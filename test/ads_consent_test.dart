import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/ads/ads_consent.dart';
import 'package:setkeep/ads/ads_consent_startup.dart';
import 'package:flutter/material.dart';

import 'support/ads_consent_backend.dart';

import 'package:google_mobile_ads/google_mobile_ads.dart';

void main() {
  // Widget tests run in separate fake-async zones while a cold-process
  // consent singleton survives. Both mounts must finish without another update.
  final sharedBackend = FakeConsent();
  final sharedConsent = AdsConsent(sharedBackend);
  for (final mount in [1, 2]) {
    testWidgets('completed process consent enters app in async zone $mount', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AdsConsentStartup(
            consent: sharedConsent,
            child: const Text('ready after remount'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ready after remount'), findsOneWidget);
      expect(sharedBackend.events, ['update', 'form']);
    });
  }
  test('startup prepare gathers once without initializing ads', () async {
    final backend = FakeConsent();
    final consent = AdsConsent(backend);
    await Future.wait([consent.prepare(), consent.prepare()]);
    expect(backend.events, ['update', 'form']);
    expect(consent.privacyRequired, isTrue);
    expect(await consent.ready(), isTrue);
    expect(backend.events.where((e) => e == 'update').length, 1);
    expect(backend.events.where((e) => e == 'initialize').length, 1);
  });
  testWidgets(
    'startup waits for form before entering app and survives remount',
    (tester) async {
      final backend = FakeConsent()..pendingForm = Completer<void>();
      final consent = AdsConsent(backend);
      Widget app(Key key) => MaterialApp(
        home: AdsConsentStartup(
          key: key,
          consent: consent,
          child: const Text('app ready'),
        ),
      );
      await tester.pumpWidget(app(const ValueKey(1)));
      await tester.pump();
      expect(find.text('app ready'), findsNothing);
      expect(backend.events, ['update', 'form']);
      backend.pendingForm!.complete();
      await tester.pumpAndSettle();
      expect(find.text('app ready'), findsOneWidget);
      await tester.pumpWidget(app(const ValueKey(2)));
      await tester.pumpAndSettle();
      expect(backend.events.where((e) => e == 'update').length, 1);
      expect(backend.events, isNot(contains('initialize')));
    },
  );
  testWidgets('failed startup keeps app accessible and ads blocked', (
    tester,
  ) async {
    final backend = FakeConsent()..updateFails = true;
    final consent = AdsConsent(backend);
    await tester.pumpWidget(
      MaterialApp(
        home: AdsConsentStartup(
          consent: consent,
          child: const Text('records available'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('records available'), findsOneWidget);
    expect(await consent.ready(), isFalse);
    expect(backend.events, isNot(contains('initialize')));
  });
  test('fresh cold-process consent object performs its own update', () async {
    final backend = FakeConsent();
    await AdsConsent(backend).prepare();
    await AdsConsent(backend).prepare();
    expect(backend.events.where((e) => e == 'update').length, 2);
    expect(backend.events, isNot(contains('initialize')));
  });
  test(
    'concurrent callers await form, update once and initialize once',
    () async {
      final backend = FakeConsent()..pendingForm = Completer<void>();
      final consent = AdsConsent(backend);
      final first = consent.ready();
      final second = consent.ready();
      await Future<void>.delayed(Duration.zero);
      expect(backend.events, ['update', 'form']);
      backend.pendingForm!.complete();
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(backend.events.where((e) => e == 'initialize').length, 1);
      expect(backend.events.where((e) => e == 'update').length, 1);
    },
  );
  test('denied consent never initializes SDK', () async {
    final backend = FakeConsent()..allowed = false;
    expect(await AdsConsent(backend).ready(), isFalse);
    expect(backend.events, isNot(contains('initialize')));
  });
  test(
    'update failure blocks even when previous SDK permission is valid',
    () async {
      final backend = FakeConsent()
        ..updateFails = true
        ..allowed = false;
      expect(await AdsConsent(backend).ready(), isFalse);
      expect(backend.events, isNot(contains('initialize')));
      final previousValid = FakeConsent()..updateFails = true;
      expect(await AdsConsent(previousValid).ready(), isFalse);
      expect(previousValid.events, isNot(contains('initialize')));
    },
  );
  test('privacy change invalidates ads and rechecks permission', () async {
    final backend = FakeConsent();
    final consent = AdsConsent(backend);
    expect(await consent.ready(), isTrue);
    final observed = <bool>[];
    consent.addListener(() => observed.add(consent.optionsOpen));
    await consent.showOptions();
    expect(observed, [true, false]);
    expect(consent.revision, 2);
    expect(await consent.ready(), isFalse);
  });
  for (final updateFails in [false, true]) {
    test('unknown + SDK true is blocked, updateFails=$updateFails', () async {
      final backend = FakeConsent()
        ..sdkStatus = ConsentStatus.unknown
        ..updateFails = updateFails;
      final consent = AdsConsent(backend);
      expect(await consent.ready(), isFalse);
      expect(consent.updateFailed, updateFails);
      expect(backend.events, isNot(contains('initialize')));
    });
  }
  test(
    'observed unconfigured app error 4 + unknown + SDK true is blocked',
    () async {
      final backend = FakeConsent()
        ..updateFails = true
        ..updateError = FormError(errorCode: 4, message: 'No forms configured')
        ..sdkStatus = ConsentStatus.unknown;
      expect(await AdsConsent(backend).ready(), isFalse);
      expect(backend.events, isNot(contains('initialize')));
    },
  );
  for (final state in [ConsentStatus.obtained, ConsentStatus.notRequired]) {
    test('valid prior SDK $state cannot bypass update error', () async {
      final backend = FakeConsent()
        ..sdkStatus = state
        ..updateFails = true;
      final consent = AdsConsent(backend);
      expect(await consent.ready(), isFalse);
      expect(consent.updateFailed, isTrue);
      expect(backend.events, isNot(contains('form')));
      expect(backend.events, isNot(contains('initialize')));
      // Repeated/concurrent callers and late SDK permission changes stay shut.
      backend.updateFails = false;
      expect(await Future.wait([consent.ready(), consent.ready()]), [
        false,
        false,
      ]);
      expect(backend.events.where((e) => e == 'update').length, 1);
      expect(backend.events, isNot(contains('initialize')));
    });
    test('successful update and form permit SDK $state', () async {
      final backend = FakeConsent()..sdkStatus = state;
      expect(await AdsConsent(backend).ready(), isTrue);
      expect(backend.events.where((e) => e == 'initialize').length, 1);
    });
    test('valid prior SDK $state cannot bypass form error', () async {
      final backend = FakeConsent()
        ..sdkStatus = state
        ..formFails = true;
      final consent = AdsConsent(backend);
      expect(await consent.ready(), isFalse);
      expect(consent.formFailed, isTrue);
      backend.formFails = false;
      expect(await consent.ready(), isFalse);
      expect(backend.events, isNot(contains('initialize')));
      // Only a fresh session that actually succeeds may recover.
      expect(await AdsConsent(backend).ready(), isTrue);
    });
    test('$state never overrides SDK false', () async {
      final backend = FakeConsent()
        ..sdkStatus = state
        ..allowed = false;
      expect(await AdsConsent(backend).ready(), isFalse);
      expect(backend.events, isNot(contains('initialize')));
    });
  }
  test('required choice never initializes even if SDK returns true', () async {
    final backend = FakeConsent()..sdkStatus = ConsentStatus.required;
    expect(await AdsConsent(backend).ready(), isFalse);
    expect(backend.events, isNot(contains('initialize')));
  });
  test('normal non-required region allows without a privacy entry', () async {
    final backend = FakeConsent()
      ..sdkStatus = ConsentStatus.notRequired
      ..required = false;
    final consent = AdsConsent(backend);
    expect(await consent.ready(), isTrue);
    expect(consent.privacyRequired, isFalse);
  });
  test(
    'completed refusal follows SDK permission, not a synthetic reject enum',
    () async {
      final backend = FakeConsent()..sdkStatus = ConsentStatus.obtained;
      final consent = AdsConsent(backend);
      expect(await consent.ready(), isTrue);
      // UMP may permit limited ads after a completed refusal. NPA stays enabled
      // in ad requests; obtained does not mean all purposes were accepted.
      backend.afterOptionsAllowed = true;
      await consent.showOptions();
      expect(await consent.ready(), isTrue);
      backend.afterOptionsAllowed = false;
      await consent.showOptions();
      expect(await consent.ready(), isFalse);
      expect(backend.events.where((e) => e == 'initialize').length, 1);
    },
  );
  test('withdrawal to unknown blocks a contradictory SDK true', () async {
    final backend = FakeConsent();
    final consent = AdsConsent(backend);
    expect(await consent.ready(), isTrue);
    backend
      ..afterOptionsStatus = ConsentStatus.unknown
      ..afterOptionsAllowed = true;
    await consent.showOptions();
    expect(await consent.ready(), isFalse);
  });
  test('privacy failure blocks ads until a successful options retry', () async {
    final backend = FakeConsent();
    final consent = AdsConsent(backend);
    expect(await consent.ready(), isTrue);
    backend.optionsFails = true;
    await expectLater(consent.showOptions(), throwsStateError);
    expect(consent.optionsOpen, isFalse);
    expect(await consent.ready(), isFalse);
    backend
      ..optionsFails = false
      ..afterOptionsAllowed = true;
    await consent.showOptions();
    expect(await consent.ready(), isTrue);
  });
  test('form error with required state blocks ads', () async {
    final backend = FakeConsent()
      ..formFails = true
      ..sdkStatus = ConsentStatus.required;
    final consent = AdsConsent(backend);
    expect(await consent.ready(), isFalse);
    expect(consent.formFailed, isTrue);
    expect(backend.events, isNot(contains('initialize')));
  });
  test('form error blocks a valid previous SDK choice', () async {
    final backend = FakeConsent()..formFails = true;
    final consent = AdsConsent(backend);
    expect(await consent.ready(), isFalse);
    expect(consent.formFailed, isTrue);
    expect(backend.events, isNot(contains('initialize')));
  });

  testWidgets(
    'timed-out update stays blocked after a late successful callback',
    (tester) async {
      final backend = FakeConsent()..pendingUpdate = Completer<void>();
      final consent = AdsConsent(backend);
      final result = consent.ready();
      await tester.pump(AdsConsent.nonInteractiveTimeout);
      expect(await result, isFalse);
      backend.pendingUpdate!.complete();
      await tester.pump();
      expect(await consent.ready(), isFalse);
      expect(backend.events.where((e) => e == 'update'), hasLength(1));
      expect(backend.events, isNot(contains('initialize')));
    },
  );

  testWidgets(
    'privacy status timeout unblocks navigation but stops session ads',
    (tester) async {
      final backend = FakeConsent()..pendingPrivacy = Completer<bool>();
      final consent = AdsConsent(backend);
      await tester.pumpWidget(
        MaterialApp(
          home: AdsConsentStartup(
            consent: consent,
            child: const Text('local records'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(AdsConsent.nonInteractiveTimeout);
      await tester.pumpAndSettle();
      expect(find.text('local records'), findsOneWidget);
      expect(await consent.ready(), isFalse);
      expect(backend.events, isNot(contains('initialize')));
      backend.pendingPrivacy!.complete(true);
      await tester.pump();
      expect(await consent.ready(), isFalse);
    },
  );

  testWidgets(
    'interactive consent is not abandoned after the SDK query timeout',
    (tester) async {
      final backend = FakeConsent()..pendingForm = Completer<void>();
      final consent = AdsConsent(backend);
      await tester.pumpWidget(
        MaterialApp(
          home: AdsConsentStartup(
            consent: consent,
            child: const Text('account gate'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('account gate'), findsNothing);
      expect(backend.events.where((e) => e == 'update'), hasLength(1));
      backend.pendingForm!.complete();
      await tester.pumpAndSettle();
      expect(find.text('account gate'), findsOneWidget);
    },
  );

  test(
    'a stale eligibility answer cannot initialize ads across a privacy change',
    () async {
      final answer = Completer<bool>();
      final backend = FakeConsent()..pendingCanRequest = answer;
      final consent = AdsConsent(backend);
      final first = consent.ready();
      await Future<void>.delayed(Duration.zero);
      expect(backend.events, contains('can'));
      backend.afterOptionsAllowed = false;
      await consent.showOptions();
      answer.complete(true);
      expect(await first, isFalse);
      expect(backend.events, isNot(contains('initialize')));
      backend.pendingCanRequest = null;
      expect(await consent.ready(), isFalse);
    },
  );

  test('duplicate privacy taps open one native form', () async {
    final backend = FakeConsent()..pendingOptions = Completer<void>();
    final consent = AdsConsent(backend);
    await consent.prepare();
    final first = consent.showOptions();
    await consent.showOptions();
    expect(backend.events.where((e) => e == 'options'), hasLength(1));
    expect(await consent.ready(), isFalse);
    backend.pendingOptions!.complete();
    await first;
    expect(consent.optionsOpen, isFalse);
  });
}
