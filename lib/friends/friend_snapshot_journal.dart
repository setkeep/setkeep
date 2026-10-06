import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'friend_workout_owner.dart';

abstract class FriendSnapshotStore {
  Future<String?> read(String key);
  Future<bool> write(String key, String value);
}

class _PreferenceStore implements FriendSnapshotStore {
  const _PreferenceStore([this.preferences]);
  final SharedPreferences? preferences;
  @override
  Future<String?> read(String key) async =>
      (preferences ?? await SharedPreferences.getInstance()).getString(key);
  @override
  Future<bool> write(String key, String value) async =>
      (preferences ?? await SharedPreferences.getInstance()).setString(
        key,
        value,
      );
}

class FriendSnapshotBatch {
  const FriendSnapshotBatch(
    this.deletions,
    this.pending,
    this.history,
    this.deviceId,
    this.revision, {
    this.publications = const {},
  });
  final Map<String, int> deletions;
  final bool pending;
  final List<Map<String, dynamic>>? history;
  final String deviceId;
  final int revision;
  final Map<String, int> publications;
}

/// Durable, account-bound deletion and explicit publication intents. No
/// credentials or workout bodies
/// are sent by the journal. The temporary history entry repairs a crash between
/// the journal write and the existing workout_history preference write.
class FriendSnapshotJournal {
  FriendSnapshotJournal({FriendSnapshotStore? store})
    : _store = store ?? const _PreferenceStore();
  static const historyKey = 'workout_history';
  static const journalKey = 'friend_snapshot_deletions_v1';
  final FriendSnapshotStore _store;
  static final _queues = Expando<Future<void>>();
  static final _storeZoneKey = Object();
  FriendSnapshotStore get _activeStore =>
      Zone.current[_storeZoneKey] as FriendSnapshotStore? ?? _store;

  Future<T> _serialized<T>(Future<T> Function() action) async {
    // Share a lock only for the same actual preference store. Binding the store
    // for the whole operation also prevents an old request from using a replaced
    // preference cache (e.g. after reset in a test or a different injected store).
    final store = _store is _PreferenceStore
        ? _PreferenceStore(await SharedPreferences.getInstance())
        : _store;
    final identity = store is _PreferenceStore ? store.preferences! : store;
    final previous = _queues[identity] ?? Future<void>.value();
    final next = previous.then(
      (_) => runZoned(action, zoneValues: {_storeZoneKey: store}),
    );
    _queues[identity] = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<Map<String, dynamic>> _read({bool persistDevice = false}) async {
    final encoded = await _activeStore.read(journalKey);
    final state = encoded == null
        ? <String, dynamic>{
            'version': 1,
            'revision': 0,
            'deletions': <String, dynamic>{},
          }
        : Map<String, dynamic>.from(jsonDecode(encoded) as Map);
    if (state['version'] != 1 ||
        state['revision'] is! int ||
        state['deletions'] is! Map) {
      throw const FormatException('Invalid friend deletion journal');
    }
    if (state['deviceId'] == null) {
      final random = Random.secure();
      final bytes = List.generate(16, (_) => random.nextInt(256));
      bytes[6] = (bytes[6] & 15) | 64;
      bytes[8] = (bytes[8] & 63) | 128;
      final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      state['deviceId'] =
          '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
      if (persistDevice) await _write(state);
    }
    return state;
  }

  Future<void> _write(Map<String, dynamic> state) async {
    if (!await _activeStore.write(journalKey, jsonEncode(state))) {
      throw StateError('Friend deletion intent could not be saved');
    }
  }

  Future<void> _recover(Map<String, dynamic> state) async {
    final prepared = state['preparedHistory'] as String?;
    if (prepared == null) return;
    if (!await _activeStore.write(historyKey, prepared)) {
      throw StateError('Workout history could not be saved');
    }
    state.remove('preparedHistory');
    await _write(state);
  }

  static List<Map<String, dynamic>>? _history(String? encoded) {
    if (encoded == null) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return null;
      return decoded
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .where((row) => row['date'] is String)
          .toList();
    } on FormatException {
      // Match the existing history loader's handling of malformed old data.
      return null;
    }
  }

  Future<String?> recoverHistory() => _serialized(() async {
    await _recover(await _read());
    return _activeStore.read(historyKey);
  });

  Future<void> rememberOwner(String owner) => _serialized(() async {
    final state = await _read();
    if (state['lastOwner'] == owner) return;
    state['lastOwner'] = owner;
    await _write(state);
  });

  Future<String?> lastOwner() =>
      _serialized(() async => (await _read())['lastOwner'] as String?);

