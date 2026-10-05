import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setkeep/main.dart';
import 'package:setkeep/friends/notification_sources_page.dart';

import 'friend_comment_notifications_test.dart'
    show CommentInbox, CommentFriends;
import 'support/trainer_delivery_flow.dart' show DeliveryRepository;

class HiddenTrainer extends DeliveryRepository {
  int unreadCalls = 0;
  @override
  Future<int> unreadCount() async {
    unreadCalls++;
    throw StateError('Hidden trainer inbox must not be fetched');
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'public bell counts only friends and hidden trainer data is untouched',
    (t) async {
      final trainer = HiddenTrainer();
      addTearDown(trainer.auth.close);
      final friends = CommentInbox(CommentFriends());
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeHeader(
              repository: trainer,
              friendRepository: friends,
              onStart: (_) async {},
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);
      expect(find.byTooltip('Notifications from friends'), findsOneWidget);
      expect(trainer.unreadCalls, 0);
      await t.tap(find.byKey(const Key('trainerInboxBell')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('friendNotificationSource')), findsOneWidget);
      expect(find.byKey(const Key('trainerNotificationSource')), findsNothing);
      expect(find.text('1 unread'), findsOneWidget);
      expect(find.textContaining('Could not load'), findsNothing);
      expect(trainer.unreadCalls, 0);
      expect(trainer.readMenuVersions, isEmpty);
      expect(trainer.readCommentVersions, isEmpty);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('friends-only header refreshes without a trainer repository', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeHeader(
            friendRepository: CommentInbox(CommentFriends()),
            onStart: (_) async {},
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'public notification page omits trainer source even with an existing link',
    (t) async {
      final trainer = HiddenTrainer();
      addTearDown(trainer.auth.close);
      await t.pumpWidget(
        MaterialApp(
          home: NotificationSourcesPage(
            trainer: trainer,
            friends: CommentInbox(CommentFriends()),
            onStart: (_) async {},
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('trainerNotificationSource')), findsNothing);
      await t
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await t.pumpAndSettle();
      expect(trainer.unreadCalls, 0);
      expect(find.text('1 unread'), findsOneWidget);
    },
  );
}
