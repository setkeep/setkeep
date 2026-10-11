import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'gym_repository.dart';

class CachedGymDetail {
  const CachedGymDetail(this.detail, this.fetchedAt);
  final GymStoreDetail detail;
  final DateTime fetchedAt;
  bool staleAt(DateTime now) =>
      now.difference(fetchedAt) >= const Duration(hours: 24);
}

/// Public reference data only. Reports and registrations must never enter this cache.
class GymEquipmentCache {
  static String _key(String id) => 'gym_equipment_v2_$id';
  static Future<CachedGymDetail?> read(String id) async {
    try {
      final value = (await SharedPreferences.getInstance()).getString(_key(id));
      if (value == null) return null;
      final j = jsonDecode(value) as Map<String, dynamic>;
      final detail = GymStoreDetail.fromJson(
        j['detail'] as Map<String, dynamic>,
      );
      if (detail.store.id != id) return null;
      return CachedGymDetail(detail, DateTime.parse(j['fetchedAt'] as String));
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(GymStoreDetail detail, {DateTime? now}) async {
    // A cache write failure must not hide successful network results.
    try {
      await (await SharedPreferences.getInstance()).setString(
        _key(detail.store.id),
        jsonEncode({
          'fetchedAt': (now ?? DateTime.now()).toIso8601String(),
          'detail': detail.toJson(),
        }),
      );
    } catch (_) {
      /* Best-effort cache; primary workout persistence is separate. */
    }
  }

  static Future<GymStoreDetail> load(GymRepository repo, GymStore store) async {
    final cached = await read(store.id);
    // Master equipment can change automatically. Refresh on each entry and
    // retain the cache only as an offline fallback.
    try {
      final detail = await repo.detail(store);
      await write(detail);
      return detail;
    } catch (_) {
      if (cached != null) return cached.detail;
      rethrow;
    }
  }
}
