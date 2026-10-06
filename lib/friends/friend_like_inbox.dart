import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'friends_repository.dart';

/// Active likes only. Read state belongs to this account on this device;
/// it is not synchronized across devices and never changes like rows.
class FriendLikeInboxRepository {
  FriendLikeInboxRepository(this.friends);
  final FriendsRepository friends;
  String? get userId => friends.client.auth.currentUser?.id;
  String key(String owner) => 'friend_like_reads_v1_$owner';
  static final Map<String, Future<void>> _writes = {};

  Future<List<Map<String, dynamic>>> notifications({
    Set<String>? clientIds,
  }) async {
    final owner = userId;
    if (owner == null) return [];
    final rows = await friends.receivedLikes();
    if (userId != owner) throw StateError('Account changed');
    final unique = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final workout = row['workout_id'];
      final author = row['user_id'];
      final client = row['client_id'];
      final created = row['created_at'];
      if (row['owner_id'] != owner ||
          author == owner ||
          workout is! String ||
          author is! String ||
          client is! String ||
          created is! String ||
          DateTime.tryParse(created) == null ||
          (clientIds != null && !clientIds.contains(client))) {
        continue;
      }
      final instant = DateTime.parse(created).toUtc().toIso8601String();
      final id = '$workout:$author:$instant';
      unique[id] = {...row, 'id': id};
    }
    final prefs = await SharedPreferences.getInstance();
    if (userId != owner) throw StateError('Account changed');
    final read = (prefs.getStringList(key(owner)) ?? []).toSet();
    final result = unique.values
        .map((row) => {...row, 'read': read.contains(row['id'])})
        .toList();
    result.sort((a, b) {
      final date = DateTime.parse(b['created_at'] as String)
          .compareTo(DateTime.parse(a['created_at'] as String));
      return date != 0
          ? date
          : (a['id'] as String).compareTo(b['id'] as String);
    });
    return result;
  }

  Future<int> unreadCount({Set<String>? clientIds}) async =>
      (await notifications(clientIds: clientIds))
          .where((row) => row['read'] != true)
          .length;

  Future<Map<String, dynamic>?> resolve(
    String id, {
    Set<String>? clientIds,
  }) async {
    final rows = await notifications(clientIds: clientIds);
    final matches = rows.where((row) => row['id'] == id);
    return matches.isEmpty ? null : matches.first;
  }

  Future<bool> markRead(String id, {Set<String>? clientIds}) {
    final owner = userId;
    if (owner == null) return Future<bool>.value(false);
    Future<bool> write() async {
      if (userId != owner) return false;
      if (await resolve(id, clientIds: clientIds) == null || userId != owner) {
        return false;
      }
      final prefs = await SharedPreferences.getInstance();
      if (userId != owner) return false;
      final ids = (prefs.getStringList(key(owner)) ?? []).toSet()..add(id);
      if (!await prefs.setStringList(key(owner), ids.toList())) {
        throw StateError('Could not save read state');
      }
      return userId == owner;
    }

    final pending = _writes[owner];
    final result = pending == null ? write() : pending.then((_) => write());
    final tail = result.then<void>((_) {}).catchError((Object _) {});
    _writes[owner] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_writes[owner], tail)) _writes.remove(owner);
      }),
    );
    return result;
  }
}
