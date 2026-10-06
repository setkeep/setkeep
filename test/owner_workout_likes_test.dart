import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setkeep/design/family_theme.dart';
import 'package:setkeep/friends/friend_avatar.dart';
import 'package:setkeep/friends/workout_comments.dart';
import 'package:setkeep/main.dart';

import 'support/owner_likes_fixture.dart';
import 'friend_release_feedback_test.dart' show PhotoClient, settlePhotos;

Future<void> ownDetail(
  WidgetTester t,
  OwnerLikesFriends repo, {
  double width = 390,
  double scale = 1,
}) async {
  t.view.physicalSize = Size(width, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MaterialApp(
      theme: familyTheme(),
      locale: const Locale('ja'),
      supportedLocales: const [Locale('ja'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: WorkoutDetailPage(
        workout: ownLikeWorkout,
        selectedGym: null,
        friendsRepository: repo,
        onWorkoutCompleted: (_) async {},
        onWorkoutUpdated: (_, _) async {},
        onWorkoutDeleted: (_) async => false,
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> refreshDetail(WidgetTester t) async {
  await t.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh();
  await t.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'own detail reads exact old remote session with comments closed',
    (t) async {
      final repo = OwnerLikesFriends();
      await ownDetail(t, repo);
      expect(find.text('いいね 2'), findsOneWidget);
      expect(find.byType(LikeAvatarStrip), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(LikeAvatarStrip),
          matching: find.byType(FriendAvatar),
        ),
        findsNWidgets(2),
      );
      expect(repo.resolvedClients.toSet(), {
        ownLikeWorkout.date.toIso8601String(),
      });
      expect(repo.resolvedRemoteIds, ['old-remote-session']);
      expect(repo.writes, 0);
      expect(repo.commentReads, 0);
      expect(find.byKey(const Key('historyWorkoutComments')), findsNothing);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.byType(WorkoutExerciseCardHeader), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('historyWorkoutLikes')),
          matching: find.byType(TextButton),
        ),
        findsNothing,
      );
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'zero, unpublished and logout never invent likes or publish records',
    (t) async {
      final repo = OwnerLikesFriends()..likes = [];
      await ownDetail(t, repo);
      expect(find.text('いいね 0'), findsOneWidget);
      repo.records.clear();
      await refreshDetail(t);
      expect(find.byKey(const Key('historyWorkoutLikes')), findsNothing);
      final reads = repo.resolvedClients.length;
      repo.viewer = null;
      await refreshDetail(t);
      expect(repo.resolvedClients.length, reads);
      expect(repo.writes, 0);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final foreign in ['owner', 'client']) {
    testWidgets('reject another $foreign before reading liker identities', (
      t,
    ) async {
      final repo = OwnerLikesFriends();
      repo.records.values.single[foreign == 'owner' ? 'user_id' : 'client_id'] =
          'other';
      await ownDetail(t, repo);
      expect(repo.resolvedRemoteIds, isEmpty);
      expect(find.byType(LikeAvatarStrip), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets(
    'reloading fails closed then recovers and deduplicates liker icons',
    (t) async {
      final repo = OwnerLikesFriends();
      await ownDetail(t, repo);
      expect(find.text('いいね 2'), findsOneWidget);
      repo.failLikes = true;
      await refreshDetail(t);
      expect(find.byType(LikeAvatarStrip), findsNothing);
      expect(find.textContaining('いいねを読み込めませんでした'), findsOneWidget);
      repo.failLikes = false;
      repo.likes = [
        {'user_id': 'friend-a', 'avatar_path': null},
        {'user_id': 'friend-a', 'avatar_path': null},
      ];
      await refreshDetail(t);
      expect(find.text('いいね 1'), findsOneWidget);
      expect(find.byType(FriendAvatar), findsOneWidget);
      expect(repo.writes, 0);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'account switch discards late likes without querying the new account',
    (t) async {
      final repo = OwnerLikesFriends()..likesReply = Completer();
      await ownDetail(t, repo);
      expect(repo.resolvedClients.length, 1);
      repo.viewer = 'other';
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      repo.likesReply!.complete([
        {'user_id': 'old-friend', 'avatar_path': null},
      ]);
      await t.pumpAndSettle();
      expect(repo.resolvedClients.length, 1);
      expect(find.byType(LikeAvatarStrip), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('record removed while likes load cannot show cached actors', (
    t,
  ) async {
    final repo = OwnerLikesFriends()..likesReply = Completer();
    await ownDetail(t, repo);
    repo.records.clear();
    repo.likesReply!.complete([
      {'user_id': 'friend', 'avatar_path': null},
    ]);
    await t.pumpAndSettle();
    expect(find.byType(LikeAvatarStrip), findsNothing);
    expect(repo.writes, 0);
    await t.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'large text narrow screen shows one count and at most four avatars',
    (t) async {
      final repo = OwnerLikesFriends()
        ..likes = [
          for (var i = 0; i < 12; i++)
            {'user_id': 'friend-$i', 'avatar_path': null},
        ];
      await ownDetail(t, repo, width: 320, scale: 2);
      await t.scrollUntilVisible(
        find.byKey(const Key('historyWorkoutLikeCount')),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('いいね 12'), findsOneWidget);
      expect(find.byType(FriendAvatar), findsNWidgets(4));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'refresh drops cached private liker photo without removing the old like',
    (t) async {
      debugNetworkImageHttpClientProvider = () => PhotoClient();
      addTearDown(() => debugNetworkImageHttpClientProvider = null);
      final repo = OwnerLikesFriends()
        ..likes = [
          {'user_id': 'friend-a', 'avatar_path': 'friend-a/photo.png'},
        ];
      await ownDetail(t, repo);
      await settlePhotos(t);
      final strip = find.byType(LikeAvatarStrip);
      expect(
        find.descendant(of: strip, matching: find.byType(Image)),
        findsOneWidget,
      );
      repo.likes = [
        {'user_id': 'friend-a', 'avatar_path': null},
      ];
      await refreshDetail(t);
      expect(find.text('いいね 1'), findsOneWidget);
      expect(
        find.descendant(of: strip, matching: find.byType(Image)),
        findsNothing,
      );
      expect(t.widget<FriendAvatar>(find.byType(FriendAvatar)).path, isNull);
      await t.pumpWidget(const SizedBox.shrink());
      debugNetworkImageHttpClientProvider = null;
    },
  );
  testWidgets(
    'background clears pictures; resume refreshes removed friend photo access',
    (t) async {
      final repo = OwnerLikesFriends();
      await ownDetail(t, repo);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await t.pump();
      expect(find.byType(LikeAvatarStrip), findsNothing);
      repo.likes = [
        {'user_id': 'former-friend', 'avatar_path': null},
      ];
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(find.text('いいね 1'), findsOneWidget);
      expect(t.widget<FriendAvatar>(find.byType(FriendAvatar)).path, isNull);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
}
