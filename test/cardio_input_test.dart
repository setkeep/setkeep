import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

RecordedSet cardio({
  String exerciseName = 'トレッドミル',
  String? exerciseId = 'treadmill',
  int durationSeconds = 0,
  double distanceKm = 0,
  double speedKmh = 0,
  double inclinePercent = 0,
}) => RecordedSet(
  exerciseName: exerciseName,
  exerciseId: exerciseId,
  bodyPart: '有酸素',
  recordType: ExerciseRecordType.cardio,
  weight: 0,
  reps: 0,
  durationSeconds: durationSeconds,
  distanceKm: distanceKm,
  speedKmh: speedKmh,
  inclinePercent: inclinePercent,
  completed: true,
);

Finder metric(String key) => find.descendant(
  of: find.byKey(Key(key)),
  matching: find.byType(TextFormField),
);

Future<void> enterMetric(WidgetTester tester, String key, String value) async {
  await tester.ensureVisible(metric(key));
  await tester.enterText(metric(key), value);
  await tester.pump();
}

void main() {
  test('average km/h handles decimals, missing values and legacy pace', () {
    expect(activitySpeedKmh(durationSeconds: 1800, distanceKm: 2.75), 5.5);
    expect(activitySpeedKmh(durationSeconds: 0, distanceKm: 2), 0);
    expect(activitySpeedKmh(durationSeconds: 60, distanceKm: 0), 0);
    expect(activitySpeedKmh(durationSeconds: 0, distanceKm: double.nan), 0);
    expect(
      activitySpeedKmh(durationSeconds: 60, distanceKm: 0, speedKmh: 6.5),
      6.5,
    );
    expect(
      activitySpeedKmh(
        durationSeconds: 0,
        distanceKm: 0,
        paceSecondsPerKm: 600,
      ),
      6,
    );
    final legacy = cardio(durationSeconds: 1800, distanceKm: 2.75).toJson()
      ..['paceSecondsPerKm'] = 600;
    final restored = RecordedSet.fromJson(legacy);
    expect(restored.activitySummary, contains('5.5 km/h'));
    expect(restored.activitySummary, isNot(contains('/km')));
    expect(restored.toJson()['paceSecondsPerKm'], 600);
  });

  testWidgets('time and distance recalculate average speed through save', (
    tester,
  ) async {
    WorkoutRecord? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: WorkoutPage(
          isEditing: true,
          history: const [],
          initialWorkout: WorkoutRecord(
            date: DateTime(2026, 10, 1),
            sets: [cardio()],
          ),
          onSave: (record) async => saved = record,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await enterMetric(tester, 'durationField0_', '30');
    await enterMetric(tester, 'distanceField0_', '2.75');
    expect(find.text('平均速度（km/h・自動）'), findsOneWidget);
    expect(find.text('ペース（分/km）'), findsNothing);
    await enterMetric(tester, 'durationField0_', '15');
    await tester.tap(find.byKey(const Key('completeWorkoutButton')));
    await tester.pumpAndSettle();
    expect(saved?.sets.single.speedKmh, 11);
    expect(saved?.sets.single.distanceKm, 2.75);
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'completion_check_enabled': true,
      'rest_timer_enabled': false,
    });
    WorkoutUiPreference.completionCheckEnabled = true;
    RestTimerPreference.enabled = false;
  });

  test('treadmill accepts duration OR distance; speed and incline are optional', () {
    expect(cardio(durationSeconds: 30 * 60).hasRequiredValues, isTrue);
    expect(cardio(distanceKm: 3.5).hasRequiredValues, isTrue);
    expect(cardio(distanceKm: 0.1).hasRequiredValues, isTrue);
    expect(cardio(speedKmh: 10, inclinePercent: 2).hasRequiredValues, isFalse);
    expect(cardio(inclinePercent: 0).hasRequiredValues, isFalse);
    expect(
      cardio(durationSeconds: 60, inclinePercent: 0).hasRequiredValues,
      isTrue,
    );
    expect(
      cardio(exerciseId: null, durationSeconds: 60).hasRequiredValues,
      isTrue,
    );
    // Other cardio activities retain their existing record-specific validation.
    expect(
      cardio(
        exerciseName: 'エアロバイク',
        exerciseId: 'exercise_bike',
        durationSeconds: 60,
      ).hasRequiredValues,
      isFalse,
    );
  });

  test(
    'decimal formatter preserves decimal separators and rejects a second dot',
    () {
      const formatter = DecimalNumberInputFormatter();
      TextEditingValue value(String text) => TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      for (final text in ['0.1', '0.5', '1.5', '2.5', '6.5']) {
        expect(formatter.formatEditUpdate(value('0'), value(text)).text, text);
      }
      expect(formatter.formatEditUpdate(value('0'), value('0．1')).text, '0.1');
      expect(formatter.formatEditUpdate(value('0'), value('0,1')).text, '0.1');
      expect(
        formatter.formatEditUpdate(value('1.2'), value('1.2.3')).text,
        '1.2',
      );
    },
  );

  testWidgets(
    'treadmill distance, speed and incline keep decimals through save',
    (tester) async {
      WorkoutRecord? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutPage(
            isEditing: true,
            history: const [],
            initialWorkout: WorkoutRecord(
              date: DateTime(2026, 10, 1),
              sets: [cardio()],
            ),
            onSave: (record) async => saved = record,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('速度（km/h・任意）'), findsOneWidget);
      expect(find.text('傾斜（%・任意）'), findsOneWidget);
      await enterMetric(tester, 'distanceField0_', '0.');
      expect(
        tester
            .widget<TextFormField>(metric('distanceField0_'))
            .controller!
            .text,
        '0.',
      );
      await enterMetric(tester, 'distanceField0_', '0.1');
      await enterMetric(tester, 'speedField0_', '6.5');
      await enterMetric(tester, 'inclineField0_', '2.5');
      await tester.tap(find.byKey(const Key('completeWorkoutButton')));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved!.sets.single.distanceKm, 0.1);
      expect(saved!.sets.single.speedKmh, 6.5);
      expect(saved!.sets.single.inclinePercent, 2.5);
    },
  );

  testWidgets(
    'treadmill validation message stays inside content with keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1;
      tester.view.viewPadding = const FakeViewPadding(bottom: 24);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutPage(
            isEditing: true,
            history: const [],
            initialWorkout: WorkoutRecord(
              date: DateTime(2026, 10, 1),
              sets: [cardio()],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.showKeyboard(metric('distanceField0_'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('completeWorkoutButton')));
      await tester.pump();
      expect(find.text('時間または距離を入力してください'), findsOneWidget);
      final snack = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snack.behavior, SnackBarBehavior.floating);
      final messageRect = tester.getRect(find.text('時間または距離を入力してください'));
      expect(messageRect.bottom, lessThan(760 - 280));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('treadmill saves duration alone with optional metrics unset', (
    tester,
  ) async {
    WorkoutRecord? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: WorkoutPage(
          isEditing: true,
          history: const [],
          initialWorkout: WorkoutRecord(
            date: DateTime(2026, 10, 1),
            sets: [cardio()],
          ),
          onSave: (record) async => saved = record,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await enterMetric(tester, 'durationField0_', '30');
    await tester.tap(find.byKey(const Key('completeWorkoutButton')));
    await tester.pumpAndSettle();
    expect(saved?.sets.single.durationSeconds, 1800);
    expect(saved?.sets.single.distanceKm, 0);
    expect(saved?.sets.single.speedKmh, 0);
    expect(saved?.sets.single.inclinePercent, 0);
  });

  testWidgets('validation clears Android navigation area without keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);
    await tester.pumpWidget(
      MaterialApp(
        home: WorkoutPage(
          isEditing: true,
          history: const [],
          initialWorkout: WorkoutRecord(
            date: DateTime(2026, 10, 1),
            sets: [cardio()],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('completeWorkoutButton')));
    await tester.pump();
    final messageRect = tester.getRect(find.text('時間または距離を入力してください'));
    expect(messageRect.bottom, lessThan(760 - 24));
    expect(tester.takeException(), isNull);
  });
}
