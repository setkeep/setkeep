import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/main.dart';
import 'package:setkeep/services/account_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/legal_consent_fixture.dart';

class _RegistrationAuth implements AccountAuthService {
  final events = StreamController<void>.broadcast();
  @override
  bool isSignedIn = false;
  @override
  String? email;
  @override
  Stream<void> get changes => events.stream;

  int registrations = 0;
  int logins = 0;
  int googleStarts = 0;
  String? submittedEmail;
  String? submittedPassword;
  Completer<bool>? request;
  Object? failure;
  bool immediateSession = false;

  void verified() {
    isSignedIn = true;
    email = submittedEmail ?? 'member@example.com';
    events.add(null);
  }

  @override
  Future<bool> signUp(String email, String password) async {
    registrations++;
    submittedEmail = email;
    submittedPassword = password;
    if (failure != null) throw failure!;
    if (request != null) return request!.future;
    if (immediateSession) verified();
    return immediateSession;
  }

  @override
  Future<void> signIn(String email, String password) async {
    logins++;
    verified();
  }

  @override
  Future<void> signInWithGoogle() async {
    googleStarts++;
  }

  @override
  Future<void> signOut() async {
    isSignedIn = false;
    email = null;
    events.add(null);
  }

  @override
  Future<void> deleteAccount() => signOut();
}

Finder _key(String name) => find.byKey(Key(name));

Future<void> _pumpAccount(
  WidgetTester tester,
  _RegistrationAuth auth, {
  String language = 'ja',
  TargetPlatform platform = TargetPlatform.android,
  bool pushed = false,
  bool showBackupSection = true,
}) async {
  addTearDown(auth.events.close);
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(language),
      supportedLocales: const [Locale('ja'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(platform: platform),
      home: pushed
          ? const Scaffold(body: Text('Origin'))
          : _account(auth, showBackupSection: showBackupSection),
    ),
  );
  if (pushed) {
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push<void>(MaterialPageRoute(builder: (_) => _account(auth)));
  }
  await tester.pumpAndSettle();
}

CloudAccountPage _account(
  _RegistrationAuth auth, {
  bool showBackupSection = true,
}) => CloudAccountPage(
  auth: auth,
  showBackupSection: showBackupSection,
  historyCount: 0,
  onSyncRequested: () async => throw StateError('Unexpected sync'),
);

Future<void> _fillRegistration(WidgetTester tester) async {
  await tester.ensureVisible(_key('accountAuthModeButton'));
  await tester.tap(_key('accountAuthModeButton'));
  await tester.pumpAndSettle();
  await tester.enterText(_key('accountEmailField'), ' member@example.com ');
  await tester.enterText(_key('accountPasswordField'), 'secret123');
  await tester.enterText(_key('accountPasswordConfirmationField'), 'secret123');
  await tester.ensureVisible(_key('accountSignUpButton'));
  await tester.pumpAndSettle();
}

Future<void> _register(WidgetTester tester) async {
  await tester.ensureVisible(_key('accountSignUpButton'));
  await tester.pumpAndSettle();
  await tester.tap(_key('accountSignUpButton'));
  await tester.pumpAndSettle();
}

