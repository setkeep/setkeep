import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setkeep/friends/friend_comment_inbox.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:setkeep/friends/friends_repository.dart';

void main() {
  for (final upgraded in [false, true]) {
    test(
      'friends requests work against ${upgraded ? 'extended' : 'MVP-only'} schema',
      () async {
        const owner = '11111111-1111-4111-8111-111111111111';
        final requests = <Uri>[];
        var visibility = 'private';
        var accepted = true;
        var deleted = false;
        SharedPreferences.setMockInitialValues({});
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          requests.add(request.uri);
          request.response.headers.contentType = ContentType.json;
          final path = request.uri.path;
          Object body;
          if (path.endsWith('/friend_profiles')) {
            body = {
              'user_id': owner,
              'display_name': 'Synthetic',
              'visibility': visibility,
              if (upgraded) 'avatar_path': null,
            };
          } else if (path.contains('/rpc/list_friend_connections')) {
            body = [
              {
                'requester': owner,
                'recipient': 'friend-a',
                'status': accepted ? 'accepted' : 'pending',
                'friend_name': 'Synthetic friend',
              },
              {
                'requester': 'friend-b',
                'recipient': owner,
                'status': accepted ? 'accepted' : 'pending',
                'friend_name': 'Synthetic friend',
              },
              {'requester': owner, 'recipient': 'pending', 'status': 'pending'},
            ];
          } else if (path.endsWith('/friend_workouts') ||
              path.endsWith('/latest_friend_workouts')) {
            body = [
              {
                'id': 'session',
                'user_id':
                    request.uri.queryParameters['user_id']?.replaceFirst(
                      'eq.',
                      '',
                    ) ??
                    'friend-a',
                'performed_at': '2026-10-04T00:00:00Z',
              },
            ];
          } else if (path.endsWith('/friend_comments')) {
            Map<String, dynamic> comment(
              String id,
              String author, [
              String workoutOwner = owner,
            ]) => {
              'id': id,
              'user_id': author,
              'workout_id': 'session',
              'body': 'Synthetic comment',
              'created_at': '2026-10-04T00:00:00Z',
              'friend_workouts': {
                'user_id': workoutOwner,
                'performed_at': '2026-10-04T00:00:00Z',
              },
            };
            body = deleted
                ? []
                : [
                    comment('c1', 'friend-a'),
                    comment('c1', 'friend-a'),
                    comment('c2', 'friend-b'),
                    comment('self', owner),
                    comment('stranger', 'stranger'),
                    comment('someone-else', 'friend-a', 'other-owner'),
                  ];
          } else {
            request.response.statusCode = 404;
            body = {'message': 'Unexpected endpoint'};
          }
          request.response.write(jsonEncode(body));
          await request.response.close();
        });
        final client = SupabaseClient(
          'http://127.0.0.1:${server.port}',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        );
        addTearDown(() async {
          await client.dispose();
          await server.close(force: true);
        });
        final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
        final token =
            '${base64Url.encode(utf8.encode('{"alg":"HS256"}'))}.${base64Url.encode(utf8.encode(jsonEncode({'exp': expiry})))}.signature';
        await client.auth.recoverSession(
          jsonEncode({
            'access_token': token,
            'refresh_token': 'test',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': owner,
              'app_metadata': {},
              'user_metadata': {},
              'aud': 'authenticated',
              'created_at': '2026-01-01T00:00:00Z',
            },
          }),
        );
        final repository = FriendsRepository(client, commentsEnabled: true);
        await repository.ensureProfile('Synthetic');
        expect(repository.supportsProfileInvites, upgraded);
        final feed = await repository.feed();
        await repository.feed(owner: 'friend-a');
        if (upgraded) {
          expect(feed.length, 1);
          expect(
            requests.any((uri) => uri.path.endsWith('/latest_friend_workouts')),
            isTrue,
          );
          expect(
            requests.last.queryParameters['select'],
            contains('avatar_path'),
          );
        } else {
          expect(feed.map((row) => row['user_id']).toSet(), {
            'friend-a',
            'friend-b',
          });
          expect(
            requests.any(
              (uri) => uri.path.endsWith('/list_friend_connections'),
            ),
            isTrue,
          );
          expect(
            requests.where((uri) => uri.queryParameters['limit'] == '1').length,
            2,
          );
          expect(
            requests.where(
              (uri) => uri.queryParameters['user_id'] == 'eq.pending',
            ),
            isEmpty,
          );
          await expectLater(
            repository.setAvatar(Uint8List.fromList([1])),
            throwsStateError,
          );
          expect(
            requests.any(
              (uri) =>
                  uri.toString().contains('avatar_path') ||
                  uri.path.contains('/storage/') ||
                  uri.path.contains('with_avatar') ||
                  uri.path.contains('latest_friend_workouts'),
            ),
            isFalse,
          );
        }
        final closed = FriendsRepository(client);
        await closed.feed(owner: 'friend-a');
        expect(
          requests.last.queryParameters['select'],
          isNot(contains('friend_comments')),
        );
        final beforeClosedRead = requests.length;
        expect(await closed.comments('session'), isEmpty);
        expect(requests.length, beforeClosedRead);
        final inbox = FriendCommentInboxRepository(repository);
        expect(await inbox.comments(), isEmpty); // Private snapshots stay out.
        visibility = 'friends';
        final notifications = await inbox.comments();
        expect(notifications.map((row) => row['id']).toSet(), {'c1', 'c2'});
        expect(await inbox.unreadCount(), 2);
        final query = requests.last.queryParameters;
        expect(query['friend_workouts.user_id'], 'eq.$owner');
        expect(query['user_id'], 'neq.$owner');
        await Future.wait([inbox.markRead('c1'), inbox.markRead('c2')]);
        expect(await inbox.unreadCount(), 0);
        final session = client.auth.currentSession!;
        const otherAccount = '22222222-2222-4222-8222-222222222222';
        await client.auth.recoverSession(
          jsonEncode({
            ...session.toJson(),
            'user': {...session.user.toJson(), 'id': otherAccount},
          }),
        );
        expect(await inbox.unreadCount(), 0);
        expect(
          (await SharedPreferences.getInstance()).getStringList(
            inbox.key(otherAccount),
          ),
          isNull,
        );
        await client.auth.recoverSession(jsonEncode(session.toJson()));
        expect(
          (await SharedPreferences.getInstance())
              .getStringList(inbox.key(owner))!
              .toSet(),
          {'c1', 'c2'},
        );
        accepted = false;
        expect(await inbox.comments(), isEmpty);
        expect(await inbox.markRead('c1'), isFalse);
        accepted = true;
        visibility = 'private';
        expect(await inbox.unreadCount(), 0);
        visibility = 'friends';
        deleted = true;
        expect(await inbox.comments(), isEmpty);
        expect(await inbox.markRead('c1'), isFalse);
        await client.auth.signOut(scope: SignOutScope.local);
        expect(await inbox.unreadCount(), 0);
      },
    );
  }
}
