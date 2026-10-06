import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/owner_likes_fixture.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('inbox deduplicates active events and rejects self, foreign and absent records', () async {
    final friends = OwnerLikesFriends();
    final valid = likeNotice();
    friends.inboxRows = [
      valid,
      valid,
      likeNotice(created: '2026-10-06T03:00:00+00:00'),
      likeNotice(author: 'me'),
      likeNotice(owner: 'other'),
      likeNotice(created: 'unknown'),
      likeNotice(clientId: 'deleted-local'),
    ];
    final inbox = OwnerLikeInbox(friends);
    final rows = await inbox.notifications(
      clientIds: {ownLikeWorkout.date.toIso8601String()},
    );
    expect(rows.length, 1);
    expect(rows.single['display_name'], 'テスト友人');
    expect(
      await inbox.unreadCount(
        clientIds: {ownLikeWorkout.date.toIso8601String()},
      ),
      1,
    );
    expect(friends.writes, 0);
  });
  test(
    'read state is account/device local; unlike and relike form a new event',
    () async {
      final friends = OwnerLikesFriends()..inboxRows = [likeNotice()];
      final inbox = OwnerLikeInbox(friends);
      final id = (await inbox.notifications()).single['id'] as String;
      expect(await inbox.markRead(id), true);
      expect(await OwnerLikeInbox(friends).unreadCount(), 0);
      friends.inboxRows = [];
      expect(await inbox.markRead(id), false);
      expect(await inbox.unreadCount(), 0);
      friends.inboxRows = [likeNotice(created: '2026-10-06T03:01:00Z')];
      expect(await inbox.unreadCount(), 1);
      expect(await inbox.markRead(id), false);
      friends.viewer = 'other';
      friends.inboxRows = [likeNotice(owner: 'other')];
      expect(await inbox.unreadCount(), 1);
      SharedPreferences.setMockInitialValues({});
      friends.viewer = 'me';
      friends.inboxRows = [likeNotice()];
      expect(await inbox.unreadCount(), 1);
      expect(friends.writes, 0);
    },
  );
  test(
    'logout does not read and account change rejects late response',
    () async {
      final friends = OwnerLikesFriends()..viewer = null;
      final inbox = OwnerLikeInbox(friends);
      expect(await inbox.notifications(), isEmpty);
      expect(await inbox.markRead('stale'), false);
      expect(friends.inboxReads, 0);
      friends.viewer = 'me';
      friends.inboxReply = Completer();
      final pending = inbox.notifications();
      friends.viewer = 'other';
      friends.inboxReply!.complete([likeNotice()]);
      await expectLater(pending, throwsStateError);
      expect(
        (await SharedPreferences.getInstance()).getStringList(inbox.key('me')),
        isNull,
      );
    },
  );
  test(
    'concurrent reads from two inbox instances preserve both event ids',
    () async {
      final friends = OwnerLikesFriends()
        ..inboxRows = [likeNotice(), likeNotice(author: 'friend-b')];
      final first = OwnerLikeInbox(friends), second = OwnerLikeInbox(friends);
      final rows = await first.notifications();
      expect(
        await Future.wait([
          first.markRead(rows[0]['id'] as String),
          second.markRead(rows[1]['id'] as String),
        ]),
        [true, true],
      );
      expect(await first.unreadCount(), 0);
      expect(friends.writes, 0);
    },
  );
  test('friend removal and deleted/hidden local record invalidate stale notification', () async {
    final friends = OwnerLikesFriends()..inboxRows = [likeNotice()];
    final inbox = OwnerLikeInbox(friends);
    final id = (await inbox.notifications()).single['id'] as String;
    expect(await inbox.resolve(id, clientIds: {}), isNull);
    friends.inboxRows = [];
    expect(await inbox.resolve(id), isNull);
    expect(await inbox.markRead(id), false);
    expect(friends.writes, 0);
  });
}
