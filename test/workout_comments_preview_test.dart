import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/design/family_theme.dart';
import 'package:setkeep/friends/workout_comments.dart';

import 'workout_comments_test.dart' show CommentFriends;

void main() {
  testWidgets('synthetic Japanese comment bubbles and keyboard visual QA', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    t.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetViewPadding);
    addTearDown(t.view.resetViewInsets);
    await t.runAsync(() async {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final font = File('/System/Library/Fonts/Hiragino Sans GB.ttc');
      if (await font.exists()) {
        await (FontLoader('PreviewJapanese')..addFont(
              font.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
            ))
            .load();
      }
    });
    final repo = CommentFriends();
    repo.messages.first['body'] = 'おつかれさま！\nベンチプレスの記録、伸びてるね👏';
    repo.messages.add({
      'id': 'third-message',
      'user_id': 'friend',
      'body': '次のトレーニングも楽しみ！\n無理せず自分のペースで続けよう。',
      'created_at': '2026-10-03T12:05:00Z',
      'friend_profiles': {'display_name': '友人の登録名', 'avatar_path': null},
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
          home: WorkoutCommentsPage(
            repository: repo,
            workoutId: 'shared-session',
            ownerId: 'friend',
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
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('/tmp/setkeep_comment_qa/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(
            data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
        } finally {
          image.dispose();
        }
      });
    }

    await capture('thread');
    await t.enterText(
      find.byKey(const Key('workoutCommentDraft')),
      'ありがとう！\n次も頑張るね',
    );
    t.view.viewInsets = const FakeViewPadding(bottom: 290);
    await t.pumpAndSettle();
    await capture('keyboard');
    expect(
      t.getRect(find.byKey(const Key('sendWorkoutComment'))).bottom,
      lessThanOrEqualTo(844 - 290),
    );
    expect(t.takeException(), isNull);
  });
}
