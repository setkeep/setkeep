import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/signed_in_auth.dart';

void main() {
  testWidgets(
    'mutual sharing consent needs explicit reacceptance without erasing saved records',
    (tester) async {
      const savedHistory = '["saved"]';
      SharedPreferences.setMockInitialValues({
        'onboarding_completed': true,
        'workout_history': savedHistory,
        'selected_gym': '自宅',
        'legal_consent': jsonEncode({
          'accepted': true,
          'over16': true,
          'acceptedAt': '2026-10-05T00:00:00.000Z',
          'termsVersion': 'terms-1.1',
          'privacyVersion': 'privacy-1.1',
        }),
      });
      await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('legalConsent')), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(await LegalConsentPreference.load(), isFalse);
      expect(prefs.getString('workout_history'), savedHistory);

      for (final key in ['openTerms', 'openPrivacy']) {
        await tester.ensureVisible(find.byKey(Key(key)));
        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();
        final document = key == 'openTerms'
            ? LegalDocuments.terms
            : LegalDocuments.privacy;
        expect(find.text(document), findsOneWidget);
        expect(document, contains('BOREDOTA'));
        expect(document, isNot(contains('[運営者')));
        if (key == 'openPrivacy') {
          expect(document, contains('対応完了から30日以内に削除'));
          expect(document, contains('すべてのコピーが退会から30日以内に完全消去されることは保証しません'));
        }
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
      }
      final accept = find.byKey(const Key('acceptLegalConsent'));
      await tester.ensureVisible(accept);
      expect(tester.widget<FilledButton>(accept).onPressed, isNull);
      for (final key in ['confirmOver16', 'confirmTerms', 'confirmPrivacy']) {
        await tester.ensureVisible(find.byKey(Key(key)));
        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(accept);
      await tester.tap(accept);
      await tester.pumpAndSettle();

      expect(find.byType(HomeShell), findsOneWidget);
      expect(await LegalConsentPreference.load(), isTrue);
      final consent = jsonDecode(prefs.getString('legal_consent')!) as Map;
      expect(consent['termsVersion'], 'terms-1.2');
      expect(consent['privacyVersion'], 'privacy-1.2');
      expect(prefs.getString('workout_history'), savedHistory);
      expect(prefs.getString('selected_gym'), '自宅');
      expect(prefs.getBool('onboarding_completed'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
