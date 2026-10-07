import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/friends/friend_avatar.dart';
import 'package:setkeep/friends/friend_invite.dart';
import 'package:setkeep/friends/friends_ui.dart';
import 'package:setkeep/friends/friends_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:setkeep/profile/profile_preference.dart';
import 'package:setkeep/design/setkeep_navigation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'friends_mvp_test.dart' show FakeFriends;

class InviteFriends extends FakeFriends {
  @override
  bool get supportsProfileInvites => true;
  String? requested;
  String? nameReceived;
  String? relationship;
  bool invalid = false;
  int publications = 0;
  @override
  Future<Map<String, dynamic>> ensureProfile(String name) async {
    nameReceived = name;
    return {
      'display_name': ProfilePreference.socialName(name),
      'visibility': private ? 'private' : 'friends',
      'invite_code': inviteCode,
    };
  }

  @override
  Future<Map<String, dynamic>> invitePreview(String code) async {
    if (invalid || code == inviteCode) throw StateError('Invalid invite');
    return {'display_name': 'Preview friend', 'status': relationship};
  }

  @override
  Future<void> request(String code) async {
    requested = code;
  }

  @override
  Future<void> publish(List<Map<String, dynamic>> records) async {
    publications++;
  }
}

class MutualInviteFriends extends InviteFriends {
  @override
  bool get supportsMutualFriendSharing => true;
  @override
  Future<void> saveProfile(String name, String visibility) async {
    throw StateError('New server must use owner consent RPC');
  }
}

class OutgoingInviteFriends extends InviteFriends {
  @override
  Future<List<Map<String, dynamic>>> connections() async => [
    {
      'id': 'outgoing',
      'requester': 'me',
      'recipient': 'friend',
      'status': 'pending',
      'friend_name': 'Alice',
    },
  ];
}

class LegacyInviteFriends extends InviteFriends {
  @override
  bool get supportsProfileInvites => false;
  @override
  Future<Map<String, dynamic>> invitePreview(String code) =>
      throw StateError('This RPC is not deployed');
}

const inviteCode = '71000000-0000-0000-0000-000000000001';
const targetCode = '71000000-0000-0000-0000-000000000002';

