import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

class GymStore {
  const GymStore({
    required this.id,
    required this.chainName,
    required this.name,
    this.city,
    this.address,
    this.station,
    this.chainId,
    this.officialUrl,
    this.checkedAt,
    this.active = true,
    this.equipmentStatus = 'not_collected',
    this.pageStatus,
    this.operationalStatus,
  });
  final String id, chainName, name, equipmentStatus;
  final String? city, address, station, chainId, officialUrl, pageStatus;
  bool get communityEquipmentOnly =>
      const {'anytime-fitness', 'fastgym24', 'golds-gym'}.contains(chainId) ||
      id == 'auns-gym:aunsgym_jp_d4f6b4929a2a';
  final DateTime? checkedAt;
  final bool active;
  final String? operationalStatus;
  String get effectiveStatus =>
      operationalStatus ??
      (pageStatus == 'preopening_text'
          ? 'preopening'
          : active
          ? 'active'
          : 'unknown');
  String get statusLabel => switch (effectiveStatus) {
    'preopening' => 'オープン準備中',
    'temporarily_closed' => '一時休業中',
    'closed' => '閉店',
    'unknown' => '営業状況未確認',
    _ => '営業中',
  };
  String get displayName => '$chainName $name'.trim();
  bool get isPreopening => effectiveStatus == 'preopening';
  bool get isSelectable => active && effectiveStatus == 'active';
  factory GymStore.fromJson(Map<String, dynamic> j) => GymStore(
    id: j['id'] as String,
    chainName:
        j['chain_name'] as String? ??
        (j['gym_chains'] as Map?)?['name'] as String? ??
        '',
    name: j['name'] as String,
    city: j['city'] as String?,
    address: j['address'] as String?,
    station: j['station'] as String?,
    chainId: j['chain_id'] as String?,
    officialUrl: j['official_url'] as String?,
    checkedAt: DateTime.tryParse(j['checked_at'] as String? ?? ''),
    active: j['active'] != false,
    operationalStatus: j['operational_status'] as String?,
    equipmentStatus: j['equipment_status'] as String? ?? 'not_collected',
    pageStatus:
        j['page_status'] as String? ??
        (j['source'] as Map?)?['page_status'] as String?,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'chain_name': chainName,
    'name': name,
    'city': city,
    'address': address,
    'station': station,
    'chain_id': chainId,
    'official_url': officialUrl,
    'checked_at': checkedAt?.toIso8601String(),
    'active': active,
    'operational_status': operationalStatus,
    'equipment_status': equipmentStatus,
    'page_status': pageStatus,
  };
}

class GymEquipment {
  const GymEquipment({
    required this.id,
    required this.name,
    required this.category,
    this.quantity,
    this.manufacturer,
    this.model,
    this.rawName,
    this.loadType,
    this.aliases = const [],
    this.available = true,
    this.unavailableQuantity,
    this.checkedAt,
    this.exerciseIds = const {},
    this.compositeRuleIds = const {},
    this.sourceKind,
    this.sourceUrl,
  });
  final String id, name, category;
  final int? quantity;
  final String? manufacturer, model, rawName, loadType, sourceKind, sourceUrl;
  final List<String> aliases;
  final bool available;
  final int? unavailableQuantity;
  final DateTime? checkedAt;
  bool get usable =>
      available &&
      (quantity == null || quantity! - (unavailableQuantity ?? 0) > 0);
  String get displayCategory => switch (loadType) {
    'plate_loaded' || 'plate_loaded_explicit' => 'プレートロード',
    'cable' || 'cable_named' => 'ケーブル',
    'free_weight' => 'フリーウェイト',
    'cardio' => '有酸素',
    'selectorized' => 'マシン',
    _ => category == '筋トレ' ? 'マシン' : category,
  };
  bool matches(String query) {
    String normalize(String value) => value
        .toLowerCase()
        .replaceAll(RegExp(r'[\s　]'), '')
        .replaceAll('ロウ', 'ロー');
    final q = normalize(query);
    return [
      name,
      rawName ?? '',
      ...aliases,
    ].any((v) => normalize(v).contains(q));
  }

