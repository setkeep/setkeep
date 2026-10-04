import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/main.dart';
import 'package:setkeep/trainer/trainer_inbox_page.dart';
import 'package:setkeep/trainer/trainer_menu_codec.dart';

import 'support/trainer_delivery_flow.dart';

class _BadgeRepository extends DeliveryRepository {
  int count = 0;
  @override
  Future<int> unreadCount() async => count;
}

class _LayoutRepository extends DeliveryRepository {
  final layoutMenu = {
    ...deliveryMenu(),
    'name': '肩トレをしましょ',
    'note': '肩を中心にやりましょう',
    'updated_at': '2026-09-25T15:54:53.382527+00:00',
    'due_at': '2026-09-25T15:00:00+00:00',
    'items': [
      {
        'exercise_id': 'shoulder_press',
        'exercise_name': 'ショルダープレスマシン',
        'body_part': '肩',
        'equipment': 'マシン',
        'record_type': 'weightReps',
        'set_values': [
          {'weight': 10.0, 'reps': 10},
          {'weight': 10.0, 'reps': 10},
          {'weight': 10.0, 'reps': 10},
        ],
      },
      {
        'exercise_id': 'lateral_raise',
        'exercise_name': 'ダンベルサイドレイズ',
        'body_part': '肩',
        'equipment': 'ダンベル',
        'record_type': 'weightReps',
        'set_values': [
          {'weight': 2.0, 'reps': 10},
          {'weight': 2.0, 'reps': 10},
          {'weight': 2.0, 'reps': 10},
        ],
      },
    ],
  };

  @override
  Future<List<Map<String, dynamic>>> menus({int offset = 0}) async =>
      offset == 0 ? [layoutMenu] : [];

  @override
  Future<Map<String, dynamic>?> menu(String id) async => layoutMenu;

  @override
  Future<List<Map<String, dynamic>>> comments({int offset = 0}) async =>
      offset == 0
      ? [
          {
            'id': 'comment-layout',
            'body': 'フォームを意識して取り組みましょう',
            'version': 1,
            'updated_at': '2026-09-25T15:54:53.382527+00:00',
            'menu_id': 'menu-a',
          },
        ]
      : [];
}

