import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/friends/friends_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'friend_profile_identity_test.dart' show login, owner;

void main() {
  test('lost committed response retries exact operation and draft', () async {
    const operationId = '11111111-2222-4333-8444-555555555555';
    final drafts = <Map<String, dynamic>>[];
    final committed = <String>{};
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path.endsWith('/friend_profiles')) {
        request.response.write(
          jsonEncode({
            'user_id': owner,
            'display_name': 'Synthetic',
            'avatar_path': null,
            'comment_idempotency_version': 1,
          }),
        );
      } else {
        expect(request.uri.path.endsWith('/rpc/send_friend_comment'), true);
        final draft = Map<String, dynamic>.from(
          jsonDecode(await utf8.decoder.bind(request).join()) as Map,
        );
        drafts.add(draft);
        committed.add(draft['operation_id'] as String);
        if (drafts.length == 1) {
          request.response.statusCode = 500;
          request.response.write(
            jsonEncode({'message': 'Synthetic lost response', 'code': 'XX000'}),
          );
        } else {
          request.response.write(jsonEncode('existing-comment'));
        }
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
    final repo = FriendsRepository(client, commentsEnabled: true);
    await expectLater(
      repo.sendComment('session', ' 日本語\nmessage ', operationId: operationId),
      throwsA(isA<PostgrestException>()),
    );
    await repo.sendComment(
      'session',
      ' 日本語\nmessage ',
      operationId: operationId,
    );
    expect(drafts.length, 2);
    expect(drafts.first, drafts.last);
    expect(drafts.last, {
      'target_workout_id': 'session',
      'body': '日本語\nmessage',
      'operation_id': operationId,
    });
    expect(committed.length, 1);
    expect(repo.supportsIdempotentComments, true);
  });

  test(
    'old schema never silently falls back to duplicate-prone INSERT',
    () async {
      var writes = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.method != 'GET') writes++;
        request.response.write(
          jsonEncode({'user_id': owner, 'display_name': 'Synthetic'}),
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
      final repo = FriendsRepository(client, commentsEnabled: true);
      await expectLater(
        repo.sendComment('session', 'Hello', operationId: owner),
        throwsStateError,
      );
      expect(repo.supportsIdempotentComments, false);
      expect(writes, 0);
      await expectLater(
        repo.sendComment('session', 'Hello', operationId: 'not-a-uuid'),
        throwsArgumentError,
      );
      expect(writes, 0);
    },
  );
}
