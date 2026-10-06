import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setkeep/design/family_theme.dart';
import 'package:setkeep/friends/friend_like_inbox_page.dart';
import 'package:setkeep/main.dart';

import 'support/owner_likes_fixture.dart';

Widget app(Widget home) => MaterialApp(
  theme: familyTheme(),
  locale: const Locale('ja'),
  supportedLocales: const [Locale('ja'), Locale('en')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: home,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'closed comments and TRAINER still allow like bell, badge and exact own detail',
    (t) async {
      final friends = OwnerLikesFriends()
        ..inboxRows = [
          likeNotice(),
          likeNotice(
            author: 'friend-b',
            name: '別の友人',
            created: '2026-10-06T02:00:00Z',
          ),
        ];
      final inbox = OwnerLikeInbox(friends);
      await t.pumpWidget(
        app(
          DashboardPage(
            history: [ownLikeWorkout],
            selectedGym: null,
            onGymChanged: (_) {},
            onWorkoutCompleted: (_) async {},
            onWorkoutUpdated: (_, _) async {},
            onWorkoutDeleted: (_) async => false,
            workoutTemplates: const [],
            onTemplateSaved: (_) async {},
            onTemplateDeleted: (_) async {},
            workoutDraft: null,
            onDraftChanged: () async {},
            onDraftDiscarded: () async {},
            likeInboxRepository: inbox,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('trainerInboxBell')), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      await t.tap(find.byKey(const Key('trainerInboxBell')));
      await t.pumpAndSettle();
      expect(find.byType(FriendLikeInboxPage), findsOneWidget);
      expect(find.byKey(const Key('trainerNotificationSource')), findsNothing);
      expect(find.byKey(const Key('friendNotificationSource')), findsNothing);
      await t.tap(find.text('テスト友人さんがあなたのトレーニングにいいねしました'));
      await t.pumpAndSettle();
      expect(friends.resolvedRemoteIds, contains('old-remote-session'));
      expect(friends.records.length, 1);
      expect(find.byType(WorkoutDetailPage), findsOneWidget);
      expect(find.text('いいね 2'), findsOneWidget);
      expect(await inbox.unreadCount(), 1);
      expect(find.byKey(const Key('historyWorkoutComments')), findsNothing);
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      expect(find.byType(WorkoutDetailPage), findsNothing);
      expect(find.byType(FriendLikeInboxPage), findsOneWidget);
      expect(await inbox.unreadCount(), 1);
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);
      expect(friends.writes, 0);
      expect(friends.commentReads, 0);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('two workouts on the same day open the exact notified session', (
    t,
  ) async {
    final later = WorkoutRecord(
      date: DateTime(2020, 1, 1, 20),
      sets: ownLikeWorkout.sets,
      gymName: '自宅',
    );
    final friends = OwnerLikesFriends();
    final client = later.date.toIso8601String();
    friends.records[client] = {
      'id': 'later-remote-session',
      'user_id': 'me',
      'client_id': client,
    };
    friends.inboxRows = [
      likeNotice(workout: 'later-remote-session', clientId: client),
    ];
    final inbox = OwnerLikeInbox(friends);
    await t.pumpWidget(
      app(
        Scaffold(
          body: DashboardPage(
            history: [ownLikeWorkout, later],
            selectedGym: null,
            onGymChanged: (_) {},
            onWorkoutCompleted: (_) async {},
            onWorkoutUpdated: (_, _) async {},
            onWorkoutDeleted: (_) async => false,
            workoutTemplates: const [],
            onTemplateSaved: (_) async {},
            onTemplateDeleted: (_) async {},
            workoutDraft: null,
            onDraftChanged: () async {},
            onDraftDiscarded: () async {},
            likeInboxRepository: inbox,
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('trainerInboxBell')));
    await t.pumpAndSettle();
    await t.tap(find.text('テスト友人さんがあなたのトレーニングにいいねしました'));
    await t.pumpAndSettle();
    expect(
      t.widget<WorkoutDetailPage>(find.byType(WorkoutDetailPage)).workout.date,
      later.date,
    );
    expect(friends.resolvedRemoteIds, ['later-remote-session']);
    expect(friends.resolvedClients.toSet(), {client});
    expect(friends.records.length, 2);
    expect(await inbox.unreadCount(), 0);
    expect(friends.writes, 0);
    await t.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('revoked event cannot open a record or mark it read', (t) async {
    final friends = OwnerLikesFriends()..inboxRows = [likeNotice()];
    final inbox = OwnerLikeInbox(friends);
    var opens = 0;
    await t.pumpWidget(
      app(
        FriendLikeInboxPage(
          repository: inbox,
          onOpenWorkout: (_) async {
            opens++;
            return true;
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    friends.inboxRows = [];
    await t.tap(find.text('テスト友人さんがあなたのトレーニングにいいねしました'));
    await t.pumpAndSettle();
    expect(opens, 0);
    expect(find.text('いいね通知はまだありません'), findsOneWidget);
    expect(
      (await SharedPreferences.getInstance()).getStringList(inbox.key('me')),
      isNull,
    );
    await t.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'load failure clears old actor and logout clears inbox and bell',
    (t) async {
      final friends = OwnerLikesFriends()..inboxRows = [likeNotice()];
      final inbox = OwnerLikeInbox(friends);
      await t.pumpWidget(app(FriendLikeInboxPage(repository: inbox)));
      await t.pumpAndSettle();
      friends.failInbox = true;
      await t
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await t.pumpAndSettle();
      expect(find.text('テスト友人さんがあなたのトレーニングにいいねしました'), findsNothing);
      expect(find.textContaining('通知を読み込めませんでした'), findsOneWidget);
      friends.viewer = null;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(find.textContaining('通知を読み込めませんでした'), findsNothing);
      await t.pumpWidget(
        app(
          Scaffold(
            body: HomeHeader(
              likeRepository: inbox,
              showTrainerNotifications: false,
              onStart: (_) async {},
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('trainerInboxBell')), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
}
