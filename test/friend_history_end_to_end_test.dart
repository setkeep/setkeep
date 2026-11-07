import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/design/workout_month_calendar.dart';
import 'package:setkeep/friends/friend_avatar_preview.dart'
    show FriendProfilePhoto;
import 'package:setkeep/friends/friends_repository.dart';
import 'package:setkeep/friends/friends_ui.dart';
import 'package:setkeep/main.dart' show RecordedSet, WorkoutDetailSummary;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'friend_profile_identity_test.dart' show owner, anotherOwner, login;

const _timestamp = '2026-11-07T10:00:00.123456+00:00';
const _historyOrder = 'performed_at.desc.nullslast,id.desc.nullslast';
const _photoPath = '$anotherOwner/synthetic.png';

String _id(int number) =>
    '00000000-0000-4000-8000-${number.toRadixString(16).padLeft(12, '0')}';

// Deliberately store rows in ascending ID order. All server timestamps tie,
// including the old sessions: the calendar must use the independent client_id
// date, while pagination must use performed_at plus ID. IDs 2 and 1 straddle
// the 1000-row boundary and together make 5 sets / 800 kg / 300 seconds.
List<Map<String, dynamic>> _records({required bool photo}) => [
  for (var number = 1; number <= 1001; number++)
    {
      'id': _id(number),
      'user_id': anotherOwner,
      'performed_at': _timestamp,
      'client_id': switch (number) {
        1 => '2026-10-03T09:00:00.000',
        2 => '2026-10-03T18:00:00.000',
        _ => '2026-11-06T12:00:00.000',
      },
      'duration_seconds': number == 1 ? 120 : (number == 2 ? 180 : 60),
      'sets': [
        for (
          var set = 0;
          set < (number == 1 ? 2 : (number == 2 ? 3 : 1));
          set++
        )
          const RecordedSet(weight: 20, reps: 8, completed: true).toJson(),
      ],
      'friend_profiles': {
        'display_name': 'Alice',
        'avatar_path': photo ? _photoPath : null,
      },
      'friend_likes': <Object>[],
    },
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'HTTP history crosses a tied 1000-row boundary into the complete old day',
    (t) => _withBackend(t, (h) async {
      await _mount(t, h);
      await _ready(t, h);
      await _expectSummary(t);
      final calendar = await _calendar(t);
      expect(calendar.selectedDay, DateTime(2026, 10, 3));
      expect(calendar.visibleMonth, DateTime(2026, 10));
      expect(calendar.recordedDates.length, 1001);
      expect(calendar.recordedDates.skip(999), [
        DateTime(2026, 10, 3, 18),
        DateTime(2026, 10, 3, 9),
      ]);
      expect(h.pageSizes, [1000, 1, 0]);
      expect(h.historyPages.length, 3);
      expect(h.historyPages.first.queryParameters['or'], isNull);
      expect(
        h.historyPages[1].queryParameters['or'],
        '(performed_at.lt."$_timestamp",and(performed_at.eq."$_timestamp",id.lt."${_id(2)}"))',
      );
      expect(
        h.historyPages[2].queryParameters['or'],
        '(performed_at.lt."$_timestamp",and(performed_at.eq."$_timestamp",id.lt."${_id(1)}"))',
      );
      expect(h.visibilityReads.length, 1);
      expect(h.feedReads, isEmpty);
      for (final number in [2, 1]) {
        await _reveal(t, find.byKey(Key('friendLike-${_id(number)}')));
        expect(find.byKey(Key('friendLike-${_id(number)}')), findsOneWidget);
      }

      // The selected ID was not in page one. Retapping the same civil day must
      // reload all pages, not revert to a bounded feed plus a one-row fallback.
      await _reveal(t, find.byKey(const Key('calendarDay3')));
      await t.tap(find.byKey(const Key('calendarDay3')));
      await t.pump();
      await _ready(t, h);
      await _expectSummary(t);
      expect((await _calendar(t)).recordedDates.length, 1001);
      expect(h.pageSizes, [1000, 1, 0, 1000, 1, 0]);
      expect(h.visibilityReads.length, 2);
      expect(h.feedReads, isEmpty);
      expect(
        h.requests.any((r) => r.uri.queryParameters.containsKey('id')),
        isFalse,
      );
    }),
  );

  testWidgets(
    'a later HTTP page failure never renders partial totals and retry is complete',
    (t) => _withBackend(t, (h) async {
      final gate = h.hold(_InterruptAt.secondPage);
      await _mount(t, h);
      await _waitFor(t, h, () => gate.requested, 'second history page');
      expect(h.pageSizes, [1000]);
      expect(find.byType(WorkoutDetailSummary), findsNothing);
      expect((await _calendarWhileLoading(t)).recordedDates, isEmpty);
      gate.release(fail: true);
      await _ready(t, h);
      await _expectEmpty(t);
      expect(
        find.text('Could not load or complete action. Retry'),
        findsOneWidget,
      );
      expect(h.visibilityReads, isEmpty);

      await _refresh(t, h);
      await _expectSummary(t);
      expect((await _calendar(t)).selectedDay, DateTime(2026, 10, 3));
      expect(h.pageSizes, [1000, 1000, 1, 0]);

      // Also remove previously displayed totals after a failed refresh.
      final refreshGate = h.hold(_InterruptAt.secondPage);
      final refreshing = t
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await t.pump();
      await _waitFor(t, h, () => refreshGate.requested, 'refresh second page');
      refreshGate.release(fail: true);
      await _ready(t, h);
      await refreshing;
      await _expectEmpty(t);
      expect(h.feedReads, isEmpty);
    }),
  );

  for (final stage in _InterruptAt.values) {
    testWidgets(
      'sharing revoked at ${stage.name} clears HTTP history before rendering totals',
      (t) => _withBackend(t, (h) async {
        final gate = h.hold(stage);
        await _mount(t, h);
        await _waitFor(t, h, () => gate.requested, stage.name);
        expect(h.pageSizes.first, 1000);
        expect(find.byType(WorkoutDetailSummary), findsNothing);
        expect((await _calendarWhileLoading(t)).recordedDates, isEmpty);
        gate.release(revoke: true);
        await _ready(t, h);
        await _expectEmpty(t);
        expect(h.visibilityReads.length, 1);
        expect(
          find.text('Could not load or complete action. Retry'),
          findsNothing,
        );

        // Recover, select the old day, then revoke again during refresh so the
        // end-to-end path also proves previously visible totals are cleared.
        h.sharing = true;
        await _refresh(t, h);
        // An initially empty history intentionally leaves the calendar in the
        // current month. Recovery must explicitly navigate to the old month.
        await _goToMonth(t, DateTime(2026, 10));
        await _reveal(t, find.byKey(const Key('calendarDay3')));
        await t.tap(find.byKey(const Key('calendarDay3')));
        await t.pump();
        await _ready(t, h);
        await _expectSummary(t);
        final refreshGate = h.hold(stage);
        final refreshing = t
            .widget<RefreshIndicator>(find.byType(RefreshIndicator))
            .onRefresh();
        await t.pump();
        await _waitFor(t, h, () => refreshGate.requested, 'revoked refresh');
        refreshGate.release(revoke: true);
        await _ready(t, h);
        await refreshing;
        await _expectEmpty(t);
        expect(h.feedReads, isEmpty);
      }),
    );
  }

  testWidgets(
    'photo preview retains bounded feed checks while closing reloads full history',
    (t) => _withBackend(t, (h) async {
      await _mount(t, h);
      await _ready(t, h);
      await _waitFor(
        t,
        h,
        () =>
            h.photoDownloads > 0 &&
            _hasPixels(within: find.byType(FriendProfilePhoto)),
        'profile photo',
      );
      await _expectSummary(t);
      await _reveal(t, find.byKey(const Key('viewFriendProfilePhoto')));
      final historyReads = h.historyPages.length;
      final visibilityReads = h.visibilityReads.length;
      await t.tap(find.byKey(const Key('viewFriendProfilePhoto')));
      await t.pump();
      await _waitFor(
        t,
        h,
        () =>
            _hasPixels(
              within: find.byKey(const Key('friendProfilePhotoPreview')),
            ) &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty,
        'validated photo preview',
      );
      expect(find.byKey(const Key('friendProfilePhotoImage')), findsOneWidget);
      expect(h.historyPages.length, historyReads);
      expect(h.visibilityReads.length, visibilityReads);
      // Supabase replays the current auth state to the preview subscription.
      // That can trigger another validation cycle in addition to initState.
      // Each cycle must still use two bounded reads, never history pagination.
      final previewFeedReads = h.feedReads.length;
      expect(previewFeedReads, greaterThanOrEqualTo(2));
      expect(previewFeedReads.isEven, isTrue);
      for (final uri in h.feedReads) {
        expect(uri.queryParameters['limit'], '1000');
        expect(uri.queryParameters['order'], 'performed_at.desc.nullslast');
        expect(uri.queryParameters['or'], isNull);
      }
      expect(h.feedSizes, hasLength(previewFeedReads));
      expect(h.feedSizes, everyElement(1000));
      await t.tap(find.byKey(const Key('dismissFriendProfilePhoto')));
      await t.pump();
      await _waitFor(
        t,
        h,
        () =>
            h.historyPages.length == historyReads + 3 &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty,
        'history refresh after closing photo',
      );
      await _expectSummary(t);
      expect(h.visibilityReads.length, visibilityReads + 1);
      expect(h.feedReads.length, previewFeedReads);
    }, photo: true),
  );
}

