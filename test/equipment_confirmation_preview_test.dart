import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:setkeep/exercise_media.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/gym/training_equipment_confirmation.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('confirmation preview $platform', (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.runAsync(() async {
        final path = File('/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc');
        if (path.existsSync()) {
          final loader = FontLoader('qaJapanese');
          loader.addFont(
            Future.value(ByteData.sublistView(await path.readAsBytes())),
          );
          await loader.load();
        }
      });
      final k = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(
          key: k,
          child: MaterialApp(
            theme: ThemeData(platform: platform, fontFamily: 'qaJapanese'),
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: Material(
                  child: TrainingEquipmentSheet(
                    workout: const EquipmentWorkout(
                      key: 'preview',
                      storeId: 'preview',
                      completed: true,
                      exercises: {
                        'smith_bench_press': 'スミスマシンベンチプレス',
                        'leg_press': 'レッグプレス',
                      },
                    ),
                    prompts: const [
                      {
                        'exercise_id': 'smith_bench_press',
                        'options': [
                          {
                            'equipment_id': 'community-training:smith',
                            'label': 'スミスマシン',
                            'known': false,
                          },
                        ],
                      },
                      {
                        'exercise_id': 'leg_press',
                        'options': [
                          {
                            'equipment_id': 'community-training:leg_press',
                            'label': 'レッグプレス',
                            'known': false,
                          },
                        ],
                      },
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.runAsync(() async {
        final context = k.currentContext!;
        for (final path in [
          'assets/brand/setkeep_splash_mark.png',
          ExerciseMediaCatalog.forExerciseId('leg_press')?.thumbnailAssetPath,
        ]) {
          if (path != null) await precacheImage(AssetImage(path), context);
        }
      });
      await t.pumpAndSettle();
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await t.pump(const Duration(milliseconds: 100));
      await t.runAsync(() async {
        final image =
            await (k.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory(
          Platform.environment['SETKEEP_QA_PREVIEW_DIR'] ??
              '${Directory.systemTemp.path}/setkeep_equipment_preview',
        );
        await directory.create(recursive: true);
        await File('${directory.path}/confirmation_${platform.name}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      });
      expect(t.takeException(), isNull);
    });
  }
}
