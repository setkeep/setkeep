import 'support/signed_in_auth.dart';
import 'package:setkeep/exercise_form_catalog.dart';

import 'support/bulk_exercise_flow.dart';
import 'support/legal_consent_fixture.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/design/app_colors.dart';
import 'package:setkeep/main.dart';
import 'package:setkeep/body_weight.dart';
import 'package:setkeep/muscle_targets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _setExistingUserPreferences(Map<String, Object> values) {
  SharedPreferences.setMockInitialValues({
    'onboarding_completed': true,
    'legal_consent': acceptedLegalConsentJson,
    ...values,
  });
}

void main() {
  test('legal consent validates confirmations and document versions', () async {
    SharedPreferences.setMockInitialValues({});
    await expectLater(
      LegalConsentPreference.accept(over16: false, terms: true, privacy: true),
      throwsStateError,
    );
    expect(await LegalConsentPreference.load(), isFalse);
    await LegalConsentPreference.accept(
      over16: true,
      terms: true,
      privacy: true,
    );
    expect(await LegalConsentPreference.load(), isTrue);
    final preferences = await SharedPreferences.getInstance();
    final data = jsonDecode(
      preferences.getString('legal_consent')!,
    ) as Map<String, dynamic>;
    expect(data['over16'], isTrue);
    expect(data['accepted'], isTrue);
    expect(DateTime.tryParse(data['acceptedAt'] as String), isNotNull);
    expect(data['termsVersion'], LegalDocuments.termsVersion);
    expect(data['privacyVersion'], LegalDocuments.privacyVersion);
    for (final field in ['termsVersion', 'privacyVersion']) {
      await preferences.setString(
        'legal_consent',
        jsonEncode({...data, field: 'old'}),
      );
      expect(await LegalConsentPreference.load(), isFalse);
    }
    await preferences.setString('legal_consent', 'invalid');
    expect(await LegalConsentPreference.load(), isFalse);
  });

  testWidgets('legal consent requires all checks and fits a small screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('legalConsent')), findsOneWidget);
    expect(find.byKey(const Key('onboarding')), findsNothing);
    final scrollable = find.descendant(
      of: find.byKey(const Key('legalConsent')),
      matching: find.byType(Scrollable),
    );
    Future<void> scrollTo(Finder target) async {
      // Start at the top so lazy children can be found in either direction.
      final position = tester.state<ScrollableState>(scrollable).position;
      while (position.pixels > position.minScrollExtent) {
        await tester.drag(scrollable, const Offset(0, 400));
        await tester.pumpAndSettle();
      }
      await tester.scrollUntilVisible(target, 150, scrollable: scrollable);
      await tester.pumpAndSettle();
    }

    final button = find.byKey(const Key('acceptLegalConsent'));
    await scrollTo(button);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    for (final key in ['openTerms', 'openPrivacy']) {
      await scrollTo(find.byKey(Key(key)));
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      expect(find.textContaining(key == 'openTerms' ? 'SETKEEP 利用規約' : 'SETKEEP プライバシーポリシー'), findsOneWidget);
      expect(find.textContaining('正式版公開前の暫定内容'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
    }
    for (final key in ['confirmOver16', 'confirmTerms', 'confirmPrivacy']) {
      await scrollTo(find.byKey(Key(key)));
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      await scrollTo(button);
      if (key != 'confirmPrivacy') {
        expect(tester.widget<FilledButton>(button).onPressed, isNull);
      }
      expect(tester.takeException(), isNull);
    }
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);
    expect(await LegalConsentPreference.load(), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byKey(const Key('legalConsent')), findsNothing);
  });

  testWidgets(
    'onboarding completes only at the last page and stays completed',
    (tester) async {
      SharedPreferences.setMockInitialValues({'selected_gym': '自宅'});
      await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('onboarding')), findsOneWidget);
      expect(find.text('ジムと一緒にトレーニングを記録'), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getBool('onboarding_completed'), isNull);
      await tester.tap(find.byKey(const Key('onboardingNext')));
      await tester.pumpAndSettle();
      expect(find.text('成長を可視化'), findsOneWidget);
      await tester.tap(find.byKey(const Key('onboardingBack')));
      await tester.pumpAndSettle();
      expect(find.text('1 / 4'), findsOneWidget);

      // Closing before completion must not persist the flag.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
      await tester.pumpAndSettle();
      expect(find.text('1 / 4'), findsOneWidget);
      for (var page = 2; page <= 4; page++) {
        await tester.tap(find.byKey(const Key('onboardingNext')));
        await tester.pumpAndSettle();
        expect(find.text('$page / 4'), findsOneWidget);
        expect(preferences.getBool('onboarding_completed'), isNull);
      }
      expect(find.text('はじめる'), findsOneWidget);
      await tester.tap(find.text('はじめる'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('legalConsent')), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
      for (final key in ['confirmOver16', 'confirmTerms', 'confirmPrivacy']) {
        await tester.ensureVisible(find.byKey(Key(key)));
        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.byKey(const Key('acceptLegalConsent')));
      await tester.tap(find.byKey(const Key('acceptLegalConsent')));
      await tester.pumpAndSettle();
      expect(find.byType(HomeShell), findsOneWidget);
      expect(preferences.getBool('onboarding_completed'), isTrue);
      expect(preferences.getString('selected_gym'), '自宅');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
      await tester.pumpAndSettle();
      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.byKey(const Key('onboarding')), findsNothing);
    },
  );

  testWidgets('onboarding completed preference opens HomeShell directly', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'onboarding_completed': true,
      'legal_consent': acceptedLegalConsentJson,
    });
    await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byKey(const Key('onboarding')), findsNothing);
  });

  testWidgets('onboarding fits a small screen and supports swiping', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
    await tester.pumpAndSettle();
    for (var page = 1; page <= 4; page++) {
      expect(find.text('$page / 4'), findsOneWidget);
      if (page == 1) {
        expect(find.text('ジムと一緒にトレーニングを記録'), findsOneWidget);
        expect(
          find.textContaining('店舗の設備情報と連動し、そのジムでできる種目も探せます。'),
          findsOneWidget,
        );
      } else if (page == 2) {
        expect(find.textContaining('フォームガイド動画で動きも確認できます。'), findsOneWidget);
      } else if (page == 3) {
        expect(find.text('SETKEEP TRAINERと連携'), findsOneWidget);
        expect(find.textContaining('メニューやコメントを受け取ったり'), findsOneWidget);
      } else {
        expect(find.text('アカウントでSETKEEPをもっと便利に'), findsOneWidget);
        expect(find.textContaining('クラウドバックアップは現在準備中です。'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      if (page < 4) {
        await tester.drag(find.byType(PageView), const Offset(-300, 0));
        await tester.pumpAndSettle();
      }
    }
    expect(await OnboardingPreference.load(), isFalse);
  });

  testWidgets('hidden body model is released and retains the selected angle', (
    tester,
  ) async {
    Future<void> show(bool active) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MuscleMannequinView(scores: const {}, active: active),
        ),
      ),
    );
    expect(MuscleMannequinAngle.values, [
      MuscleMannequinAngle.front,
      MuscleMannequinAngle.back,
    ]);
    expect(MuscleMannequinAngle.front.bodyViewAngle, 0);
    expect(MuscleMannequinAngle.back.bodyViewAngle, 2);
    var expected = MuscleMannequinAngle.front;
    for (final active in [false, true, false, true]) {
      await show(active);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('bodyMannequinFallback')),
        active ? findsOneWidget : findsNothing,
      );
      expect(find.byKey(const Key('body-tab-continuous')), findsNothing);
      final frame = find.byKey(const Key('muscleMannequinFrame'));
      expect(frame, active ? findsOneWidget : findsNothing);
      expect(find.byKey(const Key('muscleMannequinAngle')), findsNothing);
      expect(find.byType(SegmentedButton<MuscleMannequinAngle>), findsNothing);
      if (active) {
        expect(tester.getSemantics(frame).value, expected.label);
        await tester.tap(frame);
        await tester.pumpAndSettle();
        expected = expected == MuscleMannequinAngle.front
            ? MuscleMannequinAngle.back
            : MuscleMannequinAngle.front;
        expect(tester.getSemantics(frame).value, expected.label);
      }
    }
  });

  test('rest countdown does not finish before its absolute deadline', () {
    final end = DateTime(2026, 9, 14, 12);
    expect(
      remainingRestSeconds(end, end.subtract(const Duration(microseconds: 1))),
      1,
    );
    expect(
      remainingRestSeconds(
        end,
        end.subtract(const Duration(milliseconds: 1001)),
      ),
      2,
    );
    expect(remainingRestSeconds(end, end), 0);
    expect(remainingRestSeconds(end, end.add(const Duration(seconds: 10))), 0);
  });

  test('training volume is formatted in kilograms', () {
    expect(formatVolumeKg(12500), '12,500');
    expect(formatVolumeKg(987.5), '987.5');
  });

  test('cardio exercises are available without adding weight volume', () {
    final cardioNames = exerciseTemplates
        .where((exercise) => exercise.bodyPart == '有酸素')
        .map((exercise) => exercise.name)
        .toSet();
    expect(cardioNames, {
      'トレッドミル',
      'エアロバイク',
      'クロストレーナー',
      'ステアクライマー',
      'ローイングマシン',
      'ランニング',
      'ウォーキング',
      'サイクリング',
      'アサルトバイク',
      'スピンバイク',
      '縄跳び',
      'バトルロープ',
      'リカンベントバイク',
    });
    final workout = WorkoutRecord(
      date: DateTime(2026, 9, 13),
      sets: const [
        RecordedSet(
          exerciseName: 'トレッドミル',
          bodyPart: '有酸素',
          weight: 1,
          reps: 30,
          completed: true,
        ),
        RecordedSet(
          exerciseName: 'ベンチプレス',
          bodyPart: '胸',
          weight: 50,
          reps: 10,
          completed: true,
        ),
      ],
    );
    expect(workout.volume, 500);
  });

  test('record types preserve metrics and only weights add volume', () {
    final workout = WorkoutRecord(
      date: DateTime(2026, 9, 14),
      sets: const [
        RecordedSet(
          exerciseName: 'ベンチプレス',
          bodyPart: '胸',
          recordType: ExerciseRecordType.weightReps,
          weight: 60,
          reps: 10,
          completed: true,
        ),
        RecordedSet(
          exerciseName: 'クランチ',
          bodyPart: '腹',
          recordType: ExerciseRecordType.bodyweightReps,
          weight: 0,
          reps: 20,
          completed: true,
        ),
        RecordedSet(
          exerciseName: 'トレッドミル',
          bodyPart: '有酸素',
          recordType: ExerciseRecordType.cardio,
          weight: 0,
          reps: 0,
          durationSeconds: 1800,
          distanceKm: 4.2,
          speedKmh: 8.4,
          inclinePercent: 2,
          completed: true,
        ),
      ],
    );

    final restored = WorkoutRecord.fromJson(workout.toJson());
    expect(restored.volume, 600);
    expect(restored.sets[1].displaySummary, '20 回');
    expect(restored.sets[2].durationSeconds, 1800);
    expect(restored.sets[2].distanceKm, 4.2);
    expect(restored.sets[2].displaySummary, contains('4.2 km'));
  });

  testWidgets('record type selects natural workout fields', (tester) async {
    WorkoutUiPreference.completionCheckEnabled = true;
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final workout = WorkoutRecord(
      date: DateTime(2026, 9, 14),
      sets: const [
        RecordedSet(
          exerciseName: 'クランチ',
          bodyPart: '腹',
          recordType: ExerciseRecordType.bodyweightReps,
          weight: 0,
          reps: 15,
          completed: true,
        ),
        RecordedSet(
          exerciseName: 'プランク',
          bodyPart: '腹',
          recordType: ExerciseRecordType.timed,
          weight: 0,
          reps: 0,
          durationSeconds: 60,
          completed: true,
        ),
        RecordedSet(
          exerciseName: 'トレッドミル',
          bodyPart: '有酸素',
          recordType: ExerciseRecordType.cardio,
          weight: 0,
          reps: 0,
          durationSeconds: 1200,
          distanceKm: 3,
          speedKmh: 9,
          inclinePercent: 1,
          completed: true,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: WorkoutPage(initialWorkout: workout)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('repsField0_1')), findsOneWidget);
    expect(find.byKey(const Key('weightField0_1')), findsNothing);
    expect(find.byKey(const Key('durationField1_1')), findsOneWidget);
    expect(find.byKey(const Key('repsField1_1')), findsNothing);
    expect(find.byKey(const Key('durationField2_')), findsOneWidget);
    expect(find.byKey(const Key('distanceField2_')), findsOneWidget);
    expect(find.byKey(const Key('speedField2_')), findsOneWidget);
    expect(find.byKey(const Key('inclineField2_')), findsOneWidget);
    expect(find.byKey(const Key('weightField2_1')), findsNothing);
    expect(find.byKey(const Key('addSetButton2')), findsNothing);
  });

  testWidgets(
    'exercise picker parent search favorites and row selection are independent',
    (tester) async {
      _setExistingUserPreferences({});
      await CustomExercisePreference.load();
      Future<void> open() async {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: ExercisePickerSheet())),
        );
        await tester.pumpAndSettle();
      }

      await open();
      expect(
        find.byKey(const Key('exercisePickerMyMenuEntry')),
        findsOneWidget,
      );
      expect(find.text('0メニュー'), findsOneWidget);
      await tester.tap(find.byKey(const Key('exercisePickerMyMenuEntry')));
      await tester.pumpAndSettle();
      expect(find.text('保存したマイメニューはありません'), findsOneWidget);
      await tester.tap(find.byKey(const Key('backToExerciseCategories')));
      await tester.pumpAndSettle();
      final search = find.byKey(const Key('exerciseSearchField'));
      for (final query in ['ベンチプレス', 'トレッドミル', 'スレッド']) {
        await tester.enterText(search, query);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('exerciseCategory胸')), findsNothing);
        expect(find.byType(ListTile), findsWidgets);
      }
      await tester.enterText(search, 'ショルダープレス');
      await tester.pumpAndSettle();
      final plate = exerciseTemplates.firstWhere(
        (e) => e.exerciseId == 'plate_loaded_shoulder_press',
      );
      final row = find.byKey(
        const Key('selectExerciseplate_loaded_shoulder_press'),
      );
      final star = find.byKey(Key('favoriteExercise${plate.identity}'));
      await tester.ensureVisible(star);
      await tester.pumpAndSettle();
      await tester.tap(star);
      await tester.pumpAndSettle();
      expect(find.text('0種目選択中'), findsOneWidget);
      expect(await ExerciseFavoritePreference.load(), {plate.identity});
      expect(tester.widget<ListTile>(row).selected, false);
      expect(find.byType(Checkbox), findsNothing);
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(tester.widget<ListTile>(row).selected, true);
      expect(find.text('1種目選択中'), findsOneWidget);
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.text('0種目選択中'), findsOneWidget);
      await tester.tap(find.byKey(const Key('clearExerciseSearch')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('exercisePickerMyMenuEntry')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await open();
      await tester.enterText(search, 'ショルダープレス');
      await tester.pumpAndSettle();
      expect(
        tester.widgetList<ListTile>(find.byType(ListTile)).first.key,
        row.evaluate().single.widget.key,
      );
      expect(
        find.descendant(of: star, matching: find.byIcon(Icons.star_rounded)),
        findsOneWidget,
      );
      await tester.tap(star);
      await tester.pumpAndSettle();
      expect(await ExerciseFavoritePreference.load(), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('exercise picker sorts favorites and normal rows by kana', (
    tester,
  ) async {
    _setExistingUserPreferences({});
    await CustomExercisePreference.load();
    final items = [
      for (final name in ['ソートラ', 'ソートカ', 'ソートナ', 'ソートア'])
        ExerciseTemplate(
          exerciseId: 'custom:$name',
          name: name,
          bodyPart: '胸',
          equipment: 'ダンベル',
          startWeight: 0,
          startReps: 10,
        ),
    ];
    for (final item in items) {
      await CustomExercisePreference.add(item);
    }
    await ExerciseFavoritePreference.save({
      items[0].identity,
      items[1].identity,
    });
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ExercisePickerSheet())),
    );
    await tester.pumpAndSettle();
    Future<void> checkOrder() async {
      await tester.enterText(
        find.byKey(const Key('exerciseSearchField')),
        'ソート',
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<ListTile>(find.byType(ListTile))
            .map((row) => row.key),
        [
          for (final name in ['ソートカ', 'ソートラ', 'ソートア', 'ソートナ'])
            ValueKey('selectExercisecustom:$name'),
        ],
      );
    }

    await checkOrder();
    await tester.tap(find.byKey(const Key('clearExerciseSearch')));
    await tester.pumpAndSettle();
    await openExerciseCategory(tester, '胸');
    await checkOrder();
    _setExistingUserPreferences({});
    await CustomExercisePreference.load();
  });

  test('exercise picker kana sort normalizes katakana and Latin case', () {
    expect(exerciseSortKey('アーム'), exerciseSortKey('あーむ'));
    expect(exerciseSortKey('ABC'), exerciseSortKey('abc'));
    expect(exerciseSortKey('あ').compareTo(exerciseSortKey('カ')), lessThan(0));
  });

  testWidgets('exercise picker menus preserve sets order and skip identities', (
    tester,
  ) async {
    _setExistingUserPreferences({});
    final menu = SavedWorkoutTemplate(
      name: '肩の日',
      sets: [
        for (final id in ['plate_loaded_shoulder_press', 'shoulder_press'])
          RecordedSet(
            exerciseId: id,
            exerciseName: 'ショルダープレス',
            bodyPart: '肩',
            equipment: id == 'shoulder_press' ? 'マシン' : 'プレートロード',
            weight: 25,
            reps: 8,
            completed: true,
          ),
      ],
    );
    List<ExerciseSelection>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await Navigator.of(context)
                    .push<List<ExerciseSelection>>(
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          body: ExercisePickerSheet(
                            menus: [
                              menu,
                              SavedWorkoutTemplate(
                                name: '背中の日',
                                sets: [
                                  menu.sets.first,
                                  const RecordedSet(
                                    exerciseId: 'lat_pulldown',
                                    exerciseName: 'ラットプルダウン',
                                    bodyPart: '背中',
                                    weight: 40,
                                    reps: 10,
                                    completed: true,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
              },
              child: const Text('開く'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
    expect(find.text('肩の日'), findsNothing);
    expect(find.text('2メニュー'), findsOneWidget);
    final entry = find.byKey(const Key('exercisePickerMyMenuEntry'));
    expect(entry, findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('exerciseCategory胸'))).dy -
          tester.getBottomLeft(entry).dy,
      greaterThanOrEqualTo(10),
    );
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exerciseSearchField')), findsNothing);
    expect(find.byKey(const Key('selectExerciseshoulder_press')), findsNothing);
    expect(find.byKey(const Key('selectExerciselat_pulldown')), findsNothing);
    for (var i = 0; i < 2; i++) {
      await tester.tap(
        find.byKey(Key(i == 0 ? 'pickMenu肩の日' : 'pickMenu背中の日')),
      );
      await tester.pumpAndSettle();
      expect(find.text(i == 0 ? '2種目選択中' : '3種目選択中'), findsOneWidget);
      expect(find.byKey(const Key('pickMenu肩の日')), findsNothing);
      expect(
        find.byKey(const Key('selectExerciseshoulder_press')),
        i == 0 ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(const Key('selectExerciselat_pulldown')),
        i == 0 ? findsNothing : findsOneWidget,
      );
      expect(result, isNull);
      // Searching this menu must never bring in exercises from another menu.
      await tester.enterText(
        find.byKey(const Key('exerciseSearchField')),
        i == 0 ? 'ラットプルダウン' : 'マシン',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          Key(
            i == 0
                ? 'selectExerciselat_pulldown'
                : 'selectExerciseshoulder_press',
          ),
        ),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('backToExerciseCategories')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pickMenu肩の日')), findsOneWidget);
      expect(
        find.byKey(const Key('selectExerciseplate_loaded_shoulder_press')),
        findsNothing,
      );
    }
    await tester.tap(find.byKey(const Key('backToExerciseCategories')));
    await tester.pumpAndSettle();
    expect(entry, findsOneWidget);
    expect(find.text('3種目選択中'), findsOneWidget);
    await tester.tap(find.byKey(const Key('addSelectedExercises')));
    await tester.pumpAndSettle();
    expect(result!.map((e) => e.template.exerciseId), [
      'plate_loaded_shoulder_press',
      'shoulder_press',
      'lat_pulldown',
    ]);
    expect(result!.first.savedSets!.single.weight, 25);
    expect(result!.first.savedSets!.single.reps, 8);
    expect(result!.first.savedSets!.single.completed, true);
  });

  testWidgets('exercise picker clips selected ink below opaque fixed areas', (
    tester,
  ) async {
    _setExistingUserPreferences({});
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ExercisePickerSheet())),
    );
    await tester.pumpAndSettle();
    await openExerciseCategory(tester, '胸');
    await selectPickerExercise(tester, 'bench_press');
    final row = find.byKey(const Key('selectExercisebench_press'));
    expect(tester.widget<ListTile>(row).selected, isTrue);
    expect(
      tester.widget<ListTile>(row).selectedTileColor,
      AppColors.primaryGreenSoft,
    );
    for (final key in [
      'exercisePickerHeader',
      'exercisePickerSearchArea',
      'exercisePickerFooter',
    ]) {
      expect(tester.widget<ColoredBox>(find.byKey(Key(key))).color.a, 1);
    }
    final clip = find.byKey(const Key('exercisePickerListClip'));
    expect(tester.widget<ClipRect>(clip).clipBehavior, Clip.hardEdge);
    // Ink must paint on a Material INSIDE the clip, not on the bottom sheet.
    final material = find
        .ancestor(of: row, matching: find.byType(Material))
        .first;
    expect(find.descendant(of: clip, matching: material), findsOneWidget);
    await tester.tap(find.byKey(const Key('clearExerciseSearch')));
    await tester.pumpAndSettle();
    await tester.drag(exercisePickerScrollable(), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(clip).dy,
      greaterThanOrEqualTo(
        tester
            .getBottomLeft(find.byKey(const Key('exercisePickerSearchArea')))
            .dy,
      ),
    );
    expect(
      tester.getBottomLeft(clip).dy,
      lessThanOrEqualTo(
        tester.getTopLeft(find.byKey(const Key('exercisePickerFooter'))).dy,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('exercise picker selects a category before searching exercises', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ExercisePickerSheet(existingNames: <String>{})),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('部位・カテゴリを選択'), findsOneWidget);
    expect(find.text('トレッドミル'), findsNothing);
    for (final category in ['胸', '背中', '肩', '腕', '脚', '腹', '有酸素', 'HYROX']) {
      expect(find.byKey(Key('bodyPartIllustration$category')), findsOneWidget);
    }
    const assets = {
      '胸': 'chest',
      '背中': 'back',
      '肩': 'shoulders',
      '腕': 'arms',
      '脚': 'legs',
      '腹': 'abs',
      '有酸素': 'cardio',
      'HYROX': 'hyrox',
    };
    for (final entry in assets.entries) {
      final image = tester.widget<Image>(
        find.descendant(
          of: find.byKey(Key('bodyPartIllustration${entry.key}')),
          matching: find.byType(Image),
        ),
      );
      expect(
        (image.image as AssetImage).assetName,
        'assets/category_muscles/${entry.value}.png',
      );
    }
    await openExerciseCategory(tester, '有酸素');
    expect(find.text('有酸素の種目'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('exerciseSearchField')),
      'トレッドミル',
    );
    await tester.pumpAndSettle();
    expect(find.text('トレッドミル'), findsOneWidget);
    expect(find.byKey(const Key('exerciseSearchField')), findsOneWidget);

    tester.view.physicalSize = const Size(320, 480);
    for (final category in ['有酸素', 'HYROX']) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ExercisePickerSheet(existingNames: <String>{})),
        ),
      );
      await tester.pumpAndSettle();
      final card = find.byKey(Key('exerciseCategory$category'));
      await tester.scrollUntilVisible(
        card,
        180,
        scrollable: exercisePickerScrollable(),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(Key('bodyPartIllustration$category')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.text('$categoryの種目'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('exercise muscle detail explains main and supporting targets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final exercise = exerciseTemplates.firstWhere(
      (item) => item.exerciseId == 'chest_press',
    );
    await tester.pumpWidget(
      MaterialApp(home: ExerciseMuscleDetailPage(exercise: exercise)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('exerciseVitalVideoCard')), findsOneWidget);
    expect(find.text('主に使う筋肉'), findsOneWidget);
    expect(find.text('大胸筋'), findsOneWidget);
    expect(find.text('三角筋前部'), findsOneWidget);
    expect(find.text('上腕三頭筋'), findsOneWidget);
  });

  testWidgets('exercise rows show thumbnail, name, favorite and detail', (
    tester,
  ) async {
    _setExistingUserPreferences({});
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ExercisePickerSheet(existingNames: {}, menus: []),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final available = exerciseTemplates
        .where(
          (e) =>
              ExerciseFormCatalog.resolve(e.exerciseId, e.name)?.available ==
              true,
        )
        .take(2)
        .toList();
    expect(available, hasLength(2));
    for (final exercise in available) {
      await tester.enterText(
        find.byKey(const Key('exerciseSearchField')),
        exercise.name,
      );
      await tester.pumpAndSettle();
      final row = find.byKey(
        Key('selectExercise${exercise.exerciseId ?? exercise.name}'),
      );
      final thumbnail = find.descendant(
        of: row,
        matching: find.byKey(const Key('exerciseListThumbnail')),
      );
      final detail = find.byKey(
        Key('exerciseDetails${exercise.exerciseId ?? exercise.name}'),
      );
      final favorite = find.byKey(Key('favoriteExercise${exercise.identity}'));
      final title = find.byWidget(tester.widget<ListTile>(row).title!);
      expect(thumbnail, findsOneWidget);
      expect(tester.getSize(thumbnail), const Size.square(56));
      expect(
        tester.getRect(thumbnail).right,
        lessThan(tester.getRect(title).left),
      );
      expect(
        tester.getRect(title).right,
        lessThanOrEqualTo(tester.getRect(favorite).left),
      );
      expect(
        tester.getRect(favorite).right,
        lessThanOrEqualTo(tester.getRect(detail).left),
      );
      expect(
        tester.getRect(detail).right,
        lessThanOrEqualTo(tester.getRect(row).right),
      );
      expect(tester.widget<Text>(title).maxLines, 2);
      final favoritesBefore = await ExerciseFavoritePreference.load();
      await tester.tap(detail);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(ExerciseMuscleDetailPage), findsOneWidget);
      expect(find.text(exercise.name), findsWidgets);
      expect(find.byKey(const Key('exerciseMuscleModel3D')), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('0種目選択中'), findsOneWidget);
      expect(await ExerciseFavoritePreference.load(), favoritesBefore);
      await tester.tap(favorite);
      await tester.pumpAndSettle();
      expect(find.text('0種目選択中'), findsOneWidget);
      expect(
        (await ExerciseFavoritePreference.load()).contains(exercise.identity),
        !favoritesBefore.contains(exercise.identity),
      );
    }
    final unavailable = exerciseTemplates.firstWhere(
      (e) =>
          ExerciseFormCatalog.resolve(e.exerciseId, e.name)?.available != true,
    );
    await tester.enterText(
      find.byKey(const Key('exerciseSearchField')),
      unavailable.name,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        Key('exerciseDetails${unavailable.exerciseId ?? unavailable.name}'),
      ),
      findsOneWidget,
    );
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('long exercise row fits a compact $platform screen', (
      tester,
    ) async {
      _setExistingUserPreferences({});
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: const Scaffold(body: ExercisePickerSheet()),
        ),
      );
      await tester.pumpAndSettle();
      final exercise = exerciseTemplates.reduce(
        (a, b) => a.name.length >= b.name.length ? a : b,
      );
      await tester.enterText(
        find.byKey(const Key('exerciseSearchField')),
        exercise.name,
      );
      await tester.pumpAndSettle();
      final row = find.byKey(
        Key('selectExercise${exercise.exerciseId ?? exercise.name}'),
      );
      expect(row, findsOneWidget);
      final title = tester.widget<ListTile>(row).title! as Text;
      expect(title.maxLines, 2);
      expect(title.overflow, TextOverflow.ellipsis);
      final favorite = find.byKey(Key('favoriteExercise${exercise.identity}'));
      final detail = find.byKey(
        Key('exerciseDetails${exercise.exerciseId ?? exercise.name}'),
      );
      expect(
        tester.getRect(favorite).right,
        lessThanOrEqualTo(tester.getRect(detail).left),
      );
      expect(
        tester.getRect(detail).right,
        lessThanOrEqualTo(tester.getRect(row).right),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('custom exercise is created from and inherits its category', (
    tester,
  ) async {
    _setExistingUserPreferences({});
    await CustomExercisePreference.load();
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ExercisePickerSheet(existingNames: {}, menus: []),
        ),
      ),
    );
    expect(find.text('自分で種目を作る'), findsNothing);
    await openExerciseCategory(tester, '背中');
    await tester.tap(find.byKey(const Key('addCustomExerciseForCategory')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('customExerciseBodyPartField')), findsNothing);
    expect(
      find.byKey(const Key('inheritedCustomExerciseBodyPart')),
      findsOneWidget,
    );
    expect(find.text('背中'), findsWidgets);
    await tester.enterText(
      find.byKey(const Key('customExerciseNameField')),
      'テスト背中種目',
    );
    await tester.tap(find.byKey(const Key('saveCustomExerciseButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('exerciseSearchField')),
      'テスト背中種目',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        Key(
          'selectExercise${CustomExercisePreference.exercises.single.exerciseId}',
        ),
      ),
      findsOneWidget,
    );
    expect(CustomExercisePreference.exercises.single.bodyPart, '背中');
  });

  test('workout UI preferences persist', () async {
    _setExistingUserPreferences({});
    await WorkoutUiPreference.load();
    expect(WorkoutUiPreference.completionCheckEnabled, isTrue);
    expect(WorkoutUiPreference.workoutTimerEnabled, isTrue);
    expect(WorkoutUiPreference.workoutDurationEnabled, isTrue);

    await WorkoutUiPreference.setCompletionCheckEnabled(false);
    await WorkoutUiPreference.setWorkoutTimerEnabled(false);
    await WorkoutUiPreference.setWorkoutDurationEnabled(false);
    WorkoutUiPreference.completionCheckEnabled = true;
    WorkoutUiPreference.workoutTimerEnabled = true;
    WorkoutUiPreference.workoutDurationEnabled = true;
    await WorkoutUiPreference.load();

    expect(WorkoutUiPreference.completionCheckEnabled, isFalse);
    expect(WorkoutUiPreference.workoutTimerEnabled, isFalse);
    expect(WorkoutUiPreference.workoutDurationEnabled, isFalse);
    await WorkoutUiPreference.setCompletionCheckEnabled(true);
    await WorkoutUiPreference.setWorkoutTimerEnabled(true);
    await WorkoutUiPreference.setWorkoutDurationEnabled(true);
  });

  test(
    'legacy timer settings migrate to one training duration value',
    () async {
      _setExistingUserPreferences({
        'workout_timer_enabled': false,
        'workout_duration_enabled': true,
      });

      await WorkoutUiPreference.load();

      expect(WorkoutUiPreference.workoutTimerEnabled, isFalse);
      expect(WorkoutUiPreference.workoutDurationEnabled, isFalse);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getBool('workout_timer_enabled'), isFalse);
      expect(preferences.getBool('workout_duration_enabled'), isFalse);
    },
  );

  test('custom exercises persist between sessions', () async {
    _setExistingUserPreferences({});
    await CustomExercisePreference.load();
    await CustomExercisePreference.add(
      const ExerciseTemplate(
        name: 'テスト種目',
        bodyPart: '背中',
        equipment: 'カスタム',
        startWeight: 15,
      ),
    );

    CustomExercisePreference.exercises = [];
    await CustomExercisePreference.load();
    expect(CustomExercisePreference.exercises, hasLength(1));
    expect(CustomExercisePreference.exercises.single.name, 'テスト種目');
    expect(CustomExercisePreference.exercises.single.bodyPart, '背中');
  });

  test(
    'custom exercises reject duplicates and support update and removal',
    () async {
      _setExistingUserPreferences({});
      await CustomExercisePreference.load();
      const exercise = ExerciseTemplate(
        name: 'ケーブルプレス',
        bodyPart: '胸',
        equipment: 'ケーブル',
        startWeight: 15,
      );

      expect(await CustomExercisePreference.add(exercise), isTrue);
      expect(
        await CustomExercisePreference.add(
          const ExerciseTemplate(
            name: 'ケーブルプレス',
            bodyPart: '肩',
            equipment: 'ケーブル',
            startWeight: 10,
          ),
        ),
        isFalse,
      );
      expect(
        await CustomExercisePreference.add(
          const ExerciseTemplate(
            name: 'ベンチプレス',
            bodyPart: '胸',
            equipment: 'その他',
            startWeight: 10,
          ),
        ),
        isTrue,
      );

      await CustomExercisePreference.remove(
        CustomExercisePreference.exercises.firstWhere(
          (e) => e.name == 'ベンチプレス',
        ),
      );
      final originalId = CustomExercisePreference.exercises.single.exerciseId;
      const updated = ExerciseTemplate(
        name: 'ケーブルプレス改',
        bodyPart: '肩',
        equipment: 'ケーブル',
        startWeight: 17.5,
        startReps: 12,
      );
      expect(await CustomExercisePreference.update('ケーブルプレス', updated), isTrue);
      expect(CustomExercisePreference.exercises.single.name, 'ケーブルプレス改');
      expect(CustomExercisePreference.exercises.single.startWeight, 17.5);

      expect(CustomExercisePreference.exercises.single.exerciseId, originalId);
      await CustomExercisePreference.remove(
        CustomExercisePreference.exercises.single,
      );
      CustomExercisePreference.exercises = [];
      await CustomExercisePreference.load();
      expect(CustomExercisePreference.exercises, isEmpty);
    },
  );

  test('custom gyms persist without standard or duplicate names', () async {
    _setExistingUserPreferences({});
    await CustomGymPreference.load();

    expect(await CustomGymPreference.add('中央体育館'), isTrue);
    expect(await CustomGymPreference.add('中央体育館'), isFalse);
    expect(await CustomGymPreference.add('自宅'), isFalse);
    expect(await CustomGymPreference.update('中央体育館', '市民スポーツセンター'), isTrue);

    CustomGymPreference.gyms = [];
    await CustomGymPreference.load();
    expect(CustomGymPreference.gyms, ['市民スポーツセンター']);

    await CustomGymPreference.remove('市民スポーツセンター');
    expect(CustomGymPreference.gyms, isEmpty);
  });

  test('saved menus and custom exercises skip only broken items', () async {
    const validMenu = SavedWorkoutTemplate(
      name: '脚の日',
      sets: [
        RecordedSet(
          exerciseName: 'スクワット',
          bodyPart: '脚',
          weight: 80,
          reps: 5,
          completed: true,
        ),
      ],
    );
    const validExercise = ExerciseTemplate(
      name: 'ケーブルフライ',
      bodyPart: '胸',
      equipment: 'カスタム',
      startWeight: 12.5,
    );
    _setExistingUserPreferences({
      'workout_templates': jsonEncode([
        validMenu.toJson(),
        {'name': '', 'sets': []},
        {'name': '壊れたメニュー'},
        'unexpected',
      ]),
      'custom_exercises': jsonEncode([
        validExercise.toJson(),
        {'name': '', 'bodyPart': '胸'},
        {'name': '壊れた種目'},
        42,
      ]),
    });

    final menus = await WorkoutTemplatePreference.load();
    await CustomExercisePreference.load();

    expect(menus, hasLength(1));
    expect(menus.single.name, '脚の日');
    expect(CustomExercisePreference.exercises, hasLength(1));
    expect(CustomExercisePreference.exercises.single.name, 'ケーブルフライ');
  });

  test('personal bests are counted in date order', () {
    WorkoutRecord workout(DateTime date, String exercise, int weight) =>
        WorkoutRecord(
          date: date,
          sets: [
            RecordedSet(
              exerciseName: exercise,
              bodyPart: exercise == 'スクワット' ? '脚' : '胸',
              weight: weight.toDouble(),
              reps: 5,
              completed: true,
            ),
          ],
        );

    final history = [
      workout(DateTime(2026, 1, 4), 'ベンチプレス', 50),
      workout(DateTime(2026, 1, 3), 'ベンチプレス', 60),
      workout(DateTime(2026, 1, 1), 'ベンチプレス', 50),
      workout(DateTime(2026, 1, 2), 'スクワット', 80),
      workout(DateTime(2026, 1, 2), 'ベンチプレス', 55),
    ];

    expect(countPersonalBests(history, DateTime(2026, 1, 2)), 3);
  });

  test('muscle map periods count completed sets by body part', () {
    final now = DateTime(2026, 9, 12, 12);
    WorkoutRecord workout(DateTime date, String part, int sets) =>
        WorkoutRecord(
          date: date,
          sets: List.generate(
            sets,
            (_) => RecordedSet(
              exerciseName: part,
              bodyPart: part,
              weight: 10,
              reps: 10,
              completed: true,
            ),
          ),
        );
    final history = [
      workout(now.subtract(const Duration(days: 2)), '胸', 2),
      workout(now.subtract(const Duration(days: 20)), '背中', 3),
      workout(now.subtract(const Duration(days: 100)), '脚', 4),
    ];

    expect(bodyPartSetCounts(history, MuscleMapPeriod.week, now: now), {
      '胸': 2,
    });
    expect(bodyPartSetCounts(history, MuscleMapPeriod.month, now: now), {
      '胸': 2,
      '背中': 3,
    });
    expect(
      bodyPartSetCounts(history, MuscleMapPeriod.sixMonths, now: now)['脚'],
      4,
    );
  });

  test('chest press maps primary and secondary muscles independently', () {
    final profile = muscleProfileForExercise('チェストプレス', '胸');
    expect(profile.primary, [MuscleRegion.pectoralisMajor]);
    expect(profile.secondary, contains(MuscleRegion.anteriorDeltoid));
    expect(profile.secondary, contains(MuscleRegion.triceps));

    final scores = muscleScoresForSets(const [
      MuscleSetUsage('チェストプレス', '胸'),
      MuscleSetUsage('チェストプレス', '胸'),
    ]);
    expect(scores[MuscleRegion.pectoralisMajor], 2);
    expect(scores[MuscleRegion.anteriorDeltoid], closeTo(0.7, 0.001));
  });

  testWidgets('3D muscle mannequin switches history periods', (tester) async {
    final workout = WorkoutRecord(
      date: DateTime.now().subtract(const Duration(days: 15)),
      sets: const [
        RecordedSet(
          exerciseName: 'ラットプルダウン',
          bodyPart: '背中',
          weight: 40,
          reps: 10,
          completed: true,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BodyMapPage(history: [workout])),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('3D筋肉マネキン'), findsOneWidget);
    expect(find.byKey(const Key('muscleModel3D')), findsOneWidget);

    final frame = find.byKey(const Key('muscleMannequinFrame'));
    String selected() => tester.getSemantics(frame).value;
    expect(selected(), '正面');
    expect(find.byKey(const Key('muscleMannequinAngle')), findsNothing);
    expect(find.text('側面'), findsNothing);
    expect(find.text('背面'), findsNothing);
    await tester.tapAt(tester.getTopLeft(frame) + const Offset(12, 12));
    await tester.pumpAndSettle();
    expect(selected(), '背面');
    await tester.tap(find.byKey(const Key('musclePeriodmonth')));
    await tester.pumpAndSettle();
    expect(find.text('1ヶ月 ・ 1セット'), findsOneWidget);
    expect(selected(), '背面');
    expect(find.text('3方向表示'), findsNothing);
    await tester.tap(frame);
    await tester.pumpAndSettle();
    expect(selected(), '正面');
    await tester.tap(find.byKey(const Key('musclePeriodweek')));
    await tester.pumpAndSettle();
    expect(find.text('1週間 ・ 0セット'), findsOneWidget);
    expect(selected(), '正面');
    expect(find.byKey(const Key('muscleModel3D')), findsOneWidget);
    expect(find.byKey(const Key('bodyMannequinFallback')), findsOneWidget);
    await tester.tap(find.byKey(const Key('musclePeriodmonth')));
    await tester.pumpAndSettle();
    expect(selected(), '正面');

    await tester.scrollUntilVisible(
      find.byKey(const Key('muscleCount背中')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('muscleCount背中')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('muscleCount背中'))).data,
      '1セット',
    );
  });

  test('changing the calendar day preserves the recorded time', () {
    final original = DateTime(2026, 9, 12, 18, 42, 31, 120, 45);
    final changed = preserveWorkoutTime(original, DateTime(2026, 8, 3));

    expect(changed, DateTime(2026, 8, 3, 18, 42, 31, 120, 45));
  });

  test('decimal weights support old integer data and compact display', () {
    final oldData = RecordedSet.fromJson({
      'exerciseName': 'ベンチプレス',
      'bodyPart': '胸',
      'weight': 50,
      'reps': 8,
      'completed': true,
    });
    final decimalData = RecordedSet.fromJson({
      'exerciseName': 'ベンチプレス',
      'bodyPart': '胸',
      'weight': 52.5,
      'reps': 8,
      'completed': true,
    });

    expect(oldData.weight, 50.0);
    expect(decimalData.weight, 52.5);
    expect(formatWeight(oldData.weight), '50');
    expect(formatWeight(decimalData.weight), '52.5');
    expect(parseWeight('52,5'), 52.5);
  });

  test('history decoding keeps valid records and skips broken items', () {
    final valid = WorkoutRecord(
      date: DateTime(2026, 9, 12, 18, 30),
      sets: const [
        RecordedSet(
          exerciseName: 'ベンチプレス',
          bodyPart: '胸',
          weight: 52.5,
          reps: 8,
          completed: true,
        ),
      ],
    );
    final decoded = decodeWorkoutHistory(
      jsonEncode([
        valid.toJson(),
        {'date': '壊れた日付', 'sets': []},
        {'date': '2026-09-11T18:30:00.000', 'sets': []},
        'unexpected',
      ]),
    );

    expect(decoded, hasLength(1));
    expect(decoded.single.exerciseNames, ['ベンチプレス']);
    expect(decodeWorkoutHistory('broken json'), isEmpty);
    expect(decodeWorkoutHistory('{"workouts":[]}'), isEmpty);
  });

  testWidgets('app opens when saved history is corrupted', (tester) async {
    _setExistingUserPreferences({'workout_history': 'broken json'});

    await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
    await tester.pumpAndSettle();

    expect(find.text('今日も積み上げよう'), findsNothing);
    expect(find.byKey(const Key('startWorkoutButton')), findsOneWidget);
  });

  testWidgets('custom exercises can be created edited deleted and restored', (
    tester,
  ) async {
    _setExistingUserPreferences({});
    await CustomExercisePreference.load();
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: CustomExerciseManagementPage()),
    );
    await tester.pumpAndSettle();
    expect(find.text('カスタム種目はまだありません'), findsOneWidget);

    await tester.tap(find.text('種目を作る'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('customExerciseBodyPartField')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('customExerciseEquipmentField')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('customExerciseNameField')),
      'テストプレス',
    );
    await tester.enterText(
      find.byKey(const Key('customExerciseWeightField')),
      '17.5',
    );
    await tester.enterText(
      find.byKey(const Key('customExerciseRepsField')),
      '12',
    );
    await tester.tap(find.byKey(const Key('saveCustomExerciseButton')));
    await tester.pumpAndSettle();

    expect(find.text('テストプレス'), findsOneWidget);
    expect(find.text('胸 ・ マシン ・ 17.5kg × 12回'), findsOneWidget);
    expect(CustomExercisePreference.exercises, hasLength(1));

    await tester.tap(find.byTooltip('テストプレスを編集'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('customExerciseNameField')),
      'テストプレス改',
    );
    await tester.enterText(
      find.byKey(const Key('customExerciseWeightField')),
      '20',
    );
    await tester.tap(find.byKey(const Key('saveCustomExerciseButton')));
    await tester.pumpAndSettle();
    expect(find.text('テストプレス改'), findsOneWidget);
    expect(find.text('胸 ・ マシン ・ 20kg × 12回'), findsOneWidget);

    await tester.tap(find.byTooltip('テストプレス改を削除'));
    await tester.pumpAndSettle();
    expect(find.text('カスタム種目はまだありません'), findsOneWidget);
    expect(find.text('「テストプレス改」を削除しました'), findsOneWidget);

    await tester.tap(find.text('元に戻す'));
    await tester.pumpAndSettle();
    expect(find.text('テストプレス改'), findsOneWidget);
    expect(find.text('「テストプレス改」を元に戻しました'), findsOneWidget);

    CustomExercisePreference.exercises = [];
    await CustomExercisePreference.load();
    expect(CustomExercisePreference.exercises.single.name, 'テストプレス改');
    expect(CustomExercisePreference.exercises.single.startWeight, 20);
    expect(CustomExercisePreference.exercises.single.startReps, 12);
  });

  testWidgets('custom gyms can be created edited deleted and restored', (
    tester,
  ) async {
    _setExistingUserPreferences({});
    await CustomGymPreference.load();
    String? selectedGym = '中央体育館';
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: CustomGymManagementPage(
          selectedGym: selectedGym,
          onSelectedGymChanged: (gym) async => selectedGym = gym,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addCustomGymButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('customGymNameField')),
      '中央体育館',
    );
    await tester.tap(find.byKey(const Key('saveCustomGymButton')));
    await tester.pumpAndSettle();
    expect(find.text('中央体育館'), findsOneWidget);
    expect(CustomGymPreference.gyms, ['中央体育館']);

    await tester.tap(find.byKey(const Key('gymActions中央体育館')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('名前を変更'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('customGymNameField')),
      '市民スポーツセンター',
    );
    await tester.tap(find.byKey(const Key('saveCustomGymButton')));
    await tester.pumpAndSettle();
    expect(find.text('市民スポーツセンター'), findsOneWidget);
    expect(selectedGym, '市民スポーツセンター');

    await tester.tap(find.byKey(const Key('gymActions市民スポーツセンター')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('削除'));
    await tester.pumpAndSettle();
    expect(find.text('市民スポーツセンター'), findsNothing);
    expect(find.text('「市民スポーツセンター」を削除しました'), findsOneWidget);
    expect(selectedGym, isNull);

    await tester.tap(find.text('元に戻す'));
    await tester.pumpAndSettle();
    expect(find.text('市民スポーツセンター'), findsOneWidget);
    expect(find.text('「市民スポーツセンター」を元に戻しました'), findsOneWidget);
    expect(selectedGym, '市民スポーツセンター');

    CustomGymPreference.gyms = [];
    await CustomGymPreference.load();
    expect(CustomGymPreference.gyms, ['市民スポーツセンター']);
  });

  testWidgets('profile display name persists and empty values reset it', (
    tester,
  ) async {
    _setExistingUserPreferences({});

    Future<void> openProfile() async {
      await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.person_outline_rounded));
      await tester.pumpAndSettle();
    }

    Future<void> saveName(String name) async {
      await tester.tap(find.byKey(const Key('editProfileDisplayName')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('profileDisplayNameField')),
        name,
      );
      await tester.tap(find.byKey(const Key('saveProfileDisplayName')));
      await tester.pumpAndSettle();
    }

    String? shownName() =>
        tester.widget<Text>(find.byKey(const Key('profileDisplayName'))).data;

    await openProfile();
    expect(shownName(), 'SETKEEPユーザー');
    await saveName('  トレーニング太郎  ');
    expect(shownName(), 'トレーニング太郎');
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('profile_display_name'), 'トレーニング太郎');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await openProfile();
    expect(shownName(), 'トレーニング太郎');
    await tester.tap(find.byKey(const Key('editProfileDisplayName')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const Key('profileDisplayNameField')),
          )
          .initialValue,
      'トレーニング太郎',
    );
    await tester.enterText(
      find.byKey(const Key('profileDisplayNameField')),
      '保存しない名前',
    );
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(shownName(), 'トレーニング太郎');
    expect(preferences.getString('profile_display_name'), 'トレーニング太郎');

    await saveName('');
    expect(shownName(), 'SETKEEPユーザー');
    expect(preferences.getString('profile_display_name'), '');
    await saveName('別の名前');
    await saveName('  　 ');
    expect(shownName(), 'SETKEEPユーザー');
    expect(preferences.getString('profile_display_name'), '');

    await saveName(List.filled(30, '長い表示名').join());
    expect(tester.takeException(), isNull);
    final nameText = tester.widget<Text>(
      find.byKey(const Key('profileDisplayName')),
    );
    expect(nameText.maxLines, 2);
    expect(nameText.overflow, TextOverflow.ellipsis);
  });

  testWidgets('profile sections are ordered and backup tools open separately', (
    tester,
  ) async {
    _setExistingUserPreferences({});
    await WorkoutUiPreference.load();
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.person_outline_rounded));
    await tester.pumpAndSettle();

    expect(find.text('SETKEEPユーザー'), findsOneWidget);
    expect(find.byKey(const Key('editProfileDisplayName')), findsOneWidget);
    expect(find.byKey(const Key('trainingSettingsButton')), findsOneWidget);
    expect(find.byKey(const Key('trainerQrButton')), findsOneWidget);
    expect(find.text('SETKEEP TRAINER連携'), findsOneWidget);
    expect(find.text('SETKEEP TRAINERと連携'), findsOneWidget);
    expect(find.byKey(const Key('contactButton')), findsOneWidget);
    expect(find.byKey(const Key('appAboutButton')), findsOneWidget);
    expect(find.byKey(const Key('locationSettingsButton')), findsNothing);
    expect(find.byKey(const Key('registeredGymsButton')), findsOneWidget);
    expect(find.text('いつもの場所'), findsNothing);
    expect(find.text('カスタム場所'), findsNothing);
    expect(find.text('重量の単位'), findsNothing);
    expect(find.byKey(const Key('savedMenuManagementButton')), findsNothing);
    expect(
      find.byKey(const Key('customExerciseManagementButton')),
      findsNothing,
    );

    final trainingY = tester.getTopLeft(find.text('トレーニング設定').first).dy;
    expect(find.text('アカウント関連'), findsNothing);
    expect(find.text('Supabaseクラウド'), findsNothing);
    final otherY = tester.getTopLeft(find.text('その他設定')).dy;
    final backupY = tester.getTopLeft(find.text('バックアップ・データ管理').first).dy;
    expect(trainingY, lessThan(otherY));
    expect(otherY, lessThan(backupY));

    final trainerEntry = tester.widget<ListTile>(
      find.byKey(const Key('trainerQrButton')),
    );
    expect(trainerEntry.enabled, isTrue);
    expect(trainerEntry.onTap, isNotNull);
    expect(find.text('準備中'), findsOneWidget);
    await tester.tap(find.byKey(const Key('trainerQrButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trainerSharingPage')), findsNothing);
    expect(find.byKey(const Key('trainerComingSoonDialog')), findsOneWidget);
    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('backupDataManagementButton')),
    );
    await tester.tap(find.byKey(const Key('backupDataManagementButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exportBackupFile')), findsOneWidget);
    expect(find.byKey(const Key('importBackupFile')), findsOneWidget);
    expect(find.text('バックアップをコピー'), findsNothing);
    expect(find.text('バックアップを読み込む'), findsNothing);
  });

  testWidgets(
    'training settings are grouped and rest timer depends on checks',
    (tester) async {
      _setExistingUserPreferences({
        'completion_check_enabled': false,
        'workout_timer_enabled': true,
        'workout_duration_enabled': true,
        'rest_timer_enabled': true,
        'rest_timer_seconds': 90,
      });
      await RestTimerPreference.load();
      await WorkoutUiPreference.load();
      await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.person_outline_rounded));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('completionCheckSwitch')), findsNothing);
      await tester.ensureVisible(
        find.byKey(const Key('trainingSettingsButton')),
      );
      await tester.tap(find.byKey(const Key('trainingSettingsButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('completionCheckSwitch')), findsOneWidget);
      expect(find.byKey(const Key('trainingDurationSwitch')), findsOneWidget);
      expect(find.byKey(const Key('workoutTimerSwitch')), findsNothing);
      expect(find.byKey(const Key('workoutDurationSwitch')), findsNothing);
      expect(find.text('トレーニング時間'), findsOneWidget);
      expect(find.text('トレーニングタイマー'), findsNothing);
      expect(find.text('筋トレ時間'), findsNothing);
      expect(find.byKey(const Key('restTimerSwitch')), findsNothing);
      expect(
        find.byKey(const Key('savedMenuManagementButton')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('customExerciseManagementButton')),
        findsOneWidget,
      );
      final completionY = tester
          .getTopLeft(find.byKey(const Key('completionCheckSwitch')))
          .dy;
      final timerY = tester
          .getTopLeft(find.byKey(const Key('trainingDurationSwitch')))
          .dy;
      final menuY = tester
          .getTopLeft(find.byKey(const Key('savedMenuManagementButton')))
          .dy;
      final customExerciseY = tester
          .getTopLeft(find.byKey(const Key('customExerciseManagementButton')))
          .dy;
      expect(completionY, lessThan(timerY));
      expect(timerY, lessThan(menuY));
      expect(menuY, lessThan(customExerciseY));
      expect(find.byKey(const Key('restTimerDurationButton')), findsNothing);
      await tester.tap(find.byKey(const Key('completionCheckSwitch')));
      await tester.pumpAndSettle();
      expect(RestTimerPreference.enabled, isFalse);
      expect(find.byKey(const Key('restTimerSwitch')), findsOneWidget);
      final restY = tester
          .getTopLeft(find.byKey(const Key('restTimerSwitch')))
          .dy;
      final timerAfterRestY = tester
          .getTopLeft(find.byKey(const Key('trainingDurationSwitch')))
          .dy;
      expect(completionY, lessThan(restY));
      expect(restY, lessThan(timerAfterRestY));
      await tester.tap(find.byKey(const Key('restTimerSwitch')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('restTimerDurationButton')), findsOneWidget);

      await tester.tap(find.byKey(const Key('trainingDurationSwitch')));
      await tester.pumpAndSettle();
      expect(WorkoutUiPreference.workoutTimerEnabled, isFalse);
      expect(WorkoutUiPreference.workoutDurationEnabled, isFalse);
      await WorkoutUiPreference.setTrainingDurationEnabled(true);
    },
  );

  testWidgets(
    'custom rest duration validates persists and marks the selected duration',
    (tester) async {
      _setExistingUserPreferences({
        'completion_check_enabled': true,
        'rest_timer_enabled': true,
        'rest_timer_seconds': 90,
      });
      await RestTimerPreference.load();
      await WorkoutUiPreference.load();
      await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.person_outline_rounded));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('trainingSettingsButton')),
      );
      await tester.tap(find.byKey(const Key('trainingSettingsButton')));
      await tester.pumpAndSettle();
      Future<void> openDurations() async {
        await tester.tap(find.byKey(const Key('restTimerDurationButton')));
        await tester.pumpAndSettle();
      }

      Future<void> openCustom() async {
        final custom = find.byKey(const Key('customRestDurationButton'));
        await tester.scrollUntilVisible(
          custom,
          120,
          scrollable: find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(custom);
        await tester.pumpAndSettle();
      }

      Finder field(String unit) => find.byKey(Key('customRest${unit}Field'));
      Future<void> enter(String minutes, String seconds) async {
        await tester.enterText(field('Minutes'), minutes);
        await tester.enterText(field('Seconds'), seconds);
        await tester.tap(find.byKey(const Key('saveCustomRestDurationButton')));
        await tester.pumpAndSettle();
      }

      await openDurations();
      for (final seconds in [30, 60, 90, 120, 180]) {
        expect(find.byKey(Key('restDurationPreset$seconds')), findsOneWidget);
      }
      expect(find.text('5分'), findsNothing);
      expect(
        tester
            .widget<ListTile>(find.byKey(const Key('restDurationPreset90')))
            .trailing,
        isNotNull,
      );
      await openCustom();
      String value(String unit) => tester
          .widget<EditableText>(
            find.descendant(
              of: field(unit),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text;
      expect(value('Minutes'), '1');
      expect(value('Seconds'), '30');
      for (final invalid in [
        ('0', '0'),
        ('0', '60'),
        ('60', '0'),
        ('-1', '0'),
        ('abc', '0'),
        ('1.5', '0'),
      ]) {
        await enter(invalid.$1, invalid.$2);
        expect(
          find.byKey(const Key('saveCustomRestDurationButton')),
          findsOneWidget,
        );
        expect(RestTimerPreference.seconds, 90);
      }
      await enter('5', '0');
      expect(RestTimerPreference.seconds, 300);
      expect(find.text('5分'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('rest_timer_seconds'), 300);
      await openDurations();
      await openCustom();
      expect(value('Minutes'), '5');
      expect(value('Seconds'), '0');
      await enter('4', '30');
      expect(RestTimerPreference.seconds, 270);
      expect(find.text('4分30秒'), findsOneWidget);
      RestTimerPreference.seconds = 90;
      await RestTimerPreference.load();
      expect(RestTimerPreference.seconds, 270);
      await openDurations();
      final custom = find.byKey(const Key('customRestDurationButton'));
      await tester.scrollUntilVisible(
        custom,
        120,
        scrollable: find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<ListTile>(custom).trailing, isNotNull);
      expect(
        tester
            .widget<ListTile>(find.byKey(const Key('restDurationPreset90')))
            .trailing,
        isNull,
      );
      await tester.tap(custom);
      await tester.pumpAndSettle();
      expect(value('Minutes'), '4');
      expect(value('Seconds'), '30');
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(RestTimerPreference.seconds, 270);
      await openDurations();
      await tester.tap(find.byKey(const Key('restDurationPreset90')));
      await tester.pumpAndSettle();
      await openDurations();
      await tester.scrollUntilVisible(
        custom,
        120,
        scrollable: find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<ListTile>(custom).trailing, isNull);
      expect(
        tester
            .widget<ListTile>(find.byKey(const Key('restDurationPreset90')))
            .trailing,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('custom rest duration survives the existing backup format', () {
    for (final seconds in [270, 300]) {
      final json = SetkeepBackup(
        workouts: const [],
        restTimerSeconds: seconds,
      ).toJson();
      expect(json['version'], 3);
      expect(SetkeepBackup.fromJson(json).restTimerSeconds, seconds);
    }
  });

  testWidgets(
    'custom rest duration starts and retains pause resume and extra seconds',
    (tester) async {
      _setExistingUserPreferences({
        'completion_check_enabled': true,
        'rest_timer_enabled': true,
        'rest_timer_seconds': 300,
      });
      await RestTimerPreference.load();
      await WorkoutUiPreference.load();
      await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('startWorkoutButton')));
      await tester.pumpAndSettle();
      expect(find.text('05:00'), findsOneWidget);
      await tester.tap(find.byKey(const Key('startRestTimerButton')));
      await tester.pump();
      expect(find.text('05:00'), findsOneWidget);
      await tester.tap(find.byKey(const Key('stopRestTimerButton')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('05:00'), findsOneWidget);
      await tester.tap(find.byKey(const Key('startRestTimerButton')));
      await tester.pump();
      expect(find.text('05:00'), findsOneWidget);
      await tester.tap(find.text('+30秒'));
      await tester.pump();
      expect(find.text('05:30'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('previously selected custom gym is migrated for reuse', (
    tester,
  ) async {
    _setExistingUserPreferences({'selected_gym': '以前の体育館'});
    CustomGymPreference.gyms = [];

    await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
    await tester.pumpAndSettle();

    expect(CustomGymPreference.gyms, ['以前の体育館']);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('custom_gyms'), contains('以前の体育館'));
  });

  testWidgets('legacy custom gyms remain selectable as manual places', (
    tester,
  ) async {
    _setExistingUserPreferences({
      'custom_gyms': jsonEncode(['中央体育館', '会社のジム']),
    });
    await CustomGymPreference.load();
    String? selected;
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                selected = await showGymPicker(context, null);
              },
              child: const Text('場所を選ぶ'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('場所を選ぶ'));
    await tester.pumpAndSettle();
    expect(find.text('中央体育館'), findsOneWidget);
    expect(find.text('会社のジム'), findsOneWidget);
    expect(find.text('ジムを追加'), findsOneWidget);

    await tester.tap(find.byKey(const Key('selectTrainingPlaceHome')));
    await tester.pumpAndSettle();
    expect(selected, '自宅');
    expect(CustomGymPreference.gyms, ['中央体育館', '会社のジム']);
  });

  testWidgets('location settings chooses a usual place without adding there', (
    tester,
  ) async {
    _setExistingUserPreferences({
      'custom_gyms': jsonEncode(['中央体育館']),
    });
    await CustomGymPreference.load();
    String? selectedGym;
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: CustomGymManagementPage(
          selectedGym: selectedGym,
          onSelectedGymChanged: (gym) async => selectedGym = gym,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('いつもの場所'), findsOneWidget);
    expect(find.text('カスタム場所'), findsNothing);
    expect(find.byKey(const Key('addCustomGymButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('preferredGym自宅')));
    await tester.pumpAndSettle();
    expect(selectedGym, '自宅');
    expect(CustomGymPreference.gyms, ['中央体育館']);
  });

  test('version 3 backup preserves workouts body weights and settings', () {
    final backup = SetkeepBackup(
      workouts: [
        WorkoutRecord(
          date: DateTime(2026, 9, 12, 18, 30),
          sets: const [
            RecordedSet(
              exerciseName: 'ベンチプレス',
              bodyPart: '胸',
              weight: 52.5,
              reps: 8,
              completed: true,
            ),
          ],
        ),
      ],
      workoutTemplates: const [
        SavedWorkoutTemplate(
          name: '胸の日',
          sets: [
            RecordedSet(
              exerciseName: 'ベンチプレス',
              bodyPart: '胸',
              weight: 52.5,
              reps: 8,
              completed: true,
            ),
          ],
        ),
      ],
      bodyWeights: [
        BodyWeightEntry(
          id: 'weight-1',
          recordedAt: DateTime(2026, 9, 12, 7),
          weightKg: 82.5,
        ),
      ],
      customExercises: const [
        ExerciseTemplate(
          name: 'テストプレス',
          bodyPart: '胸',
          equipment: 'カスタム',
          startWeight: 12.5,
        ),
      ],
      customGyms: const ['中央体育館'],
      selectedGym: 'テストジム',
      restTimerEnabled: true,
      restTimerSeconds: 120,
    );

    final restored = SetkeepBackup.fromJson(backup.toJson());

    expect(backup.toJson()['app'], 'SETKEEP');
    expect(backup.toJson()['version'], 3);
    expect(restored.workouts.single.sets.single.weight, 52.5);
    expect(restored.workoutTemplates.single.name, '胸の日');
    expect(restored.bodyWeights.single.weightKg, 82.5);
    expect(restored.customExercises.single.startWeight, 12.5);
    expect(restored.customGyms, ['中央体育館']);
    expect(restored.selectedGym, 'テストジム');
    expect(restored.restTimerEnabled, isTrue);
    expect(restored.restTimerSeconds, 120);

    final partiallyBroken = backup.toJson();
    (partiallyBroken['workoutTemplates'] as List<dynamic>).add({
      'name': '壊れたメニュー',
    });
    (partiallyBroken['customExercises'] as List<dynamic>).add({
      'name': '壊れた種目',
    });
    final safelyRestored = SetkeepBackup.fromJson(partiallyBroken);
    expect(safelyRestored.workoutTemplates, hasLength(1));
    expect(safelyRestored.customExercises, hasLength(1));
  });

  test('old history-only backups remain readable', () {
    final restored = SetkeepBackup.fromJson({
      'app': 'MuscleMemory',
      'version': 1,
      'workouts': <dynamic>[],
    });

    expect(restored.workouts, isEmpty);
    expect(restored.workoutTemplates, isEmpty);
    expect(restored.customGyms, isEmpty);
  });

  test('invalid and unsupported backups are rejected before import', () {
    expect(
      () => SetkeepBackup.fromJson({
        'app': 'SETKEEP',
        'version': 3,
        'workouts': 'invalid',
      }),
      throwsFormatException,
    );
    expect(
      () => SetkeepBackup.fromJson({
        'app': 'SETKEEP',
        'version': 99,
        'workouts': <dynamic>[],
      }),
      throwsFormatException,
    );
  });

  testWidgets('about page uses the official SETKEEP name', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AppAboutPage()));
    await tester.pumpAndSettle();

    expect(find.text('SETKEEP'), findsOneWidget);
    expect(find.text('バージョン 1.0.0'), findsOneWidget);
    expect(find.text('端末内への保存'), findsOneWidget);
    expect(find.text('クラウド同期'), findsOneWidget);
    expect(find.text('バックアップ'), findsOneWidget);
  });

  test('workout draft summary reads exercises date and set count', () {
    final summary = WorkoutDraftSummary.tryParse(
      jsonEncode({
        'date': '2026-09-12T18:30:00.000',
        'exercises': [
          {
            'name': 'ベンチプレス',
            'sets': [{}, {}, {}],
          },
          {
            'name': 'ラットプルダウン',
            'sets': [{}, {}],
          },
        ],
      }),
    );

    expect(summary, isNotNull);
    expect(summary!.exerciseNames, ['ベンチプレス', 'ラットプルダウン']);
    expect(summary.setCount, 5);
    expect(summary.date, DateTime(2026, 9, 12, 18, 30));
    expect(WorkoutDraftSummary.tryParse('broken'), isNull);
  });

  test('workouts are sorted newest first without changing the input list', () {
    WorkoutRecord workout(DateTime date) => WorkoutRecord(
      date: date,
      sets: const [
        RecordedSet(
          exerciseName: 'ベンチプレス',
          bodyPart: '胸',
          weight: 50,
          reps: 8,
          completed: true,
        ),
      ],
    );
    final old = workout(DateTime(2026, 1, 1));
    final newest = workout(DateTime(2026, 1, 3));
    final middle = workout(DateTime(2026, 1, 2));
    final input = [old, newest, middle];

    final sorted = sortWorkoutsNewestFirst(input);

    expect(sorted, [newest, middle, old]);
    expect(input, [old, newest, middle]);
  });

  test('latest exercise sets are selected independently of history order', () {
    WorkoutRecord workout(DateTime date, double weight, String exercise) =>
        WorkoutRecord(
          date: date,
          sets: [
            RecordedSet(
              exerciseName: exercise,
              bodyPart: '胸',
              weight: weight,
              reps: 8,
              completed: true,
            ),
          ],
        );
    final older = workout(DateTime(2026, 1, 1), 50, 'ベンチプレス');
    final unrelated = workout(DateTime(2026, 1, 5), 80, 'スクワット');
    final newest = workout(DateTime(2026, 1, 3), 60, 'ベンチプレス');

    final sets = latestSetsForExercise([older, unrelated, newest], 'ベンチプレス');

    expect(sets, hasLength(1));
    expect(sets.single.weight, 60);
    expect(latestSetsForExercise([older], 'スクワット'), isEmpty);
  });

  test('history search matches dates as well as workout details', () {
    final workout = WorkoutRecord(
      date: DateTime(2026, 9, 12, 18, 30),
      gymName: '中央体育館',
      note: 'フォーム確認',
      sets: const [
        RecordedSet(
          exerciseName: 'スクワット',
          bodyPart: '脚',
          weight: 80,
          reps: 5,
          completed: true,
        ),
      ],
    );

    expect(workoutMatchesQuery(workout, '2026年9月12日'), isTrue);
    expect(workoutMatchesQuery(workout, '2026-09-12'), isTrue);
    expect(workoutMatchesQuery(workout, '9/12'), isTrue);
    expect(workoutMatchesQuery(workout, '９・１２'), isTrue);
    expect(workoutMatchesQuery(workout, '体育館'), isTrue);
    expect(workoutMatchesQuery(workout, 'ベンチプレス'), isFalse);
  });

  testWidgets('history cards show the saved location and memo', (tester) async {
    final workout = WorkoutRecord(
      date: DateTime(2026, 9, 12),
      gymName: 'テストジム',
      note: 'フォームを丁寧に',
      sets: const [
        RecordedSet(
          exerciseName: 'ベンチプレス',
          bodyPart: '胸',
          weight: 50,
          reps: 8,
          completed: true,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HistoryCard(
            workout: workout,
            selectedGym: null,
            onWorkoutCompleted: (_) async {},
            onWorkoutUpdated: (_, _) async {},
            onWorkoutDeleted: (_) async => true,
          ),
        ),
      ),
    );

    expect(find.text('テストジム'), findsOneWidget);
    expect(find.text('フォームを丁寧に'), findsOneWidget);
  });

  testWidgets('history search shows result counts and can be cleared', (
    tester,
  ) async {
    WorkoutRecord workout(DateTime date, String exercise) => WorkoutRecord(
      date: date,
      sets: [
        RecordedSet(
          exerciseName: exercise,
          bodyPart: '胸',
          weight: 50,
          reps: 8,
          completed: true,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HistorySearchPage(
          history: [
            workout(DateTime(2026, 9, 12), 'ベンチプレス'),
            workout(DateTime(2026, 8, 3), 'ダンベルフライ'),
          ],
          selectedGym: null,
          onWorkoutCompleted: (_) async {},
          onWorkoutUpdated: (_, _) async {},
          onWorkoutDeleted: (_) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('全2件'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('historySearchField')), '9/12');
    await tester.pumpAndSettle();
    expect(find.text('1件の記録'), findsOneWidget);
    expect(find.text('ベンチプレス'), findsOneWidget);
    expect(find.text('ダンベルフライ'), findsNothing);

    await tester.tap(find.byTooltip('検索をクリア'));
    await tester.pumpAndSettle();
    expect(find.text('全2件'), findsOneWidget);
    expect(find.byType(HistoryCard), findsNWidgets(2));
  });

  testWidgets('removing home summaries preserves history detail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final workout = WorkoutRecord(
      date: DateTime.now(),
      gymName: 'テストジム',
      note: '肩を下げる',
      durationSeconds: 600,
      sets: const [
        RecordedSet(
          exerciseName: 'ラットプルダウン',
          bodyPart: '背中',
          weight: 45,
          reps: 10,
          completed: true,
        ),
      ],
    );
    _setExistingUserPreferences({
      'workout_history': jsonEncode([workout.toJson()]),
    });
    await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('lastWorkoutCard')), findsNothing);
    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('calendarDay${DateTime.now().day}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(HistoryCard));
    await tester.pumpAndSettle();

    expect(find.text('トレーニング詳細'), findsOneWidget);
    expect(find.text('ラットプルダウン'), findsOneWidget);
    expect(find.text('肩を下げる'), findsOneWidget);
    expect(find.text('この内容でもう一度'), findsOneWidget);
  });

  testWidgets('history can return to the current month in one tap', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MonthlyHistoryPage(
          history: const [],
          selectedGym: null,
          onWorkoutCompleted: (_) async {},
          onWorkoutUpdated: (_, _) async {},
          onWorkoutDeleted: (_) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final now = DateTime.now();
    expect(find.text('${now.year}年 ${now.month}月'), findsOneWidget);
    expect(find.byKey(const Key('historyCurrentMonthButton')), findsNothing);

    await tester.tap(find.byTooltip('前の月'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('historyCurrentMonthButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('historyCurrentMonthButton')));
    await tester.pumpAndSettle();
    expect(find.text('${now.year}年 ${now.month}月'), findsOneWidget);
    expect(find.byKey(const Key('historyCurrentMonthButton')), findsNothing);
  });

  testWidgets('an existing workout date can be changed', (tester) async {
    _setExistingUserPreferences({});
    final workout = WorkoutRecord(
      date: DateTime(2025, 3, 15, 19, 30),
      durationSeconds: 120,
      sets: const [
        RecordedSet(
          exerciseName: 'ベンチプレス',
          bodyPart: '胸',
          weight: 50,
          reps: 8,
          completed: true,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(home: WorkoutPage(initialWorkout: workout, isEditing: true)),
    );
    await tester.pumpAndSettle();

    expect(find.text('3.15（土）'), findsOneWidget);
    expect(find.text('2025年'), findsOneWidget);
    expect(find.text('2分'), findsOneWidget);
    final recordedTimer = tester
        .widget<Text>(find.byKey(const Key('workoutElapsedLabel')))
        .data;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 3));
    expect(
      tester.widget<Text>(find.byKey(const Key('workoutElapsedLabel'))).data,
      recordedTimer,
    );
    await tester.tap(find.byKey(const Key('workoutDateButton')));
    await tester.pumpAndSettle();
    expect(find.text('トレーニング日'), findsWidgets);
    await tester.tap(find.text('14'));
    await tester.tap(find.text('決定'));
    await tester.pumpAndSettle();

    expect(find.text('3.14（金）'), findsOneWidget);
  });

  testWidgets('editing history does not remove an active workout draft', (
    tester,
  ) async {
    const draftNote = 'あとで続けるトレーニング';
    final encodedDraft = jsonEncode({
      'date': DateTime.now().toIso8601String(),
      'note': draftNote,
      'exercises': [
        {
          'name': 'スクワット',
          'bodyPart': '脚',
          'equipment': 'フリーウェイト',
          'sets': [
            {'weight': 80, 'reps': 5, 'completed': false},
          ],
        },
      ],
    });
    _setExistingUserPreferences({activeWorkoutDraftStorageKey: encodedDraft});
    final workout = WorkoutRecord(
      date: DateTime(2025, 3, 15, 19, 30),
      sets: const [
        RecordedSet(
          exerciseName: 'ベンチプレス',
          bodyPart: '胸',
          weight: 50,
          reps: 8,
          completed: true,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(home: WorkoutPage(initialWorkout: workout, isEditing: true)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('completeWorkoutButton')));
    await tester.pumpAndSettle();
    expect(find.text('修正を保存'), findsOneWidget);
    await tester.tap(find.byKey(const Key('completeAndPreviewShareButton')));
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(activeWorkoutDraftStorageKey), encodedDraft);
  });

  test('saved workout templates persist', () async {
    _setExistingUserPreferences({});
    await WorkoutTemplatePreference.save([
      const SavedWorkoutTemplate(
        name: '胸の日',
        sets: [
          RecordedSet(
            exerciseName: 'ベンチプレス',
            bodyPart: '胸',
            weight: 50,
            reps: 8,
            completed: true,
          ),
        ],
      ),
    ]);

    final templates = await WorkoutTemplatePreference.load();
    expect(templates, hasLength(1));
    expect(templates.single.name, '胸の日');
    expect(templates.single.sets.single.weight, 50);
  });

  testWidgets('saved menus can be renamed reordered deleted and restored', (
    tester,
  ) async {
    const chest = SavedWorkoutTemplate(
      name: '胸の日',
      sets: [
        RecordedSet(
          exerciseName: 'ベンチプレス',
          bodyPart: '胸',
          weight: 50,
          reps: 8,
          completed: true,
        ),
      ],
    );
    const legs = SavedWorkoutTemplate(
      name: '脚の日',
      sets: [
        RecordedSet(
          exerciseName: 'スクワット',
          bodyPart: '脚',
          weight: 80,
          reps: 5,
          completed: true,
        ),
      ],
    );
    _setExistingUserPreferences({});
    var saved = <SavedWorkoutTemplate>[chest, legs];
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: SavedMenuManagementPage(
          initialTemplates: saved,
          onChanged: (templates) async {
            saved = List<SavedWorkoutTemplate>.from(templates);
            await WorkoutTemplatePreference.save(saved);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ベンチプレス ・ 1セット'), findsOneWidget);

    await tester.tap(find.byTooltip('胸の日の名前を変更'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('renameTemplateField')),
      '胸メイン',
    );
    await tester.tap(find.byKey(const Key('saveTemplateNameButton')));
    await tester.pumpAndSettle();
    expect(find.text('胸メイン'), findsOneWidget);
    expect(saved.first.name, '胸メイン');

    await tester.tap(find.byTooltip('胸メインの名前を変更'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('renameTemplateField')), '脚の日');
    await tester.tap(find.byKey(const Key('saveTemplateNameButton')));
    await tester.pumpAndSettle();
    expect(find.text('同じ名前のメニューがあります'), findsOneWidget);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('reorderMenu1')),
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
    expect(saved.first.name, '脚の日');

    await tester.tap(find.byTooltip('胸メインを削除'));
    await tester.pumpAndSettle();
    expect(saved.map((item) => item.name), ['脚の日']);
    expect(find.text('「胸メイン」を削除しました'), findsOneWidget);

    await tester.tap(find.text('元に戻す'));
    await tester.pumpAndSettle();
    expect(saved.map((item) => item.name), ['脚の日', '胸メイン']);
    final persisted = await WorkoutTemplatePreference.load();
    expect(persisted.map((item) => item.name), ['脚の日', '胸メイン']);
  });

  testWidgets('a menu is created directly with multiple ordered exercises', (
    tester,
  ) async {
    List<SavedWorkoutTemplate> saved = [];
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: SavedMenuManagementPage(
          initialTemplates: const [],
          onChanged: (templates) async => saved = templates,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('createSavedMenuButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('templateNameField')), '胸の日');
    await tester.tap(find.byKey(const Key('saveNewTemplateNameButton')));
    await tester.pumpAndSettle();
    await openExerciseCategory(tester, '胸');
    await selectPickerExercise(tester, 'bench_press');
    await tester.enterText(
      find.byKey(const Key('exerciseSearchField')),
      'ダンベルフライ',
    );
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('selectExercisedumbbell_fly')),
    );
    await tester.tap(find.byKey(const Key('selectExercisedumbbell_fly')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addSelectedExercises')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menuExerciseOrderList')), findsOneWidget);
    await tester.tap(find.byKey(const Key('saveCreatedMenuButton')));
    await tester.pumpAndSettle();

    expect(saved, hasLength(1));
    expect(saved.single.name, '胸の日');
    expect(saved.single.exerciseNames, ['ベンチプレス', 'ダンベルフライ']);
    expect(saved.single.sets, hasLength(2));
  });

  testWidgets('previous sets can be applied and completed together', (
    tester,
  ) async {
    _setExistingUserPreferences({});
    final initial = WorkoutRecord(
      date: DateTime(2025, 1, 1),
      sets: const [
        RecordedSet(
          exerciseName: 'ベンチプレス',
          bodyPart: '胸',
          weight: 40,
          reps: 10,
          completed: true,
        ),
      ],
    );
    final latest = WorkoutRecord(
      date: DateTime(2026, 2, 2),
      sets: const [
        RecordedSet(
          exerciseName: 'ベンチプレス',
          bodyPart: '胸',
          weight: 60,
          reps: 8,
          completed: true,
        ),
        RecordedSet(
          exerciseName: 'ベンチプレス',
          bodyPart: '胸',
          weight: 62.5,
          reps: 6,
          completed: true,
        ),
      ],
    );
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: WorkoutPage(history: [latest], initialWorkout: initial),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(
            find.descendant(
              of: find.byKey(const Key('weightField0_1')),
              matching: find.byType(TextFormField),
            ),
          )
          .initialValue,
      '40',
    );
    expect(find.text('完了 0 / 1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('applyPrevious0')));
    await tester.pumpAndSettle();
    expect(find.text('ベンチプレスに前回の記録を反映しました'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(
            find.descendant(
              of: find.byKey(const Key('weightField0_1')),
              matching: find.byType(TextFormField),
            ),
          )
          .initialValue,
      '60',
    );
    expect(
      tester
          .widget<TextFormField>(
            find.descendant(
              of: find.byKey(const Key('weightField0_2')),
              matching: find.byType(TextFormField),
            ),
          )
          .initialValue,
      '62.5',
    );
    expect(find.text('完了 0 / 2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('toggleAllSets0')));
    await tester.pumpAndSettle();
    expect(find.text('完了 2 / 2'), findsOneWidget);
    expect(find.text('すべて解除'), findsOneWidget);
    var preferences = await SharedPreferences.getInstance();
    var draft = jsonDecode(
      preferences.getString(activeWorkoutDraftStorageKey)!,
    ) as Map<String, dynamic>;
    var sets =
        (draft['exercises'] as List<dynamic>).first['sets'] as List<dynamic>;
    expect(sets.every((set) => set['completed'] == true), isTrue);

    await tester.tap(find.byKey(const Key('toggleAllSets0')));
    await tester.pumpAndSettle();
    expect(find.text('完了 0 / 2'), findsOneWidget);
    preferences = await SharedPreferences.getInstance();
    draft = jsonDecode(
      preferences.getString(activeWorkoutDraftStorageKey)!,
    ) as Map<String, dynamic>;
    sets = (draft['exercises'] as List<dynamic>).first['sets'] as List<dynamic>;
    expect(sets.every((set) => set['completed'] == false), isTrue);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('new workout starts empty and supports adding sets', (
    tester,
  ) async {
    _setExistingUserPreferences({});
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
    await tester.pumpAndSettle();

    expect(find.text('今日も積み上げよう'), findsNothing);
    await tester.tap(find.byKey(const Key('startWorkoutButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('emptyWorkoutExercises')), findsOneWidget);
    expect(find.text('種目はまだありません'), findsOneWidget);
    expect(find.text('ベンチプレス'), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('addExerciseButton')));
    await tester.tap(find.byKey(const Key('addExerciseButton')));
    await tester.pumpAndSettle();
    await openExerciseCategory(tester, '胸');
    await selectPickerExercise(tester, 'bench_press');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addSelectedExercises')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('emptyWorkoutExercises')), findsNothing);
    expect(find.text('ベンチプレス'), findsOneWidget);
    expect(find.byKey(const Key('weightField0_1')), findsOneWidget);
    expect(find.byKey(const Key('weightField0_2')), findsNothing);

    await tester.enterText(find.byKey(const Key('weightField0_1')), '42.5');
    expect(find.text('42.5'), findsOneWidget);

    await tester.tap(find.byKey(const Key('addSetButton')));
    await tester.pump();
    expect(find.byKey(const Key('weightField0_2')), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString('active_workout_draft'),
      contains('"weight":42.5'),
    );

    await tester.ensureVisible(find.byKey(const Key('deleteSet0_2')));
    await tester.tap(find.byKey(const Key('deleteSet0_2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('weightField0_2')), findsNothing);
  });

  testWidgets('an empty draft from any app version becomes a fresh workout', (
    tester,
  ) async {
    _setExistingUserPreferences({
      activeWorkoutDraftStorageKey: jsonEncode({
        'startedAt': DateTime.now()
            .subtract(const Duration(minutes: 10))
            .toIso8601String(),
        'elapsedSeconds': 600,
        'date': DateTime.now().toIso8601String(),
        'note': '',
        'exercises': <dynamic>[],
      }),
    });

    await tester.pumpWidget(const MaterialApp(home: WorkoutPage()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('emptyWorkoutExercises')), findsOneWidget);
    expect(find.textContaining('00:00 ・'), findsNothing);
    expect(find.byKey(const Key('workoutDateButton')), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(activeWorkoutDraftStorageKey), isNull);
  });

  testWidgets('disabled workout UI hides checks and timer but still saves', (
    tester,
  ) async {
    _setExistingUserPreferences({
      'completion_check_enabled': false,
      'workout_timer_enabled': false,
      'workout_duration_enabled': false,
    });
    await WorkoutUiPreference.load();
    addTearDown(() async {
      WorkoutUiPreference.completionCheckEnabled = true;
      WorkoutUiPreference.workoutTimerEnabled = true;
    });
    await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('startWorkoutButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('workoutElapsedLabel')), findsNothing);
    expect(find.byKey(const Key('workoutGymButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('addExerciseButton')));
    await tester.pumpAndSettle();
    await openExerciseCategory(tester, '胸');
    await selectPickerExercise(tester, 'bench_press');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addSelectedExercises')));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.circle_outlined), findsNothing);
    expect(find.byKey(const Key('toggleAllSets0')), findsNothing);
    await tester.tap(find.byKey(const Key('completeWorkoutButton')));
    await tester.pumpAndSettle();
    expect(find.text('1セットを記録しました。'), findsOneWidget);
  });

  testWidgets('active workout can be deleted without leaving a draft', (
    tester,
  ) async {
    _setExistingUserPreferences({});
    WorkoutUiPreference.completionCheckEnabled = true;
    WorkoutUiPreference.workoutTimerEnabled = true;
    await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('startWorkoutButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addExerciseButton')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('exerciseCategory脚')),
      180,
      scrollable: find
          .descendant(
            of: find.byType(ExercisePickerSheet),
            matching: find.byType(Scrollable),
          )
          .last,
    );
    await tester.pumpAndSettle();
    await openExerciseCategory(tester, '脚');
    await selectPickerExercise(tester, 'barbell_squat');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addSelectedExercises')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('deleteWorkoutDraftButton')));
    await tester.pumpAndSettle();
    expect(find.text('記録をすべて削除しますか？'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmDeleteWorkoutDraftButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('startWorkoutButton')), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(activeWorkoutDraftStorageKey), isNull);
  });

  testWidgets('last exercise can be removed and empty state stays stable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    _setExistingUserPreferences({});
    await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('startWorkoutButton')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('addExerciseButton')));
    await tester.tap(find.byKey(const Key('addExerciseButton')));
    await tester.pumpAndSettle();
    await openExerciseCategory(tester, '脚');
    await selectPickerExercise(tester, 'barbell_squat');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addSelectedExercises')));
    await tester.pumpAndSettle();

    expect(find.byTooltip('種目を削除'), findsOneWidget);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1100)),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byTooltip('種目を削除'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('emptyWorkoutExercises')), findsOneWidget);
    expect(find.text('スクワット'), findsNothing);
    expect(find.text('ベンチプレス'), findsNothing);
    expect(find.byTooltip('種目を削除'), findsNothing);
    final preferences = await SharedPreferences.getInstance();
    var savedDraft = preferences.getString(activeWorkoutDraftStorageKey);
    expect(savedDraft, contains('"exercises":[]'));
    expect(savedDraft, isNot(contains('ベンチプレス')));
    final savedDraftJson = jsonDecode(savedDraft!) as Map<String, dynamic>;
    expect(savedDraftJson['timerStopped'], isTrue);
    expect(savedDraftJson['elapsedSeconds'], isA<int>());

    expect(find.text('バーベルスクワットを削除しました'), findsOneWidget);

    final stoppedTimer = tester
        .widget<Text>(find.byKey(const Key('workoutElapsedLabel')))
        .data;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 3));
    expect(
      tester.widget<Text>(find.byKey(const Key('workoutElapsedLabel'))).data,
      stoppedTimer,
    );

    await tester.pump();
    expect(find.byKey(const Key('emptyWorkoutExercises')), findsOneWidget);
    expect(find.text('ベンチプレス'), findsNothing);

    await tester.tap(find.byKey(const Key('workoutDateButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('emptyWorkoutExercises')), findsOneWidget);
    expect(find.text('ベンチプレス'), findsNothing);

    savedDraft = preferences.getString(activeWorkoutDraftStorageKey);
    expect(savedDraft, contains('"exercises":[]'));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('completed workout appears in history', (tester) async {
    _setExistingUserPreferences({});
    await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('startWorkoutButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('completeWorkoutButton')));
    await tester.pump();
    expect(find.text('完了したセットを1つ以上チェックしてください'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('addExerciseButton')));
    await tester.tap(find.byKey(const Key('addExerciseButton')));
    await tester.pumpAndSettle();
    await openExerciseCategory(tester, '胸');
    await selectPickerExercise(tester, 'bench_press');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addSelectedExercises')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.circle_outlined).first);
    await tester.tap(find.byKey(const Key('completeWorkoutButton')));
    await tester.pumpAndSettle();
    expect(find.textContaining('自己ベスト更新'), findsOneWidget);
    expect(find.text('共有画像を確認'), findsOneWidget);
    expect(find.text('ホームへ戻る'), findsOneWidget);
    final stoppedTimer = tester
        .widget<Text>(find.byKey(const Key('workoutElapsedLabel')))
        .data;
    await tester.pump(const Duration(seconds: 3));
    expect(
      tester.widget<Text>(find.byKey(const Key('workoutElapsedLabel'))).data,
      stoppedTimer,
    );
    await tester.tap(find.text('ホームへ戻る'));
    await tester.pumpAndSettle();

    expect(find.text('クイックスタート'), findsNothing);

    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();
    expect(find.text('月間カレンダー'), findsOneWidget);
    expect(find.byKey(const Key('monthlyCalendar')), findsOneWidget);
    expect(find.text('トレーニング履歴'), findsNothing);
    expect(find.byTooltip('カレンダーで見る'), findsNothing);
    expect(find.byTooltip('履歴を検索'), findsOneWidget);
    expect(find.byTooltip('種目ごとの成長を見る'), findsNothing);

    final today = DateTime.now();
    await tester.tap(find.byKey(Key('calendarDay${today.day}')));
    await tester.pumpAndSettle();
    expect(find.text('${today.month}月${today.day}日の記録'), findsOneWidget);
    expect(find.text('ベンチプレス'), findsOneWidget);
  });

  testWidgets('deleted workout can be restored from history', (tester) async {
    final workout = WorkoutRecord(
      date: DateTime.now(),
      note: '削除復元テスト',
      sets: const [
        RecordedSet(
          exerciseName: 'スクワット',
          bodyPart: '脚',
          weight: 80,
          reps: 5,
          completed: true,
        ),
      ],
    );
    _setExistingUserPreferences({
      'workout_history': jsonEncode([workout.toJson()]),
    });
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('calendarDay${DateTime.now().day}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(HistoryCard));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('記録を削除'));
    await tester.pumpAndSettle();
    expect(find.text('削除後も直後なら元に戻せます。'), findsOneWidget);
    await tester.tap(find.text('削除'));
    await tester.pumpAndSettle();

    expect(find.text('トレーニング記録を削除しました'), findsOneWidget);
    expect(find.byType(HistoryCard), findsNothing);
    var preferences = await SharedPreferences.getInstance();
    expect(
      jsonDecode(preferences.getString('workout_history')!) as List<dynamic>,
      isEmpty,
    );

    await tester.tap(find.text('元に戻す'));
    await tester.pumpAndSettle();
    expect(find.text('トレーニング記録を元に戻しました'), findsOneWidget);
    expect(find.byType(HistoryCard), findsOneWidget);
    preferences = await SharedPreferences.getInstance();
    final restored =
        jsonDecode(preferences.getString('workout_history')!) as List<dynamic>;
    expect(restored, hasLength(1));
    expect(jsonEncode(restored.single), contains('削除復元テスト'));
  });

  testWidgets('deleted saved menu can be restored', (tester) async {
    const template = SavedWorkoutTemplate(
      name: '胸の日',
      sets: [
        RecordedSet(
          exerciseName: 'ベンチプレス',
          bodyPart: '胸',
          weight: 60,
          reps: 8,
          completed: true,
        ),
      ],
    );
    _setExistingUserPreferences({
      'workout_templates': jsonEncode([template.toJson()]),
    });
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('savedMenu0')), findsOneWidget);
    await tester.tap(find.byTooltip('胸の日を削除'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('savedMenu0')), findsNothing);
    expect(find.text('「胸の日」を削除しました'), findsOneWidget);

    var preferences = await SharedPreferences.getInstance();
    var savedMenus = jsonDecode(
      preferences.getString('workout_templates')!,
    ) as List<dynamic>;
    expect(savedMenus, isEmpty);

    await tester.tap(find.text('元に戻す'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('savedMenu0')), findsOneWidget);
    expect(find.text('「胸の日」を元に戻しました'), findsOneWidget);

    preferences = await SharedPreferences.getInstance();
    savedMenus = jsonDecode(
      preferences.getString('workout_templates')!,
    ) as List<dynamic>;
    expect(savedMenus, hasLength(1));
    expect((savedMenus.single as Map<String, dynamic>)['name'], '胸の日');
  });

  testWidgets('rest timer only starts when enabled', (tester) async {
    final platformCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          platformCalls.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    _setExistingUserPreferences({
      'rest_timer_enabled': false,
      'rest_timer_seconds': 60,
    });
    await RestTimerPreference.load();
    await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('startWorkoutButton')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('addExerciseButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addExerciseButton')));
    await tester.pumpAndSettle();
    await openExerciseCategory(tester, '胸');
    await selectPickerExercise(tester, 'bench_press');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addSelectedExercises')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.circle_outlined).first);
    await tester.pump();
    expect(find.byKey(const Key('restTimerBanner')), findsNothing);

    await tester.pumpWidget(const SizedBox());
    _setExistingUserPreferences({
      'rest_timer_enabled': true,
      'rest_timer_seconds': 1,
    });
    await RestTimerPreference.load();
    await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('startWorkoutButton')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('addExerciseButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addExerciseButton')));
    await tester.pumpAndSettle();
    await openExerciseCategory(tester, '胸');
    await selectPickerExercise(tester, 'bench_press');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addSelectedExercises')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.circle_outlined).first);
    await tester.pump();

    expect(find.byKey(const Key('restTimerBanner')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('startRestTimerButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('startRestTimerButton')));
    await tester.pump();
    expect(find.text('00:01'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(
      platformCalls.any((call) => call.method == 'SystemSound.play'),
      isTrue,
    );
  });

  testWidgets('workout draft is saved and leaving asks for confirmation', (
    tester,
  ) async {
    _setExistingUserPreferences({});
    await RestTimerPreference.load();
    await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('startWorkoutButton')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('addExerciseButton')));
    await tester.tap(find.byKey(const Key('addExerciseButton')));
    await tester.pumpAndSettle();
    await openExerciseCategory(tester, '胸');
    await selectPickerExercise(tester, 'bench_press');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addSelectedExercises')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('weightField0_1')), '55');
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString('active_workout_draft'),
      contains('"weight":55'),
    );
    expect(preferences.getString('active_workout_draft'), contains('"date":'));

    // The first system back closes the app's numeric keypad.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('workoutNumericKeypad')), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('トレーニングを中断しますか？'), findsOneWidget);
    await tester.tap(find.text('入力を続ける'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('completeWorkoutButton')), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('トレーニングを中断しますか？'), findsOneWidget);
    expect(find.textContaining('入力内容は自動保存'), findsOneWidget);

    await tester.tap(find.text('中断する'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('activeWorkoutDraftCard')), findsOneWidget);
    expect(find.text('入力途中のトレーニング'), findsOneWidget);
    expect(find.text('新しいトレーニングを始める'), findsOneWidget);

    var pausedDraft = jsonDecode(
      preferences.getString(activeWorkoutDraftStorageKey)!,
    ) as Map<String, dynamic>;
    final pausedElapsed = pausedDraft['elapsedSeconds'];
    expect(pausedElapsed, isA<int>());
    await tester.pump(const Duration(seconds: 3));
    pausedDraft = jsonDecode(
      preferences.getString(activeWorkoutDraftStorageKey)!,
    ) as Map<String, dynamic>;
    expect(pausedDraft['elapsedSeconds'], pausedElapsed);

    await tester.tap(find.byKey(const Key('activeWorkoutDraftCard')));
    await tester.pumpAndSettle();
    expect(find.text('入力途中のトレーニングを再開しました'), findsOneWidget);
    expect(find.text('55'), findsOneWidget);
  });

  testWidgets('saved menu start protects a draft and starts with today', (
    tester,
  ) async {
    _setExistingUserPreferences({
      activeWorkoutDraftStorageKey: jsonEncode({
        'date': DateTime.now().toIso8601String(),
        'note': '',
        'exercises': [
          {
            'name': 'ベンチプレス',
            'bodyPart': '胸',
            'equipment': 'フリーウェイト',
            'sets': [
              {'weight': 55, 'reps': 8, 'completed': false},
            ],
          },
        ],
      }),
    });
    var discarded = false;
    final oldWorkout = WorkoutRecord(
      date: DateTime(2024, 1, 2, 18, 30),
      sets: const [
        RecordedSet(
          exerciseName: 'ラットプルダウン',
          bodyPart: '背中',
          weight: 45,
          reps: 10,
          completed: true,
        ),
      ],
    );
    final draft = WorkoutDraftSummary(
      date: DateTime.now(),
      exerciseNames: const ['ベンチプレス'],
      setCount: 3,
    );
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardPage(
            history: [oldWorkout],
            selectedGym: null,
            onGymChanged: (_) {},
            onWorkoutCompleted: (_) async {},
            onWorkoutUpdated: (_, _) async {},
            onWorkoutDeleted: (_) async => true,
            workoutTemplates: [
              SavedWorkoutTemplate(name: '背中メニュー', sets: oldWorkout.sets),
            ],
            onTemplateSaved: (_) async {},
            onTemplateDeleted: (_) async {},
            workoutDraft: draft,
            onDraftChanged: () async {},
            onDraftDiscarded: () async => discarded = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('savedMenu0')));
    await tester.tap(find.byKey(const Key('savedMenu0')));
    await tester.pumpAndSettle();
    expect(find.text('新しく始めますか？'), findsOneWidget);
    expect(find.text('入力途中の内容は破棄されます。'), findsOneWidget);

    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(discarded, isFalse);
    expect(find.byKey(const Key('activeWorkoutDraftCard')), findsOneWidget);
    var preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(activeWorkoutDraftStorageKey), isNotNull);

    await tester.tap(find.byKey(const Key('savedMenu0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('破棄して始める'));
    await tester.pumpAndSettle();
    expect(discarded, isTrue);
    preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(activeWorkoutDraftStorageKey), isNull);
    expect(find.text('ラットプルダウン'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('workoutDateValue'))).data,
      startsWith('${DateTime.now().month}.${DateTime.now().day}（'),
    );
    expect(find.text('2024年1月2日'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('repeating from history protects the active draft', (
    tester,
  ) async {
    _setExistingUserPreferences({
      activeWorkoutDraftStorageKey: jsonEncode({
        'date': DateTime.now().toIso8601String(),
        'note': '残したいメモ',
        'exercises': [
          {
            'name': 'ベンチプレス',
            'bodyPart': '胸',
            'equipment': 'フリーウェイト',
            'sets': [
              {'weight': 60, 'reps': 8, 'completed': false},
            ],
          },
        ],
      }),
    });
    final workout = WorkoutRecord(
      date: DateTime(2025, 3, 15, 18),
      sets: const [
        RecordedSet(
          exerciseName: 'スクワット',
          bodyPart: '脚',
          weight: 80,
          reps: 5,
          completed: true,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WorkoutDetailPage(
          workout: workout,
          selectedGym: null,
          onWorkoutCompleted: (_) async {},
          onWorkoutUpdated: (_, _) async {},
          onWorkoutDeleted: (_) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('repeatWorkoutButton')));
    await tester.pumpAndSettle();
    expect(find.text('入力途中の内容は破棄されます。'), findsOneWidget);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    var preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(activeWorkoutDraftStorageKey),
      contains('残したいメモ'),
    );

    await tester.tap(find.byKey(const Key('repeatWorkoutButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('破棄して始める'));
    await tester.pumpAndSettle();
    preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(activeWorkoutDraftStorageKey), isNull);
    expect(find.text('スクワット'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('workoutDateValue'))).data,
      startsWith('${DateTime.now().month}.${DateTime.now().day}（'),
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'frozen draft restores exact duration without rewriting its date',
    (tester) async {
      final draft = jsonEncode({
        'startedAt': DateTime(2025, 1, 1).toIso8601String(),
        'elapsedSeconds': 543,
        'timerStopped': true,
        'date': DateTime(2026, 8, 1).toIso8601String(),
        'note': '確定したメモ',
        'exercises': [
          {
            'name': 'ベンチプレス',
            'bodyPart': '胸',
            'equipment': 'フリーウェイト',
            'sets': [
              {'weight': 55, 'reps': 8, 'completed': false},
            ],
          },
        ],
      });
      _setExistingUserPreferences({activeWorkoutDraftStorageKey: draft});
      await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('activeWorkoutDraftCard')));
      await tester.pumpAndSettle();
      final label = find.byKey(const Key('workoutElapsedLabel'));
      expect(tester.widget<Text>(label).data, contains('09:03'));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 10));
      expect(tester.widget<Text>(label).data, contains('09:03'));
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString(activeWorkoutDraftStorageKey), draft);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('removing the final set freezes time including after undo', (
    tester,
  ) async {
    _setExistingUserPreferences({
      activeWorkoutDraftStorageKey: jsonEncode({
        'elapsedSeconds': 123,
        'timerStopped': false,
        'date': DateTime.now().toIso8601String(),
        'exercises': [
          {
            'name': 'ベンチプレス',
            'bodyPart': '胸',
            'equipment': 'フリーウェイト',
            'sets': [
              {'weight': 55, 'reps': 8, 'completed': false},
            ],
          },
        ],
      }),
    });
    await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('activeWorkoutDraftCard')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('セットを削除'));
    await tester.pumpAndSettle();
    final preferences = await SharedPreferences.getInstance();
    final frozen = jsonDecode(
      preferences.getString(activeWorkoutDraftStorageKey)!,
    ) as Map<String, dynamic>;
    expect(frozen['timerStopped'], true);
    final label = find.byKey(const Key('workoutElapsedLabel'));
    final elapsed = tester.widget<Text>(label).data;
    await tester.tap(find.text('元に戻す'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    expect(tester.widget<Text>(label).data, elapsed);
    expect(find.byTooltip('セットを削除'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('resumed draft keeps its elapsed time', (tester) async {
    final startedAt = DateTime.now().subtract(const Duration(minutes: 5));
    _setExistingUserPreferences({
      activeWorkoutDraftStorageKey: jsonEncode({
        'startedAt': startedAt.toIso8601String(),
        'date': DateTime.now().toIso8601String(),
        'note': '再開テスト',
        'exercises': [
          {
            'name': 'ベンチプレス',
            'bodyPart': '胸',
            'equipment': 'フリーウェイト',
            'sets': [
              {'weight': 55, 'reps': 8, 'completed': false},
            ],
          },
        ],
      }),
    });
    await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('activeWorkoutDraftCard')));
    await tester.pumpAndSettle();
    expect(find.textContaining('05:0'), findsOneWidget);
    expect(find.text('55'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  test(
    'body weights keep multiple entries on the same date and skip missing days',
    () {
      final now = DateTime(2026, 9, 13, 12);
      final entries = [
        BodyWeightEntry(
          id: 'old',
          recordedAt: DateTime(2026, 5, 1),
          weightKg: 84,
        ),
        BodyWeightEntry(
          id: 'morning',
          recordedAt: DateTime(2026, 9, 12, 8),
          weightKg: 82.5,
        ),
        BodyWeightEntry(
          id: 'night',
          recordedAt: DateTime(2026, 9, 12, 21),
          weightKg: 82.1,
        ),
      ];

      final shown = bodyWeightsForPeriod(
        entries,
        BodyWeightPeriod.oneMonth,
        now: now,
      );

      expect(shown.map((entry) => entry.id), ['morning', 'night']);
      expect(shown.map((entry) => entry.weightKg), [82.5, 82.1]);
    },
  );

  testWidgets('body weight can be saved and appears in the history chart', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final entries = ValueNotifier<List<BodyWeightEntry>>([]);
    addTearDown(entries.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ValueListenableBuilder<List<BodyWeightEntry>>(
              valueListenable: entries,
              builder: (context, value, _) => BodyWeightTrendSection(
                entries: value,
                onSaved: (entry) async {
                  entries.value = [entry];
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('addBodyWeightButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('deleteBodyWeightButton')), findsNothing);
    await tester.enterText(find.byKey(const Key('bodyWeightField')), '82.5');
    await tester.tap(find.byKey(const Key('saveBodyWeightButton')));
    await tester.pumpAndSettle();

    expect(entries.value.single.weightKg, 82.5);
    expect(find.byKey(const Key('bodyWeightChart')), findsOneWidget);
    expect(find.text('82.5 kg'), findsOneWidget);

    final originalId = entries.value.single.id;
    await tester.tap(find.byTooltip('体重を編集'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('bodyWeightField')), '81.9');
    await tester.tap(find.byKey(const Key('saveBodyWeightButton')));
    await tester.pumpAndSettle();
    expect(entries.value, hasLength(1));
    expect(entries.value.single.id, originalId);
    expect(entries.value.single.weightKg, 81.9);
  });

  testWidgets('SNS preview contains exercise data without workout totals', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final workout = WorkoutRecord(
      date: DateTime(2026, 9, 13),
      durationSeconds: 1800,
      sets: const [
        RecordedSet(
          exerciseName: 'チェストプレス',
          bodyPart: '胸',
          weight: 50,
          reps: 10,
          completed: true,
        ),
        RecordedSet(
          exerciseName: 'インクラインダンベルプレス（スローテンポ・ワイドグリップ）',
          bodyPart: '胸',
          weight: 12.5,
          reps: 12,
          completed: true,
        ),
        RecordedSet(
          exerciseName: 'チェストプレス',
          bodyPart: '胸',
          weight: 55,
          reps: 8,
          completed: true,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: WorkoutSharePage(workout: workout)),
    );
    await tester.pumpAndSettle();

    expect(find.text('チェストプレス'), findsOneWidget);
    expect(find.text('55 kg × 8 回  /  2 セット'), findsOneWidget);
    expect(find.text('インクラインダンベルプレス（スローテンポ・ワイドグリップ）'), findsOneWidget);
    expect(find.text('総ボリューム'), findsNothing);
    expect(find.text('トレーニング時間'), findsNothing);
    expect(find.byKey(const Key('chooseSharePhotoButton')), findsOneWidget);
    expect(find.byKey(const Key('shareWorkoutImageButton')), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    final brand = find.byKey(const Key('shareBrandLogo'));
    expect(brand, findsOneWidget);
    final mark = tester.widget<Image>(brand);
    expect(
      (mark.image as AssetImage).assetName,
      'assets/brand/setkeep_share_lockup.png',
    );
    expect(mark.width, 84);
    expect(mark.height, 52);
    expect(mark.fit, BoxFit.contain);
    expect(find.textContaining('TRAIN TODAY. KEEP GROWING.'), findsNothing);
    final longTitle = tester.widget<Text>(
      find.text('インクラインダンベルプレス（スローテンポ・ワイドグリップ）'),
    );
    expect(longTitle.maxLines, 1);
    expect(longTitle.style?.fontSize, 16);
    expect(longTitle.style?.fontWeight, FontWeight.w900);
    final recordLine = tester.widget<Text>(find.text('55 kg × 8 回  /  2 セット'));
    expect(recordLine.style?.fontSize, 13);
    expect(recordLine.style?.fontWeight, FontWeight.w700);
    final date = tester.widget<Text>(find.text('2026.09.13'));
    expect(date.style?.fontSize, 12);
    expect(tester.takeException(), isNull);

    expect(find.byKey(const Key('shareVolumeToggle')), findsNothing);
    expect(find.byKey(const Key('shareDurationToggle')), findsNothing);
  });

  testWidgets(
    'body weight deletion persists without changing workout history',
    (tester) async {
      final history = jsonEncode([
        WorkoutRecord(
          date: DateTime(2026, 9, 1),
          sets: const [RecordedSet(weight: 50, reps: 8, completed: true)],
        ).toJson(),
      ]);
      _setExistingUserPreferences({'workout_history': history});
      await BodyWeightPreference.save([
        BodyWeightEntry(
          id: 'delete-me',
          recordedAt: DateTime.now(),
          weightKg: 80,
        ),
      ]);
      await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
      await tester.pumpAndSettle();
      final edit = find.byKey(const Key('editBodyWeightdelete-me'));
      await tester.scrollUntilVisible(
        edit,
        200,
        scrollable: find
            .descendant(
              of: find.byType(DashboardPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deleteBodyWeightButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmDeleteBodyWeightButton')));
      await tester.pumpAndSettle();
      expect(await BodyWeightPreference.load(), isEmpty);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('workout_history'), history);
      expect(find.text('体重を記録するとグラフが表示されます'), findsOneWidget);
    },
  );

  testWidgets('body weight trend appears on home but not history', (
    tester,
  ) async {
    _setExistingUserPreferences({
      'body_weight_entries': jsonEncode([
        BodyWeightEntry(
          id: 'home-weight',
          recordedAt: DateTime(2026, 9, 15),
          weightKg: 82.5,
        ).toJson(),
      ]),
    });
    await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bodyWeightTrendSection')), findsOneWidget);

    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bodyWeightTrendSection')), findsNothing);
    expect(find.byKey(const Key('monthlyCalendar')), findsOneWidget);
  });

  testWidgets('contact form is available from profile', (tester) async {
    _setExistingUserPreferences(const {});
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.person_outline_rounded));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('contactButton')));
    await tester.tap(find.byKey(const Key('contactButton')));
    await tester.pumpAndSettle();

    expect(find.text('不具合報告'), findsOneWidget);
    expect(find.text('機能要望'), findsNothing);
    expect(find.byKey(const Key('contactSubjectField')), findsOneWidget);
    expect(find.byKey(const Key('contactMessageField')), findsOneWidget);
    expect(find.byKey(const Key('contactImageButton')), findsOneWidget);
    expect(find.byKey(const Key('sendContactButton')), findsOneWidget);
  });

  testWidgets('weekly goal UI is removed', (tester) async {
    _setExistingUserPreferences(const {});
    await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
    await tester.pumpAndSettle();
    expect(find.text('1週間の目標'), findsNothing);
  });
}
