import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/gym/gym_pages.dart';
import 'package:setkeep/gym/gym_repository.dart';

// RPC contract: original inventory IDs/names survive canonical resolution.
GymStoreDetail resolvedDetail() => GymStoreDetail.fromJson({
  'store': {
    'id': 'anytime-fitness:anytime_jp_1d4bdbb1432e',
    'chain_name': 'エニタイムフィットネス',
    'name': '松戸馬橋店',
  },
  'equipment': [
    {
      'quantity': null,
      'raw_name': 'ダンベル 1～50kg',
      'available': true,
      'equipment': {
        'id': 'golds-gym:fp_eq_e2f3c2ba7ec7',
        'name': 'ダンベル',
        'category': 'フリーウェイト',
        'equipment_exercise_mapping': [
          {'exercise_id': 'dumbbell_curl'},
        ],
        'exercise_equipment_rule_items': [
          {
            'rule_id':
                'canonical:incline_dumbbell_press:dumbbell+incline_bench',
          },
        ],
      },
    },
    {
      'available': true,
      'equipment': {
        'id': 'bench',
        'name': 'アジャスタブルベンチ',
        'category': 'フリーウェイト',
      },
    },
  ],
  'evidence': [
    {
      'exercise_id': 'dumbbell_curl',
      'equipment_ids': ['golds-gym:fp_eq_e2f3c2ba7ec7'],
      'equipment_names': ['ダンベル'],
      'rule_id': null,
    },
    {
      'exercise_id': 'incline_dumbbell_press',
      'equipment_ids': ['golds-gym:fp_eq_e2f3c2ba7ec7', 'bench'],
      'equipment_names': ['ダンベル', 'アジャスタブルベンチ'],
      'rule_id': 'canonical:incline_dumbbell_press:dumbbell+incline_bench',
    },
    // Multiple evidence paths must not create duplicate selectable exercises.
    {
      'exercise_id': 'incline_dumbbell_press',
      'equipment_ids': ['golds-gym:fp_eq_e2f3c2ba7ec7', 'bench'],
      'equipment_names': ['ダンベル', 'アジャスタブルベンチ'],
      'rule_id': 'legacy-reviewed-rule',
    },
  ],
});

void main() {
  test('canonical RPC data preserves inventory and deduplicates exercises', () {
    final d = resolvedDetail();
    expect(d.equipment.first.rawName, 'ダンベル 1～50kg');
    expect(d.exerciseIds, {'dumbbell_curl', 'incline_dumbbell_press'});
    expect(d.forEquipment(d.equipment.first.id), hasLength(3));
    final restored = GymStoreDetail.fromJson(d.toJson());
    expect(restored.exerciseIds, d.exerciseIds);
    expect(restored.evidence.last.equipmentNames, ['ダンベル', 'アジャスタブルベンチ']);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('resolved equipment displays and adds one batch on $platform', (
      t,
    ) async {
      t.view.physicalSize = const Size(360, 740);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final d = resolvedDetail();
      final batches = <Set<String>>[];
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: GymEquipmentExercisesPage(
            store: d.store,
            equipment: d.equipment.first,
            evidence: d.evidence,
            allowReports: false,
            onAdd: (ids) async => batches.add(ids),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('対応種目は現在準備中です'), findsNothing);
      expect(find.textContaining('canonical:'), findsNothing);
      expect(find.text('ダンベル ＋ アジャスタブルベンチ'), findsWidgets);
      for (final id in ['dumbbell_curl', 'incline_dumbbell_press']) {
        final tile = find.byKey(ValueKey('addGymExercise$id'));
        await t.ensureVisible(tile);
        await t.tap(tile);
        await t.pumpAndSettle();
        expect(tile, findsOneWidget);
      }
      await t.tap(find.byKey(const Key('addSelectedGymExercises')));
      await t.pumpAndSettle();
      expect(batches.single, {'dumbbell_curl', 'incline_dumbbell_press'});
      expect(t.takeException(), isNull);
    });
  }
}
