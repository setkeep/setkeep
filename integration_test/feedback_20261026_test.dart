import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setkeep/main.dart';
import 'package:setkeep/design/family_theme.dart';
import 'package:setkeep/exercise_media_form_view.dart';
import 'package:setkeep/gym/gym_pages.dart';
import 'package:setkeep/gym/gym_repository.dart';
import 'package:setkeep/gym/training_place_preference.dart';

// Dedicated QA devices only. Real preferences, two separate process launches.
const _phase = 'qa_feedback_20261026_favorites';
const _backup = 'qa_feedback_20261026_favorites_backup';
const _gym = GymStore(
  id: 'qa-a',
  chainName: 'KANEKIN FITNESS GYM',
  name: '松戸店',
);

class _Gyms extends GymRepository {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
  @override
  Future<List<GymStore>> registered() async => [
    _gym,
    const GymStore(id: 'qa-b', chainName: 'FIT PLACE24', name: '市川店'),
  ];
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var secondLaunch = false;
  WidgetController.hitTestWarningShouldBeFatal = true;
  const rest = MethodChannel('com.setkeep.app/rest_timer');
  Future<Map<String, dynamic>> status() async =>
      (await rest.invokeMapMethod<String, dynamic>('debugStatus'))!;
  Future<void> pause(int seconds) =>
      Future<void>.delayed(Duration(seconds: seconds));
  Future<void> capture(String label) async {
    debugPrint('QA_FEEDBACK_CAPTURE_$label');
    if (Platform.isIOS) await binding.takeScreenshot(label);
    await pause(
      3,
    ); // Host captures Android without changing the Flutter surface.
  }

