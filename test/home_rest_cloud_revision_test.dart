import 'support/signed_in_auth.dart';
import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:setkeep/config/supabase_config.dart';
import 'package:setkeep/services/account_auth_service.dart';

import 'support/legal_consent_fixture.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/body_weight.dart';
import 'package:setkeep/main.dart';
import 'package:setkeep/services/supabase_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAccountAuth implements AccountAuthService {
  final events = StreamController<void>.broadcast();
  @override
  bool isSignedIn = false;
  @override
  String? email;
  int signIns = 0, signUps = 0, signOuts = 0;
  bool registrationSession = false;
  bool rejectSignIn = false;
  int deletions = 0;
  Completer<void>? deletion;
  bool rejectDeletion = false;
  @override
  Future<void> deleteAccount() async {
    deletions++;
    await deletion?.future;
    if (rejectDeletion) throw const AuthException('削除できませんでした');
    await signOut();
  }

  int googleSignIns = 0;
  Completer<void>? googleLaunch;
  Object? googleError;
  @override
  Future<void> signInWithGoogle() async {
    googleSignIns++;
    if (googleError != null) throw googleError!;
    await googleLaunch?.future;
  }

  @override
  Stream<void> get changes => events.stream;
  void signedIn(String value) {
    isSignedIn = true;
    email = value;
    events.add(null);
  }

  @override
  Future<void> signIn(String email, String password) async {
    signIns++;
    if (rejectSignIn) throw const AuthException('認証できませんでした');
    signedIn(email);
  }

  @override
  Future<bool> signUp(String email, String password) async {
    signUps++;
    if (registrationSession) signedIn(email);
    return registrationSession;
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    isSignedIn = false;
    email = null;
    events.add(null);
  }
}

