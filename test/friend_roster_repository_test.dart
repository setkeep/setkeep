import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:setkeep/friends/friends_repository.dart';

void main() {
  for (final upgraded in [false, true]) {
    test(
      'roster uses authorized connection metadata and ${upgraded ? 'update' : 'legacy'} feed',
      () async {
        const viewer = '11111111-1111-4111-8111-111111111111';
        final requests = <Uri>[];
        var feedFails = false, connectionsFail = false;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          requests.add(request.uri);
          request.response.headers.contentType = ContentType.json;
          final path = request.uri.path;
          Object body;
          if (path.endsWith('/friend_profiles')) {
            body = {
              'user_id': viewer,
              'display_name': 'Viewer',
              'avatar_path': null,
              if (upgraded) 'friend_workout_updates_version': 1,
            };
          } else if (path.endsWith('/list_friend_connections_with_avatar')) {
            if (connectionsFail) request.response.statusCode = 503;
            body = connectionsFail
                ? {'message': 'offline'}
                : [
                    for (final id in ['b', 'a', 'c'])
                      {
                        'requester': viewer,
                        'recipient': id,
                        'status': 'accepted',
                        if (id != 'c') 'friend_name': 'Approved $id',
                      },
                    {
                      'requester': viewer,
                      'recipient': 'pending',
                      'status': 'pending',
                    },
                  ];
          } else if (path.endsWith(
            upgraded
                ? '/latest_updated_friend_workouts'
                : '/latest_friend_workouts',
          )) {
            if (feedFails) request.response.statusCode = 404;
            body = feedFails
                ? {'message': 'missing RPC', 'code': 'PGRST202'}
                : [
                    {
                      'id': 'old-exercise',
                      'user_id': 'a',
                      'performed_at': '2026-01-01T00:00:00Z',
                      'updated_at': '2026-11-02T00:00:00Z',
                    },
                    {
                      'id': 'new-exercise',
                      'user_id': 'b',
                      'performed_at': '2026-12-01T00:00:00Z',
                      'updated_at': '2026-11-01T00:00:00Z',
                    },
                    {'id': 'unexpected', 'user_id': 'pending'},
                  ];
          } else {
            request.response.statusCode = 500;
            body = {'message': 'unexpected endpoint'};
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
              'id': viewer,
              'app_metadata': {},
              'user_metadata': {},
              'aud': 'authenticated',
              'created_at': '2026-01-01T00:00:00Z',
            },
          }),
        );
        final repo = FriendsRepository(client);
        final entries = await repo.roster();
        expect(entries.map((e) => e.userId), ['a', 'b', 'c']);
        expect(entries.first.displayName, 'Approved a');
        expect(entries.last.displayName, isNull);
        expect(entries.last.workout, isNull);
        expect(entries.first.updatedAt != null, upgraded);
        expect(
          requests.every(
            (uri) => !uri.queryParameters.containsKey('updated_at'),
          ),
          true,
        );
        if (upgraded) {
          expect(
            requests.last.queryParameters['select'],
            isNot(contains('friend_profiles')),
          );
        }
        feedFails = true;
        expect(
          (await repo.roster()).every(
            (e) => e.workoutsFailed && e.workout == null,
          ),
          true,
        );
        connectionsFail = true;
        await expectLater(repo.roster(), throwsA(isA<PostgrestException>()));
      },
    );
  }
}