Future<void> showOnPage(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'profile_display_name': 'My Page name',
    }),
  );
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.app_links/events'),
          (_) async => null,
        );
  });
  tearDown(FriendInviteStore.reset);
  testWidgets(
    'MVP-only invite confirms consent without calling unavailable preview RPC',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'profile_display_name': 'Synthetic',
      });
      final repo = LegacyInviteFriends();
      await tester.pumpWidget(
        MaterialApp(
          home: FriendsSettingsPage(
            repository: repo,
            history: const [],
            initialInvite: targetCode,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await showOnPage(tester, find.text('Send request'));
      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();
      expect(
        find.text('Send a friend request using this invite code'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('consentFriendsSharing')));
      await tester.pumpAndSettle();
      expect(repo.requested, targetCode);
      expect(repo.private, isFalse);
      expect(repo.publications, 1);
    },
  );
  test(
    'avatar account guard rejects stale account before reading or uploading',
    () async {
      final repo = FriendsRepository(
        SupabaseClient(
          'http://localhost',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
      await expectLater(
        repo.setAvatar(Uint8List.fromList([1]), expectedOwner: inviteCode),
        throwsStateError,
      );
    },
  );
  test('invite parser accepts registered scheme and UUID, rejects auth and foreign URLs', () {
    expect(
      FriendInviteLink.parse('setkeep://friend-invite/$targetCode'),
      targetCode,
    );
    expect(FriendInviteLink.parse(targetCode), targetCode);
    for (final text in [
      'setkeep://login-callback/$targetCode',
      'https://foreign.example/$targetCode',
      'javascript:bad',
      'setkeep://friend-invite/$targetCode?extra=1',
      'bad-code',
      'setkeep://friend-invite/$targetCode/extra',
    ]) {
      expect(FriendInviteLink.parse(text), isNull);
    }
    expect(
      FriendInviteLink.url(targetCode, configuredBaseUrl: ''),
      'setkeep://friend-invite/$targetCode',
    );
    expect(FriendInviteLink.parse(FriendInviteLink.url(targetCode)), targetCode);
  });
  test('valid invite survives login and app restart, invalid link leaves it intact', () async {
    await FriendInviteStore.capture('setkeep://friend-invite/$targetCode');
    await FriendInviteStore.capture('setkeep://login-callback/');
    expect(FriendInviteStore.pending.value, targetCode);
    await FriendInviteStore.reset();
    await FriendInviteStore.start();
    expect(FriendInviteStore.pending.value, targetCode);
    await FriendInviteStore.consume(targetCode);
    expect(FriendInviteStore.pending.value, isNull);
    expect(
      (await SharedPreferences.getInstance()).getString(
        'pending_friend_invite',
      ),
      isNull,
    );
  });
  test(
    'home chooses latest session per friend without mutating detail history',
    () {
      final input = [
        {'user_id': 'A', 'id': 'old', 'performed_at': '2026-10-01T00:00:00Z'},
        {'user_id': 'B', 'id': 'B', 'performed_at': '2026-10-02T00:00:00Z'},
        {
          'user_id': 'A',
          'id': 'latest',
          'performed_at': '2026-10-03T00:00:00Z',
        },
      ];
      expect(latestFriendWorkouts(input).map((row) => row['id']), [
        'latest',
        'B',
      ]);
      expect(input.length, 3);
      expect(input.first['id'], 'old');
    },
  );
  testWidgets(
    'shared tab background encloses icon and label and tab changes still work',
    (t) async {
      int? selected;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: SetkeepNavigation(
              selectedIndex: 0,
              onSelected: (i) => selected = i,
            ),
          ),
        ),
      );
      final pill = find.byKey(const ValueKey('selectedTab0'));
      expect(
        find.descendant(of: pill, matching: find.text('ホーム')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: pill, matching: find.byIcon(Icons.home_rounded)),
        findsOneWidget,
      );
      await t.tap(find.text('マイページ'));
      expect(selected, 4);
    },
  );
  testWidgets(
    'C settings omits own profile/privacy cards and cancellation preserves pending invite',
    (t) async {
      final repo = InviteFriends();
      await FriendInviteStore.capture('setkeep://friend-invite/$targetCode');
      await t.pumpWidget(
        MaterialApp(
          home: FriendsSettingsPage(
            repository: repo,
            history: const [],
            initialInvite: targetCode,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('My Page name'), findsNothing);
      expect(find.text('Friends & privacy'), findsNothing);
      expect(find.text('Record visibility'), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(
        find.byType(TextField),
        findsOneWidget,
      ); // Invite only, no duplicate name.
      await showOnPage(t, find.text('Send request'));
      await showOnPage(t, find.text('Send request'));
      await t.tap(find.text('Send request'));
      await t.pumpAndSettle();
      expect(
        find.text('Send a friend request to Preview friend'),
        findsOneWidget,
      );
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(repo.requested, isNull);
      expect(repo.private, isTrue);
      expect(repo.publications, 0);
      expect(FriendInviteStore.pending.value, targetCode);
      expect(find.byKey(const Key('connectWithoutSharing')), findsNothing);
      await showOnPage(t, find.text('Send request'));
      await t.tap(find.text('Send request'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('consentFriendsSharing')));
      await t.pumpAndSettle();
      expect(repo.requested, targetCode);
      expect(repo.private, isFalse);
      expect(repo.publications, 1);
    },
  );
  testWidgets(
    'explicit consent publishes; existing relationship does not request twice',
    (t) async {
      final repo = InviteFriends();
      await t.pumpWidget(
        MaterialApp(
          home: FriendsSettingsPage(
            repository: repo,
            history: const [],
            initialInvite: targetCode,
          ),
        ),
      );
      await t.pumpAndSettle();
      await showOnPage(t, find.text('Send request'));
      await showOnPage(t, find.text('Send request'));
      await t.tap(find.text('Send request'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('consentFriendsSharing')));
      await t.pumpAndSettle();
      expect(repo.private, isFalse);
      expect(repo.publications, 1);
      repo.requested = null;
      repo.relationship = 'accepted';
      await t.enterText(find.byType(TextField), targetCode);
      await showOnPage(t, find.text('Send request'));
      await t.tap(find.text('Send request'));
      await t.pumpAndSettle();
      expect(repo.requested, isNull);
      expect(
        find.text('You already have a pending request or connection'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'new server consent acknowledges only after explicit confirmation',
    (t) async {
      final repo = MutualInviteFriends();
      await t.pumpWidget(
        MaterialApp(
          home: FriendsSettingsPage(
            repository: repo,
            history: const [],
            initialInvite: targetCode,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(repo.sharingAcknowledgements, 0);
      expect(repo.private, isTrue);
      await showOnPage(t, find.text('Send request'));
      await showOnPage(t, find.text('Send request'));
      await t.tap(find.text('Send request'));
      await t.pumpAndSettle();
      expect(repo.sharingAcknowledgements, 0);
      await t.tap(find.byKey(const Key('consentFriendsSharing')));
      await t.pumpAndSettle();
      expect(repo.sharingAcknowledgements, 1);
      expect(repo.requested, targetCode);
      expect(repo.publications, 1);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('outgoing request exposes cancellation without accept action', (
    t,
  ) async {
    final repo = OutgoingInviteFriends();
    await t.pumpWidget(
      MaterialApp(
        home: FriendsSettingsPage(repository: repo, history: const []),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byTooltip('Accept'), findsNothing);
    await showOnPage(t, find.text('Alice'));
    expect(find.text('Pending'), findsOneWidget);
    expect(repo.accepted, isFalse);
    expect(repo.private, isTrue);
  });

  testWidgets('invalid and self invites do not form connections', (t) async {
    final repo = InviteFriends();
    await t.pumpWidget(
      MaterialApp(
        home: FriendsSettingsPage(repository: repo, history: const []),
      ),
    );
    await t.pumpAndSettle();
    await showOnPage(t, find.text('Send request'));
    await t.enterText(find.byType(TextField), inviteCode);
    await showOnPage(t, find.text('Send request'));
    await t.tap(find.text('Send request'));
    await t.pumpAndSettle();
    expect(repo.requested, isNull);
    await t.enterText(find.byType(TextField), 'invalid');
    await showOnPage(t, find.text('Send request'));
    await t.tap(find.text('Send request'));
    await t.pumpAndSettle();
    expect(find.text('Enter a valid invite code or link'), findsOneWidget);
    expect(repo.requested, isNull);
  });
  testWidgets('avatar re-encodes a square PNG and rejects oversized source', (
    t,
  ) async {
    await t.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..drawRect(
          const Rect.fromLTWH(0, 0, 400, 200),
          Paint()..color = Colors.green,
        );
      final picture = recorder.endRecording();
      final image = await picture.toImage(400, 200);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
      final result = await prepareFriendAvatar(bytes);
      final codec = await ui.instantiateImageCodec(result);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 256);
      expect(frame.image.height, 256);
      expect(result.length, lessThan(512 * 1024));
      await expectLater(
        prepareFriendAvatar(Uint8List(10 * 1024 * 1024 + 1)),
        throwsArgumentError,
      );
      frame.image.dispose();
      codec.dispose();
      image.dispose();
      picture.dispose();
      // Keep the canvas referenced until recording is complete.
      expect(canvas, isNotNull);
    });
  });
}
