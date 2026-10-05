import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/friends/friends_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  for (final outcome in ['success', 'lost reply', 'rejected']) {
    test('atomic photo removal and name: $outcome', () async {
      const owner = '11111111-1111-4111-8111-111111111111';
      var name = 'Before';
      String? avatar = '$owner/old.png';
      var patches = 0, deletes = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path.endsWith('/friend_profiles')) {
          if (request.method == 'PATCH') {
            patches++;
            final body =
                jsonDecode(await utf8.decoder.bind(request).join()) as Map;
            expect(body.keys.toSet(), {'avatar_path', 'display_name'});
            expect(body['display_name'], 'After');
            expect(body['avatar_path'], null);
            if (outcome != 'rejected') {
              name = body['display_name'] as String;
              avatar = null;
            }
            if (outcome != 'success') {
              request.response.statusCode = 500;
              request.response.write(
                jsonEncode({'message': 'Synthetic failure', 'code': 'XX000'}),
              );
            } else {
              request.response.write('{}');
            }
          } else {
            request.response.write(
              jsonEncode({
                'user_id': owner,
                'display_name': name,
                'avatar_path': avatar,
                'visibility': 'private',
              }),
            );
          }
        } else if (request.method == 'DELETE') {
          deletes++;
          request.response.write('[]');
        } else {
          request.response.statusCode = 404;
          request.response.write('{}');
        }
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
      final save = FriendsRepository(client)
          .setAvatar(null, expectedOwner: owner, displayName: 'After');
      if (outcome == 'rejected') {
        await expectLater(save, throwsA(isA<PostgrestException>()));
      } else {
        await save;
      }
      expect(patches, 1);
      expect(deletes, outcome == 'rejected' ? 0 : 1);
      expect(name, outcome == 'rejected' ? 'Before' : 'After');
    });
  }
}
