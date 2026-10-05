import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setkeep/design/family_theme.dart';
import 'package:setkeep/friends/notification_sources_page.dart';

import 'friend_comment_notifications_test.dart'
    show CommentInbox, CommentFriends;
import 'support/trainer_delivery_flow.dart' show DeliveryRepository;

void main() {
  testWidgets('Japanese public notification preview omits unreleased trainer', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final trainer = DeliveryRepository();
    addTearDown(trainer.auth.close);
    await t.runAsync(() async {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final font = File('/System/Library/Fonts/Hiragino Sans GB.ttc');
      await (FontLoader('PreviewJapanese')
            ..addFont(font.readAsBytes().then((b) => ByteData.sublistView(b))))
          .load();
    });
    final theme = familyTheme();
    final boundaryKey = GlobalKey();
    await t.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('ja'),
          supportedLocales: const [Locale('ja'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'PreviewJapanese'),
          ),
          home: NotificationSourcesPage(
            trainer: trainer,
            friends: CommentInbox(CommentFriends()),
            onStart: (_) async {},
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const Key('trainerNotificationSource')), findsNothing);
    await t.runAsync(() async {
      final image =
          await (boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('/tmp/setkeep_trainer_public_qa/notifications.png');
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
