import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setkeep/design/app_colors.dart';
import 'package:setkeep/design/setkeep_navigation.dart';
import 'package:setkeep/friends/friends_tab_page.dart';
import 'package:setkeep/friends/friends_ui.dart';
import 'package:setkeep/main.dart';

import 'friends_mvp_test.dart' show FakeFriends;

class TabFriends extends FakeFriends {
  TabFriends([this.owner = 'me']);
  final String owner;
  int feedReads = 0;
  int publications = 0;
  int friendCount = 1;
  @override
  String get userId => owner;
  @override
  Future<List<Map<String, dynamic>>> feed({String? owner}) async {
    feedReads++;
    final rows = await super.feed(owner: owner);
    if (owner != null || friendCount == 1) return rows;
    return [
      for (var i = 0; i < friendCount; i++)
        {
          ...rows.first,
          'id': 'workout$i',
          'user_id': 'friend$i',
          'friend_profiles': {'display_name': i == 0 ? 'Alice' : 'Friend $i'},
        },
    ];
  }

  @override
  Future<void> publish(List<Map<String, dynamic>> records) async {
    publications++;
  }
}

Widget app(Widget home, {Locale locale = const Locale('ja')}) => MaterialApp(
  locale: locale,
  supportedLocales: const [Locale('ja'), Locale('en')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: home,
);

Future<void> selectTab(WidgetTester t, int index) async {
  await t.tap(find.byKey(ValueKey('selectedTab$index')));
  await t.pumpAndSettle();
}

void expectSelected(WidgetTester t, int index) {
  final selected = t.widget<AnimatedContainer>(
    find.byKey(ValueKey('selectedTab$index')),
  );
  expect((selected.decoration! as BoxDecoration).color, AppColors.primaryGreen);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RestTimerPreference.enabled = false;
    WorkoutUiPreference.workoutTimerEnabled = false;
  });

  testWidgets('Friends sits between Body and My Page with five usable tabs', (
    t,
  ) async {
    expect(SetkeepNavigation.labels, ['ホーム', '履歴', '部位', 'フレンド', 'マイページ']);
    final repo = TabFriends();
    await t.pumpWidget(app(HomeShell(friendsRepository: repo)));
    await t.pumpAndSettle();
    await selectTab(t, 2);
    expect(t.widget<BodyMapPage>(find.byType(BodyMapPage)).active, true);
    await selectTab(t, 3);
    expect(find.byType(FriendsTabPage), findsOneWidget);
    expectSelected(t, 3);
    expect(
      t
          .widget<BodyMapPage>(find.byType(BodyMapPage, skipOffstage: false))
          .active,
      false,
    );
    await selectTab(t, 4);
    expect(find.byType(ProfilePage), findsOneWidget);
    expectSelected(t, 4);
    await selectTab(t, 1);
    expect(find.byType(MonthlyHistoryPage), findsOneWidget);
    await selectTab(t, 0);
    expect(find.byType(DashboardPage), findsOneWidget);
    expect(find.byType(FriendsSection), findsNothing);
    expect(find.byType(FriendsSection, skipOffstage: false), findsOneWidget);
    expect(find.byType(HomeHeader), findsOneWidget);
    expect(repo.publications, 0);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'friend detail and management return to Friends; retap refreshes',
    (t) async {
      final repo = TabFriends();
      await t.pumpWidget(app(HomeShell(friendsRepository: repo)));
      await t.pumpAndSettle();
      await selectTab(t, 3);
      expect(find.text('Alice'), findsOneWidget);
      await t.tap(find.text('Alice'));
      await t.pumpAndSettle();
      expect(find.byType(FriendActivityPage), findsOneWidget);
      expect(find.byKey(const Key('monthlyCalendar')), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.byType(FriendsTabPage), findsOneWidget);
      expectSelected(t, 3);
      await t.tap(find.byTooltip('フレンド'));
      await t.pumpAndSettle();
      expect(find.byType(FriendsSettingsPage), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expectSelected(t, 3);
      final reads = repo.feedReads;
      await selectTab(t, 3);
      expect(repo.feedReads, greaterThan(reads));
      expect(repo.publications, 0);
      expect(repo.sharingAcknowledgements, 0);
      expect(repo.private, true);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('tab keeps scroll position and account changes clear old cards', (
    t,
  ) async {
    final repo = TabFriends()..friendCount = 20;
    await t.pumpWidget(app(HomeShell(friendsRepository: repo)));
    await t.pumpAndSettle();
    await selectTab(t, 3);
    final list = find.byKey(const PageStorageKey('friendsTabScroll'));
    final state = t.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)).first,
    );
    state.position.jumpTo(180);
    await t.pump();
    await selectTab(t, 4);
    await selectTab(t, 3);
    final restored = t.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)).first,
    );
    expect(identical(restored, state), true);
    expect(restored.position.pixels, 180);
    await t.pumpWidget(
      app(HomeShell(friendsRepository: TabFriends('other')..fail = true)),
    );
    await t.pumpAndSettle();
    expectSelected(t, 3);
    expect(find.text('Alice'), findsNothing);
    expect(find.text('読み込めませんでした。再試行'), findsOneWidget);
    expect(repo.publications, 0);
    await t.pumpWidget(const SizedBox.shrink());
  });

  for (final locale in [const Locale('ja'), const Locale('en')]) {
    testWidgets('friend tab has localized empty state and management $locale', (
      t,
    ) async {
      await t.pumpWidget(
        app(const FriendsTabPage(history: []), locale: locale),
      );
      await t.pumpAndSettle();
      expect(
        find.text(locale.languageCode == 'en' ? 'Friends' : 'フレンド'),
        findsOneWidget,
      );
      expect(
        find.text(
          locale.languageCode == 'en'
              ? 'Sign in to use friends'
              : 'ログインするとフレンドを利用できます',
        ),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    });
  }
}
