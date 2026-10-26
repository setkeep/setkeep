import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/exercise_form_catalog.dart';
import 'package:setkeep/bench_press_form.dart';
import 'package:setkeep/exercise_media.dart';
import 'package:setkeep/exercise_media_form_view.dart';
import 'package:setkeep/main.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _TestVideoPlatform extends VideoPlayerPlatform {
  final sources = <DataSource>[];
  final loops = <bool>[];
  final volumes = <double>[];
  final calls = <String>[];
  final streams = <int, StreamController<VideoEvent>>{};
  var nextId = 1;
  bool failPlay = false;
  Size frameSize = const Size(100, 100);
  bool coloredDecoderEdges = false;

  @override
  Future<void> init() async => calls.add('init');

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(
    int playerId,
    bool preventsDisplaySleepDuringVideoPlayback,
  ) async {}

  @override
  Future<int?> create(DataSource dataSource) => _create(dataSource);

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) =>
      _create(options.dataSource);

  Future<int> _create(DataSource source) async {
    final id = nextId++;
    sources.add(source);
    calls.add('create');
    final stream = streams[id] = StreamController<VideoEvent>();
    stream.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        size: frameSize,
        duration: const Duration(seconds: 2),
      ),
    );
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => streams[playerId]!.stream;

  @override
  Widget buildView(int playerId) => coloredDecoderEdges
      ? const CustomPaint(painter: _DecoderEdgePainter())
      : const ColoredBox(color: Colors.blue);

  @override
  Future<void> setLooping(int playerId, bool looping) async {
    loops.add(looping);
  }

  @override
  Future<void> setVolume(int playerId, double volume) async {
    volumes.add(volume);
  }

  @override
  Future<void> play(int playerId) async {
    if (failPlay) throw PlatformException(code: 'VideoError');
    calls.add('play');
  }

  @override
  Future<void> pause(int playerId) async => calls.add('pause');

  @override
  Future<void> dispose(int playerId) async {
    calls.add('dispose');
    await streams.remove(playerId)?.close();
  }

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
}

