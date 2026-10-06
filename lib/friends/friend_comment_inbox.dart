import 'package:shared_preferences/shared_preferences.dart';

import 'friends_repository.dart';

/// Derived from existing MVP rows. Read IDs are private to this account/device;
/// no notification table or new production migration is required.
class FriendCommentInboxRepository {
  FriendCommentInboxRepository(this.friends);
  final FriendsRepository friends;
  String? get userId => friends.client.auth.currentUser?.id;
  String key(String owner) => 'friend_comment_reads_v1_$owner';
  static Future<void> _writes = Future<void>.value();

  Future<List<Map<String, dynamic>>> comments() async {
    if (!friends.commentsEnabled) return [];
    final owner = userId;
    if (owner == null) return [];
    final profile = await friends.profile();
    if (profile?['visibility'] != 'friends') return [];
    final connections = await friends.connections();
    final names = <String, String>{
      for (final row in connections)
        if (row['status'] == 'accepted')
          (row['requester'] == owner ? row['recipient'] : row['requester'])
                  as String:
              row['friend_name'] as String,
    };
    if (names.isEmpty) return [];
    final result = <String, Map<String, dynamic>>{};
    for (var offset = 0; ; offset += 100) {
      final page = await friends.client
          .from('friend_comments')
          .select('*,friend_workouts!inner(user_id,performed_at)')
          .eq('friend_workouts.user_id', owner)
          .neq('user_id', owner)
          .order('created_at', ascending: false)
          .order('id')
          .range(offset, offset + 99);
      for (final row in page) {
        final author = row['user_id'] as String;
        if (author != owner &&
            names.containsKey(author) &&
            (row['friend_workouts'] as Map?)?['user_id'] == owner) {
          result[row['id'] as String] = {...row, 'friend_name': names[author]};
        }
      }
      if (page.length < 100) break;
    }
    if (userId != owner) throw StateError('Account changed');
    final prefs = await SharedPreferences.getInstance();
    final read = (prefs.getStringList(key(owner)) ?? []).toSet();
    if (userId != owner) throw StateError('Account changed');
    return result.values
        .map((row) => {...row, 'read': read.contains(row['id'])})
        .toList();
  }

  Future<int> unreadCount() async =>
      (await comments()).where((row) => row['read'] != true).length;

  Future<bool> markRead(String id) {
    if (!friends.commentsEnabled) return Future.value(false);
    final owner = userId;
    final result = _writes.then((_) async {
      if (owner == null || userId != owner) return false;
      // Revalidate before opening a stale notification or updating read state.
      final rows = await comments();
      if (userId != owner || !rows.any((row) => row['id'] == id)) return false;
      final prefs = await SharedPreferences.getInstance();
      if (userId != owner) return false;
      final ids = (prefs.getStringList(key(owner)) ?? []).toSet()..add(id);
      if (!await prefs.setStringList(key(owner), ids.toList())) {
        throw StateError('Could not save read state');
      }
      return userId == owner;
    });
    _writes = result.then<void>((_) {}).catchError((Object _) {});
    return result;
  }
}
