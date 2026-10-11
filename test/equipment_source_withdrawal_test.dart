import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setkeep/gym/gym_repository.dart';
import 'package:setkeep/gym/gym_equipment_cache.dart';
import 'package:setkeep/gym/training_equipment_confirmation.dart';

import 'training_equipment_confirmation_test.dart'
    show FakeTrainingEquipment, workout;

void main() {
  test(
    'withdrawn RPC/cache data cannot provide inventory or exercise evidence',
    () async {
      SharedPreferences.setMockInitialValues({});
      final j = <String, dynamic>{
        'store': {
          'id': 'withdrawn',
          'chain_id': 'anytime-fitness',
          'chain_name': 'Anytime',
          'name': 'QA',
        },
        'equipment': [
          {
            'source_kind': 'official',
            'equipment': {
              'id': 'old',
              'name': 'Imported old name',
              'category': '筋トレ',
            },
          },
          {
            'source_kind': 'confirmed_report',
            'equipment': {
              'id': 'community:new',
              'name': 'New on-site name',
              'category': '筋トレ',
            },
          },
        ],
        'evidence': [
          {
            'exercise_id': 'old-exercise',
            'equipment_ids': ['old'],
            'equipment_names': ['Imported old name'],
          },
          {
            'exercise_id': 'new-exercise',
            'equipment_ids': ['community:new'],
            'equipment_names': ['New on-site name'],
          },
        ],
      };
      final detail = GymStoreDetail.fromJson(j);
      expect(detail.equipment.map((e) => e.id), ['community:new']);
      expect(detail.exerciseIds, {'new-exercise'});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'gym_equipment_v1_withdrawn',
        jsonEncode({
          'detail': j,
          'fetchedAt': DateTime.now().toIso8601String(),
        }),
      );
      expect(await GymEquipmentCache.read('withdrawn'), isNull);
      await GymEquipmentCache.write(detail);
      expect(
        (await GymEquipmentCache.read('withdrawn'))!
            .detail
            .equipment
            .single
            .sourceKind,
        'confirmed_report',
      );
    },
  );
  testWidgets(
    'only unique machine option is preselected; ambiguous and dumbbell options are not',
    (t) async {
      final w = EquipmentWorkout(
        key: 'qa',
        storeId: 'qa',
        completed: true,
        exercises: {
          'smith_bench_press': 'Smith',
          'dumbbell_curl': 'Dumbbell',
          'cable_curl': 'Cable',
        },
      );
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrainingEquipmentSheet(
              workout: w,
              prompts: [
                {
                  'exercise_id': 'smith_bench_press',
                  'options': [
                    {
                      'equipment_id': 'smith',
                      'label': 'スミスマシン',
                      'known': false,
                    },
                  ],
                },
                {
                  'exercise_id': 'dumbbell_curl',
                  'options': [
                    {
                      'equipment_id': 'dumbbell',
                      'label': 'ダンベル',
                      'known': false,
                    },
                  ],
                },
                {
                  'exercise_id': 'cable_curl',
                  'options': [
                    {
                      'equipment_id': 'cable1',
                      'label': 'ケーブルA',
                      'known': false,
                    },
                    {
                      'equipment_id': 'cable2',
                      'label': 'ケーブルB',
                      'known': false,
                    },
                  ],
                },
              ],
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        t
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'スミスマシン'))
            .selected,
        true,
      );
      expect(
        t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'ダンベル')).selected,
        false,
      );
      expect(
        t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'ケーブルA')).selected,
        false,
      );
      expect(
        t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'ケーブルB')).selected,
        false,
      );
      await t.ensureVisible(find.text('ケーブルA'));
      await t.pumpAndSettle();
      await t.tap(find.text('ケーブルA'));
      await t.pump();
      await t.ensureVisible(find.text('ケーブルB'));
      await t.pumpAndSettle();
      await t.tap(find.text('ケーブルB'));
      await t.pump();
      expect(
        t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'ケーブルA')).selected,
        true,
      );
      expect(
        t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'ケーブルB')).selected,
        true,
      );
    },
  );
  testWidgets(
    'simultaneous completion creates one prompt and dismissal sends nothing',
    (t) async {
      final original = TrainingEquipmentServices.repository;
      final repo = FakeTrainingEquipment();
      TrainingEquipmentServices.repository = repo;
      addTearDown(() => TrainingEquipmentServices.repository = original);
      SharedPreferences.setMockInitialValues({});
      late BuildContext context;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const Scaffold();
            },
          ),
        ),
      );
      final a = confirmWorkoutEquipment(context, workout);
      final b = confirmWorkoutEquipment(context, workout);
      await t.pumpAndSettle();
      expect(repo.optionReads, 1);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      await a;
      await b;
      expect(repo.sent, isEmpty);
      expect(
        (await SharedPreferences.getInstance()).getString(
          TrainingEquipmentJournal.storageKey,
        ),
        isNull,
      );
    },
  );
}