  final Set<String> exerciseIds;
  final Set<String> compositeRuleIds;
  factory GymEquipment.fromJson(Map<String, dynamic> row) {
    final e = Map<String, dynamic>.from(row['equipment'] as Map);
    return GymEquipment(
      sourceKind: row['source_kind'] as String?,
      sourceUrl: row['source_url'] as String?,
      id: e['id'] as String,
      name: e['display_name'] as String? ?? e['name'] as String,
      rawName: row['raw_name'] as String? ?? e['name'] as String?,
      loadType: e['load_type'] as String?,
      aliases: List<String>.from(e['aliases'] as List? ?? []),
      available: row['available'] != false,
      unavailableQuantity: (row['unavailable_quantity'] as num?)?.toInt(),
      checkedAt: DateTime.tryParse(row['checked_at'] as String? ?? ''),
      category: e['category'] as String,
      quantity: (row['quantity'] as num?)?.toInt(),
      manufacturer: e['manufacturer'] as String?,
      model: e['model'] as String?,
      exerciseIds: {
        for (final m in e['equipment_exercise_mapping'] as List? ?? const [])
          m['exercise_id'] as String,
      },
      compositeRuleIds: {
        for (final m in e['exercise_equipment_rule_items'] as List? ?? const [])
          m['rule_id'] as String,
      },
    );
  }
  Map<String, dynamic> toJson() => {
    'quantity': quantity,
    'source_kind': sourceKind,
    'source_url': sourceUrl,
    'raw_name': rawName,
    'available': available,
    'unavailable_quantity': unavailableQuantity,
    'checked_at': checkedAt?.toIso8601String(),
    'equipment': {
      'id': id,
      'name': name,
      'category': category,
      'manufacturer': manufacturer,
      'model': model,
      'load_type': loadType,
      'aliases': aliases,
      'equipment_exercise_mapping': [
        for (final id in exerciseIds) {'exercise_id': id},
      ],
      'exercise_equipment_rule_items': [
        for (final id in compositeRuleIds) {'rule_id': id},
      ],
    },
  };
}

class PrivatePlaceEquipment {
  const PrivatePlaceEquipment({
    required this.id,
    required this.name,
    this.equipmentId,
    this.quantity,
    this.exerciseIds = const {},
  });
  final String id, name;
  final String? equipmentId;
  final int? quantity;
  final Set<String> exerciseIds;
  factory PrivatePlaceEquipment.fromJson(Map<String, dynamic> j) =>
      PrivatePlaceEquipment(
        id: j['id'] as String,
        name: j['name'] as String,
        equipmentId: j['equipment_id'] as String?,
        quantity: j['quantity'] as int?,
        exerciseIds: Set<String>.from(j['exercise_ids'] as List? ?? []),
      );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'equipment_id': equipmentId,
    'quantity': quantity,
    'exercise_ids': exerciseIds.toList(),
  };
}

abstract class GymRepository {
  Future<List<GymEquipment>> searchEquipment(
    String query, {
    int offset = 0,
  }) async => [];
  Future<List<GymExerciseEvidence>> equipmentEvidence(Set<String> ids) async =>
      [];
  Future<List<PrivatePlaceEquipment>> privateEquipment(String placeId) async {
    final p = await SharedPreferences.getInstance();
    return (jsonDecode(p.getString('guest_place_equipment_$placeId') ?? '[]')
            as List)
        .map(
          (j) => PrivatePlaceEquipment.fromJson(
            Map<String, dynamic>.from(j as Map),
          ),
        )
        .toList();
  }

  Future<void> savePrivateEquipment(
    String placeId,
    PrivatePlaceEquipment item,
  ) async {
    final items = await privateEquipment(placeId);
    items.removeWhere(
      (e) =>
          e.id == item.id ||
          (item.equipmentId != null && item.equipmentId == e.equipmentId),
    );
    items.add(item);
    final p = await SharedPreferences.getInstance();
    if (!await p.setString(
      'guest_place_equipment_$placeId',
      jsonEncode(items.map((e) => e.toJson()).toList()),
    )) {
      throw StateError('保存できませんでした');
    }
  }