Future<void> _mount(WidgetTester t, _HistoryBackend h) async {
  t.view.physicalSize = const Size(390, 1100);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MaterialApp(
      home: FriendActivityPage(
        repository: h.repository,
        owner: anotherOwner,
        selectedId: _id(1),
      ),
    ),
  );
}

// Real sockets advance only in runAsync; Flutter state/animation continuations
// advance in pump. Avoid pumpAndSettle while an intentionally held request or
// network-backed progress indicator is pending.
Future<void> _waitFor(
  WidgetTester t,
  _HistoryBackend h,
  bool Function() condition,
  String description,
) async {
  for (var attempt = 0; attempt < 500; attempt++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump(const Duration(milliseconds: 16));
    expect(h.errors, isEmpty, reason: 'Synthetic HTTP backend failed');
    if (condition()) return;
  }
  fail('Timed out waiting for $description. Requests: ${h.requests}');
}

Future<void> _ready(WidgetTester t, _HistoryBackend h) async {
  // The ListView builds lazily. Bring its progress indicator back into view
  // before using absence of that indicator as the completion signal.
  t.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
  await t.pump();
  await _waitFor(
    t,
    h,
    () =>
        h.historyPages.isNotEmpty &&
        find.byType(LinearProgressIndicator).evaluate().isEmpty,
    'complete history load',
  );
}

