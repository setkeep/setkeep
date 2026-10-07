import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

RecordedSet strength(
  double weight,
  int reps, {
  String name = 'ケーブルラットプルダウン',
  ExerciseRecordType type = ExerciseRecordType.weightReps,
}) => RecordedSet(
  exerciseName: name,
  weight: weight,
  reps: reps,
  recordType: type,
  completed: true,
);

Future<void> preview(WidgetTester tester, List<RecordedSet> sets) async {
  await tester.pumpWidget(
    MaterialApp(
      home: WorkoutSharePage(
        workout: WorkoutRecord(date: DateTime(2026, 10, 6), sets: sets),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'SNS preserves four recorded sets as three value lines in export',
    (tester) async {
      final workout = WorkoutRecord(
        date: DateTime(2026, 10, 6),
        sets: [
          strength(25, 20),
          strength(50, 10),
          strength(55, 10),
          strength(55, 10),
          for (var i = 0; i < 3; i++)
            strength(
              30,
              10,
              name: 'アシストチンニング',
              type: ExerciseRecordType.assistedReps,
            ),
          strength(80, 10, name: 'ライナーロウ'),
          strength(80, 10, name: 'ライナーロウ'),
          strength(90, 8, name: 'ライナーロウ'),
          for (var i = 0; i < 3; i++) strength(40, 12, name: 'ストレートアームプルダウン'),
        ],
      );
      final historyBefore = jsonEncode([workout.toJson()]);
      const draftBefore = 'synthetic unrelated draft';
      SharedPreferences.setMockInitialValues({
        'workout_history': historyBefore,
        activeWorkoutDraftStorageKey: draftBefore,
      });
      Uint8List? saved;
      WorkoutImageService.saveOverride = (bytes) async {
        saved = bytes;
      };
      addTearDown(() => WorkoutImageService.saveOverride = null);
      await tester.pumpWidget(
        MaterialApp(home: WorkoutSharePage(workout: workout)),
      );
      await tester.pumpAndSettle();
      for (final line in [
        '25 kg × 20 回  /  1 セット',
        '50 kg × 10 回  /  1 セット',
        '55 kg × 10 回  /  2 セット',
        '補助 30 kg × 10 回  /  3 セット',
        '80 kg × 10 回  /  2 セット',
        '90 kg × 8 回  /  1 セット',
        '40 kg × 12 回  /  3 セット',
      ]) {
        expect(find.text(line), findsOneWidget);
      }
      expect(find.text('55 kg × 10 回  /  4 セット'), findsNothing);
      expect(
        tester.getTopLeft(find.text('25 kg × 20 回  /  1 セット')).dy,
        lessThan(tester.getTopLeft(find.text('50 kg × 10 回  /  1 セット')).dy),
      );
      expect(
        tester.getTopLeft(find.text('50 kg × 10 回  /  1 セット')).dy,
        lessThan(tester.getTopLeft(find.text('55 kg × 10 回  /  2 セット')).dy),
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('shareWorkoutImageButton')),
        150,
      );
      await tester.ensureVisible(
        find.byKey(const Key('shareWorkoutImageButton')),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('shareWorkoutImageButton')));
        await tester.pump();
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (saved == null && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(saved, isNotNull, reason: 'Wait for the actual PNG capture');
      });
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      final evidencePath =
          Platform.environment['SETKEEP_SHARE_PREVIEW_EVIDENCE_PATH'];
      if (evidencePath != null) {
        await tester.runAsync(() => File(evidencePath).writeAsBytes(saved!));
      }
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('workout_history'), historyBefore);
      expect(preferences.getString(activeWorkoutDraftStorageKey), draftBefore);
      expect(jsonEncode([workout.toJson()]), historyBefore);
      expect(workout.sets.take(4).map((set) => (set.weight, set.reps)), [
        (25.0, 20),
        (50.0, 10),
        (55.0, 10),
        (55.0, 10),
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('only equal weights and repetitions combine, in recorded order', (
    tester,
  ) async {
    await preview(tester, [
      strength(55, 8),
      strength(25.5, 20),
      strength(55, 10),
      strength(25, 20),
      strength(55, 8),
    ]);
    final lines = [
      '55 kg × 8 回  /  2 セット',
      '25.5 kg × 20 回  /  1 セット',
      '55 kg × 10 回  /  1 セット',
      '25 kg × 20 回  /  1 セット',
    ];
    double? previousTop;
    for (final line in lines) {
      expect(find.text(line), findsOneWidget);
      final top = tester.getTopLeft(find.text(line)).dy;
      if (previousTop != null) expect(top, greaterThan(previousTop));
      previousTop = top;
    }
  });

  testWidgets('assistance, bodyweight and timed values retain separate lines', (
    tester,
  ) async {
    await preview(tester, [
      strength(30, 10, name: '補助運動', type: ExerciseRecordType.assistedReps),
      strength(20, 10, name: '補助運動', type: ExerciseRecordType.assistedReps),
      strength(30, 10, name: '補助運動', type: ExerciseRecordType.assistedReps),
      strength(0, 8, name: '腕立て', type: ExerciseRecordType.bodyweightReps),
      strength(0, 12, name: '腕立て', type: ExerciseRecordType.bodyweightReps),
      strength(0, 8, name: '腕立て', type: ExerciseRecordType.bodyweightReps),
      for (final seconds in [60, 90, 60])
        RecordedSet(
          exerciseName: 'プランク',
          recordType: ExerciseRecordType.timed,
          weight: 0,
          reps: 0,
          durationSeconds: seconds,
          completed: true,
        ),
    ]);
    for (final line in [
      '補助 30 kg × 10 回  /  2 セット',
      '補助 20 kg × 10 回  /  1 セット',
      '8 回  /  2 セット',
      '12 回  /  1 セット',
      '01:00 保持  /  2 セット',
      '01:30 保持  /  1 セット',
    ]) {
      expect(find.text(line), findsOneWidget);
    }
  });

  testWidgets('activity entries retain distance units and individual metrics', (
    tester,
  ) async {
    final sets = [
      for (final incline in [5.0, 10.0])
        RecordedSet(
          exerciseName: 'トレッドミル',
          exerciseId: 'treadmill',
          recordType: ExerciseRecordType.cardio,
          weight: 0,
          reps: 0,
          durationSeconds: 600,
          distanceKm: 1,
          inclinePercent: incline,
          completed: true,
        ),
      for (final weight in [10.0, 20.0])
        RecordedSet(
          exerciseName: '運搬',
          recordType: ExerciseRecordType.loadedDistance,
          weight: weight,
          reps: 0,
          distanceKm: 0.02,
          distanceUnit: 'm',
          completed: true,
        ),
    ];
    await preview(tester, sets);
    for (final set in sets) {
      expect(find.text(set.displaySummary), findsOneWidget);
    }
    expect(find.textContaining('セット'), findsNothing);
  });

  testWidgets('three value lines stay inside compact large-text share frame', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(335, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: WorkoutSharePage(
          workout: WorkoutRecord(
            date: DateTime(2026, 10, 6),
            sets: [
              strength(25, 20),
              strength(50, 10),
              strength(55, 10),
              strength(55, 10),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final frame = tester.getRect(
      find.byKey(const Key('sharePhotoDragSurface')),
    );
    for (final line in [
      '25 kg × 20 回  /  1 セット',
      '50 kg × 10 回  /  1 セット',
      '55 kg × 10 回  /  2 セット',
    ]) {
      final rect = tester.getRect(find.text(line));
      expect(rect.left, greaterThanOrEqualTo(frame.left));
      expect(rect.right, lessThanOrEqualTo(frame.right));
      expect(rect.top, greaterThanOrEqualTo(frame.top));
      expect(rect.bottom, lessThanOrEqualTo(frame.bottom));
    }
    expect(tester.takeException(), isNull);
  });
}
