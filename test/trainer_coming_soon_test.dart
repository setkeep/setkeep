import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setkeep/main.dart';
import 'package:setkeep/trainer/trainer_coming_soon.dart';

import 'friend_comment_notifications_test.dart'
    show CommentInbox, CommentFriends;
import 'trainer_public_release_test.dart' show HiddenTrainer;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final locale in ['ja', 'en']) {
    testWidgets(
      'information closes, Back and repeated openings keep unread and linking unchanged in $locale',
      (t) async {
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final trainer = HiddenTrainer();
        addTearDown(trainer.auth.close);
        await t.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            supportedLocales: const [Locale('ja'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    HomeHeader(
                      repository: trainer,
                      friendRepository: CommentInbox(CommentFriends()),
                      onStart: (_) async {},
                    ),
                    TextButton(
                      key: const Key('openTrainerNotice'),
                      onPressed: () => showTrainerComingSoon(context),
                      child: const Text('TRAINER'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('1'), findsOneWidget);
        for (var attempt = 0; attempt < 3; attempt++) {
          await t.tap(find.byKey(const Key('openTrainerNotice')));
          await t.pumpAndSettle();
          expect(
            find.byKey(const Key('trainerComingSoonDialog')),
            findsOneWidget,
          );
          expect(find.byKey(const Key('trainerSharingPage')), findsNothing);
          if (attempt == 0) {
            await t.tap(find.text(locale == 'ja' ? '閉じる' : 'Close'));
          } else if (attempt == 1) {
            await t.binding.handlePopRoute();
          } else {
            await t.tapAt(const Offset(2, 2));
          }
          await t.pumpAndSettle();
          expect(
            find.byKey(const Key('trainerComingSoonDialog')),
            findsNothing,
          );
          expect(find.byKey(const Key('openTrainerNotice')), findsOneWidget);
          expect(find.text('1'), findsOneWidget);
          expect(trainer.unreadCalls, 0);
          expect(trainer.readMenuVersions, isEmpty);
          expect(trainer.readCommentVersions, isEmpty);
          expect(t.takeException(), isNull);
        }
      },
    );
  }
}