Future<void> _reveal(WidgetTester t, Finder target) async {
  t.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
  await t.pumpAndSettle();
  await t.scrollUntilVisible(
    target,
    150,
    scrollable: find.byType(Scrollable).first,
  );
  await t.ensureVisible(target);
  await t.pumpAndSettle();
}

Future<WorkoutMonthCalendar> _calendar(WidgetTester t) async {
  await _reveal(t, find.byKey(const Key('monthlyCalendar')));
  return t.widget<WorkoutMonthCalendar>(find.byType(WorkoutMonthCalendar));
}

Future<WorkoutMonthCalendar> _calendarWhileLoading(WidgetTester t) async {
  // At the top of this 1100px viewport the calendar is already built. Do not
  // settle the intentionally running progress indicator.
  await t.pump();
  return t.widget<WorkoutMonthCalendar>(find.byType(WorkoutMonthCalendar));
}

Future<void> _expectSummary(WidgetTester t) async {
  await _reveal(t, find.byKey(const Key('workoutDetailSummary')));
  final finder = find.byType(WorkoutDetailSummary);
  final summary = t.widget<WorkoutDetailSummary>(finder);
  expect(summary.workout.date, DateTime(2026, 10, 3));
  expect(summary.workout.sets.length, 5);
  expect(summary.workout.volume, 800);
  expect(summary.workout.durationSeconds, 300);
  for (final text in ['5 セット', '800 kg', '5分']) {
    expect(
      find.descendant(of: finder, matching: find.text(text)),
      findsOneWidget,
    );
  }
}

