import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/design/family_theme.dart';
import 'package:setkeep/friends/friends_ui.dart';
import 'package:setkeep/main.dart';

import 'friend_release_feedback_test.dart' show ClosedFriends;
import 'workout_record_header_test.dart' show headerRecordSets;

class HeaderFriends extends ClosedFriends {
  @override
  Future<List<Map<String, dynamic>>> feed({String? owner}) async => [
    {
      ...(await super.feed(owner: owner)).first,
      'sets': headerRecordSets.map((s) => s.toJson()).toList(),
    },
  ];
}

void main() {
  testWidgets('own and friend saved card visual QA', (t) async {
    await t.runAsync(() async {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final font = File('/System/Library/Fonts/Hiragino Sans GB.ttc');
      if (await font.exists()) {
        await (FontLoader(
          'HeaderJapanese',
        )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
      }
    });
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPadding);
    final theme = familyTheme();
    for (final size in [(390.0, 1.0), (320.0, 2.0)]) {
      for (final own in [true, false]) {
        t.view.physicalSize = Size(size.$1, 844);
        t.view.devicePixelRatio = 1;
        t.view.padding = const FakeViewPadding(bottom: 24);
        final key = GlobalKey();
        final workout = WorkoutRecord(
          date: DateTime(2026, 10, 3),
          sets: headerRecordSets,
        );
        await t.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: const Locale('ja'),
              supportedLocales: const [Locale('ja'), Locale('en')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: theme.copyWith(
                textTheme: theme.textTheme.apply(fontFamily: 'HeaderJapanese'),
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(size.$2)),
                child: child!,
              ),
              home: own
                  ? WorkoutDetailPage(
                      workout: workout,
                      selectedGym: null,
                      onWorkoutCompleted: (_) async {},
                      onWorkoutUpdated: (_, _) async {},
                      onWorkoutDeleted: (_) async => false,
                    )
                  : FriendActivityPage(
                      repository: HeaderFriends(),
                      owner: 'friend',
                      selectedId: 'workout',
                    ),
            ),
          ),
        );
        await t.pumpAndSettle();
        // Await asset decoding so snapshots include the same stills as devices.
        await t.runAsync(() async {
          for (final image in t.widgetList<Image>(find.byType(Image))) {
            await precacheImage(image.image, key.currentContext!);
          }
        });
        await t.pumpAndSettle();
        Future<void> capture(String section) async {
          await t.runAsync(() async {
            final image =
                await (key.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            try {
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                '/tmp/setkeep_workout_header_qa/'
                '${own ? 'own' : 'friend'}-$section-${size.$1.toInt()}.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(
                data!.buffer.asUint8List(
                  data.offsetInBytes,
                  data.lengthInBytes,
                ),
              );
            } finally {
              image.dispose();
            }
          });
        }

        await t.scrollUntilVisible(
          find.text('ベンチプレス'),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await t.pumpAndSettle();
        await capture('cards');
        await t.scrollUntilVisible(
          find.text(headerRecordSets[2].exerciseName),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await t.pumpAndSettle();
        await capture('fallback');
        expect(find.byType(TextField), findsNothing);
        expect(find.byIcon(Icons.close_rounded), findsNothing);
        expect(find.byKey(const Key('openWorkoutComments')), findsNothing);
        expect(t.takeException(), isNull);
      }
    }
  });
}