  Future<void> deletePrivateEquipment(String placeId, {String? itemId}) async {
    final p = await SharedPreferences.getInstance();
    if (itemId == null) {
      await p.remove('guest_place_equipment_$placeId');
      return;
    }
    final items = await privateEquipment(placeId);
    items.removeWhere((e) => e.id == itemId);
    if (!await p.setString(
      'guest_place_equipment_$placeId',
      jsonEncode(items.map((e) => e.toJson()).toList()),
    )) {
      throw StateError('削除できませんでした');
    }
  }

  Future<List<GymExerciseEvidence>> privateEvidence(String placeId) async {
    final items = await privateEquipment(placeId);
    final ids = items.map((e) => e.equipmentId).whereType<String>().toSet();
    return [
      if (ids.isNotEmpty) ...await equipmentEvidence(ids),
      for (final e in items.where((e) => e.equipmentId == null))
        for (final id in e.exerciseIds)
          GymExerciseEvidence(id, [e.id], [e.name]),
    ];
  }

  Future<void> reportStore({
    String? storeId,
    String? chainId,
    String? chainName,
    required String kind,
    String? name,
    String? address,
    String? officialUrl,
    required String comment,
  }) async {
    throw StateError('店舗情報の報告を利用できません');
  }

  Future<void> reportExercise({
    required String storeId,
    required String kind,
    String? exerciseId,
    required String comment,
  }) async {
    throw StateError('対応種目の報告を利用できません');
  }

  Future<List<GymStore>> search(String query, {int offset = 0});
  Future<List<GymStore>> searchStores(
    String query, {
    int offset = 0,
    String? chainId,
  }) async => (await search(
    query,
    offset: offset,
  )).where((s) => chainId == null || s.chainId == chainId).toList();
  Future<GymStore?> storeById(String id) async {
    for (final store in await registered()) {
      if (store.id == id) return store;
    }
    return null;
  }

  Future<Map<String, String>> chains() async => {};
  Future<Set<String>> pendingEquipment(String storeId) async => {};
  Future<GymStoreDetail> detail(GymStore store) async {
    final items = <GymEquipment>[];
    for (var offset = 0; ; offset += 50) {
      final page = await equipment(store.id, offset: offset);
      items.addAll(page);
      if (page.length < 50) break;
    }
    return GymStoreDetail(
      store: store,
      equipment: items,
      evidence: [
        for (final e in items.where((e) => e.usable))
          for (final id in e.exerciseIds)
            GymExerciseEvidence(id, [e.id], [e.name]),
      ],
    );
  }

  Future<List<GymStore>> registered();
  Future<void> register(GymStore store);
  Future<void> unregister(String storeId);
  Future<List<GymEquipment>> equipment(String storeId, {int offset = 0});
  Future<void> report({
    required String storeId,
    String? equipmentId,
    required String kind,
    String? equipmentName,
    required String comment,
    int? reportedQuantity,
    int? reportedUnavailableQuantity,
    String? unavailableScope,
  });
  bool get canReport;
  Future<Set<String>> exerciseIds(String storeId) async {
    final ids = <String>{};
    for (var offset = 0; ; offset += 50) {
      final page = await equipment(storeId, offset: offset);
      ids.addAll(page.where((e) => e.usable).expand((e) => e.exerciseIds));
      if (page.length < 50) return ids;
    }
  }
}

// Injectable boundary: tests never contact real accounts or production data.
class GymServices {
  static GymRepository? override;
  static GymRepository get repository => override ?? SupabaseGymRepository();
}

class SupabaseGymRepository extends GymRepository {
  SupabaseClient get _client {
    if (!SupabaseConfig.initialized) throw StateError('店舗情報を現在利用できません');
    return Supabase.instance.client;
  }

