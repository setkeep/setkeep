import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setkeep/main.dart';
import 'package:setkeep/admin/report_repository.dart';

import 'report_management_test.dart' show FakeReports;
import 'support/signed_in_auth.dart';
import 'support/legal_consent_fixture.dart';

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'onboarding_completed': true,
      'legal_consent': acceptedLegalConsentJson,
    }),
  );
  tearDown(() => ReportServices.override = null);
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'admin management is absent from My Page and About on $platform',
      (t) async {
        ReportServices.override = FakeReports();
        t.view.physicalSize = const Size(800, 1800);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await t.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
        await t.pumpAndSettle();
        await t.tap(find.byIcon(Icons.person_outline_rounded));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('reportAdminEntry')), findsNothing);
        expect(find.text('報告管理'), findsNothing);
        await t.ensureVisible(find.byKey(const Key('appAboutButton')));
        await t.tap(find.byKey(const Key('appAboutButton')));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('reportAdminEntry')), findsNothing);
        expect(find.text('報告管理'), findsNothing);
        expect(t.takeException(), isNull);
      },
      variant: TargetPlatformVariant({platform}),
    );
    testWidgets('non-admin About keeps management hidden on $platform', (
      t,
    ) async {
      ReportServices.override = FakeReports()..admin = false;
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: const AppAboutPage(),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('reportAdminEntry')), findsNothing);
      expect(find.text('報告管理'), findsNothing);
      expect(t.takeException(), isNull);
    });
  }
}
