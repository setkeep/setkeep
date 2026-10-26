import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/main.dart';
import 'package:setkeep/services/account_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/legal_consent_fixture.dart';

class _Auth implements AccountAuthService {
  final _events = StreamController<void>.broadcast();
  bool _signedIn = false;
  String? _email;
  int googleStarts = 0;

  @override
  bool get isSignedIn => _signedIn;
  @override
  String? get email => _email;
  @override
  Stream<void> get changes => _events.stream;

  void completeSignIn([String email = 'member@example.com']) {
    _signedIn = true;
    _email = email;
    _events.add(null);
  }

  void failRefresh() => _events.addError(StateError('offline'));

  @override
  Future<void> signIn(String email, String password) async {
    completeSignIn(email);
  }

  @override
  Future<bool> signUp(String email, String password) async {
    completeSignIn(email);
    return true;
  }

  @override
  Future<void> signInWithGoogle() async {
    googleStarts++;
  }

  @override
  Future<void> signOut() async {
    _signedIn = false;
    _email = null;
    _events.add(null);
  }

  @override
  Future<void> deleteAccount() => signOut();

  Future<void> close() => _events.close();
}

void main() {
  testWidgets(
    'first use requires onboarding, consent and sign-in before Home',
    (tester) async {
      SharedPreferences.setMockInitialValues({'workout_history': '["saved"]'});
      final auth = _Auth();
      addTearDown(auth.close);
      await tester.pumpWidget(SetkeepApp(auth: auth));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('onboarding')), findsOneWidget);
      for (var page = 1; page < 4; page++) {
        await tester.tap(find.byKey(const Key('onboardingNext')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('はじめる'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('legalConsent')), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
      for (final key in ['confirmOver16', 'confirmTerms', 'confirmPrivacy']) {
        await tester.ensureVisible(find.byKey(Key(key)));
        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.byKey(const Key('acceptLegalConsent')));
      await tester.tap(find.byKey(const Key('acceptLegalConsent')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('requiredAccountPage')), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
      expect(
        find.byKey(const Key('accountGoogleSignInButton')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('accountGoogleSignInButton')));
      await tester.pumpAndSettle();
      expect(auth.googleStarts, 1);
      expect(find.byType(HomeShell), findsNothing);
      auth.completeSignIn();
      await tester.pumpAndSettle();
      expect(find.byType(HomeShell), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getString('workout_history'),
        '["saved"]',
      );
    },
  );

  testWidgets('existing session returns to Home; sign-out closes its routes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'onboarding_completed': true,
      'legal_consent': acceptedLegalConsentJson,
    });
    final auth = _Auth()..completeSignIn();
    addTearDown(auth.close);
    await tester.pumpWidget(SetkeepApp(auth: auth));
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byKey(const Key('requiredAccountPage')), findsNothing);
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => CloudAccountPage(
          historyCount: 0,
          auth: auth,
          onSyncRequested: () async => 0,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('accountSignOutButton')));
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsNothing);
    expect(find.byKey(const Key('requiredAccountPage')), findsOneWidget);
    expect(navigator.canPop(), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(SetkeepApp(auth: auth));
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsNothing);
    await tester.enterText(
      find.byKey(const Key('accountEmailField')),
      'member@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('accountPasswordField')),
      'password123',
    );
    await tester.tap(find.byKey(const Key('accountSignInButton')));
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(SetkeepApp(auth: auth));
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);
  });

  testWidgets('missing Supabase configuration never enables guest use', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'onboarding_completed': true,
      'legal_consent': acceptedLegalConsentJson,
    });
    await tester.pumpWidget(const SetkeepApp());
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsNothing);
    expect(find.text('現在アカウント機能を利用できません'), findsOneWidget);
  });

  testWidgets('production startup restores a session before showing Home', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'onboarding_completed': true,
      'legal_consent': acceptedLegalConsentJson,
    });
    final auth = _Auth()..completeSignIn();
    addTearDown(auth.close);
    await tester.pumpWidget(SetkeepApp(showStartup: true, auth: auth));
    expect(find.byType(HomeShell), findsNothing);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byKey(const Key('requiredAccountPage')), findsNothing);
  });

  testWidgets('production startup without a session opens the account page', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'onboarding_completed': true,
      'legal_consent': acceptedLegalConsentJson,
    });
    final auth = _Auth();
    addTearDown(auth.close);
    await tester.pumpWidget(SetkeepApp(showStartup: true, auth: auth));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsNothing);
    expect(find.byKey(const Key('requiredAccountPage')), findsOneWidget);
  });

  testWidgets('a refresh error does not hide local data for a signed-in user', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'onboarding_completed': true,
      'legal_consent': acceptedLegalConsentJson,
      'workout_history': '["saved"]',
    });
    final auth = _Auth()..completeSignIn();
    addTearDown(auth.close);
    await tester.pumpWidget(SetkeepApp(auth: auth));
    await tester.pumpAndSettle();
    auth.failRefresh();
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);
    expect(
      (await SharedPreferences.getInstance()).getString('workout_history'),
      '["saved"]',
    );
  });

  testWidgets('old consent requires acceptance again before authentication', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'onboarding_completed': true,
      'legal_consent': '{"accepted":true,"over16":true,"acceptedAt":"2026-09-01T00:00:00Z","termsVersion":"provisional-1","privacyVersion":"provisional-1"}',
    });
    final auth = _Auth()..completeSignIn();
    addTearDown(auth.close);
    await tester.pumpWidget(SetkeepApp(auth: auth));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('legalConsent')), findsOneWidget);
    expect(find.byType(HomeShell), findsNothing);
  });
}
