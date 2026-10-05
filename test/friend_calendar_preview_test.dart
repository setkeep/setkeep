import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/design/family_theme.dart';
import 'package:setkeep/design/setkeep_navigation.dart';
import 'package:setkeep/friends/friends_ui.dart';

import 'friend_calendar_navigation_test.dart' show CalendarFriends;

void main() {
  testWidgets('synthetic calendar and fixed navigation visual previews', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    var theme = familyTheme();
    await t.runAsync(() async {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final font = File('/System/Library/Fonts/Hiragino Sans GB.ttc');
      if (await font.exists()) {
        await (FontLoader(
              'PreviewJapanese',
            )..addFont(font.readAsBytes().then((b) => ByteData.sublistView(b))))
            .load();
        theme = theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'PreviewJapanese'),
          primaryTextTheme: theme.primaryTextTheme.apply(
            fontFamily: 'PreviewJapanese',
          ),
        );
      }
    });
    final key = GlobalKey();
    Future<void> show(Widget home) async {
      await t.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('ja'),
            supportedLocales: const [Locale('ja'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: theme,
            home: home,
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    Future<void> capture(String name) async {
      await t.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('/tmp/setkeep_calendar_qa/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(
            data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
        } finally {
          image.dispose();
        }
      });
    }

    await show(
      FriendActivityPage(
        repository: CalendarFriends(),
        owner: 'friend',
        selectedId: 'first',
      ),
    );
    await capture('friend_calendar');
    await t.tap(find.byKey(const Key('calendarDay4')));
    await t.pumpAndSettle();
    await capture('friend_empty_day');
    for (var i = 0; i < 4; i++) {
      await show(
        Scaffold(
          body: const Center(child: Text('タブ表示確認')),
          bottomNavigationBar: SetkeepNavigation(
            selectedIndex: i,
            onSelected: (_) {},
          ),
        ),
      );
      await capture('navigation_$i');
      expect(t.takeException(), isNull);
    }
  });
}
