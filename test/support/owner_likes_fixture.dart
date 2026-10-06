import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:setkeep/main.dart';
import 'package:setkeep/friends/friends_repository.dart';
import 'package:setkeep/friends/friend_like_inbox.dart';

final ownLikeWorkout = WorkoutRecord(
  date: DateTime(2020, 1, 1, 10),
  gymName: '自宅',
  sets: const [
    RecordedSet(
      exerciseId: 'bench_press',
      exerciseName: 'ベンチプレス',
      bodyPart: '胸',
      equipment: 'バーベル',
      weight: 20,
      reps: 8,
      completed: true,
    ),
  ],
);

class OwnerLikesFriends extends FriendsRepository {
  OwnerLikesFriends()
    : super(
        SupabaseClient(
          'http://localhost',
          'synthetic',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      ) {
    records[ownLikeWorkout.date.toIso8601String()] = {
      'id': 'old-remote-session',
      'user_id': 'me',
      'client_id': ownLikeWorkout.date.toIso8601String(),
    };
  }
  String? viewer = 'me';
  @override
  String get userId => viewer ?? (throw StateError('Logged out'));
  @override
  bool get commentsEnabled => false;
  final records = <String, Map<String, dynamic>>{};
  final resolvedClients = <String>[];
  final resolvedRemoteIds = <String>[];
  List<Map<String, dynamic>> likes = [
    {'user_id': 'friend-a', 'avatar_path': null},
    {'user_id': 'friend-b', 'avatar_path': null},
  ];
  List<Map<String, dynamic>> inboxRows = [];
  Completer<List<Map<String, dynamic>>>? likesReply, inboxReply;
  bool failLikes = false, failInbox = false, failRecord = false;
  int inboxReads = 0, writes = 0, commentReads = 0;
  @override
  Future<Map<String, dynamic>?> workoutForRecord(String clientId) async {
    resolvedClients.add(clientId);
    if (failRecord) throw StateError('Offline');
    return records[clientId];
  }

  @override
  Future<List<Map<String, dynamic>>> likerAvatars(String id) async {
    resolvedRemoteIds.add(id);
    if (failLikes) throw StateError('Permission denied');
    return likesReply == null ? [...likes] : await likesReply!.future;
  }

  @override
  Future<String> avatarUrl(String path) async =>
      'https://synthetic.invalid/profile.png';
  @override
  Future<List<Map<String, dynamic>>> receivedLikes() async {
    inboxReads++;
    if (failInbox) throw StateError('Offline');
    return inboxReply == null ? [...inboxRows] : await inboxReply!.future;
  }

  @override
  Future<List<Map<String, dynamic>>> comments(String id) async {
    commentReads++;
    throw StateError('Comments remain off');
  }

  @override
  Future<void> publish(List<Map<String, dynamic>> records) async => writes++;
  @override
  Future<void> like(String id, bool liked) async => writes++;
}

class OwnerLikeInbox extends FriendLikeInboxRepository {
  OwnerLikeInbox(OwnerLikesFriends super.friends);
  @override
  String? get userId => (friends as OwnerLikesFriends).viewer;
}

Map<String, dynamic> likeNotice({
  String author = 'friend-a',
  String workout = 'old-remote-session',
  String owner = 'me',
  String name = 'テスト友人',
  String? clientId,
  String created = '2026-10-06T03:00:00Z',
}) => {
  'owner_id': owner,
  'user_id': author,
  'workout_id': workout,
  'client_id': clientId ?? ownLikeWorkout.date.toIso8601String(),
  'performed_at': ownLikeWorkout.date.toIso8601String(),
  'created_at': created,
  'display_name': name,
  'avatar_path': null,
};
