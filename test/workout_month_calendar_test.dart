import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/design/app_colors.dart';
import 'package:setkeep/design/family_theme.dart';
import 'package:setkeep/design/workout_month_calendar.dart';

BoxDecoration decoration(WidgetTester tester, int day) =>
    tester
            .widget<Container>(
              find
                  .descendant(
                    of: find.byKey(Key('calendarDay$day')),
                    matching: find.byType(Container),
                  )
                  .first,
            )
            .decoration!
        as BoxDecoration;

Future<void> showCalendar(
  WidgetTester tester, {
  required DateTime Function() now,
  DateTime? month,
  DateTime? selected,
  List<DateTime> recorded = const [],
  void Function(DateTime, bool)? onSelect,
  double textScale = 1,
}) => tester.pumpWidget(
  MaterialApp(
    theme: familyTheme(),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: WorkoutMonthCalendar(
          visibleMonth: month ?? DateTime(2026, 10),
          selectedDay: selected,
          recordedDates: recorded,
          onSelectDay: onSelect ?? (_, _) {},
          now: now,
        ),
      ),
    ),
  ),
);

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('today is distinct from selected and recorded days', (t) async {
    final clock = DateTime(2026, 10, 6, 14);
    DateTime? tapped;
    bool? wasSelected;
    await showCalendar(
      t,
      now: () => clock,
      selected: DateTime(2026, 10, 31),
      recorded: [DateTime(2026, 10, 3)],
      onSelect: (date, selected) {
        tapped = date;
        wasSelected = selected;
      },
    );
    expect(decoration(t, 6).border, isNotNull);
    expect(decoration(t, 6).color, isNull);
    expect(decoration(t, 31).color, AppColors.ink);
    expect(decoration(t, 31).border, isNull);
    expect(decoration(t, 3).color, isNotNull);
    expect(decoration(t, 3).border, isNull);
    final todaySemantics = t.widget<Semantics>(
      find.descendant(
        of: find.byKey(const Key('calendarDay6')),
        matching: find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.label == 'Today',
        ),
      ),
    );
    expect(todaySemantics.properties.label, 'Today');
    await t.tap(find.byKey(const Key('calendarDay6')));
    expect(tapped, DateTime(2026, 10, 6));
    expect(wasSelected, false);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('selected today keeps outline, selection and workout dot', (
    t,
  ) async {
    await showCalendar(
      t,
      now: () => DateTime(2026, 10, 6, 14),
      selected: DateTime(2026, 10, 6),
      recorded: [DateTime(2026, 10, 6)],
    );
    final cell = decoration(t, 6);
    expect(cell.color, AppColors.ink);
    final border = cell.border! as Border;
    expect(border.top.width, greaterThanOrEqualTo(2));
    final luminance = border.top.color.computeLuminance();
    expect(
      (luminance + .05) / (AppColors.ink.computeLuminance() + .05),
      greaterThanOrEqualTo(3),
    );
    expect(1.05 / (luminance + .05), greaterThanOrEqualTo(3));
    final dot = t.widget<Container>(
      find.descendant(
        of: find.byKey(const Key('calendarDay6')),
        matching: find.byWidgetPredicate(
          (widget) => widget is Container && widget.constraints?.maxWidth == 4,
        ),
      ),
    );
    expect((dot.decoration! as BoxDecoration).color, AppColors.primaryGreen);
    final text = t.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('calendarDay6')),
        matching: find.byType(Text),
      ),
    );
    expect(text.style!.color, Colors.white);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('month and year navigation do not mark the same day number', (
    t,
  ) async {
    DateTime clock() => DateTime(2026, 10, 6, 14);
    for (final month in [DateTime(2026, 9), DateTime(2025, 10)]) {
      await showCalendar(t, now: clock, month: month);
      expect(decoration(t, 6).border, isNull);
    }
    await showCalendar(t, now: clock);
    expect(decoration(t, 6).border, isNotNull);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('foreground midnight moves today without changing selection', (
    t,
  ) async {
    var clock = DateTime(2026, 10, 6, 23, 59, 59, 500);
    await showCalendar(t, now: () => clock, selected: DateTime(2026, 10, 6));
    expect(decoration(t, 6).border, isNotNull);
    clock = DateTime(2026, 10, 7);
    await t.pump(const Duration(seconds: 1));
    expect(decoration(t, 6).border, isNull);
    expect(decoration(t, 6).color, AppColors.ink);
    expect(decoration(t, 7).border, isNotNull);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('resume after multiple days and month rollover refreshes today', (
    t,
  ) async {
    var clock = DateTime(2026, 10, 31, 22);
    await showCalendar(t, now: () => clock, selected: DateTime(2026, 10, 31));
    expect(decoration(t, 31).border, isNotNull);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    clock = DateTime(2026, 11, 2, 8);
    await t.pump(const Duration(days: 2));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    expect(decoration(t, 31).border, isNull);
    expect(decoration(t, 31).color, AppColors.ink);
    await showCalendar(t, now: () => clock, month: DateTime(2026, 11));
    expect(decoration(t, 2).border, isNotNull);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('UTC clock is converted to the device local calendar date', (
    t,
  ) async {
    final utc = DateTime.utc(2026, 10, 6, 23, 30);
    final local = utc.toLocal();
    await showCalendar(
      t,
      now: () => utc,
      month: DateTime(local.year, local.month),
    );
    expect(decoration(t, local.day).border, isNotNull);
    if (local.day != utc.day && local.month == utc.month) {
      expect(decoration(t, utc.day).border, isNull);
    }
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('selected recorded today fits narrow width and enlarged text', (
    t,
  ) async {
    t.view.physicalSize = const Size(280, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await showCalendar(
      t,
      now: () => DateTime(2026, 10, 6, 14),
      selected: DateTime(2026, 10, 6),
      recorded: [DateTime(2026, 10, 6)],
      textScale: 2,
    );
    expect(decoration(t, 6).border, isNotNull);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  });
}