  String? get _userId =>
      SupabaseConfig.initialized ? _client.auth.currentUser?.id : null;
  @override
  bool get canReport => _userId != null;
  @override
  Future<List<GymEquipment>> searchEquipment(
    String query, {
    int offset = 0,
  }) async {
    final rows = await _client.rpc(
      'search_equipment',
      params: {'search_query': query, 'page_offset': offset},
    );
    return (rows as List)
        .map((j) => GymEquipment.fromJson(Map<String, dynamic>.from(j as Map)))
        .toList();
  }

  @override
  Future<List<GymExerciseEvidence>> equipmentEvidence(Set<String> ids) async {
    final rows = await _client.rpc(
      'equipment_exercise_evidence',
      params: {'selected_equipment_ids': ids.toList()},
    );
    return (rows as List)
        .map(
          (j) =>
              GymExerciseEvidence.fromJson(Map<String, dynamic>.from(j as Map)),
        )
        .toList();
  }

  @override
  Future<List<PrivatePlaceEquipment>> privateEquipment(String placeId) async {
    if (_userId == null) return super.privateEquipment(placeId);
    final rows = await _client
        .from('user_custom_place_equipment')
        .select()
        .eq('user_id', _userId!)
        .eq('custom_place_id', placeId)
        .order('created_at');
    return rows.map(PrivatePlaceEquipment.fromJson).toList();
  }

