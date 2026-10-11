import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setkeep/gym/training_equipment_confirmation.dart';
import 'package:setkeep/main.dart';

class FakeTrainingEquipment implements TrainingEquipmentRepository {
  String? user = 'user-a';
  bool offline = false;
  int optionReads = 0;
  final sent = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> rows = [
    {
      'exercise_id': 'smith_bench_press',
      'options': [
        {'equipment_id': 'smith', 'label': 'スミスマシン', 'known': false},
      ],
    },
  ];
  @override
  String? get userId => user;
  @override
  Future<List<Map<String, dynamic>>> options(
    String store,
    List<String> ids,
  ) async {
    optionReads++;
    if (offline) throw StateError('offline');
    return rows;
  }

  @override
  Future<void> confirm(Map<String, dynamic> r, bool performed) async {
    if (offline) throw StateError('offline');
    sent.add({...r, 'performed': performed});
  }
}

const workout = EquipmentWorkout(
  key: 'record',
  storeId: 'store',
  completed: true,
  exercises: {'smith_bench_press': 'スミスマシンベンチプレス'},
);
const choice = {'exercise_id': 'smith_bench_press', 'equipment_id': 'smith'};

void main() {
  late FakeTrainingEquipment repo;
  late TrainingEquipmentRepository original;
  late TrainingEquipmentJournal originalJournal;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    original = TrainingEquipmentServices.repository;
    originalJournal = TrainingEquipmentServices.journal;
    TrainingEquipmentServices.journal = TrainingEquipmentJournal(
      () => TrainingEquipmentServices.repository,
    );
    repo = FakeTrainingEquipment();
    TrainingEquipmentServices.repository = repo;
  });
  tearDown(() {
    TrainingEquipmentServices.repository = original;
    TrainingEquipmentServices.journal = originalJournal;
  });

  test(
    'adapter includes only completed valid sets with standard exercise IDs',
    () {
      final record = WorkoutRecord(
        date: DateTime(2026, 9, 29),
        gymStoreId: 'store',
        sets: const [
          RecordedSet(
            exerciseId: 'smith_bench_press',
            weight: 20,
            reps: 10,
            completed: true,
          ),
          RecordedSet(
            exerciseId: 'lateral_raise',
            weight: 5,
            reps: 10,
            completed: false,
          ),
          RecordedSet(
            exerciseId: 'dumbbell_curl',
            weight: 0,
            reps: 0,
            completed: true,
          ),
          RecordedSet(
            exerciseId: 'custom:smith',
            weight: 20,
            reps: 10,
            completed: true,
          ),
        ],
      );
      expect(equipmentWorkoutFromRecord(record).exercises.keys, [
        'smith_bench_press',
      ]);
      expect(
        equipmentWorkoutFromRecord(
          WorkoutRecord(date: record.date, sets: record.sets),
        ).eligible,
        false,
      );
      expect(
        equipmentWorkoutFromRecord(
          WorkoutRecord(
            date: record.date,
            sets: record.sets,
            gymStoreId: 'store',
            customPlaceId: 'custom',
          ),
        ).eligible,
        false,
      );
      expect(
        equipmentWorkoutFromRecord(
          WorkoutRecord(
            date: record.date,
            sets: record.sets,
            gymStoreId: 'store',
            trainerWorkoutId: 'trainer',
          ),
        ).eligible,
        false,
      );
    },
  );

  test('one consent per account/store/equipment; offline, edit/delete, Undo and restart', () async {
    final journal = TrainingEquipmentJournal(() => repo);
    await journal.remember(workout, [choice]);
    repo.offline = true;
    await journal.reconcile([workout]);
    expect(repo.sent, isEmpty);
    repo.offline = false;
    final restarted = TrainingEquipmentJournal(() => repo);
    await restarted.reconcile([workout]);
    await restarted.reconcile([workout]);
    expect(repo.sent, hasLength(1));
    expect(repo.sent.single['performed'], true);
    await restarted.reconcile([]); // deletion
    expect(repo.sent.last['performed'], false);
    await restarted.reconcile([workout]); // Undo
    expect(repo.sent.last['performed'], true);
    const next = EquipmentWorkout(
      key: 'second',
      storeId: 'store',
      completed: true,
      exercises: {'smith_bench_press': 'スミスマシンベンチプレス'},
    );
    await restarted.remember(next, [choice]);
    await restarted.reconcile([workout, next]);
    final prefs = await SharedPreferences.getInstance();
    expect(
      jsonDecode(prefs.getString(TrainingEquipmentJournal.storageKey)!),
      hasLength(1),
    );
    expect(repo.sent.last['workout_key'], 'second');
    await restarted.reconcile([
      const EquipmentWorkout(
        key: 'second',
        storeId: 'store',
        completed: true,
        exercises: {},
      ),
    ]);
    expect(repo.sent.last['performed'], false); // removed performed exercise
    repo.user = 'user-b';
    final count = repo.sent.length;
    await restarted.reconcile([workout]);
    expect(repo.sent, hasLength(count));
  });

  test(
    'completion sync uses full persisted history, not a repeat-screen subset',
    () async {
      final old = WorkoutRecord(
        date: DateTime(2026, 9, 28),
        gymStoreId: 'store',
        sets: const [
          RecordedSet(
            exerciseId: 'smith_bench_press',
            weight: 40,
            reps: 10,
            completed: true,
          ),
        ],
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('workout_history', jsonEncode([old.toJson()]));
      await TrainingEquipmentServices.journal.remember(
        equipmentWorkoutFromRecord(old),
        [choice],
      );
      await syncSavedTrainingEquipment();
      expect(repo.sent.single['performed'], true);
      // Another workout completes; the old consent must not be withdrawn.
      final newer = WorkoutRecord(date: DateTime(2026, 9, 29), sets: const []);
      await prefs.setString(
        'workout_history',
        jsonEncode([old.toJson(), newer.toJson()]),
      );
      await syncSavedTrainingEquipment();
      expect(repo.sent, hasLength(1));
    },
  );

  Future<void> open(WidgetTester t, EquipmentWorkout w) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => confirmWorkoutEquipment(context, w),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  testWidgets(
    'no store, unfinished, no actual set, existing equipment: no prompt',
    (t) async {
      for (final w in [
        const EquipmentWorkout(
          key: 'draft',
          storeId: 'store',
          completed: false,
          exercises: {'smith_bench_press': 'Smith'},
        ),
        const EquipmentWorkout(
          key: 'home',
          storeId: null,
          completed: true,
          exercises: {'smith_bench_press': 'Smith'},
        ),
        const EquipmentWorkout(
          key: 'empty',
          storeId: 'store',
          completed: true,
          exercises: {},
        ),
      ]) {
        await open(t, w);
        expect(find.text('今回使用した設備を確認'), findsNothing);
      }
      expect(repo.optionReads, 0);
      repo.rows[0]['options'][0]['known'] = true;
      await open(t, workout);
      expect(find.text('今回使用した設備を確認'), findsNothing);
      expect(repo.sent, isEmpty);
    },
  );

  testWidgets('new equipment requires explicit choice; skip emits no receipt', (
    t,
  ) async {
    await open(t, workout);
    expect(find.text('今回使用した設備を確認'), findsOneWidget);
    expect(t.widget<ChoiceChip>(find.byType(ChoiceChip)).selected, true);
    await t.tap(find.text('スキップ'));
    await t.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(TrainingEquipmentJournal.storageKey), isNull);
    expect(repo.sent, isEmpty);
    await open(t, workout);
    await t.tap(find.text('この内容で送信'));
    await t.pumpAndSettle();
    final rows = jsonDecode(
      prefs.getString(TrainingEquipmentJournal.storageKey)!,
    );
    expect(rows.single['equipment_id'], 'smith');
    expect(rows.single['exercise_id'], 'smith_bench_press');
  });

  testWidgets(
    'ambiguous choice stores only selected equipment, dismiss sends nothing',
    (t) async {
      repo.rows[0]['options'] = [
        {'equipment_id': 'smith', 'label': '設備A', 'known': false},
        {'equipment_id': 'other', 'label': '設備B', 'known': false},
      ];
      await open(t, workout);
      await t.tap(find.text('設備A'));
      await t.pump();
      await t.tap(find.text('設備B'));
      await t.pump();
      await t.tap(find.text('その他 / 判定しない'));
      await t.pump();
      await t.tap(find.text('この内容で送信'));
      await t.pumpAndSettle();
      expect(
        (await SharedPreferences.getInstance()).getString(
          TrainingEquipmentJournal.storageKey,
        ),
        isNull,
      );
      await open(t, workout);
      await t.tap(find.text('設備B'));
      await t.pumpAndSettle();
      expect(
        t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '設備B')).selected,
        true,
      );
      await t.tap(find.text('この内容で送信'));
      await t.pumpAndSettle();
      final rows = jsonDecode(
        (await SharedPreferences.getInstance()).getString(
          TrainingEquipmentJournal.storageKey,
        )!,
      );
      expect(rows, hasLength(1));
      expect(rows.single['equipment_id'], 'other');
    },
  );

  for (final dismiss in ['skip', 'back', 'confirm']) {
    testWidgets(
      'workout saved before optional confirmation; $dismiss preserves history',
      (t) async {
        SharedPreferences.setMockInitialValues({
          activeWorkoutDraftStorageKey: jsonEncode({
            'date': '2026-09-29T18:30:00.000',
            'elapsedSeconds': 120,
            'gymName': '確認用店舗',
            'gymStoreId': 'store',
            'exercises': [
              {
                'name': 'スミスマシンベンチプレス',
                'exerciseId': 'smith_bench_press',
                'bodyPart': '胸',
                'equipment': 'スミスマシン',
                'sets': [
                  {'weight': 40, 'reps': 10, 'completed': true},
                ],
              },
            ],
          }),
        });
        WorkoutUiPreference.completionCheckEnabled = true;
        WorkoutUiPreference.workoutTimerEnabled = false;
        WorkoutUiPreference.workoutDurationEnabled = false;
        RestTimerPreference.enabled = false;
        await t.pumpWidget(const MaterialApp(home: HomeShell()));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('activeWorkoutDraftCard')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('completeWorkoutButton')));
        await t.pumpAndSettle();
        expect(find.text('今回使用した設備を確認'), findsOneWidget);
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getString('workout_history');
        expect(decodeWorkoutHistory(saved).single.gymStoreId, 'store');
        expect(prefs.getString(activeWorkoutDraftStorageKey), isNull);
        if (dismiss == 'back') {
          await t.binding.handlePopRoute();
        } else if (dismiss == 'confirm') {
          await t.tap(find.text('この内容で送信'));
        } else {
          await t.tap(find.text('スキップ'));
        }
        await t.pumpAndSettle();
        expect(find.text('トレーニング完了'), findsOneWidget);
        expect(prefs.getString('workout_history'), saved);
        if (dismiss == 'confirm') {
          expect(repo.sent.single['performed'], true);
        } else {
          expect(repo.sent, isEmpty);
          expect(prefs.getString(TrainingEquipmentJournal.storageKey), isNull);
        }
        await t.pumpWidget(const SizedBox.shrink());
        await t.pumpAndSettle();
        await t.pumpWidget(const MaterialApp(home: HomeShell()));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('activeWorkoutDraftCard')), findsNothing);
        expect(prefs.getString('workout_history'), saved);
      },
    );
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('optional confirmation fits narrow $platform screen', (
      t,
    ) async {
      t.view.physicalSize = const Size(320, 568);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: Scaffold(
            body: TrainingEquipmentSheet(workout: workout, prompts: repo.rows),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('スキップ'), findsOneWidget);
    });
  }
}