  testWidgets('favorites survive a real process restart and the next workout', (
    t,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    secondLaunch = prefs.getBool(_phase) == true;
    if (!secondLaunch) {
      await prefs.setStringList(
        _backup,
        (await ExerciseFavoritePreference.load()).toList(),
      );
      await ExerciseFavoritePreference.setFavorite('id:bench_press', true);
      await ExerciseFavoritePreference.setFavorite('id:wall_sit', true);
      await prefs.setBool(_phase, true);
      debugPrint('QA_FAVORITES_FIRST_PROCESS_SAVED');
      return;
    }
    final favorites = await ExerciseFavoritePreference.load();
    expect(favorites, containsAll(['id:bench_press', 'id:wall_sit']));
    Future<void> checkPicker() async {
      await t.enterText(find.byKey(const Key('exerciseSearchField')), 'ベンチプレス');
      await t.pumpAndSettle();
      final star = find.byKey(const Key('favoriteExerciseid:bench_press'));
      await t.ensureVisible(star);
      expect(
        find.descendant(of: star, matching: find.byIcon(Icons.star_rounded)),
        findsOneWidget,
      );
    }

    await t.pumpWidget(
      MaterialApp(
        theme: familyTheme(),
        home: Scaffold(body: ExercisePickerSheet()),
      ),
    );
    await t.pumpAndSettle();
    await checkPicker();
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
    await t.pumpWidget(
      MaterialApp(theme: familyTheme(), home: WorkoutPage(resumeDraft: false)),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('addExerciseButton')));
    await t.pumpAndSettle();
    await checkPicker();
    await capture('favorites_next_workout');
    final previousPicker = t.element(find.byType(ExercisePickerSheet));
    FocusManager.instance.primaryFocus?.unfocus();
    await pause(1);
    await t.pumpAndSettle();
    final sheet = t.getRect(find.byType(BottomSheet));
    await t.tapAt(Offset(4, sheet.top / 2));
    await t.pumpAndSettle();
    expect(find.byType(ExercisePickerSheet), findsNothing);
    final add = find.byKey(const Key('addExerciseButton'));
    await t.ensureVisible(add);
    await t.pumpAndSettle();
    await t.tap(add);
    await t.pumpAndSettle();
    await checkPicker();
    expect(
      identical(t.element(find.byType(ExercisePickerSheet)), previousPicker),
      isFalse,
    );
    expect(await ExerciseFavoritePreference.load(), favorites);
    debugPrint('QA_FAVORITES_RESTART_NEXT_WORKOUT_REOPEN_PASS');
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
    await ExerciseFavoritePreference.save(
      (prefs.getStringList(_backup) ?? []).toSet(),
    );
    await prefs.remove(_backup);
    await prefs.remove(_phase);
  });

  testWidgets('native guide navigation retains edited values and timer', (
    t,
  ) async {
    if (!secondLaunch) return;
    WorkoutUiPreference.completionCheckEnabled = true;
    WorkoutUiPreference.workoutTimerEnabled = false;
    WorkoutUiPreference.workoutDurationEnabled = false;
    RestTimerPreference.enabled = true;
    RestTimerPreference.seconds = 90;
    await RestNotificationService.cancel();
    await t.pumpWidget(
      MaterialApp(
        theme: familyTheme(),
        navigatorObservers: [exerciseMediaRouteObserver],
        home: WorkoutPage(
          resumeDraft: false,
          initialWorkout: WorkoutRecord(
            date: DateTime.now(),
            sets: const [
              RecordedSet(
                exerciseId: 'bench_press',
                exerciseName: 'ベンチプレス',
                bodyPart: '胸',
                weight: 40,
                reps: 10,
                completed: true,
              ),
              RecordedSet(
                exerciseId: 'bench_press',
                exerciseName: 'ベンチプレス',
                bodyPart: '胸',
                weight: 40,
                reps: 10,
                completed: true,
              ),
            ],
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final weight = find.descendant(
      of: find.byKey(const Key('weightField0_1')),
      matching: find.byType(TextFormField),
    );
    await t.ensureVisible(weight);
    await t.pumpAndSettle();
    await t.enterText(weight, '72.5');
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pumpAndSettle();
    final check = find.byKey(const Key('toggleSet0_1'));
    await t.ensureVisible(check);
    await t.pumpAndSettle();
    await t.tap(check);
    await t.pumpAndSettle();
    final before = await RestNotificationService.state();
    expect(
      before!['endsAtMilliseconds'],
      greaterThan(DateTime.now().millisecondsSinceEpoch),
    );
    final guide = find.byKey(const Key('workoutExerciseGuideid:bench_press'));
    await t.ensureVisible(guide);
    await t.pumpAndSettle();
    await t.tap(guide);
    await t.pumpAndSettle();
    expect(
      t
          .widget<ExerciseMuscleDetailPage>(
            find.byType(ExerciseMuscleDetailPage),
          )
          .exercise
          .exerciseId,
      'bench_press',
    );
    await pause(3);
    await capture('bench_guide');
    await t.pageBack();
    await t.pumpAndSettle();
    expect(
      t
          .widget<ExerciseInputCard>(find.byType(ExerciseInputCard))
          .exercise
          .sets
          .first
          .weight,
      72.5,
    );
    final after = await RestNotificationService.state();
    expect(after!['endsAtMilliseconds'], before['endsAtMilliseconds']);
    debugPrint('QA_GUIDE_INPUT_DEADLINE_PRESERVED');
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
    await RestNotificationService.cancel();
  });

  testWidgets('detail tap rotates the native mannequin front and back', (
    t,
  ) async {
    if (!secondLaunch) return;
    await t.pumpWidget(
      MaterialApp(
        theme: familyTheme(),
        home: ExerciseMuscleDetailPage(
          exercise: ExerciseTemplate(
            exerciseId: 'custom:qa',
            name: 'QA種目',
            bodyPart: '背中',
            equipment: '',
            startWeight: 0,
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await pause(5);
    await t.pump();
    const models = MethodChannel('interactive_3d_plugin');
    if (Platform.isAndroid) {
      final states = await models.invokeListMethod<dynamic>(
        'debugCameraStates',
      );
      expect(states, isNotEmpty);
      expect(states!.single['angle'], 0);
      expect(states.single['successfulFrames'], greaterThan(0));
    }
    await capture('mannequin_front');
    await t.tap(find.byKey(const Key('muscleMannequinFrame')));
    await t.pumpAndSettle();
    await pause(3);
    if (Platform.isAndroid) {
      final states = await models.invokeListMethod<dynamic>(
        'debugCameraStates',
      );
      expect(states!.single['angle'], 2);
      expect(states.single['successfulFrames'], greaterThan(0));
      debugPrint('QA_MANNEQUIN_NATIVE_BACK ${jsonEncode(states)}');
    }
    await capture('mannequin_back');
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
  });

  testWidgets('location B is usable on native screen', (t) async {
    if (!secondLaunch) return;
    final oldPlace = await TrainingPlacePreference.load();
    GymServices.override = _Gyms();
    await TrainingPlacePreference.save(const TrainingPlace.store(_gym));
    try {
      await t.pumpWidget(
        MaterialApp(theme: familyTheme(), home: RegisteredGymsPage()),
      );
      await t.pumpAndSettle();
      expect(
        find.byKey(const Key('preferredTrainingPlaceCard')),
        findsOneWidget,
      );
      await capture('location_B');
      expect(t.takeException(), isNull);
    } finally {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      GymServices.override = null;
      await TrainingPlacePreference.save(oldPlace);
    }
  });

  testWidgets(
    'Android locked deadline completes before any resume or state read',
    (t) async {
      if (!secondLaunch ||
          !Platform.isAndroid ||
          !const bool.fromEnvironment('FEEDBACK_LOCK_HOST_QA')) {
        return;
      }
      await t.pumpWidget(
        MaterialApp(
          theme: familyTheme(),
          home: Scaffold(body: Text('休憩タイマー QA')),
        ),
      );
      await RestNotificationService.cancel();
      final before = await status();
      await RestNotificationService.schedule(12, exerciseName: 'QA休憩');
      final running = await status();
      expect(running['alarmSchedulingMode'], 'exact');
      debugPrint('QA_FEEDBACK_LOCK_READY');
      await pause(16);
      // debugStatus does not complete overdue timers; state() and resume would.
      final ended = await status();
      // The host records screen/idle state before waking the device. Dart
      // timers and the VM connection may be suspended during deep Doze.
      expect(ended['lastCompletionTimerId'], running['timerId']);
      expect(
        ended['lastCompletionAt'],
        lessThanOrEqualTo((running['deadline'] as int) + 2000),
      );
      expect(
        ended['completionCount'],
        (before['completionCount'] as int? ?? 0) + 1,
      );
      expect(ended['lastCompletionPath'], 'background_notification');
      expect(ended['remainingSeconds'], 0);
      debugPrint('QA_LOCKED_COMPLETED_BEFORE_RESUME ${jsonEncode(ended)}');
      debugPrint('QA_FEEDBACK_UNLOCK_READY');
      await pause(4);
      final resumed = await RestNotificationService.state();
      expect(resumed!['endsAtMilliseconds'], 0);
      expect(resumed['remainingSeconds'], 0);
      await RestNotificationService.cancel();
    },
  );
}
