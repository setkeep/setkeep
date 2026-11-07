import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setkeep/design/family_theme.dart';
import 'package:setkeep/main.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final menu in [false, true]) {
      testWidgets('picker rounded corners $platform menu=$menu', (t) async {
        SharedPreferences.setMockInitialValues({});
        t.view.physicalSize = const Size(390, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final key = GlobalKey();
        await t.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              theme: familyTheme().copyWith(platform: platform),
              home: menu
                  ? SavedMenuManagementPage(
                      initialTemplates: const [],
                      onChanged: (_) async {},
                    )
                  : const WorkoutPage(resumeDraft: false),
            ),
          ),
        );
        await t.pumpAndSettle();
        final opener = find.byKey(
          Key(menu ? 'createSavedMenuButton' : 'addExerciseButton'),
        );
        await Scrollable.ensureVisible(t.element(opener));
        await t.pumpAndSettle();
        await t.tap(opener);
        await t.pumpAndSettle();
        if (menu) {
          await t.enterText(find.byType(TextField), '角の確認');
          await t.tap(find.text('保存'));
          await t.pumpAndSettle();
        }
        final sheet = find.byType(BottomSheet);
        expect(sheet, findsOneWidget);
        final material = find
            .descendant(of: sheet, matching: find.byType(Material))
            .first;
        final surface = t.widget<Material>(material);
        expect(surface.clipBehavior, Clip.antiAlias);
        expect(surface.shape, isA<RoundedRectangleBorder>());
        final header = t.widget<ColoredBox>(
          find.byKey(const Key('exercisePickerHeader')),
        );
        expect(surface.color, header.color);
        final rect = t.getRect(material);
        await t.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final pixels = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          int pixel(int x, int y) =>
              pixels.getUint32((y * image.width + x) * 4);
          final y = rect.top.round() + 20;
          final center = pixel(rect.center.dx.round(), y);
          // The opaque header starts before the 28px corner ends. Its paint
          // must remain inside the modal shape on both sides.
          expect(pixel(rect.left.round(), y), isNot(center));
          expect(pixel(rect.right.round() - 1, y), isNot(center));
          final output = Platform.environment['CORNER_QA_DIR'];
          if (output != null) {
            final png = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            await Directory(output).create(recursive: true);
            await File('$output/${platform.name}-$menu.png')
                .writeAsBytes(png.buffer.asUint8List());
          }
          image.dispose();
        });
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        expect(sheet, findsNothing);
        expect(t.takeException(), isNull);
      });
    }
  }
}
