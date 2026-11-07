import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setkeep/main.dart';
import 'package:setkeep/gym/gym_repository.dart';
import 'package:setkeep/gym/place_equipment_pages.dart';
import 'package:setkeep/gym/training_place_preference.dart';

import 'gym_integration_test.dart' show FakeGyms, storeA;

class EquipmentRepo extends FakeGyms {
  final exerciseReports = <String>[];
  bool failReports = false;
  @override
  Future<void> reportExercises({
    required String storeId,
    required String kind,
    required Set<String> exerciseIds,
    required String comment,
  }) async {
    for (final id in exerciseIds) {
      await reportExercise(
        storeId: storeId,
        kind: kind,
        exerciseId: id,
        comment: comment,
      );
    }
  }

  @override
  Future<List<GymEquipment>> searchEquipment(
    String query, {
    int offset = 0,
  }) async => [
    const GymEquipment(id: 'rack', name: 'パワーラック', category: 'フリーウェイト'),
    const GymEquipment(id: 'bench', name: 'アジャスタブルベンチ', category: 'フリーウェイト'),
  ].where((e) => e.name.contains(query)).toList();
  @override
  Future<List<GymExerciseEvidence>> equipmentEvidence(Set<String> ids) async =>
      [
        if (ids.contains('rack'))
          const GymExerciseEvidence('barbell_squat', ['rack'], ['パワーラック']),
        if (ids.containsAll({'rack', 'bench'}))
          const GymExerciseEvidence(
            'bench_press',
            ['rack', 'bench'],
            ['パワーラック', 'アジャスタブルベンチ'],
            ruleId: 'pair',
          ),
      ];
  @override
  Future<void> reportExercise({
    required String storeId,
    required String kind,
    String? exerciseId,
    required String comment,
  }) async {
    if (failReports) {
      throw const PostgrestException(
        message: 'QA permission denied',
        code: '42501',
      );
    }
    final key = '$storeId/$kind/$exerciseId/$comment';
    if (!exerciseReports.contains(key)) exerciseReports.add(key);
  }
}