Future<void> _expectEmpty(WidgetTester t) async {
  await _reveal(t, find.text('No visible workouts'));
  expect(find.text('No visible workouts'), findsOneWidget);
  expect(find.text('Alice'), findsNothing);
  expect(find.byType(WorkoutDetailSummary), findsNothing);
  expect((await _calendar(t)).recordedDates, isEmpty);
  expect(find.byKey(Key('friendLike-${_id(1)}')), findsNothing);
  expect(find.byKey(Key('friendLike-${_id(2)}')), findsNothing);
}

Future<void> _refresh(WidgetTester t, _HistoryBackend h) async {
  final refreshing = t
      .widget<RefreshIndicator>(find.byType(RefreshIndicator))
      .onRefresh();
  await t.pump();
  await _ready(t, h);
  await refreshing;
}

bool _hasPixels({required Finder within}) {
  final pixels = find.byWidgetPredicate(
    (w) => w is RawImage && w.image != null,
  );
  return find.descendant(of: within, matching: pixels).evaluate().isNotEmpty;
}

Future<void> _goToMonth(WidgetTester t, DateTime target) async {
  final current = (await _calendar(t)).visibleMonth;
  final difference =
      (target.year - current.year) * 12 + target.month - current.month;
  final arrow = find.byTooltip(
    difference < 0 ? 'Previous month' : 'Next month',
  );
  for (var step = 0; step < difference.abs(); step++) {
    await _reveal(t, arrow);
    await t.tap(arrow);
    await t.pumpAndSettle();
  }
  expect((await _calendar(t)).visibleMonth, target);
}

// Let Flutter encode a synthetic image rather than embedding an unchecked PNG
// fixture. Its pixels are distinct from all exercise thumbnails on the page.
Future<Uint8List> _makePhoto() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xFF267CB5), ui.BlendMode.src);
  canvas.drawRect(
    const ui.Rect.fromLTWH(2, 2, 4, 4),
    ui.Paint()..color = const ui.Color(0xFFFFCC33),
  );
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(8, 8);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('Could not encode the synthetic photo');
      }
      return Uint8List.fromList(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

Future<void> _withBackend(
  WidgetTester t,
  Future<void> Function(_HistoryBackend) exercise, {
  bool photo = false,
}) async {
  final server = (await t.runAsync(
    () => HttpServer.bind(InternetAddress.loopbackIPv4, 0),
  ))!;
  final previousOverrides = HttpOverrides.current;
  final previousImageProvider = debugNetworkImageHttpClientProvider;
  final transport = _LoopbackOnlyHttpOverrides(server.port);
  HttpOverrides.global = transport;
  final imageClient = transport.createHttpClient(null);
  debugNetworkImageHttpClientProvider = () => imageClient;
  _HistoryBackend? backend;
  try {
    backend = (await t.runAsync(() async {
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'synthetic',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final bytes = photo ? await _makePhoto() : null;
      final h = _HistoryBackend(server, client, photoBytes: bytes);
      server.listen(h.handle);
      await login(client, owner);
      return h;
    }))!;
    await exercise(backend);
    expect(backend.errors, isEmpty);
    expect(t.takeException(), isNull);
  } finally {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump();
    final h = backend;
    await t.runAsync(() async {
      h?.releaseHeldRequests();
      if (h != null) await h.client.dispose();
      transport.close();
      await server.close(force: true);
    });
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    debugNetworkImageHttpClientProvider = previousImageProvider;
    HttpOverrides.global = previousOverrides;
  }
}

// This is a real HttpClient, not the test binding's always-400 mock. Its socket
// factory refuses every destination except this test's exact loopback server,
// so a mistaken production URL cannot produce an external request.
class _LoopbackOnlyHttpOverrides extends HttpOverrides {
  _LoopbackOnlyHttpOverrides(this.port);
  final int port;
  final _clients = <HttpClient>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (_) => 'DIRECT';
    client.connectionFactory = (uri, proxyHost, proxyPort) {
      if (uri.scheme != 'http' ||
          uri.host != '127.0.0.1' ||
          uri.port != port ||
          proxyHost != null ||
          proxyPort != null) {
        throw StateError('Only the synthetic loopback backend is permitted');
      }
      return Socket.startConnect(InternetAddress.loopbackIPv4, port);
    };
    _clients.add(client);
    return client;
  }

  void close() {
    for (final client in _clients) {
      client.close(force: true);
    }
  }
}

