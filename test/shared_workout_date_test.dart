import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/friends/shared_workout_date.dart';

void main() {
  test(
    'original local date survives the legacy server UTC cast and viewer zone',
    () {
      final result = sharedWorkoutDate({
        'client_id': '2026-11-06T23:30:00.000',
        'performed_at': '2026-11-06T23:30:00+00:00',
      });
      expect([result.year, result.month, result.day], [2026, 11, 6]);
      expect(result.isUtc, false);
      expect([result.hour, result.minute], [23, 30]);
      // Asia/Tokyo's legacy timestamp becomes tomorrow; the original key does not.
      final utc = DateTime.parse('2026-11-06T23:30:00Z');
      if (utc.toLocal().timeZoneOffset == const Duration(hours: 9)) {
        expect(utc.toLocal().day, 7);
      }
    },
  );
  test('explicit offsets and UTC keys preserve the saved civil date too', () {
    for (final suffix in ['Z', '+09:00', '-07:00']) {
      final result = sharedWorkoutDate({
        'client_id': '2026-12-31T23:30:00$suffix',
        'performed_at': '2027-01-01T06:30:00Z',
      });
      expect([result.year, result.month, result.day], [2026, 12, 31]);
    }
  });
  test(
    'unknown or invalid keys use the timestamp without guessing a time zone',
    () {
      for (final key in [null, '', 'opaque', '2026-02-30T12:00:00']) {
        final expected = DateTime.parse('2026-11-06T03:00:00Z').toLocal();
        expect(
          sharedWorkoutDate({
            'client_id': key,
            'performed_at': '2026-11-06T03:00:00Z',
          }),
          expected,
        );
      }
    },
  );
}
