import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/exercise_form_catalog.dart';
import 'package:setkeep/exercise_media.dart';
import 'package:setkeep/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

const oldId = 'weighted_back_extension';
const normalId = 'back_extension';
const machineId = 'back_extension_machine';
const oldName = 'バックエクステンション（荷重）';

RecordedSet setFor(String? id, double weight) => RecordedSet(
  exerciseId: id,
  exerciseName: id == normalId ? 'バックエクステンション' : oldName,
  bodyPart: '背中',
  equipment: id == machineId ? 'マシン' : 'ローマンチェア',
  weight: weight,
  reps: 12,
  completed: true,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CustomExercisePreference.exercises = [];
  });

  test(
    'back extension exposes one roman-chair choice and keeps machine separate',
    () {
      expect(exerciseTemplates.where((e) => e.exerciseId == oldId), isEmpty);
      final normal = exerciseTemplates.singleWhere(
        (e) => e.exerciseId == normalId,
      );
      expect(
        exerciseTemplates.where((e) => e.exerciseId == machineId),
        hasLength(1),
      );
      for (final query in [oldName, 'Weighted Back Extension', '荷重']) {
        expect(normal.matchesQuery(query), isTrue);
      }
      expect(exerciseDisplayName(oldName, exerciseId: oldId), normal.name);
      expect(
        exerciseDisplayName(oldName, exerciseId: oldId, languageCode: 'en'),
        'Back Extension',
      );
      expect(ExerciseFormCatalog.canonicalId(machineId), machineId);
      expect(ExerciseFormCatalog.resolve(oldId, oldName)!.exerciseId, oldId);
      expect(ExerciseFormCatalog.forName(oldName)!.exerciseId, oldId);
      expect(ExerciseMediaCatalog.forExerciseId(normalId)!.provider, 'vital_animations');
    },
  );

  test('back extension keeps legacy ID names weights and backup sets without double counting', () {
    final sets = [
      setFor(oldId, 10),
      setFor(normalId, 0),
      setFor(oldId, 20),
      setFor(machineId, 30),
    ];
    final record = WorkoutRecord(date: DateTime(2026, 10, 26), sets: sets);
    final menu = SavedWorkoutTemplate(name: '背中', sets: sets);
    final original = SetkeepBackup(
      workouts: [record],
      workoutTemplates: [menu],
    );
    final copy = SetkeepBackup.fromJson(
      jsonDecode(jsonEncode(original.toJson())),
    );
    expect(copy.workouts.single.toJson(), record.toJson());
    expect(copy.workoutTemplates.single.toJson(), menu.toJson());
    expect(copy.workouts.single.exerciseGroups, hasLength(2));
    expect(copy.workoutTemplates.single.exerciseGroups, hasLength(2));
    expect(copy.workouts.single.exerciseGroups['id:$normalId'], hasLength(3));
    expect(copy.workouts.single.volume, 720);
    expect(countPersonalBests([record], DateTime(2026, 10, 26)), 2);
    expect(
      latestSetsForExercise(
        [record],
        'ignored',
        exerciseId: normalId,
      ).map((e) => e.weight),
      [10, 0, 20],
    );
    expect(
      latestSetsForExercise(
        [record],
        'ignored',
        exerciseId: machineId,
      ).single.weight,
      30,
    );
    for (final id in [oldId, normalId, null]) {
      for (final load in [0.0, 5.0, 20.0]) {
        final set = setFor(id, load);
        expect(set.hasRequiredValues, isTrue);
        expect(RecordedSet.fromJson(set.toJson()).toJson(), set.toJson());
      }
    }
    expect(exerciseIdentity(null, oldName), 'legacy:$oldName');
    expect(exerciseIdentity('custom:$oldId', oldName), 'id:custom:$oldId');
  });

  test('back extension favorite and template survive durable reload and canonical toggles', () async {
    SharedPreferences.setMockInitialValues({
      'favorite_exercise_identities': [
        'id:$oldId',
        'id:$normalId',
        'id:$machineId',
        'id:custom:$oldId',
      ],
    });
    final expected = {'id:$normalId', 'id:$machineId', 'id:custom:$oldId'};
    expect(await ExerciseFavoritePreference.load(), expected);
    await ExerciseFavoritePreference.save(
      await ExerciseFavoritePreference.load(),
    );
    expect(await ExerciseFavoritePreference.load(), expected);
    await ExerciseFavoritePreference.setFavorite('id:$oldId', false);
    expect(await ExerciseFavoritePreference.load(), {
      'id:$machineId',
      'id:custom:$oldId',
    });
    await ExerciseFavoritePreference.setFavorite('id:$oldId', true);
    expect(await ExerciseFavoritePreference.load(), expected);
    final menu = SavedWorkoutTemplate(
      name: '旧メニュー',
      sets: [setFor(oldId, 15), setFor(normalId, 0)],
    );
    await WorkoutTemplatePreference.save([menu]);
    final restored = (await WorkoutTemplatePreference.load()).single;
    expect(restored.toJson(), menu.toJson());
    expect(restored.toWorkoutRecord().exerciseGroups, hasLength(1));
    expect(restored.toWorkoutRecord().sets, hasLength(2));
  });

  testWidgets(
    'back extension picker has no duplicate and recognizes an added old ID',
    (t) async {
      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ExercisePickerSheet(
              existingIdentities: {'id:weighted_back_extension'},
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const Key('exerciseSearchField')),
        'バックエクステンション',
      );
      await t.pumpAndSettle();
      final normal = find.byKey(const Key('selectExerciseback_extension'));
      final machine = find.byKey(
        const Key('selectExerciseback_extension_machine'),
      );
      expect(normal, findsOneWidget);
      expect(machine, findsOneWidget);
      expect(
        find.byKey(const Key('selectExerciseweighted_back_extension')),
        findsNothing,
      );
      expect(t.widget<ListTile>(normal).onTap, isNull);
      expect(t.widget<ListTile>(machine).onTap, isNotNull);
      expect(find.text('追加済み'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'back extension old favorite reappears in a newly opened picker',
    (t) async {
      SharedPreferences.setMockInitialValues({
        'favorite_exercise_identities': ['id:$oldId'],
      });
      for (var opening = 0; opening < 2; opening++) {
        await t.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: ExercisePickerSheet(existingIdentities: {})),
          ),
        );
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const Key('exerciseSearchField')),
          oldName,
        );
        await t.pumpAndSettle();
        expect(
          find.byKey(const Key('selectExerciseback_extension')),
          findsOneWidget,
        );
        expect(await ExerciseFavoritePreference.load(), {'id:$normalId'});
        expect(
          find.descendant(
            of: find.byKey(const Key('favoriteExerciseid:back_extension')),
            matching: find.byIcon(Icons.star_rounded),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('selectExerciseweighted_back_extension')),
          findsNothing,
        );
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
        await t.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'back extension editing preserves old and normal IDs and exact stored sets',
    (t) async {
      final record = WorkoutRecord(
        date: DateTime(2026, 10, 26),
        sets: [setFor(oldId, 15), setFor(normalId, 0)],
      );
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
      expect(saved!.exerciseGroups, hasLength(1));
      expect(saved!.volume, 180);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    },
  );
}
