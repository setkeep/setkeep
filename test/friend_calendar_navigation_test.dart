import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/friends/friends_ui.dart';
import 'package:setkeep/main.dart';
import 'package:setkeep/design/setkeep_navigation.dart';

import 'friends_mvp_test.dart' show FakeFriends;

class CalendarFriends extends FakeFriends {
  final likedIds = <String>{};
  String? lastLikedId;
  String? lastCommentsId;
  bool withoutDuration = false;
  @override
  Future<void> like(String id, bool value) async {
    lastLikedId = id;
    if (value) {
      likedIds.add(id);
    } else {
      likedIds.remove(id);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> comments(String id) async {
    lastCommentsId = id;
    return [];
  }

  @override
  Future<List<Map<String, dynamic>>> likerAvatars(String id) async => [];

  @override
  Future<List<Map<String, dynamic>>> feed({String? owner}) async {
    final row = (await super.feed(owner: owner)).first;
    return [
      {
        ...row,
        'id': 'first',
        'duration_seconds': withoutDuration ? 0 : 60,
        'friend_likes': [
          if (likedIds.contains('first')) {'user_id': 'me'},
        ],
        'performed_at': DateTime(2026, 10, 3, 12).toUtc().toIso8601String(),
      },
      {
        ...row,
        'id': 'second',
        'duration_seconds': withoutDuration ? null : 120,
        'friend_likes': [
          if (likedIds.contains('second')) {'user_id': 'me'},
        ],
        'performed_at': DateTime(2026, 10, 3, 18).toUtc().toIso8601String(),
      },
      {
        ...row,
        'id': 'september',
        'friend_likes': [
          if (likedIds.contains('september')) {'user_id': 'me'},
        ],
        'performed_at': DateTime(2026, 9, 26, 12).toUtc().toIso8601String(),
      },
    ];
  }
}

void main() {
  testWidgets(
    'friend calendar filters duplicate sessions, empty days and month changes',
    (t) async {
      t.view.physicalSize = const Size(390, 1100);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final repository = CalendarFriends();
      await t.pumpWidget(
        MaterialApp(
          home: FriendActivityPage(
            repository: repository,
            owner: 'friend',
            selectedId: 'first',
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Muscle heatmap'), findsOneWidget);
      expect(find.byKey(const Key('monthlyCalendar')), findsOneWidget);
      await t.scrollUntilVisible(
        find.byKey(const Key('workoutDetailSummary')),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Workout 1'), findsNothing);
      expect(find.text('Workout 2'), findsNothing);
      final summary = t.widget<WorkoutDetailSummary>(
        find.byType(WorkoutDetailSummary),
      );
      expect(summary.workout.sets.length, 2);
      expect(summary.workout.exerciseNames.length, 1);
      expect(summary.workout.volume, 320);
      expect(summary.workout.durationSeconds, 180);
      await t.scrollUntilVisible(
        find.byKey(const Key('friendLike-second')),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await t.ensureVisible(find.byKey(const Key('friendLike-second')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('friendLike-second')));
      await t.pumpAndSettle();
      expect(repository.lastLikedId, 'second');
      expect(repository.likedIds, {'second'});
      expect(find.byKey(const Key('friendLike-second')), findsOneWidget);
      await t.scrollUntilVisible(
        find.byKey(const Key('openWorkoutComments-second')),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await t.ensureVisible(
        find.byKey(const Key('openWorkoutComments-second')),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('openWorkoutComments-second')));
      await t.pumpAndSettle();
      expect(repository.lastCommentsId, 'second');
      await t.pageBack();
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('calendarDay4')));
      await t.tap(find.byKey(const Key('calendarDay4')));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('No workouts on this day'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Workout 1'), findsNothing);
      await t.ensureVisible(find.byTooltip('Previous month'));
      await t.tap(find.byTooltip('Previous month'));
      await t.pumpAndSettle();
      expect(find.text('2026/9'), findsOneWidget);
      await t.ensureVisible(find.byKey(const Key('calendarDay26')));
      await t.tap(find.byKey(const Key('calendarDay26')));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byKey(const Key('workoutDetailSummary')),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await t.scrollUntilVisible(
        find.text('Like 0'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.text('Like 0'));
      await t.pumpAndSettle();
      expect(find.text('Like 1'), findsOneWidget);
      expect(repository.lastLikedId, 'september');
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'friend daily summary preserves missing durations and single day navigation',
    (t) async {
      t.view.physicalSize = const Size(390, 1100);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final repository = CalendarFriends()..withoutDuration = true;
      await t.pumpWidget(
        MaterialApp(
          home: FriendActivityPage(
            repository: repository,
            owner: 'friend',
            selectedId: 'second',
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byKey(const Key('workoutDetailSummary')),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      final summary = t.widget<WorkoutDetailSummary>(
        find.byType(WorkoutDetailSummary),
      );
      expect(summary.workout.durationSeconds, 0);
      expect(summary.workout.sets.length, 2);
      expect(find.text('—'), findsOneWidget);
      expect(find.text('Workout 1'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'all tabs keep My Page pill size at narrow width and enlarged text',
    (t) async {
      t.view.physicalSize = const Size(280, 600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      Size? baseline;
      for (
        var selected = 0;
        selected < SetkeepNavigation.labels.length;
        selected++
      ) {
        await t.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                bottomNavigationBar: SetkeepNavigation(
                  selectedIndex: selected,
                  onSelected: (_) {},
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        final size = t.getSize(find.byKey(ValueKey('selectedTab$selected')));
        baseline ??= size;
        expect(size, baseline);
        expect(t.takeException(), isNull);
      }
    },
  );
}
