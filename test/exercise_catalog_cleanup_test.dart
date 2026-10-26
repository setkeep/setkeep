import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/exercise_form_catalog.dart';
import 'package:setkeep/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

RecordedSet oldSet(String? id, String name, {double weight = 30}) =>
    RecordedSet(
      exerciseId: id,
      exerciseName: name,
      bodyPart: '背中',
      equipment: 'ケーブル',
      weight: weight,
      reps: 10,
      completed: true,
    );
WorkoutRecord workout(List<RecordedSet> sets, [int day = 1]) => WorkoutRecord(
  date: DateTime(2026, 9, day, 12, 34),
  sets: sets,
  durationSeconds: 270,
  gymName: 'テストジム',
  note: '元のメモ',
);
Widget picker({
  Set<String> existing = const {},
  List<SavedWorkoutTemplate> menus = const [],
}) => MaterialApp(
  home: Scaffold(
    body: ExercisePickerSheet(existingIdentities: existing, menus: menus),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CustomExercisePreference.exercises = [];
  });

  test('renamed equipment variants keep distinct identities and old search aliases', () {
    for (final ids in [
      ['seated_row', 'plate_loaded_seated_row', 'cable_row'],
      ['chest_press', 'plate_loaded_chest_press'],
      ['selectorized_incline_chest_press', 'plate_loaded_incline_chest_press'],
      [
        'shoulder_press',
        'plate_loaded_shoulder_press',
        'dumbbell_shoulder_press',
      ],
      ['preacher_curl', 'machine_preacher_curl'],
      ['hip_thrust', 'machine_hip_thrust'],
    ]) {
      final entries = ids.map((id) => ExerciseFormCatalog.byId[id]!).toList();
      expect(entries.map((e) => e.exerciseName).toSet(), hasLength(ids.length));
      final sets = ids.map((id) => oldSet(id, '旧名称')).toList();
      expect(workout(sets).exerciseGroups, hasLength(ids.length));
      expect(countPersonalBests([workout(sets)], DateTime(2026)), ids.length);
    }
    for (final query in [
      'シーテッドロー',
      'シーテッドロウ',
      'ケーブルロー',
      'シーテッドケーブルロー',
      'Cable Row',
    ]) {
      final results = exerciseTemplates
          .where((e) => e.matchesQuery(query))
          .toList();
      expect(results.any((e) => e.exerciseId == 'cable_row'), isTrue);
      expect(results.map((e) => e.identity).toSet(), hasLength(results.length));
    }
    expect(ExerciseFormCatalog.byId['lat_pulldown']!.equipmentLabel, 'ケーブル');
    for (final id in [
      'dy_row',
      'low_row',
      'high_row',
      'linear_row',
      'incline_press_machine',
      'decline_press_machine',
      'decline_fly_machine',
    ]) {
      expect(ExerciseFormCatalog.byId[id]!.equipmentLabel, 'プレートロード');
    }
  });

  test('only explicit standard IDs resolve display names; saved names remain intact', () {
    expect(
      exerciseDisplayName('シーテッドロー', exerciseId: 'seated_row'),
      'シーテッドローマシン',
    );
    expect(
      exerciseDisplayName('ケーブルプルオーバー', exerciseId: 'cable_pullover'),
      'ストレートアームプルダウン',
    );
    for (final id in [null, 'unknown', 'custom:shoulder_press']) {
      expect(exerciseDisplayName('ショルダープレス', exerciseId: id), 'ショルダープレス');
      expect(
        exerciseDisplayName('ショルダープレス', exerciseId: id, languageCode: 'en'),
        'ショルダープレス',
      );
    }
    final record = workout([oldSet('seated_row', 'シーテッドロー')]);
    expect(record.exerciseNames, ['シーテッドローマシン']);
    expect(record.sets.single.toJson()['exerciseName'], 'シーテッドロー');
    for (final query in ['シーテッドロー', 'シーテッドローマシン', 'Seated Row']) {
      expect(workoutMatchesQuery(record, query), isTrue);
    }
  });

  test(
    'merged IDs share history and PR without discarding sets or altering JSON',
    () {
      for (final pair in [
        ['cable_pullover', 'straight_arm_pulldown'],
        ['triceps_pushdown', 'rope_pushdown'],
        ['weighted_back_extension', 'back_extension'],
      ]) {
        final original = workout([
          oldSet(pair[0], '保存名A'),
          oldSet(pair[1], '保存名B'),
          oldSet(pair[0], '保存名A'),
        ]);
        final json = original.toJson();
        final restored = WorkoutRecord.fromJson(jsonDecode(jsonEncode(json)));
        expect(restored.toJson(), json);
        expect(restored.exerciseGroups, hasLength(1));
        expect(restored.exerciseGroups.values.single, hasLength(3));
        expect(restored.volume, 900);
        expect(
          latestSetsForExercise([restored], 'ignored', exerciseId: pair[1]),
          hasLength(3),
        );
        expect(
          countPersonalBests([
            workout([oldSet(pair[0], '旧名', weight: 40)]),
            workout([oldSet(pair[1], '新名', weight: 30)], 2),
          ], DateTime(2026, 9, 2)),
          0,
        );
        final backup = SetkeepBackup(workouts: [restored]);
        final copy = SetkeepBackup.fromJson(
          jsonDecode(jsonEncode(backup.toJson())),
        );
        expect(copy.workouts.single.toJson(), json);
        expect(
          ExerciseFormCatalog.resolve(pair[0], 'ignored')!.exerciseId,
          pair[0],
        );
        expect(
          ExerciseFormCatalog.canonicalDefinition(pair[0])!.exerciseId,
          pair[1],
        );
        expect(
          exerciseTemplates.where((e) => e.exerciseId == pair[0]),
          isEmpty,
        );
      }
    },
  );

  test(
    'generic old IDs remain restorable and never join specific variants',
    () {
      for (final pair in [
        ['leg_curl', 'seated_leg_curl'],
        ['calf_raise', 'standing_calf_raise'],
      ]) {
        expect(
          exerciseTemplates.where((e) => e.exerciseId == pair[0]),
          isEmpty,
        );
        expect(ExerciseFormCatalog.byId[pair[0]], isNotNull);
        final record = workout([
          oldSet(pair[0], '旧汎用名'),
          oldSet(pair[1], '具体種目'),
        ]);
        final copy = WorkoutRecord.fromJson(record.toJson());
        expect(copy.exerciseGroups, hasLength(2));
        expect(copy.toJson(), record.toJson());
        expect(
          latestSetsForExercise([copy], 'ignored', exerciseId: pair[1]),
          hasLength(1),
        );
      }
    },
  );

  test(
    'legacy merged favorites resolve persistently without touching custom keys',
    () async {
      SharedPreferences.setMockInitialValues({
        'favorite_exercise_identities': [
          'id:cable_pullover',
          'id:straight_arm_pulldown',
          'id:custom:ケーブルプルオーバー',
        ],
      });
      final favorites = await ExerciseFavoritePreference.load();
      expect(favorites, {'id:straight_arm_pulldown', 'id:custom:ケーブルプルオーバー'});
      await ExerciseFavoritePreference.save(favorites);
      expect(await ExerciseFavoritePreference.load(), favorites);
    },
  );

  testWidgets(
    'editing merged legacy records preserves original IDs and values',
    (t) async {
      final record = workout([
        oldSet('cable_pullover', 'ケーブルプルオーバー', weight: 25),
        oldSet('straight_arm_pulldown', 'ストレートアームプルダウン', weight: 35),
      ]);
      WorkoutRecord? saved;
      await t.pumpWidget(
        MaterialApp(
          home: WorkoutPage(
            initialWorkout: record,
            isEditing: true,
            onSave: (value) async {
              saved = value;
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('completeWorkoutButton')));
      await t.pumpAndSettle();
      expect(saved, isNotNull);
      expect(
        saved!.sets.map((e) => e.toJson()).toList(),
        record.sets.map((e) => e.toJson()).toList(),
      );
      expect(saved!.date, record.date);
      expect(saved!.gymName, record.gymName);
      expect(saved!.note, record.note);
      expect(saved!.exerciseGroups, hasLength(1));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    },
  );

  testWidgets(
    'merged search candidate appears once and recognizes an already added old ID',
    (t) async {
      await t.pumpWidget(picker(existing: {'id:cable_pullover'}));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const Key('exerciseSearchField')),
        'ケーブルプルオーバー',
      );
      await t.pumpAndSettle();
      final row = find.byKey(const Key('selectExercisestraight_arm_pulldown'));
      expect(row, findsOneWidget);
      expect(
        find.byKey(const Key('selectExercisecable_pullover')),
        findsNothing,
      );
      expect(t.widget<ListTile>(row).onTap, isNull);
      expect(find.text('追加済み'), findsOneWidget);
      expect(
        t
            .widget<IconButton>(
              find.byKey(const Key('favoriteExerciseid:straight_arm_pulldown')),
            )
            .onPressed,
        isNotNull,
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'old IDs display current names in details, share and editable workout at narrow width',
    (t) async {
      t.view.physicalSize = const Size(320, 700);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final record = workout([oldSet('overhead_triceps_extension', '旧名称')]);
      final name =
          ExerciseFormCatalog.byId['overhead_triceps_extension']!.exerciseName;
      await t.pumpWidget(
        MaterialApp(
          home: WorkoutDetailPage(
            workout: record,
            selectedGym: null,
            onWorkoutCompleted: (_) async {},
            onWorkoutUpdated: (_, _) async {},
            onWorkoutDeleted: (_) async => false,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text(name), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(MaterialApp(home: WorkoutSharePage(workout: record)));
      await t.pumpAndSettle();
      expect(find.text(name), findsWidgets);
      expect(t.takeException(), isNull);
      await t.pumpWidget(
        MaterialApp(home: WorkoutPage(initialWorkout: record, isEditing: true)),
      );
      await t.pumpAndSettle();
      expect(find.text(name), findsOneWidget);
      expect(
        t
            .widget<ExerciseInputCard>(find.byType(ExerciseInputCard))
            .exercise
            .sets
            .single
            .weight,
        30,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    },
  );
}
