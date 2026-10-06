import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/friends/friend_snapshot_journal.dart';

class MemorySnapshotStore implements FriendSnapshotStore {
  final values = <String, String>{};
  String? failKey;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<bool> write(String key, String value) async {
    if (key == failKey) return false;
    values[key] = value;
    return true;
  }
}

Map<String, dynamic> record(String date, {String? owner = 'A'}) => {
  'date': date,
  'durationSeconds': 10,
  'sets': [],
  'friendOwnerUserId': ?owner,
};
void main() {
  late MemorySnapshotStore store;
  late FriendSnapshotJournal journal;
  setUp(() {
    store = MemorySnapshotStore();
    journal = FriendSnapshotJournal(store: store);
    store.values[FriendSnapshotJournal.historyKey] = jsonEncode([
      record('deleted'),
      record('kept'),
    ]);
  });
  test(
    'legacy history and unverified old journal never guess ownership',
    () async {
      store.values[FriendSnapshotJournal.historyKey] = jsonEncode([
        record('legacy', owner: null),
      ]);
      store.values[FriendSnapshotJournal.journalKey] = jsonEncode({
        'version': 1,
        'revision': 2,
        'lastOwner': 'B',
        'deletions': {
          'B': {
            'old': {'revision': 2, 'pending': true},
          },
        },
      });
      await journal.saveHistory([], expectedOwner: 'B', queuePublication: true);
      final batch = await journal.batch('B');
      expect(batch.pending, false);
      expect(batch.deletions, isEmpty);
      final state = jsonDecode(store.values[FriendSnapshotJournal.journalKey]!);
      expect(state['deletions']['B']['old']['pending'], true);
    },
  );
  test('owned publication survives restart and newer revision survives late receipt', () async {
    await journal.saveHistory(
      [record('new')],
      expectedOwner: 'A',
      queuePublication: true,
    );
    final old = await journal.batch('A');
    expect(old.publications.keys, ['new']);
    expect((await journal.batch('B')).pending, false);
    await journal.saveHistory(
      [
        {...record('new'), 'durationSeconds': 20},
      ],
      expectedOwner: 'A',
      queuePublication: true,
    );
    journal = FriendSnapshotJournal(store: store);
    await journal.acknowledge(
      'A',
      old.deletions,
      publications: old.publications,
    );
    final current = await journal.batch('A');
    expect(current.pending, true);
    expect(current.publications['new'], greaterThan(old.publications['new']!));
    await journal.acknowledge(
      'A',
      current.deletions,
      publications: current.publications,
    );
    expect((await journal.batch('A')).pending, false);
  });
  test('deleting a queued record removes publication and journals only proved deletion', () async {
    await journal.saveHistory(
      [record('new')],
      expectedOwner: 'A',
      queuePublication: true,
    );
    await journal.saveHistory([], expectedOwner: 'A', queuePublication: true);
    final batch = await journal.batch('A');
    expect(batch.publications, isEmpty);
    expect(batch.deletions.keys, unorderedEquals(['deleted', 'kept', 'new']));
    expect((await journal.batch('B')).pending, false);
  });
  test(
    'offline deletion survives restart with only owner/date intent',
    () async {
      await journal.saveHistory([record('kept')], expectedOwner: 'A');
      final batch = await FriendSnapshotJournal(store: store).batch('A');
      expect(batch.pending, true);
      expect(batch.deletions.keys, ['deleted']);
      expect(batch.history!.map((r) => r['date']), ['kept']);
      final saved = jsonDecode(store.values[FriendSnapshotJournal.journalKey]!);
      expect(saved.containsKey('preparedHistory'), false);
      expect(saved.toString(), isNot(contains('durationSeconds')));
    },
  );
  test('no account never guesses the next login as deletion owner', () async {
    await journal.saveHistory([], expectedOwner: null);
    await journal.rememberOwner('B');
    expect((await journal.batch('B')).deletions, isEmpty);
  });
  test('signed-out deletion belongs to last owner, not new account', () async {
    await journal.rememberOwner('A');
    final captured = await journal.lastOwner();
    await journal.rememberOwner('B');
    await journal.saveHistory([record('kept')], expectedOwner: captured);
    await journal.rememberOwner('B');
    expect((await journal.batch('B')).deletions, isEmpty);
    expect((await journal.batch('A')).deletions.keys, ['deleted']);
  });
  test(
    'captured owner survives account switch during local operation',
    () async {
      await journal.rememberOwner('B');
      await journal.saveHistory([record('kept')], expectedOwner: 'A');
      expect((await journal.batch('A')).pending, true);
      expect((await journal.batch('B')).pending, false);
      expect(
        jsonDecode(
          store.values[FriendSnapshotJournal.journalKey]!,
        )['lastOwner'],
        'B',
      );
    },
  );
  test(
    'journal write failure leaves local history and intent unchanged',
    () async {
      final before = store.values[FriendSnapshotJournal.historyKey];
      store.failKey = FriendSnapshotJournal.journalKey;
      await expectLater(
        journal.saveHistory([], expectedOwner: 'A'),
        throwsStateError,
      );
      expect(store.values[FriendSnapshotJournal.historyKey], before);
      expect(store.values.containsKey(FriendSnapshotJournal.journalKey), false);
    },
  );
  test('crash between writes repairs history before sync', () async {
    store.failKey = FriendSnapshotJournal.historyKey;
    await expectLater(
      journal.saveHistory([record('kept')], expectedOwner: 'A'),
      throwsStateError,
    );
    await expectLater(journal.batch('A'), throwsStateError);
    store.failKey = null;
    final restarted = FriendSnapshotJournal(store: store);
    expect(jsonDecode((await restarted.recoverHistory())!).length, 1);
    expect((await restarted.batch('A')).deletions.keys, ['deleted']);
  });
  test('ack retains tombstone; Undo restores and cancels deletion', () async {
    await journal.saveHistory([record('kept')], expectedOwner: 'A');
    await journal.acknowledge('A', (await journal.batch('A')).deletions);
    expect((await journal.batch('A')).pending, false);
    expect((await journal.batch('A')).deletions.keys, ['deleted']);
    await journal.saveHistory([
      record('deleted'),
      record('kept'),
    ], expectedOwner: 'A');
    expect((await journal.batch('A')).deletions, isEmpty);
  });
  test(
    'late ack cannot clear a newer deletion after Undo and re-delete',
    () async {
      await journal.saveHistory([record('kept')], expectedOwner: 'A');
      final sent = await journal.batch('A');
      await journal.saveHistory([
        record('deleted'),
        record('kept'),
      ], expectedOwner: 'A');
      await journal.saveHistory([record('kept')], expectedOwner: 'A');
      await journal.acknowledge('A', sent.deletions);
      final current = await journal.batch('A');
      expect(current.pending, true);
      expect(current.deletions['deleted'], isNot(sent.deletions['deleted']));
    },
  );
  test(
    'other trainer owner records cannot enqueue deletion for current account',
    () async {
      store.values[FriendSnapshotJournal.historyKey] = jsonEncode([
        record('other-trainer', owner: 'B'),
        record('own-trainer', owner: 'A'),
        record('general', owner: null),
      ]);
      await journal.saveHistory([], expectedOwner: 'A');
      expect(
        (await journal.batch('A')).deletions.keys,
        unorderedEquals(['own-trainer']),
      );
      expect((await journal.batch('B')).deletions, isEmpty);
    },
  );
  test('malformed legacy history retains graceful save behavior', () async {
    store.values[FriendSnapshotJournal.historyKey] = 'broken JSON';
    await journal.saveHistory([record('new')], expectedOwner: 'A');
    expect((await journal.batch('A')).deletions, isEmpty);
    expect((await journal.batch('A')).history!.single['date'], 'new');
  });
  test(
    'unknown journal version fails closed without changing history',
    () async {
      final before = store.values[FriendSnapshotJournal.historyKey];
      store.values[FriendSnapshotJournal.journalKey] = '{"version":2}';
      await expectLater(
        journal.saveHistory([], expectedOwner: 'A'),
        throwsFormatException,
      );
      expect(store.values[FriendSnapshotJournal.historyKey], before);
    },
  );
}
