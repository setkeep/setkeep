import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;

import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/friends/friends_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'friend_profile_identity_test.dart' show owner, anotherOwner, login;

const _performedAt = '2026-11-07T10:00:00.123456+00:00';

String _id(int number) =>
    '00000000-0000-4000-8000-${number.toRadixString(16).padLeft(12, '0')}';

Map<String, dynamic> _row(int number, {String time = _performedAt}) => {
  'id': _id(number),
  'user_id': anotherOwner,
  'performed_at': time,
  // Keep client_id distinct: history's paging timestamp must not replace the
  // wall-clock record date used by sharedWorkoutDate in the calendar.
  'client_id': '2026-11-06T23:00:00.000',
  'duration_seconds': number,
  'sets': <Object>[],
  'friend_profiles': {'display_name': 'Friend', 'avatar_path': null},
  'friend_likes': [
    {'user_id': owner},
  ],
  'friend_comments': [
    {'id': 'comment-$number'},
  ],
};

void main() {
  for (final count in [0, 999, 1000, 1001, 2001]) {
    test('history returns all $count rows, including timestamp ties', () async {
      final h = await _HistoryHarness.open(count: count);
      final result = await h.repo.history(owner: anotherOwner);
      expect(result.length, count);
      expect(result.map((row) => row['id']), h.rows.map((row) => row['id']));
      expect(result.map((row) => row['id']).toSet().length, count);
      final nonemptyPages = (count + 999) ~/ 1000;
      expect(h.pages.length, nonemptyPages + 1);
      expect(h.pages.first.queryParameters['or'], isNull);
      for (var page = 1; page < h.pages.length; page++) {
        final lastNumber = count - min<int>(page * 1000, count) + 1;
        expect(
          h.pages[page].queryParameters['or'],
          '(performed_at.lt."$_performedAt",and(performed_at.eq."$_performedAt",id.lt."${_id(lastNumber)}"))',
        );
      }
      h.expectHistoryQueries();
      expect(h.visibilityChecks.length, count == 0 ? 0 : 1);
      if (count > 0) {
        expect(result.first['friend_likes'], [
          {'user_id': owner},
        ]);
        expect(result.first['client_id'], '2026-11-06T23:00:00.000');
      }
    });
  }

  test('short server-capped pages continue until an empty page', () async {
    final h = await _HistoryHarness.open(count: 17, rowCap: 7);
    expect((await h.repo.history(owner: anotherOwner)).length, 17);
    expect(h.pages.length, 4);
    h.expectHistoryQueries();
  });

  test(
    'keyset survives deletion of earlier and not-yet-read records',
    () async {
      final h = await _HistoryHarness.open(count: 8, rowCap: 3);
      final expected = h.rows.map((row) => row['id']).toList()..remove(_id(5));
      h.beforeRequest = (request) {
        if (h.isPage(request) && h.pages.length == 2) {
          // Remove the cursor row and one unread row. Offset-based paging would
          // now skip additional records, but the tuple boundary stays valid.
          h.rows.removeWhere((row) => [_id(6), _id(5)].contains(row['id']));
        }
      };
      final result = await h.repo.history(owner: anotherOwner);
      expect(result.map((row) => row['id']), expected);
      h.expectHistoryQueries();
    },
  );

  test('timestamp comparison preserves offsets and microsecond precision', () async {
    final h = await _HistoryHarness.open(rowCap: 1);
    h.rows.addAll([
      _row(1, time: '2026-11-07T10:00:00.000002+09:00'),
      _row(3, time: '2026-11-07T01:00:00.000001Z'),
      _row(2, time: '2026-11-07T10:00:00.000001+09:00'),
      _row(4, time: '2026-11-07T00:59:59.999999Z'),
    ]);
    final result = await h.repo.history(owner: anotherOwner);
    expect(result.map((row) => row['id']), [1, 3, 2, 4].map(_id));
    expect(
      h.pages[1].queryParameters['or'],
      '(performed_at.lt."2026-11-07T10:00:00.000002+09:00",and(performed_at.eq."2026-11-07T10:00:00.000002+09:00",id.lt."${_id(1)}"))',
    );
    expect(result.first['performed_at'], '2026-11-07T10:00:00.000002+09:00');
  });

  test(
    'second-page error rejects the whole history and permits a fresh retry',
    () async {
      final h = await _HistoryHarness.open(count: 5, rowCap: 2);
      h.failPage = 2;
      await expectLater(
        h.repo.history(owner: anotherOwner),
        throwsA(isA<PostgrestException>()),
      );
      expect(h.pages.length, 2);
      expect(h.visibilityChecks, isEmpty);
      h.failPage = null;
      h.pages.clear();
      expect((await h.repo.history(owner: anotherOwner)).length, 5);
      expect(h.pages.first.queryParameters['or'], isNull);
    },
  );

  for (final stage in ['second page', 'visibility check']) {
    test('revoked sharing at $stage discards accumulated history', () async {
      final h = await _HistoryHarness.open(count: 5, rowCap: 2);
      h.beforeRequest = (request) {
        if ((stage == 'second page' &&
                h.isPage(request) &&
                h.pages.length == 2) ||
            (stage == 'visibility check' && h.isVisibilityCheck(request))) {
          h.sharing = false;
        }
      };
      expect(await h.repo.history(owner: anotherOwner), isEmpty);
      expect(h.visibilityChecks.length, 1);
      expect(h.visibilityChecks.single.queryParameters['or'], isNull);
    });
  }

  test(
    'failed final visibility read cannot return accumulated history',
    () async {
      final h = await _HistoryHarness.open(count: 3, rowCap: 2);
      h.failVisibility = true;
      await expectLater(
        h.repo.history(owner: anotherOwner),
        throwsA(isA<PostgrestException>()),
      );
      expect(h.visibilityChecks.length, 1);
    },
  );

  for (final stage in [
    'profile',
    'first page',
    'second page',
    'visibility check',
  ]) {
    test(
      'account switch during $stage fails before another history read',
      () async {
        final h = await _HistoryHarness.open(count: 3, rowCap: 2);
        final requested = Completer<void>(), release = Completer<void>();
        h.beforeRequest = (request) async {
          final pause = switch (stage) {
            'profile' => request.uri.path.endsWith('/friend_profiles'),
            'first page' => h.isPage(request) && h.pages.length == 1,
            'second page' => h.isPage(request) && h.pages.length == 2,
            _ => h.isVisibilityCheck(request),
          };
          if (pause) {
            requested.complete();
            await release.future;
          }
        };
        final rejected = expectLater(
          h.repo.history(owner: anotherOwner),
          throwsStateError,
        );
        await requested.future;
        final requestCount = h.requests.length;
        await login(h.client, anotherOwner);
        release.complete();
        await rejected;
        expect(h.requests.length, requestCount);
      },
    );
  }

  test('signed-out history fails without any database request', () async {
    final h = await _HistoryHarness.open(authenticated: false);
    await expectLater(h.repo.history(owner: anotherOwner), throwsStateError);
    expect(h.requests, isEmpty);
  });

  final invalidRows = <String, Map<String, dynamic>>{
    'different owner': {..._row(1), 'user_id': owner},
    'missing owner': {..._row(1)}..remove('user_id'),
    'missing ID': {..._row(1)}..remove('id'),
    'empty ID': {..._row(1), 'id': ''},
    'non-UUID ID': {..._row(1), 'id': 'not-a-uuid'},
    'ID filter syntax': {..._row(1), 'id': '"\\),user_id.neq.$anotherOwner'},
    'missing timestamp': {..._row(1)}..remove('performed_at'),
    'invalid timestamp': {..._row(1), 'performed_at': 'not-a-date'},
    'overflowing timestamp': {
      ..._row(1),
      'performed_at': '2026-02-31T00:00:00Z',
    },
    'ambiguous local timestamp': {
      ..._row(1),
      'performed_at': '2026-11-07T10:00:00',
    },
    'timestamp filter syntax': {
      ..._row(1),
      'performed_at': '2026-11-07T10:00:00Z"\\),id.gt.0',
    },
  };
  for (final entry in invalidRows.entries) {
    test('${entry.key} fails closed instead of producing a cursor', () async {
      final h = await _HistoryHarness.open(count: 2, rowCap: 1);
      h.pageOverrides[2] = [entry.value];
      await expectLater(h.repo.history(owner: anotherOwner), throwsStateError);
      expect(h.pages.length, 2);
      expect(h.visibilityChecks, isEmpty);
    });
  }

  final badPages = <String, List<Map<String, dynamic>>>{
    'repeated page': [_row(4), _row(3)],
    'repeated boundary': [_row(3), _row(2)],
    'duplicate ID with older timestamp': [
      _row(4, time: '2026-11-06T00:00:00Z'),
    ],
    'newer timestamp': [_row(2, time: '2026-11-08T00:00:00Z')],
    'larger tie ID': [_row(5)],
    'out-of-order second page': [_row(1), _row(2)],
    'duplicate within page': [_row(2), _row(2)],
  };
  for (final entry in badPages.entries) {
    test('${entry.key} rejects the entire history', () async {
      final h = await _HistoryHarness.open(count: 4, rowCap: 2);
      h.pageOverrides[2] = entry.value;
      await expectLater(h.repo.history(owner: anotherOwner), throwsStateError);
      expect(h.pages.length, 2);
      expect(h.visibilityChecks, isEmpty);
    });
  }

  test('oversized server page is not accepted as complete history', () async {
    final h = await _HistoryHarness.open(count: 1001);
    h.pageOverrides[1] = h.rows;
    await expectLater(h.repo.history(owner: anotherOwner), throwsStateError);
    expect(h.pages.length, 1);
  });

  for (final upgraded in [false, true]) {
    for (final comments in [false, true]) {
      test(
        'history keeps legacy/upgraded fields (profile=$upgraded, comments=$comments)',
        () async {
          final h = await _HistoryHarness.open(
            count: 1,
            upgraded: upgraded,
            comments: comments,
          );
          expect((await h.repo.history(owner: anotherOwner)).length, 1);
          final fields = h.pages
              .singleWhere((uri) => uri.queryParameters['or'] == null)
              .queryParameters['select']!;
          expect(fields.contains('avatar_path'), upgraded);
          expect(fields.contains('friend_comments(id)'), comments);
          expect(fields, contains('friend_profiles!inner(display_name'));
          expect(fields, contains('friend_likes(user_id)'));
          expect(
            h.requests.where((uri) => uri.path.contains('/rpc/')),
            isEmpty,
          );
        },
      );
    }
  }

  test(
    'owner feed stays bounded and does not perform a history scan',
    () async {
      final h = await _HistoryHarness.open(count: 1001);
      expect((await h.repo.feed(owner: anotherOwner)).length, 1000);
      expect(h.pages.length, 1);
      expect(
        h.pages.single.queryParameters['order'],
        'performed_at.desc.nullslast',
      );
      expect(h.pages.single.queryParameters['or'], isNull);
      expect(h.visibilityChecks, isEmpty);
    },
  );

  for (final upgraded in [false, true]) {
    test(
      'owner-null feed retains its ${upgraded ? 'RPC' : 'legacy'} path',
      () async {
        final h = await _HistoryHarness.open(count: 3, upgraded: upgraded);
        final result = await h.repo.feed();
        expect(result.length, 1);
        expect(h.visibilityChecks, isEmpty);
        if (upgraded) {
          expect(h.pages, isEmpty);
          expect(h.requests.last.path, endsWith('/rpc/latest_friend_workouts'));
          expect(h.requests.last.queryParameters['or'], isNull);
        } else {
          expect(
            h.requests.map((uri) => uri.path),
            contains(endsWith('/rpc/list_friend_connections')),
          );
          expect(h.pages.length, 1);
          expect(h.pages.single.queryParameters['limit'], '1');
          expect(h.pages.single.queryParameters['or'], isNull);
        }
      },
    );
  }
}

