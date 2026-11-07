import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setkeep/design/workout_month_calendar.dart';
import 'package:setkeep/friends/friends_ui.dart';
import 'package:setkeep/friends/workout_comments.dart';
import 'package:setkeep/main.dart';

import 'friends_mvp_test.dart' show FakeFriends;

Map<String, dynamic> _record(
  String id, {
  required String clientId,
  required String performedAt,
  int sets = 1,
  int duration = 60,
}) => {
  'id': id,
  'user_id': 'friend',
  'client_id': clientId,
  'performed_at': performedAt,
  'duration_seconds': duration,
  'sets': [
    for (var i = 0; i < sets; i++)
      const RecordedSet(weight: 20, reps: 8, completed: true).toJson(),
  ],
  'friend_profiles': {'display_name': 'Alice'},
  'friend_likes': <Map<String, dynamic>>[],
  'friend_comments': <Map<String, dynamic>>[],
};

List<Map<String, dynamic>> _historyAcrossLimit({int recentCount = 999}) => [
  for (var i = 0; i < recentCount; i++)
    _record(
      'recent-$i',
      clientId: '2026-11-06T12:00:00.000',
      performedAt: '2026-11-06T12:00:00Z',
    ),
  // Match the feed's performed_at descending order. With 999 recent records,
  // the afternoon session is row 1000 and the morning session is row 1001.
  _record(
    'old-afternoon',
    clientId: '2026-10-03T18:00:00.000',
    performedAt: '2026-10-03T18:00:00Z',
    sets: 3,
    duration: 180,
  ),
  _record(
    'old-morning',
    clientId: '2026-10-03T09:00:00.000',
    performedAt: '2026-10-03T09:00:00Z',
    sets: 2,
    duration: 120,
  ),
];

class HistoryNavigationFriends extends FakeFriends {
  HistoryNavigationFriends({List<Map<String, dynamic>>? records})
    : records = records ?? _historyAcrossLimit();

  final List<Map<String, dynamic>> records;
  final likedIds = <String>{};
  final likeWrites = <String>[];
  final commentReads = <String>[];
  String viewer = 'me';
  bool sharedVisible = true;
  bool historyFails = false;
  int feedReads = 0;
  int historyReads = 0;
  int exactReads = 0;

  @override
  String get userId => viewer;

  List<Map<String, dynamic>> _visibleRows(String? owner) => [
    if (sharedVisible)
      for (final row in records)
        if (owner == null || row['user_id'] == owner)
          {
            ...row,
            'friend_likes': [
              if (likedIds.contains(row['id'])) {'user_id': viewer},
            ],
          },
  ];