enum _InterruptAt { secondPage, visibility }

class _ReadGate {
  _ReadGate(this.stage);
  final _InterruptAt stage;
  final _released = Completer<void>();
  bool requested = false;
  bool fail = false;
  bool revoke = false;

  void release({bool fail = false, bool revoke = false}) {
    this.fail = fail;
    this.revoke = revoke;
    if (!_released.isCompleted) _released.complete();
  }
}

class _HistoryBackend {
  _HistoryBackend(this.server, this.client, {required this.photoBytes})
    : rows = _records(photo: photoBytes != null),
      repository = FriendsRepository(client, commentsEnabled: false);

  final Uint8List? photoBytes;

  final HttpServer server;
  final SupabaseClient client;
  final FriendsRepository repository;
  final List<Map<String, dynamic>> rows;
  final requests = <({String method, Uri uri})>[];
  final historyPages = <Uri>[];
  final feedReads = <Uri>[];
  final visibilityReads = <Uri>[];
  final pageSizes = <int>[];
  final feedSizes = <int>[];
  final errors = <Object>[];
  final _gates = <_ReadGate>[];
  _ReadGate? _pendingGate;
  int _pageInScan = 0;
  int photoDownloads = 0;
  bool sharing = true;

  _ReadGate hold(_InterruptAt stage) {
    final gate = _ReadGate(stage);
    _pendingGate = gate;
    _gates.add(gate);
    return gate;
  }

  void releaseHeldRequests() {
    for (final gate in _gates) {
      gate.release();
    }
  }

