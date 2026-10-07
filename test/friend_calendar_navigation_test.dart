import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/friends/friends_ui.dart';
import 'package:setkeep/design/setkeep_navigation.dart';

import 'friends_mvp_test.dart' show FakeFriends;

class CalendarFriends extends FakeFriends {
  @override
  Future<List<Map<String, dynamic>>> feed({String? owner}) async {
    final row = (await super.feed(owner: owner)).first;
    return [
      {
        ...row,
        'id': 'first',
        'performed_at': DateTime(2026, 10, 3, 12).toUtc().toIso8601String(),
      },
      {
        ...row,
        'id': 'second',
        'performed_at': DateTime(2026, 10, 3, 18).toUtc().toIso8601String(),
      },
      {
        ...row,
        'id': 'september',
        'performed_at': DateTime(2026, 9, 26, 12).toUtc().toIso8601String(),
      },
    ];
  }
}

void main() {
  testWidgets(
    'friend calendar filters duplicate sessions, empty days and month changes',
    (t) async {
      t.view.physicalSize = const Size(390, 1100);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          home: FriendActivityPage(
            repository: CalendarFriends(),
            owner: 'friend',
            selectedId: 'first',
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Muscle heatmap'), findsOneWidget);
      expect(find.byKey(const Key('monthlyCalendar')), findsOneWidget);
      await t.scrollUntilVisible(
        find.text('12:00').first,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('12:00'), findsOneWidget);
      expect(find.text('18:00'), findsOneWidget);
      await t.ensureVisible(find.byKey(const Key('calendarDay4')));
      await t.tap(find.byKey(const Key('calendarDay4')));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('No workouts on this day'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('12:00'), findsNothing);
      await t.ensureVisible(find.byTooltip('Previous month'));
      await t.tap(find.byTooltip('Previous month'));
      await t.pumpAndSettle();
      expect(find.text('2026/9'), findsOneWidget);
      await t.ensureVisible(find.byKey(const Key('calendarDay26')));
      await t.tap(find.byKey(const Key('calendarDay26')));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('12:00'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.text('12:00'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Like 0'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.text('Like 0'));
      await t.pumpAndSettle();
      expect(find.text('Like 1'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'all tabs keep My Page pill size at narrow width and enlarged text',
    (t) async {
      t.view.physicalSize = const Size(280, 600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      Size? baseline;
      for (
        var selected = 0;
        selected < SetkeepNavigation.labels.length;
        selected++
      ) {
        await t.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                bottomNavigationBar: SetkeepNavigation(
                  selectedIndex: selected,
                  onSelected: (_) {},
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        final size = t.getSize(find.byKey(ValueKey('selectedTab$selected')));
        baseline ??= size;
        expect(size, baseline);
        expect(t.takeException(), isNull);
      }
    },
  );
}
