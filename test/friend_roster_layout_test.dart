import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setkeep/design/family_theme.dart';
import 'package:setkeep/friends/friends_tab_page.dart';
import 'package:setkeep/main.dart' show RecordedSet;

import 'friend_roster_widget_test.dart' show RosterFriends, record;

class LayoutFriends extends RosterFriends {
  @override
  bool get commentsEnabled => false;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final compact in [false, true]) {
      testWidgets(
        'roster fits $platform ${compact ? '320px 2x text' : '390px'}',
        (t) async {
          t.view.physicalSize = Size(compact ? 320 : 390, compact ? 568 : 844);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          await t.runAsync(() async {
            await (FontLoader('MaterialIcons')
                  ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
                .load();
            final font = File('/System/Library/Fonts/Hiragino Sans GB.ttc');
            if (await font.exists()) {
              await (FontLoader(
                'RosterJapanese',
              )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
            }
          });
          final repo = LayoutFriends()
            ..records = [
              {
                ...record('a', '2026-11-02T00:00:00Z'),
                'sets': [
                  const RecordedSet(
                    weight: 20,
                    reps: 8,
                    completed: true,
                  ).toJson(),
                ],
              },
            ];
          final key = GlobalKey();
          final theme = familyTheme();
          await t.pumpWidget(
            RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                locale: const Locale('ja'),
                supportedLocales: const [Locale('ja'), Locale('en')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                theme: theme.copyWith(
                  platform: platform,
                  textTheme: theme.textTheme.apply(
                    fontFamily: 'RosterJapanese',
                  ),
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(compact ? 2 : 1)),
                  child: child!,
                ),
                home: FriendsTabPage(history: const [], repository: repo),
              ),
            ),
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          expect(find.text('共有された記録はまだありません'), findsNWidgets(2));
          final output = Platform.environment['ROSTER_QA_DIR'];
          if (output != null) {
            await t.runAsync(() async {
              final boundary =
                  key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage(pixelRatio: 2);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory(output).create(recursive: true);
              await File(
                '$output/roster-${platform.name}-${compact ? 'compact' : 'normal'}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await t.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
