import 'package:flutter/material.dart';

import 'ads_config.dart';
import 'ads_consent.dart';
import 'banner_backend.dart';
import 'workout_interstitial.dart';

/// No scope means no ads. Only SetkeepApp installs an enabled scope; TRAINER
/// never opts in, even though it imports other components from this package.
class AdsScope extends InheritedWidget {
  const AdsScope({
    super.key,
    required this.config,
    required this.entitlement,
    required super.child,
    this.backend,
    this.interstitialBackend,
  });
  final AdsConfig config;
  final AdsEntitlement entitlement;
  final BannerBackend? backend;
  final InterstitialBackend? interstitialBackend;
  static AdsScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AdsScope>();
  @override
  bool updateShouldNotify(AdsScope oldWidget) =>
      config != oldWidget.config ||
      entitlement != oldWidget.entitlement ||
      backend != oldWidget.backend ||
      interstitialBackend != oldWidget.interstitialBackend;
}

class SetkeepBannerAd extends StatefulWidget {
  const SetkeepBannerAd({super.key, this.consent});
  final AdsConsent? consent;
  @override
  State<SetkeepBannerAd> createState() => _SetkeepBannerAdState();
}

class _SetkeepBannerAdState extends State<SetkeepBannerAd>
    with WidgetsBindingObserver {
  late AdsConsent _consent;
  bool _foreground = true;
  int _lifecycleRevision = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _consent = widget.consent ?? AdsConsent.instance;
    _consent.addListener(_onConsent);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) {
      setState(() {
        _foreground = state == AppLifecycleState.resumed;
        _lifecycleRevision++;
      });
    }
  }

  @override
  void didUpdateWidget(SetkeepBannerAd oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.consent ?? AdsConsent.instance;
    if (!identical(next, _consent)) {
      _consent.removeListener(_onConsent);
      _consent = next;
      _consent.addListener(_onConsent);
      _lifecycleRevision++;
    }
  }

  void _onConsent() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _consent.removeListener(_onConsent);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AdsScope.of(context);
    final platform = Theme.of(context).platform;
    final id = scope?.config.bannerId(platform);
    final backend = scope?.backend ?? GoogleBannerBackend.instance;
    if (_consent.requestsBlocked ||
        scope == null ||
        id == null ||
        !backend.supported ||
        !_foreground ||
        !(ModalRoute.isCurrentOf(context) ?? true)) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<bool>(
      valueListenable: scope.entitlement,
      builder: (context, adFree, _) {
        if (adFree) return const SizedBox.shrink();
        return SafeArea(
          top: false,
          bottom:
              false, // Home's existing NavigationBar owns bottom system inset.
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (!constraints.maxWidth.isFinite) {
                return const SizedBox.shrink();
              }
              final width = constraints.maxWidth.floor();
              if (width < 1) {
                return const SizedBox.shrink();
              }
              return _BannerSlot(
                key: ValueKey((
                  width,
                  _consent.revision,
                  _lifecycleRevision,
                  MediaQuery.orientationOf(context),
                  backend,
                  id,
                  scope.entitlement,
                )),
                width: width,
                unitId: id,
                entitlement: scope.entitlement,
                backend: backend,
              );
            },
          ),
        );
      },
    );
  }
}

class _BannerSlot extends StatefulWidget {
  const _BannerSlot({
    super.key,
    required this.width,
    required this.unitId,
    required this.backend,
    required this.entitlement,
  });
  final int width;
  final String unitId;
  final BannerBackend backend;
  final AdsEntitlement entitlement;
  @override
  State<_BannerSlot> createState() => _BannerSlotState();
}

class _BannerSlotState extends State<_BannerSlot> with WidgetsBindingObserver {
  final _request = BannerRequest();
  BannerHandle? _ad;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.entitlement.addListener(_cancelWhenAdFree);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _request.cancel();
  }

  void _cancelWhenAdFree() {
    if (widget.entitlement.adFree) _request.cancel();
  }

  Future<void> _load() async {
    try {
      final ad = await widget.backend.load(
        widget.width,
        widget.unitId,
        _request,
      );
      if (!mounted || _request.cancelled) {
        ad?.dispose();
        return;
      }
      ad?.onUnavailable = () {
        if (mounted) setState(() => _ad = null);
        ad.dispose();
      };
      setState(() => _ad = ad);
    } catch (_) {
      // Ads never prevent HOME or workout use. No retry loop.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.entitlement.removeListener(_cancelWhenAdFree);
    _ad?.onUnavailable = null;
    _request.cancel();
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: SizedBox(
          width: ad.size.width,
          height: ad.size.height,
          child: ad.build(),
        ),
      ),
    );
  }
}
