import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:typed_data';

import '../profile/profile_preference.dart';
import 'friend_snapshot_journal.dart';

class FriendsRepository {
  FriendsRepository(this.client, {FriendSnapshotJournal? journal})
    : _journal = journal ?? FriendSnapshotJournal();
  final SupabaseClient client;
  final FriendSnapshotJournal _journal;
  String get userId => client.auth.currentUser!.id;
  bool? _profileInvitesAvailable;
  bool get supportsProfileInvites => _profileInvitesAvailable ?? false;

  Future<Map<String, dynamic>?> profile() async {
    final result = await client
        .from('friend_profiles')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    // SELECT * works with the already deployed MVP schema. No probe of a
    // missing column/RPC and no production migration is needed for this build.
    _profileInvitesAvailable = result?.containsKey('avatar_path') ?? false;
    return result;
  }

  Future<void> saveProfile(String name, String visibility) async {
    final owner = userId;
    final existing = await profile();
    if (client.auth.currentUser?.id != owner) {
      throw StateError('Account changed');
    }
    final values = {'display_name': name.trim(), 'visibility': visibility};
    if (existing == null) {
      await client.from('friend_profiles').insert({
        'user_id': owner,
        ...values,
      });
    } else {
      await client.from('friend_profiles').update(values).eq('user_id', owner);
    }
  }

  /// Name synchronization never changes the existing sharing choice.
  Future<Map<String, dynamic>> ensureProfile(String name) async {
    final owner = userId;
    final displayName = ProfilePreference.socialName(name);
    var existing = await profile();
    if (client.auth.currentUser?.id != owner) {
      throw StateError('Account changed');
    }
    if (existing == null) {
      try {
        await client.from('friend_profiles').insert({
          'user_id': owner,
          'display_name': displayName,
        });
      } on PostgrestException catch (e) {
        if (e.code != '23505') rethrow; // Another device may have created it.
      }
      existing = await profile();
    }
    if (existing == null) throw StateError('Profile unavailable');
    if (client.auth.currentUser?.id != owner) {
      throw StateError('Account changed');
    }
    if (existing['display_name'] != displayName) {
      await client
          .from('friend_profiles')
          .update({'display_name': displayName})
          .eq('user_id', owner);
    }
    return {...existing, 'display_name': displayName};
  }

  Future<Map<String, dynamic>> invitePreview(String code) async =>
      Map<String, dynamic>.from(
        await client.rpc('lookup_friend_invite', params: {'code': code}),
      );

  Future<String> avatarUrl(String path) =>
      client.storage.from('friend-avatars').createSignedUrl(path, 60);

  Future<void> setAvatar(Uint8List? photo, {String? expectedOwner}) async {
    final owner = expectedOwner ?? userId;
    if (client.auth.currentUser?.id != owner) {
      throw StateError('Account changed');
    }
    final previous = (await profile())?['avatar_path'] as String?;
    if (client.auth.currentUser?.id != owner) {
      throw StateError('Account changed');
    }
    if (!supportsProfileInvites) throw StateError('Profile photos unavailable');
    String? path;
    if (photo != null) {
      if (photo.isEmpty || photo.length > 512 * 1024) {
        throw ArgumentError('Photo size');
      }
      path = '$owner/${DateTime.now().microsecondsSinceEpoch}.png';
      await client.storage
          .from('friend-avatars')
          .uploadBinary(
            path,
            photo,
            fileOptions: const FileOptions(
              contentType: 'image/png',
              upsert: false,
            ),
          );
    }
    try {
      if (client.auth.currentUser?.id != owner) {
        throw StateError('Account changed');
      }
      await client
          .from('friend_profiles')
          .update({'avatar_path': path})
          .eq('user_id', owner);
    } catch (_) {
      if (path != null) {
        try {
          await client.storage.from('friend-avatars').remove([path]);
        } catch (_) {}
      }
      rethrow;
    }
    if (previous != null && previous != path) {
      try {
        await client.storage.from('friend-avatars').remove([previous]);
      } catch (_) {}
    }
  }

  static Future<void> _publication = Future<void>.value();
  static bool _retryRunning = false;
  Future<void> publish(List<Map<String, dynamic>> records) {
    final owner = userId;
    return _publish(owner, records);
  }

  /// Only pending intents trigger a retry; no periodic feed fetch or publishing
  /// for another account. The RPC also verifies owner identity at request time.
  Future<void> retryDeletions() async {
    final owner = client.auth.currentUser?.id;
    if (owner == null || _retryRunning) return;
    _retryRunning = true;
    try {
      if ((await _journal.batch(owner)).pending) {
        await _publish(owner, const [], deletionsOnly: true);
      }
    } finally {
      _retryRunning = false;
    }
  }

