/// An accepted relationship and only the shared workout visible to the viewer.
class FriendRosterEntry {
  const FriendRosterEntry({
    required this.userId,
    this.displayName,
    this.avatarPath,
    this.workout,
    this.updatedAt,
    this.workoutsFailed = false,
  });

  final String userId;
  final String? displayName;
  final String? avatarPath;
  final Map<String, dynamic>? workout;
  final DateTime? updatedAt;
  final bool workoutsFailed;
}

/// Unknown timestamps never use the exercise date as a guessed update time.
/// Known updates come first, then undated shared records, failed reads, and
/// confirmed empty reads. Equal/unknown times use the stable account ID.
List<FriendRosterEntry> friendRosterEntries({
  required String viewer,
  required List<Map<String, dynamic>> connections,
  required List<Map<String, dynamic>> workouts,
  required bool updateTimesAvailable,
  bool workoutsFailed = false,
}) {
  final accepted = <String, Map<String, dynamic>>{};
  for (final connection in connections) {
    if (connection['status'] != 'accepted') continue;
    final other = connection['requester'] == viewer
        ? connection['recipient']
        : connection['recipient'] == viewer
        ? connection['requester']
        : null;
    if (other is String && other.isNotEmpty && other != viewer) {
      accepted.putIfAbsent(other, () => connection);
    }
  }
  DateTime? updated(Map<String, dynamic> row) => updateTimesAvailable
      ? DateTime.tryParse(row['updated_at'] as String? ?? '')
      : null;
  final shared = <String, Map<String, dynamic>>{};
  // The server selects the latest update per owner. This tie-break also makes
  // synthetic/legacy responses deterministic without disclosing hidden rows.
  final sorted = [...workouts]
    ..sort((a, b) {
      final aTime = updated(a), bTime = updated(b);
      if (aTime != null && bTime != null) {
        final time = bTime.compareTo(aTime);
        if (time != 0) return time;
      } else if (aTime != null || bTime != null) {
        return aTime != null ? -1 : 1;
      }
      return (b['id'] as String? ?? '').compareTo(a['id'] as String? ?? '');
    });
  if (!workoutsFailed) {
    for (final row in sorted) {
      final owner = row['user_id'];
      if (owner is String && accepted.containsKey(owner)) {
        shared.putIfAbsent(owner, () => row);
      }
    }
  }
  final entries = [
    for (final connection in accepted.entries)
      FriendRosterEntry(
        userId: connection.key,
        displayName: connection.value['friend_name'] as String?,
        avatarPath: connection.value['avatar_path'] as String?,
        workout: shared[connection.key],
        updatedAt: shared[connection.key] == null
            ? null
            : updated(shared[connection.key]!),
        workoutsFailed: workoutsFailed,
      ),
  ];
  int group(FriendRosterEntry entry) => entry.updatedAt != null
      ? 0
      : entry.workout != null
      ? 1
      : entry.workoutsFailed
      ? 2
      : 3;
  entries.sort((a, b) {
    final rank = group(a).compareTo(group(b));
    if (rank != 0) return rank;
    if (a.updatedAt != null && b.updatedAt != null) {
      final time = b.updatedAt!.compareTo(a.updatedAt!);
      if (time != 0) return time;
    }
    return a.userId.compareTo(b.userId);
  });
  return entries;
}
