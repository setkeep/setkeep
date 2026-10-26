import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setkeep/gym/gym_repository.dart';
import 'package:setkeep/gym/gym_equipment_cache.dart';
import 'package:setkeep/gym/gym_pages.dart';
import 'package:setkeep/gym/training_place_preference.dart';
import 'package:setkeep/main.dart';

import 'gym_integration_test.dart' show FakeGyms, storeA, storeB;

final detailedStore = GymStore(
  id: 'detail',
  chainName: '共通チェーン',
  chainId: 'chain',
  name: '店舗',
  city: '市区町村',
  equipmentStatus: 'partial',
  checkedAt: DateTime(2025, 1, 1),
  officialUrl: 'https://example.com/store',
);
const rack = GymEquipment(
  id: 'rack',
  name: 'パワーラック',
  category: 'フリーウェイト',
  quantity: 3,
  unavailableQuantity: 1,
  manufacturer: '確認済みメーカー',
  model: '型番A',
);
const bench = GymEquipment(
  id: 'bench',
  name: 'アジャスタブルベンチ',
  category: 'フリーウェイト',
);
const row = GymEquipment(
  id: 'row',
  name: 'シーテッドロー',
  rawName: 'シーテッドロウ',
  category: '筋トレ',
  aliases: ['ローイング'],
  exerciseIds: {'seated_row'},
);

class DetailRepo extends FakeGyms {
  int detailCalls = 0;
  final Set<String> pending = {};
  List<GymExerciseEvidence> evidence = const [
    GymExerciseEvidence(
      'bench_press',
      ['rack', 'bench'],
      ['パワーラック', 'アジャスタブルベンチ'],
      ruleId: 'rule',
    ),
    GymExerciseEvidence(
      'close_grip_bench_press',
      ['rack', 'bench'],
      ['パワーラック', 'アジャスタブルベンチ'],
      ruleId: 'rule2',
    ),
    GymExerciseEvidence('seated_row', ['row'], ['シーテッドロー']),
    GymExerciseEvidence('seated_row', ['row2'], ['別機種のロー']),
  ];
  @override
  Future<GymStoreDetail> detail(GymStore store) async {
    detailCalls++;
    if (this.fail) throw StateError('offline');
    return GymStoreDetail(
      store: detailedStore,
      equipment: [rack, bench, row],
      evidence: evidence,
    );
  }

  @override
  Future<Map<String, String>> chains() async => {'chain': '共通チェーン'};
  @override
  Future<Set<String>> pendingEquipment(String storeId) async => pending;
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
    if (equipmentId != null) pending.add(equipmentId);
    await super.report(
      storeId: storeId,
      equipmentId: equipmentId,
      kind: kind,
      equipmentName: equipmentName,
      comment: comment,
      reportedQuantity: reportedQuantity,
      reportedUnavailableQuantity: reportedUnavailableQuantity,
      unavailableScope: unavailableScope,
    );
  }
}

