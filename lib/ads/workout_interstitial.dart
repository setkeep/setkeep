import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ads_config.dart';
import 'ads_consent.dart';

/// Interstitial frequency is based on an actual display in the local calendar
/// day. The former completed-workout counter is intentionally ignored.
class WorkoutInterstitialPolicy {
  const WorkoutInterstitialPolicy([this._now]);

  static const lastShownLocalDateKey =
      'ads_last_interstitial_shown_local_date_v1';
  final DateTime Function()? _now;

  DateTime get _localNow => (_now?.call() ?? DateTime.now()).toLocal();

  String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Future<bool> canShow(SharedPreferences prefs) async =>
      prefs.getString(lastShownLocalDateKey) != _dateKey(_localNow);

  Future<bool> recordShown(SharedPreferences prefs) =>
      prefs.setString(lastShownLocalDateKey, _dateKey(_localNow));
}

abstract class InterstitialHandle {
  /// Returns true only after the SDK reports full-screen content was shown.
  Future<bool> show({required Future<void> Function() onShown});
  void dispose();
}

abstract class InterstitialBackend {
  bool get supported;
  Future<InterstitialHandle?> load(String unitId);
}

class GoogleInterstitialBackend implements InterstitialBackend {
  static final instance = GoogleInterstitialBackend();

  @override
  bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  Future<InterstitialHandle?> load(String unitId) async {
    if (!supported) return null;
    try {
      final consentRevision = AdsConsent.instance.revision;
      if (!await AdsConsent.instance.ready().timeout(
            const Duration(seconds: 12),
            onTimeout: () => false,
          ) ||
          AdsConsent.instance.requestsBlocked ||
          AdsConsent.instance.revision != consentRevision) {
        return null;
      }
      final result = Completer<InterstitialHandle?>();
      var expired = false;
      InterstitialAd.load(
        adUnitId: unitId,
        request: const AdRequest(nonPersonalizedAds: true),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            if (expired ||
                result.isCompleted ||
                AdsConsent.instance.requestsBlocked ||
                AdsConsent.instance.revision != consentRevision) {
              unawaited(ad.dispose().catchError((Object _) {}));
              if (!result.isCompleted) result.complete(null);
            } else {
              result.complete(_GoogleInterstitialHandle(ad));
            }
          },
          onAdFailedToLoad: (error) {
            if (kDebugMode) {
              debugPrint('Test interstitial unavailable (${error.code})');
            }
            if (!expired && !result.isCompleted) result.complete(null);
          },
        ),
      );
      return await result.future.timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          expired = true;
          return null;
        },
      );
    } catch (_) {
      return null;
    }
  }
}

class _GoogleInterstitialHandle implements InterstitialHandle {
  _GoogleInterstitialHandle(this._ad);
  final InterstitialAd _ad;
  bool _disposed = false;

  @override
  Future<bool> show({required Future<void> Function() onShown}) async {
    final consentRevision = AdsConsent.instance.revision;
    if (_disposed ||
        !await AdsConsent.instance.ready() ||
        _disposed ||
        AdsConsent.instance.requestsBlocked ||
        AdsConsent.instance.revision != consentRevision) {
      dispose();
      return false;
    }
    final finished = Completer<bool>();
    var shown = false;
    Future<void>? recording;
    Future<void> finish(bool value) async {
      if (finished.isCompleted) return;
      if (value) await recording;
      finished.complete(value);
    }

    _ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdShowedFullScreenContent: (_) {
        shown = true;
        recording = onShown();
      },
      onAdDismissedFullScreenContent: (_) => unawaited(finish(shown)),
      onAdFailedToShowFullScreenContent: (_, error) => unawaited(finish(false)),
    );
    try {
      await _ad.show();
      return await finished.future;
    } catch (_) {
      return false;
    } finally {
      dispose();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_ad.dispose().catchError((Object _) {}));
  }
}

/// One instance is passed from the completed workout to its share page.
/// It can attempt display only once, even if save and Back race each other.
class WorkoutInterstitialSession with WidgetsBindingObserver {
  WorkoutInterstitialSession._(
    this._entitlement,
    this._backend,
    this._unitId,
    this._preferences,
    this._policy,
    this._consent,
    this._now,
  ) {
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _entitlement.addListener(_onEntitlement);
    _consent.addListener(_onConsent);
    WidgetsBinding.instance.addObserver(this);
  }

  static const loadWaitBeforeNavigation = Duration(seconds: 1);
  static const maxPreloadAge = Duration(minutes: 55);

