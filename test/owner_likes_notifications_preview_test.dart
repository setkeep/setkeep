import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setkeep/design/family_theme.dart';
import 'package:setkeep/main.dart';

import 'support/owner_likes_fixture.dart';

void main() {
  testWidgets('like bell, inbox and own detail Japanese visual QA', (t) async {
    await t.runAsync(() async {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final font = File('/System/Library/Fonts/Hiragino Sans GB.ttc');
      if (await font.exists()) {
        await (FontLoader(
          'LikesJapanese',
        )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
      }
    });
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPadding);
    for (final size in [(390.0, 1.0), (320.0, 2.0)]) {
      SharedPreferences.setMockInitialValues({});
      t.view.physicalSize = Size(size.$1, 844);
      t.view.devicePixelRatio = 1;
      t.view.padding = const FakeViewPadding(bottom: 24);
      final friends = OwnerLikesFriends()
        ..inboxRows = [
          likeNotice(),
          likeNotice(
            author: 'friend-b',
            name: '別の友人',
            created: '2026-10-06T02:00:00Z',
          ),
        ];
      final inbox = OwnerLikeInbox(friends);
      final boundary = GlobalKey();
      final theme = familyTheme();
      await t.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme.copyWith(
              textTheme: theme.textTheme.apply(fontFamily: 'LikesJapanese'),
            ),
            locale: const Locale('ja'),
            supportedLocales: const [Locale('ja'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(size.$2)),
              child: child!,
            ),
            home: Scaffold(
              body: DashboardPage(
                history: [ownLikeWorkout],
                selectedGym: null,
                onGymChanged: (_) {},
                onWorkoutCompleted: (_) async {},
                onWorkoutUpdated: (_, _) async {},
                onWorkoutDeleted: (_) async => false,
                workoutTemplates: const [],
                onTemplateSaved: (_) async {},
                onTemplateDeleted: (_) async {},
                workoutDraft: null,
                onDraftChanged: () async {},
                onDraftDiscarded: () async {},
                likeInboxRepository: inbox,
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.runAsync(() async {
        final context = t.element(find.byType(DashboardPage));
        for (final path in [
          'assets/brand/setkeep_splash_lockup_source.png',
          'assets/vital_thumbnails/0042.png',
        ]) {
          await precacheImage(AssetImage(path), context);
        }
      });
      await t.pumpAndSettle();
      Future<void> capture(String name) async {
        await t.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              '/tmp/setkeep_owner_likes_qa/$name-${size.$1.toInt()}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(
              bytes!.buffer.asUint8List(
                bytes.offsetInBytes,
                bytes.lengthInBytes,
              ),
            );
          } finally {
            image.dispose();
          }
        });
      }

      await capture('home-bell');
      await t.tap(find.byKey(const Key('trainerInboxBell')));
      await t.pumpAndSettle();
      await capture('received-likes');
      await t.tap(find.text('テスト友人さんがあなたのトレーニングにいいねしました'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byKey(const Key('historyWorkoutLikeCount')),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await capture('own-detail-likes');
      expect(find.text('いいね 2'), findsOneWidget);
      expect(await inbox.unreadCount(), 1);
      expect(friends.writes, 0);
      expect(friends.commentReads, 0);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    }
  });
}
