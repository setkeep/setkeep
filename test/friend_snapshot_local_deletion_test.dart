import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setkeep/friends/friend_snapshot_journal.dart';
import 'package:setkeep/main.dart';

void main() {
  testWidgets(
    'signed-out HomeShell deletion persists owner intent through restart and Undo',
    (tester) async {
      final target = WorkoutRecord(
        friendOwnerUserId: '81000000-0000-0000-0000-000000000001',
        date: DateTime(2026, 10, 1),
        gymName: 'Local gym',
        note: 'Local note',
        sets: const [
          RecordedSet(
            exerciseName: 'ベンチプレス',
            weight: 20,
            reps: 8,
            completed: true,
          ),
        ],
      );
      final kept = WorkoutRecord(
        friendOwnerUserId: '81000000-0000-0000-0000-000000000001',
        date: DateTime(2026, 10, 2),
        gymName: 'Local gym',
        note: '',
        sets: const [
          RecordedSet(
            exerciseName: 'ベンチプレス',
            weight: 30,
            reps: 8,
            completed: true,
          ),
        ],
      );
      SharedPreferences.setMockInitialValues({
        'workout_history': jsonEncode([kept.toJson(), target.toJson()]),
      });
      final journal = FriendSnapshotJournal();
      await journal.rememberOwner('81000000-0000-0000-0000-000000000001');
      await tester.pumpWidget(const MaterialApp(home: HomeShell()));
      await tester.pumpAndSettle();
      final home = tester.widget<DashboardPage>(find.byType(DashboardPage));
      expect(await home.onWorkoutDeleted(target), true);
      final pending = await journal.batch(
        '81000000-0000-0000-0000-000000000001',
      );
      expect(pending.pending, true);
      expect(pending.deletions.keys, [target.date.toIso8601String()]);
      expect(pending.history!.map((r) => r['date']), [
        kept.date.toIso8601String(),
      ]);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(const MaterialApp(home: HomeShell()));
      await tester.pumpAndSettle();
      final restarted = tester.widget<DashboardPage>(
        find.byType(DashboardPage),
      );
      expect(restarted.history.map((r) => r.date), [kept.date]);
      expect(
        (await journal.batch('81000000-0000-0000-0000-000000000001')).pending,
        true,
      );
      await restarted.onWorkoutCompleted(target);
      expect(
        (await journal.batch('81000000-0000-0000-0000-000000000001')).deletions,
        isEmpty,
      );
      final stored = (await SharedPreferences.getInstance()).getString(
        'workout_history',
      )!;
      expect(decodeWorkoutHistory(stored).map((r) => r.toJson()), [
        kept.toJson(),
        target.toJson(),
      ]);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
