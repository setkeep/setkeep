import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:setkeep/friends/friend_avatar.dart';
import 'package:setkeep/friends/friend_comment_inbox.dart';
import 'package:setkeep/friends/friends_repository.dart';
import 'package:setkeep/friends/workout_comments.dart';

class CommentFriends extends FriendsRepository {
  CommentFriends()
    : super(
        SupabaseClient(
          'http://localhost',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  String viewer = 'me';
  bool sendingReady = true;
  @override
  bool get supportsIdempotentComments => sendingReady;
  @override
  String get userId => viewer;
  @override
  bool get commentsEnabled => true;
  bool accessible = true;
  bool failSend = false;
  bool loseReplyAfterCommit = false;
  final operationIds = <String>[];
  final receipts = <String, Map<String, String>>{};
  bool failLoad = false;
  bool noSharedRecord = false;
  Completer<void>? sending;
  int sends = 0;
  int deletions = 0;
  int publishes = 0;
  String? resolvedClientId;
  String? writtenWorkoutId;
  final messages = <Map<String, dynamic>>[
    {
      'id': 'other-message',
      'user_id': 'friend',
      'body': 'おつかれさま！\n次も頑張ろう',
      'created_at': '2026-10-03T12:03:00Z',
      'friend_profiles': {'display_name': '友人の登録名', 'avatar_path': null},
    },
    {
      'id': 'own-message',
      'user_id': 'me',
      'body': 'ありがとう！',
      'created_at': '2026-10-03T12:04:00Z',
      'friend_profiles': {'display_name': '本人の登録名', 'avatar_path': null},
    },
  ];
  @override
  Future<List<Map<String, dynamic>>> feed({String? owner}) async {
    if (failLoad) throw StateError('offline');
    return accessible
        ? [
            {'id': 'shared-session', 'user_id': 'friend'},
          ]
        : [];
  }

  @override
  Future<Map<String, dynamic>?> workoutById(String id) async {
    if (failLoad) throw StateError('offline');
    return accessible && id == 'shared-session'
        ? {'id': id, 'user_id': 'friend'}
        : null;
  }

  @override
  Future<List<Map<String, dynamic>>> comments(String id) async => [...messages];
  @override
  Future<void> sendComment(
    String id,
    String body, {
    required String operationId,
  }) async {
    sends++;
    operationIds.add(operationId);
    writtenWorkoutId = id;
    if (sending != null) await sending!.future;
    if (!accessible) throw StateError('Forbidden');
    final previous = receipts[operationId];
    if (previous != null) {
      if (previous['user_id'] != viewer ||
          previous['workout_id'] != id ||
          previous['body'] != body ||
          !messages.any((row) => row['id'] == operationId)) {
        throw StateError('Receipt mismatch or deleted comment');
      }
      return;
    }
    if (failSend) throw StateError('offline');
    messages.add({
      'id': operationId,
      'user_id': viewer,
      'body': body,
      'created_at': '2026-10-03T12:05:00Z',
      'friend_profiles': {'display_name': '本人の登録名', 'avatar_path': null},
    });
    receipts[operationId] = {'user_id': viewer, 'workout_id': id, 'body': body};
    if (loseReplyAfterCommit) {
      loseReplyAfterCommit = false;
      throw StateError('Reply lost after commit');
    }
  }

  @override
  Future<void> deleteComment(String id) async {
    deletions++;
    messages.removeWhere((row) => row['id'] == id);
  }

  @override
  Future<Map<String, dynamic>?> workoutForRecord(String clientId) async {
    resolvedClientId = clientId;
    return noSharedRecord
        ? null
        : {'id': 'shared-session', 'user_id': 'friend'};
  }

  @override
  Future<void> publish(List<Map<String, dynamic>> records) async {
    publishes++;
  }
}

class NotificationInbox extends FriendCommentInboxRepository {
  NotificationInbox(super.friends);
  bool available = true;
  String workoutId = 'shared-session';
  @override
  Future<List<Map<String, dynamic>>> comments() async => available
      ? [
          {'id': 'other-message', 'workout_id': workoutId},
        ]
      : [];
}

Future<void> open(WidgetTester t, CommentFriends repo) async {
  await t.pumpWidget(
    MaterialApp(
      home: WorkoutCommentsPage(
        repository: repo,
        workoutId: 'shared-session',
        ownerId: 'friend',
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'registered identities, timestamp and multiline bubbles face the author',
    (t) async {
      final repo = CommentFriends();
      await open(t, repo);
      expect(find.text('友人の登録名'), findsOneWidget);
      expect(find.text('本人の登録名'), findsOneWidget);
      expect(find.text('おつかれさま！\n次も頑張ろう'), findsOneWidget);
      expect(find.textContaining('10/3 '), findsNWidgets(2));
      final other = t.getCenter(find.text('おつかれさま！\n次も頑張ろう')).dx;
      final own = t.getCenter(find.text('ありがとう！')).dx;
      expect(other, lessThan(own));
      expect(find.byType(FriendAvatar), findsNWidgets(2));
      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('send failure keeps draft; repeated taps send only once', (
    t,
  ) async {
    final repo = CommentFriends()..failSend = true;
    await open(t, repo);
    await t.enterText(find.byKey(const Key('workoutCommentDraft')), '次も頑張ろう');
    await t.pump();
    await t.tap(find.byKey(const Key('sendWorkoutComment')));
    await t.pumpAndSettle();
    expect(repo.sends, 1);
    expect(
      t.widget<TextField>(find.byType(TextField)).controller!.text,
      '次も頑張ろう',
    );
    expect(find.textContaining('Your draft is kept'), findsOneWidget);
    repo.failSend = false;
    repo.sending = Completer<void>();
    await t.tap(find.byKey(const Key('sendWorkoutComment')));
    await t.pump();
    await t.tap(find.byKey(const Key('sendWorkoutComment')));
    await t.pump();
    expect(repo.sends, 2);
    repo.sending!.complete();
    await t.pumpAndSettle();
    expect(repo.messages.where((row) => row['body'] == '次も頑張ろう').length, 1);
    expect(repo.writtenWorkoutId, 'shared-session');
    expect(
      t.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets(
    'rune-based 140 limit rejects oversized combined emoji and whitespace',
    (t) async {
      final repo = CommentFriends();
      await open(t, repo);
      await t.enterText(find.byType(TextField), '   ');
      expect(
        t
            .widget<IconButton>(find.byKey(const Key('sendWorkoutComment')))
            .onPressed,
        isNull,
      );
      // Each emoji is two code points but one grapheme.
      await t.enterText(find.byType(TextField), List.filled(71, '👍🏽').join());
      await t.pump();
      expect(find.text('142/140'), findsOneWidget);
      expect(
        t
            .widget<IconButton>(find.byKey(const Key('sendWorkoutComment')))
            .onPressed,
        isNull,
      );
      await t.enterText(find.byType(TextField), List.filled(70, '👍🏽').join());
      await t.pump();
      expect(
        t
            .widget<IconButton>(find.byKey(const Key('sendWorkoutComment')))
            .onPressed,
        isNotNull,
      );
      await t.tap(find.byKey(const Key('sendWorkoutComment')));
      await t.pumpAndSettle();
      expect(repo.sends, 1);
    },
  );

  testWidgets('revocation before send clears messages and prevents write', (
    t,
  ) async {
    final repo = CommentFriends();
    await open(t, repo);
    await t.enterText(find.byType(TextField), 'draft');
    await t.pump();
    repo.accessible = false;
    await t.tap(find.byKey(const Key('sendWorkoutComment')));
    await t.pumpAndSettle();
    expect(repo.sends, 0);
    expect(find.text('ありがとう！'), findsNothing);
    expect(find.text('This thread is unavailable'), findsOneWidget);
    expect(
      t.widget<TextField>(find.byType(TextField)).controller!.text,
      'draft',
    );
  });

  testWidgets('account switch clears old thread on lifecycle refresh', (
    t,
  ) async {
    final repo = CommentFriends();
    await open(t, repo);
    repo.viewer = 'other-account';
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(find.text('ありがとう！'), findsNothing);
    expect(
      t
          .widget<IconButton>(find.byKey(const Key('sendWorkoutComment')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('notification revocation clears open thread and prevents write', (
    t,
  ) async {
    final repo = CommentFriends();
    final inbox = NotificationInbox(repo);
    var viewed = 0;
    await t.pumpWidget(
      MaterialApp(
        home: WorkoutCommentsPage(
          repository: repo,
          workoutId: 'shared-session',
          ownerId: 'friend',
          commentNotificationId: 'other-message',
          notificationRepository: inbox,
          onCommentViewed: () async {
            viewed++;
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(viewed, 1);
    inbox.available = false;
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(find.text('ありがとう！'), findsNothing);
    expect(find.text('This thread is unavailable'), findsOneWidget);
    expect(viewed, 1);
    expect(repo.sends, 0);
  });

  testWidgets('deleted or different-session notification never marks read', (
    t,
  ) async {
    final repo = CommentFriends();
    final inbox = NotificationInbox(repo)..workoutId = 'another-session';
    var viewed = 0;
    await t.pumpWidget(
      MaterialApp(
        home: WorkoutCommentsPage(
          repository: repo,
          workoutId: 'shared-session',
          ownerId: 'friend',
          commentNotificationId: 'other-message',
          notificationRepository: inbox,
          onCommentViewed: () async {
            viewed++;
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(viewed, 0);
    expect(find.text('ありがとう！'), findsNothing);
    inbox.workoutId = 'shared-session';
    repo.messages.removeWhere((row) => row['id'] == 'other-message');
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(viewed, 0);
    expect(find.text('ありがとう！'), findsNothing);
  });

  testWidgets(
    'notification scrolls to lazy offscreen target before marking read',
    (t) async {
      final repo = CommentFriends();
      final target = repo.messages.first;
      repo.messages.clear();
      repo.messages.addAll([
        for (var i = 0; i < 30; i++)
          {
            'id': 'earlier-$i',
            'user_id': 'me',
            'body': 'Earlier comment $i',
            'created_at': '2026-10-03T12:01:00Z',
          },
        target,
      ]);
      var viewed = 0;
      await t.pumpWidget(
        MaterialApp(
          home: WorkoutCommentsPage(
            repository: repo,
            workoutId: 'shared-session',
            ownerId: 'friend',
            commentNotificationId: 'other-message',
            notificationRepository: NotificationInbox(repo),
            onCommentViewed: () async {
              viewed++;
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('おつかれさま！\n次も頑張ろう'), findsOneWidget);
      expect(viewed, 1);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'failed notification read status stays retryable without losing thread',
    (t) async {
      final repo = CommentFriends();
      var calls = 0;
      await t.pumpWidget(
        MaterialApp(
          home: WorkoutCommentsPage(
            repository: repo,
            workoutId: 'shared-session',
            ownerId: 'friend',
            commentNotificationId: 'other-message',
            notificationRepository: NotificationInbox(repo),
            onCommentViewed: () async {
              calls++;
              throw StateError('offline');
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('おつかれさま！\n次も頑張ろう'), findsOneWidget);
      expect(find.textContaining('Could not save read status'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('lost reply reuses operation and creates exactly one comment', (
    t,
  ) async {
    final repo = CommentFriends()..loseReplyAfterCommit = true;
    await open(t, repo);
    await t.enterText(find.byType(TextField), 'Same attempt');
    await t.pump();
    await t.tap(find.byKey(const Key('sendWorkoutComment')));
    await t.pumpAndSettle();
    expect(
      repo.messages.where((row) => row['body'] == 'Same attempt').length,
      1,
    );
    expect(
      t.widget<TextField>(find.byType(TextField)).controller!.text,
      'Same attempt',
    );
    await t.tap(find.byKey(const Key('sendWorkoutComment')));
    await t.pumpAndSettle();
    expect(repo.operationIds.length, 2);
    expect(repo.operationIds[0], repo.operationIds[1]);
    expect(
      repo.operationIds[0],
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(
      repo.messages.where((row) => row['body'] == 'Same attempt').length,
      1,
    );
    expect(
      t.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets(
    'edited retry creates a new operation, deleted receipt never resurrects',
    (t) async {
      final repo = CommentFriends()..loseReplyAfterCommit = true;
      await open(t, repo);
      await t.enterText(find.byType(TextField), 'First body');
      await t.pump();
      await t.tap(find.byKey(const Key('sendWorkoutComment')));
      await t.pumpAndSettle();
      final firstOperation = repo.operationIds.single;
      await t.enterText(find.byType(TextField), 'Edited body');
      await t.pump();
      repo.loseReplyAfterCommit = true;
      await t.tap(find.byKey(const Key('sendWorkoutComment')));
      await t.pumpAndSettle();
      final secondOperation = repo.operationIds.last;
      expect(firstOperation, isNot(secondOperation));
      await repo.deleteComment(secondOperation);
      await t.tap(find.byKey(const Key('sendWorkoutComment')));
      await t.pumpAndSettle();
      expect(repo.operationIds.last, secondOperation);
      expect(
        repo.messages.where((row) => row['body'] == 'Edited body'),
        isEmpty,
      );
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        'Edited body',
      );
    },
  );

  testWidgets(
    'account change clears pending body and operation before any retry',
    (t) async {
      final repo = CommentFriends()..loseReplyAfterCommit = true;
      await open(t, repo);
      await t.enterText(find.byType(TextField), 'Private pending draft');
      await t.pump();
      await t.tap(find.byKey(const Key('sendWorkoutComment')));
      await t.pumpAndSettle();
      repo.viewer = 'other-account';
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(find.text('ありがとう！'), findsNothing);
      expect(repo.sends, 1);
    },
  );

  testWidgets(
    'old schema keeps thread readable and own deletion available, send awaits update',
    (t) async {
      final repo = CommentFriends()..sendingReady = false;
      await open(t, repo);
      expect(find.text('ありがとう！'), findsOneWidget);
      expect(find.text('Comment sending is being prepared'), findsOneWidget);
      expect(t.widget<TextField>(find.byType(TextField)).enabled, false);
      expect(
        t
            .widget<IconButton>(find.byKey(const Key('sendWorkoutComment')))
            .onPressed,
        isNull,
      );
      await t.tap(find.byType(PopupMenuButton<String>));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();
      expect(repo.deletions, 1);
      expect(repo.sends, 0);
    },
  );

  testWidgets('deletion requires own action and confirmation', (t) async {
    final repo = CommentFriends();
    await open(t, repo);
    await t.tap(find.byType(PopupMenuButton<String>));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    expect(repo.deletions, 0);
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    expect(repo.deletions, 1);
    expect(find.text('ありがとう！'), findsNothing);
    expect(find.text('おつかれさま！\n次も頑張ろう'), findsOneWidget);
  });

  testWidgets(
    'small screen, large Japanese text and keyboard keep send visible',
    (t) async {
      final repo = CommentFriends();
      repo.messages.first['body'] = List.filled(18, '長い日本語のコメント\n').join();
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      t.view.viewPadding = const FakeViewPadding(bottom: 34);
      t.view.viewInsets = const FakeViewPadding(bottom: 240);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetViewPadding);
      addTearDown(t.view.resetViewInsets);
      await t.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: WorkoutCommentsPage(
            repository: repo,
            workoutId: 'shared-session',
            ownerId: 'friend',
          ),
        ),
      );
      await t.pumpAndSettle();
      final rect = t.getRect(find.byKey(const Key('sendWorkoutComment')));
      expect(rect.bottom, lessThanOrEqualTo(400));
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'history opens exact existing thread without creating shared records',
    (t) async {
      final repo = CommentFriends();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HistoryWorkoutCommentsEntry(
              repository: repo,
              clientId: 'stable-local-session',
            ),
          ),
        ),
      );
      await t.tap(find.byKey(const Key('historyWorkoutComments')));
      await t.pumpAndSettle();
      expect(repo.resolvedClientId, 'stable-local-session');
      final page = t.widget<WorkoutCommentsPage>(
        find.byType(WorkoutCommentsPage),
      );
      expect(page.workoutId, 'shared-session');
      expect(repo.publishes, 0);
    },
  );

  testWidgets(
    'unpublished history stays local; empty thread and likes gracefully fallback',
    (t) async {
      final repo = CommentFriends()..noSharedRecord = true;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HistoryWorkoutCommentsEntry(
              repository: repo,
              clientId: 'unpublished',
            ),
          ),
        ),
      );
      await t.tap(find.byKey(const Key('historyWorkoutComments')));
      await t.pumpAndSettle();
      expect(find.byType(WorkoutCommentsPage), findsNothing);
      expect(repo.publishes, 0);
      repo.messages.clear();
      await open(t, repo);
      expect(find.text('No comments yet'), findsOneWidget);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LikeAvatarStrip(
              repository: repo,
              likes: [
                for (var i = 0; i < 20; i++) {'user_id': '$i'},
              ],
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(FriendAvatar), findsNWidgets(4));
      expect(
        find.descendant(
          of: find.byType(LikeAvatarStrip),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
      expect(t.takeException(), isNull);
    },
  );
}