/// Exercise real Supabase/PostgREST URL construction. This server interprets
/// the actual tuple filter instead of returning pages by request number, so a
/// missing/wrong cursor or offset pagination cannot accidentally pass.
class _HistoryHarness {
  _HistoryHarness(
    this.server,
    this.client,
    this.rows,
    this.rowCap,
    this.upgraded,
    bool comments,
  ) : repo = FriendsRepository(client, commentsEnabled: comments);

  final HttpServer server;
  final SupabaseClient client;
  final FriendsRepository repo;
  final List<Map<String, dynamic>> rows;
  final int rowCap;
  final bool upgraded;
  final requests = <Uri>[];
  final pages = <Uri>[];
  final visibilityChecks = <Uri>[];
  final pageOverrides = <int, List<Map<String, dynamic>>>{};
  FutureOr<void> Function(HttpRequest)? beforeRequest;
  int? failPage;
  bool failVisibility = false;
  bool sharing = true;

  static Future<_HistoryHarness> open({
    int count = 0,
    int rowCap = 1000,
    bool upgraded = true,
    bool comments = false,
    bool authenticated = true,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'synthetic',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final harness = _HistoryHarness(
      server,
      client,
      List.generate(count, (index) => _row(count - index)),
      rowCap,
      upgraded,
      comments,
    );
    server.listen(harness._handle);
    addTearDown(() async {
      await client.dispose();
      await server.close(force: true);
    });
    if (authenticated) await login(client, owner);
    return harness;
  }

  bool isVisibilityCheck(HttpRequest request) =>
      request.uri.path.endsWith('/friend_workouts') &&
      request.uri.queryParameters['select'] == 'id';

  bool isPage(HttpRequest request) =>
      request.uri.path.endsWith('/friend_workouts') &&
      !isVisibilityCheck(request);

  void expectHistoryQueries() {
    for (final uri in pages) {
      expect(uri.queryParameters['user_id'], 'eq.$anotherOwner');
      expect(uri.queryParameters['limit'], '1000');
      expect(uri.queryParameters['offset'], isNull);
      expect(
        uri.queryParameters['order'],
        'performed_at.desc.nullslast,id.desc.nullslast',
      );
    }
    for (final uri in visibilityChecks) {
      expect(uri.queryParameters['user_id'], 'eq.$anotherOwner');
      expect(uri.queryParameters['select'], 'id');
      expect(uri.queryParameters['limit'], '1');
      expect(uri.queryParameters['or'], isNull);
    }
  }

  Future<void> _handle(HttpRequest request) async {
    requests.add(request.uri);
    if (isVisibilityCheck(request)) visibilityChecks.add(request.uri);
    if (isPage(request)) pages.add(request.uri);
    await beforeRequest?.call(request);
    request.response.headers.contentType = ContentType.json;
    final endpoint = request.uri.path.split('/').last;
    Object body;
    if ((isPage(request) && failPage == pages.length) ||
        (isVisibilityCheck(request) && failVisibility)) {
      request.response.statusCode = 400;
      body = {'message': 'synthetic read failure', 'code': 'XX000'};
    } else if (endpoint == 'friend_profiles') {
      expect(request.method, 'GET');
      body = {
        'user_id': owner,
        'display_name': 'Viewer',
        if (upgraded) 'avatar_path': null,
      };
    } else if (endpoint == 'friend_workouts') {
      expect(request.method, 'GET');
      expect(request.uri.queryParameters['user_id'], 'eq.$anotherOwner');
      if (isVisibilityCheck(request)) {
        body = sharing && rows.isNotEmpty
            ? [
                {'id': rows.first['id']},
              ]
            : [];
      } else {
        body = pageOverrides[pages.length] ?? _page(request.uri);
      }
    } else if (endpoint == 'latest_friend_workouts') {
      body = rows.take(1).toList();
    } else if (endpoint == 'list_friend_connections') {
      body = [
        {'requester': owner, 'recipient': anotherOwner, 'status': 'accepted'},
        {'requester': owner, 'recipient': 'pending', 'status': 'pending'},
      ];
    } else {
      fail('Unexpected endpoint: ${request.uri}');
    }
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  List<Map<String, dynamic>> _page(Uri uri) {
    if (!sharing) return [];
    var filtered = rows.toList();
    final filter = uri.queryParameters['or'];
    if (filter != null) {
      final match = RegExp(
        r'^\(performed_at\.lt\."([^"]+)",and\(performed_at\.eq\."([^"]+)",id\.lt\."([^"]+)"\)\)$',
      ).firstMatch(filter);
      expect(
        match,
        isNotNull,
        reason: 'Expected a quoted PostgREST tuple filter',
      );
      expect(match![1], match[2]);
      final cursorTime = DateTime.parse(match[1]!);
      final cursorId = match[3]!;
      filtered = filtered.where((row) {
        final order = DateTime.parse(row['performed_at'] as String)
            .compareTo(cursorTime);
        return order < 0 ||
            (order == 0 && (row['id'] as String).compareTo(cursorId) < 0);
      }).toList();
    }
    filtered.sort((a, b) {
      final time = DateTime.parse(b['performed_at'] as String)
          .compareTo(DateTime.parse(a['performed_at'] as String));
      return time != 0
          ? time
          : (b['id'] as String).compareTo(a['id'] as String);
    });
    final offset = int.parse(uri.queryParameters['offset'] ?? '0');
    final limit = min<int>(
      int.parse(uri.queryParameters['limit'] ?? '1000'),
      rowCap,
    );
    return filtered.skip(offset).take(limit).toList();
  }
}
