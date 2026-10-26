import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/ads/ads_config.dart';
import 'package:setkeep/ads/banner_backend.dart';
import 'package:setkeep/ads/setkeep_banner_ad.dart';
import 'package:setkeep/ads/workout_interstitial.dart';
import 'package:setkeep/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoBanner implements BannerBackend {
  @override
  bool get supported => false;
  @override
  Future<BannerHandle?> load(
    int width,
    String id,
    BannerRequest request,
  ) async => null;
}

class _FakeAd implements InterstitialHandle {
  int shows = 0;
  int disposals = 0;
  bool showSucceeds = true;
  Completer<void>? pending;
  @override
  Future<bool> show({required Future<void> Function() onShown}) async {
    shows++;
    await pending?.future;
    if (showSucceeds) await onShown();
    return showSucceeds;
  }

  @override
  void dispose() => disposals++;
}

class _FakeBackend implements InterstitialBackend {
  _FakeBackend(this.ad);
  final _FakeAd ad;
  int loads = 0;
  bool fail = false;
  bool pending = false;
  Duration? delay;
  Completer<InterstitialHandle?>? loading;
  @override
  bool get supported => true;
  @override
  Future<InterstitialHandle?> load(String unitId) async {
    loads++;
    if (fail) throw StateError('offline');
    if (delay != null) await Future<void>.delayed(delay!);
    if (pending) {
      loading = Completer<InterstitialHandle?>();
      return loading!.future;
    }
    return ad;
  }
}

Future<WorkoutInterstitialSession?> _finish(
  AdsEntitlement entitlement,
  _FakeBackend backend, {
  AdsConfig config = const AdsConfig(generalApp: true),
  SharedPreferences? preferences,
  WorkoutInterstitialPolicy policy = const WorkoutInterstitialPolicy(),
}) => WorkoutInterstitialSession.prepareForWorkoutCompletion(
  config: config,
  entitlement: entitlement,
  platform: TargetPlatform.android,
  backend: backend,
  preferences: preferences,
  policy: policy,
);

