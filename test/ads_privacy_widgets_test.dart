import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:setkeep/ads/ads_config.dart';
import 'package:setkeep/ads/ads_consent.dart';
import 'package:setkeep/ads/ads_privacy_tile.dart';
import 'package:setkeep/ads/banner_backend.dart';
import 'package:setkeep/ads/setkeep_banner_ad.dart';

import 'support/ads_consent_backend.dart';

class _Banner implements BannerHandle {
  int disposals = 0;
  @override
  VoidCallback? onUnavailable;
  @override
  Size get size => const Size(320, 50);
  @override
  Widget build() => const Text('test banner');
  @override
  void dispose() => disposals++;
}

class _Backend implements BannerBackend {
  final pending = Completer<BannerHandle?>();
  int loads = 0;
  @override
  bool get supported => true;
  @override
  Future<BannerHandle?> load(int width, String id, BannerRequest request) {
    loads++;
    return pending.future;
  }
}

void main() {
  for (final language in ['ja', 'en']) {
    testWidgets('privacy entry visibility and failure recovery in $language', (
      tester,
    ) async {
      final backend = FakeConsent()..required = false;
      final consent = AdsConsent(backend);
      await consent.prepare();
      final title = language == 'en' ? 'Ad privacy settings' : '広告のプライバシー設定';
      final error = language == 'en'
          ? 'Could not open settings. Please try again.'
          : '設定を開けませんでした。もう一度お試しください。';
      Widget app() => MaterialApp(
        locale: Locale(language),
        supportedLocales: const [Locale('ja'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: AdsPrivacyTile(consent: consent)),
      );
      await tester.pumpWidget(app());
      expect(find.text(title), findsNothing);
      consent.privacyRequired = true;
      await tester.pumpWidget(app());
      expect(find.text(title), findsOneWidget);
      backend.optionsFails = true;
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      expect(find.text(error), findsOneWidget);
      expect(await consent.ready(), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      consent.dispose();
    });
  }

  testWidgets('privacy failure removes a banner and disposes its late load', (
    tester,
  ) async {
    final consentBackend = FakeConsent()..optionsFails = true;
    final consent = AdsConsent(consentBackend);
    await consent.prepare();
    final backend = _Backend();
    final entitlement = AdsEntitlement();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: AdsScope(
          config: const AdsConfig(generalApp: true),
          entitlement: entitlement,
          backend: backend,
          child: Scaffold(body: SetkeepBannerAd(consent: consent)),
        ),
      ),
    );
    expect(backend.loads, 1);
    await expectLater(consent.showOptions(), throwsStateError);
    await tester.pump();
    final ad = _Banner();
    backend.pending.complete(ad);
    await tester.pumpAndSettle();
    expect(ad.disposals, 1);
    expect(find.text('test banner'), findsNothing);
    expect(backend.loads, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    entitlement.dispose();
    consent.dispose();
  });

  testWidgets(
    'options remain exclusive while privacy requirement is refreshing',
    (tester) async {
      final backend = FakeConsent()..afterOptionsAllowed = true;
      final consent = AdsConsent(backend);
      await consent.ready();
      backend.pendingPrivacy = Completer<bool>();
      final options = consent.showOptions();
      await tester.pump();
      expect(consent.optionsOpen, isTrue);
      expect(await consent.ready(), isFalse);
      await consent.showOptions();
      expect(backend.events.where((e) => e == 'options'), hasLength(1));
      await tester.pump(AdsConsent.nonInteractiveTimeout);
      await options;
      expect(consent.optionsOpen, isFalse);
      expect(await consent.ready(), isFalse);
      backend.pendingPrivacy!.complete(true);
      await tester.pump();
      consent.dispose();
    },
  );
}
