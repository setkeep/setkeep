import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/exercise_form_catalog.dart';
import 'package:setkeep/design/family_theme.dart';
import 'package:setkeep/gym/gym_repository.dart';
import 'package:setkeep/gym/place_equipment_pages.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'gym_integration_test.dart' show FakeGyms;

class BulkReportRepo extends FakeGyms {
  final batches = <Set<String>>[];
  final comments = <String>[];
  final kinds = <String>[];
  Completer<void>? pending;
  @override
  Future<void> reportExercises({
    required String storeId,
    required String kind,
    required Set<String> exerciseIds,
    required String comment,
  }) async {
    expect(storeId, 'synthetic-store');
    batches.add({...exerciseIds});
    comments.add(comment);
    kinds.add(kind);
    await pending?.future;
  }
}

Future<void> openReport(
  WidgetTester t, {
  TargetPlatform? platform,
  GlobalKey? boundaryKey,
  String? fontFamily,
}) async {
  final theme = familyTheme();
  await t.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: MaterialApp(
        theme: theme.copyWith(
          platform: platform,
          textTheme: theme.textTheme.apply(fontFamily: fontFamily),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showStoreExerciseReport(
                context,
                'synthetic-store',
                {'bench_press', 'barbell_squat'},
              ),
              child: const Text('報告を開く'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('報告を開く'));
  await t.pumpAndSettle();
}

Future<void> chooseExercise(WidgetTester t, String id) async {
  await t.enterText(
    find.byKey(const Key('placeExerciseSearch')),
    ExerciseFormCatalog.byId[id]!.exerciseName,
  );
  await t.pumpAndSettle();
  final row = find.byKey(ValueKey('choosePlaceExercise$id'));
  await t.scrollUntilVisible(
    row.hitTestable(),
    140,
    scrollable: find.descendant(
      of: find.byKey(const Key('placeExerciseResults')),
      matching: find.byType(Scrollable),
    ),
  );
  await t.tap(row);
  await t.pumpAndSettle();
}

Future<void> selectPair(WidgetTester t) async {
  await t.tap(find.byKey(const Key('exerciseReportTarget')));
  await t.pumpAndSettle();
  await chooseExercise(t, 'bench_press');
  await chooseExercise(t, 'barbell_squat');
  expect(find.text('対象種目を選択（2件）'), findsOneWidget);
  await t.tap(find.byKey(const Key('confirmPlaceExercises')));
  await t.pumpAndSettle();
}

void main() {
  late BulkReportRepo repo;
  setUp(() {
    repo = BulkReportRepo();
    GymServices.override = repo;
  });
  tearDown(() => GymServices.override = null);

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final kind in ['missing_exercise', 'incorrect_exercise']) {
      testWidgets('$platform sends $kind as one selected batch', (t) async {
        t.view.physicalSize = const Size(390, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await openReport(t, platform: platform);
        if (kind == 'incorrect_exercise') {
          await t.tap(find.byKey(const Key('exerciseReportKind')));
          await t.pumpAndSettle();
          await t.tap(find.text('表示されているができない').last);
          await t.pumpAndSettle();
        }
        await selectPair(t);
        expect(find.text('2件をまとめて送信'), findsOneWidget);
        await t.enterText(
          find.byKey(const Key('exerciseReportComment')),
          '共通コメント',
        );
        await t.tap(find.byKey(const Key('sendExerciseReport')));
        await t.pumpAndSettle();
        expect(repo.batches, [
          {'bench_press', 'barbell_squat'},
        ]);
        expect(repo.comments, ['共通コメント']);
        expect(repo.kinds, [kind]);
        expect(find.byType(AlertDialog), findsNothing);
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'draft cancellation, toggles, chips and clear preserve explicit selection',
    (t) async {
      await openReport(t);
      await selectPair(t);
      await t.tap(find.byKey(const Key('exerciseReportTarget')));
      await t.pumpAndSettle();
      await chooseExercise(t, 'bench_press');
      expect(find.text('対象種目を選択（1件）'), findsOneWidget);
      await t.tap(find.byTooltip('閉じる'));
      await t.pumpAndSettle();
      expect(find.text('2件をまとめて送信'), findsOneWidget);
      final chip = find.byKey(const Key('exerciseReportSelectedbench_press'));
      await t.tap(find.descendant(of: chip, matching: find.byTooltip('選択を解除')));
      await t.pumpAndSettle();
      expect(find.text('報告を送信'), findsOneWidget);
      await t.tap(find.byKey(const Key('exerciseReportTarget')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('clearPlaceExercises')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('confirmPlaceExercises')));
      await t.pumpAndSettle();
      expect(
        t
            .widget<FilledButton>(find.byKey(const Key('sendExerciseReport')))
            .onPressed,
        isNull,
      );
      await t.tap(find.text('キャンセル'));
      await t.pumpAndSettle();
      expect(repo.batches, isEmpty);
      await t.tap(find.text('報告を開く'));
      await t.pumpAndSettle();
      expect(find.byType(InputChip), findsNothing);
    },
  );

  testWidgets(
    'busy blocks duplicate taps, edits, barrier and back; failure retains retry draft',
    (t) async {
      await openReport(t);
      await selectPair(t);
      await t.enterText(
        find.byKey(const Key('exerciseReportComment')),
        '再試行する内容',
      );
      repo.pending = Completer<void>();
      final send = t
          .widget<FilledButton>(find.byKey(const Key('sendExerciseReport')))
          .onPressed!;
      send();
      send();
      await t.pump();
      expect(repo.batches.length, 1);
      expect(
        t
            .widget<TextField>(find.byKey(const Key('exerciseReportComment')))
            .enabled,
        false,
      );
      expect(
        t
            .widget<OutlinedButton>(
              find.byKey(const Key('exerciseReportTarget')),
            )
            .onPressed,
        isNull,
      );
      expect(
        t
            .widget<TextButton>(find.widgetWithText(TextButton, 'キャンセル'))
            .onPressed,
        isNull,
      );
      await t.tapAt(const Offset(2, 2));
      await t.binding.handlePopRoute();
      await t.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      repo.pending!.completeError(
        const PostgrestException(
          message: 'Please wait before reporting again',
          code: 'P0001',
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('10分ほど待って'), findsOneWidget);
      expect(find.text('2件をまとめて送信'), findsOneWidget);
      expect(find.text('再試行する内容'), findsOneWidget);
      repo.pending = null;
      await t.tap(find.byKey(const Key('sendExerciseReport')));
      await t.pumpAndSettle();
      expect(repo.batches.length, 2);
      expect(repo.batches.first, repo.batches.last);
      expect(repo.comments.first, repo.comments.last);
      expect(find.byType(AlertDialog), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'kind switch clears incompatible targets and incorrect filter limits choices',
    (t) async {
      await openReport(t);
      await selectPair(t);
      await t.tap(find.byKey(const Key('exerciseReportKind')));
      await t.pumpAndSettle();
      await t.tap(find.text('表示されているができない').last);
      await t.pumpAndSettle();
      expect(find.byType(InputChip), findsNothing);
      await t.tap(find.byKey(const Key('exerciseReportTarget')));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const Key('placeExerciseSearch')),
        'dumbbell curl',
      );
      await t.pumpAndSettle();
      expect(find.text('該当する種目がありません'), findsOneWidget);
      expect(repo.batches, isEmpty);
    },
  );

  testWidgets(
    'picker respects limit, allows removal and has usable small keyboard layout',
    (t) async {
      t.view.physicalSize = const Size(320, 568);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetViewInsets);
      final ids = ExerciseFormCatalog.entries
          .take(20)
          .map((e) => e.exerciseId)
          .toSet();
      final extra = ExerciseFormCatalog.entries.firstWhere(
        (e) => !ids.contains(e.exerciseId),
      );
      Set<String>? result;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await selectPlaceExercises(context, selected: ids);
                },
                child: const Text('選択'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('選択'));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const Key('placeExerciseSearch')),
        extra.exerciseName,
      );
      await t.pumpAndSettle();
      final extraRow = find.byKey(
        ValueKey('choosePlaceExercise${extra.exerciseId}'),
      );
      await t.scrollUntilVisible(
        extraRow,
        140,
        scrollable: find.descendant(
          of: find.byKey(const Key('placeExerciseResults')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(t.widget<ListTile>(extraRow).enabled, false);
      await chooseExercise(t, ids.first);
      expect(find.text('対象種目を選択（19件）'), findsOneWidget);
      await chooseExercise(t, extra.exerciseId);
      expect(find.text('対象種目を選択（20件）'), findsOneWidget);
      t.view.viewInsets = const FakeViewPadding(bottom: 240);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(
        find.byKey(const Key('confirmPlaceExercises')).hitTestable(),
        findsOneWidget,
      );
      await t.tap(find.byKey(const Key('confirmPlaceExercises')));
      await t.pumpAndSettle();
      expect(result!.length, 20);
      expect(ids.length, 20);
      expect(result, isNot(contains(ids.first)));
      expect(result, contains(extra.exerciseId));
    },
  );
}
