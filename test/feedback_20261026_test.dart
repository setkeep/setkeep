import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/main.dart';
import 'package:setkeep/exercise_media_form_view.dart';
import 'package:setkeep/gym/gym_pages.dart';
import 'package:setkeep/gym/gym_repository.dart';
import 'package:setkeep/gym/training_place_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _Video extends VideoPlayerPlatform {
  final streams = <int, StreamController<VideoEvent>>{};
  final sources = <DataSource>[];
  @override
  Future<void> init() async {}
  @override
  Future<void> setMixWithOthers(bool value) async {}
  @override
  Future<int?> create(DataSource source) async {
    sources.add(source);
    final id = sources.length;
    streams[id] = StreamController<VideoEvent>()
      ..add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          size: const Size(512, 512),
          duration: const Duration(seconds: 8),
        ),
      );
    return id;
  }

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) =>
      create(options.dataSource);
  @override
  Stream<VideoEvent> videoEventsFor(int id) => streams[id]!.stream;
  @override
  Widget buildView(int id) => const ColoredBox(color: Colors.white);
  @override
  Future<void> dispose(int id) async {
    await streams.remove(id)?.close();
  }

  @override
  Future<void> play(int id) async {}
  @override
  Future<void> pause(int id) async {}
  @override
  Future<void> setLooping(int id, bool value) async {}
  @override
  Future<void> setVolume(int id, double value) async {}
  @override
  Future<void> setPlaybackSpeed(int id, double value) async {}
  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(
    int id,
    bool value,
  ) async {}
  @override
  Future<Duration> getPosition(int id) async => Duration.zero;
}

const _gymA = GymStore(
  id: 'qa-a',
  chainName: 'KANEKIN FITNESS GYM',
  name: '松戸店',
);
const _gymB = GymStore(id: 'qa-b', chainName: 'FIT PLACE24', name: '市川店');

class _Gyms extends GymRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<List<GymStore>> registered() async => [_gymA, _gymB];
}

void main() {
  late VideoPlayerPlatform oldVideo;
  late _Video video;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CustomExercisePreference.exercises = [];
    WorkoutUiPreference.completionCheckEnabled = true;
    WorkoutUiPreference.workoutTimerEnabled = false;
    WorkoutUiPreference.workoutDurationEnabled = false;
    RestTimerPreference.enabled = true;
    RestTimerPreference.seconds = 90;
    oldVideo = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = video = _Video();
    GymServices.override = _Gyms();
  });
  tearDown(() {
    VideoPlayerPlatform.instance = oldVideo;
    GymServices.override = null;
  });

  test(
    'concurrent individual favorite updates retain previously saved IDs',
    () async {
      await ExerciseFavoritePreference.save({'id:bench_press'});
      await Future.wait([
        ExerciseFavoritePreference.setFavorite('id:wall_sit', true),
        ExerciseFavoritePreference.setFavorite('id:pallof_press', true),
      ]);
      expect(await ExerciseFavoritePreference.load(), {
        'id:bench_press',
        'id:wall_sit',
        'id:pallof_press',
      });
      await ExerciseFavoritePreference.setFavorite('id:wall_sit', false);
      expect(await ExerciseFavoritePreference.load(), {
        'id:bench_press',
        'id:pallof_press',
      });
    },
  );

  testWidgets('favorites survive picker recreation and a new workout', (
    t,
  ) async {
    await ExerciseFavoritePreference.setFavorite('id:bench_press', true);
    Future<void> picker() async {
      await t.pumpWidget(
        const MaterialApp(home: Scaffold(body: ExercisePickerSheet())),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('exerciseSearchField')), 'ベンチプレス');
      await t.pumpAndSettle();
      final star = find.byKey(const Key('favoriteExerciseid:bench_press'));
      await t.ensureVisible(star);
      expect(
        find.descendant(of: star, matching: find.byIcon(Icons.star_rounded)),
        findsOneWidget,
      );
    }

    await picker();
    await t.pumpWidget(
      const MaterialApp(home: WorkoutPage(resumeDraft: false)),
    );
    await t.pumpAndSettle();
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
    await picker();
    expect(await ExerciseFavoritePreference.load(), {'id:bench_press'});
  });

  testWidgets(
    'thumbnail opens the matching guide and preserves inputs and rest timer',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
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
      final start = find.byKey(const Key('toggleSet0_1'));
      await t.ensureVisible(start);
      await t.pumpAndSettle();
      await t.tap(start);
      await t.pump();
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
      expect(video.sources.single.asset, 'assets/vital_videos/0042.mp4');
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
      await t.drag(find.byType(Scrollable).first, const Offset(0, 800));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('stopRestTimerButton')), findsOneWidget);
      expect(await ExerciseFavoritePreference.load(), isEmpty);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('detail mannequin uses the front/back tap action', (t) async {
    final semantics = t.ensureSemantics();
    await t.pumpWidget(
      const MaterialApp(
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
    final frame = find.byKey(const Key('muscleMannequinFrame'));
    expect(t.getSemantics(frame).value, '正面');
    await t.tap(frame);
    await t.pumpAndSettle();
    expect(t.getSemantics(frame).value, '背面');
    await t.tap(frame);
    await t.pumpAndSettle();
    expect(t.getSemantics(frame).value, '正面');
    semantics.dispose();
  });

  testWidgets(
    'place B emphasizes one default and keeps the other places compact',
    (t) async {
      await TrainingPlacePreference.save(const TrainingPlace.store(_gymA));
      await t.pumpWidget(const MaterialApp(home: RegisteredGymsPage()));
      await t.pumpAndSettle();
      final preferred = find.byKey(const Key('preferredTrainingPlaceCard'));
      final others = find.byKey(const Key('otherTrainingPlaces'));
      expect(
        find.descendant(of: preferred, matching: find.text(_gymA.chainName)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: others, matching: find.text(_gymA.displayName)),
        findsNothing,
      );
      expect(
        find.descendant(of: others, matching: find.text('自宅')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: others, matching: find.text(_gymB.displayName)),
        findsOneWidget,
      );
      final select = find.byKey(const Key('defaultTrainingPlaceHome'));
      await t.ensureVisible(select);
      await t.pumpAndSettle();
      await t.tap(select);
      await t.pumpAndSettle();
      expect((await TrainingPlacePreference.load()).isHome, isTrue);
      expect(
        find.descendant(of: preferred, matching: find.text('自宅')),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );
}
