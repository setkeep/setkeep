import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/design/app_colors.dart';
import 'package:setkeep/main.dart';

WorkoutRecord detailFixture({int duration = 60, double weight = 40}) =>
    WorkoutRecord(
      date: DateTime(2026, 9, 21),
      durationSeconds: duration,
      sets: [
        for (var i = 0; i < 3; i++)
          RecordedSet(weight: weight, reps: 10, completed: true),
      ],
    );
WorkoutDetailPage detailPage(WorkoutRecord record) => WorkoutDetailPage(
  workout: record,
  selectedGym: null,
  onWorkoutCompleted: (_) async {},
  onWorkoutUpdated: (_, _) async {},
  onWorkoutDeleted: (_) async => false,
);
Widget headerFixture({List<String> names = const ['ベンチプレス', 'ショルダープレス']}) =>
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              for (final (index, name) in names.indexed)
                ExerciseInputCard(
                  exerciseIndex: index,
                  exercise: WorkoutExercise(
                    name: name,
                    bodyPart: index == 0 ? '胸' : '肩',
                    equipment: 'フリーウェイト',
                    recordType: ExerciseRecordType.weightReps,
                    sets: [WorkoutSet(weight: 40, reps: 10)],
                  ),
                  history: const [],
                  onAddSet: () {},
                  onRemoveSet: (_) {},
                  onRemove: () {},
                  onToggleSet: (_) {},
                  onApplyPrevious: (_) {},
                  onSetAllCompleted: (_) {},
                  onValuesChanged: () {},
                ),
            ],
          ),
        ),
      ),
    );
