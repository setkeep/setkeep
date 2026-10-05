import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setkeep/main.dart';
import 'package:setkeep/design/family_theme.dart';
import 'package:setkeep/friends/friend_invite.dart';

void main() {
  testWidgets('synthetic profile editor visual preview', (t) async {
    SharedPreferences.setMockInitialValues({'profile_display_name': 'UI確認用'});
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
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
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
      }
    });
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
          home: const HomeShell(),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.person_outline_rounded));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('editProfileDisplayName')));
    await t.pumpAndSettle();
    expect(find.text('プロフィールを編集'), findsOneWidget);
    await t.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('/tmp/setkeep_profile_edit_qa/integrated.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(
          data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      } finally {
        image.dispose();
      }
    });
    expect(t.takeException(), isNull);
  });
}
