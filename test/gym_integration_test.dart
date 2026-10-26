import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setkeep/main.dart';
import 'package:setkeep/gym/gym_repository.dart';
import 'package:setkeep/gym/gym_pages.dart';

const storeA = GymStore(
  id: 'a',
  chainName: 'FIT PLACE24',
  name: '松戸店',
  city: '松戸市',
  station: '松戸駅',
  equipmentStatus: 'published',
);
const storeB = GymStore(
  id: 'b',
  chainName: '別チェーン',
  name: '柏店',
  city: '柏市',
  station: '柏駅',
);
const preopeningStore = GymStore(
  id: 'anytime-fitness:preopening',
  chainName: 'エニタイムフィットネス',
  name: '開店準備店',
  city: '松戸市',
  pageStatus: 'preopening_text',
);

class FakeGyms extends GymRepository {
  List<GymStore> saved = [];
  bool fail = false, failRegistered = false;
  bool emptyEquipment = false;
  String query = '';
  final reports = <String>[];
  final reportValues = <Map<String, Object?>>[];
  @override
  bool get canReport => true;
  @override
  Future<List<GymStore>> search(String q, {int offset = 0}) async {
    if (fail) throw StateError('offline');
    query = q;
    return [
      storeA,
      storeB,
    ].where((s) => '${s.chainName} ${s.name}'.contains(q)).toList();
  }

  @override
  Future<List<GymStore>> registered() async {
    if (failRegistered) throw StateError('registration unavailable');
    return saved;
  }

  @override
  Future<void> register(GymStore s) async {
    if (!saved.any((e) => e.id == s.id)) saved.add(s);
  }

  @override
  Future<void> unregister(String id) async =>
      saved.removeWhere((e) => e.id == id);
  @override
  Future<List<GymEquipment>> equipment(String id, {int offset = 0}) async {
    if (fail) throw StateError('offline');
    if (emptyEquipment) return const [];
    return const [
      GymEquipment(
        id: 'e',
        name: 'ダンベル',
        category: 'フリーウェイト',
        exerciseIds: {'dumbbell_curl', 'hammer_curl'},
      ),
      GymEquipment(
        id: 'c',
        name: 'アジャスタブルベンチ',
        category: 'フリーウェイト',
        compositeRuleIds: {'rack_bench_rule'},
      ),
      GymEquipment(id: 'u', name: '未確認マシン', category: 'その他'),
    ];
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
    reports.add('$storeId/$kind/$equipmentName');
    reportValues.add({
      'kind': kind,
      'reported_quantity': reportedQuantity,
      'reported_unavailable_quantity': reportedUnavailableQuantity,
      'unavailable_scope': unavailableScope,
    });
  }
}

