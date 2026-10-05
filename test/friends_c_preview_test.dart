import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setkeep/design/family_theme.dart';
import 'package:setkeep/friends/friends_ui.dart';

import 'friends_mvp_test.dart' show FakeFriends;

class PreviewFriends extends FakeFriends {
  @override
  Future<List<Map<String, dynamic>>> connections() async => [
    {
      'id': 'preview-accepted',
      'requester': 'friend-one',
      'recipient': 'me',
      'status': 'accepted',
      'friend_name': 'ゆうき',
      'avatar_path': null,
    },
    {
      'id': 'preview-pending',
      'requester': 'friend-two',
      'recipient': 'me',
      'status': 'pending',
      'friend_name': 'さくら',
      'avatar_path': null,
    },
  ];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> fonts(WidgetTester t) async {
    await t.runAsync(() async {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final font = File('/System/Library/Fonts/Hiragino Sans GB.ttc');
      if (await font.exists()) {
        await (FontLoader(
          'PreviewJapanese',
        )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
      }
    });
  }

  Future<GlobalKey> screen(WidgetTester t, double width, double scale) async {
    t.view.physicalSize = Size(width, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final theme = familyTheme();
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
            textTheme: theme.textTheme.apply(fontFamily: 'PreviewJapanese'),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: FriendsSettingsPage(
            repository: PreviewFriends(),
            history: const [],
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    return key;
  }

  testWidgets('C invite page Japanese visual preview', (t) async {
    await fonts(t);
    final key = await screen(t, 390, 1);
    expect(find.text('フレンド・公開範囲'), findsNothing);
    expect(find.text('記録の公開範囲'), findsNothing);
    expect(find.text('Me'), findsNothing);
    expect(find.textContaining('ABCD2345'), findsOneWidget);
    await t.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = File(
          '/Users/macintosh/Documents/Codex/2026-10-04/task/friend-c-integration/friends_c_actual.png',
        );
        await output.writeAsBytes(
          data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      } finally {
        image.dispose();
      }
    });
    expect(t.takeException(), isNull);
  });

  testWidgets('C invite page narrow Japanese large text remains usable', (
    t,
  ) async {
    await screen(t, 320, 2);
    await t.scrollUntilVisible(
      find.byType(TextField),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'WXYZ6789');
    await t.scrollUntilVisible(
      find.text('フレンド申請'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    expect(find.text('フレンド申請'), findsOneWidget);
    await t.scrollUntilVisible(
      find.text('さくら'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    expect(find.text('さくら'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
