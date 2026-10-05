import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/friends/friend_invite.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const base = 'https://boredota.com/invite';
  const uuid = '11111111-2222-3333-4444-555555555555';
  setUp(() async {
    await FriendInviteStore.reset();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(FriendInviteStore.reset);

  test('short code normalizes case and one readable separator', () {
    for (final value in ['abCd2345', 'ABCD-2345', ' abcd2345 ']) {
      expect(FriendInviteLink.parse(value), 'ABCD2345');
    }
    for (final invalid in [
      'ABCDO234',
      'ABCDI234',
      'ABCDL234',
      'ABCD0234',
      'ABCD1234',
      'ABC D2345',
      'AB-CD2345',
      'ABCD234',
      'ABCD23456',
      'ＡＢＣＤ２３４５',
    ]) {
      expect(FriendInviteLink.parse(invalid), isNull, reason: invalid);
    }
    expect(
      FriendInviteLink.shortCodeAlphabet.split('').toSet().length,
      FriendInviteLink.shortCodeAlphabet.length,
    );
  });

  test('UUIDs and registered app links remain compatible', () {
    expect(FriendInviteLink.parse(uuid), uuid);
    expect(FriendInviteLink.parse('setkeep://friend-invite/$uuid'), uuid);
    expect(
      FriendInviteLink.parse('setkeep://friend-invite/abcd2345'),
      'ABCD2345',
    );
    expect(
      FriendInviteLink.url('abcd-2345', configuredBaseUrl: ''),
      'setkeep://friend-invite/ABCD2345',
    );
    expect(() => FriendInviteLink.url('INVALID0'), throwsArgumentError);
  });

  test('HTTPS invitation uses exact configured origin and query route', () {
    final url = FriendInviteLink.url('ABCD2345', configuredBaseUrl: base);
    expect(url, '$base?code=ABCD2345');
    expect(FriendInviteLink.parse(url, configuredBaseUrl: base), 'ABCD2345');
    expect(
      FriendInviteLink.parse('$base/$uuid', configuredBaseUrl: base),
      uuid,
    );
    expect(
      FriendInviteLink.parse('$base?code=$uuid', configuredBaseUrl: base),
      uuid,
    );
    expect(
      FriendInviteLink.parse('$base?code=abcd-2345', configuredBaseUrl: base),
      'ABCD2345',
    );
    expect(FriendInviteLink.url('ABCD2345', configuredBaseUrl: '$base/'), url);
  });

  test(
    'foreign routes, auth URLs, ambiguous and malformed links are rejected',
    () {
      for (final invalid in [
        'https://foreign.example/invite?code=ABCD2345',
        'http://boredota.com/invite?code=ABCD2345',
        'https://boredota.com:444/invite?code=ABCD2345',
        'https://boredota.com/other?code=ABCD2345',
        'https://boredota.com/invite.html?code=ABCD2345',
        'https://boredota.com/invite/?code=ABCD2345',
        'https://boredota.com/invite?code=ABCD2345&code=QRST6789',
        'https://boredota.com/invite?code=ABCD2345&next=login',
        'https://boredota.com/invite?%63ode=ABCD2345',
        'https://boredota.com/invite?code=ABCD%32345',
        'https://boredota.com/invite?code=ABCD2345#fragment',
        'https://someone@boredota.com/invite?code=ABCD2345',
        'https://boredota.com/invite/$uuid/other',
        'setkeep://login-callback/ABCD2345',
        'setkeep://friend-invite:42/ABCD2345',
        'setkeep://friend-invite/ABCD2345?extra=1',
        'setkeep://friend-invite/ABCD2345/',
        'setkeep://friend-invite/%41BCD2345',
        'javascript:ABCD2345',
        'https:ABCD2345',
        'https:///invite?code=ABCD2345',
      ]) {
        expect(
          FriendInviteLink.parse(invalid, configuredBaseUrl: base),
          isNull,
          reason: invalid,
        );
      }
    },
  );

  test('unpublished or unsafe bases never produce a claimed public link', () {
    for (final invalid in [
      '',
      'http://boredota.com/invite',
      'https://user@boredota.com/invite',
      'https://boredota.com/invite?x=1',
      'https://boredota.com/invite#fragment',
    ]) {
      expect(
        FriendInviteLink.url('ABCD2345', configuredBaseUrl: invalid),
        'setkeep://friend-invite/ABCD2345',
      );
      expect(
        FriendInviteLink.parse(
          '$base?code=ABCD2345',
          configuredBaseUrl: invalid,
        ),
        isNull,
      );
    }
  });

  test(
    'pending invite survives restart and unrelated login callback',
    () async {
      await FriendInviteStore.capture('setkeep://friend-invite/abcd2345');
      await FriendInviteStore.capture('setkeep://login-callback/');
      expect(FriendInviteStore.pending.value, 'ABCD2345');
      await FriendInviteStore.reset();
      await FriendInviteStore.start();
      expect(FriendInviteStore.pending.value, 'ABCD2345');
      await FriendInviteStore.consume('QRST6789');
      expect(FriendInviteStore.pending.value, 'ABCD2345');
      await FriendInviteStore.consume('abcd-2345');
      expect(FriendInviteStore.pending.value, isNull);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'pending_friend_invite',
        ),
        isNull,
      );
    },
  );

  test('receiving same code again signals a new explicit invitation', () async {
    await FriendInviteStore.capture('ABCD2345');
    final revision = FriendInviteStore.revision.value;
    await FriendInviteStore.capture('ABCD2345');
    expect(FriendInviteStore.revision.value, revision + 1);
  });

  test(
    'concurrent consume and new capture preserve the latest invitation',
    () async {
      await FriendInviteStore.capture(uuid);
      await Future.wait([
        FriendInviteStore.consume(uuid),
        FriendInviteStore.capture('ABCD2345'),
      ]);
      expect(FriendInviteStore.pending.value, 'ABCD2345');
      expect(
        (await SharedPreferences.getInstance()).getString(
          'pending_friend_invite',
        ),
        'ABCD2345',
      );
    },
  );
}
