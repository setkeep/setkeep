import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/friends/friends_repository.dart';
import 'package:setkeep/profile/profile_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const owner = '11111111-1111-4111-8111-111111111111';
const anotherOwner = '22222222-2222-4222-8222-222222222222';

Future<void> login(SupabaseClient client, String id) async {
  final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  final token =
      '${base64Url.encode(utf8.encode('{"alg":"HS256"}'))}.'
      '${base64Url.encode(utf8.encode(jsonEncode({'exp': expiry})))}.signature';
  await client.auth.recoverSession(
    jsonEncode({
      'access_token': token,
      'refresh_token': 'synthetic',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': id,
        'app_metadata': {},
        'user_metadata': {},
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
      },
    }),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final localName in ['', 'Name from another device']) {
    test('background cache "$localName" never renames cloud profile', () async {
      var writes = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.method != 'GET') writes++;
        request.response.write(
          jsonEncode({
            'user_id': owner,
            'display_name': 'Registered name',
            'visibility': 'private',
            'invite_code': owner,
          }),
        );
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'synthetic',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(() async {
        await client.dispose();
        await server.close(force: true);
      });
      await login(client, owner);
      final row = await FriendsRepository(client).ensureProfile(localName);
      expect(row['display_name'], 'Registered name');
      expect(row['visibility'], 'private');
      expect(writes, 0);
      expect(await ProfilePreference.load(owner: owner), 'Registered name');
      expect(await ProfilePreference.load(owner: anotherOwner), '');
    });
  }

  test('legacy/global cache cannot seed another account', () async {
    SharedPreferences.setMockInitialValues({'profile_display_name': 'Legacy'});
    expect(await ProfilePreference.load(), 'Legacy');
    expect(await ProfilePreference.load(owner: owner), '');
    await ProfilePreference.setDisplayName('First account', owner: owner);
    await ProfilePreference.cacheServerName(anotherOwner, 'Second account');
    expect(await ProfilePreference.load(owner: owner), 'First account');
    expect(await ProfilePreference.load(owner: anotherOwner), 'Second account');
    expect(await ProfilePreference.load(), 'First account');
  });

  test(
    'explicit editor updates only current owner name, preserves privacy',
    () async {
      var patches = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.method == 'PATCH') {
          patches++;
          expect(request.uri.queryParameters['user_id'], 'eq.$owner');
          expect(jsonDecode(await utf8.decoder.bind(request).join()), {
            'display_name': 'Explicit rename',
          });
          request.response.write('{}');
        } else {
          request.response.write(
            jsonEncode({
              'user_id': owner,
              'display_name': 'Cloud name',
              'visibility': 'private',
            }),
          );
        }
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'synthetic',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(() async {
        await client.dispose();
        await server.close(force: true);
      });
      await login(client, owner);
      final repo = FriendsRepository(client);
      await repo.saveDisplayName(' Explicit rename ', expectedOwner: owner);
      expect(patches, 1);
      await login(client, anotherOwner);
      await expectLater(
        repo.saveDisplayName('Wrong owner', expectedOwner: owner),
        throwsStateError,
      );
      expect(patches, 1);
    },
  );

  test(
    'capability selects v2 and scopes comment/like identity to workout',
    () async {
      final calls = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        final action = request.uri.path.split('/').last;
        calls.add(action);
        Object? result;
        if (action == 'friend_profiles') {
          result = {
            'user_id': owner,
            'display_name': 'Cloud name',
            'visibility': 'private',
            'avatar_path': null,
            'sharing_consent_version': 0,
            'friend_owned_sync_version': 1,
          };
        } else {
          final params = request.method == 'POST'
              ? (jsonDecode(await utf8.decoder.bind(request).join()) as Map? ??
                    {})
              : <String, dynamic>{};
          switch (action) {
            case 'my_friend_invite_code':
              result = 'ABCD2345';
            case 'lookup_friend_invite_v2':
              expect(params, {'code': 'ABCD2345'});
              result = {'ok': true, 'display_name': 'Friend', 'status': null};
            case 'request_friend_v2':
              result = {'ok': false, 'error': 'invite_unavailable'};
            case 'acknowledge_owned_friend_sharing':
              expect(params, {
                'expected_owner': owner,
                'consent_version': 'privacy-1.2',
              });
              result = null;
            case 'friend_comment_thread':
              expect(params, {'target_workout_id': 'session'});
              result = [
                {
                  'id': 'comment',
                  'workout_id': 'session',
                  'user_id': anotherOwner,
                  'body': 'Hello',
                  'display_name': 'Friend',
                  'avatar_path': null,
                },
              ];
            case 'friend_liker_avatars':
              expect(params, {'target_workout_id': 'session'});
              result = [
                {'user_id': anotherOwner, 'avatar_path': null},
              ];
            default:
              throw StateError('Unexpected action: $action');
          }
        }
        request.response.write(jsonEncode(result));
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'synthetic',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(() async {
        await client.dispose();
        await server.close(force: true);
      });
      await login(client, owner);
      final repo = FriendsRepository(client, commentsEnabled: true);
      expect(await repo.myInviteCode(), 'ABCD2345');
      expect(repo.supportsMutualFriendSharing, true);
      expect((await repo.invitePreview('ABCD2345'))['display_name'], 'Friend');
      await expectLater(repo.request('INVALID'), throwsStateError);
      await repo.acknowledgeMutualSharing();
      expect((await repo.comments('session')).single['friend_profiles'], {
        'display_name': 'Friend',
        'avatar_path': null,
      });
      expect(
        (await repo.likerAvatars('session')).single['user_id'],
        anotherOwner,
      );
      expect(calls.where((c) => c == 'request_friend'), isEmpty);
    },
  );
}
