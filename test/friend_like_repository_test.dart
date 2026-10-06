import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/friends/friends_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'friend_profile_identity_test.dart' show owner, anotherOwner, login;

void main() {
  test('owner exact legacy lookup and received-likes pagination ignore comment gate', () async {
    final offsets = <int>[];
    var writes = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      final action = request.uri.path.split('/').last;
      if (action == 'friend_workouts') {
        expect(request.method, 'GET');
        expect(request.uri.queryParameters['user_id'], 'eq.$owner');
        expect(
          request.uri.queryParameters['client_id'],
          'eq.2020-01-01T10:00:00.000',
        );
        request.response.write(
          jsonEncode({
            'id': 'old-remote-id',
            'user_id': owner,
            'client_id': '2020-01-01T10:00:00.000',
          }),
        );
      } else if (action == 'received_friend_likes') {
        final offset = int.parse(request.uri.queryParameters['offset'] ?? '0');
        offsets.add(offset);
        expect(request.uri.queryParameters['limit'], '100');
        expect(
          request.uri.queryParameters['order'],
          'created_at.desc.nullslast,workout_id.asc.nullslast,user_id.asc.nullslast',
        );
        final end = (offset + 100).clamp(0, 251);
        request.response.write(
          jsonEncode([
            for (var i = offset; i < end; i++)
              {
                'owner_id': owner,
                'user_id': anotherOwner,
                'workout_id': 'session-$i',
                'created_at': '2026-10-06T03:00:00Z',
                'client_id': 'record-$i',
                'display_name': 'Registered friend',
                'avatar_path': null,
              },
          ]),
        );
      } else {
        writes++;
        request.response.statusCode = 400;
        request.response.write('{}');
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
    expect(repo.commentsEnabled, false);
    expect(
      (await repo.workoutForRecord('2020-01-01T10:00:00.000'))!['id'],
      'old-remote-id',
    );
    expect((await repo.receivedLikes()).length, 251);
    expect(offsets, [0, 100, 200]);
    expect(writes, 0);
  });
  test('unauthenticated repository never reads received-like RPC', () async {
    var calls = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      calls++;
      request.response.statusCode = 400;
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
    expect(await FriendsRepository(client).receivedLikes(), isEmpty);
    expect(calls, 0);
  });
  test(
    'account change during RPC discards response before next pagination query',
    () async {
      final requested = Completer<void>(), reply = Completer<void>();
      var calls = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        calls++;
        requested.complete();
        await reply.future;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode([
            for (var i = 0; i < 100; i++)
              {'owner_id': owner, 'workout_id': 'old-$i'},
          ]),
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
      final pending = FriendsRepository(client).receivedLikes();
      final rejected = expectLater(pending, throwsStateError);
      await requested.future;
      await login(client, anotherOwner);
      reply.complete();
      await rejected;
      expect(calls, 1);
    },
  );
}
