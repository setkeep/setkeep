/// Sharing provenance only. Local history remains available on this device
/// when an account changes. Old self records never acquire a guessed owner.
String? friendWorkoutOwner(Map<String, dynamic> record) {
  final owner = record['friendOwnerUserId'];
  final trainerOwner = record['trainerOwnerUserId'];
  final trainerId = record['trainerWorkoutId'];
  if (trainerId != null) {
    if (trainerId is! String ||
        trainerId.isEmpty ||
        trainerOwner is! String ||
        trainerOwner.isEmpty ||
        (owner != null && owner != trainerOwner)) {
      return null;
    }
    return trainerOwner;
  }
  if (trainerOwner != null) return null;
  return owner is String && owner.isNotEmpty ? owner : null;
}
