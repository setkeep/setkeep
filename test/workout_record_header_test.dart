import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/design/family_theme.dart';
import 'package:setkeep/exercise_list_thumbnail.dart';
import 'package:setkeep/main.dart';

const headerRecordSets = [
  RecordedSet(
    exerciseId: 'bench_press',
    exerciseName: 'ベンチプレス',
    bodyPart: '胸',
    equipment: 'バーベル',
    weight: 40,
    reps: 10,
    completed: true,
  ),
  RecordedSet(
    exerciseId: 'bench_press',
    exerciseName: 'ベンチプレス',
    bodyPart: '胸',
    equipment: 'バーベル',
    weight: 45,
    reps: 8,
    completed: true,
  ),
  RecordedSet(
    exerciseName: 'とても長い種目名のサムネイル未登録トレーニング記録',
    bodyPart: '脚',
    equipment: '複合ケーブル・プレートロード',
    recordType: ExerciseRecordType.bodyweightReps,
    weight: 0,
    reps: 12,
    completed: true,
  ),
  RecordedSet(
    exerciseName: '保持の記録',
    bodyPart: '腹',
    recordType: ExerciseRecordType.timed,
    weight: 0,
    reps: 0,
    durationSeconds: 45,
    completed: true,
  ),
  RecordedSet(
    exerciseName: '距離と負荷の記録',
    bodyPart: '有酸素',
    recordType: ExerciseRecordType.cardio,
    weight: 0,
    reps: 0,
    durationSeconds: 600,
    distanceKm: 1.2,
    inclinePercent: 4,
    resistanceLevel: 3,
    completed: true,
  ),
];

void main() {
  for (final size in [(390.0, 1.0), (320.0, 2.0)]) {
    for (final own in [true, false]) {
      testWidgets(
        'saved header matches training shell and preserves read-only values $size own=$own',
        (t) async {
          t.view.physicalSize = Size(size.$1, 844);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          final workout = WorkoutRecord(
            date: DateTime(2026, 10, 3),
            sets: headerRecordSets,
          );
          await t.pumpWidget(
            MaterialApp(
              theme: familyTheme(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(size.$2)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final sets in workout.exerciseGroups.values)
                        WorkoutDetailExerciseCard(
                          sets: sets,
                          showCompletionChecks: own,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          final headers = t
              .widgetList<WorkoutExerciseCardHeader>(
                find.byType(WorkoutExerciseCardHeader),
              )
              .toList();
          expect(
            headers.map((h) => h.name),
            workout.exerciseGroups.values.map((s) => s.first.exerciseName),
          );
          expect(headers.every((h) => h.trailing == null), isTrue);
          expect(find.byType(WorkoutExerciseCardShell), findsNWidgets(4));
          expect(find.byType(ExerciseListThumbnail), findsNWidgets(4));
          final first = find.byType(WorkoutExerciseCardHeader).first;
          final backdrop = t.widget<Container>(
            find.descendant(of: first, matching: find.byType(Container)).first,
          );
          expect(
            (backdrop.decoration as BoxDecoration).color,
            const Color(0xFFC7F36B),
          );
          expect(backdrop.padding, const EdgeInsets.fromLTRB(12, 8, 4, 8));
          expect(
            t.getSize(
              find.descendant(
                of: first,
                matching: find.byKey(const Key('exerciseListThumbnail')),
              ),
            ),
            const Size.square(56),
          );
          final images = t.widgetList<Image>(find.byType(Image)).toList();
          expect(
            images.any(
              (i) =>
                  (i.image as AssetImage).assetName ==
                  'assets/vital_thumbnails/0042.png',
            ),
            isTrue,
          );
          expect(
            images.any(
              (i) =>
                  (i.image as AssetImage).assetName ==
                      'assets/brand/setkeep_splash_mark.png' &&
                  i.color == const Color(0xFFAFB5B4),
            ),
            isTrue,
          );
          expect(find.byType(TextField), findsNothing);
          expect(find.byType(IconButton), findsNothing);
          expect(find.byIcon(Icons.close_rounded), findsNothing);
          expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
          expect(find.textContaining('セットを追加'), findsNothing);
          expect(
            find.byIcon(Icons.check_circle_rounded),
            own ? findsNWidgets(5) : findsNothing,
          );
          for (final set in headerRecordSets) {
            await t.ensureVisible(find.text(set.displaySummary));
            await t.pumpAndSettle();
            expect(find.text(set.displaySummary), findsOneWidget);
            expect(t.takeException(), isNull);
          }
          final long = t.widget<Text>(
            find.text(headerRecordSets[2].exerciseName),
          );
          expect(long.maxLines, 1);
          expect(long.overflow, TextOverflow.ellipsis);
          expect(long.style!.fontSize, inInclusiveRange(16, 18));
        },
      );
    }
  }
}
