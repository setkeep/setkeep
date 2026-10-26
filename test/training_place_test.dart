import 'support/signed_in_auth.dart';

import 'dart:convert';

import 'support/legal_consent_fixture.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setkeep/main.dart';
import 'package:setkeep/gym/gym_pages.dart';
import 'package:setkeep/gym/gym_repository.dart';
import 'package:setkeep/gym/training_place_preference.dart';

import 'gym_integration_test.dart'
    show FakeGyms, preopeningStore, storeA, storeB;

class MissingDefaultStoreRepository extends FakeGyms {
  @override
  Future<GymStore?> storeById(String id) async => null;
}

void main() {
  late FakeGyms repo;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = FakeGyms()..saved = [storeA, storeB];
    GymServices.override = repo;
    WorkoutUiPreference.workoutTimerEnabled = false;
    WorkoutUiPreference.workoutDurationEnabled = false;
    RestTimerPreference.enabled = false;
  });
  tearDown(() async {
    GymServices.override = null;
    await WorkoutUiPreference.load();
    await RestTimerPreference.load();
  });

  test('legacy names are retained without guessing a store identity', () async {
    SharedPreferences.setMockInitialValues({
      'selected_gym': storeA.displayName,
      'custom_gyms': jsonEncode(['体育館']),
    });
    final place = await TrainingPlacePreference.load();
    expect(place.name, '自宅');
    expect(place.storeId, isNull);
    final p = await SharedPreferences.getInstance();
    expect(p.getString('selected_gym'), storeA.displayName);
    expect(p.getString('custom_gyms'), jsonEncode(['体育館']));
    await TrainingPlacePreference.save(const TrainingPlace.store(storeA));
    expect((await TrainingPlacePreference.load()).storeId, 'a');
    expect((await TrainingPlacePreference.reconcile([storeB])).name, '自宅');
    expect((await TrainingPlacePreference.load()).storeId, isNull);
  });

  test(
    'new workout validates registered default and repairs removed stores',
    () async {
      await TrainingPlacePreference.save(const TrainingPlace.store(storeA));
      expect(
        (await TrainingPlacePreference.forNewWorkout()).storeId,
        storeA.id,
      );
      repo.saved = [storeB];
      expect((await TrainingPlacePreference.forNewWorkout()).isHome, isTrue);
      expect((await TrainingPlacePreference.load()).isHome, isTrue);
    },
  );
  test('preopening default cannot become a new workout location', () async {
    repo.saved = [preopeningStore];
    await TrainingPlacePreference.save(
      const TrainingPlace.store(preopeningStore),
    );
    expect((await TrainingPlacePreference.forNewWorkout()).isHome, isTrue);
    expect((await TrainingPlacePreference.load()).storeId, preopeningStore.id);
  });

  test(
    'manual default follows its ID through rename but not replacement',
    () async {
      await CustomGymPreference.load();
      await CustomGymPreference.add('体育館');
      final id = CustomGymPreference.idFor('体育館');
      await TrainingPlacePreference.save(
        TrainingPlace.manual('体育館', storedCustomPlaceId: id),
      );
      await CustomGymPreference.update('体育館', '市民体育館');
      final renamed = await TrainingPlacePreference.forNewWorkout();
      expect(renamed.name, '市民体育館');
      expect(renamed.customPlaceId, id);
      expect(renamed.storeId, isNull);
      await CustomGymPreference.remove('市民体育館');
      await CustomGymPreference.add('市民体育館');
      expect((await TrainingPlacePreference.forNewWorkout()).isHome, isTrue);
      expect((await TrainingPlacePreference.load()).isHome, isTrue);
    },
  );

  testWidgets(
    'new workout ignores stale draft while resume retains its place',
    (t) async {
      await TrainingPlacePreference.save(const TrainingPlace.store(storeA));
      final p = await SharedPreferences.getInstance();
      await p.setString(
        activeWorkoutDraftStorageKey,
        jsonEncode({
          'gymName': storeB.displayName,
          'gymStoreId': storeB.id,
          'exercises': [],
        }),
      );
      await t.pumpWidget(
        const MaterialApp(
          home: WorkoutPage(useDefaultPlace: true, resumeDraft: false),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text(storeA.displayName), findsOneWidget);
      await t.tap(find.byKey(const Key('workoutGymButton')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('selectRegisteredPlaceb')));
      await t.pumpAndSettle();
      expect((await TrainingPlacePreference.load()).storeId, storeA.id);
      expect(
        jsonDecode(p.getString(activeWorkoutDraftStorageKey)!)['gymStoreId'],
        storeB.id,
      );
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(
        const MaterialApp(home: WorkoutPage(useDefaultPlace: true)),
      );
      await t.pumpAndSettle();
      expect(find.text(storeB.displayName), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(
        const MaterialApp(
          home: WorkoutPage(useDefaultPlace: true, resumeDraft: false),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text(storeA.displayName), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );

  test(
    'missing database store falls back even with a cached registration',
    () async {
      GymServices.override = MissingDefaultStoreRepository()..saved = [storeA];
      await TrainingPlacePreference.save(const TrainingPlace.store(storeA));
      expect((await TrainingPlacePreference.forNewWorkout()).isHome, isTrue);
      expect((await TrainingPlacePreference.load()).isHome, isTrue);
    },
  );

  test('temporary network failure does not erase the default store', () async {
    await TrainingPlacePreference.save(const TrainingPlace.store(storeA));
    repo.failRegistered = true;
    expect((await TrainingPlacePreference.forNewWorkout()).storeId, storeA.id);
    expect((await TrainingPlacePreference.load()).storeId, storeA.id);
  });

  testWidgets(
    'history edit and picker retain recorded place instead of default',
    (t) async {
      await TrainingPlacePreference.save(const TrainingPlace.store(storeA));
      final original = WorkoutRecord(
        date: DateTime(2026, 9, 24),
        sets: const [],
        gymName: storeB.displayName,
        gymStoreId: storeB.id,
      );
      await t.pumpWidget(
        MaterialApp(
          home: WorkoutPage(
            isEditing: true,
            initialWorkout: original,
            useDefaultPlace: true,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text(storeB.displayName), findsOneWidget);
      await t.tap(find.byKey(const Key('workoutGymButton')));
      await t.pumpAndSettle();
      expect(
        t
            .widget<ListTile>(find.byKey(const Key('selectRegisteredPlaceb')))
            .trailing,
        isNotNull,
      );
      expect(
        t
            .widget<ListTile>(find.byKey(const Key('selectRegisteredPlacea')))
            .trailing,
        isNull,
      );
      expect((await TrainingPlacePreference.load()).storeId, storeA.id);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('one default place persists and removing it preserves history', (
    t,
  ) async {
    final p = await SharedPreferences.getInstance();
    final original = WorkoutRecord(
      date: DateTime(2026, 9, 24),
      sets: const [
        RecordedSet(
          exerciseName: 'ベンチプレス',
          bodyPart: '胸',
          weight: 50,
          reps: 8,
          completed: true,
        ),
      ],
      gymName: storeA.displayName,
      gymStoreId: storeA.id,
    );
    final history = jsonEncode([original.toJson()]);
    await p.setString('workout_history', history);
    await t.pumpWidget(const MaterialApp(home: RegisteredGymsPage()));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('trainingPlaceHome')), findsOneWidget);
    expect(find.byKey(const Key('removeRegisteredGymhome')), findsNothing);
    expect(find.text(storeA.displayName), findsOneWidget);
    await t.tap(find.byKey(const Key('defaultTrainingPlacea')));
    await t.pumpAndSettle();
    expect((await TrainingPlacePreference.load()).storeId, 'a');
    final preferred = find.byKey(const Key('preferredTrainingPlaceCard'));
    expect(find.byKey(const Key('defaultTrainingPlacea')), findsNothing);
    expect(
      find.descendant(
        of: preferred,
        matching: find.byKey(const Key('preferredTrainingPlaceBadge')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: preferred, matching: find.text(storeA.chainName)),
      findsOneWidget,
    );
    expect(
      t
          .widget<TextButton>(find.byKey(const Key('defaultTrainingPlaceb')))
          .onPressed,
      isNotNull,
    );
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(const MaterialApp(home: RegisteredGymsPage()));
    await t.pumpAndSettle();
    expect(
      find.descendant(of: preferred, matching: find.text(storeA.chainName)),
      findsOneWidget,
    );
    final removeB = find.byKey(const Key('removeRegisteredGymb'));
    await t.ensureVisible(removeB);
    await t.pumpAndSettle();
    await t.tap(removeB);
    await t.pumpAndSettle();
    await t.tap(find.text('利用場所から削除'));
    await t.pumpAndSettle();
    expect((await TrainingPlacePreference.load()).storeId, 'a');
    final removeA = find.byKey(const Key('removeRegisteredGyma'));
    await t.ensureVisible(removeA);
    await t.pumpAndSettle();
    await t.tap(removeA);
    await t.pumpAndSettle();
    await t.tap(find.text('利用場所から削除'));
    await t.pumpAndSettle();
    expect((await TrainingPlacePreference.load()).name, '自宅');
    expect(repo.saved, isEmpty);
    expect(p.getString('workout_history'), history);
    expect(WorkoutRecord.fromJson(jsonDecode(history).single).gymStoreId, 'a');
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('default store, per-workout changes and home on $platform', (
      t,
    ) async {
      t.view.physicalSize = const Size(320, 568);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await TrainingPlacePreference.save(const TrainingPlace.store(storeA));
      final app = MaterialApp(
        theme: ThemeData(platform: platform),
        home: const WorkoutPage(useDefaultPlace: true),
      );
      await t.pumpWidget(app);
      await t.pumpAndSettle();
      expect(find.text(storeA.displayName), findsOneWidget);
      expect(
        find.byKey(const Key('workoutGymEquipmentButton')),
        findsOneWidget,
      );
      await t.tap(find.byKey(const Key('workoutGymButton')));
      await t.pumpAndSettle();
      for (final name in ['エニタイムフィットネス', 'ゴールドジム', 'FIT PLACE24']) {
        expect(find.text(name), findsNothing);
      }
      expect(find.byKey(const Key('selectRegisteredPlacea')), findsOneWidget);
      await t.ensureVisible(find.byKey(const Key('selectRegisteredPlaceb')));
      await t.tap(find.byKey(const Key('selectRegisteredPlaceb')));
      await t.pumpAndSettle();
      final p = await SharedPreferences.getInstance();
      var draft = jsonDecode(p.getString(activeWorkoutDraftStorageKey)!);
      expect(draft['gymStoreId'], 'b');
      expect((await TrainingPlacePreference.load()).storeId, 'a');
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(app);
      await t.pumpAndSettle();
      expect(find.text(storeB.displayName), findsOneWidget);
      await t.tap(find.byKey(const Key('workoutGymButton')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('selectTrainingPlaceHome')));
      await t.pumpAndSettle();
      draft = jsonDecode(p.getString(activeWorkoutDraftStorageKey)!);
      expect(draft['gymName'], '自宅');
      expect(draft['gymStoreId'], isNull);
      expect(find.byKey(const Key('workoutGymEquipmentButton')), findsNothing);
      expect((await TrainingPlacePreference.load()).storeId, 'a');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets('profile default becomes the new workout initial store', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({
      'onboarding_completed': true,
      'legal_consent': acceptedLegalConsentJson,
    });
    t.view.physicalSize = const Size(400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.person_outline_rounded));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('locationSettingsButton')), findsNothing);
    await t.ensureVisible(find.byKey(const Key('registeredGymsButton')));
    await t.tap(find.byKey(const Key('registeredGymsButton')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('defaultTrainingPlacea')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('trainingPlaceHome')));
    await t.pumpAndSettle();
    expect((await TrainingPlacePreference.load()).storeId, isNull);
    await t.tap(find.byKey(const Key('defaultTrainingPlacea')));
    await t.pumpAndSettle();
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.home_outlined));
    await t.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      activeWorkoutDraftStorageKey,
      jsonEncode({'gymName': '自宅', 'exercises': []}),
    );
    await t.ensureVisible(find.byKey(const Key('startWorkoutButton')));
    await t.tap(find.byKey(const Key('startWorkoutButton')));
    await t.pumpAndSettle();
    expect(find.text(storeA.displayName), findsOneWidget);
    expect(find.byKey(const Key('workoutGymEquipmentButton')), findsOneWidget);
    await t.ensureVisible(find.byKey(const Key('addExerciseButton')));
    await t.tap(find.byKey(const Key('addExerciseButton')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('storeExerciseFilter')), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  for (final hasLegacyName in [true, false]) {
    testWidgets('legacy draft does not guess a store ID name=$hasLegacyName', (
      t,
    ) async {
      await TrainingPlacePreference.save(const TrainingPlace.store(storeA));
      final p = await SharedPreferences.getInstance();
      await p.setString(
        activeWorkoutDraftStorageKey,
        jsonEncode({
          if (hasLegacyName) 'gymName': '昔のジム',
          'exercises': [
            {
              'name': 'ベンチプレス',
              'bodyPart': '胸',
              'equipment': 'フリーウェイト',
              'sets': [
                {'weight': 50, 'reps': 8, 'completed': false},
              ],
            },
          ],
        }),
      );
      await t.pumpWidget(
        const MaterialApp(home: WorkoutPage(useDefaultPlace: true)),
      );
      await t.pumpAndSettle();
      expect(
        find.text(hasLegacyName ? '昔のジム' : storeA.displayName),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('workoutGymEquipmentButton')),
        hasLegacyName ? findsNothing : findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets('home remains usable when registered stores fail to load', (
    t,
  ) async {
    repo.failRegistered = true;
    await t.pumpWidget(
      const MaterialApp(home: Scaffold(body: TrainingPlacePicker())),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const Key('selectTrainingPlaceHome')), findsOneWidget);
    expect(find.text('再読み込み'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
