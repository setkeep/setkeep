import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setkeep/design/family_theme.dart';
import 'package:setkeep/friends/friends_ui.dart';
import 'package:setkeep/main.dart';
import 'package:setkeep/sharing/workout_share_artwork.dart';

import 'package:setkeep/friends/friend_like_inbox_page.dart';
import 'package:setkeep/gym/gym_pages.dart';
import 'package:setkeep/gym/gym_repository.dart';
import 'package:setkeep/gym/training_place_preference.dart';

import 'gym_integration_test.dart' show FakeGyms, storeA;
import 'friends_mvp_test.dart' show FakeFriends;
import 'support/owner_likes_fixture.dart';
import 'friend_roster_widget_test.dart' show RosterFriends;
import 'share_photo_position_test.dart' show photo;

// DateTime cannot be const, so fixtures are built below.
final sample = WorkoutRecord(
  date: DateTime(2026, 11, 6),
  durationSeconds: 120,
  sets: [
    const RecordedSet(
      exerciseName: 'ベンチプレス',
      bodyPart: '胸',
      weight: 40,
      reps: 10,
      completed: true,
    ),
  ],
);

class FeedbackCalendar extends FakeFriends {
  @override
  bool get commentsEnabled => false;
  @override
  Future<List<Map<String, dynamic>>> feed({String? owner}) async => [
    for (var i = 0; i < 2; i++)
      {
        'id': 'record-$i',
        'user_id': 'friend',
        'client_id': '2026-11-06T23:${i == 0 ? '30' : '45'}:00.000',
        'performed_at': '2026-11-06T23:${i == 0 ? '30' : '45'}:00+00:00',
        'sets': sample.sets.map((s) => s.toJson()).toList(),
        'duration_seconds': 120,
        'friend_likes': [],
        'friend_profiles': {'display_name': '表示テスト'},
      },
  ];
}

Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
  final output = Platform.environment['FEEDBACK_QA_DIR'];
  if (output == null) return;
  await t.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory(output);
    await dir.create(recursive: true);
    await File('${dir.path}/$name.png')
        .writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
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
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'approved friends remain visually separated in the product theme',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          theme: familyTheme(),
          home: Scaffold(
            body: FriendsSection(
              history: const [],
              repository: RosterFriends(),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final cards = find.byType(Card);
      expect(cards, findsNWidgets(3));
      for (var i = 0; i < 2; i++) {
        final a = t.getRect(
          find
              .descendant(of: cards.at(i), matching: find.byType(Material))
              .first,
        );
        final b = t.getRect(
          find
              .descendant(of: cards.at(i + 1), matching: find.byType(Material))
              .first,
        );
        expect(b.top - a.bottom, greaterThanOrEqualTo(12));
      }
    },
  );
  testWidgets(
    'friend summary always keeps four equal white columns and duration',
    (t) async {
      WorkoutUiPreference.workoutDurationEnabled = false;
      addTearDown(() => WorkoutUiPreference.workoutDurationEnabled = true);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: WorkoutDetailSummary(
                workout: sample,
                alwaysShowDuration: true,
              ),
            ),
          ),
        ),
      );
      expect(find.byType(Expanded), findsNWidgets(4));
      expect(find.text('2分'), findsOneWidget);
      final widths = [
        for (final e in t.widgetList<Expanded>(find.byType(Expanded))) e.flex,
      ];
      expect(widths, [1, 1, 1, 1]);
      expect(t.takeException(), isNull);
    },
  );
  for (final compact in [false, true]) {
    testWidgets(
      'notifications, places and friend detail ${compact ? '320px 2x' : '390px'}',
      (t) async {
        t.view.physicalSize = Size(compact ? 320 : 390, 1100);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        Future<GlobalKey> show(Widget page) async {
          final key = GlobalKey();
          final theme = familyTheme();
          await t.pumpWidget(
            RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: theme.copyWith(
                  platform: TargetPlatform.iOS,
                  textTheme: theme.textTheme.apply(
                    fontFamily: 'FeedbackJapanese',
                  ),
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(compact ? 2 : 1)),
                  child: child!,
                ),
                home: page,
              ),
            ),
          );
          await t.pumpAndSettle();
          return key;
        }

        final friends = OwnerLikesFriends()
          ..inboxRows = [
            likeNotice(name: '通知テスト A'),
            likeNotice(author: 'friend-b', name: '通知テスト B'),
          ];
        final noticeKey = await show(
          FriendLikeInboxPage(
            repository: OwnerLikeInbox(friends),
            onOpenWorkout: (_) async => false,
          ),
        );
        final notices = find.byType(Card);
        expect(notices, findsNWidgets(2));
        final a = t.getRect(
          find
              .descendant(of: notices.at(0), matching: find.byType(Material))
              .first,
        );
        final b = t.getRect(
          find
              .descendant(of: notices.at(1), matching: find.byType(Material))
              .first,
        );
        expect(b.top - a.bottom, greaterThanOrEqualTo(12));
        expect(t.takeException(), isNull);
        await capture(
          t,
          noticeKey,
          'notifications-${compact ? 'compact' : 'normal'}',
        );
        GymServices.override = FakeGyms()..saved = [storeA];
        addTearDown(() => GymServices.override = null);
        await CustomGymPreference.replaceAll(['ホテルのジム', 'トレーニングルーム']);
        await TrainingPlacePreference.save(const TrainingPlace.home());
        final placeKey = await show(const RegisteredGymsPage());
        final placeCards = find.descendant(
          of: find.byKey(const Key('otherTrainingPlaces')),
          matching: find.byType(Card),
        );
        expect(placeCards, findsNWidgets(3));
        for (var i = 0; i < 2; i++) {
          final a = t.getRect(
            find
                .descendant(
                  of: placeCards.at(i),
                  matching: find.byType(Material),
                )
                .first,
          );
          final b = t.getRect(
            find
                .descendant(
                  of: placeCards.at(i + 1),
                  matching: find.byType(Material),
                )
                .first,
          );
          expect(b.top - a.bottom, greaterThanOrEqualTo(12));
        }
        expect(t.takeException(), isNull);
        await capture(t, placeKey, 'places-${compact ? 'compact' : 'normal'}');
        final detailKey = await show(
          FriendActivityPage(
            repository: FeedbackCalendar(),
            owner: 'friend',
            selectedId: 'record-0',
          ),
        );
        expect(find.text('2026/11'), findsOneWidget);
        expect(find.text('Workout 1'), findsOneWidget);
        expect(find.text('Workout 2'), findsOneWidget);
        expect(find.text('23:30'), findsNothing);
        expect(find.text('08:30'), findsNothing);
        await t.scrollUntilVisible(
          find.byKey(const Key('workoutDetailSummary')),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.byKey(const Key('workoutDetailSummary')), findsOneWidget);
        expect(find.text('2分'), findsWidgets);
        expect(t.takeException(), isNull);
        await capture(
          t,
          detailKey,
          'friend-detail-${compact ? 'compact' : 'normal'}',
        );
      },
    );
  }
  for (final withPhoto in [false, true]) {
    testWidgets(
      'share artwork ${withPhoto ? 'photo' : 'plain'} branding and export pixels',
      (t) async {
        t.view.physicalSize = const Size(390, 850);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final bytes = withPhoto
            ? await t.runAsync(() => photo(600, 1000))
            : null;
        final key = GlobalKey();
        await t.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'FeedbackJapanese'),
            home: Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: key,
                  child: SizedBox(
                    width: 340,
                    height: 340 * 16 / 9,
                    child: WorkoutShareArtwork(
                      backgroundBytes: bytes,
                      date: '2026.11.06',
                      exerciseRows: [
                        for (final name in ['ベンチプレス', 'ラットプルダウン', 'ダンベルロー'])
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                                const Text(
                                  '40 kg × 10 回 / 3 セット',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await t.runAsync(() async {
          final context = t.element(find.byType(WorkoutShareArtwork));
          await precacheImage(
            const AssetImage(WorkoutShareArtwork.logoAsset),
            context,
          );
          if (bytes != null) await precacheImage(MemoryImage(bytes), context);
        });
        await t.pumpAndSettle();
        expect(
          t
              .widget<Image>(find.byKey(const Key('shareBrandLogo')))
              .filterQuality,
          FilterQuality.high,
        );
        final logo = t.getRect(find.byKey(const Key('shareBrandLogo')));
        final date = t.getRect(find.byKey(const Key('shareDate')));
        final frame = t.getRect(find.byType(WorkoutShareArtwork));
        if (withPhoto) {
          expect(logo.bottom, lessThan(date.top));
          expect(logo.top - frame.top, greaterThan(frame.height * 0.14));
          final crop = find
              .ancestor(
                of: find.byKey(const Key('shareBrandLogo')),
                matching: find.byType(ClipRect),
              )
              .first;
          expect((t.getRect(crop).left - date.left).abs(), lessThan(1));
          expect((t.getSize(crop).width - date.width).abs(), lessThan(1));
        } else {
          expect((logo.center - frame.center).distance, lessThan(1));
          expect(WorkoutShareArtwork.centeredLogoOpacity, 0.24);
        }
        expect(t.takeException(), isNull);
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        await t.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 3);
          expect(image.width, 1020);
          expect(image.height, 1814);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          final output = Platform.environment['FEEDBACK_QA_DIR'];
          if (output != null) {
            final dir = Directory(output);
            await dir.create(recursive: true);
            await File('${dir.path}/share-${withPhoto ? 'photo' : 'plain'}.png')
                .writeAsBytes(png!.buffer.asUint8List());
          }
          image.dispose();
        });
      },
    );
  }
}
