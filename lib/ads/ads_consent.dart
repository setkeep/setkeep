import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

abstract class ConsentBackend {
  Future<void> update();
  Future<void> showRequired();
  Future<bool> canRequest();
  Future<ConsentStatus> status();
  Future<bool> privacyRequired();
  Future<void> showOptions();
  Future<void> initializeAds();
}

class GoogleConsentBackend implements ConsentBackend {
  bool get _supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  @override
  Future<void> update() {
    if (!_supported) {
      return Future.error(UnsupportedError('Ads consent is mobile only'));
    }
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(tagForUnderAgeOfConsent: false),
      () {
        if (!done.isCompleted) done.complete();
      },
      (error) {
        if (!done.isCompleted) done.completeError(error);
      },
    );
    return done.future;
  }

  @override
  Future<void> showRequired() =>
      ConsentForm.loadAndShowConsentFormIfRequired((error) {
        if (error != null) throw error;
      });
  @override
  Future<bool> canRequest() => ConsentInformation.instance.canRequestAds();
  @override
  Future<ConsentStatus> status() =>
      ConsentInformation.instance.getConsentStatus();
  @override
  Future<bool> privacyRequired() async =>
      _supported &&
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
  @override
  Future<void> showOptions() => ConsentForm.showPrivacyOptionsForm((error) {
    if (error != null) throw StateError('privacy options unavailable');
  });
  @override
  Future<void> initializeAds() async {
    await MobileAds.instance.initialize();
    await MobileAds.instance.setAppMuted(true);
  }
}

/// One update per cold process after SETKEEP's existing 16+ and legal gate.
/// Startup gathers consent without initializing/loading ads. No cached shortcut.
class AdsConsent extends ChangeNotifier {
  AdsConsent(this.backend);
  static final instance = AdsConsent(GoogleConsentBackend());
  final ConsentBackend backend;
  Future<void>? _session;
  bool _prepared = false;
  Future<void>? _initialization;
  bool privacyRequired = false;
  bool optionsOpen = false;
  int revision = 0;
  bool updateFailed = false;
  bool formFailed = false;
  bool _privacyChangeFailed = false;
  bool _privacyStatusFailed = false;
  static const nonInteractiveTimeout = Duration(seconds: 10);

  bool get requestsBlocked =>
      optionsOpen ||
      updateFailed ||
      formFailed ||
      _privacyChangeFailed ||
      _privacyStatusFailed;

  Future<void> prepare() {
    // Re-entry needs the completed state, not a Future tied to the first
    // caller's async zone. Pending callers still share exactly one update.
    if (_prepared) return Future<void>.value();
    return _session ??= _gather();
  }

  Future<void> _gather() async {
    try {
      await backend.update().timeout(const Duration(seconds: 10));
    } catch (_) {
      updateFailed = true;
    }
    if (!updateFailed) {
      // Do not time out an interactive form: late completion must never overlap
      // another consent request. Ad callers impose their own wait bounds.
      try {
        await backend.showRequired();
      } catch (_) {
        formFailed = true;
      }
    }
    try {
      privacyRequired = await backend.privacyRequired().timeout(
        nonInteractiveTimeout,
      );
      _privacyStatusFailed = false;
    } catch (_) {
      _privacyStatusFailed = true;
    }
    _prepared = true;
    notifyListeners();
  }

  Future<bool> _allowed() async {
    // A failed update/form must not fall back to a previous SDK permission.
    // Keep this process blocked even if a late callback updates SDK state.
    final currentRevision = revision;
    if (requestsBlocked) {
      return false;
    }
    // Read only UMP's current state, after this session's update attempt.
    // A region requiring no consent and a completed choice (including refusal)
    // are distinct from unknown/required. UMP still decides ad eligibility.
    final status = await backend.status().timeout(nonInteractiveTimeout);
    if (status != ConsentStatus.obtained &&
        status != ConsentStatus.notRequired) {
      return false;
    }
    final permitted = await backend.canRequest().timeout(nonInteractiveTimeout);
    return permitted && !requestsBlocked && currentRevision == revision;
  }

  Future<bool> ready() async {
    if (optionsOpen) return false;
    try {
      await prepare();
      // Require a successful update/form path and the SDK's current permission.
      // Unknown + canRequest=true must never initialize ads either.
      final currentRevision = revision;
      if (!await _allowed() || currentRevision != revision || requestsBlocked) {
        return false;
      }
      await (_initialization ??= backend.initializeAds().timeout(
        nonInteractiveTimeout,
      ));
      return currentRevision == revision && await _allowed();
    } catch (_) {
      return false;
    }
  }

  Future<void> showOptions() async {
    if (optionsOpen || !privacyRequired) return;
    optionsOpen = true;
    revision++;
    notifyListeners(); // Dispose visible/preloaded ads before changing consent.
    try {
      await backend.showOptions();
      _privacyChangeFailed = false;
    } catch (_) {
      // Do not resume ads after an indeterminate privacy-change attempt.
      // A successful retry or a fresh session can establish SDK state again.
      _privacyChangeFailed = true;
      rethrow;
    } finally {
      try {
        privacyRequired = await backend.privacyRequired().timeout(
          nonInteractiveTimeout,
        );
        _privacyStatusFailed = false;
      } catch (_) {
        _privacyStatusFailed = true;
      }
      optionsOpen = false;
      revision++;
      notifyListeners();
    }
  }
}
