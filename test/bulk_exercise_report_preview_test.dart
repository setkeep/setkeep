import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/gym/gym_repository.dart';

import 'bulk_exercise_report_test.dart'
    show BulkReportRepo, openReport, selectPair;

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('bulk report rendered preview ${platform.name}', (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetViewInsets);
      GymServices.override = BulkReportRepo();
      addTearDown(() => GymServices.override = null);
      await t.runAsync(() async {
        final icons = FontLoader('MaterialIcons');
        icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
        final font = File('/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc');
        if (font.existsSync()) {
          final loader = FontLoader('qaJapanese');
          loader.addFont(
            Future.value(ByteData.sublistView(await font.readAsBytes())),
          );
          await loader.load();
        }
      });
      final boundary = GlobalKey();
      Future<void> capture(String name) async {
        final output = Platform.environment['SETKEEP_QA_PREVIEW_DIR'];
        if (output == null) return;
        await t.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory(output);
          await directory.create(recursive: true);
          await File('${directory.path}/${platform.name}_$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await openReport(
        t,
        platform: platform,
        boundaryKey: boundary,
        fontFamily: 'qaJapanese',
      );
      await selectPair(t);
      await capture('selected');
      await t.tap(find.byKey(const Key('exerciseReportTarget')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('placeExerciseSearch')), 'ベンチ');
      await t.pumpAndSettle();
      await capture('picker');
      t.view.viewInsets = const FakeViewPadding(bottom: 300);
      await t.pumpAndSettle();
      await capture('keyboard');
      expect(
        find.byKey(const Key('confirmPlaceExercises')).hitTestable(),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    });
  }
}
