import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'support/bulk_exercise_flow.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/body_part_illustration.dart';
import 'package:setkeep/main.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'upper body renders share silhouette framing and image dimensions $platform',
      (tester) async {
        await tester.runAsync(() async {
          List<int>? silhouette;
          for (final asset in ['chest', 'shoulders', 'arms', 'abs']) {
            final data = await rootBundle.load(
              'assets/category_muscles/$asset.png',
            );
            final codec = await ui.instantiateImageCodec(
              data.buffer.asUint8List(),
            );
            final image = (await codec.getNextFrame()).image;
            expect(image.width, 600);
            expect(image.height, 480);
            final pixels = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
            bool isHighlighted(int x, int y) {
              final offset = (y * image.width + x) * 4;
              return pixels[offset + 3] > 200 &&
                  pixels[offset] > pixels[offset + 1] + 30;
            }

            if (asset == 'chest') {
              expect(
                isHighlighted(225, 235),
                isTrue,
                reason: 'left nipple region',
              );
              expect(
                isHighlighted(375, 235),
                isTrue,
                reason: 'right nipple region',
              );
              expect(
                isHighlighted(300, 340),
                isFalse,
                reason: 'abdomen excluded',
              );
            } else if (asset == 'shoulders') {
              expect(isHighlighted(155, 115), isTrue, reason: 'shoulder cap');
              expect(
                isHighlighted(115, 260),
                isFalse,
                reason: 'upper arm excluded',
              );
            } else if (asset == 'arms') {
              expect(
                isHighlighted(120, 210),
                isTrue,
                reason: 'proximal upper arm',
              );
              expect(
                isHighlighted(120, 130),
                isFalse,
                reason: 'deltoid excluded',
              );
            }
            final alpha = [
              for (var i = 3; i < pixels.length; i += 4)
                pixels[i] >= 128 ? 1 : 0,
            ];
            if (silhouette != null) {
              expect(
                [
                  for (var i = 0; i < alpha.length; i++)
                    if (alpha[i] != silhouette[i]) i,
                ].length,
                lessThan(30),
                reason: '$asset must not change pose or camera',
              );
            }
            silhouette = alpha;
            image.dispose();
            codec.dispose();
          }
        });
      },
    );

    testWidgets(
      'upper body mannequin thumbnails keep category layout on $platform',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final category in ['胸', '肩', '腕', '腹']) {
          var tapped = false;
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: platform),
              home: Scaffold(
                body: Center(
                  child: BodyPartCategoryCard(
                    category: category,
                    label: category == '腹' ? '腹筋' : category,
                    count: 20,
                    onTap: () => tapped = true,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final image = tester.widget<Image>(find.byType(Image));
          expect(
            (image.image as AssetImage).assetName,
            'assets/category_muscles/${BodyPartIllustration.assets[category]}.png',
          );
          expect(image.fit, BoxFit.contain);
          expect(tester.getSize(find.byType(BodyPartIllustration)).height, 104);
          expect(find.text(category == '腹' ? '腹筋' : category), findsOneWidget);
          expect(find.text('20種目'), findsOneWidget);
          await tester.tap(find.byKey(Key('exerciseCategory$category')));
          expect(tapped, isTrue);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
  testWidgets(
    'small picker wraps heading and opens scrolled category at the top',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: ExercisePickerSheet(existingNames: <String>{}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final legs = find.byKey(const Key('exerciseCategory脚'));
      await tester.scrollUntilVisible(
        legs,
        180,
        scrollable: exercisePickerScrollable(),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<BodyPartCategoryCard>(
              find.ancestor(
                of: legs,
                matching: find.byType(BodyPartCategoryCard),
              ),
            )
            .category,
        '脚',
        reason: 'The stored category key must remain unchanged',
      );
      expect(
        tester
            .widget<BodyPartCategoryCard>(
              find.ancestor(
                of: legs,
                matching: find.byType(BodyPartCategoryCard),
              ),
            )
            .label,
        '下半身',
      );
      await tester.tap(legs);
      await tester.pumpAndSettle();
      expect(find.text('下半身の種目'), findsOneWidget);
      expect(find.byKey(const Key('exerciseSearchField')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'category cards fit 320px with text scale $scale and remain selectable',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final categories = BodyPartIllustration.assets.keys.toList();
        final selected = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(320, 568),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    for (final category in categories)
                      BodyPartCategoryCard(
                        category: category,
                        label: category == '腹' ? '腹筋' : category,
                        count: 123,
                        onTap: () => selected.add(category),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final heights = <double>{};
        for (final category in categories) {
          final card = find.byKey(Key('exerciseCategory$category'));
          await tester.scrollUntilVisible(
            card,
            150,
            scrollable: find.byType(Scrollable),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          heights.add(tester.getSize(card).height);
          final art = find.descendant(
            of: card,
            matching: find.byType(BodyPartIllustration),
          );
          expect(
            find.descendant(of: art, matching: find.byType(CustomPaint)),
            findsNothing,
          );
          expect(
            find.descendant(of: art, matching: find.byType(Image)),
            findsOneWidget,
          );
          final image = tester.widget<Image>(
            find.descendant(of: art, matching: find.byType(Image)),
          );
          expect(
            (image.image as AssetImage).assetName,
            'assets/category_muscles/${BodyPartIllustration.assets[category]}.png',
          );
          expect(
            find.descendant(of: art, matching: find.byType(Icon)),
            findsNothing,
          );
          await tester.tap(card);
        }
        expect(selected, categories);
        if (scale == 1) expect(heights, hasLength(1));
      },
    );
  }
}