void main() {
  for (final email in ['google@example.com', 'mail@example.com']) {
    testWidgets('delete confirmation preserves local history: $email', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'workout_history': '["saved"]'});
      final auth = _FakeAccountAuth()..signedIn(email);
      addTearDown(auth.events.close);
      var syncs = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: CloudAccountPage(
            historyCount: 1,
            auth: auth,
            onSyncRequested: () async {
              syncs++;
              return 0;
            },
          ),
        ),
      );
      final delete = find.byKey(const Key('accountDeleteButton'));
      await tester.tap(delete);
      await tester.pumpAndSettle();
      expect(find.textContaining('この端末のトレーニング記録は残ります。'), findsOneWidget);
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(auth.deletions, 0);
      expect(auth.isSignedIn, isTrue);
      auth.deletion = Completer<void>();
      await tester.tap(delete);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('accountDeleteConfirmButton')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(auth.deletions, 1);
      expect(tester.widget<TextButton>(delete).onPressed, isNull);
      auth.deletion!.complete();
      await tester.pumpAndSettle();
      expect(auth.isSignedIn, isFalse);
      expect(delete, findsNothing);
      expect(find.byKey(const Key('accountEmailField')), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getString('workout_history'),
        '["saved"]',
      );
      expect(syncs, 0);
      expect(SupabaseSyncService.canUseCloud, isFalse);
    });
  }

  testWidgets('failed deletion keeps account available for retry', (
    tester,
  ) async {
    final auth = _FakeAccountAuth()
      ..signedIn('mail@example.com')
      ..rejectDeletion = true;
    addTearDown(auth.events.close);
    await tester.pumpWidget(
      MaterialApp(
        home: CloudAccountPage(
          historyCount: 0,
          auth: auth,
          onSyncRequested: () async => 0,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('accountDeleteButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('accountDeleteConfirmButton')));
    await tester.pumpAndSettle();
    expect(auth.isSignedIn, isTrue);
    expect(find.text('削除できませんでした'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('accountDeleteButton')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('callback errors are handled and a later login recovers', (
    tester,
  ) async {
    final auth = _FakeAccountAuth();
    addTearDown(auth.events.close);
    await tester.pumpWidget(
      MaterialApp(
        home: CloudAccountPage(
          historyCount: 0,
          auth: auth,
          onSyncRequested: () async => throw StateError('Unexpected sync'),
        ),
      ),
    );
    final google = find.byKey(const Key('accountGoogleSignInButton'));
    await tester.tap(google);
    await tester.pumpAndSettle();
    for (final error in [
      const AuthException('sensitive SDK detail'),
      StateError('sensitive SDK detail'),
    ]) {
      auth.events.addError(error, StackTrace.current);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('ログイン状態を確認できませんでした。もう一度お試しください。'), findsOneWidget);
      expect(find.textContaining('sensitive SDK detail'), findsNothing);
      expect(tester.widget<OutlinedButton>(google).onPressed, isNotNull);
    }
    auth.signedIn('google@example.com');
    await tester.pumpAndSettle();
    expect(find.text('google@example.com'), findsOneWidget);
    expect(find.text('ログイン状態を確認できませんでした。もう一度お試しください。'), findsNothing);
    expect(google, findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(auth.events.hasListener, isFalse);
  });

  for (final registration in [false, true]) {
    testWidgets(
      'Google launch waits for auth callback registration=$registration',
      (tester) async {
        final auth = _FakeAccountAuth()..googleLaunch = Completer<void>();
        addTearDown(auth.events.close);
        var syncs = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: CloudAccountPage(
              historyCount: 0,
              auth: auth,
              onSyncRequested: () async {
                syncs++;
                return 0;
              },
            ),
          ),
        );
        if (registration) {
          await tester.tap(find.byKey(const Key('accountAuthModeButton')));
          await tester.pumpAndSettle();
        }
        final google = find.byKey(const Key('accountGoogleSignInButton'));
        expect(google, findsOneWidget);
        await tester.tap(google);
        await tester.pump();
        expect(auth.googleSignIns, 1);
        expect(
          tester
              .widget<TextButton>(
                find.byKey(const Key('accountAuthModeButton')),
              )
              .onPressed,
          isNull,
        );
        expect(tester.widget<OutlinedButton>(google).onPressed, isNull);
        await tester.tap(google);
        expect(auth.googleSignIns, 1);
        auth.googleLaunch!.complete();
        await tester.pumpAndSettle();
        // Closing/cancelling the browser without a callback leaves login available.
        expect(find.byKey(const Key('accountEmailField')), findsOneWidget);
        expect(tester.widget<OutlinedButton>(google).onPressed, isNotNull);
        expect(find.text('ログインしました'), findsNothing);
        expect(find.text('通信に失敗しました。接続を確認してください。'), findsNothing);
        auth.signedIn('google@example.com');
        await tester.pumpAndSettle();
        expect(find.text('google@example.com'), findsOneWidget);
        expect(google, findsNothing);
        expect(SupabaseSyncService.canUseCloud, isFalse);
        expect(syncs, 0);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('cloudBackupButton')))
              .onPressed,
          isNull,
        );
      },
    );
  }

  testWidgets('Google launch errors are shown and can be retried', (
    tester,
  ) async {
    final auth = _FakeAccountAuth()
      ..googleError = const AuthException('Googleログイン画面を開けませんでした');
    addTearDown(auth.events.close);
    await tester.pumpWidget(
      MaterialApp(
        home: CloudAccountPage(
          historyCount: 0,
          auth: auth,
          onSyncRequested: () async => 0,
        ),
      ),
    );
    final google = find.byKey(const Key('accountGoogleSignInButton'));
    await tester.tap(google);
    await tester.pumpAndSettle();
    expect(find.text('Googleログイン画面を開けませんでした'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(google).onPressed, isNotNull);
    auth.googleError = null;
    await tester.tap(google);
    await tester.pumpAndSettle();
    expect(auth.googleSignIns, 2);
    expect(find.text('Googleログイン画面を開けませんでした'), findsNothing);
  });
  testWidgets(
    'account is accessible from profile without configuration or Premium',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'onboarding_completed': true,
        'legal_consent': acceptedLegalConsentJson,
      });
      expect(SupabaseConfig.initialized, isFalse);
      await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.person_outline_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('accountButton')));
      await tester.pumpAndSettle();
      expect(find.text('アカウント'), findsOneWidget);
      expect(find.text('現在アカウント機能を利用できません'), findsOneWidget);
      expect(find.byKey(const Key('accountGoogleSignInButton')), findsNothing);
      expect(find.byKey(const Key('accountEmailField')), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('cloudBackupButton')))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'account modes switch without authentication and validate confirmation',
    (tester) async {
      final auth = _FakeAccountAuth();
      addTearDown(auth.events.close);
      await tester.pumpWidget(
        MaterialApp(
          home: CloudAccountPage(
            historyCount: 0,
            auth: auth,
            onSyncRequested: () async => throw StateError('Unexpected sync'),
          ),
        ),
      );
      final toggle = find.byKey(const Key('accountAuthModeButton'));
      final confirmation = find.byKey(
        const Key('accountPasswordConfirmationField'),
      );
      final email = find.byKey(const Key('accountEmailField'));
      final password = find.byKey(const Key('accountPasswordField'));
      expect(find.text('アカウントをお持ちでない方 → 新規アカウント作成'), findsOneWidget);
      expect(confirmation, findsNothing);
      await tester.enterText(email, 'user@example.com');
      await tester.enterText(password, 'secret123');
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(auth.signIns, 0);
      expect(auth.signUps, 0);
      expect(find.text('アカウントを作成'), findsNWidgets(2));
      expect(find.text('すでにアカウントをお持ちの方 → ログイン'), findsOneWidget);
      expect(find.byKey(const Key('accountSignInButton')), findsNothing);
      expect(
        tester.widget<TextFormField>(email).controller!.text,
        'user@example.com',
      );
      expect(tester.widget<TextFormField>(password).controller!.text, isEmpty);
      await tester.enterText(password, 'secret123');
      final submit = find.byKey(const Key('accountSignUpButton'));
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.text('確認用のパスワードを入力してください'), findsOneWidget);
      await tester.enterText(confirmation, 'secret123 ');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.text('パスワードが一致しません'), findsOneWidget);
      expect(auth.signUps, 0);
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(confirmation, findsNothing);
      expect(find.text('パスワードが一致しません'), findsNothing);
      expect(find.byKey(const Key('accountSignInButton')), findsOneWidget);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(confirmation).controller!.text,
        isEmpty,
      );
      expect(auth.signUps, 0);
      expect(auth.signIns, 0);
    },
  );

  testWidgets('account validates credentials without calling authentication', (
    tester,
  ) async {
    final auth = _FakeAccountAuth();
    addTearDown(auth.events.close);
    await tester.pumpWidget(
      MaterialApp(
        home: CloudAccountPage(
          historyCount: 0,
          onSyncRequested: () async => throw StateError('Unexpected sync'),
          auth: auth,
        ),
      ),
    );
    for (final button in ['accountSignInButton', 'accountSignUpButton']) {
      if (button == 'accountSignUpButton') {
        await tester.ensureVisible(find.byKey(const Key('accountAuthModeButton')));
        await tester.tap(find.byKey(const Key('accountAuthModeButton')));
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byKey(const Key('accountEmailField')), '');
      await tester.enterText(
        find.byKey(const Key('accountPasswordField')),
        '12345',
      );
      await tester.tap(find.byKey(Key(button)));
      await tester.pumpAndSettle();
      expect(find.text('メールアドレスを入力してください'), findsOneWidget);
      expect(find.text('パスワードは6文字以上で入力してください'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('accountEmailField')),
        'not-an-email',
      );
      await tester.tap(find.byKey(Key(button)));
      await tester.pumpAndSettle();
      expect(find.text('メールアドレスの形式を確認してください'), findsOneWidget);
    }
    expect(auth.signIns, 0);
    expect(auth.signUps, 0);
  });

  testWidgets(
    'account login logout and external auth events never unlock or sync cloud',
    (tester) async {
      final auth = _FakeAccountAuth();
      addTearDown(auth.events.close);
      var syncs = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: CloudAccountPage(
            historyCount: 1,
            onSyncRequested: () async {
              syncs++;
              return 1;
            },
            auth: auth,
          ),
        ),
      );
      expect(SupabaseSyncService.canUseCloud, isFalse);
      await tester.enterText(
        find.byKey(const Key('accountEmailField')),
        ' user@example.com ',
      );
      await tester.enterText(
        find.byKey(const Key('accountPasswordField')),
        'secret123',
      );
      await tester.tap(find.byKey(const Key('accountSignInButton')));
      await tester.pumpAndSettle();
      expect(auth.signIns, 1);
      expect(find.text('user@example.com'), findsOneWidget);
      expect(find.text('ログインしました'), findsOneWidget);
      expect(find.byKey(const Key('accountGoogleSignInButton')), findsNothing);
      expect(find.byKey(const Key('accountEmailField')), findsNothing);
      expect(SupabaseSyncService.canUseCloud, isFalse);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('cloudBackupButton')))
            .onPressed,
        isNull,
      );
      expect(syncs, 0);
      await tester.tap(find.byKey(const Key('accountSignOutButton')));
      await tester.pumpAndSettle();
      expect(auth.signOuts, 1);
      expect(find.text('ログアウトしました'), findsOneWidget);
      expect(find.byKey(const Key('accountEmailField')), findsOneWidget);
      auth.signedIn('external@example.com');
      await tester.pumpAndSettle();
      expect(find.text('external@example.com'), findsOneWidget);
      auth.signedIn('refreshed@example.com');
      await tester.pumpAndSettle();
      expect(find.text('refreshed@example.com'), findsOneWidget);
      await auth.signOut();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('accountEmailField')), findsOneWidget);
      auth.rejectSignIn = true;
      await tester.enterText(
        find.byKey(const Key('accountPasswordField')),
        'secret123',
      );
      await tester.tap(find.byKey(const Key('accountSignInButton')));
      await tester.pumpAndSettle();
      expect(find.text('認証できませんでした'), findsOneWidget);
      expect(syncs, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(auth.events.hasListener, isFalse);
      auth.signedIn('disposed@example.com');
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  for (final session in [false, true]) {
    testWidgets('account registration without Premium session=$session', (
      tester,
    ) async {
      final auth = _FakeAccountAuth()..registrationSession = session;
      addTearDown(auth.events.close);
      var syncs = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: CloudAccountPage(
            historyCount: 0,
            onSyncRequested: () async {
              syncs++;
              return 0;
            },
            auth: auth,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('accountAuthModeButton')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('accountEmailField')),
        'user@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('accountPasswordField')),
        'secret123',
      );
      await tester.enterText(
        find.byKey(const Key('accountPasswordConfirmationField')),
        'secret123',
      );
      await tester.tap(find.byKey(const Key('accountSignUpButton')));
      await tester.pumpAndSettle();
      expect(auth.signUps, 1);
      expect(
        find.text(session ? 'アカウントを作成しました' : 'Confirmation email sent'),
        findsOneWidget,
      );
      expect(SupabaseSyncService.canUseCloud, isFalse);
      expect(syncs, 0);
      if (!session) {
        expect(find.byKey(const Key('cloudBackupButton')), findsNothing);
        return;
      }
      await tester.ensureVisible(find.byKey(const Key('cloudBackupButton')));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('cloudBackupButton')))
            .onPressed,
        isNull,
      );
    });
  }
  testWidgets(
    '12 weights stay in graph, only latest row is shown and editable',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final today = DateUtils.dateOnly(DateTime.now());
      final entries = ValueNotifier(
        List.generate(
          12,
          (i) => BodyWeightEntry(
            id: 'w$i',
            recordedAt: today.subtract(Duration(days: 11 - i)),
            weightKg: 80 + i / 10,
          ),
        ),
      );
      addTearDown(entries.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ValueListenableBuilder<List<BodyWeightEntry>>(
                valueListenable: entries,
                builder: (_, value, _) => BodyWeightTrendSection(
                  entries: value,
                  onDeleted: (entry) async => entries.value = [
                    for (final old in entries.value) if (old.id != entry.id) old,
                  ],
                  onSaved: (entry) async => entries.value = [
                    for (final old in value) old.id == entry.id ? entry : old,
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byTooltip('体重を編集'), findsOneWidget);
      expect(find.byKey(const Key('editBodyWeightw11')), findsOneWidget);
      expect(find.text('任意で記録できます ・ kg'), findsNothing);
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.descendant(
                      of: find.byKey(const Key('bodyWeightChart')),
                      matching: find.byType(CustomPaint),
                    ),
                  )
                  .painter!
              as BodyWeightChartPainter;
      expect(painter.entries, hasLength(12));
      await tester.tap(find.byKey(const Key('editBodyWeightw11')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('bodyWeightField')), '87.5');
      await tester.tap(find.byKey(const Key('saveBodyWeightButton')));
      await tester.pumpAndSettle();
      expect(entries.value, hasLength(12));
      expect(entries.value.last.weightKg, 87.5);
      expect(find.textContaining('87.5 kg'), findsOneWidget);
      expect(entries.value.first.weightKg, 80);
      Future<void> deleteOpenedEntry() async {
        await tester.tap(find.byKey(const Key('deleteBodyWeightButton')));
        await tester.pumpAndSettle();
        expect(find.text('この体重記録を削除しますか？'), findsOneWidget);
        await tester.tap(find.byKey(const Key('confirmDeleteBodyWeightButton')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('editBodyWeightw11')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deleteBodyWeightButton')), findsOneWidget);
      await tester.tap(find.byKey(const Key('deleteBodyWeightButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cancelDeleteBodyWeightButton')));
      await tester.pumpAndSettle();
      expect(entries.value, hasLength(12));
      expect(find.byKey(const Key('bodyWeightField')), findsOneWidget);
      await deleteOpenedEntry();
      expect(entries.value, hasLength(11));
      expect(find.byKey(const Key('editBodyWeightw10')), findsOneWidget);
      expect(find.byKey(const Key('bodyWeightField')), findsNothing);
      // Select and delete an older graph point, keeping the latest unchanged.
      final chart = find.byKey(const Key('bodyWeightChart'));
      await tester.tapAt(tester.getTopLeft(chart) + const Offset(46, 100));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byKey(const Key('selectedBodyWeight')),
        matching: find.text('編集'),
      ));
      await tester.pumpAndSettle();
      await deleteOpenedEntry();
      expect(entries.value.any((e) => e.id == 'w0'), isFalse);
      expect(entries.value, hasLength(10));
      final updatedPainter = tester.widget<CustomPaint>(find.descendant(
        of: chart, matching: find.byType(CustomPaint),
      )).painter! as BodyWeightChartPainter;
      expect(updatedPainter.entries, hasLength(10));
      expect(updatedPainter.selectedId, isNull);
      expect(find.byKey(const Key('selectedBodyWeight')), findsNothing);
      while (entries.value.isNotEmpty) {
        await tester.tap(find.byKey(Key('editBodyWeight${entries.value.last.id}')));
        await tester.pumpAndSettle();
        await deleteOpenedEntry();
      }
      expect(find.byKey(const Key('bodyWeightChart')), findsNothing);
      expect(find.text('体重を記録するとグラフが表示されます'), findsOneWidget);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('free local backup actions work and cloud button is locked', (
    tester,
  ) async {
    var exports = 0, imports = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: BackupDataManagementPage(
          onExport: (_) async {
            exports++;
          },
          onImportFile: (_) async {
            imports++;
          },
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('exportBackupFile')));
    await tester.tap(find.byKey(const Key('importBackupFile')));
    expect(exports, 1);
    expect(imports, 1);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('cloudBackupButton')),
    );
    expect(button.onPressed, isNull);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });

  testWidgets('verified premium presentation enables cloud area only', (
    tester,
  ) async {
    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudBackupSection(premium: true, onOpen: () => opens++),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('cloudBackupButton')));
    expect(opens, 1);
    expect(find.byIcon(Icons.lock_outline), findsNothing);
  });

  test(
    'all cloud entry points deny free access before using Supabase',
    () async {
      expect(SupabaseSyncService.canUseCloud, isFalse);
      await expectLater(SupabaseSyncService.syncWorkouts([]), throwsStateError);
      await expectLater(SupabaseSyncService.fetchWorkouts(), throwsStateError);
      await expectLater(
        SupabaseSyncService.deleteWorkout('x'),
        throwsStateError,
      );
    },
  );

  testWidgets('home removes summaries without removing saved workouts', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true, 'legal_consent': acceptedLegalConsentJson});
    await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
    await tester.pumpAndSettle();
    expect(find.byType(WeeklySummary), findsNothing);
    expect(find.byType(LastWorkoutCard), findsNothing);
    expect(find.text('今週の記録'), findsNothing);
    expect(find.text('前回のトレーニング'), findsNothing);
    expect(find.byKey(const Key('startWorkoutButton')), findsOneWidget);
  });

  testWidgets('manual rest stop remains silent past original deadline', (
    tester,
  ) async {
    final sounds = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        sounds.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    SharedPreferences.setMockInitialValues({
      'onboarding_completed': true,
    'legal_consent': acceptedLegalConsentJson,
      'rest_timer_enabled': true,
      'rest_timer_seconds': 30,
      'completion_check_enabled': true,
    });
    await RestTimerPreference.load();
    await WorkoutUiPreference.load();
    final initial = WorkoutRecord(
      date: DateTime.now(),
      durationSeconds: 0,
      sets: const [
        RecordedSet(
          exerciseName: 'ベンチプレス',
          bodyPart: '胸',
          weight: 60,
          reps: 10,
          completed: true,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WorkoutPage(history: const [], initialWorkout: initial),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('startRestTimerButton')));
    await tester.pump();
    expect(find.byKey(const Key('restTimerBanner')), findsOneWidget);
    await tester.tap(find.byKey(const Key('stopRestTimerButton')));
    await tester.pump();
    expect(find.byKey(const Key('startRestTimerButton')), findsOneWidget);
    expect(find.text('00:30'), findsOneWidget);
    sounds.clear();
    await tester.pump(const Duration(seconds: 35));
    expect(find.byKey(const Key('restTimerFinishedMessage')), findsNothing);
    expect(sounds.where((c) => c.method == 'SystemSound.play'), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