void main() {
  late FakeGyms repo;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = FakeGyms();
    GymServices.override = repo;
    CustomExercisePreference.exercises = [];
  });
  tearDown(() => GymServices.override = null);
  Future<void> page(WidgetTester t, Widget w) async {
    await t.pumpWidget(MaterialApp(home: w));
    await t.pumpAndSettle();
  }

  testWidgets('gym search supports store chain and network retry', (t) async {
    await page(t, const GymStoreSearchPage());
    for (final q in ['松戸店', 'FIT PLACE24']) {
      await t.enterText(find.byKey(const Key('gymStoreSearchField')), q);
      await t.pump(const Duration(milliseconds: 350));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('selectGymStorea')), findsOneWidget);
      expect(find.byKey(const Key('selectGymStoreb')), findsNothing);
    }
    repo.fail = true;
    await t.enterText(find.byKey(const Key('gymStoreSearchField')), '柏');
    await t.pump(const Duration(milliseconds: 350));
    await t.pumpAndSettle();
    expect(find.text('再読み込み'), findsOneWidget);
    repo.fail = false;
    await t.tap(find.text('再読み込み'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('selectGymStoreb')), findsOneWidget);
  });
  testWidgets('preopening store is identified and cannot be registered', (
    t,
  ) async {
    final parsed = GymStore.fromJson({
      'id': preopeningStore.id,
      'chain_name': preopeningStore.chainName,
      'name': preopeningStore.name,
      'source': {'page_status': 'preopening_text'},
    });
    expect(parsed.isPreopening, isTrue);
    expect(parsed.isSelectable, isFalse);
    expect(GymStore.fromJson(parsed.toJson()).isPreopening, isTrue);
    await page(t, GymStoreEquipmentPage(store: parsed, onSelect: () {}));
    expect(find.textContaining('オープン準備中'), findsWidgets);
    expect(
      t
          .widget<FilledButton>(
            find.byKey(const Key('confirmGymStoreSelection')),
          )
          .onPressed,
      isNull,
    );
  });
  testWidgets('registered gym failure does not block public store search', (
    t,
  ) async {
    repo.failRegistered = true;
    await page(t, const GymStoreSearchPage());
    expect(find.byKey(const Key('selectGymStorea')), findsOneWidget);
    expect(find.text('登録済み店舗を読み込めませんでした。店舗検索は利用できます。'), findsOneWidget);
    await t.enterText(find.byKey(const Key('gymStoreSearchField')), '松戸');
    await t.pump(const Duration(milliseconds: 350));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('selectGymStorea')), findsOneWidget);
  });

  testWidgets('multiple registered gyms can be added and removed', (t) async {
    await page(t, const RegisteredGymsPage());
    for (final id in ['a', 'b']) {
      await t.tap(find.byKey(const Key('registerGymButton')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(Key('selectGymStore$id')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('confirmGymStoreSelection')));
      await t.pumpAndSettle();
    }
    expect(repo.saved.length, 2);
    await t.tap(find.byKey(const Key('removeRegisteredGyma')));
    await t.pumpAndSettle();
    await t.tap(find.text('利用場所から削除'));
    await t.pumpAndSettle();
    expect(repo.saved.single.id, 'b');
  });
  testWidgets(
    'gym equipment maps multiple exercises without duplicate additions',
    (t) async {
      final added = <String>{};
      await page(
        t,
        GymStoreEquipmentPage(
          store: storeA,
          onAdd: (ids) async => added.addAll(ids),
        ),
      );
      expect(find.text('フリーウェイト'), findsOneWidget);
      expect(find.textContaining('対応種目は現在準備中です'), findsWidgets);

      await t.scrollUntilVisible(
        find.byKey(const Key('gymEquipmentc')),
        150,
        scrollable: find.byType(Scrollable).last,
      );
      await t.tap(find.byKey(const Key('gymEquipmentc')));
      await t.pumpAndSettle();
      expect(find.text('対応種目は現在準備中です'), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byKey(const Key('gymEquipmente')),
        150,
        scrollable: find.byType(Scrollable).last,
      );
      await t.tap(find.byKey(const Key('gymEquipmente')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('addGymExercisedumbbell_curl')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('addSelectedGymExercises')));
      await t.pumpAndSettle();
      expect(added, {'dumbbell_curl'});
      expect(
        t
            .widget<ListTile>(
              find.byKey(const Key('addGymExercisedumbbell_curl')),
            )
            .onTap,
        isNull,
      );
      expect(
        find.byKey(const Key('addGymExercisehammer_curl')),
        findsOneWidget,
      );
    },
  );
  testWidgets('gym reports validate added equipment and do not modify master', (
    t,
  ) async {
    await page(t, const GymStoreEquipmentPage(store: storeA));
    await t.tap(find.byKey(const Key('reportNewGymEquipment')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('submitGymEquipmentReport')));
    await t.pumpAndSettle();
    expect(repo.reports, isEmpty);
    await t.enterText(find.byKey(const Key('gymReportEquipmentName')), '新しい設備');
    await t.tap(find.byKey(const Key('submitGymEquipmentReport')));
    await t.pumpAndSettle();
    expect(repo.reports, ['a/added/新しい設備']);
    expect(find.byKey(const Key('gymEquipmente')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('store filter leaves normal search accessible', (t) async {
    await page(t, const Scaffold(body: ExercisePickerSheet(gymStoreId: 'a')));
    await t.enterText(
      find.byKey(const Key('exerciseSearchField')),
      'デクラインダンベルプレス',
    );
    await t.pumpAndSettle();
    expect(
      find.byKey(const Key('selectExercisedecline_dumbbell_press')),
      findsOneWidget,
    );
    await t.tap(find.byKey(const Key('storeExerciseFilter')));
    await t.pumpAndSettle();
    expect(
      find.byKey(const Key('selectExercisedecline_dumbbell_press')),
      findsNothing,
    );
    await t.tap(find.text('全種目'));
    await t.pumpAndSettle();
    expect(
      find.byKey(const Key('selectExercisedecline_dumbbell_press')),
      findsOneWidget,
    );
  });
  testWidgets('empty equipment is not described as a network failure', (
    t,
  ) async {
    repo.emptyEquipment = true;
    await page(t, const Scaffold(body: ExercisePickerSheet(gymStoreId: 'a')));
    await t.tap(find.byKey(const Key('storeExerciseFilter')));
    await t.pumpAndSettle();
    expect(find.textContaining('設備情報は未取得'), findsOneWidget);
    expect(find.textContaining('取得できませんでした'), findsNothing);
    expect(find.text('全種目を見る'), findsOneWidget);
  });
  testWidgets(
    'store filter includes mapped exercises and recovers from errors',
    (t) async {
      await page(t, const Scaffold(body: ExercisePickerSheet(gymStoreId: 'a')));
      await t.enterText(
        find.byKey(const Key('exerciseSearchField')),
        'ダンベルカール',
      );
      await t.pumpAndSettle();
      repo.fail = true;
      await t.tap(find.byKey(const Key('storeExerciseFilter')));
      await t.pumpAndSettle();
      expect(find.text('対応種目を取得できませんでした。「全種目」からも追加できます。'), findsOneWidget);
      expect(
        find.byKey(const Key('selectExercisedumbbell_curl')),
        findsOneWidget,
      );
      repo.fail = false;
      await t.tap(find.byKey(const Key('storeExerciseFilter')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('clearExerciseSearch')));
      await t.pumpAndSettle();
      final armCard = find.byKey(const Key('exerciseCategory腕'));
      await t.scrollUntilVisible(
        armCard,
        180,
        scrollable: find.byType(Scrollable).last,
      );
      expect(
        find.descendant(of: armCard, matching: find.text('2種目')),
        findsOneWidget,
      );
      await t.enterText(
        find.byKey(const Key('exerciseSearchField')),
        'ダンベルカール',
      );
      await t.pumpAndSettle();
      final row = find.byKey(const Key('selectExercisedumbbell_curl'));
      expect(row, findsOneWidget);
      await t.tap(row);
      await t.pumpAndSettle();
      expect(find.text('1種目選択中'), findsOneWidget);
    },
  );

  testWidgets('small gym screens keep long names and reporting usable', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 568);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    const longStore = GymStore(
      id: 'long',
      chainName: '長いチェーン名',
      name: '長い店舗名が続くショッピングセンターの店舗',
    );
    await page(t, const GymStoreEquipmentPage(store: longStore));
    await t.tap(find.byKey(const Key('reportNewGymEquipment')));
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const Key('gymReportEquipmentName')),
      '長い名前の新規設備',
    );
    await t.ensureVisible(find.byKey(const Key('submitGymEquipmentReport')));
    await t.tap(find.byKey(const Key('submitGymEquipmentReport')));
    await t.pumpAndSettle();
    expect(repo.reports.length, 1);
    expect(t.takeException(), isNull);
  });

  test('guest stores persist privately and deduplicate; record keeps stable store ID', () async {
    final r = SupabaseGymRepository();
    await r.register(storeA);
    await r.register(storeA);
    await r.register(storeB);
    expect((await SupabaseGymRepository().registered()).length, 2);
    await r.unregister('a');
    expect((await r.registered()).single.id, 'b');
    final w = WorkoutRecord(
      date: DateTime(2026, 9, 23),
      sets: [],
      gymName: storeA.displayName,
      gymStoreId: storeA.id,
    );
    expect(
      WorkoutRecord.fromJson(jsonDecode(jsonEncode(w.toJson()))).gymStoreId,
      'a',
    );
    expect(
      WorkoutRecord.fromJson({
        'date': '2026-09-23',
        'sets': [],
        'gymName': '昔のジム',
      }).gymStoreId,
      isNull,
    );
  });
}
