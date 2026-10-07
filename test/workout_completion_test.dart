import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

String draft() => jsonEncode({
  'date': DateTime(2026, 9, 20, 18, 30).toIso8601String(),
  'elapsedSeconds': 120,
  'gymName': 'テストジム',
  'note': '保存確認',
  'exercises': [
    {
      'name': 'ベンチプレス',
      'exerciseId': 'bench_press',
      'bodyPart': '胸',
      'equipment': 'フリーウェイト',
      'sets': [
        {'weight': 65, 'reps': 8, 'completed': true},
        {'weight': 60, 'reps': 5, 'completed': true},
      ],
    },
  ],
});

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      activeWorkoutDraftStorageKey: draft(),
    });
    WorkoutUiPreference.completionCheckEnabled = true;
    WorkoutUiPreference.workoutTimerEnabled = false;
    WorkoutUiPreference.workoutDurationEnabled = true;
    RestTimerPreference.enabled = false;
  });

  for (final closeDialog in [false, true]) {
    testWidgets(
      'completion persists before dialog and survives restart close=$closeDialog',
      (t) async {
        await t.pumpWidget(const MaterialApp(home: HomeShell()));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('activeWorkoutDraftCard')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('completeWorkoutButton')));
        await t.pumpAndSettle();
        expect(find.text('トレーニング完了'), findsOneWidget);
        final prefs = await SharedPreferences.getInstance();
        final history = decodeWorkoutHistory(
          prefs.getString('workout_history'),
        );
        expect(history, hasLength(1));
        expect(history.single.sets, hasLength(2));
        expect(history.single.sets.last.weight, 60);
        expect(history.single.sets.last.reps, 5);
        expect(history.single.sets.first.weight, 65);
        expect(history.single.sets.first.reps, 8);
        expect(history.single.sets.first.exerciseId, 'bench_press');
        expect(history.single.date, DateTime(2026, 9, 20, 18, 30));
        expect(history.single.gymName, 'テストジム');
        expect(history.single.note, '保存確認');
        // Resuming adds real elapsed time; a slow test host may advance a second.
        expect(history.single.durationSeconds, greaterThanOrEqualTo(120));
        expect(prefs.getString(activeWorkoutDraftStorageKey), isNull);
        expect(find.textContaining('自己ベスト更新'), findsOneWidget);
        if (closeDialog) {
          await t.tap(find.byKey(const Key('completeWithoutSharingButton')));
          await t.pumpAndSettle();
          expect(
            decodeWorkoutHistory(prefs.getString('workout_history')),
            hasLength(1),
          );
        }
        // Dispose the entire application with the completion dialog still open.
        await t.pumpWidget(const SizedBox.shrink());
        await t.pumpAndSettle();
        await t.pumpWidget(const MaterialApp(home: HomeShell()));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('activeWorkoutDraftCard')), findsNothing);
        await t.tap(find.byIcon(Icons.calendar_month_outlined));
        await t.pumpAndSettle();
        expect(
          t.widget<MonthlyHistoryPage>(find.byType(MonthlyHistoryPage)).history,
          hasLength(1),
        );
      },
    );
  }

  testWidgets('completion waits for storage and rejects repeated presses', (
    t,
  ) async {
    final saving = Completer<void>();
    var calls = 0;
    await t.pumpWidget(
      MaterialApp(
        home: WorkoutPage(
          onSave: (record) async {
            calls++;
            await saving.future;
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    final press = t
        .widget<OutlinedButton>(find.byKey(const Key('completeWorkoutButton')))
        .onPressed!;
    press();
    press();
    await t.pump();
    expect(calls, 1);
    expect(find.text('トレーニング完了'), findsNothing);
    expect(
      (await SharedPreferences.getInstance()).getString(
        activeWorkoutDraftStorageKey,
      ),
      isNotNull,
    );
    saving.complete();
    await t.pumpAndSettle();
    expect(find.text('トレーニング完了'), findsOneWidget);
    expect(
      (await SharedPreferences.getInstance()).getString(
        activeWorkoutDraftStorageKey,
      ),
      isNull,
    );
    expect(calls, 1);
  });

  testWidgets('failed completion keeps draft and supports retry', (t) async {
    var calls = 0;
    await t.pumpWidget(
      MaterialApp(
        home: WorkoutPage(
          onSave: (_) async {
            if (++calls == 1) throw StateError('storage unavailable');
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('completeWorkoutButton')));
    await t.pumpAndSettle();
    expect(find.text('トレーニング完了'), findsNothing);
    expect(
      (await SharedPreferences.getInstance()).getString(
        activeWorkoutDraftStorageKey,
      ),
      isNotNull,
    );
    await t.tap(find.byKey(const Key('completeWorkoutButton')));
    await t.pumpAndSettle();
    expect(find.text('トレーニング完了'), findsOneWidget);
    expect(calls, 2);
  });
  testWidgets('share navigation never saves a completed workout again', (
    t,
  ) async {
    var saves = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => WorkoutPage(
                      onSave: (_) async {
                        saves++;
                      },
                    ),
                  ),
                ),
                child: const Text('開始'),
              ),
            );
          },
        ),
      ),
    );
    await t.tap(find.text('開始'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('completeWorkoutButton')));
    await t.pumpAndSettle();
    expect(saves, 1);
    await t.tap(find.byKey(const Key('completeAndPreviewShareButton')));
    await t.pumpAndSettle();
    expect(find.byType(WorkoutSharePage), findsOneWidget);
    expect(find.byType(WorkoutPage, skipOffstage: false), findsNothing);
    expect(saves, 1);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('開始'), findsOneWidget);
    expect(saves, 1);
  });
  for (final systemBack in [false, true]) {
    testWidgets(
      'completed share returns home with saved history systemBack=$systemBack',
      (t) async {
        await t.pumpWidget(const MaterialApp(home: HomeShell()));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('activeWorkoutDraftCard')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('completeWorkoutButton')));
        await t.pumpAndSettle();
        final prefs = await SharedPreferences.getInstance();
        expect(
          decodeWorkoutHistory(prefs.getString('workout_history')),
          hasLength(1),
        );
        expect(prefs.getString(activeWorkoutDraftStorageKey), isNull);
        await t.tap(find.byKey(const Key('completeAndPreviewShareButton')));
        await t.pumpAndSettle();
        expect(find.byType(WorkoutPage, skipOffstage: false), findsNothing);
        expect(find.byType(WorkoutSharePage), findsOneWidget);
        if (systemBack) {
          await t.binding.handlePopRoute();
        } else {
          await t.pageBack();
        }
        await t.pumpAndSettle();
        expect(find.byType(DashboardPage), findsOneWidget);
        expect(find.byType(WorkoutPage, skipOffstage: false), findsNothing);
        expect(find.byType(WorkoutSharePage), findsNothing);
        expect(find.byKey(const Key('activeWorkoutDraftCard')), findsNothing);
        expect(prefs.getString(activeWorkoutDraftStorageKey), isNull);
        expect(
          decodeWorkoutHistory(prefs.getString('workout_history')),
          hasLength(1),
        );
        await t.tap(find.byIcon(Icons.calendar_month_outlined));
        await t.pumpAndSettle();
        expect(
          t.widget<MonthlyHistoryPage>(find.byType(MonthlyHistoryPage)).history,
          hasLength(1),
        );
      },
    );
  }
}
