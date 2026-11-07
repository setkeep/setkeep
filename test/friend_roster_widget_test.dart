import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setkeep/friends/friends_tab_page.dart';
import 'package:setkeep/friends/friends_ui.dart';

import 'friends_mvp_test.dart' show FakeFriends;

class RosterFriends extends FakeFriends {
  List<String> ids = ['c', 'b', 'a'];
  List<Map<String, dynamic>> records = [];
  Completer<void>? gate;
  bool connectionFailure = false;
  @override
  bool get supportsWorkoutUpdates => true;
  @override
  Future<List<Map<String, dynamic>>> connections() async {
    if (connectionFailure) throw StateError('connection read failed');
    return [
      for (final id in ids)
        {
          'requester': 'me',
          'recipient': id,
          'status': 'accepted',
          if (id != 'c') 'friend_name': 'Friend $id',
        },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> latestUpdates() async {
    final snapshot = [...records];
    await gate?.future;
    if (this.fail) throw StateError('workout read failed');
    return snapshot;
  }
}

Map<String, dynamic> record(String owner, String update) => {
  'id': 'record-$owner',
  'user_id': owner,
  'updated_at': update,
  'performed_at': owner == 'a'
      ? '2026-01-01T00:00:00Z'
      : '2026-12-01T00:00:00Z',
  'duration_seconds': 60,
  'sets': [],
  'friend_likes': [],
};

class PagedFriends extends RosterFriends {
  bool exactVisible = true;
  @override
  bool get commentsEnabled => false;
  @override
  Future<List<Map<String, dynamic>>> feed({String? owner}) async => [
    for (var i = 0; i < 1000; i++)
      {
        ...record('a', '2026-11-02T00:00:00Z'),
        'id': 'page-$i',
        'performed_at': '2026-10-30T00:00:00Z',
        'friend_profiles': {'display_name': 'Paged friend'},
      },
  ];
  @override
  Future<List<Map<String, dynamic>>> history({required String owner}) async => [
    ...await feed(owner: owner),
    if (exactVisible) (await historyWorkoutById('old-edited', owner))!,
  ];
  @override
  Future<Map<String, dynamic>?> historyWorkoutById(
    String id,
    String owner,
  ) async => exactVisible
      ? {
          ...record('a', '2026-11-02T00:00:00Z'),
          'id': id,
          'friend_profiles': {'display_name': 'Paged friend'},
        }
      : null;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> show(
    WidgetTester t,
    RosterFriends repo, {
    bool english = false,
  }) async {
    await t.pumpWidget(
      MaterialApp(
        locale: Locale(english ? 'en' : 'ja'),
        supportedLocales: const [Locale('ja'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: FriendsTabPage(history: const [], repository: repo),
      ),
    );
    await t.pumpAndSettle();
  }

  Finder card(String id) => find.byKey(ValueKey('friendCard-$id'));
  testWidgets(
    'every accepted friend, including missing profile, has an empty card',
    (t) async {
      final repo = RosterFriends();
      await show(t, repo);
      expect(find.text('共有された記録はまだありません'), findsNWidgets(3));
      for (final id in repo.ids) {
        final tile = t.widget<ListTile>(
          find.descendant(of: card(id), matching: find.byType(ListTile)),
        );
        expect(tile.onTap, isNull);
        expect(tile.trailing, isNull);
      }
      expect(find.text('フレンド'), findsNWidgets(2));
      expect(repo.sharingAcknowledgements, 0);
      expect(repo.private, true);
    },
  );
  testWidgets(
    'updates reorder old exercise dates; deletion and revoked sharing keep blank friends',
    (t) async {
      final repo = RosterFriends()
        ..records = [
          record('b', '2026-11-01T00:00:00Z'),
          record('a', '2026-11-02T00:00:00Z'),
        ];
      await show(t, repo);
      expect(t.getTopLeft(card('a')).dy, lessThan(t.getTopLeft(card('b')).dy));
      expect(t.getTopLeft(card('b')).dy, lessThan(t.getTopLeft(card('c')).dy));
      repo.records = [];
      await FriendsRefresh.refresh();
      await t.pumpAndSettle();
      expect(find.text('共有された記録はまだありません'), findsNWidgets(3));
    },
  );
  testWidgets(
    'refresh discards cached cards; removed/blocked relationships cannot return from stale feed',
    (t) async {
      final repo = RosterFriends()
        ..records = [record('a', '2026-11-02T00:00:00Z')];
      await show(t, repo);
      repo.ids.remove('a');
      repo.gate = Completer<void>();
      final pending = FriendsRefresh.refresh();
      await t.pump();
      expect(card('a'), findsNothing);
      repo.gate!.complete();
      await pending;
      await t.pumpAndSettle();
      expect(card('a'), findsNothing);
      expect(card('b'), findsOneWidget);
      repo.gate = null;
      repo.ids.add('a');
      await FriendsRefresh.refresh();
      await t.pumpAndSettle();
      expect(card('a'), findsOneWidget);
    },
  );
  testWidgets(
    'network failure is not empty; retry restores records; failed relationships clear roster',
    (t) async {
      final repo = RosterFriends()..fail = true;
      await show(t, repo, english: true);
      expect(find.text('No shared workouts yet'), findsNothing);
      expect(find.text('Could not load shared workouts'), findsNWidgets(3));
      repo.fail = false;
      await t.tap(find.text('Could not load. Retry'));
      await t.pumpAndSettle();
      expect(find.text('No shared workouts yet'), findsNWidgets(3));
      repo.connectionFailure = true;
      await FriendsRefresh.refresh();
      await t.pumpAndSettle();
      expect(card('a'), findsNothing);
      expect(find.text('Could not load. Retry'), findsOneWidget);
    },
  );
  testWidgets('newer refresh wins over an older response', (t) async {
    final repo = RosterFriends();
    await show(t, repo);
    repo.gate = Completer<void>();
    final gate = repo.gate!;
    final stale = FriendsRefresh.refresh();
    await t.pump();
    repo.gate = null;
    repo.ids = ['b'];
    await FriendsRefresh.refresh();
    gate.complete();
    await stale;
    await t.pumpAndSettle();
    expect(card('a'), findsNothing);
    expect(card('b'), findsOneWidget);
  });
  testWidgets(
    'recently edited old record opens beyond 1000 rows and exact revocation clears it',
    (t) async {
      final repo = PagedFriends();
      await t.pumpWidget(
        MaterialApp(
          home: FriendActivityPage(
            repository: repo,
            owner: 'a',
            selectedId: 'old-edited',
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('2026/1'), findsOneWidget);
      repo.exactVisible = false;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('No workouts on this day'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('No workouts on this day'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
}
