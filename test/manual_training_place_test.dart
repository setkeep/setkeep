import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setkeep/main.dart';
import 'package:setkeep/gym/gym_pages.dart';
import 'package:setkeep/gym/gym_repository.dart';
import 'package:setkeep/gym/training_place_preference.dart';

import 'gym_integration_test.dart' show FakeGyms, storeA;

const kanekinStore = GymStore(
  id: 'kanekin-fitness-gym:matsudo',
  chainName: 'KANEKIN FITNESS GYM',
  name: '松戸店',
  equipmentStatus: 'published',
);

class KanekinRepository extends FakeGyms {
  @override
  Future<List<GymStore>> search(String query, {int offset = 0}) async {
    if (this.fail) throw StateError('offline');
    return [kanekinStore];
  }
}

void main() {
  late FakeGyms repo;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = FakeGyms();
    GymServices.override = repo;
    RestTimerPreference.enabled = false;
    WorkoutUiPreference.workoutTimerEnabled = false;
    WorkoutUiPreference.workoutDurationEnabled = false;
  });
  tearDown(() => GymServices.override = null);

  test('Kanekin correction registers exact DB identity and retains history and other manual places', () async {
    final repository = KanekinRepository();
    final p = await SharedPreferences.getInstance();
    await p.setString('selected_gym', 'カネキンフィットネスジム');
    await p.setString('workout_history', 'unchanged history');
    await CustomGymPreference.replaceAll(['カネキンフィットネスジム', 'ホテルのジム']);
    await TrainingPlacePreference.save(
      const TrainingPlace.manual('カネキンフィットネスジム'),
    );
    await TrainingPlacePreference.migrateKanekinPlace(repository);
    expect(repository.saved.single.id, kanekinStore.id);
    expect((await TrainingPlacePreference.load()).storeId, kanekinStore.id);
    expect(CustomGymPreference.gyms, ['ホテルのジム']);
    expect(p.getString('selected_gym'), isNull);
    expect(p.getString('workout_history'), 'unchanged history');
    await TrainingPlacePreference.migrateKanekinPlace(repository);
    expect(repository.saved.length, 1);
  });

  testWidgets(
    'corrected Kanekin appears as DB equipment entry rather than manual place',
    (t) async {
      GymServices.override = KanekinRepository();
      await CustomGymPreference.replaceAll(['カネキンジム']);
      await TrainingPlacePreference.save(const TrainingPlace.manual('カネキンジム'));
      await t.pumpWidget(const MaterialApp(home: RegisteredGymsPage()));
      await t.pumpAndSettle();
      final preferred = find.byKey(const Key('preferredTrainingPlaceCard'));
      expect(
        find.descendant(
          of: preferred,
          matching: find.text(kanekinStore.chainName),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: preferred, matching: find.text(kanekinStore.name)),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('preferredTrainingPlaceBadge')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('manualPlaceカネキンジム')), findsNothing);
      await t.tap(
        find.descendant(of: preferred, matching: find.text('設備を見る  ›')),
      );
      await t.pumpAndSettle();
      expect(find.byType(GymStoreEquipmentPage), findsOneWidget);
      expect(find.text('ダンベル'), findsWidgets);
    },
  );

  test(
    'offline Kanekin correction retains data until registration succeeds',
    () async {
      final repository = KanekinRepository()..fail = true;
      await CustomGymPreference.replaceAll(['カネキンジム']);
      await TrainingPlacePreference.save(const TrainingPlace.manual('カネキンジム'));
      await TrainingPlacePreference.migrateKanekinPlace(repository);
      expect(CustomGymPreference.gyms, ['カネキンジム']);
      expect((await TrainingPlacePreference.load()).manualName, 'カネキンジム');
      repository.fail = false;
      await TrainingPlacePreference.migrateKanekinPlace(repository);
      expect((await TrainingPlacePreference.load()).storeId, kanekinStore.id);
    },
  );

  testWidgets(
    'manual registration works offline, default rename and deletion preserve history',
    (t) async {
      repo.fail = true;
      repo.failRegistered = true;
      final p = await SharedPreferences.getInstance();
      final history = jsonEncode([
        WorkoutRecord(
          date: DateTime(2026, 9, 24),
          sets: const [],
          gymName: '体育館',
        ).toJson(),
      ]);
      await p.setString('workout_history', history);
      await t.pumpWidget(const MaterialApp(home: RegisteredGymsPage()));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('registerGymButton')));
      await t.pumpAndSettle();
      expect(find.text('探しているジムがありませんか？'), findsOneWidget);
      await t.tap(find.byKey(const Key('registerManualPlace')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('saveCustomGymButton')));
      await t.pumpAndSettle();
      expect(find.text('場所の名前を入力してください'), findsOneWidget);
      await t.enterText(find.byKey(const Key('customGymNameField')), '  体育館  ');
      await t.tap(find.byKey(const Key('saveCustomGymButton')));
      await t.pumpAndSettle();
      expect(CustomGymPreference.gyms, ['体育館']);
      expect(repo.saved, isEmpty);
      await t.tap(find.byKey(const Key('defaultManualPlace体育館')));
      await t.pumpAndSettle();
      expect((await TrainingPlacePreference.load()).name, '体育館');
      expect((await TrainingPlacePreference.load()).storeId, isNull);
      expect(
        t.getTopLeft(find.byKey(const Key('manualPlace体育館'))).dy,
        lessThan(t.getTopLeft(find.byKey(const Key('trainingPlaceHome'))).dy),
      );
      await t.tap(find.byKey(const Key('manualPlaceActions体育館')));
      await t.pumpAndSettle();
      await t.tap(find.text('名前を変更'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('customGymNameField')), '会社のジム');
      await t.tap(find.byKey(const Key('saveCustomGymButton')));
      await t.pumpAndSettle();
      expect((await TrainingPlacePreference.load()).name, '会社のジム');
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(const MaterialApp(home: RegisteredGymsPage()));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('manualPlace会社のジム')), findsOneWidget);
      await t.tap(find.byKey(const Key('manualPlaceActions会社のジム')));
      await t.pumpAndSettle();
      await t.tap(find.text('削除'));
      await t.pumpAndSettle();
      expect(CustomGymPreference.gyms, isEmpty);
      expect((await TrainingPlacePreference.load()).isHome, isTrue);
      expect(p.getString('workout_history'), history);
      expect(t.takeException(), isNull);
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'manual default and workout selection never acquire a store ID on $platform',
      (t) async {
        t.view.physicalSize = const Size(320, 568);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await CustomGymPreference.replaceAll([
          '会社のジム',
          '会社のジム',
          storeA.displayName,
        ]);
        repo.saved = [storeA];
        await TrainingPlacePreference.save(const TrainingPlace.manual('会社のジム'));
        await t.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            home: const WorkoutPage(useDefaultPlace: true),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('会社のジム'), findsOneWidget);
        expect(
          find.byKey(const Key('workoutGymEquipmentButton')),
          findsOneWidget,
        );
        await t.tap(find.byKey(const Key('workoutGymButton')));
        await t.pumpAndSettle();
        await t.scrollUntilVisible(
          find.byKey(ValueKey('selectManualPlace${storeA.displayName}')),
          100,
          scrollable: find.descendant(
            of: find.byType(TrainingPlacePicker),
            matching: find.byType(Scrollable),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(
          find.byKey(ValueKey('selectManualPlace${storeA.displayName}')),
        );
        await t.pumpAndSettle();
        final p = await SharedPreferences.getInstance();
        final draft = jsonDecode(p.getString(activeWorkoutDraftStorageKey)!);
        expect(draft['gymName'], storeA.displayName);
        expect(draft['gymStoreId'], isNull);
        expect(
          draft['customPlaceId'],
          CustomGymPreference.idFor(storeA.displayName),
        );
        expect((await TrainingPlacePreference.load()).name, '会社のジム');
        expect(
          find.byKey(const Key('workoutGymEquipmentButton')),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }

  test('manual default remains manual when an identically named official store is registered', () async {
    await CustomGymPreference.replaceAll([storeA.displayName]);
    await TrainingPlacePreference.save(
      TrainingPlace.manual(storeA.displayName),
    );
    final place = await TrainingPlacePreference.reconcile([storeA]);
    expect(place.manualName, storeA.displayName);
    expect(place.storeId, isNull);
    final record = WorkoutRecord(
      date: DateTime(2026, 9, 24),
      sets: const [],
      gymName: place.name,
      gymStoreId: place.storeId,
    );
    expect(WorkoutRecord.fromJson(record.toJson()).gymStoreId, isNull);
    expect(WorkoutRecord.fromJson(record.toJson()).gymName, place.name);
  });
}
