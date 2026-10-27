import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/ads/ads_consent.dart';
import 'package:setkeep/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ads_consent_backend.dart';
import 'support/legal_consent_fixture.dart';
import 'support/signed_in_auth.dart';

class _SignedOut extends SignedInTestAuth {
  const _SignedOut();
  @override
  bool get isSignedIn => false;
}

void main() {
  testWidgets('onboarding and all 16+/legal confirmations precede UMP', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final backend = FakeConsent();
    final consent = AdsConsent(backend);
    await tester.pumpWidget(
      SetkeepApp(adsConsent: consent, auth: const _SignedOut()),
    );
    await tester.pumpAndSettle();
    expect(find.text('ジムと一緒にトレーニングを記録'), findsOneWidget);
    expect(backend.events, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});
    await tester.pumpWidget(
      SetkeepApp(adsConsent: consent, auth: const _SignedOut()),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('legalConsent')), findsOneWidget);
    for (final key in ['confirmTerms', 'confirmPrivacy']) {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }
    final accept = find.byKey(const Key('acceptLegalConsent'));
    expect(tester.widget<FilledButton>(accept).onPressed, isNull);
    expect(backend.events, isEmpty);
    await tester.ensureVisible(find.byKey(const Key('confirmOver16')));
    await tester.tap(find.byKey(const Key('confirmOver16')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(accept);
    await tester.tap(accept);
    await tester.pumpAndSettle();
    expect(backend.events, ['update', 'form']);
    expect(find.byKey(const Key('accountSignInButton')), findsOneWidget);
  });

  for (final showStartup in [false, true]) {
    testWidgets(
      'current policy stays accepted; UMP precedes login, startup=$showStartup',
      (tester) async {
        final saved = acceptedLegalConsentJson;
        SharedPreferences.setMockInitialValues({
          'onboarding_completed': true,
          'legal_consent': saved,
          'workout_history': '["saved"]',
          'selected_gym': '自宅',
          'favorite_exercises': '["bench_press"]',
        });
        final backend = FakeConsent()..pendingForm = Completer<void>();
        final consent = AdsConsent(backend);
        await tester.pumpWidget(
          SetkeepApp(
            showStartup: showStartup,
            adsConsent: consent,
            auth: const _SignedOut(),
          ),
        );
        await tester.pump();
        for (var frame = 0; frame < 40 && backend.events.isEmpty; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pump();
        expect(backend.events, ['update', 'form']);
        expect(find.byKey(const Key('legalConsent')), findsNothing);
        expect(find.byKey(const Key('accountSignInButton')), findsNothing);
        backend.pendingForm!.complete();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('accountSignInButton')), findsOneWidget);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('legal_consent'), saved);
        expect(prefs.getString('workout_history'), '["saved"]');
        expect(prefs.getString('favorite_exercises'), '["bench_press"]');
        expect(prefs.getString('selected_gym'), '自宅');
        expect(LegalDocuments.termsVersion, 'terms-1.2');
        expect(LegalDocuments.privacyVersion, 'privacy-1.2');
        expect(backend.events, isNot(contains('initialize')));
      },
    );
  }

  testWidgets(
    'failed UMP update preserves access to existing signed-in records',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'onboarding_completed': true,
        'legal_consent': acceptedLegalConsentJson,
        'workout_history': '[]',
        'selected_gym': '自宅',
      });
      final backend = FakeConsent()..updateFails = true;
      final consent = AdsConsent(backend);
      await tester.pumpWidget(
        SetkeepApp(adsConsent: consent, auth: const SignedInTestAuth()),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HomeShell), findsOneWidget);
      expect(await consent.ready(), isFalse);
      expect(
        (await SharedPreferences.getInstance()).getString('workout_history'),
        '[]',
      );
      expect(backend.events, isNot(contains('initialize')));
    },
  );
}