void main() {
  trainerDeliveryNativeFlow();
  testWidgets('trainer inbox uses workout cards and Japanese dates', (t) async {
    final repo = _LayoutRepository();
    addTearDown(repo.auth.close);
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    WorkoutRecord? started;
    await t.pumpWidget(
      MaterialApp(
        locale: const Locale('ja'),
        supportedLocales: const [Locale('ja'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: TrainerInboxPage(
          repository: repo,
          onStart: (record) async => started = record,
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('肩トレをしましょ'), findsOneWidget);
    expect(find.text('肩を中心にやりましょう'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('trainerMenu:menu-a')),
        matching: find.text('更新：9月26日 00:54'),
      ),
      findsOneWidget,
    );
    expect(find.text('期限：9月26日 0:00'), findsOneWidget);
    expect(find.textContaining('2026-09-25T'), findsNothing);
    expect(find.text('単発'), findsNothing);
    final first = find.byKey(const ValueKey('trainerMenuExercise:menu-a:0'));
    final second = find.byKey(const ValueKey('trainerMenuExercise:menu-a:1'));
    for (final card in [first, second]) {
      expect(
        find.descendant(
          of: card,
          matching: find.byType(WorkoutExerciseCardHeader),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.byType(SetHeader)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.byType(WorkoutSetRowLayout)),
        findsNWidgets(3),
      );
    }
    expect(find.text('ショルダープレスマシン'), findsOneWidget);
    expect(find.text('ダンベルサイドレイズ'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('trainerMenuSet:menu-a:0:0')),
        matching: find.text('10'),
      ),
      findsNWidgets(2),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('trainerMenuSet:menu-a:1:0')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    final start = find.byKey(const ValueKey('startTrainerMenu:menu-a'));
    expect(t.getSize(start).height, 54);
    await t.ensureVisible(start);
    await t.pumpAndSettle();
    await t.tap(start);
    await t.pumpAndSettle();
    expect(started?.sets.map((set) => set.weight), [10, 10, 10, 2, 2, 2]);
    await revealTrainerComment(t, 'フォームを意識して取り組みましょう');
    expect(find.text('フォームを意識して取り組みましょう'), findsOneWidget);
    expect(find.text('対象メニュー：肩トレをしましょ'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('trainerComment:comment-layout')),
        matching: find.text('更新：9月26日 00:54'),
      ),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
  });
  testWidgets('bell badge hides zero and shows counts with a 99+ cap', (
    t,
  ) async {
    final repo = _BadgeRepository();
    addTearDown(repo.auth.close);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeHeader(repository: repo, onStart: (_) async {}),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const Key('trainerInboxUnreadBadge')), findsNothing);
    for (final entry in [(1, '1'), (3, '3'), (120, '99+')]) {
      repo.count = entry.$1;
      repo.auth.add(null);
      await t.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('trainerInboxUnreadBadge')),
          matching: find.text(entry.$2),
        ),
        findsOneWidget,
      );
    }
  });
  testWidgets(
    'bell is the sole inbox entry and reflects unread menus/comments',
    (t) async {
      final repo = DeliveryRepository();
      addTearDown(repo.auth.close);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeHeader(repository: repo, onStart: (_) async {}),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('trainerInboxButton')), findsNothing);
      expect(find.text('2', findRichText: true), findsOneWidget);
      await t.tap(find.byKey(const Key('trainerInboxBell')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('trainerNotificationSource')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('trainerInboxPage')), findsOneWidget);
      expect(await repo.unreadCount(), 0);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('trainerInboxUnreadBadge')), findsNothing);

      repo.version = 2;
      repo.body = 'A new comment';
      await t.pump(const Duration(seconds: 30));
      await t.pump();
      expect(find.text('2', findRichText: true), findsOneWidget);
      await t.tap(find.byKey(const Key('trainerInboxBell')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('trainerNotificationSource')));
      await t.pumpAndSettle();
      expect(find.text('Coach plan v2'), findsOneWidget);
      await revealTrainerComment(t, 'A new comment');
      expect(find.text('A new comment'), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('trainerInboxUnreadBadge')), findsNothing);
    },
  );

  testWidgets(
    'failed inbox load leaves unread, and account switch clears badge',
    (t) async {
      final repo = DeliveryRepository();
      addTearDown(repo.auth.close);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeHeader(repository: repo, onStart: (_) async {}),
          ),
        ),
      );
      await t.pumpAndSettle();
      repo.fail = true;
      await t.tap(find.byKey(const Key('trainerInboxBell')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('trainerNotificationSource')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('trainerInboxError')), findsOneWidget);
      repo.fail = false;
      expect(await repo.unreadCount(), 2);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      repo.userId = 'user-b';
      repo.auth.add(null);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('trainerInboxUnreadBadge')), findsNothing);
      repo.userId = 'user-a';
      repo.auth.add(null);
      await t.pumpAndSettle();
      expect(find.text('2', findRichText: true), findsOneWidget);
    },
  );
  test('one codec preserves exercise/set order and all SK numeric fields', () {
    final row = TrainerMenuCodec.fromRow({
      'id': 'menu',
      'tenant_menu_exercises': [
        {
          'position': 2,
          'exercise_id': 'run',
          'exercise_name': 'Run',
          'record_type': 'cardio',
          'tenant_menu_sets': [
            {
              'position': 1,
              'values': {
                'durationSeconds': 123,
                'distanceKm': 1.23,
                'speedKmh': 12.3,
                'inclinePercent': 4.5,
                'resistanceLevel': 6.7,
                'paceSecondsPerKm': 345,
                'distanceUnit': 'm',
              },
            },
          ],
        },
        {
          'position': 1,
          'exercise_id': 'bench_press',
          'exercise_name': 'Bench',
          'record_type': 'weightReps',
          'tenant_menu_sets': [
            {
              'position': 2,
              'values': {'weight': 25.5, 'reps': 8},
            },
            {
              'position': 1,
              'values': {'weight': 20.5, 'reps': 10},
            },
          ],
        },
      ],
    });
    final workout = TrainerMenuCodec.workout(row);
    final editable = TrainerMenuCodec.exercises(row['items'] as List);
    expect(workout.sets.map((s) => s.exerciseId), [
      'bench_press',
      'bench_press',
      'run',
    ]);
    expect(editable.first.sets.map((s) => s.weight), [20.5, 25.5]);
    final run = workout.sets.last;
    expect(run.durationSeconds, 123);
    expect(run.distanceKm, 1.23);
    expect(run.speedKmh, 12.3);
    expect(run.inclinePercent, 4.5);
    expect(run.resistanceLevel, 6.7);
    expect(run.paceSecondsPerKm, 345);
    expect(editable.last.distanceUnit, 'm');
    expect(editable.last.sets.single.durationSeconds, run.durationSeconds);
    expect(workout.sets.every((s) => !s.completed), true);
  });
  testWidgets(
    'refresh reflects menu update and comment update/delete without copies',
    (t) async {
      final repo = DeliveryRepository();
      addTearDown(repo.auth.close);
      await t.pumpWidget(
        MaterialApp(
          home: TrainerInboxPage(repository: repo, onStart: (_) async {}),
        ),
      );
      await t.pumpAndSettle();
      repo.version = 2;
      repo.body = 'Edited comment';
      await t.tap(find.byKey(const Key('refreshTrainerInbox')));
      await t.pumpAndSettle();
      expect(find.text('Coach plan v1'), findsNothing);
      expect(find.text('Coach plan v2'), findsOneWidget);
      await revealTrainerComment(t, 'Edited comment');
      expect(find.text('Edited comment'), findsOneWidget);
      repo.deleted = true;
      repo.canceled = true;
      await t.tap(find.byKey(const Key('refreshTrainerInbox')));
      await t.pumpAndSettle();
      expect(find.text('Edited comment'), findsNothing);
      expect(find.text('Coach plan v2'), findsNothing);
    },
  );
  testWidgets('start rechecks version/cancel state; stale menu cannot start', (
    t,
  ) async {
    final repo = DeliveryRepository();
    addTearDown(repo.auth.close);
    var starts = 0;
    await t.pumpWidget(
      MaterialApp(
        home: TrainerInboxPage(
          repository: repo,
          onStart: (_) async {
            starts++;
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    repo.version = 2;
    await t.tap(find.byKey(const ValueKey('startTrainerMenu:menu-a')));
    await t.pumpAndSettle();
    expect(starts, 0);
    expect(find.text('Coach plan v2'), findsOneWidget);
    repo.canceled = true;
    await t.tap(find.byKey(const ValueKey('startTrainerMenu:menu-a')));
    await t.pumpAndSettle();
    expect(starts, 0);
    expect(find.text('Coach plan v2'), findsNothing);
  });
  testWidgets('account switch discards late A response and clears comments', (
    t,
  ) async {
    final repo = DeliveryRepository();
    addTearDown(repo.auth.close);
    final delayed = Completer<List<Map<String, dynamic>>>();
    repo.pending = delayed;
    await t.pumpWidget(
      MaterialApp(
        home: TrainerInboxPage(repository: repo, onStart: (_) async {}),
      ),
    );
    await t.pump();
    repo.pending = null;
    repo.userId = 'user-b';
    repo.auth.add(null);
    await t.pumpAndSettle();
    delayed.complete([deliveryMenu()]);
    await t.pumpAndSettle();
    expect(find.text('Coach plan v1'), findsNothing);
    expect(find.text('Coach comment'), findsNothing);
    repo.userId = null;
    repo.auth.add(null);
    await t.pumpAndSettle();
    expect(find.text('Sign in from Account on your profile.'), findsOneWidget);
  });
  testWidgets(
    'failed refresh removes stale private content and supports retry',
    (t) async {
      final repo = DeliveryRepository();
      addTearDown(repo.auth.close);
      await t.pumpWidget(
        MaterialApp(
          home: TrainerInboxPage(repository: repo, onStart: (_) async {}),
        ),
      );
      await t.pumpAndSettle();
      repo.fail = true;
      await t.tap(find.byKey(const Key('refreshTrainerInbox')));
      await t.pumpAndSettle();
      expect(find.text('Coach comment'), findsNothing);
      expect(find.byKey(const Key('trainerInboxError')), findsOneWidget);
      repo.fail = false;
      await t.tap(find.byKey(const Key('refreshTrainerInbox')));
      await t.pumpAndSettle();
      await revealTrainerComment(t, 'Coach comment');
      expect(find.text('Coach comment'), findsOneWidget);
    },
  );
}
