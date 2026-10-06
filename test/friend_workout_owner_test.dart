import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/friends/friend_workout_owner.dart';
import 'package:setkeep/main.dart';

void main() {
  test(
    'legacy self records keep unknown provenance through JSON and editing',
    () {
      final old = WorkoutRecord(date: DateTime(2026, 10, 1), sets: const []);
      expect(friendWorkoutOwner(old.toJson()), isNull);
      expect(old.toJson().containsKey('friendOwnerUserId'), false);
      expect(WorkoutRecord.fromJson(old.toJson()).friendOwnerUserId, isNull);
      final edit = old
          .withFriendOwner('B')
          .withFriendOwner(old.friendOwnerUserId);
      expect(edit.toJson(), old.toJson());
    },
  );
  test(
    'known social owner survives save, restart and Undo without rebinding',
    () {
      final owned = WorkoutRecord(
        date: DateTime(2026, 10, 1),
        sets: const [],
        friendOwnerUserId: 'A',
      );
      final restored = WorkoutRecord.fromJson(owned.toJson());
      expect(friendWorkoutOwner(restored.toJson()), 'A');
      expect(restored.toJson(), owned.toJson());
    },
  );
  test('server-identified TRAINER provenance is accepted; conflicting fields fail closed', () {
    final trainer = {
      'trainerWorkoutId': 'server-id',
      'trainerOwnerUserId': 'A',
    };
    expect(friendWorkoutOwner(trainer), 'A');
    expect(friendWorkoutOwner({...trainer, 'friendOwnerUserId': 'B'}), isNull);
    expect(friendWorkoutOwner({'trainerOwnerUserId': 'A'}), isNull);
    expect(friendWorkoutOwner({'friendOwnerUserId': ''}), isNull);
    expect(friendWorkoutOwner({'friendOwnerUserId': 12}), isNull);
  });
}
