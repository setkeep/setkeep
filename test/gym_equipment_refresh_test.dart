import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setkeep/gym/gym_equipment_cache.dart';
import 'package:setkeep/gym/gym_pages.dart';
import 'package:setkeep/gym/gym_repository.dart';

import 'gym_integration_test.dart' show FakeGyms;

const store = GymStore(
  id: 'kanekin-fitness-gym:matsudo',
  chainId: 'kanekin-fitness-gym',
  chainName: 'KANEKIN FITNESS GYM',
  name: '松戸店',
);
final cables = [
  for (final entry in const {
    'community-training:cable_crossover': 'ケーブルクロスオーバー',
    'community-training:dual_pulley': 'デュアルアジャスタブルプーリー',
  }.entries)
    GymEquipment.fromJson({
      'source_kind': 'admin',
      'available': true,
      'equipment': {'id': entry.key, 'name': entry.value, 'category': '利用者確認'},
    }),
];

final latest = GymStoreDetail(
  store: store,
  equipment: cables,
  evidence: const [
    GymExerciseEvidence(
      'cable_fly',
      ['community-training:cable_crossover'],
      ['ケーブルクロスオーバー'],
    ),
    GymExerciseEvidence(
      'cable_curl',
      ['community-training:dual_pulley'],
      ['デュアルアジャスタブルプーリー'],
    ),
  ],
);

class RefreshRepository extends FakeGyms {
  int calls = 0;
  Completer<GymStoreDetail>? pending;
  @override
  Future<GymStoreDetail> detail(GymStore requested) async {
    expect(requested.id, store.id);
    calls++;
    if (this.fail) throw StateError('offline');
    return pending?.future ?? latest;
  }
}

void main() {
  late RefreshRepository repo;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = RefreshRepository();
    GymServices.override = repo;
  });
  tearDown(() => GymServices.override = null);
  test('admin cable IDs survive parsing and offline cache without local master IDs', () async {
    final detail = GymStoreDetail.fromJson(latest.toJson());
    expect(detail.equipment.map((e) => e.id), cables.map((e) => e.id));
    expect(detail.equipment.every((e) => e.usable), true);
    expect(detail.exerciseIds, {'cable_fly', 'cable_curl'});
    await GymEquipmentCache.write(detail);
    repo.fail = true;
    expect((await GymEquipmentCache.load(repo, store)).equipment.length, 2);
  });

  testWidgets(
    'resuming a stale offline equipment page fetches new approved equipment',
    (t) async {
      await GymEquipmentCache.write(
        const GymStoreDetail(store: store, equipment: [], evidence: []),
      );
      repo.fail = true;
      await t.pumpWidget(
        const MaterialApp(home: GymStoreEquipmentPage(store: store)),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('前回取得した設備情報'), findsOneWidget);
      expect(
        find.byKey(const Key('gymEquipmentcommunity-training:dual_pulley')),
        findsNothing,
      );
      repo.fail = false;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(repo.calls, 2);
      for (final equipment in cables) {
        await t.enterText(
          find.byKey(const Key('gymEquipmentSearch')),
          equipment.name,
        );
        await t.pumpAndSettle();
        expect(
          find.byKey(ValueKey('gymEquipment${equipment.id}')),
          findsOneWidget,
        );
      }
      expect(
        (await GymEquipmentCache.read(store.id))!.detail.equipment.length,
        2,
      );
    },
  );

  testWidgets('older response cannot overwrite equipment refreshed on resume', (
    t,
  ) async {
    final old = Completer<GymStoreDetail>();
    repo.pending = old;
    await t.pumpWidget(
      const MaterialApp(home: GymStoreEquipmentPage(store: store)),
    );
    await t.pump();
    repo.pending = null;
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    old.complete(
      const GymStoreDetail(store: store, equipment: [], evidence: []),
    );
    await t.pumpAndSettle();
    expect(repo.calls, 2);
    await t.enterText(find.byKey(const Key('gymEquipmentSearch')), 'デュアル');
    await t.pumpAndSettle();
    expect(
      find.byKey(const Key('gymEquipmentcommunity-training:dual_pulley')),
      findsOneWidget,
    );
    expect(
      (await GymEquipmentCache.read(store.id))!.detail.equipment.length,
      2,
    );
  });
}
