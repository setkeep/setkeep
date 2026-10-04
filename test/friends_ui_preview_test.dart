import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/design/family_theme.dart';
import 'package:setkeep/main.dart';
import 'package:setkeep/friends/friend_invite.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('home and profile layout preview uses synthetic data', (t) async {
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.app_links/events'),
      (_) async => null,
    );
    addTearDown(() async {
      await FriendInviteStore.reset();
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.llfbandit.app_links/events'),
        null,
      );
    });
    SharedPreferences.setMockInitialValues({
      'profile_display_name': 'UI確認用',
      'rest_timer_enabled': false,
    });
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    var theme = familyTheme();
    await t.runAsync(() async {
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      final font = File('/System/Library/Fonts/Hiragino Sans GB.ttc');
      if (await font.exists()) {
        final loader = FontLoader('PreviewJapanese')
          ..addFont(
            font.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
          );
        await loader.load();
        theme = theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'PreviewJapanese'),
          primaryTextTheme: theme.primaryTextTheme.apply(
            fontFamily: 'PreviewJapanese',
          ),
        );
      }
    });
    final boundaryKey = GlobalKey();
    await t.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('ja'),
          supportedLocales: const [Locale('ja'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: theme,
          home: const HomeShell(),
        ),
      ),
    );
    await t.runAsync(
      () => precacheImage(
        const AssetImage('assets/brand/setkeep_splash_lockup_source.png'),
        t.element(find.byKey(const Key('homeBrandLogo'))),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const Key('homeBrandLogo')), findsOneWidget);
    expect(t.getSize(find.byKey(const Key('homeBrandLogo'))).height, 46);
    expect(find.text('次の1セットが、\n成長の記録になる。'), findsOneWidget);
    Future<void> capture(String name) async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      await t.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('docs/qa/friends_ux_2026-10-04/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(
            bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          );
        } finally {
          image.dispose();
        }
      });
    }

    await capture('home');
    await t.tap(find.text('マイページ').last);
    await t.pumpAndSettle();
    expect(find.text('UI確認用'), findsOneWidget);
    final profile = find
        .ancestor(
          of: find.byKey(const Key('profileDisplayName')),
          matching: find.byType(Card),
        )
        .first;
    expect(
      find.descendant(
        of: profile,
        matching: find.byKey(const Key('accountButton')),
      ),
      findsOneWidget,
    );
    await capture('profile');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  });
}
