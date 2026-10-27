import 'dart:async';

import 'package:setkeep/ads/ads_consent.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class FakeConsent implements ConsentBackend {
  final events = <String>[];
  bool allowed = true;
  bool updateFails = false;
  Object? updateError;
  bool required = true;
  ConsentStatus sdkStatus = ConsentStatus.obtained;
  ConsentStatus? afterOptionsStatus;
  bool afterOptionsAllowed = false;
  bool optionsFails = false;
  bool formFails = false;
  Completer<void>? pendingForm;
  Completer<void>? pendingUpdate;
  Completer<void>? pendingOptions;
  Completer<void>? pendingInitialization;
  Completer<bool>? pendingPrivacy;
  Completer<bool>? pendingCanRequest;
  @override
  Future<void> update() async {
    events.add('update');
    await pendingUpdate?.future;
    if (updateFails) throw updateError ?? StateError('offline');
  }

  @override
  Future<void> showRequired() async {
    events.add('form');
    if (formFails) throw StateError('form unavailable');
    await pendingForm?.future;
  }

  @override
  Future<bool> canRequest() async {
    events.add('can');
    return pendingCanRequest == null
        ? allowed
        : await pendingCanRequest!.future;
  }

  @override
  Future<ConsentStatus> status() async => sdkStatus;

  @override
  Future<bool> privacyRequired() async =>
      pendingPrivacy == null ? required : await pendingPrivacy!.future;
  @override
  Future<void> showOptions() async {
    events.add('options');
    await pendingOptions?.future;
    if (optionsFails) throw StateError('options unavailable');
    sdkStatus = afterOptionsStatus ?? sdkStatus;
    allowed = afterOptionsAllowed;
  }

  @override
  Future<void> initializeAds() async {
    events.add('initialize');
    await pendingInitialization?.future;
  }
}