void main() {
  setUp(() => WorkoutUiPreference.workoutDurationEnabled = true);
  tearDown(() => WorkoutUiPreference.workoutDurationEnabled = true);
  testWidgets(
    'detail uses one calendar-style summary with four values without changing shared summary',
    (t) async {
      final record = detailFixture();
      expect(record.summaryLabel, '1種目 ・ 3セット ・ 1,200 kg ・ 1分');
      await t.pumpWidget(MaterialApp(home: detailPage(record)));
      await t.pumpAndSettle();
      expect(find.text(record.summaryLabel), findsNothing);
      for (final text in ['1 種目', '3 セット', '1,200 kg', '1分']) {
        final value = t.widget<Text>(find.text(text));
        expect(value.maxLines, 1);
        expect(value.softWrap, false);
      }
      final rects = [
        for (final label in ['種目数', 'セット数', '総ボリューム', 'トレーニング時間'])
          t.getRect(find.byKey(Key('detailSummaryValue$label'))),
      ];
      expect(rects.map((r) => r.top).toSet().length, 1);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('one trainer set shows its session comment on SK detail', (
    t,
  ) async {
    final record = WorkoutRecord(
      date: DateTime(2026, 9, 26),
      sets: const [RecordedSet(weight: 25, reps: 8, completed: true)],
      trainerWorkoutId: 'trainer-record',
      trainerOwnerUserId: 'client',
      note: 'フォームが安定してきています。',
    );
    await t.pumpWidget(MaterialApp(home: detailPage(record)));
    await t.pumpAndSettle();
    expect(find.text('1 セット'), findsOneWidget);
    expect(find.text('25 kg × 8 回'), findsOneWidget);
    expect(find.text('トレーナーからのコメント'), findsOneWidget);
    expect(find.text(record.note), findsOneWidget);
  });
  testWidgets('no trainer comment leaves no comment heading or card', (
    t,
  ) async {
    final record = WorkoutRecord(
      date: DateTime(2026, 9, 26),
      sets: const [RecordedSet(weight: 25, reps: 8, completed: true)],
      trainerWorkoutId: 'trainer-record',
      trainerOwnerUserId: 'client',
    );
    await t.pumpWidget(MaterialApp(home: detailPage(record)));
    await t.pumpAndSettle();
    expect(find.text('トレーナーからのコメント'), findsNothing);
    expect(find.byIcon(Icons.notes_rounded), findsNothing);
  });
  for (final duration in [0, 60]) {
    testWidgets('duration conditional: $duration', (t) async {
      if (duration > 0) WorkoutUiPreference.workoutDurationEnabled = false;
      await t.pumpWidget(
        MaterialApp(home: detailPage(detailFixture(duration: duration))),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('detailSummaryValueトレーニング時間')), findsNothing);
      expect(find.byKey(const Key('detailSummaryValue総ボリューム')), findsOneWidget);
    });
  }
  testWidgets('large values and text scale fit one row at 280px', (t) async {
    final record = detailFixture(weight: 12345678);
    // Mount the real detail page before isolating its summary for large text.
    await t.pumpWidget(MaterialApp(home: detailPage(record)));
    await t.pumpAndSettle();
    final summary = t.widget<Container>(
      find.byKey(const Key('workoutDetailSummary')),
    );
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: SizedBox(
                  width: 280,
                  child: MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: const TextScaler.linear(2)),
                    child: summary,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('${formatVolumeKg(record.volume)} kg'), findsOneWidget);
    expect(find.byType(FittedBox), findsNWidgets(8));
    expect(t.takeException(), isNull);
  });
  for (final width in [320.0, 400.0]) {
    testWidgets('exercise header titles stay on one line at $width px', (
      t,
    ) async {
      t.view.physicalSize = Size(width, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      double? removeRight;
      for (final name in [
        'ベンチプレス',
        'インクラインダンベルフライ',
        'インクラインダンベルプレス・とても長いカスタムトレーニング種目名',
      ]) {
        await t.pumpWidget(headerFixture(names: [name]));
        await t.pumpAndSettle();
        final titleFinder = find.byKey(const Key('exerciseInputTitle0'));
        final title = t.widget<Text>(titleFinder);
        expect(title.maxLines, 1);
        expect(title.softWrap, false);
        expect(title.overflow, TextOverflow.ellipsis);
        expect(title.style!.fontSize, inInclusiveRange(16, 18));
        if (name == 'ベンチプレス') expect(title.style!.fontSize, 18);
        if (name.contains('とても長い')) expect(title.style!.fontSize, 16);
        final painter = TextPainter(
          text: TextSpan(
            text: title.data,
            style: DefaultTextStyle.of(t.element(titleFinder)).style
                .merge(title.style),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: t.getSize(titleFinder).width);
        if (name.contains('とても長い')) expect(painter.didExceedMaxLines, isTrue);
        expect(painter.computeLineMetrics(), hasLength(1));
        painter.dispose();
        final remove = find.byTooltip('種目を削除');
        expect(remove, findsOneWidget);
        removeRight ??= t.getRect(remove).right;
        expect(t.getRect(remove).right, removeRight);
        expect(
          t.getRect(titleFinder).right,
          lessThanOrEqualTo(t.getRect(remove).left),
        );
        expect(find.text('胸 ・ フリーウェイト'), findsOneWidget);
        expect(t.takeException(), isNull);
      }
    });
  }

  testWidgets(
    'only exercise headers use brand green with readable text and remove icons',
    (t) async {
      await t.pumpWidget(headerFixture());
      await t.pumpAndSettle();
      for (final index in [0, 1]) {
        final header = find.byKey(Key('exerciseInputHeader$index'));
        final box = t.widget<Container>(header).decoration as BoxDecoration;
        expect(box.color, AppColors.primaryGreen);
        for (final text in t.widgetList<Text>(
          find.descendant(of: header, matching: find.byType(Text)),
        )) {
          expect(text.style!.color, const Color(0xFF101820));
        }
        expect(
          find.descendant(of: header, matching: find.byTooltip('種目を削除')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: header, matching: find.byType(ValueBox)),
          findsNothing,
        );
      }
      expect(find.text('前回の記録はありません'), findsNWidgets(2));
      expect(t.takeException(), isNull);
    },
  );
}