void main() {
  late DetailRepo repo;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = DetailRepo();
    GymServices.override = repo;
  });
  tearDown(() => GymServices.override = null);
  Future<void> open(WidgetTester t, Widget page) async {
    await t.pumpWidget(MaterialApp(home: page));
    await t.pumpAndSettle();
  }

  test(
    'equipment aliases, quantity, metadata and cache TTL round trip',
    () async {
      final d = await repo.detail(detailedStore);
      expect(d.exerciseIds.length, 3);
      expect(row.matches('ローイング'), isTrue);
      expect(row.matches('シーテッドロウ'), isTrue);
      expect(row.displayCategory, 'マシン');
      expect(rack.usable, isTrue);
      expect(
        const GymEquipment(
          id: 'e',
          name: 'e',
          category: 'その他',
          quantity: 3,
          unavailableQuantity: 3,
        ).usable,
        isFalse,
      );
      expect(
        const GymEquipment(
          id: 'e',
          name: 'e',
          category: 'その他',
          available: false,
        ).usable,
        isFalse,
      );
      final now = DateTime(2026, 9, 24);
      await GymEquipmentCache.write(d, now: now);
      final cached = (await GymEquipmentCache.read('detail'))!;
      expect(cached.staleAt(now.add(const Duration(hours: 23))), isFalse);
      expect(cached.staleAt(now.add(const Duration(hours: 24))), isTrue);
      expect(cached.detail.equipment.first.quantity, 3);
      expect(cached.detail.equipment.first.unavailableQuantity, 1);
      expect(cached.detail.evidence.first.equipmentIds, ['rack', 'bench']);
      expect(cached.detail.store.officialUrl, detailedStore.officialUrl);
    },
  );
  testWidgets(
    'equipment state reports require values and submit distinct payloads',
    (t) async {
      await open(
        t,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showGymEquipmentReport(context, detailedStore, rack),
              child: const Text('報告を開く'),
            ),
          ),
        ),
      );
      Future<void> choose(String label) async {
        await t.tap(find.text('報告を開く'));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('gymReportKind')));
        await t.pumpAndSettle();
        await t.tap(find.text(label).last);
        await t.pumpAndSettle();
      }

      await choose('台数が違う');
      await t.tap(find.byKey(const Key('submitGymEquipmentReport')));
      await t.pumpAndSettle();
      expect(repo.reportValues, isEmpty);
      expect(find.textContaining('総台数を1〜100'), findsOneWidget);
      await t.enterText(find.byKey(const Key('gymReportedQuantity')), '4');
      await t.tap(find.byKey(const Key('submitGymEquipmentReport')));
      await t.pumpAndSettle();
      expect(repo.reportValues.last['reported_quantity'], 4);

      await choose('現在利用できない');
      await t.tap(find.byKey(const Key('gymUnavailableScope')));
      await t.pumpAndSettle();
      await t.tap(find.text('一部利用不可').last);
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const Key('gymReportedUnavailableQuantity')),
        '1',
      );
      await t.tap(find.byKey(const Key('submitGymEquipmentReport')));
      await t.pumpAndSettle();
      expect(repo.reportValues.last['unavailable_scope'], 'partial');
      expect(repo.reportValues.last['reported_unavailable_quantity'], 1);

      await choose('利用可能に戻った');
      expect(find.textContaining('全台が再び利用できる'), findsOneWidget);
      await t.tap(find.byKey(const Key('submitGymEquipmentReport')));
      await t.pumpAndSettle();
      expect(repo.reportValues.last['kind'], 'available_again');
      expect(repo.reportValues.last['reported_quantity'], isNull);
    },
  );
  test(
    'cache offline fallback and corrupt cache do not affect workouts',
    () async {
      final p = await SharedPreferences.getInstance();
      await p.setString('workout_history', 'unchanged');
      final d = await repo.detail(detailedStore);
      await GymEquipmentCache.write(d, now: DateTime(2020));
      repo.fail = true;
      expect(
        (await GymEquipmentCache.load(repo, detailedStore)).exerciseIds.length,
        3,
      );
      await p.setString('gym_equipment_v2_detail', 'broken');
      expect(await GymEquipmentCache.read('detail'), isNull);
      await expectLater(
        GymEquipmentCache.load(repo, detailedStore),
        throwsStateError,
      );
      expect(p.getString('workout_history'), 'unchanged');
    },
  );
  test(
    'fresh cached equipment is revalidated before store filtering',
    () async {
      final detail = await repo.detail(detailedStore);
      await GymEquipmentCache.write(detail);
      repo.detailCalls = 0;
      await GymEquipmentCache.load(repo, detailedStore);
      expect(repo.detailCalls, 1);
    },
  );
  testWidgets(
    'preferred store precedes home and other places without duplication',
    (t) async {
      repo.saved = [storeA, storeB];
      await TrainingPlacePreference.save(const TrainingPlace.store(storeB));
      await open(t, const RegisteredGymsPage());
      expect(
        t.getTopLeft(find.byKey(const Key('preferredTrainingPlaceCard'))).dy,
        lessThan(t.getTopLeft(find.text('自宅')).dy),
      );
      expect(
        t.getTopLeft(find.text('自宅')).dy,
        lessThan(t.getTopLeft(find.text(storeA.displayName)).dy),
      );
      expect(find.text('自宅'), findsOneWidget);
    },
  );
  testWidgets(
    'store detail metadata search aliases unknown quantity and refresh',
    (t) async {
      await open(t, GymStoreEquipmentPage(store: detailedStore));
      expect(find.byKey(const Key('gymEquipmentStatus')), findsNothing);
      expect(find.byKey(const Key('gymOfficialPage')), findsNothing);
      expect(find.text('最終確認日：2025/1/1'), findsNothing);
      expect(find.text('設備情報が古い可能性があります'), findsNothing);
      expect(find.text('対応 3種目'), findsOneWidget);
      expect(find.text('台数不明'), findsNothing);
      expect(find.text('確認済みメーカー'), findsNothing);
      await t.enterText(find.byKey(const Key('gymEquipmentSearch')), 'ローイング');
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byKey(const Key('gymEquipmentrow')),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.byKey(const Key('gymEquipmentrack')), findsNothing);
      expect(find.byKey(const Key('gymEquipmentrow')), findsOneWidget);
      final before = repo.detailCalls;
      final refresh = t
          .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
          .show();
      await t.pumpAndSettle();
      await refresh;
      expect(repo.detailCalls, greaterThan(before));
    },
  );
  testWidgets(
    'composite evidence and bulk addition preserve identities and report pending',
    (t) async {
      final batches = <Set<String>>[];
      await open(
        t,
        GymEquipmentExercisesPage(
          store: detailedStore,
          equipment: rack,
          evidence: repo.evidence.where((e) => e.ruleId != null).toList(),
          onAdd: (ids) async => batches.add(ids),
        ),
      );
      expect(find.text('他の設備と組み合わせてできる種目'), findsOneWidget);
      expect(find.text('パワーラック ＋ アジャスタブルベンチ'), findsWidgets);
      for (final id in ['bench_press', 'close_grip_bench_press']) {
        await t.scrollUntilVisible(
          find.byKey(Key('addGymExercise$id')),
          100,
          scrollable: find.byType(Scrollable).last,
        );
        await t.tap(find.byKey(Key('addGymExercise$id')));
        await t.pumpAndSettle();
      }
      expect(batches, isEmpty);
      await t.tap(find.byKey(const Key('addSelectedGymExercises')));
      await t.pumpAndSettle();
      expect(batches.single, {'bench_press', 'close_grip_bench_press'});
      expect(
        t
            .widget<FilledButton>(
              find.byKey(const Key('addSelectedGymExercises')),
            )
            .onPressed,
        isNull,
      );
      await t.scrollUntilVisible(
        find.byKey(const Key('reportGymEquipment')),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await t.tap(find.byKey(const Key('reportGymEquipment')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('submitGymEquipmentReport')));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byKey(const Key('gymReportPending')),
        -150,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.byKey(const Key('gymReportPending')), findsOneWidget);
      expect(repo.pending, {'rack'});
      expect(repo.evidence.length, 4);
    },
  );
  testWidgets('zero store results stay filtered until user chooses all', (
    t,
  ) async {
    repo.evidence = [];
    await open(
      t,
      const Scaffold(body: ExercisePickerSheet(gymStoreId: 'detail')),
    );
    expect(
      t
          .widget<ChoiceChip>(find.byKey(const Key('storeExerciseFilter')))
          .selected,
      isFalse,
    );
    await t.tap(find.byKey(const Key('storeExerciseFilter')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('showAllStoreExercises')), findsOneWidget);
    expect(
      t
          .widget<ChoiceChip>(find.byKey(const Key('storeExerciseFilter')))
          .selected,
      isTrue,
    );
    await t.tap(find.byKey(const Key('showAllStoreExercises')));
    await t.pumpAndSettle();
    expect(
      t
          .widget<ChoiceChip>(find.byKey(const Key('storeExerciseFilter')))
          .selected,
      isFalse,
    );
  });
  testWidgets('store-filtered exercise detail explains composite evidence', (
    t,
  ) async {
    await open(
      t,
      const Scaffold(body: ExercisePickerSheet(gymStoreId: 'detail')),
    );
    await t.tap(find.byKey(const Key('storeExerciseFilter')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('exerciseSearchField')), 'ベンチプレス');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('exerciseDetailsbench_press')));
    // The video player's loading indicator animates until its platform
    // controller is ready; the detail content does not depend on that event.
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('この店舗で使用可能'), findsOneWidget);
    expect(find.text('パワーラック ＋ アジャスタブルベンチ'), findsOneWidget);
  });
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('small store detail and stale offline cache $platform', (
      t,
    ) async {
      t.view.physicalSize = const Size(320, 568);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await GymEquipmentCache.write(
        await repo.detail(detailedStore),
        now: DateTime(2020),
      );
      repo.fail = true;
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: GymStoreEquipmentPage(store: detailedStore),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('gymTotalExerciseCount')), findsOneWidget);
      await t.scrollUntilVisible(
        find.text('更新できませんでした。前回取得した設備情報を表示しています。'),
        150,
        scrollable: find.byType(Scrollable).last,
      );
      expect(t.takeException(), isNull);
    });
  }
}