void main() {
  late EquipmentRepo repo;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repo = EquipmentRepo();
    GymServices.override = repo;
    await CustomGymPreference.load();
  });
  tearDown(() => GymServices.override = null);
  test('stable IDs survive rename, private inventories and old records remain separate', () async {
    await CustomGymPreference.add('体育館');
    final id = CustomGymPreference.idFor('体育館')!;
    await repo.savePrivateEquipment(
      id,
      const PrivatePlaceEquipment(id: 'rack', equipmentId: 'rack', name: 'ラック'),
    );
    expect((await repo.privateEvidence(id)).map((e) => e.exerciseId), [
      'barbell_squat',
    ]);
    await repo.savePrivateEquipment(
      id,
      const PrivatePlaceEquipment(
        id: 'bench',
        equipmentId: 'bench',
        name: 'ベンチ',
        quantity: 2,
      ),
    );
    expect(
      (await repo.privateEvidence(id)).map((e) => e.exerciseId),
      contains('bench_press'),
    );
    await CustomGymPreference.update('体育館', '会社');
    await CustomGymPreference.load();
    expect(CustomGymPreference.idFor('会社'), id);
    expect(await repo.privateEquipment('different-place'), isEmpty);
    final record = WorkoutRecord(
      date: DateTime(2026),
      sets: const [],
      gymName: '体育館',
      customPlaceId: id,
    );
    final encoded = jsonEncode(record.toJson());
    await repo.deletePrivateEquipment(id, itemId: 'bench');
    expect(
      (await repo.privateEvidence(id)).map((e) => e.exerciseId),
      isNot(contains('bench_press')),
    );
    await CustomGymPreference.remove('会社');
    expect(await repo.privateEquipment(id), isEmpty);
    expect(jsonEncode(record.toJson()), encoded);
    expect(WorkoutRecord.fromJson(record.toJson()).customPlaceId, id);
    expect(record.gymStoreId, isNull);
  });
  testWidgets(
    'workout completion preserves manual place ID independently of store ID',
    (t) async {
      await CustomGymPreference.add('体育館');
      final id = CustomGymPreference.idFor('体育館')!;
      await TrainingPlacePreference.save(const TrainingPlace.manual('体育館'));
      WorkoutUiPreference.completionCheckEnabled = false;
      WorkoutUiPreference.workoutTimerEnabled = false;
      WorkoutUiPreference.workoutDurationEnabled = false;
      RestTimerPreference.enabled = false;
      addTearDown(() async {
        await WorkoutUiPreference.load();
        await RestTimerPreference.load();
      });
      WorkoutRecord? saved;
      await t.pumpWidget(
        MaterialApp(
          home: WorkoutPage(
            useDefaultPlace: true,
            initialWorkout: WorkoutRecord(
              date: DateTime(2026),
              sets: const [
                RecordedSet(
                  exerciseName: 'ベンチプレス',
                  bodyPart: '胸',
                  weight: 60,
                  reps: 10,
                  completed: true,
                ),
              ],
            ),
            onSave: (record) async => saved = record,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('completeWorkoutButton')));
      await t.pumpAndSettle();
      expect(saved?.gymName, '体育館');
      expect(saved?.gymStoreId, isNull);
      expect(saved?.customPlaceId, id);
      expect(saved?.sets.single.weight, 60);
      expect(WorkoutRecord.fromJson(saved!.toJson()).customPlaceId, id);
      await t.pumpWidget(const SizedBox());
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'private equipment search add edit delete and explicit free mapping on $platform',
      (t) async {
        t.view.physicalSize = const Size(360, 720);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await t.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            home: const PrivatePlaceEquipmentPage(placeId: 'p', name: '体育館'),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('addPrivateEquipment')));
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const Key('equipmentMasterSearch')),
          'ラック',
        );
        await t.pumpAndSettle(const Duration(milliseconds: 400));
        expect(find.text('アジャスタブルベンチ'), findsNothing);
        await t.tap(find.byKey(const Key('selectMasterEquipmentrack')));
        await t.pumpAndSettle();
        expect((await repo.privateEquipment('p')).single.equipmentId, 'rack');
        await t.tap(find.byKey(const Key('editPrivateEquipmentmaster:rack')));
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const Key('privateEquipmentQuantity')),
          '3',
        );
        await t.tap(find.byKey(const Key('savePrivateEquipment')));
        await t.pumpAndSettle();
        expect((await repo.privateEquipment('p')).single.quantity, 3);
        await t.tap(find.byKey(const Key('privateEquipmentmaster:rack')));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('reportGymEquipment')), findsNothing);
        expect(
          find.byKey(const Key('addGymExercisebarbell_squat')),
          findsOneWidget,
        );
        await t.pageBack();
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('deletePrivateEquipmentmaster:rack')));
        await t.pumpAndSettle();
        expect(await repo.privateEquipment('p'), isEmpty);
        await t.tap(find.byKey(const Key('addPrivateEquipment')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('addFreeEquipment')));
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const Key('privateEquipmentName')),
          '独自ロー',
        );
        await t.tap(find.byKey(const Key('savePrivateEquipment')));
        await t.pumpAndSettle();
        var item = (await repo.privateEquipment('p')).single;
        expect(item.equipmentId, isNull);
        expect(await repo.privateEvidence('p'), isEmpty);
        await t.tap(find.byKey(ValueKey('editPrivateEquipment${item.id}')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('choosePrivateExercise')));
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const Key('placeExerciseSearch')),
          'ベンチプレス',
        );
        await t.pumpAndSettle();
        await t.scrollUntilVisible(
          find.byKey(const Key('choosePlaceExercisebench_press')),
          160,
          scrollable: find.descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('choosePlaceExercisebench_press')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('savePrivateEquipment')));
        await t.pumpAndSettle();
        expect(
          (await repo.privateEvidence('p')).single.exerciseId,
          'bench_press',
        );
        expect(repo.reports, isEmpty);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'private filter uses combined equipment; only DB filtered view offers reports',
    (t) async {
      await repo.savePrivateEquipment(
        'p',
        const PrivatePlaceEquipment(id: 'r', name: 'ラック', equipmentId: 'rack'),
      );
      await repo.savePrivateEquipment(
        'p',
        const PrivatePlaceEquipment(id: 'b', name: 'ベンチ', equipmentId: 'bench'),
      );
      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ExercisePickerSheet(customPlaceId: 'p')),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('この場所でできる'), findsOneWidget);
      expect(find.byKey(const Key('reportStoreExercises')), findsNothing);
      await t.tap(find.byKey(const Key('storeExerciseFilter')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('storeExerciseCount')), findsNothing);
      expect(
        (await repo.privateEvidence('p')).map((e) => e.exerciseId),
        containsAll(['barbell_squat', 'bench_press']),
      );
      expect(find.byKey(const Key('reportStoreExercises')), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ExercisePickerSheet(gymStoreId: storeA.id)),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('reportStoreExercises')), findsNothing);
      await t.tap(find.byKey(const Key('storeExerciseFilter')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('reportStoreExercises')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(
        const MaterialApp(home: Scaffold(body: ExercisePickerSheet())),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('storeExerciseFilter')), findsNothing);
    },
  );
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'store picker keyboard keeps results and footer visible on $platform',
      (t) async {
        t.view.physicalSize = const Size(320, 568);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.view.resetViewInsets);
        t.view.padding = const FakeViewPadding(top: 24);
        addTearDown(t.view.resetPadding);
        repo.saved = [storeA];
        await TrainingPlacePreference.save(const TrainingPlace.store(storeA));
        await t.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            home: const WorkoutPage(useDefaultPlace: true, resumeDraft: false),
          ),
        );
        await t.pumpAndSettle();
        await Scrollable.ensureVisible(
          t.element(find.byKey(const Key('addExerciseButton'))),
          alignment: 0.5,
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('addExerciseButton')));
        await t.pumpAndSettle();
        final sheet = t.widget<BottomSheet>(find.byType(BottomSheet));
        expect(sheet.clipBehavior, Clip.antiAlias);
        final header = t.widget<ColoredBox>(
          find.byKey(const Key('exercisePickerHeader')),
        );
        expect(sheet.backgroundColor, header.color);
        final surface = t.widget<Material>(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Material),
          ).first,
        );
        expect(surface.clipBehavior, Clip.antiAlias);
        expect(surface.shape, isA<RoundedRectangleBorder>());
        await t.tap(find.byKey(const Key('storeExerciseFilter')));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('reportStoreExercises')), findsOneWidget);
        expect(find.byKey(const Key('storeExerciseCount')), findsNothing);
        expect(
          find.descendant(
            of: find.byKey(const Key('exercisePickerHeader')),
            matching: find.byKey(const Key('reportStoreExercises')),
          ),
          findsOneWidget,
        );
        final normalList = find.byKey(const Key('exercisePickerListClip'));
        expect(t.getSize(normalList).height, greaterThan(210));
        // Both category and exercise views retain the compact shared header.
        await t.scrollUntilVisible(
          find.byKey(const Key('exerciseCategory腕')),
          140,
          scrollable: find.descendant(
            of: normalList,
            matching: find.byType(Scrollable),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('exerciseCategory腕')));
        await t.pumpAndSettle();
        expect(
          find.byKey(const Key('addCustomExerciseForCategory')),
          findsOneWidget,
        );
        expect(t.getSize(normalList).height, greaterThan(210));
        await t.tap(find.byKey(const Key('exerciseSearchField')));
        await t.enterText(find.byKey(const Key('exerciseSearchField')), 'ダンベル');
        t.view.viewInsets = const FakeViewPadding(bottom: 260);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(
          find.byKey(const Key('reportStoreExercises')).hitTestable(),
          findsOneWidget,
        );
        expect(find.byTooltip('対応種目を報告'), findsOneWidget);
        expect(find.byKey(const Key('selectedExerciseCount')), findsNothing);
        final list = find.byKey(const Key('exercisePickerListClip'));
        expect(t.getSize(list).height, greaterThan(60));
        final search = t.getRect(find.byKey(const Key('exerciseSearchField')));
        final footer = t.getRect(find.byKey(const Key('addSelectedExercises')));
        expect(search.bottom, lessThanOrEqualTo(t.getRect(list).top));
        expect(footer.bottom, lessThanOrEqualTo(568 - 260));
        final scrollable = find.descendant(
          of: list,
          matching: find.byType(Scrollable),
        );
        await t.scrollUntilVisible(
          find.byKey(const Key('selectExercisehammer_curl')),
          60,
          scrollable: scrollable,
        );
        await Scrollable.ensureVisible(
          t.element(find.byKey(const Key('selectExercisehammer_curl'))),
          alignment: 0.5,
        );
        await t.pumpAndSettle();
        expect(
          find.byKey(const Key('selectExercisehammer_curl')).hitTestable(),
          findsOneWidget,
        );
        await t.tap(find.byKey(const Key('selectExercisehammer_curl')));
        await t.pumpAndSettle();
        expect(
          t
              .widget<FilledButton>(
                find.byKey(const Key('addSelectedExercises')),
              )
              .onPressed,
          isNotNull,
        );
        t.view.resetViewInsets();
        FocusManager.instance.primaryFocus?.unfocus();
        await t.pumpAndSettle();
        expect(find.text('1種目選択中'), findsOneWidget);
        expect(find.byTooltip('対応種目を報告'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('exercise report failure stays open and permits retry', (
    t,
  ) async {
    repo.failReports = true;
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showStoreExerciseReport(context, storeA.id, {'bench_press'}),
              child: const Text('報告'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('報告'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('exerciseReportKind')));
    await t.pumpAndSettle();
    await t.tap(find.text('その他').last);
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('exerciseReportComment')), '   ');
    await t.pump();
    expect(
      t
          .widget<FilledButton>(find.byKey(const Key('sendExerciseReport')))
          .onPressed,
      isNull,
    );
    await t.enterText(
      find.byKey(const Key('exerciseReportComment')),
      '確認してください',
    );
    await t.pump();
    await t.tap(find.byKey(const Key('sendExerciseReport')));
    await t.pumpAndSettle();
    expect(find.text('報告を送信できませんでした。再度お試しください。'), findsOneWidget);
    expect(t.takeException(), isNull);
    repo.failReports = false;
    await t.tap(find.byKey(const Key('sendExerciseReport')));
    await t.pumpAndSettle();
    expect(repo.exerciseReports.length, 1);
  });

  for (final kind in ['missing_exercise', 'incorrect_exercise', 'other']) {
    testWidgets(
      'exercise report sends $kind without changing shared equipment',
      (t) async {
        await t.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showStoreExerciseReport(context, storeA.id, {
                    'bench_press',
                  }),
                  child: const Text('報告'),
                ),
              ),
            ),
          ),
        );
        await t.tap(find.text('報告'));
        await t.pumpAndSettle();
        if (kind != 'missing_exercise') {
          await t.tap(find.byKey(const Key('exerciseReportKind')));
          await t.pumpAndSettle();
          await t.tap(find.text(kind == 'other' ? 'その他' : '表示されているができない').last);
          await t.pumpAndSettle();
        }
        expect(
          t
              .widget<FilledButton>(find.byKey(const Key('sendExerciseReport')))
              .onPressed,
          isNull,
        );
        if (kind != 'other') {
          expect(find.textContaining('対象種目（必須）'), findsOneWidget);
          await t.tap(find.byKey(const Key('exerciseReportTarget')));
          await t.pumpAndSettle();
          expect(find.byType(BottomSheet), findsOneWidget);
          if (kind == 'incorrect_exercise') {
            expect(
              find
                  .byType(ListTile)
                  .evaluate()
                  .where(
                    (e) => (e.widget as ListTile).key.toString().contains(
                      'choosePlaceExercise',
                    ),
                  )
                  .length,
              1,
            );
            expect(
              find.byKey(const Key('choosePlaceExercisebarbell_squat')),
              findsNothing,
            );
          }
          await t.enterText(
            find.byKey(const Key('placeExerciseSearch')),
            'ベンチプレス',
          );
          await t.pumpAndSettle();
          await t.scrollUntilVisible(
            find.byKey(const Key('choosePlaceExercisebench_press')),
            160,
            scrollable: find.descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            ),
          );
          await t.pumpAndSettle();
          await t.tap(find.byKey(const Key('choosePlaceExercisebench_press')));
          await t.pumpAndSettle();
          await t.tap(find.byKey(const Key('confirmPlaceExercises')));
          await t.pumpAndSettle();
        }
        await t.enterText(
          find.byKey(const Key('exerciseReportComment')),
          '確認お願いします',
        );
        await t.pump();
        expect(
          t
              .widget<FilledButton>(find.byKey(const Key('sendExerciseReport')))
              .onPressed,
          isNotNull,
        );
        await t.tap(find.byKey(const Key('sendExerciseReport')));
        await t.pumpAndSettle();
        expect(
          repo.exerciseReports.single,
          contains('/$kind/${kind == 'other' ? 'null' : 'bench_press'}/'),
        );
        expect(find.text('報告を受け付けました。確認後に対応種目情報を更新します。'), findsOneWidget);
        expect(repo.reports, isEmpty);
        expect((await repo.equipment(storeA.id)).length, 3);
      },
    );
  }
}
