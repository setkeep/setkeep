import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:setkeep/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.setkeep.app/rest_timer');
  Future<Map<String, dynamic>> status() async {
    // NotificationManager updates are asynchronous to the method-channel reply.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return (await channel.invokeMapMethod<String, dynamic>('debugStatus'))!;
  }
  Future<void> action(String action) async {
    await channel.invokeMethod<void>('debugRestAction', {'action': action});
    // PendingIntent.send enqueues a broadcast; observe after receiver delivery.
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  Map<dynamic, dynamic> notification(Map<String, dynamic> s) =>
      (s['ongoingDetails'] as List).single as Map;
  void countdown(Map<dynamic, dynamic> n, int seconds) {
    expect(n['chronometer'], true);
    expect(n['countdown'], true);
    expect(n['when'], greaterThan(DateTime.now().millisecondsSinceEpoch));
    expect(n['timeoutAfter'], inInclusiveRange(1, seconds * 1000));
    for (final kind in ['compact', 'expanded', 'headsUp']) {
      final v = n[kind] as Map;
      expect(v['clockVisible'], true, reason: kind);
      expect(v['fallbackVisible'], false, reason: kind);
      expect(v['countdown'], true, reason: kind);
      expect(v['clockText'], matches(RegExp(r'^\d{1,2}:\d{2}$')), reason: kind);
      expect(
        v['baseRemainingMs'],
        inInclusiveRange(1, seconds * 1000),
        reason: kind,
      );
    }
  }

  testWidgets(
    'native duration display, pause, extension, expiry and cancellation',
    (t) async {
      if (!Platform.isAndroid) return;
      await t.pumpWidget(const MaterialApp(home: Scaffold()));
      await RestNotificationService.cancel();
      final exact =
          (await RestNotificationService.state())!['exactAlarmAllowed'];
      debugPrint('QA_TIMER_PERMISSION exact=$exact');
      await RestNotificationService.schedule(90, exerciseName: 'QA');
      final first = notification(await status());
      countdown(first, 90);
      debugPrint('QA_TIMER_CAPTURE_READY');
      await Future<void>.delayed(const Duration(seconds: 4));
      await Future<void>.delayed(const Duration(seconds: 2));
      final next = notification(await status());
      countdown(next, 90);
      expect(
        (next['compact'] as Map)['baseRemainingMs'],
        lessThan((first['compact'] as Map)['baseRemainingMs']),
      );
      await action('pauseNotification');
      final paused = notification(await status());
      expect(paused['chronometer'], false);
      expect(paused['showWhen'], false);
      // Android 16 may replace no app timeout with its 3-day system cap.
      expect(
        paused['timeoutAfter'] == 0 || (paused['timeoutAfter'] as int) > 90000,
        true,
      );
      for (final kind in ['compact', 'expanded', 'headsUp']) {
        final v = paused[kind] as Map;
        expect(v['clockVisible'], false);
        expect(v['fallbackVisible'], true);
        expect(v['fallbackText'], matches(RegExp(r'^\d{2}:\d{2}$')));
      }
      final held =
          (await RestNotificationService.state())!['remainingSeconds'] as int;
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(
        (await RestNotificationService.state())!['remainingSeconds'],
        held,
      );
      await action('extendNotification');
      expect(
        (await RestNotificationService.state())!['remainingSeconds'],
        held + 30,
      );
      await action('resumeNotification');
      countdown(notification(await status()), held + 30);
      await action('extendNotification');
      countdown(notification(await status()), held + 60);
      await RestNotificationService.cancel();
      expect((await status())['delivered'], isEmpty);
      await RestNotificationService.schedule(2, exerciseName: 'QA');
      await Future<void>.delayed(const Duration(seconds: 3));
      // Observe native state before calling state(), which can complete on resume.
      final expired = await status();
      expect(expired['deadline'], 0);
      expect(expired['remainingSeconds'], 0);
      expect(expired['delivered'], isNot(contains(7340)));
      await RestNotificationService.cancel();
      await RestNotificationService.schedule(2, exerciseName: 'QA');
      await RestNotificationService.cancel();
      await Future<void>.delayed(const Duration(seconds: 3));
      expect((await status())['delivered'], isEmpty);
      debugPrint('QA_TIMER_DISPLAY_PASS exact=$exact');
    },
  );
  testWidgets(
    'deadline clears the live countdown and reconciles after lifecycle window',
    (t) async {
      if (!Platform.isAndroid) return;
      await t.pumpWidget(const MaterialApp(home: Scaffold()));
      await RestNotificationService.cancel();
      await RestNotificationService.schedule(8, exerciseName: 'QA lock');
      debugPrint('QA_TIMER_LOCK_READY');
      await Future<void>.delayed(const Duration(seconds: 25));
      final resumed = (await RestNotificationService.state())!;
      expect(resumed['phase'], 'finished');
      expect(resumed['endsAtMilliseconds'], 0);
      expect(resumed['remainingSeconds'], 0);
      expect((await status())['delivered'], isNot(contains(7340)));
      await RestNotificationService.cancel();
      debugPrint('QA_TIMER_RESUME_PASS');
    },
  );
}