String _draft() => jsonEncode({
  'date': DateTime(2026, 9, 30, 18).toIso8601String(),
  'gymName': '自宅',
  'exercises': [
    {
      'name': 'ベンチプレス',
      'exerciseId': 'bench_press',
      'bodyPart': '胸',
      'equipment': 'フリーウェイト',
      'sets': [
        {'weight': 50, 'reps': 8, 'completed': true},
      ],
    },
  ],
});

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WorkoutUiPreference.completionCheckEnabled = true;
    WorkoutUiPreference.workoutTimerEnabled = false;
    RestTimerPreference.enabled = false;
  });

  testWidgets('test IDs and TRAINER/production fail closed', (tester) async {
    const config = AdsConfig(generalApp: true);
    expect(
      config.interstitialId(TargetPlatform.android),
      'ca-app-pub-3940256099942544/1033173712',
    );
    expect(
      config.interstitialId(TargetPlatform.iOS),
      'ca-app-pub-3940256099942544/4411468910',
    );
    expect(config.interstitialId(TargetPlatform.macOS), isNull);
    expect(const AdsConfig().interstitialId(TargetPlatform.android), isNull);
    expect(
      const AdsConfig(
        generalApp: true,
        mode: 'production',
      ).interstitialId(TargetPlatform.android),
      isNull,
    );
    final entitlement = AdsEntitlement();
    final backend = _FakeBackend(_FakeAd());
    expect(
      await _finish(entitlement, backend, config: const AdsConfig()),
      isNull,
    );
    expect(backend.loads, 0);
    entitlement.dispose();
  });

  testWidgets('actual display is limited to once per local calendar day', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final entitlement = AdsEntitlement();
    final backend = _FakeBackend(_FakeAd());
    final octoberFirst = WorkoutInterstitialPolicy(
      () => DateTime(2026, 10, 1, 23, 50),
    );
    final first = await _finish(
      entitlement,
      backend,
      preferences: prefs,
      policy: octoberFirst,
    );
    await tester.pump();
    expect(first, isNotNull);
    await first!.tryShow();
    expect(backend.ad.shows, 1);
    expect(
      prefs.getString(WorkoutInterstitialPolicy.lastShownLocalDateKey),
      '2026-10-01',
    );
    expect(
      await _finish(
        entitlement,
        backend,
        preferences: prefs,
        policy: octoberFirst,
      ),
      isNull,
    );
    expect(backend.loads, 1);

    final octoberSecond = WorkoutInterstitialPolicy(
      () => DateTime(2026, 10, 2, 0, 10),
    );
    final nextDay = await _finish(
      entitlement,
      backend,
      preferences: prefs,
      policy: octoberSecond,
    );
    expect(
      nextDay,
      isNotNull,
      reason: 'local date changed after only 20 minutes',
    );
    nextDay!.dispose();
    first.dispose();
    entitlement.dispose();
  });

  testWidgets(
    'old completion counter is ignored and first completion is eligible',
    (tester) async {
      SharedPreferences.setMockInitialValues({'ads_completed_workouts_v1': 1});
      final entitlement = AdsEntitlement();
      final backend = _FakeBackend(_FakeAd());
      final session = await _finish(entitlement, backend);
      await tester.pump();
      expect(session, isNotNull);
      expect(backend.loads, 1);
      session!.dispose();
      entitlement.dispose();
    },
  );

  testWidgets('load and show failures do not consume the daily allowance', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final entitlement = AdsEntitlement();
    final failedBackend = _FakeBackend(_FakeAd())..fail = true;
    final failedLoad = await _finish(
      entitlement,
      failedBackend,
      preferences: prefs,
    );
    await tester.pump();
    await failedLoad!.tryShow();
    expect(
      prefs.getString(WorkoutInterstitialPolicy.lastShownLocalDateKey),
      isNull,
    );
    failedLoad.dispose();

    final failedAd = _FakeAd()..showSucceeds = false;
    final failedShow = await _finish(
      entitlement,
      _FakeBackend(failedAd),
      preferences: prefs,
    );
    await tester.pump();
    await failedShow!.tryShow();
    expect(failedAd.shows, 1);
    expect(
      prefs.getString(WorkoutInterstitialPolicy.lastShownLocalDateKey),
      isNull,
    );
    failedShow.dispose();

    final retryBackend = _FakeBackend(_FakeAd());
    final retry = await _finish(entitlement, retryBackend, preferences: prefs);
    await tester.pump();
    expect(retry, isNotNull);
    await retry!.tryShow();
    expect(retryBackend.ad.shows, 1);
    retry.dispose();
    entitlement.dispose();
  });

  testWidgets('tryShow waits briefly for a 500ms preload race', (tester) async {
    final entitlement = AdsEntitlement();
    final backend = _FakeBackend(_FakeAd())
      ..delay = const Duration(milliseconds: 500);
    final session = await _finish(entitlement, backend);
    final showing = session!.tryShow();
    await tester.pump(const Duration(milliseconds: 500));
    await showing;
    expect(backend.ad.shows, 1);
    session.dispose();
    entitlement.dispose();
  });

  testWidgets(
    'failed early preload can retry at completion without a retry loop',
    (tester) async {
      final entitlement = AdsEntitlement();
      final backend = _FakeBackend(_FakeAd())..fail = true;
      final session = await _finish(entitlement, backend);
      await tester.pump();
      expect(backend.loads, 1);
      backend.fail = false;
      session!.preload();
      await tester.pump();
      expect(backend.loads, 2);
      await session.tryShow();
      expect(backend.ad.shows, 1);
      session.dispose();
      entitlement.dispose();
    },
  );

  testWidgets('permission interruption reloads on resume before completion', (
    tester,
  ) async {
    final entitlement = AdsEntitlement();
    final backend = _FakeBackend(_FakeAd());
    final session = await _finish(entitlement, backend);
    await tester.pump();
    expect(backend.loads, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(backend.ad.disposals, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(backend.loads, 2);
    await session!.tryShow();
    expect(backend.ad.shows, 1);
    session.dispose();
    entitlement.dispose();
  });

  testWidgets('interrupted delayed load cannot replace resumed preload', (
    tester,
  ) async {
    final entitlement = AdsEntitlement();
    final backend = _FakeBackend(_FakeAd())..pending = true;
    final session = await _finish(entitlement, backend);
    final oldLoad = backend.loading!;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    backend.pending = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    final stale = _FakeAd();
    oldLoad.complete(stale);
    await tester.pump();
    expect(stale.disposals, 1);
    await session!.tryShow();
    expect(stale.shows, 0);
    expect(backend.ad.shows, 1);
    session.dispose();
    entitlement.dispose();
  });

  testWidgets('adFree, unloaded, background and dispose remain safe', (
    tester,
  ) async {
    final entitlement = AdsEntitlement(adFree: true);
    final backend = _FakeBackend(_FakeAd());
    expect(await _finish(entitlement, backend), isNull);
    expect(backend.loads, 0);

    entitlement.adFree = false;
    backend.pending = true;
    final unloaded = await _finish(entitlement, backend);
    final skipped = unloaded!.tryShow();
    await tester.pump(WorkoutInterstitialSession.loadWaitBeforeNavigation);
    await skipped;
    expect(unloaded.attempted, true);
    expect(backend.ad.shows, 0);
    backend.loading!.complete(backend.ad);
    await tester.pump();
    expect(backend.ad.disposals, greaterThan(0));
    unloaded.dispose();

    backend.pending = false;
    final background = await _finish(entitlement, backend);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await background!.tryShow();
    expect(backend.ad.shows, 0);
    background.dispose();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    entitlement.dispose();
  });

  testWidgets(
    'same workout can show at most once and late callbacks are safe',
    (tester) async {
      final entitlement = AdsEntitlement();
      final backend = _FakeBackend(_FakeAd()..pending = Completer<void>());
      final session = await _finish(entitlement, backend);
      await tester.pump();
      final first = session!.tryShow();
      await session.tryShow();
      expect(backend.ad.shows, 1);
      backend.ad.pending!.complete();
      await first;
      session.dispose();
      await session.tryShow();
      expect(backend.ad.shows, 1);
      entitlement.dispose();
    },
  );

  testWidgets('no-save exit attempts ad after saved workout, once', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      activeWorkoutDraftStorageKey: _draft(),
    });
    final entitlement = AdsEntitlement();
    final backend = _FakeBackend(_FakeAd());
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AdsScope(
          config: const AdsConfig(generalApp: true),
          entitlement: entitlement,
          backend: _NoBanner(),
          interstitialBackend: backend,
          child: child!,
        ),
        home: const HomeShell(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('activeWorkoutDraftCard')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('completeWorkoutButton')));
    await tester.pumpAndSettle();
    expect(find.text('トレーニング完了'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(
      decodeWorkoutHistory(prefs.getString('workout_history')),
      hasLength(1),
    );
    expect(prefs.getString(activeWorkoutDraftStorageKey), isNull);
    await tester.tap(find.byKey(const Key('completeWithoutSharingButton')));
    await tester.pumpAndSettle();
    expect(backend.ad.shows, 1);
    expect(find.byType(DashboardPage), findsOneWidget);
    expect(find.byType(WorkoutPage), findsNothing);
    entitlement.dispose();
  });

  testWidgets('saved image shows then returns home; Back does not show twice', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      activeWorkoutDraftStorageKey: _draft(),
    });
    int saves = 0;
    WorkoutImageService.captureOverride = () async => Uint8List(1);
    WorkoutImageService.saveOverride = (_) async {
      saves++;
    };
    addTearDown(() {
      WorkoutImageService.captureOverride = null;
      WorkoutImageService.saveOverride = null;
    });
    final entitlement = AdsEntitlement();
    final backend = _FakeBackend(_FakeAd());
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AdsScope(
          config: const AdsConfig(generalApp: true),
          entitlement: entitlement,
          backend: _NoBanner(),
          interstitialBackend: backend,
          child: child!,
        ),
        home: const HomeShell(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('activeWorkoutDraftCard')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('completeWorkoutButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('completeAndPreviewShareButton')));
    await tester.pumpAndSettle();
    expect(find.byType(WorkoutSharePage), findsOneWidget);
    await tester.tap(find.byKey(const Key('shareWorkoutImageButton')));
    for (var i = 0; i < 30 && saves == 0; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    for (
      var i = 0;
      i < 20 && find.byType(WorkoutSharePage).evaluate().isNotEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(saves, 1);
    expect(backend.ad.shows, 1);
    expect(find.byType(WorkoutSharePage), findsNothing);
    expect(find.byType(DashboardPage), findsOneWidget);
    entitlement.dispose();
  });
}
