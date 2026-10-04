import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setkeep/main.dart';
import 'package:setkeep/friends/friend_comment_inbox.dart';
import 'package:setkeep/friends/notification_sources_page.dart';

import 'friends_mvp_test.dart' show FakeFriends;
import 'support/trainer_delivery_flow.dart' show DeliveryRepository;

class CommentFriends extends FakeFriends {
  @override
  String get userId => 'user-a';
}

class CommentInbox extends FriendCommentInboxRepository {
  CommentInbox(super.friends);
  @override
  String? get userId => friends.userId;
  bool available = true, fail = false;
  @override
  Future<List<Map<String, dynamic>>> comments() async {
    if (fail) throw StateError('offline');
    if (!available) return [];
    final read =
        (await SharedPreferences.getInstance()).getStringList(key(userId!)) ??
        [];
    return [
      {
        'id': 'c1',
        'workout_id': 'workout',
        'body': 'Synthetic friend comment',
        'friend_name': 'Synthetic friend',
        'created_at': '2026-10-04T00:00:00Z',
        'read': read.contains('c1'),
      },
    ];
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'bell groups friend/trainer unread, opens own comment and marks only viewed item',
    (tester) async {
      final friends = CommentFriends();
      friends.messages.add({
        'id': 'c1',
        'user_id': 'friend',
        'body': 'Synthetic friend comment',
      });
      final inbox = CommentInbox(friends);
      final trainer = DeliveryRepository();
      addTearDown(trainer.auth.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeHeader(
              repository: trainer,
              friendRepository: inbox,
              onStart: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('3'), findsOneWidget);
      await tester.tap(find.byKey(const Key('trainerInboxBell')));
      await tester.pumpAndSettle();
      expect(find.text('From friends'), findsOneWidget);
      expect(find.text('From your trainer'), findsOneWidget);
      expect(find.text('1 unread'), findsOneWidget);
      expect(find.text('2 unread'), findsOneWidget);
      expect(
        await trainer.unreadCount(),
        2,
      ); // Classification alone isn't read.
      await tester.tap(find.byKey(const Key('friendNotificationSource')));
      await tester.pumpAndSettle();
      expect(await inbox.unreadCount(), 1); // Listing alone isn't read.
      await tester.tap(
        find.byKey(const ValueKey('friendCommentNotification_c1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Synthetic friend comment'), findsOneWidget);
      expect(await inbox.unreadCount(), 0);
      expect(await trainer.unreadCount(), 2);
      // Private/removed/deleted notification disappears from an open detail too.
      inbox.available = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Synthetic friend comment'), findsNothing);
      expect(find.text('No visible workouts'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('friendCommentNotification_c1')),
        findsNothing,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'failed/stale friend notification does not mark read or open detail',
    (tester) async {
      final inbox = CommentInbox(CommentFriends());
      await tester.pumpWidget(
        MaterialApp(home: FriendCommentInboxPage(repository: inbox)),
      );
      await tester.pumpAndSettle();
      inbox.fail = true;
      await tester.tap(
        find.byKey(const ValueKey('friendCommentNotification_c1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Could not open comment. Retry.'), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getStringList(
          inbox.key('user-a'),
        ),
        isNull,
      );
      inbox.fail = false;
      inbox.available = false;
      await tester.tap(
        find.byKey(const ValueKey('friendCommentNotification_c1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('No comment notifications yet'), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getStringList(
          inbox.key('user-a'),
        ),
        isNull,
      );
    },
  );
}
