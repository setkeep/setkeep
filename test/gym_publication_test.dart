import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setkeep/gym/gym_equipment_cache.dart';
import 'package:setkeep/gym/gym_pages.dart';
import 'package:setkeep/gym/gym_repository.dart';

import 'gym_integration_test.dart' show FakeGyms;

// RPC fixture with official provenance and no user reports/confirmations.
// Source/date/unknown values are not manufactured by the display layer.
GymStoreDetail officialDetail({bool present = true}) =>
    GymStoreDetail.fromJson({
      'store': {
        'id': 'publication-store',
        'chain_name': 'テストチェーン',
        'name': 'テスト店舗',
        'equipment_status': 'partial',
        'checked_at': '2026-01-02T00:00:00Z',
        'official_url': 'https://example.com/store',
      },
      'equipment': [
        if (present)
          {
            'equipment_id': 'publication-machine',
            'source_kind': 'official',
            'source_url': 'https://example.com/equipment',
            'checked_at': '2026-01-02T00:00:00Z',
            'quantity': null,
            'available': true,
            'equipment': {
              'id': 'publication-machine',
              'name': 'チェストプレス',
              'category': '筋トレ',
              'manufacturer': '登録済みメーカー',
              'model': '登録済み型番',
              'equipment_exercise_mapping': [
                {'exercise_id': 'chest_press'},
              ],
            },
          },
      ],
      'evidence': [
        if (present)
          {
            'exercise_id': 'chest_press',
            'equipment_ids': ['publication-machine'],
            'equipment_names': ['チェストプレス'],
          },
      ],
    });

class PublicationRepo extends FakeGyms {
  GymStoreDetail value = officialDetail();
  @override
  Future<GymStoreDetail> detail(GymStore store) async => value;
}

void main() {
  late PublicationRepo repo;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = PublicationRepo();
    GymServices.override = repo;
  });
  tearDown(() => GymServices.override = null);

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'official inventory without votes remains usable on $platform',
      (t) async {
        t.view.physicalSize = const Size(360, 740);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await t.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            home: GymStoreEquipmentPage(store: repo.value.store),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('対応 1種目'), findsOneWidget);
        expect(find.text('最終確認日：2026/1/2'), findsNothing);
        expect(find.byKey(const Key('gymOfficialPage')), findsNothing);
        expect(find.byKey(const Key('reportNewGymEquipment')), findsOneWidget);
        final tile = find.byKey(const Key('gymEquipmentpublication-machine'));
        await t.scrollUntilVisible(
          tile,
          100,
          scrollable: find
              .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.textContaining('対応種目は現在準備中'), findsNothing);
        await t.tap(tile);
        await t.pumpAndSettle();
        expect(find.text('メーカー：登録済みメーカー'), findsOneWidget);
        expect(find.text('型番：登録済み型番'), findsOneWidget);
        expect(find.textContaining('1台'), findsNothing);
        expect(find.textContaining('対応種目は現在準備中'), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
  }

  test(
    'persisted cache keeps date and unknown quantity, refresh honors removal',
    () async {
      final old = repo.value;
      await GymEquipmentCache.write(old);
      // Read from preferences, not a retained UI/controller instance.
      final cached = (await GymEquipmentCache.read(old.store.id))!.detail;
      expect(cached.exerciseIds, {'chest_press'});
      expect(cached.equipment.single.quantity, isNull);
      expect(cached.equipment.single.checkedAt, DateTime.utc(2026, 1, 2));
      repo.value = officialDetail(present: false);
      final refreshed = await GymEquipmentCache.load(repo, old.store);
      expect(refreshed.equipment, isEmpty);
      expect(refreshed.exerciseIds, isEmpty);
      expect(
        (await GymEquipmentCache.read(old.store.id))!.detail.equipment,
        isEmpty,
      );
      expect(refreshed.store.equipmentStatus, 'partial');
    },
  );
}
