import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/design/family_theme.dart';
import 'package:setkeep/friends/friends_ui.dart';

import 'friend_release_feedback_test.dart' show ClosedFriends;

void main() {
  testWidgets(
    'synthetic friend detail Japanese visual QA at normal and narrow large text',
    (t) async {
      await t.runAsync(() async {
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        final font = File('/System/Library/Fonts/Hiragino Sans GB.ttc');
        if (await font.exists()) {
          await (FontLoader(
            'FeedbackJapanese',
          )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
        }
      });
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetPadding);
      final theme = familyTheme();
      for (final size in [(390.0, 1.0), (320.0, 2.0)]) {
        t.view.physicalSize = Size(size.$1, 844);
        t.view.devicePixelRatio = 1;
        t.view.padding = const FakeViewPadding(bottom: 24);
        final key = GlobalKey();
        await t.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: const Locale('ja'),
              supportedLocales: const [Locale('ja'), Locale('en')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: theme.copyWith(
                textTheme: theme.textTheme.apply(
                  fontFamily: 'FeedbackJapanese',
                ),
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(size.$2)),
                child: child!,
              ),
              home: FriendActivityPage(
                repository: ClosedFriends(),
                owner: 'friend',
                selectedId: 'workout',
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        Future<void> capture(String name) async {
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
                '/tmp/setkeep_feedback_qa/$name-${size.$1.toInt()}.png',
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

        await capture('calendar');
        await t.scrollUntilVisible(
          find.text('Synthetic press'),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await t.pumpAndSettle();
        await capture('exercise-cards');
        await t.scrollUntilVisible(
          find.text('いいね 0'),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await t.pumpAndSettle();
        await capture('bottom-safe-area');
        expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
        expect(find.byKey(const Key('openWorkoutComments')), findsNothing);
        expect(t.takeException(), isNull);
      }
    },
  );
}
