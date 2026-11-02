import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/friends/friend_roster.dart';

Map<String, dynamic> connection(String id, {String status = 'accepted'}) => {
  'requester': 'me',
  'recipient': id,
  'status': status,
  'friend_name': id,
};
Map<String, dynamic> workout(String owner, String id, {String? updated}) => {
  'user_id': owner, 'id': id, 'updated_at': updated,
  // Deliberately unrelated to update time.
  'performed_at': owner == 'a'
      ? '2026-01-01T00:00:00Z'
      : '2026-12-01T00:00:00Z',
};

void main() {
  List<FriendRosterEntry> roster(
    List<Map<String, dynamic>> rows, {
    bool updates = true,
    bool failed = false,
  }) => friendRosterEntries(
    viewer: 'me',
    connections: [
      connection('c'),
      connection('b'),
      connection('a'),
      connection('pending', status: 'pending'),
      {'requester': 'outsider', 'recipient': 'stranger', 'status': 'accepted'},
    ],
    workouts: rows,
    updateTimesAvailable: updates,
    workoutsFailed: failed,
  );
  test('all accepted friends survive zero visible records, stable across responses', () {
    expect(roster([]).map((e) => e.userId), ['a', 'b', 'c']);
    expect(
      roster([]).every((e) => e.workout == null && !e.workoutsFailed),
      true,
    );
  });
  test(
    'orders by content update rather than exercise date; blanks come last',
    () {
      final entries = roster([
        workout('a', 'a', updated: '2026-11-02T10:00:00Z'),
        workout('b', 'b', updated: '2026-11-01T10:00:00Z'),
        workout('pending', 'hidden', updated: '2026-12-01T10:00:00Z'),
      ]);
      expect(entries.map((e) => e.userId), ['a', 'b', 'c']);
      expect(entries.last.workout, isNull);
    },
  );
  test('same timestamps and unknown timestamps use stable identity, not feed order', () {
    final same = '2026-11-02T10:00:00Z';
    final rows = [
      workout('b', 'b', updated: same),
      workout('a', 'a', updated: same),
    ];
    expect(roster(rows).map((e) => e.userId), ['a', 'b', 'c']);
    expect(roster(rows.reversed.toList()).map((e) => e.userId), [
      'a',
      'b',
      'c',
    ]);
    expect(
      roster(rows, updates: false).every((e) => e.updatedAt == null),
      true,
    );
    expect(roster([workout('b', 'b')], updates: false).map((e) => e.userId), [
      'b',
      'a',
      'c',
    ]);
  });
  test('failed reads never claim empty or retain old shared records', () {
    final entries = roster([workout('a', 'old')], failed: true);
    expect(entries.every((e) => e.workoutsFailed && e.workout == null), true);
  });
  test('missing profile keeps relationship; removed or unauthorized owners do not appear', () {
    final entries = friendRosterEntries(
      viewer: 'me',
      connections: [
        {
          'requester': 'missing-profile',
          'recipient': 'me',
          'status': 'accepted',
        },
      ],
      workouts: [workout('removed', 'stale')],
      updateTimesAvailable: true,
    );
    expect(entries.single.userId, 'missing-profile');
    expect(entries.single.displayName, isNull);
    expect(entries.single.workout, isNull);
  });
  test(
    'deletion or revoked sharing clears workout but retains accepted friend',
    () {
      expect(roster([workout('a', 'record')]).first.workout, isNotNull);
      expect(roster([]).first.workout, isNull);
    },
  );
}