class _DecoderEdgePainter extends CustomPainter {
  const _DecoderEdgePainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.greenAccent);
    canvas.drawRect(
      Rect.fromLTRB(
        size.width * .0075,
        size.height * .0075,
        size.width * .9925,
        size.height * .9925,
      ),
      Paint()..color = Colors.blue,
    );
  }

  @override
  bool shouldRepaint(_DecoderEdgePainter oldDelegate) => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const originalMappings = {
    'bench_press': '0042',
    'incline_dumbbell_press': '0048',
    'incline_barbell_press': '0043',
    'flat_dumbbell_press': '0046',
    'assisted_chin_up': '0102',
    'cable_row': '0163',
    'dumbbell_shoulder_press': '0257',
    'barbell_curl': '0009',
    'dumbbell_curl': '0015',
    'hammer_curl': '0016',
    'pec_fly': '0051',
    'barbell_squat': '0054',
    'leg_press': '0074',
    'rope_pushdown': '0085',
    'machine_lateral_raise': '0097',
  };

  test('approved seven guides preserve exact exercise identities and bundle assets', () async {
    const approved = {
      'smith_bench_press': 'smith_bench_press_v1',
      'smith_incline_press': 'smith_incline_press_v11',
      'smith_squat': 'smith_squat_wrist_v2_white',
      'decline_barbell_press': 'decline_barbell_press_v1',
      'split_squat': 'split_squat_v1',
      'rear_raise': 'rear_raise_v1',
      'reverse_curl': 'reverse_curl_coordination_v2',
    };
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    for (final entry in approved.entries) {
      final media = ExerciseMediaCatalog.forExerciseId(entry.key)!;
      expect(ExerciseFormCatalog.byId[entry.key], isNotNull);
      expect(media.exerciseId, entry.key);
      expect(media.providerAssetId, entry.value);
      expect(media.provider, 'setkeep_original');
      expect(manifest.listAssets(), contains(media.assetPath));
      expect(manifest.listAssets(), contains(media.thumbnailAssetPath));
      expect(File(media.assetPath).lengthSync(), greaterThan(1000000));
    }
    expect(ExerciseMediaCatalog.forExerciseId('smith_decline_press'), isNull);
    expect(
      ExerciseMediaCatalog.forExerciseId('smith_bulgarian_split_squat'),
      isNull,
    );
    expect(
      ExerciseMediaCatalog.forExerciseId('bulgarian_split_squat')!.provider,
      'vital_animations',
    );
  });

  test('white guide thumbnails keep the former label area clear', () async {
    for (final id in [
      'smith_bench_press',
      'smith_incline_press',
      'smith_squat',
      'decline_barbell_press',
      'split_squat',
      'rear_raise',
      'reverse_curl',
    ]) {
      final media = ExerciseMediaCatalog.forExerciseId(id)!;
      final data = await rootBundle.load(media.thumbnailAssetPath!);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final image = (await codec.getNextFrame()).image;
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      var inkPixels = 0;
      // This blank area includes the start of the former trial caption.
      // The wider old panel check would reject the intended white background.
      for (var y = (image.height * .02).floor(); y < image.height * .07; y++) {
        for (var x = (image.width * .02).floor(); x < image.width * .18; x++) {
          final offset = (y * image.width + x) * 4;
          if (pixels[offset] < 225 ||
              pixels[offset + 1] < 225 ||
              pixels[offset + 2] < 225) {
            inkPixels++;
          }
        }
      }
      expect(inkPixels, 0, reason: '$id must keep the old caption area white');
      image.dispose();
      codec.dispose();
    }
  });

  test('reviewed Vital IDs map to existing SETKEEP identities only', () async {
    expect(
      ExerciseMediaCatalog.entries.where(
        (media) => media.provider == 'vital_animations',
      ),
      hasLength(108),
    );
    for (final entry in originalMappings.entries) {
      final media = ExerciseMediaCatalog.forExerciseId(entry.key)!;
      expect(media.exerciseId, entry.key);
      expect(media.provider, 'vital_animations');
      expect(media.providerAssetId, entry.value);
      expect(media.assetPath, endsWith('/${entry.value}.mp4'));
      expect(media.thumbnailAssetPath, endsWith('/${entry.value}.png'));
      expect(ExerciseFormCatalog.byId[entry.key], isNotNull);
    }
    expect(
      ExerciseMediaCatalog.forExerciseId('triceps_pushdown')?.exerciseId,
      'rope_pushdown',
    );
    expect(ExerciseMediaCatalog.forExerciseId('dy_row'), isNull);
    expect(ExerciseMediaCatalog.forExerciseId('cable_lateral_raise'), isNull);
    expect(
      ExerciseMediaCatalog.forExerciseId('single_arm_cable_lateral_raise')
          ?.providerAssetId,
      '0137',
    );
    final benchMedia = ExerciseMediaCatalog.forExerciseId('bench_press')!;
    if (File(benchMedia.assetPath).existsSync()) {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      expect(manifest.listAssets(), contains(benchMedia.assetPath));
      expect(manifest.listAssets(), contains(benchMedia.thumbnailAssetPath));
    }
  });

  test(
    'approved SETKEEP Smith incline video is bundled for its own ID',
    () async {
      final media = ExerciseMediaCatalog.forExerciseId('smith_incline_press')!;
      expect(media.exerciseId, 'smith_incline_press');
      expect(media.provider, 'setkeep_original');
      expect(media.providerAssetId, 'smith_incline_press_v11');
      expect(media.mediaType, 'video');
      expect(
        media.assetPath,
        'assets/exercise_videos/smith_incline_press_v11.mp4',
      );
      expect(
        media.thumbnailAssetPath,
        'assets/exercise_thumbnails/smith_incline_press_v11.png',
      );
      expect(ExerciseMediaCatalog.entries, hasLength(115));
      expect(File(media.assetPath).lengthSync(), greaterThan(100000));
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      expect(manifest.listAssets(), contains(media.assetPath));
      expect(manifest.listAssets(), contains(media.thumbnailAssetPath));
      expect(ExerciseMediaCatalog.forExerciseId('smith_decline_press'), isNull);
      expect(
        ExerciseMediaCatalog.forExerciseId('incline_barbell_press')
            ?.providerAssetId,
        '0043',
      );
    },
  );

  test('approved SETKEEP Smith flat video is bundled for its own ID', () async {
    final media = ExerciseMediaCatalog.forExerciseId('smith_bench_press')!;
    expect(media.exerciseId, 'smith_bench_press');
    expect(media.provider, 'setkeep_original');
    expect(media.providerAssetId, 'smith_bench_press_v1');
    expect(media.mediaType, 'video');
    expect(media.assetPath, 'assets/exercise_videos/smith_bench_press_v1.mp4');
    expect(
      media.thumbnailAssetPath,
      'assets/exercise_thumbnails/smith_bench_press_v1.png',
    );
    expect(ExerciseMediaCatalog.entries, hasLength(115));
    expect(File(media.assetPath).lengthSync(), greaterThan(100000));
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    expect(manifest.listAssets(), contains(media.assetPath));
    expect(manifest.listAssets(), contains(media.thumbnailAssetPath));
    expect(await ExerciseMediaCatalog.isAvailable(media), isTrue);
    expect(
      ExerciseMediaCatalog.forExerciseId('bench_press')?.providerAssetId,
      '0042',
    );
    expect(
      ExerciseMediaCatalog.forExerciseId('smith_incline_press')
          ?.providerAssetId,
      'smith_incline_press_v11',
    );
    expect(ExerciseMediaCatalog.forExerciseId('smith_decline_press'), isNull);
  });

  test('purchased source and staged videos match reviewed IDs', () {
    final manifest = jsonDecode(
      File('tool/vital_media/mapping.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final source = Directory('local_assets/vital_animations/gym_dataset');
    if (!source.existsSync()) return; // Licensed files are never committed.
    expect(manifest['mappings'], hasLength(109));
    expect(manifest['reviewRequired'], hasLength(91));
    for (final item in manifest['mappings'] as List) {
      final exerciseId = item['exerciseId'] as String;
      final vitalId = item['providerAssetId'] as String;
      final media = ExerciseMediaCatalog.forExerciseId(exerciseId)!;
      if (exerciseId == 'smith_squat') {
        expect(media.provider, 'setkeep_original');
        expect(media.providerAssetId, 'smith_squat_wrist_v2_white');
      } else {
        expect(media.providerAssetId, vitalId);
      }
      expect(
        File('${source.path}/${item['sourceAsset']}').existsSync(),
        isTrue,
      );
      // Purchased sources remain intact when an approved original overrides one ID.
      final video = File('assets/vital_videos/$vitalId.mp4');
      expect(video.existsSync(), isTrue);
      expect(video.lengthSync(), greaterThan(100000));
      expect(File('assets/vital_thumbnails/$vitalId.png').existsSync(), isTrue);
    }
  });

  group('purchased form video', () {
    late VideoPlayerPlatform original;
    late _TestVideoPlatform video;

    setUp(() {
      original = VideoPlayerPlatform.instance;
      VideoPlayerPlatform.instance = video = _TestVideoPlatform();
    });
    tearDown(() => VideoPlayerPlatform.instance = original);

    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      for (final frameSize in [
        const Size(1080, 1080),
        const Size(1440, 2144),
      ]) {
        testWidgets('video edges clipped on $platform for $frameSize', (
          tester,
        ) async {
          video.frameSize = frameSize;
          video.coloredDecoderEdges = true;
          final capture = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: platform),
              home: Scaffold(
                body: Center(
                  child: RepaintBoundary(
                    key: capture,
                    child: ColoredBox(
                      color: Colors.white,
                      child: SizedBox(
                        width: 301.25,
                        child: ExerciseMediaFormView(
                          media: ExerciseMediaCatalog.entries.first,
                          assetAvailable: (_) async => true,
                          fallback: const SizedBox(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final viewport = find.byKey(const Key('exerciseVitalVideoCard'));
          final size = tester.getSize(viewport);
          expect(size.width, 301.25);
          expect(
            size.width / size.height,
            closeTo(frameSize.width / frameSize.height, .00001),
          );
          await tester.runAsync(() async {
            final boundary =
                capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            // Fractional physical pixels exercise scaling and rounded clipping.
            final image = await boundary.toImage(pixelRatio: 2.625);
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            var greenPixels = 0;
            var bluePixels = 0;
            for (var i = 0; i < bytes.lengthInBytes; i += 4) {
              final r = bytes.getUint8(i),
                  g = bytes.getUint8(i + 1),
                  b = bytes.getUint8(i + 2);
              if (g > r + 20 && g > b + 20) greenPixels++;
              if (b > r + 20 && b > g + 20) bluePixels++;
            }
            expect(greenPixels, 0);
            expect(bluePixels, greaterThan(image.width * image.height * .95));
            image.dispose();
          });
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('all mapped detail pages prefer muted looping video', (
      tester,
    ) async {
      for (final media in ExerciseMediaCatalog.entries) {
        final id = media.exerciseId;
        final form = ExerciseFormCatalog.byId[id]!;
        await tester.pumpWidget(
          MaterialApp(
            home: ExerciseMuscleDetailPage(
              exercise: ExerciseTemplate.fromForm(form),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('exerciseVitalVideoCard')),
          findsOneWidget,
          reason: id,
        );
        expect(find.byType(VideoPlayer), findsOneWidget, reason: id);
        expect(find.textContaining('試用動画'), findsNothing);
        expect(find.byType(ExerciseFormView), findsNothing);
        expect(
          video.sources.last.asset,
          ExerciseMediaCatalog.forExerciseId(id)!.assetPath,
        );
        expect(video.loops.last, isTrue);
        expect(video.volumes.last, 0);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(
        video.calls.where((call) => call == 'dispose'),
        hasLength(ExerciseMediaCatalog.entries.length),
      );
    });

    testWidgets('absent Vital asset uses a non-3D fallback', (tester) async {
      final media = ExerciseMediaCatalog.forExerciseId('barbell_squat')!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                ExerciseMediaFormView(
                  media: media,
                  assetAvailable: (_) async => false,
                  fallback: const SizedBox(
                    height: 100,
                    key: Key('unavailable'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unavailable')), findsOneWidget);
      expect(find.byType(ExerciseFormView), findsNothing);
      expect(find.byType(VideoPlayer), findsNothing);
    });

    testWidgets('no Vital and no 3D keeps the existing alternative', (
      tester,
    ) async {
      final form = ExerciseFormCatalog.byId['leg_press']!;
      expect(form.available, isFalse);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                ExerciseMediaFormView(
                  media: ExerciseMediaCatalog.forExerciseId('leg_press')!,
                  assetAvailable: (_) async => false,
                  fallback: const SizedBox(
                    height: 100,
                    key: Key('existingAlternative'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('existingAlternative')), findsOneWidget);
    });

    testWidgets('video failure falls back without crashing', (tester) async {
      video.failPlay = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                ExerciseMediaFormView(
                  media: ExerciseMediaCatalog.forExerciseId('pec_fly')!,
                  assetAvailable: (_) async => true,
                  fallback: const SizedBox(
                    height: 100,
                    key: Key('failedFallback'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('failedFallback')), findsOneWidget);
    });

    testWidgets('video pauses under another route and resumes on return', (
      tester,
    ) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          navigatorObservers: [exerciseMediaRouteObserver],
          home: Scaffold(
            body: ListView(
              children: [
                ExerciseMediaFormView(
                  media: ExerciseMediaCatalog.forExerciseId('pec_fly')!,
                  assetAvailable: (_) async => true,
                  fallback: const SizedBox(height: 100),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(video.calls, contains('play'));
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('other page')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(video.calls, contains('pause'));
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(video.calls.where((call) => call == 'play'), hasLength(2));
    });

    testWidgets('video pauses in background and resumes in foreground', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExerciseMediaFormView(
              media: ExerciseMediaCatalog.forExerciseId('lat_pulldown')!,
              assetAvailable: (_) async => true,
              fallback: const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(video.calls.where((call) => call == 'play'), hasLength(1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(video.calls, contains('pause'));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(video.calls.where((call) => call == 'play'), hasLength(2));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets('long detail title and form fit a small $platform screen', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final form =
            ExerciseFormCatalog.byId['single_arm_cable_lateral_raise']!;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            home: ExerciseMuscleDetailPage(
              exercise: ExerciseTemplate.fromForm(form),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('exerciseVitalVideoCard')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('unmatched former 3D guide is not shown', (tester) async {
      for (final id in ['dy_row', 'low_row', 'linear_row', 'high_row']) {
        final form = ExerciseFormCatalog.byId[id]!;
        await tester.pumpWidget(
          MaterialApp(
            home: ExerciseMuscleDetailPage(
              exercise: ExerciseTemplate.fromForm(form),
            ),
          ),
        );
        await tester.pump();
        expect(
          find.byKey(const Key('exerciseVitalVideoCard')),
          findsNothing,
          reason: id,
        );
        expect(
          find.byKey(const Key('exerciseFormUnavailable')),
          findsOneWidget,
          reason: id,
        );
        expect(find.byType(ExerciseFormView), findsNothing, reason: id);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  });
}
