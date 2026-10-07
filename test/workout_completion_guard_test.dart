import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object?> entry({
  ExerciseRecordType type = ExerciseRecordType.weightReps,
  List<bool> checked = const [true, false],
  bool valid = true,
}) => {
  'name': type.usesSets ? 'ベンチプレス' : 'ランニング',
  'exerciseId': type.usesSets ? 'bench_press' : 'running',
  'bodyPart': type.usesSets ? '胸' : '有酸素',
  'equipment': 'フリーウェイト',
  'recordType': type.name,
  'sets': [
    for (var i = 0; i < checked.length; i++)
      {
        'weight': valid ? 50 + i * 5 : 0,
        'reps': valid ? 8 + i : 0,
        'durationSeconds': valid ? 60 : 0,
        'distanceKm': valid ? 1 : 0,
        'completed': checked[i],
      },
  ],
};

String encodeDraft(List<Map<String, Object?>> entries) => jsonEncode({
  'date': DateTime(2026, 10, 6).toIso8601String(),
  'gymName': '自宅',
  'note': '途中入力を保持',
  'exercises': entries,
});

OutlinedButton finishButton(WidgetTester t) =>
    t.widget<OutlinedButton>(find.byKey(const Key('completeWorkoutButton')));

ExerciseInputCard card(WidgetTester t, [int index = 0]) => t
    .widgetList<ExerciseInputCard>(find.byType(ExerciseInputCard))
    .elementAt(index);

