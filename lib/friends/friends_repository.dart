import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:typed_data';

import '../profile/profile_preference.dart';
import '../config/friends_release.dart';
import 'friend_snapshot_journal.dart';

class FriendsRepository {
  FriendsRepository(
    this.client, {
    FriendSnapshotJournal? journal,
    this.commentsEnabled = friendCommentsPublicEnabled,
  }) : _journal = journal ?? FriendSnapshotJournal();
  final bool commentsEnabled;
  final SupabaseClient client;
  final FriendSnapshotJournal _journal;
  String get userId => client.auth.currentUser!.id;
  bool? _profileInvitesAvailable;
  bool _mutualSharingAvailable = false;
  bool _idempotentCommentsAvailable = false;
  bool get supportsIdempotentComments => _idempotentCommentsAvailable;
  bool get supportsMutualFriendSharing => _mutualSharingAvailable;
  bool get supportsProfileInvites => _profileInvitesAvailable ?? false;

  Future<Map<String, dynamic>?> profile() async {
    final result = await client
        .from('friend_profiles')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    // SELECT * also works with legacy schemas. New RPCs are called only when
    // their additive capability column is present.
    _profileInvitesAvailable = result?.containsKey('avatar_path') ?? false;
    _mutualSharingAvailable =
        result?.containsKey('sharing_consent_version') ?? false;
    _idempotentCommentsAvailable = result?['comment_idempotency_version'] == 1;
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

  /// Background refresh uses the server name; an empty/stale device cache must
  /// never rename an existing account or change its sharing permission.
  Future<Map<String, dynamic>> ensureProfile(String name) async {
    final owner = userId;
    var existing = await profile();
    _requireOwner(owner);
    if (existing == null) {
      try {
        await client.from('friend_profiles').insert({
          'user_id': owner,
          'display_name': ProfilePreference.socialName(name),
        });
      } on PostgrestException catch (e) {
        if (e.code != '23505') rethrow;
      }
      _requireOwner(owner);
      existing = await profile();
    }
    if (existing == null) throw StateError('Profile unavailable');
    _requireOwner(owner);
    await ProfilePreference.cacheServerName(
      owner,
      existing['display_name'] as String? ?? '',
    );
    _requireOwner(owner);
    return existing;
  }

  void _requireOwner(String owner) {
    if (client.auth.currentUser?.id != owner) {
      throw StateError('Account changed');
    }
  }

  /// Only the explicit My Page editor may rename an existing cloud profile.
  Future<void> saveDisplayName(String name, {String? expectedOwner}) async {
    final owner = expectedOwner ?? userId;
    _requireOwner(owner);
    await ensureProfile(await ProfilePreference.load(owner: owner));
    _requireOwner(owner);
    await client
        .from('friend_profiles')
        .update({'display_name': ProfilePreference.socialName(name)})
        .eq('user_id', owner);
    _requireOwner(owner);
  }

  /// Called after the individual confirms mutual friend sharing. This grants
  /// only that owner's permission; migration/profile refresh never grants it.
  Future<void> acknowledgeMutualSharing() async {
    final owner = userId;
    if (!_mutualSharingAvailable) await profile();
    _requireOwner(owner);
    if (!supportsMutualFriendSharing) {
      throw StateError('Friend sharing update unavailable');
    }
    await client.rpc(
      'acknowledge_mutual_friend_sharing',
      params: {'consent_version': 'privacy-1.2'},
    );
    _requireOwner(owner);
  }

  Future<String?> myInviteCode() async {
    final owner = userId;
    final row = await profile();
    _requireOwner(owner);
    if (!supportsMutualFriendSharing) return row?['invite_code'] as String?;
    final code = await client.rpc('my_friend_invite_code');
    _requireOwner(owner);
    return code as String;
  }

  Future<Map<String, dynamic>> invitePreview(String code) async {
    if (_profileInvitesAvailable == null) await profile();
    final result = Map<String, dynamic>.from(
      await client.rpc(
        supportsMutualFriendSharing
            ? 'lookup_friend_invite_v2'
            : 'lookup_friend_invite',
        params: {'code': code.trim()},
      ),
    );
    if (result['ok'] == false) throw StateError('Invite unavailable');
    return result;
  }

  Future<String> avatarUrl(String path) =>
      client.storage.from('friend-avatars').createSignedUrl(path, 60);

  /// A supplied name is updated in the same profile row write as the photo.
  Future<void> setAvatar(
    Uint8List? photo, {
    String? expectedOwner,
    String? displayName,
  }) async {
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
          .update({
            'avatar_path': path,
            if (displayName != null)
              'display_name': ProfilePreference.socialName(displayName),
          })
          .eq('user_id', owner);
    } catch (_) {
      // A lost response can follow a committed row update. Never delete the
      // active photo; only clean up a candidate confirmed not to be referenced.
      Map<String, dynamic>? current;
      try {
        if (client.auth.currentUser?.id == owner) current = await profile();
        if (client.auth.currentUser?.id != owner) current = null;
      } catch (_) {}
      final committed =
          current != null &&
          current['avatar_path'] == path &&
          (displayName == null ||
              current['display_name'] ==
                  ProfilePreference.socialName(displayName));
      if (!committed) {
        if (path != null &&
            current != null &&
            current['avatar_path'] != path &&
            client.auth.currentUser?.id == owner) {
          try {
            await client.storage.from('friend-avatars').remove([path]);
          } catch (_) {}
        }
        rethrow;
      }
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
    if (_profileInvitesAvailable == null) await profile();
    final result = await client.rpc(
      supportsMutualFriendSharing ? 'request_friend_v2' : 'request_friend',
      params: {'code': code.trim()},
    );
    if (result is Map && result['ok'] == false) {
      throw StateError('Invite unavailable');
    }
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
        '*, friend_profiles!inner(display_name${supportsProfileInvites ? ', avatar_path' : ''}), friend_likes(user_id)${commentsEnabled ? ', friend_comments(id)' : ''}';
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

  /// Exact RLS-protected lookup also works beyond the history feed's page size.
  Future<Map<String, dynamic>?> workoutById(String id) async =>
      await client.from('friend_workouts').select().eq('id', id).maybeSingle();

  Future<Map<String, dynamic>?> workoutForRecord(String clientId) async =>
      await client
          .from('friend_workouts')
          .select()
          .eq('user_id', userId)
          .eq('client_id', clientId)
          .maybeSingle();

  Future<List<Map<String, dynamic>>> comments(String id) async {
    if (!commentsEnabled) return [];
    if (_profileInvitesAvailable == null) await profile();
    if (supportsMutualFriendSharing) {
      final rows = List<Map<String, dynamic>>.from(
        await client.rpc(
          'friend_comment_thread',
          params: {'target_workout_id': id},
        ),
      );
      return rows
          .map(
            (row) => {
              ...row,
              'friend_profiles': {
                'display_name': row['display_name'],
                'avatar_path': row['avatar_path'],
              },
            },
          )
          .toList();
    }
    return await client
        .from('friend_comments')
        .select()
        .eq('workout_id', id)
        .order('created_at');
  }

  Future<List<Map<String, dynamic>>> likerAvatars(String id) async {
    if (_profileInvitesAvailable == null) await profile();
    if (supportsMutualFriendSharing) {
      return List<Map<String, dynamic>>.from(
        await client.rpc(
          'friend_liker_avatars',
          params: {'target_workout_id': id},
        ),
      );
    }
    final rows = await client
        .from('friend_likes')
        .select('user_id')
        .eq('workout_id', id);
    return rows.map((row) => {...row, 'avatar_path': null}).toList();
  }

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

  /// A failed/lost response must be retried with the same operation ID and
  /// exact draft. The server binds it to author/workout/body and rejects replay
  /// after deletion or revoked access. Legacy inserts remain separate.
  Future<void> sendComment(
    String id,
    String body, {
    required String operationId,
  }) async {
    if (!commentsEnabled) throw StateError('Friend comments unavailable');
    final owner = userId;
    final text = body.trim();
    if (text.isEmpty || text.runes.length > 140) {
      throw ArgumentError('1–140 characters required');
    }
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(operationId)) {
      throw ArgumentError('Operation ID required');
    }
    if (_profileInvitesAvailable == null) await profile();
    _requireOwner(owner);
    if (!supportsIdempotentComments) {
      throw StateError('Comment retry safety update unavailable');
    }
    await client.rpc(
      'send_friend_comment',
      params: {
        'target_workout_id': id,
        'body': text,
        'operation_id': operationId,
      },
    );
    _requireOwner(owner);
  }

  Future<void> comment(String id, String body) async {
    if (!commentsEnabled) throw StateError('Friend comments unavailable');
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
    if (!commentsEnabled) throw StateError('Friend comments unavailable');
    await client
        .from('friend_comments')
        .delete()
        .eq('id', id)
        .eq('user_id', userId);
  }
}
