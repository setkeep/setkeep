import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ads_config.dart';

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
      await MobileAds.instance.initialize().timeout(
        const Duration(seconds: 10),
      );
      await MobileAds.instance.setAppMuted(true);
      final result = Completer<InterstitialHandle?>();
      var expired = false;
      InterstitialAd.load(
        adUnitId: unitId,
        request: const AdRequest(nonPersonalizedAds: true),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            if (expired || result.isCompleted) {
              unawaited(ad.dispose().catchError((Object _) {}));
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
  ) {
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _entitlement.addListener(_onEntitlement);
    WidgetsBinding.instance.addObserver(this);
  }

  static const loadWaitBeforeNavigation = Duration(seconds: 1);

  final AdsEntitlement _entitlement;
  final InterstitialBackend _backend;
  final String _unitId;
  final SharedPreferences _preferences;
  final WorkoutInterstitialPolicy _policy;
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
  }) async {
    final id = config.interstitialId(platform);
    final resolvedBackend = backend ?? GoogleInterstitialBackend.instance;
    if (id == null || entitlement.adFree || !resolvedBackend.supported) {
      return null;
    }
    final prefs = preferences ?? await SharedPreferences.getInstance();
    if (!await policy.canShow(prefs)) return null;
    final session = WorkoutInterstitialSession._(
      entitlement,
      resolvedBackend,
      id,
      prefs,
      policy,
    );
    session.preload();
    return session;
  }

  void preload() {
    if (_disposed || _attempted || _entitlement.adFree || !_foreground) return;
    // Native ads expire; a long workout must not retain a stale preload.
    if (_loadedAt != null &&
        DateTime.now().difference(_loadedAt!) >= const Duration(minutes: 55)) {
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
          !_foreground ||
          generation != _loadGeneration) {
        ad?.dispose();
        return null;
      }
      _ad = ad;
      _loadedAt = ad == null ? null : DateTime.now();
      if (ad == null) _loadFuture = null;
      return ad;
    } catch (_) {
      if (generation == _loadGeneration) _loadFuture = null;
      return null;
    }
  }

  Future<void> tryShow() async {
    if (_attempted || _disposed) return;
    _attempted = true;
    if (_entitlement.adFree || !_foreground) return;
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
    if (ad == null || _disposed || _entitlement.adFree || !_foreground) {
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
    WidgetsBinding.instance.removeObserver(this);
    _ad?.dispose();
    _ad = null;
  }
}