  /// Record the local change and deletion intent before any network request.
  /// The caller captures the signed-in/last owner at the user's action, before
  /// waiting on mutations. A null owner never guesses a future login's identity.
  /// Restore/Undo cancels that owner's matching tombstone.
  Future<void> saveHistory(
    List<Map<String, dynamic>> records, {
    required String? expectedOwner,
    bool queuePublication = false,
  }) => _serialized(() async {
    final state = await _read();
    await _recover(state);
    final previous = _history(await _activeStore.read(historyKey)) ?? [];
    final owner = expectedOwner;
    final revision = (state['revision'] as int) + 1;
    state['revision'] = revision;
    if (owner != null) {
      Set<String> dates(List<Map<String, dynamic>> items) => items
          .where((row) => friendWorkoutOwner(row) == owner)
          .map((row) => row['date'] as String)
          .toSet();
      final before = dates(previous);
      final after = dates(records);
      final publicationAccounts =
          state.putIfAbsent('publications', () => <String, dynamic>{}) as Map;
      final publications = Map<String, dynamic>.from(
        publicationAccounts[owner] as Map? ?? {},
      );
      publications.removeWhere((date, _) => !after.contains(date));
      if (queuePublication) {
        final previousRows = {
          for (final row in previous) row['date']: jsonEncode(row),
        };
        for (final row in records.where(
          (r) => friendWorkoutOwner(r) == owner,
        )) {
          final date = row['date'] as String;
          if (previousRows[date] != jsonEncode(row)) {
            publications[date] = {'revision': revision, 'pending': true};
          }
        }
      }
      publicationAccounts[owner] = publications;
      final accounts = state['deletions'] as Map;
      final entries = Map<String, dynamic>.from(accounts[owner] as Map? ?? {});
      for (final date in before.difference(after)) {
        entries[date] = {
          'revision': revision,
          'pending': true,
          'ownershipVerified': true,
        };
      }
      for (final date in after.difference(before)) {
        entries.remove(date);
      }
      accounts[owner] = entries;
      state['lastOwner'] ??= owner;
    }
    state['preparedHistory'] = jsonEncode(records);
    await _write(state);
    await _recover(state);
  });

  Future<FriendSnapshotBatch> batch(String owner) => _serialized(() async {
    final state = await _read(persistDevice: true);
    await _recover(state);
    final entries = (state['deletions'] as Map)[owner] as Map? ?? {};
    final deletions = <String, int>{};
    var pending = false;
    final history = _history(await _activeStore.read(historyKey));
    final ownedDates = {
      for (final row in history ?? <Map<String, dynamic>>[])
        if (friendWorkoutOwner(row) == owner) row['date'],
    };
    final publications = <String, int>{};
    final queued = (state['publications'] as Map?)?[owner] as Map? ?? {};
    for (final entry in queued.entries) {
      final value = entry.value as Map;
      if (value['pending'] == true && ownedDates.contains(entry.key)) {
        publications[entry.key as String] = value['revision'] as int;
        pending = true;
      }
    }
    for (final entry in entries.entries) {
      final value = entry.value as Map;
      // Old intents may have been created after an account switch from the
      // shared local history. Keep them intact, but never send guessed deletes.
      if (value['ownershipVerified'] != true) continue;
      deletions[entry.key as String] = value['revision'] as int;
      pending |= value['pending'] as bool;
    }
    return FriendSnapshotBatch(
      deletions,
      pending,
      history,
      state['deviceId'] as String,
      state['revision'] as int,
      publications: publications,
    );
  });

  Future<void> acknowledge(
    String owner,
    Map<String, int> sent, {
    Map<String, int> publications = const {},
  }) => _serialized(() async {
    final state = await _read();
    final entries = (state['deletions'] as Map)[owner] as Map? ?? {};
    var changed = false;
    for (final entry in sent.entries) {
      final current = entries[entry.key] as Map?;
      if (current?['revision'] == entry.value && current?['pending'] == true) {
        current!['pending'] = false;
        changed = true;
      }
    }
    // Keep acknowledged tombstones until an explicit local restore. This
    // prevents a stale widget snapshot from resurrecting a deleted record.
    final queued = (state['publications'] as Map?)?[owner] as Map? ?? {};
    for (final entry in publications.entries) {
      final current = queued[entry.key] as Map?;
      if (current?['revision'] == entry.value && current?['pending'] == true) {
        current!['pending'] = false;
        changed = true;
      }
    }
    if (changed) await _write(state);
  });
}
