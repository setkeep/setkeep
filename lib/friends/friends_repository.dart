import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'dart:typed_data';

import '../profile/profile_preference.dart';
import '../config/friends_release.dart';
import 'friend_snapshot_journal.dart';
import 'friend_workout_owner.dart';
import 'friend_roster.dart';

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
  bool _ownedSharingAvailable = false;
  bool _workoutUpdatesAvailable = false;
  bool get supportsWorkoutUpdates => _workoutUpdatesAvailable;
  bool get supportsOwnedSharing => _ownedSharingAvailable;
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
    _ownedSharingAvailable = result?['friend_owned_sync_version'] == 1;
    _workoutUpdatesAvailable = result?['friend_workout_updates_version'] == 1;
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
    if (!supportsOwnedSharing) {
      throw StateError('Safe friend sharing update unavailable');
    }
    await client.rpc(
      'acknowledge_owned_friend_sharing',
      params: {'expected_owner': owner, 'consent_version': 'privacy-1.2'},
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

  /// Widget tests each have a distinct virtual clock. Call only after the
  /// previous test's client and requests have been disposed.
  @visibleForTesting
  static void resetPublicationQueueForTesting() {
    _publication = Future<void>.value();
    _retryRunning = false;
  }

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
      final batch = await _journal.batch(owner);
      if (batch.pending) {
        await _publish(
          owner,
          const [],
          deletionsOnly: batch.publications.isEmpty,
        );
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
                    friendWorkoutOwner(r) == owner &&
                    !batch.deletions.containsKey(r['date']),
              )
              .map(
                (r) => {
                  'date': r['date'],
                  'durationSeconds': r['durationSeconds'],
                  'sets': r['sets'],
                  'friendOwnerUserId': owner,
                },
              )
              .toList();
      if (payload.isEmpty && batch.deletions.isEmpty) return;
      final ownProfile = await profile();
      if (client.auth.currentUser?.id != owner) return;
      if (!supportsOwnedSharing) {
        // Never fall back to the legacy full-snapshot RPC: it can remove
        // existing shared records that this device does not contain.
        throw StateError('Safe friend sharing update unavailable');
      }
      final visiblePayload =
          ownProfile?['visibility'] == 'friends' &&
              ownProfile?['sharing_consent_version'] == 1
          ? payload
          : <Map<String, dynamic>>[];
      if (visiblePayload.isEmpty && batch.deletions.isEmpty) return;
      final result = await client.rpc(
        'sync_owned_friend_workouts',
        params: {
          'expected_owner': owner,
          'records': visiblePayload,
          'deleted_client_ids': batch.deletions.keys.toList(),
          'device_id': batch.deviceId,
          'revision': batch.revision,
        },
      );
      if (result is Map && result['accepted'] == true) {
        await _journal.acknowledge(
          owner,
          batch.deletions,
          publications: result['published'] == true
              ? batch.publications
              : const {},
        );
      }
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

  /// Always start from current accepted connections. No cached workout can
  /// resurrect a removed relationship, and a failed read is never an empty one.
  Future<List<FriendRosterEntry>> roster() async {
    final viewer = userId;
    final items = await connections();
    if (userId != viewer) throw StateError('Account changed');
    List<Map<String, dynamic>> workouts;
    var failed = false;
    try {
      workouts = supportsWorkoutUpdates ? await latestUpdates() : await feed();
    } catch (_) {
      workouts = [];
      failed = true;
    }
    if (userId != viewer) throw StateError('Account changed');
    return friendRosterEntries(
      viewer: viewer,
      connections: items,
      workouts: workouts,
      updateTimesAvailable: supportsWorkoutUpdates,
      workoutsFailed: failed,
    );
  }

  Future<List<Map<String, dynamic>>> latestUpdates() async => await client
      .rpc('latest_updated_friend_workouts')
      .select(
        '*, friend_likes(user_id)${commentsEnabled ? ', friend_comments(id)' : ''}',
      );

  /// An edited workout can be older than the detail history's 1000-row page.
  /// Recheck its owner and RLS; never open a cached payload from the card.
  Future<Map<String, dynamic>?> historyWorkoutById(
    String id,
    String owner,
  ) async => await client
      .from('friend_workouts')
      .select(
        '*, friend_profiles!inner(display_name${supportsProfileInvites ? ', avatar_path' : ''}), friend_likes(user_id)${commentsEnabled ? ', friend_comments(id)' : ''}',
      )
      .eq('id', id)
      .eq('user_id', owner)
      .maybeSingle();

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

  /// Loads the complete visible history separately from the bounded feed used
  /// by cards and avatar previews. A failed page never returns a partial list.
  Future<List<Map<String, dynamic>>> history({required String owner}) async {
    final viewer = client.auth.currentUser?.id;
    if (viewer == null) throw StateError('Account changed');
    if (_profileInvitesAvailable == null) await profile();
    _requireOwner(viewer);
    final fields =
        '*, friend_profiles!inner(display_name${supportsProfileInvites ? ', avatar_path' : ''}), friend_likes(user_id)${commentsEnabled ? ', friend_comments(id)' : ''}';
    const pageSize = 1000;
    final result = <Map<String, dynamic>>[];
    final seenIds = <String>{};
    _FriendHistoryCursor? cursor;
    while (true) {
      _requireOwner(viewer);
      var query = client
          .from('friend_workouts')
          .select(fields)
          .eq('user_id', owner);
      if (cursor != null) query = query.or(cursor.filter);
      final page = await query
          .order('performed_at', ascending: false)
          .order('id', ascending: false)
          .limit(pageSize);
      _requireOwner(viewer);
      if (page.isEmpty) break;
      if (page.length > pageSize) {
        throw StateError('Invalid friend history page');
      }
      for (final row in page) {
        if (row['user_id'] != owner) {
          throw StateError('Invalid friend history owner');
        }
        final next = _FriendHistoryCursor.fromRow(row);
        if (!seenIds.add(next.id) ||
            (cursor != null && !next.isBefore(cursor))) {
          throw StateError('Friend history did not advance');
        }
        result.add(row);
        cursor = next;
      }
      // A server row cap can be smaller than pageSize. Only an empty page is
      // conclusive; offset pagination could skip rows deleted between reads.
    }
    if (result.isNotEmpty) {
      // Access may have been revoked after earlier pages. Recheck current RLS
      // without a cursor so a revoked share cannot publish accumulated rows.
      _requireOwner(viewer);
      final visible = await client
          .from('friend_workouts')
          .select('id')
          .eq('user_id', owner)
          .limit(1);
      _requireOwner(viewer);
      if (visible.isEmpty) return [];
      if (visible.length != 1 ||
          !_FriendHistoryCursor.validId(visible.single['id'])) {
        throw StateError('Invalid friend history visibility');
      }
    }
    return result;
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

  /// Server-scoped active notifications, independently of comment rollout.
  Future<List<Map<String, dynamic>>> receivedLikes() async {
    final owner = client.auth.currentUser?.id;
    if (owner == null) return [];
    final result = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += 100) {
      final page = await client
          .rpc('received_friend_likes')
          .order('created_at', ascending: false)
          .order('workout_id', ascending: true)
          .order('user_id', ascending: true)
          .range(offset, offset + 99);
      if (client.auth.currentUser?.id != owner) {
        throw StateError('Account changed');
      }
      result.addAll(List<Map<String, dynamic>>.from(page));
      if (page.length < 100) break;
    }
    return result;
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

/// The database orders a timestamptz and a UUID, not the timestamp's spelling.
/// Preserve the original timestamp in filters (including microseconds/offset),
/// while comparing instants and canonical UUIDs to reject stalled pages.
class _FriendHistoryCursor {
  _FriendHistoryCursor(this.performedAt, this.instant, this.id);

  factory _FriendHistoryCursor.fromRow(Map<String, dynamic> row) {
    final performedAt = row['performed_at'];
    final id = row['id'];
    final instant = _parseInstant(performedAt);
    if (!validId(id) ||
        performedAt is! String ||
        instant == null ||
        !instant.isUtc) {
      throw StateError('Invalid friend history cursor');
    }
    return _FriendHistoryCursor(
      performedAt,
      instant,
      (id as String).toLowerCase(),
    );
  }

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static bool validId(Object? id) => id is String && _uuid.hasMatch(id);

  static final _timestamp = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(?:Z|[+-](\d{2}):(\d{2}))$',
  );

  static DateTime? _parseInstant(Object? value) {
    if (value is! String) return null;
    final match = _timestamp.firstMatch(value);
    if (match == null) return null;
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    if (month < 1 ||
        month > 12 ||
        day < 1 ||
        day > DateTime.utc(year, month + 1, 0).day ||
        int.parse(match[4]!) > 23 ||
        int.parse(match[5]!) > 59 ||
        int.parse(match[6]!) > 59 ||
        int.parse(match[7] ?? '0') > 23 ||
        int.parse(match[8] ?? '0') > 59) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  final String performedAt;
  final DateTime instant;
  final String id;

  bool isBefore(_FriendHistoryCursor previous) {
    final order = instant.compareTo(previous.instant);
    return order < 0 || (order == 0 && id.compareTo(previous.id) < 0);
  }

  // PostgREST's logic grammar needs quoted literals as well as URL encoding.
  // Escape backslashes before quotes so a value cannot become filter syntax.
  static String _literal(String value) =>
      '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

  String get filter {
    final time = _literal(performedAt);
    return 'performed_at.lt.$time,and(performed_at.eq.$time,id.lt.${_literal(id)})';
  }
}
