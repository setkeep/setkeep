import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:setkeep/friends/friends_repository.dart';
import 'package:setkeep/friends/friends_ui.dart';
import 'package:setkeep/main.dart';

class FakeFriends extends FriendsRepository {
  FakeFriends()
    : super(
        SupabaseClient(
          'http://localhost',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  @override
  String get userId => 'me';
  @override
  bool get commentsEnabled => true;
  bool private = true;
  bool fail = false;
  bool liked = false;
  bool accepted = false;
  bool removed = false;
  int sharingAcknowledgements = 0;
  @override
  bool get supportsMutualFriendSharing => false;
  @override
  Future<String?> myInviteCode() async => 'ABCD2345';
  @override
  Future<void> acknowledgeMutualSharing() async {
    sharingAcknowledgements++;
    private = false;
  }

  @override
  Future<List<Map<String, dynamic>>> likerAvatars(String id) async => [
    if (liked) {'user_id': 'me', 'avatar_path': null},
  ];
  @override
  Future<Map<String, dynamic>?> workoutForRecord(String clientId) async =>
      (await feed()).first;
  @override
  Future<Map<String, dynamic>?> workoutById(String id) async {
    final matches = (await feed()).where((row) => row['id'] == id);
    return matches.isEmpty ? null : matches.first;
  }

  final messages = <Map<String, dynamic>>[];
  @override
  Future<void> publish(List<Map<String, dynamic>> records) async {}
  @override
  Future<Map<String, dynamic>?> profile() async => {
    'display_name': 'Me',
    'visibility': private ? 'private' : 'friends',
    'invite_code': 'ABCD2345',
  };
  @override
  Future<Map<String, dynamic>> ensureProfile(String name) async =>
      (await profile())!;
  @override
  Future<void> saveProfile(String name, String visibility) async {
    private = visibility == 'private';
  }

  @override
  Future<List<Map<String, dynamic>>> connections() async => removed
      ? []
      : [
          {
            'id': 'request',
            'requester': 'friend',
            'recipient': 'me',
            'status': accepted ? 'accepted' : 'pending',
            'friend_name': 'Alice',
          },
        ];
  @override
  Future<void> accept(String id) async {
    accepted = true;
  }

  @override
  Future<void> remove(String id) async {
    removed = true;
  }

  @override
  Future<List<Map<String, dynamic>>> feed({String? owner}) async {
    if (fail) throw StateError('offline');
    return [
      {
        'id': 'workout',
        'user_id': 'friend',
        'performed_at': '2026-10-03T12:00:00Z',
        'duration_seconds': 60,
        'sets': [
          const RecordedSet(weight: 20, reps: 8, completed: true).toJson(),
        ],
        'friend_profiles': {'display_name': 'Alice'},
        'friend_likes': [
          if (liked) {'user_id': 'me'},
        ],
        'friend_comments': [],
      },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> comments(String id) async {
    if (fail) throw StateError('Access revoked');
    return messages;
  }

  @override
  Future<void> like(String id, bool value) async {
    liked = value;
  }

  @override
  Future<void> comment(String id, String body) async {
    messages.add({
      'id': 'c',
      'body': body,
      'user_id': 'me',
      'workout_id': id,
      'created_at': '2026-10-05T12:00:00Z',
      'friend_profiles': {'display_name': 'Me', 'avatar_path': null},
    });
  }

  @override
  bool get supportsIdempotentComments => true;
  @override
  Future<void> sendComment(
    String id,
    String body, {
    required String operationId,
  }) => comment(id, body);

  @override
  Future<void> deleteComment(String id) async {
    messages.clear();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'feed opens read-only detail, toggles one like, comments, clears on revoked access',
    (t) async {
      final repo = FakeFriends();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FriendsSection(history: const [], repository: repo),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Alice'));
      await t.pumpAndSettle();
      expect(find.text('Muscle heatmap'), findsOneWidget);
      await t.scrollUntilVisible(
        find.text('ベンチプレス'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('ベンチプレス'), findsOneWidget);
      await t.ensureVisible(find.text('Like 0'));
      await t.pumpAndSettle();
      expect(find.text('Like 0'), findsOneWidget);
      await t.tap(find.text('Like 0'));
      await t.pumpAndSettle();
      expect(repo.liked, true);
      await t.scrollUntilVisible(
        find.text('Like 1'),
        80,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Like 1'), findsOneWidget);
      await t.tap(find.text('Like 1'));
      await t.pumpAndSettle();
      expect(repo.liked, false);
      await t.ensureVisible(find.text('Comments 0'));
      await t.pumpAndSettle();
      await t.tap(find.text('Comments 0'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byType(TextField));
      await t.enterText(find.byType(TextField), 'Nice!');
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('sendWorkoutComment')));
      await t.tap(find.byKey(const Key('sendWorkoutComment')));
      await t.pumpAndSettle();
      expect(find.text('Nice!'), findsOneWidget);
      await t.tap(find.byTooltip('Comment actions'));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete').last);
      await t.pumpAndSettle();
      expect(find.text('Nice!'), findsNothing);
      await t.pageBack();
      await t.pumpAndSettle();
      repo.fail = true;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(find.text('ベンチプレス'), findsNothing);
      expect(find.text('Nice!'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'accept requires sharing confirmation and only recipient gets accept; removal refreshes',
    (t) async {
      final repo = FakeFriends();
      await t.pumpWidget(
        MaterialApp(
          home: FriendsSettingsPage(repository: repo, history: const []),
        ),
      );
      await t.pumpAndSettle();
      expect(repo.private, true);
      await t.scrollUntilVisible(
        find.byTooltip('Accept'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      expect(find.text('Alice'), findsOneWidget);
      await t.tap(find.byTooltip('Accept'));
      await t.pumpAndSettle();
      expect(repo.accepted, false);
      await t.tap(find.byKey(const Key('consentFriendsSharing')));
      await t.pumpAndSettle();
      expect(repo.private, false);
      expect(repo.accepted, true);
      expect(find.byTooltip('Accept'), findsNothing);
      await t.scrollUntilVisible(
        find.byTooltip('More'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('More'));
      await t.pumpAndSettle();
      await t.tap(find.text('Remove / cancel'));
      await t.pumpAndSettle();
      await t.tap(find.text('Remove'));
      await t.pumpAndSettle();
      expect(repo.removed, true);
      expect(find.text('Alice'), findsNothing);
    },
  );
  test('short comments reject whitespace and >140 unicode characters before network', () async {
    final repo = FriendsRepository(
      SupabaseClient(
        'http://localhost',
        'test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      ),
      commentsEnabled: true,
    );
    await expectLater(repo.comment('id', '   '), throwsArgumentError);
    await expectLater(
      repo.comment('id', List.filled(141, '😀').join()),
      throwsArgumentError,
    );
  });
}
