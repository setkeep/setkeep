import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:setkeep/friends/friends_repository.dart';
import 'package:setkeep/friends/friend_snapshot_journal.dart';

import 'friend_snapshot_journal_test.dart' show MemorySnapshotStore, record;

const ownerA = '71000000-0000-0000-0000-000000000001';
const ownerB = '71000000-0000-0000-0000-000000000002';
Future<void> login(SupabaseClient client, String owner) async {
  final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  final token =
      '${base64Url.encode(utf8.encode('{"alg":"HS256"}'))}.${base64Url.encode(utf8.encode(jsonEncode({'exp': expiry, 'sub': owner})))}.synthetic';
  await client.auth.recoverSession(
    jsonEncode({
      'access_token': token,
      'refresh_token': 'synthetic',
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
}

class DelayedSnapshotStore extends MemorySnapshotStore {
  bool block = false;
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<String?> read(String key) async {
    if (block && key == FriendSnapshotJournal.journalKey) {
      block = false;
      entered.complete();
      await release.future;
    }
    return super.read(key);
  }
}

void main() {
  late HttpServer server;
  late SupabaseClient client;
  late MemorySnapshotStore store;
  late FriendSnapshotJournal journal;
  late FriendsRepository repo;
  late List<Map<String, dynamic>> calls;
  late Map<String, Map<String, Map<String, dynamic>>> snapshots;
  late Map<String, String> visibility;
  var fail = false, commitBeforeFailure = false, missingRpc = false;
  Completer<void>? entered, release;
  setUp(() async {
    fail = false;
    commitBeforeFailure = false;
    missingRpc = false;
    entered = null;
    release = null;
    calls = [];
    snapshots = {
      ownerA: {'deleted': record('deleted'), 'kept': record('kept')},
      ownerB: {'deleted': record('deleted')},
    };
    visibility = {ownerA: 'private', ownerB: 'private'};
    store = MemorySnapshotStore();
    store.values[FriendSnapshotJournal.historyKey] = jsonEncode([
      record('deleted'),
      record('kept'),
    ]);
    journal = FriendSnapshotJournal(store: store);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path.endsWith('/logout')) {
        request.response.write('{}');
        await request.response.close();
        return;
      }
      expect(request.uri.path, '/rest/v1/rpc/sync_friend_workouts');
      final params = Map<String, dynamic>.from(
        jsonDecode(await utf8.decoder.bind(request).join()) as Map,
      );
      calls.add(params);
      final expected = params['expected_owner'] as String;
      final jwt = request.headers.value('authorization')!.split(' ').last;
      final actual = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(jwt.split('.')[1]))),
      )['sub'];
      expect(expected, actual);
      if (entered != null && !entered!.isCompleted) entered!.complete();
      final gate = release;
      if (gate != null) await gate.future;
      if ((!fail || commitBeforeFailure) && !missingRpc) {
        final own = snapshots[expected]!;
        for (final date in params['deleted_client_ids'] as List) {
          own.remove(date);
        }
        if (params['publish_snapshot'] == true &&
            visibility[expected] == 'friends') {
          own.clear();
          for (final row in params['records'] as List) {
            own[row['date'] as String] = Map<String, dynamic>.from(row as Map);
          }
        }
      }
      if (fail || missingRpc) {
        request.response.statusCode = missingRpc ? 404 : 500;
        request.response.write(
          jsonEncode({
            'code': missingRpc ? 'PGRST202' : 'XX000',
            'message': 'Synthetic test failure',
          }),
        );
      } else {
        request.response.write('null');
      }
      await request.response.close();
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'synthetic',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await login(client, ownerA);
    repo = FriendsRepository(client, journal: journal);
  });
  tearDown(() async {
    if (release != null && !release!.isCompleted) release!.complete();
    await client.dispose();
    await server.close(force: true);
  });

  test('online private deletion removes exact ID, preserves privacy, filters stale payload', () async {
    await journal.saveHistory([record('kept')], expectedOwner: ownerA);
    await repo.publish([record('deleted'), record('kept')]);
    expect(snapshots[ownerA]!.keys, ['kept']);
    expect(snapshots[ownerB]!.keys, ['deleted']);
    expect(visibility[ownerA], 'private');
    expect((calls.single['records'] as List).map((r) => r['date']), ['kept']);
    expect((await journal.batch(ownerA)).pending, false);
  });
  test('offline then restart retries deletion only, with no upload or implicit prune', () async {
    await journal.saveHistory([record('kept')], expectedOwner: ownerA);
    fail = true;
    await expectLater(
      repo.publish([record('kept')]),
      throwsA(isA<PostgrestException>()),
    );
    expect((await journal.batch(ownerA)).pending, true);
    fail = false;
    visibility[ownerA] = 'friends';
    final restarted = FriendsRepository(
      client,
      journal: FriendSnapshotJournal(store: store),
    );
    await restarted.retryDeletions();
    expect(calls.last['publish_snapshot'], false);
    expect(calls.last['records'], isEmpty);
    expect(snapshots[ownerA]!.keys, ['kept']);
    expect((await journal.batch(ownerA)).pending, false);
    await restarted.retryDeletions();
    expect(calls.length, 2);
  });
  test(
    'signed out waits; other login never receives intent; same login resumes',
    () async {
      await journal.rememberOwner(ownerA);
      await client.auth.signOut(scope: SignOutScope.local);
      await journal.saveHistory([
        record('kept'),
      ], expectedOwner: await journal.lastOwner());
      await repo.retryDeletions();
      expect(calls, isEmpty);
      await login(client, ownerB);
      await repo.retryDeletions();
      expect(calls, isEmpty);
      expect(snapshots[ownerB]!.keys, ['deleted']);
      await login(client, ownerA);
      await repo.retryDeletions();
      expect(calls.single['expected_owner'], ownerA);
      expect(snapshots[ownerA]!.keys, ['kept']);
    },
  );
  test('account switch during in-flight request cannot delete new account snapshot', () async {
    await journal.saveHistory([record('kept')], expectedOwner: ownerA);
    entered = Completer<void>();
    release = Completer<void>();
    final publication = repo.publish([record('kept')]);
    await entered!.future;
    await login(client, ownerB);
    release!.complete();
    await publication;
    expect(calls.single['expected_owner'], ownerA);
    expect(snapshots[ownerB]!.keys, ['deleted']);
    expect(snapshots[ownerA]!.keys, ['kept']);
  });
  test(
    'lost success response leaves intent pending and duplicate retry is safe',
    () async {
      await journal.saveHistory([record('kept')], expectedOwner: ownerA);
      fail = true;
      commitBeforeFailure = true;
      await expectLater(
        repo.publish([record('kept')]),
        throwsA(isA<PostgrestException>()),
      );
      expect(snapshots[ownerA]!.keys, ['kept']);
      expect((await journal.batch(ownerA)).pending, true);
      fail = false;
      await repo.retryDeletions();
      expect(snapshots[ownerA]!.keys, ['kept']);
      expect((await journal.batch(ownerA)).pending, false);
    },
  );
  test('Undo while RPC in flight restores latest history without stale acknowledgement', () async {
    visibility[ownerA] = 'friends';
    await journal.saveHistory([record('kept')], expectedOwner: ownerA);
    entered = Completer<void>();
    release = Completer<void>();
    final deletion = repo.publish([record('kept')]);
    await entered!.future;
    await journal.saveHistory([
      record('deleted'),
      record('kept'),
    ], expectedOwner: ownerA);
    final restore = repo.publish([record('deleted'), record('kept')]);
    release!.complete();
    await deletion;
    await restore;
    expect(snapshots[ownerA]!.keys, unorderedEquals(['deleted', 'kept']));
    expect(calls.last['deleted_client_ids'], isEmpty);
    expect((await journal.batch(ownerA)).deletions, isEmpty);
  });
  test(
    'account switch while reading durable batch cancels before network send',
    () async {
      final delayed = DelayedSnapshotStore()..values.addAll(store.values);
      journal = FriendSnapshotJournal(store: delayed);
      repo = FriendsRepository(client, journal: journal);
      await journal.saveHistory([record('kept')], expectedOwner: ownerA);
      delayed.block = true;
      final publication = repo.publish([record('kept')]);
      await delayed.entered.future;
      await login(client, ownerB);
      delayed.release.complete();
      await publication;
      expect(calls, isEmpty);
      expect((await journal.batch(ownerA)).pending, true);
      expect(snapshots[ownerB]!.keys, ['deleted']);
    },
  );
  test(
    'confirmed tombstone blocks later stale public widget publication',
    () async {
      visibility[ownerA] = 'friends';
      await journal.saveHistory([record('kept')], expectedOwner: ownerA);
      await repo.publish([record('kept')]);
      await repo.publish([record('deleted'), record('kept')]);
      expect(snapshots[ownerA]!.keys, ['kept']);
      expect(calls.last['deleted_client_ids'], ['deleted']);
      expect((await journal.batch(ownerA)).pending, false);
    },
  );
  test('retry with absent device history deletes only explicit ID', () async {
    visibility[ownerA] = 'friends';
    await journal.saveHistory([record('kept')], expectedOwner: ownerA);
    store.values.remove(FriendSnapshotJournal.historyKey);
    await repo.retryDeletions();
    expect(calls.single['publish_snapshot'], false);
    expect(calls.single['records'], isEmpty);
    expect(snapshots[ownerA]!.keys, ['kept']);
  });

  test('missing migration retains intent and never falls back to unsafe legacy publish', () async {
    await journal.saveHistory([record('kept')], expectedOwner: ownerA);
    missingRpc = true;
    await expectLater(
      repo.retryDeletions(),
      throwsA(isA<PostgrestException>()),
    );
    expect((await journal.batch(ownerA)).pending, true);
    expect(snapshots[ownerA]!.keys, unorderedEquals(['deleted', 'kept']));
  });
  test('retry pending gate avoids duplicate simultaneous requests', () async {
    await journal.saveHistory([record('kept')], expectedOwner: ownerA);
    entered = Completer<void>();
    release = Completer<void>();
    final first = repo.retryDeletions();
    await entered!.future;
    await repo.retryDeletions();
    expect(calls.length, 1);
    release!.complete();
    await first;
    expect((await journal.batch(ownerA)).pending, false);
  });
  test(
    'publication keeps social allowlist and excludes other trainer ownership',
    () async {
      store.values.remove(FriendSnapshotJournal.historyKey);
      await repo.publish([
        {
          ...record('own'),
          'gymName': 'private gym',
          'note': 'private note',
          'bodyWeight': 70,
        },
        record('other', owner: ownerB),
      ]);
      final payload = calls.single['records'] as List;
      expect(payload.length, 1);
      expect(
        (payload.single as Map).keys,
        unorderedEquals(['date', 'durationSeconds', 'sets']),
      );
    },
  );
}