  @override
  Future<List<Map<String, dynamic>>> feed({String? owner}) async {
    feedReads++;
    return _visibleRows(owner).take(1000).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> history({required String owner}) async {
    historyReads++;
    // The repository must throw if a later page fails, never return page one.
    if (historyFails) throw StateError('Second history page failed');
    return _visibleRows(owner);
  }

  @override
  Future<Map<String, dynamic>?> historyWorkoutById(
    String id,
    String owner,
  ) async {
    exactReads++;
    if (id != 'old-afternoon') return null;
    final matches = _visibleRows(owner).where((row) => row['id'] == id);
    return matches.isEmpty ? null : matches.single;
  }

  @override
  Future<Map<String, dynamic>?> workoutById(String id) async {
    final matches = _visibleRows(null).where((row) => row['id'] == id);
    return matches.isEmpty ? null : matches.single;
  }

  @override
  Future<void> like(String id, bool value) async {
    likeWrites.add(id);
    if (value) {
      likedIds.add(id);
    } else {
      likedIds.remove(id);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> comments(String id) async {
    commentReads.add(id);
    return [];
  }

  @override
  Future<List<Map<String, dynamic>>> likerAvatars(String id) async => [];
}

Future<void> _showHistory(
  WidgetTester t,
  HistoryNavigationFriends repository,
  TargetPlatform platform, {
  String selectedId = 'old-afternoon',
}) async {
  t.view.physicalSize = const Size(390, 1100);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      home: FriendActivityPage(
        repository: repository,
        owner: 'friend',
        selectedId: selectedId,
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> _reveal(WidgetTester t, Finder target) async {
  // Start at the top so returning from a later session also finds lazily built
  // calendar/summary children, not only controls below the current position.
  t.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
  await t.pumpAndSettle();
  await t.scrollUntilVisible(
    target,
    150,
    scrollable: find.byType(Scrollable).first,
  );
  await t.ensureVisible(target);
  await t.pumpAndSettle();
}

Future<void> _tap(WidgetTester t, Finder target) async {
  await _reveal(t, target);
  await t.tap(target);
  await t.pumpAndSettle();
}

Future<WorkoutMonthCalendar> _calendar(WidgetTester t) async {
  await _reveal(t, find.byKey(const Key('monthlyCalendar')));
  return t.widget<WorkoutMonthCalendar>(find.byType(WorkoutMonthCalendar));
}

Future<void> _expectSummary(
  WidgetTester t, {
  int sets = 5,
  double volume = 800,
  int duration = 300,
  DateTime? date,
}) async {
  await _reveal(t, find.byKey(const Key('workoutDetailSummary')));
  final summary = t.widget<WorkoutDetailSummary>(
    find.byType(WorkoutDetailSummary),
  );
  expect(summary.workout.sets.length, sets);
  expect(summary.workout.exerciseNames.length, 1);
  expect(summary.workout.volume, volume);
  expect(summary.workout.durationSeconds, duration);
  expect(summary.workout.date, date ?? DateTime(2026, 10, 3));
}

Future<void> _refresh(WidgetTester t) async {
  await t.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh();
  await t.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      '${platform.name}: full old day survives retap, social actions and month round trip',
      (t) async {
        final repository = HistoryNavigationFriends();
        await _showHistory(t, repository, platform);
        await _expectSummary(t);
        expect((await _calendar(t)).selectedDay, DateTime(2026, 10, 3));

        // Clearing the selected record ID must not change the day's totals.
        await _tap(t, find.byKey(const Key('calendarDay3')));
        await _expectSummary(t);
        await _tap(t, find.byKey(const Key('calendarDay3')));
        await _expectSummary(t);

        for (final id in ['old-morning', 'old-afternoon']) {
          await _tap(t, find.byKey(ValueKey('friendLike-$id')));
          expect(repository.likeWrites.last, id);
          expect(repository.likedIds, contains(id));
          await _expectSummary(t);

          repository.commentReads.clear();
          await _tap(t, find.byKey(ValueKey('openWorkoutComments-$id')));
          expect(
            t
                .widget<WorkoutCommentsPage>(find.byType(WorkoutCommentsPage))
                .workoutId,
            id,
          );
          expect(repository.commentReads, isNotEmpty);
          expect(repository.commentReads, everyElement(id));
          await t.pageBack();
          await t.pumpAndSettle();
          await _expectSummary(t);
          expect((await _calendar(t)).selectedDay, DateTime(2026, 10, 3));
        }
        expect(repository.likedIds, {'old-morning', 'old-afternoon'});
        expect(repository.likeWrites, ['old-morning', 'old-afternoon']);

        await _tap(t, find.byTooltip('Next month'));
        final november = await _calendar(t);
        expect(november.visibleMonth, DateTime(2026, 11));
        expect(november.selectedDay, isNull);
        expect(find.byType(WorkoutDetailSummary), findsNothing);
        await _tap(t, find.byKey(const Key('calendarDay4')));
        await _reveal(t, find.text('No workouts on this day'));
        expect(find.text('No workouts on this day'), findsOneWidget);
        expect(find.byType(WorkoutDetailSummary), findsNothing);

        await _tap(t, find.byTooltip('Previous month'));
        expect((await _calendar(t)).visibleMonth, DateTime(2026, 10));
        await _tap(t, find.byKey(const Key('calendarDay3')));
        await _expectSummary(t);
        await _refresh(t);
        await _expectSummary(t);
        expect(repository.historyReads, greaterThan(1));
        expect(repository.feedReads, 0);
        expect(repository.exactReads, 0);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      '${platform.name}: selected session beyond the feed survives tapping its day',
      (t) async {
        final repository = HistoryNavigationFriends(
          records: _historyAcrossLimit(recentCount: 1000),
        );
        await _showHistory(t, repository, platform);
        // Old UI can open the selected afternoon via its exact-ID fallback.
        // Do not assert the full initial total here: specifically catch losing
        // that already-opened session when the calendar clears selectedId.
        await _reveal(t, find.byKey(const Key('friendLike-old-afternoon')));
        expect(
          find.byKey(const Key('friendLike-old-afternoon')),
          findsOneWidget,
        );
        await _tap(t, find.byKey(const Key('calendarDay3')));
        expect(
          (await _calendar(t)).recordedDates,
          contains(DateTime(2026, 10, 3, 18)),
          reason: 'Retapping must retain the afternoon session beyond the feed',
        );
        await _reveal(t, find.byKey(const Key('friendLike-old-afternoon')));
        expect(
          find.byKey(const Key('friendLike-old-afternoon')),
          findsOneWidget,
        );
        await _expectSummary(t);
        expect(repository.feedReads, 0);
        expect(repository.exactReads, 0);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      '${platform.name}: refresh removes revoked history and its daily totals',
      (t) async {
        final repository = HistoryNavigationFriends();
        await _showHistory(t, repository, platform);
        await _expectSummary(t);
        repository.sharedVisible = false;
        await _refresh(t);
        await _reveal(t, find.text('No visible workouts'));
        expect(find.text('No visible workouts'), findsOneWidget);
        expect(find.text('Alice'), findsNothing);
        expect(find.byType(WorkoutDetailSummary), findsNothing);
        expect(find.byKey(const Key('friendLike-old-morning')), findsNothing);
        expect(find.byKey(const Key('friendLike-old-afternoon')), findsNothing);
        expect((await _calendar(t)).recordedDates, isEmpty);
        await _tap(t, find.byKey(const Key('calendarDay3')));
        expect(find.byType(WorkoutDetailSummary), findsNothing);
        expect(repository.historyReads, greaterThan(1));
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      '${platform.name}: later-page failure clears totals and retry restores the full day',
      (t) async {
        final repository = HistoryNavigationFriends();
        await _showHistory(t, repository, platform);
        await _expectSummary(t);
        repository.historyFails = true;
        await _refresh(t);
        expect(
          find.text('Could not load or complete action. Retry'),
          findsOneWidget,
        );
        expect(find.byType(WorkoutDetailSummary), findsNothing);
        expect(find.byKey(const Key('friendLike-old-afternoon')), findsNothing);
        expect((await _calendar(t)).recordedDates, isEmpty);
        repository.historyFails = false;
        await _refresh(t);
        await _expectSummary(t);
        expect((await _calendar(t)).selectedDay, DateTime(2026, 10, 3));
        expect(repository.historyReads, greaterThanOrEqualTo(3));
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      '${platform.name}: account change clears the previous viewers history',
      (t) async {
        final repository = HistoryNavigationFriends();
        await _showHistory(t, repository, platform);
        await _expectSummary(t);
        final reads = repository.historyReads;
        repository.viewer = 'another-account';
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await t.pumpAndSettle();
        await _reveal(t, find.text('No visible workouts'));
        expect(find.text('No visible workouts'), findsOneWidget);
        expect(find.text('Alice'), findsNothing);
        expect(find.byType(WorkoutDetailSummary), findsNothing);
        expect((await _calendar(t)).recordedDates, isEmpty);
        expect(repository.historyReads, reads);
        await _tap(t, find.byKey(const Key('calendarDay3')));
        expect(find.byType(WorkoutDetailSummary), findsNothing);
        expect(repository.historyReads, reads);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      '${platform.name}: year-end UTC and offset client IDs stay on their civil day',
      (t) async {
        final repository = HistoryNavigationFriends(
          records: [
            for (final suffix in ['Z', '+09:00', '-07:00'])
              _record(
                'civil-$suffix',
                clientId: '2026-12-31T23:30:00$suffix',
                performedAt: '2027-01-01T06:30:00Z',
              ),
          ],
        );
        await _showHistory(t, repository, platform, selectedId: 'civil-Z');
        final december = await _calendar(t);
        expect(december.visibleMonth, DateTime(2026, 12));
        expect(december.selectedDay, DateTime(2026, 12, 31));
        expect(december.recordedDates.length, 3);
        for (final date in december.recordedDates) {
          expect([date.year, date.month, date.day], [2026, 12, 31]);
        }
        await _expectSummary(
          t,
          sets: 3,
          volume: 480,
          duration: 180,
          date: DateTime(2026, 12, 31),
        );
        await _tap(t, find.byKey(const Key('calendarDay31')));
        await _expectSummary(
          t,
          sets: 3,
          volume: 480,
          duration: 180,
          date: DateTime(2026, 12, 31),
        );
        await _tap(t, find.byTooltip('Next month'));
        expect((await _calendar(t)).visibleMonth, DateTime(2027, 1));
        await _tap(t, find.byKey(const Key('calendarDay1')));
        await _reveal(t, find.text('No workouts on this day'));
        expect(find.byType(WorkoutDetailSummary), findsNothing);
        await _tap(t, find.byTooltip('Previous month'));
        await _tap(t, find.byKey(const Key('calendarDay31')));
        await _expectSummary(
          t,
          sets: 3,
          volume: 480,
          duration: 180,
          date: DateTime(2026, 12, 31),
        );
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