  Future<void> handle(HttpRequest request) async {
    final uri = request.uri;
    requests.add((method: request.method, uri: uri));
    request.response.headers.contentType = ContentType.json;
    try {
      Object body;
      if (uri.path == '/rest/v1/friend_profiles') {
        _require(request.method == 'GET', 'Unexpected profile write');
        _require(uri.queryParameters['user_id'] == 'eq.$owner', 'Wrong viewer');
        body = {
          'user_id': owner,
          'display_name': 'Viewer',
          'avatar_path': null,
        };
      } else if (uri.path == '/rest/v1/friend_workouts') {
        _require(request.method == 'GET', 'Unexpected workout write');
        _require(
          uri.queryParameters['user_id'] == 'eq.$anotherOwner',
          'Wrong friend',
        );
        _require(
          !uri.queryParameters.containsKey('id'),
          'Unexpected exact-row fallback',
        );
        _require(
          !uri.queryParameters.containsKey('offset'),
          'Unexpected offset pagination',
        );
        final visibility = uri.queryParameters['select'] == 'id';
        final history =
            !visibility && uri.queryParameters['order'] == _historyOrder;
        if (visibility) {
          visibilityReads.add(uri);
          _require(
            uri.queryParameters['limit'] == '1',
            'Wrong visibility limit',
          );
          _require(
            uri.queryParameters['or'] == null,
            'Visibility must recheck without a cursor',
          );
        } else if (history) {
          historyPages.add(uri);
          _pageInScan = uri.queryParameters['or'] == null ? 1 : _pageInScan + 1;
          _require(
            uri.queryParameters['limit'] == '1000',
            'Wrong history limit',
          );
        } else {
          feedReads.add(uri);
        }
        final gate = _pendingGate;
        if (gate != null &&
            ((gate.stage == _InterruptAt.secondPage &&
                    history &&
                    _pageInScan == 2) ||
                (gate.stage == _InterruptAt.visibility && visibility))) {
          _pendingGate = null;
          gate.requested = true;
          await gate._released.future;
          if (gate.revoke) sharing = false;
          if (gate.fail) {
            request.response.statusCode = HttpStatus.badRequest;
            request.response.write(
              jsonEncode({
                'message': 'Synthetic second-page failure',
                'code': 'XX000',
              }),
            );
            return;
          }
        }
        if (visibility) {
          body = sharing
              ? [
                  {'id': rows.first['id']},
                ]
              : <Object>[];
        } else {
          final page = _select(uri);
          (history ? pageSizes : feedSizes).add(page.length);
          body = page;
        }
      } else if (uri.path == '/rest/v1/friend_likes') {
        _require(request.method == 'GET', 'Unexpected like write');
        _require(
          [
            _id(1),
            _id(2),
          ].any((id) => uri.queryParameters['workout_id'] == 'eq.$id'),
          'Unexpected day likes',
        );
        body = <Object>[];
      } else if (uri.path ==
              '/storage/v1/object/sign/friend-avatars/$_photoPath' &&
          request.method == 'GET') {
        _require(
          uri.queryParameters['token'] == 'synthetic',
          'Wrong photo token',
        );
        photoDownloads++;
        request.response.headers.contentType = ContentType('image', 'png');
        _require(photoBytes != null, 'No photo fixture was configured');
        request.response.add(photoBytes!);
        return;
      } else if (uri.path ==
          '/storage/v1/object/sign/friend-avatars/$_photoPath') {
        _require(request.method == 'POST', 'Expected signed URL request');
        final payload =
            jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        _require(payload['expiresIn'] == 60, 'Wrong photo URL expiry');
        body = {
          'signedURL':
              '/object/sign/friend-avatars/$_photoPath?token=synthetic',
        };
      } else {
        throw StateError('Unexpected endpoint: ${request.method} $uri');
      }
      request.response.write(jsonEncode(body));
    } catch (error) {
      errors.add(error);
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write(
        jsonEncode({'message': '$error', 'code': 'SYNTHETIC'}),
      );
    } finally {
      await request.response.close();
    }
  }

  List<Map<String, dynamic>> _select(Uri uri) {
    if (!sharing) return [];
    var selected = rows.toList();
    final filter = uri.queryParameters['or'];
    if (filter != null) {
      final match = RegExp(
        r'^\(performed_at\.lt\."([^"]+)",and\(performed_at\.eq\."([^"]+)",id\.lt\."([^"]+)"\)\)$',
      ).firstMatch(filter);
      _require(
        match != null && match[1] == match[2],
        'Invalid keyset filter: $filter',
      );
      final time = DateTime.parse(match![1]!);
      final id = match[3]!;
      selected = selected.where((row) {
        final compared = DateTime.parse(row['performed_at'] as String)
            .compareTo(time);
        return compared < 0 ||
            (compared == 0 && (row['id'] as String).compareTo(id) < 0);
      }).toList();
    }
    // Follow the requested SQL order rather than handing back canned pages.
    final order = (uri.queryParameters['order'] ?? '').split(',');
    selected.sort((a, b) {
      for (final item in order) {
        final parts = item.split('.');
        final field = parts.first;
        _require(
          field == 'performed_at' || field == 'id',
          'Unexpected order: $item',
        );
        final compared = field == 'performed_at'
            ? DateTime.parse(a[field] as String)
                  .compareTo(DateTime.parse(b[field] as String))
            : (a[field] as String).compareTo(b[field] as String);
        if (compared != 0) return parts[1] == 'desc' ? -compared : compared;
      }
      return 0;
    });
    return selected
        .take(min(1000, int.parse(uri.queryParameters['limit']!)))
        .toList();
  }

  void _require(bool valid, String message) {
    if (!valid) throw StateError(message);
  }
}