Future<void> openWorkout(
  WidgetTester t,
  List<Map<String, Object?>> entries, {
  Future<void> Function(WorkoutRecord)? onSave,
}) async {
  SharedPreferences.setMockInitialValues({
    activeWorkoutDraftStorageKey: encodeDraft(entries),
  });
  await t.pumpWidget(MaterialApp(home: WorkoutPage(onSave: onSave)));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    WorkoutUiPreference.completionCheckEnabled = true;
    WorkoutUiPreference.workoutTimerEnabled = false;
    WorkoutUiPreference.workoutDurationEnabled = false;
    RestTimerPreference.enabled = false;
  });

  for (final type in [
    ExerciseRecordType.weightReps,
    ExerciseRecordType.assistedReps,
    ExerciseRecordType.bodyweightReps,
    ExerciseRecordType.timed,
  ]) {
    testWidgets('$type unchecked input disables finish and survives restart', (
      t,
    ) async {
      var saves = 0;
      await openWorkout(t, [entry(type: type)], onSave: (_) async => saves++);
      expect(finishButton(t).onPressed, isNull);
      await t.tap(find.byKey(const Key('completeWorkoutButton')));
      await t.pumpAndSettle();
      expect(saves, 0);
      final prefs = await SharedPreferences.getInstance();
      final before = prefs.getString(activeWorkoutDraftStorageKey)!;
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      await t.pumpWidget(const MaterialApp(home: WorkoutPage()));
      await t.pumpAndSettle();
      expect(finishButton(t).onPressed, isNull);
      expect(card(t).exercise.sets, hasLength(2));
      expect(card(t).exercise.sets.last.completed, false);
      expect(card(t).exercise.sets.last.weight, 55);
      expect(card(t).exercise.sets.last.reps, 9);
      expect(prefs.getString(activeWorkoutDraftStorageKey), before);
      expect(find.text('トレーニング完了'), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'stale finish callback rejects unchecked sets without clearing',
    (t) async {
      var saves = 0;
      await openWorkout(t, [
        entry(checked: [true, true]),
      ], onSave: (_) async => saves++);
      final staleFinish = finishButton(t).onPressed!;
      card(t).onToggleSet(1);
      await t.pumpAndSettle();
      expect(finishButton(t).onPressed, isNull);
      final prefs = await SharedPreferences.getInstance();
      final before = prefs.getString(activeWorkoutDraftStorageKey)!;
      staleFinish();
      staleFinish();
      await t.pumpAndSettle();
      expect(saves, 0);
      expect(find.text('トレーニング完了'), findsNothing);
      expect(prefs.getString(activeWorkoutDraftStorageKey), before);
      expect(card(t).exercise.sets.last.completed, false);
      expect(card(t).exercise.sets.last.weight, 55);
      expect(card(t).exercise.sets.last.reps, 9);
      await t.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets('back and resume keep unchecked values and completion disabled', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({
      activeWorkoutDraftStorageKey: encodeDraft([entry()]),
    });
    await t.pumpWidget(const MaterialApp(home: HomeShell()));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('activeWorkoutDraftCard')));
    await t.pumpAndSettle();
    expect(finishButton(t).onPressed, isNull);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    await t.tap(find.text('中断する'));
    await t.pumpAndSettle();
    expect(find.byType(DashboardPage), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(decodeWorkoutHistory(prefs.getString('workout_history')), isEmpty);
    await t.tap(find.byKey(const Key('activeWorkoutDraftCard')));
    await t.pumpAndSettle();
    expect(finishButton(t).onPressed, isNull);
    expect(card(t).exercise.sets.last.weight, 55);
    expect(card(t).exercise.sets.last.reps, 9);
    expect(card(t).exercise.sets.last.completed, false);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'editing cannot drop an unchecked historical set via stale save',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      var saves = 0;
      final original = WorkoutRecord(
        date: DateTime(2026, 10, 6),
        sets: const [
          RecordedSet(weight: 50, reps: 8, completed: true),
          RecordedSet(weight: 55, reps: 9, completed: true),
        ],
      );
      await t.pumpWidget(
        MaterialApp(
          home: WorkoutPage(
            initialWorkout: original,
            isEditing: true,
            onSave: (_) async => saves++,
          ),
        ),
      );
      await t.pumpAndSettle();
      final staleSave = finishButton(t).onPressed!;
      card(t).onToggleSet(1);
      await t.pumpAndSettle();
      expect(finishButton(t).onPressed, isNull);
      staleSave();
      await t.pumpAndSettle();
      expect(saves, 0);
      expect(original.sets, hasLength(2));
      expect(card(t).exercise.sets.last.weight, 55);
      expect(card(t).exercise.sets.last.reps, 9);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('checking all remaining sets saves every input once', (t) async {
    final saved = <WorkoutRecord>[];
    await openWorkout(t, [entry()], onSave: (r) async => saved.add(r));
    expect(finishButton(t).onPressed, isNull);
    card(t).onSetAllCompleted(true);
    await t.pumpAndSettle();
    expect(finishButton(t).onPressed, isNotNull);
    final finish = finishButton(t).onPressed!;
    finish();
    finish();
    await t.pumpAndSettle();
    expect(saved, hasLength(1));
    expect(saved.single.sets.map((s) => s.weight), [50, 55]);
    expect(saved.single.sets.map((s) => s.reps), [8, 9]);
    expect(saved.single.note, '途中入力を保持');
    expect(
      (await SharedPreferences.getInstance()).getString(
        activeWorkoutDraftStorageKey,
      ),
      isNull,
    );
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('unchecked set in another exercise blocks a mixed workout', (
    t,
  ) async {
    var saves = 0;
    await openWorkout(t, [
      entry(checked: [true]),
      entry(checked: [false]),
      entry(type: ExerciseRecordType.distance, checked: [false]),
    ], onSave: (_) async => saves++);
    expect(finishButton(t).onPressed, isNull);
    card(t, 1).onToggleSet(0);
    await t.pumpAndSettle();
    expect(finishButton(t).onPressed, isNotNull);
    expect(saves, 0);
    await t.pumpWidget(const SizedBox.shrink());
  });

  for (final type in [
    ExerciseRecordType.cardio,
    ExerciseRecordType.distance,
    ExerciseRecordType.loadedDistance,
  ]) {
    testWidgets('$type keeps no-checkbox completion with every input', (
      t,
    ) async {
      WorkoutRecord? saved;
      await openWorkout(t, [entry(type: type)], onSave: (r) async => saved = r);
      expect(finishButton(t).onPressed, isNotNull);
      await t.tap(find.byKey(const Key('completeWorkoutButton')));
      await t.pumpAndSettle();
      expect(saved!.sets, hasLength(2));
      expect(saved!.sets.every((s) => s.completed), true);
      expect(saved!.sets.last.durationSeconds, 60);
      expect(saved!.sets.last.distanceKm, 1);
      await t.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('hidden completion checks continue to save all valid sets', (
    t,
  ) async {
    WorkoutUiPreference.completionCheckEnabled = false;
    WorkoutRecord? saved;
    await openWorkout(t, [
      entry(checked: [false, false]),
    ], onSave: (r) async => saved = r);
    expect(finishButton(t).onPressed, isNotNull);
    await t.tap(find.byKey(const Key('completeWorkoutButton')));
    await t.pumpAndSettle();
    expect(saved!.sets.map((s) => s.weight), [50, 55]);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('checked empty values still reject saving and keep the draft', (
    t,
  ) async {
    var saves = 0;
    await openWorkout(t, [
      entry(checked: [true], valid: false),
    ], onSave: (_) async => saves++);
    await t.tap(find.byKey(const Key('completeWorkoutButton')));
    await t.pumpAndSettle();
    expect(saves, 0);
    expect(card(t).exercise.sets.single.weight, 0);
    expect(
      (await SharedPreferences.getInstance()).getString(
        activeWorkoutDraftStorageKey,
      ),
      isNotNull,
    );
    expect(find.text('トレーニング完了'), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'zero sets cannot complete; an explicitly emptied exercise is allowed',
    (t) async {
      await openWorkout(t, [entry(checked: [])]);
      expect(finishButton(t).onPressed, isNull);
      await t.pumpWidget(const SizedBox.shrink());
      WorkoutRecord? saved;
      await openWorkout(t, [
        entry(checked: []),
        entry(checked: [true]),
      ], onSave: (r) async => saved = r);
      expect(finishButton(t).onPressed, isNotNull);
      await t.tap(find.byKey(const Key('completeWorkoutButton')));
      await t.pumpAndSettle();
      expect(saved!.sets, hasLength(1));
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
}