  final AdsEntitlement _entitlement;
  final InterstitialBackend _backend;
  final String _unitId;
  final SharedPreferences _preferences;
  final WorkoutInterstitialPolicy _policy;
  final AdsConsent _consent;
  final DateTime Function() _now;
  InterstitialHandle? _ad;
  Future<InterstitialHandle?>? _loadFuture;
  bool _disposed = false;
  bool _foreground = true;
  bool _attempted = false;
  int _loadGeneration = 0;
  DateTime? _loadedAt;
  bool get attempted => _attempted;

  static Future<WorkoutInterstitialSession?> prepareForWorkoutCompletion({
    required AdsConfig config,
    required AdsEntitlement entitlement,
    required TargetPlatform platform,
    InterstitialBackend? backend,
    SharedPreferences? preferences,
    WorkoutInterstitialPolicy policy = const WorkoutInterstitialPolicy(),
    AdsConsent? consent,
    DateTime Function()? now,
  }) async {
    final id = config.interstitialId(platform);
    final resolvedBackend = backend ?? GoogleInterstitialBackend.instance;
    if (id == null || entitlement.adFree || !resolvedBackend.supported) {
      return null;
    }
    final prefs = preferences ?? await SharedPreferences.getInstance();
    if (!await policy.canShow(prefs)) {
      return null;
    }
    final session = WorkoutInterstitialSession._(
      entitlement,
      resolvedBackend,
      id,
      prefs,
      policy,
      consent ?? AdsConsent.instance,
      now ?? DateTime.now,
    );
    session.preload();
    return session;
  }

  void preload() {
    if (_disposed ||
        _attempted ||
        _entitlement.adFree ||
        !_foreground ||
        _consent.requestsBlocked) {
      return;
    }
    // Native ads expire; a long workout must not retain a stale preload.
    if (_loadedAt != null && _now().difference(_loadedAt!) >= maxPreloadAge) {
      _discardPreload();
    }
    _loadFuture ??= _load(++_loadGeneration);
  }

  void _discardPreload() {
    _loadGeneration++;
    _ad?.dispose();
    _ad = null;
    _loadedAt = null;
    _loadFuture = null;
  }

  Future<InterstitialHandle?> _load(int generation) async {
    try {
      final ad = await _backend.load(_unitId);
      if (_disposed ||
          _entitlement.adFree ||
          _consent.requestsBlocked ||
          !_foreground ||
          generation != _loadGeneration) {
        ad?.dispose();
        return null;
      }
      _ad = ad;
      _loadedAt = ad == null ? null : _now();
      if (ad == null) _loadFuture = null;
      return ad;
    } catch (_) {
      if (generation == _loadGeneration) _loadFuture = null;
      return null;
    }
  }

  Future<void> tryShow() async {
    if (_attempted || _disposed) return;
    if (_loadedAt != null && _now().difference(_loadedAt!) >= maxPreloadAge) {
      _discardPreload();
      preload();
    }
    _attempted = true;
    if (_entitlement.adFree || !_foreground || _consent.requestsBlocked) return;
    if (!await _policy.canShow(_preferences)) return;

    var ad = _ad;
    if (ad == null) {
      final loading = _loadFuture;
      if (loading != null) {
        try {
          ad = await loading.timeout(
            loadWaitBeforeNavigation,
            onTimeout: () => null,
          );
        } catch (_) {
          ad = null;
        }
      }
    }
    if (ad == null ||
        _disposed ||
        _entitlement.adFree ||
        !_foreground ||
        _consent.requestsBlocked) {
      ad?.dispose();
      final loading = _loadFuture;
      if (ad == null && loading != null) {
        unawaited(
          loading
              .then((lateAd) {
                if (identical(_ad, lateAd)) _ad = null;
                lateAd?.dispose();
              })
              .catchError((Object _) {}),
        );
      }
      return;
    }
    if (identical(_ad, ad)) _ad = null;
    try {
      await ad
          .show(
            onShown: () async {
              try {
                await _policy.recordShown(_preferences);
              } catch (_) {
                // A local preference failure must not block ad dismissal.
              }
            },
          )
          .timeout(const Duration(seconds: 30), onTimeout: () => false);
    } catch (_) {
      // A failed/missing native callback must not trap the user on this page.
    } finally {
      ad.dispose();
    }
  }

  void _onConsent() {
    if (_consent.requestsBlocked) {
      _discardPreload();
    } else {
      preload();
    }
  }

  void _onEntitlement() {
    if (_entitlement.adFree) {
      _discardPreload();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _discardPreload();
    } else if (!_attempted && !_disposed) {
      preload();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _entitlement.removeListener(_onEntitlement);
    _consent.removeListener(_onConsent);
    WidgetsBinding.instance.removeObserver(this);
    _ad?.dispose();
    _ad = null;
  }
}