  Future<void> _publish(
    String owner,
    List<Map<String, dynamic>> records, {
    bool deletionsOnly = false,
  }) {
    final next = _publication.then((_) async {
      if (client.auth.currentUser?.id != owner) return;
      final batch = await _journal.batch(owner);
      if (client.auth.currentUser?.id != owner) return;
      // The saved history wins over an old widget's snapshot. Pending/confirmed
      // tombstones additionally prevent stale publication from undoing deletion.
      final payload =
          (deletionsOnly ? <Map<String, dynamic>>[] : batch.history ?? records)
              .where(
                (r) =>
                    (r['trainerOwnerUserId'] == null ||
                        r['trainerOwnerUserId'] == owner) &&
                    !batch.deletions.containsKey(r['date']),
              )
              .map(
                (r) => {
                  'date': r['date'],
                  'durationSeconds': r['durationSeconds'],
                  'sets': r['sets'],
                },
              )
              .toList();
      await client.rpc(
        'sync_friend_workouts',
        params: {
          'expected_owner': owner,
          'records': payload,
          'deleted_client_ids': batch.deletions.keys.toList(),
          'device_id': batch.deviceId,
          'revision': batch.revision,
          'publish_snapshot': !deletionsOnly,
        },
      );
      await _journal.acknowledge(owner, batch.deletions);
    });
    _publication = next.catchError((Object _) {});
    return next;
  }

  Future<List<Map<String, dynamic>>> connections() async {
    if (_profileInvitesAvailable == null) await profile();
    return List<Map<String, dynamic>>.from(
      await client.rpc(
        supportsProfileInvites
            ? 'list_friend_connections_with_avatar'
            : 'list_friend_connections',
      ),
    );
  }

  Future<void> request(String code) async {
    await client.rpc('request_friend', params: {'code': code.trim()});
  }

  Future<void> accept(String id) async {
    await client.rpc('accept_friend', params: {'connection_id': id});
  }

  Future<void> remove(String id) async {
    await client.from('friend_connections').delete().eq('id', id);
  }

  Future<List<Map<String, dynamic>>> feed({String? owner}) async {
    if (_profileInvitesAvailable == null) await profile();
    final fields =
        '*, friend_profiles!inner(display_name${supportsProfileInvites ? ', avatar_path' : ''}), friend_likes(user_id), friend_comments(id)';
    if (owner == null && supportsProfileInvites) {
      return await client
          .rpc('latest_friend_workouts')
          .select(fields)
          .order('performed_at', ascending: false);
    }
    if (owner == null) {
      // Fetch one session per accepted friend. A prolific friend cannot crowd
      // another friend's latest session out of the server's global row limit.
      final items = await connections();
      final owners = items
          .where((row) => row['status'] == 'accepted')
          .map(
            (row) =>
                (row['requester'] == userId
                        ? row['recipient']
                        : row['requester'])
                    as String,
          )
          .toSet();
      final results = await Future.wait(
        owners.map(
          (id) => client
              .from('friend_workouts')
              .select(fields)
              .eq('user_id', id)
              .order('performed_at', ascending: false)
              .order('id', ascending: false)
              .limit(1),
        ),
      );
      return results.expand((rows) => rows).toList();
    }
    final query = client.from('friend_workouts').select(fields);
    return await query
        .eq('user_id', owner)
        .order('performed_at', ascending: false)
        .limit(1000);
  }

  Future<List<Map<String, dynamic>>> comments(String id) async => await client
      .from('friend_comments')
      .select()
      .eq('workout_id', id)
      .order('created_at');
  Future<void> like(String id, bool liked) async {
    if (liked) {
      await client.from('friend_likes').insert({
        'workout_id': id,
        'user_id': userId,
      });
    } else {
      await client
          .from('friend_likes')
          .delete()
          .eq('workout_id', id)
          .eq('user_id', userId);
    }
  }

  Future<void> comment(String id, String body) async {
    final text = body.trim();
    if (text.isEmpty || text.runes.length > 140) {
      throw ArgumentError('1–140 characters required');
    }
    await client.from('friend_comments').insert({
      'workout_id': id,
      'user_id': userId,
      'body': text,
    });
  }

  Future<void> deleteComment(String id) async {
    await client
        .from('friend_comments')
        .delete()
        .eq('id', id)
        .eq('user_id', userId);
  }
}
