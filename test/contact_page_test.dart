import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:setkeep/inquiry/contact_message.dart';
import 'package:setkeep/main.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class SyntheticContactPicker extends ImagePickerPlatform {
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async => XFile('/tmp/setkeep-synthetic-attachment.png');
}

class SyntheticContactLauncher extends UrlLauncherPlatform {
  final urls = <String>[];
  final modes = <PreferredLaunchMode>[];
  Future<bool> Function()? onLaunch;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    urls.add(url);
    modes.add(options.mode);
    return onLaunch == null ? true : await onLaunch!();
  }
}

void main() {
  const channel = MethodChannel('dev.fluttercommunity.plus/share');
  final calls = <MethodCall>[];
  Future<String?> Function(MethodCall)? onShare;
  late SyntheticContactLauncher launcher;
  late UrlLauncherPlatform previousLauncher;

  setUp(() {
    calls.clear();
    onShare = null;
    previousLauncher = UrlLauncherPlatform.instance;
    launcher = SyntheticContactLauncher();
    UrlLauncherPlatform.instance = launcher;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return onShare == null ? '' : await onShare!(call);
        });
  });

  tearDown(() {
    UrlLauncherPlatform.instance = previousLauncher;
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> openForm(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ContactPage()));
    await tester.pumpAndSettle();
  }

  Future<void> fillForm(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const Key('contactSubjectField')),
      ' 日本語 & + question ',
    );
    await tester.enterText(
      find.byKey(const Key('contactMessageField')),
      ' Synthetic body & +\n日本語 ',
    );
  }

  String caseId(WidgetTester tester) => tester
      .widget<SelectableText>(find.byKey(const Key('contactCaseId')))
      .data!
      .replaceFirst('案件ID：', '');

  Future<void> compose(WidgetTester tester, {bool share = false}) async {
    final button = find.byKey(
      Key(share ? 'shareContactButton' : 'sendContactButton'),
    );
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  test('case ID date uses UTC and contains only an opaque token', () {
    final id = createContactCaseId(
      now: DateTime.parse('2026-10-09T00:30:00+09:00'),
    );
    expect(id, matches(RegExp(r'^SKQ-20261008-[A-F0-9]{12}$')));
  });

  testWidgets('empty form cannot open mail or sharing', (tester) async {
    await openForm(tester);
    await compose(tester);
    expect(calls, isEmpty);
    expect(launcher.urls, isEmpty);
    expect(find.text('件名を入力してください'), findsOneWidget);
    expect(find.text('問い合わせ内容を入力してください'), findsOneWidget);
  });

  testWidgets(
    'mail composer sets recipient and matching case ID',
    (tester) async {
      await openForm(tester);
      await fillForm(tester);
      final id = caseId(tester);
      await compose(tester);
      expect(calls, isEmpty);
      expect(launcher.urls, hasLength(1));
      expect(launcher.modes.single, PreferredLaunchMode.externalApplication);
      final uri = Uri.parse(launcher.urls.single);
      expect(uri.scheme, 'mailto');
      expect(uri.path, contactSupportEmail);
      expect(uri.queryParameters.keys, unorderedEquals(['subject', 'body']));
      expect(uri.queryParameters['subject'], '[$id][不具合報告] 日本語 & + question');
      expect(uri.queryParameters['body'], contains('案件ID：$id'));
      expect(uri.queryParameters['body'], contains('Synthetic body & +\n日本語'));
      expect(uri.query, isNot(contains('+')));
      expect(uri.query, contains('%20'));
      expect(find.text('送信完了'), findsNothing);
      expect(caseId(tester), id);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'explicit share fallback preserves the same ID and does not claim delivery',
    (tester) async {
      onShare = (_) async => 'com.example.mail';
      await openForm(tester);
      await fillForm(tester);
      final id = caseId(tester);
      await compose(tester, share: true);
      expect(calls, hasLength(1));
      final args = Map<String, dynamic>.from(calls.single.arguments as Map);
      expect(args['subject'], '[$id][不具合報告] 日本語 & + question');
      expect(args['text'], contains('案件ID：$id'));
      expect(args, isNot(contains('paths')));
      expect(find.textContaining('開いただけでは送信は完了しません'), findsOneWidget);
      expect(find.textContaining('ログイン用トークンは送らないでください'), findsOneWidget);
      expect(find.text('送信完了'), findsNothing);
      await compose(tester);
      expect(
        Uri.parse(launcher.urls.single).queryParameters['subject'],
        args['subject'],
      );
      expect(caseId(tester), id);
    },
  );

  testWidgets('unavailable or failing mail keeps draft and case ID for retry', (
    tester,
  ) async {
    await openForm(tester);
    await fillForm(tester);
    final id = caseId(tester);
    launcher.onLaunch = () async => false;
    await compose(tester);
    expect(find.text('送信画面を開けませんでした'), findsOneWidget);
    expect(caseId(tester), id);
    launcher.onLaunch = () async =>
        throw PlatformException(code: 'synthetic_failure');
    await compose(tester);
    launcher.onLaunch = () async => true;
    await compose(tester);
    expect(launcher.urls, hasLength(3));
    for (final url in launcher.urls) {
      expect(
        Uri.parse(url).queryParameters['body'],
        contains('Synthetic body & +\n日本語'),
      );
      expect(Uri.parse(url).queryParameters['body'], contains('案件ID：$id'));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'optional image is shared and is never silently dropped into mailto',
    (tester) async {
      final previousPicker = ImagePickerPlatform.instance;
      ImagePickerPlatform.instance = SyntheticContactPicker();
      addTearDown(() => ImagePickerPlatform.instance = previousPicker);
      await openForm(tester);
      await fillForm(tester);
      final id = caseId(tester);
      await tester.ensureVisible(find.byKey(const Key('contactImageButton')));
      await tester.tap(find.byKey(const Key('contactImageButton')));
      await tester.pumpAndSettle();
      await compose(tester);
      expect(launcher.urls, isEmpty);
      final args = Map<String, dynamic>.from(calls.single.arguments as Map);
      expect(args['paths'], ['/tmp/setkeep-synthetic-attachment.png']);
      expect(args['text'], contains('案件ID：$id'));
      await tester.ensureVisible(find.text('添付を外す'));
      await tester.tap(find.text('添付を外す'));
      await tester.pumpAndSettle();
      await compose(tester);
      expect(launcher.urls, hasLength(1));
      expect(caseId(tester), id);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pending composer disables both repeated mail and sharing', (
    tester,
  ) async {
    final completion = Completer<bool>();
    launcher.onLaunch = () => completion.future;
    await openForm(tester);
    await fillForm(tester);
    await compose(tester);
    expect(launcher.urls, hasLength(1));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('sendContactButton')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('shareContactButton')))
          .onPressed,
      isNull,
    );
    completion.complete(true);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('sendContactButton')))
          .onPressed,
      isNotNull,
    );
  });
}
