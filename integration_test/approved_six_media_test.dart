import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:setkeep/design/family_theme.dart';
import 'package:setkeep/exercise_form_catalog.dart';
import 'package:setkeep/exercise_media.dart';
import 'package:setkeep/main.dart';
import 'package:video_player/video_player.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const ids = [
    'pallof_press',
    'bayesian_curl',
    'wall_sit',
    'chest_supported_dumbbell_row',
    'reverse_lunge',
    'decline_dumbbell_fly',
  ];
  testWidgets(
    'all six guides play full loops from category through picker and detail',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          theme: familyTheme(),
          home: const Scaffold(body: ExercisePickerSheet()),
        ),
      );
      await t.pumpAndSettle();
      for (final id in ids) {
        final definition = ExerciseFormCatalog.byId[id]!;
        final categories = find.byKey(const Key('backToExerciseCategories'));
        if (categories.evaluate().isNotEmpty) {
          await t.tap(categories);
          await t.pumpAndSettle();
        }
        final category = find.byKey(
          Key(
            'exerciseCategory${ExerciseTemplate.fromForm(definition).bodyPart}',
          ),
        );
        await t.drag(find.byType(ListView).first, const Offset(0, 1600));
        await t.pumpAndSettle();
        await t.scrollUntilVisible(
          category,
          250,
          scrollable: find
              .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await t.tap(category);
        await t.pumpAndSettle();
        final search = find.byKey(const Key('exerciseSearchField'));
        await t.tap(search);
        // Let the native keyboard attach before sending the test edit.
        await Future<void>.delayed(const Duration(milliseconds: 700));
        await t.pumpAndSettle();
        await t.enterText(search, definition.exerciseName);
        await t.pumpAndSettle();

        final guide = find.byKey(Key('exerciseGuideid:$id'));
        debugPrint(
          'QA_SIX_SEARCH id=$id query=${t.widget<TextField>(find.byKey(const Key('exerciseSearchField'))).controller!.text} found=${guide.evaluate().length}',
        );
        await t.ensureVisible(guide);
        await t.tap(guide);
        await t.pumpAndSettle();
        VideoPlayerController? controller;
        for (var attempt = 0; attempt < 40; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          await t.pump();
          if (find.byType(VideoPlayer).evaluate().isNotEmpty) {
            controller = t
                .widget<VideoPlayer>(find.byType(VideoPlayer).first)
                .controller;
            if (controller.value.isInitialized && controller.value.isPlaying) {
              break;
            }
          }
        }
        expect(controller, isNotNull, reason: id);
        final c = controller!;
        expect(c.dataSource, ExerciseMediaCatalog.forExerciseId(id)!.assetPath);
        expect(c.value.isInitialized, isTrue);
        expect(c.value.isPlaying, isTrue);
        expect(c.value.isLooping, isTrue);
        expect(c.value.volume, 0);
        final duration = c.value.duration;
        expect(duration.inSeconds, greaterThan(5));
        var previous = c.value.position;
        var maxPosition = previous;
        var wrap = false;
        final clock = Stopwatch()..start();
        debugPrint('QA_SIX_CAPTURE_$id');
        if (Platform.isIOS) await binding.takeScreenshot(id);
        while (clock.elapsed < duration + const Duration(seconds: 5)) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          await t.pump();
          final current = c.value.position;
          if (current > maxPosition) maxPosition = current;
          if (previous > duration - const Duration(seconds: 2) &&
              current < const Duration(seconds: 2)) {
            wrap = true;
          }
          previous = current;
          expect(c.value.hasError, isFalse, reason: c.value.errorDescription);
          if (wrap && maxPosition > duration - const Duration(seconds: 1)) {
            break;
          }
        }
        expect(
          maxPosition,
          greaterThan(duration - const Duration(seconds: 1)),
          reason: id,
        );
        expect(
          wrap,
          isTrue,
          reason: '$id must loop without restarting the route',
        );
        debugPrint(
          'QA_SIX_RESULT ${jsonEncode({'id': id, 'durationMs': duration.inMilliseconds, 'maxPositionMs': maxPosition.inMilliseconds, 'looped': wrap, 'muted': c.value.volume == 0, 'platform': Platform.operatingSystem})}',
        );
        await t.pageBack();
        await t.pumpAndSettle();
        expect(find.byType(ExercisePickerSheet), findsOneWidget);
        expect(t.takeException(), isNull);
      }
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