  @override
  Future<void> savePrivateEquipment(
    String placeId,
    PrivatePlaceEquipment item,
  ) async {
    if (_userId == null) return super.savePrivateEquipment(placeId, item);
    await _client.from('user_custom_place_equipment').upsert({
      ...item.toJson(),
      'user_id': _userId!,
      'custom_place_id': placeId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,custom_place_id,id');
  }

  @override
  Future<void> deletePrivateEquipment(String placeId, {String? itemId}) async {
    if (_userId == null) {
      return super.deletePrivateEquipment(placeId, itemId: itemId);
    }
    var query = _client
        .from('user_custom_place_equipment')
        .delete()
        .eq('user_id', _userId!)
        .eq('custom_place_id', placeId);
    if (itemId != null) query = query.eq('id', itemId);
    await query;
  }

  @override
  Future<void> reportExercise({
    required String storeId,
    required String kind,
    String? exerciseId,
    required String comment,
  }) async {
    if (!canReport) throw StateError('報告にはログインが必要です');
    await _client.from('gym_exercise_reports').insert({
      'store_id': storeId,
      'exercise_id': exerciseId,
      'report_kind': kind,
      'comment': comment.trim(),
    });
  }

  @override
  Future<List<GymStore>> search(String query, {int offset = 0}) async {
    return searchStores(query, offset: offset);
  }

  @override
  Future<List<GymStore>> searchStores(
    String query, {
    int offset = 0,
    String? chainId,
  }) async {
    final rows = await _client.rpc(
      'search_gym_stores_v2',
      params: {
        'search_query': query.trim(),
        'page_offset': offset,
        'selected_chain': chainId,
      },
    );
    return (rows as List)
        .map((j) => GymStore.fromJson(Map<String, dynamic>.from(j as Map)))
        .toList();
  }

  @override
  Future<GymStore?> storeById(String id) async {
    final row = await _client
        .from('gym_stores')
        .select('*,gym_chains(name)')
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : GymStore.fromJson(row);
  }

  @override
  Future<Map<String, String>> chains() async {
    final rows = await _client
        .from('gym_chains')
        .select('id,name')
        .order('name');
    return {for (final row in rows) row['id'] as String: row['name'] as String};
  }

  @override
  Future<GymStoreDetail> detail(GymStore store) async {
    final json = await _client.rpc(
      'gym_store_detail',
      params: {'target_store_id': store.id},
    );
    return GymStoreDetail.fromJson(Map<String, dynamic>.from(json as Map));
  }

  @override
  Future<Set<String>> pendingEquipment(String storeId) async {
    if (!canReport) return {};
    final rows = await _client
        .from('gym_equipment_reports')
        .select('equipment_id')
        .eq('store_id', storeId)
        .eq('user_id', _userId!)
        .inFilter('status', ['pending', 'reviewing']);
    return {
      for (final row in rows)
        if (row['equipment_id'] is String) row['equipment_id'] as String,
    };
  }

  @override
  Future<List<GymEquipment>> equipment(String storeId, {int offset = 0}) async {
    final rows = await _client.rpc(
      'gym_store_equipment_page',
      params: {'target_store_id': storeId, 'page_offset': offset},
    );
    return (rows as List)
        .map(
          (row) => GymEquipment.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  @override
  Future<Set<String>> exerciseIds(String storeId) async {
    final rows = await _client.rpc(
      'gym_store_exercise_ids',
      params: {'target_store_id': storeId},
    );
    return {
      for (final row in rows as List)
        if (row is Map && row['exercise_id'] is String)
          row['exercise_id'] as String,
    };
  }

  // Guest registrations stay on this device. Signed-in registrations are RLS
  // protected and queried afresh; they are never exposed through profiles.
  static const _guestKey = 'guest_registered_gym_stores';
  Future<List<GymStore>> _guestStores() async {
    final p = await SharedPreferences.getInstance();
    final encoded = p.getString(_guestKey);
    if (encoded == null) return [];
    return (jsonDecode(encoded) as List)
        .map((j) => GymStore.fromJson(Map<String, dynamic>.from(j as Map)))
        .toList();
  }

  Future<void> _saveGuest(List<GymStore> stores) async {
    final p = await SharedPreferences.getInstance();
    if (!await p.setString(
      _guestKey,
      jsonEncode(stores.map((s) => s.toJson()).toList()),
    )) {
      throw StateError('保存できませんでした');
    }
  }

  @override
  Future<List<GymStore>> registered() async {
    final user = _userId;
    if (user == null) {
      final stored = await _guestStores();
      if (!SupabaseConfig.initialized || stored.isEmpty) return stored;
      try {
        final fresh = <GymStore>[];
        for (var i = 0; i < stored.length; i += 50) {
          final batch = stored.skip(i).take(50).map((s) => s.id).toList();
          final rows = await _client
              .from('gym_stores')
              .select('*,gym_chains(name)')
              .inFilter('id', batch);
          fresh.addAll(rows.map(GymStore.fromJson));
        }
        // Keep registration membership/order, refresh known store metadata only.
        final byId = {for (final s in fresh) s.id: s};
        final updated = [for (final s in stored) byId[s.id] ?? s];
        await _saveGuest(updated);
        return updated;
      } catch (_) {
        return stored;
      }
    }
    final rows = await _client
        .from('user_gym_stores')
        .select('gym_stores(*,gym_chains(name))')
        .eq('user_id', user)
        .order('created_at');
    return rows
        .map(
          (r) => GymStore.fromJson(
            Map<String, dynamic>.from(r['gym_stores'] as Map),
          ),
        )
        .toList();
  }

  @override
  Future<void> register(GymStore store) async {
    if (!store.isSelectable) throw StateError('この店舗は現在登録できません');
    final user = _userId;
    if (user == null) {
      final stores = await _guestStores();
      if (!stores.any((s) => s.id == store.id)) {
        await _saveGuest([...stores, store]);
      }
      return;
    }
    await _client
        .from('user_gym_stores')
        .upsert(
          {'user_id': user, 'store_id': store.id},
          onConflict: 'user_id,store_id',
          ignoreDuplicates: true,
        );
  }

  @override
  Future<void> unregister(String storeId) async {
    final user = _userId;
    if (user == null) {
      await _saveGuest(
        (await _guestStores()).where((s) => s.id != storeId).toList(),
      );
      return;
    }
    await _client
        .from('user_gym_stores')
        .delete()
        .eq('user_id', user)
        .eq('store_id', storeId);
  }

  @override
  Future<void> reportStore({
    String? storeId,
    String? chainId,
    String? chainName,
    required String kind,
    String? name,
    String? address,
    String? officialUrl,
    required String comment,
  }) async {
    if (!canReport) throw StateError('報告にはログインが必要です');
    await _client.from('gym_store_reports').insert({
      'store_id': storeId,
      'chain_id': chainId,
      'reported_chain_name': chainName,
      'kind': kind,
      'reported_name': name,
      'reported_address': address,
      'reported_official_url': officialUrl,
      'comment': comment.trim(),
    });
  }

  @override
  Future<void> report({
    required String storeId,
    String? equipmentId,
    required String kind,
    String? equipmentName,
    required String comment,
    int? reportedQuantity,
    int? reportedUnavailableQuantity,
    String? unavailableScope,
  }) async {
    if (!canReport) throw StateError('報告にはアカウントへのログインが必要です');
    await _client.from('gym_equipment_reports').insert({
      'store_id': storeId,
      'equipment_id': equipmentId,
      'kind': kind,
      'equipment_name': equipmentName,
      'comment': comment.trim(),
      'reported_quantity': reportedQuantity,
      'reported_unavailable_quantity': reportedUnavailableQuantity,
      'unavailable_scope': unavailableScope,
    });
  }
}

class GymExerciseEvidence {
  const GymExerciseEvidence(
    this.exerciseId,
    this.equipmentIds,
    this.equipmentNames, {
    this.ruleId,
  });
  final String exerciseId;
  final List<String> equipmentIds, equipmentNames;
  final String? ruleId;
  factory GymExerciseEvidence.fromJson(Map<String, dynamic> j) =>
      GymExerciseEvidence(
        j['exercise_id'] as String,
        List<String>.from(j['equipment_ids'] as List),
        List<String>.from(j['equipment_names'] as List),
        ruleId: j['rule_id'] as String?,
      );
  Map<String, dynamic> toJson() => {
    'exercise_id': exerciseId,
    'equipment_ids': equipmentIds,
    'equipment_names': equipmentNames,
    'rule_id': ruleId,
  };
}

class GymStoreDetail {
  const GymStoreDetail({
    required this.store,
    required this.equipment,
    required this.evidence,
  });
  final GymStore store;
  final List<GymEquipment> equipment;
  final List<GymExerciseEvidence> evidence;
  Set<String> get exerciseIds => evidence.map((e) => e.exerciseId).toSet();
  List<GymExerciseEvidence> forEquipment(String id) =>
      evidence.where((e) => e.equipmentIds.contains(id)).toList();
  factory GymStoreDetail.fromJson(Map<String, dynamic> j) {
    final store = GymStore.fromJson(
      Map<String, dynamic>.from(j['store'] as Map),
    );
    final equipment =
        [
          for (final e in j['equipment'] as List)
            GymEquipment.fromJson(Map<String, dynamic>.from(e as Map)),
        ].where((e) {
          if (!store.communityEquipmentOnly) return true;
          if (store.chainId == 'auns-gym') {
            return e.sourceUrl?.startsWith('https://beauty.hotpepper.jp/') !=
                    true &&
                !const {
                  'auns-gym:fp_eq_758e41c26277',
                  'auns-gym:fp_eq_a08d82bc89a9',
                  'auns-gym:fp_eq_0a13c23b47c0',
                  'auns-gym:fp_eq_72c38ceaa2bb',
                  'auns-gym:fp_eq_986d089885b3',
                  'auns-gym:fp_eq_93cafce3bb2c',
                  'auns-gym:fp_eq_09d623796663',
                }.contains(e.id);
          }
          return const {'admin', 'confirmed_report'}.contains(e.sourceKind);
        }).toList();
    final ids = equipment.map((e) => e.id).toSet();
    final evidence = [
      for (final e in j['evidence'] as List)
        GymExerciseEvidence.fromJson(Map<String, dynamic>.from(e as Map)),
    ].where((e) => e.equipmentIds.every(ids.contains)).toList();
    return GymStoreDetail(
      store: store,
      equipment: equipment,
      evidence: evidence,
    );
  }
  Map<String, dynamic> toJson() => {
    'store': store.toJson(),
    'equipment': equipment.map((e) => e.toJson()).toList(),
    'evidence': evidence.map((e) => e.toJson()).toList(),
  };
}