void _expectLogin(WidgetTester tester) {
  expect(_key('accountSignInButton'), findsOneWidget);
  expect(_key('accountEmailConfirmation'), findsNothing);
  expect(_key('accountPasswordConfirmationField'), findsNothing);
  expect(
    tester
        .widget<TextFormField>(_key('accountEmailField'))
        .controller!
        .text
        .trim(),
    'member@example.com',
  );
  expect(
    tester.widget<TextFormField>(_key('accountPasswordField')).controller!.text,
    isEmpty,
  );
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final language in ['ja', 'en']) {
      testWidgets('registration confirmation $platform $language', (
        tester,
      ) async {
        final auth = _RegistrationAuth();
        await _pumpAccount(
          tester,
          auth,
          language: language,
          platform: platform,
        );
        await _fillRegistration(tester);
        await _register(tester);
        expect(auth.registrations, 1);
        expect(auth.submittedEmail, 'member@example.com');
        expect(auth.submittedPassword, 'secret123');
        expect(auth.isSignedIn, isFalse);
        expect(
          find.text(
            language == 'ja' ? '確認メールを送信しました' : 'Confirmation email sent',
          ),
          findsOneWidget,
        );
        expect(_key('accountEmailConfirmation'), findsOneWidget);
        expect(
          tester.widget<SelectableText>(_key('accountConfirmationEmail')).data,
          'member@example.com',
        );
        expect(
          find.textContaining(
            language == 'ja'
                ? '確認メール内のリンクを押して'
                : 'Follow the link in the confirmation email',
          ),
          findsOneWidget,
        );
        expect(find.byType(Form), findsNothing);
        expect(_key('accountGoogleSignInButton'), findsNothing);
        expect(_key('cloudBackupButton'), findsNothing);
        expect(
          tester
              .widget<Semantics>(_key('accountEmailConfirmation'))
              .properties
              .liveRegion,
          isTrue,
        );
        await tester.tap(_key('accountConfirmationLoginButton'));
        await tester.pumpAndSettle();
        _expectLogin(tester);
        expect(auth.registrations, 1);
        expect(auth.logins, 0);
        expect(auth.googleStarts, 0);
      });
    }
  }

  testWidgets(
    'confirmation returns to normal login without registering again',
    (tester) async {
      final auth = _RegistrationAuth();
      await _pumpAccount(tester, auth);
      await _fillRegistration(tester);
      await _register(tester);
      await tester.tap(_key('accountConfirmationLoginButton'));
      await tester.pumpAndSettle();
      _expectLogin(tester);
      await tester.enterText(_key('accountPasswordField'), 'secret123');
      await tester.tap(_key('accountSignInButton'));
      await tester.pumpAndSettle();
      expect(auth.logins, 1);
      expect(auth.registrations, 1);
      expect(_key('accountSignedInEmail'), findsOneWidget);
      expect(_key('accountEmailConfirmation'), findsNothing);
    },
  );

  testWidgets('pending registration blocks duplicate requests and navigation', (
    tester,
  ) async {
    final auth = _RegistrationAuth()..request = Completer<bool>();
    await _pumpAccount(tester, auth, pushed: true);
    await _fillRegistration(tester);
    final staleSubmit = tester
        .widget<FilledButton>(_key('accountSignUpButton'))
        .onPressed!;
    staleSubmit();
    staleSubmit();
    await tester.pump();
    expect(auth.registrations, 1);
    expect(find.text('送信中…'), findsOneWidget);
    for (final field in [
      'accountEmailField',
      'accountPasswordField',
      'accountPasswordConfirmationField',
    ]) {
      expect(tester.widget<TextFormField>(_key(field)).enabled, isFalse);
    }
    expect(
      tester.widget<FilledButton>(_key('accountSignUpButton')).onPressed,
      isNull,
    );
    expect(
      tester.widget<TextButton>(_key('accountAuthModeButton')).onPressed,
      isNull,
    );
    await tester.drag(find.byType(ListView), const Offset(0, 1000));
    await tester.pump();
    expect(
      tester
          .widget<OutlinedButton>(_key('accountGoogleSignInButton'))
          .onPressed,
      isNull,
    );
    expect(
      tester.widget<IconButton>(_key('accountBackButton')).onPressed,
      isNull,
    );
    expect(
      tester.widget<IconButton>(_key('accountCloseButton')).onPressed,
      isNull,
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await tester.pump();
    expect(find.byType(CloudAccountPage), findsOneWidget);
    // An unrelated callback failure must not release the request guard.
    auth.events.addError(StateError('private SDK detail'));
    await tester.pump();
    staleSubmit();
    expect(auth.registrations, 1);
    expect(
      tester.widget<FilledButton>(_key('accountSignUpButton')).onPressed,
      isNull,
    );
    expect(find.textContaining('private SDK detail'), findsNothing);
    auth.request!.complete(false);
    await tester.pumpAndSettle();
    expect(_key('accountEmailConfirmation'), findsOneWidget);
    expect(find.text('ログイン状態を確認できませんでした。もう一度お試しください。'), findsNothing);
  });

  for (final failure in [
    const AuthException('Email rate limit exceeded'),
    StateError('private transport detail'),
  ]) {
    testWidgets('registration failure is explicit and retry works: $failure', (
      tester,
    ) async {
      final auth = _RegistrationAuth()..failure = failure;
      await _pumpAccount(tester, auth);
      await _fillRegistration(tester);
      await _register(tester);
      expect(auth.registrations, 1);
      expect(_key('accountEmailConfirmation'), findsNothing);
      expect(_key('accountRegistrationError'), findsOneWidget);
      expect(find.textContaining('アカウントを作成できませんでした'), findsOneWidget);
      expect(find.text('再試行'), findsOneWidget);
      expect(find.textContaining('private transport detail'), findsNothing);
      final errorText = tester.widget<Text>(
        find.descendant(
          of: _key('accountRegistrationError'),
          matching: find.byType(Text),
        ),
      );
      expect(
        errorText.style!.color,
        Theme.of(tester.element(_key('accountRegistrationError')))
            .colorScheme
            .error,
      );
      expect(
        tester
            .widget<Semantics>(_key('accountRegistrationError'))
            .properties
            .liveRegion,
        isTrue,
      );
      auth.failure = null;
      await tester.ensureVisible(_key('accountSignUpButton'));
      await _register(tester);
      expect(auth.registrations, 2);
      expect(_key('accountRegistrationError'), findsNothing);
      expect(_key('accountEmailConfirmation'), findsOneWidget);
    });
  }

  for (final confirming in [false, true]) {
    for (final action in ['back', 'systemBack', 'close']) {
      testWidgets('root $action returns to login confirmation=$confirming', (
        tester,
      ) async {
        final auth = _RegistrationAuth();
        await _pumpAccount(tester, auth);
        await _fillRegistration(tester);
        if (confirming) await _register(tester);
        if (action == 'systemBack') {
          await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
        } else {
          await tester.tap(
            _key(action == 'back' ? 'accountBackButton' : 'accountCloseButton'),
          );
        }
        await tester.pumpAndSettle();
        _expectLogin(tester);
        expect(auth.registrations, confirming ? 1 : 0);
        expect(auth.logins, 0);
      });
    }
  }

  testWidgets('pushed confirmation back returns to login then exits', (
    tester,
  ) async {
    final auth = _RegistrationAuth();
    await _pumpAccount(tester, auth, pushed: true);
    await _fillRegistration(tester);
    await _register(tester);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await tester.pumpAndSettle();
    _expectLogin(tester);
    expect(navigator.canPop(), isTrue);
    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Origin'), findsOneWidget);
    expect(find.byType(CloudAccountPage), findsNothing);
  });

  for (final confirming in [false, true]) {
    testWidgets('pushed registration close exits confirmation=$confirming', (
      tester,
    ) async {
      final auth = _RegistrationAuth();
      await _pumpAccount(tester, auth, pushed: true);
      await _fillRegistration(tester);
      if (confirming) await _register(tester);
      await tester.tap(_key('accountCloseButton'));
      await tester.pumpAndSettle();
      expect(find.text('Origin'), findsOneWidget);
      expect(find.byType(CloudAccountPage), findsNothing);
      expect(auth.events.hasListener, isFalse);
    });
  }

  for (final timing in [
    'beforeResponse',
    'afterResponse',
    'immediateSession',
  ]) {
    testWidgets('authenticated registration skips confirmation: $timing', (
      tester,
    ) async {
      final auth = _RegistrationAuth()
        ..immediateSession = timing == 'immediateSession';
      if (timing == 'beforeResponse') auth.request = Completer<bool>();
      await _pumpAccount(tester, auth);
      await _fillRegistration(tester);
      if (timing == 'beforeResponse') {
        await tester.tap(_key('accountSignUpButton'));
        await tester.pump();
        auth.verified();
        await tester.pump();
        // A stale no-session response must not replace an authenticated view.
        auth.request!.complete(false);
        await tester.pumpAndSettle();
      } else {
        await _register(tester);
        if (timing == 'afterResponse') {
          expect(_key('accountEmailConfirmation'), findsOneWidget);
          auth.verified();
          await tester.pumpAndSettle();
        }
      }
      expect(_key('accountEmailConfirmation'), findsNothing);
      expect(_key('accountSignedInEmail'), findsOneWidget);
      expect(find.byType(Form), findsNothing);
      await auth.signOut();
      await tester.pumpAndSettle();
      _expectLogin(tester);
    });
  }

  for (final immediate in [false, true]) {
    testWidgets(
      'required-account gate handles registration session=$immediate',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'onboarding_completed': true,
          'legal_consent': acceptedLegalConsentJson,
          'workout_history': '["saved"]',
        });
        final auth = _RegistrationAuth()..immediateSession = immediate;
        addTearDown(auth.events.close);
        await tester.pumpWidget(SetkeepApp(auth: auth));
        await tester.pumpAndSettle();
        await _fillRegistration(tester);
        await _register(tester);
        if (!immediate) {
          expect(_key('accountEmailConfirmation'), findsOneWidget);
          expect(find.byType(HomeShell), findsNothing);
          auth.verified();
          await tester.pumpAndSettle();
        }
        expect(find.byType(HomeShell), findsOneWidget);
        expect(_key('accountEmailConfirmation'), findsNothing);
        expect(
          tester.state<NavigatorState>(find.byType(Navigator).first).canPop(),
          isFalse,
        );
        expect(
          (await SharedPreferences.getInstance()).getString('workout_history'),
          '["saved"]',
        );
      },
    );
  }

  for (final failed in [false, true]) {
    testWidgets('late registration completion after disposal failed=$failed', (
      tester,
    ) async {
      final auth = _RegistrationAuth()..request = Completer<bool>();
      await _pumpAccount(tester, auth);
      await _fillRegistration(tester);
      await tester.tap(_key('accountSignUpButton'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(auth.events.hasListener, isFalse);
      if (failed) {
        auth.request!.completeError(StateError('offline'));
      } else {
        auth.request!.complete(false);
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('confirmation fits narrow screen with large text $platform', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final auth = _RegistrationAuth();
      await _pumpAccount(
        tester,
        auth,
        platform: platform,
        showBackupSection: false,
      );
      await _fillRegistration(tester);
      await _register(tester);
      await tester.ensureVisible(_key('accountConfirmationLoginButton'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(_key('accountConfirmationLoginButton'));
      await tester.pumpAndSettle();
      _expectLogin(tester);
    });
  }
}
