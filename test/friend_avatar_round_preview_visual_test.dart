import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/design/family_theme.dart';
import 'package:setkeep/friends/friends_ui.dart';

import 'friend_release_feedback_test.dart'
    show ClosedFriends, PhotoClient, PhotoRequest, PhotoResponse, settlePhotos;

class FixturePhotoClient extends PhotoClient {
  FixturePhotoClient(this.fixture);
  final Uint8List fixture;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      FixturePhotoRequest(fixture);
}

class FixturePhotoRequest extends PhotoRequest {
  FixturePhotoRequest(this.fixture);
  final Uint8List fixture;
  @override
  Future<HttpClientResponse> close() async => FixturePhotoResponse(fixture);
}

class FixturePhotoResponse extends PhotoResponse {
  FixturePhotoResponse(this.fixture);
  final Uint8List fixture;
  @override
  Uint8List get bytes => fixture;
}

void main() {
  testWidgets('synthetic circular photo visual QA without panel or X', (
    t,
  ) async {
    await t.runAsync(() async {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final font = File('/System/Library/Fonts/Hiragino Sans GB.ttc');
      if (await font.exists()) {
        await (FontLoader(
          'RoundPhotoJapanese',
        )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
      }
    });
    final fixture = (await rootBundle.load('assets/vital_thumbnails/0042.png'))
        .buffer
        .asUint8List();
    debugNetworkImageHttpClientProvider = () => FixturePhotoClient(fixture);
    addTearDown(() => debugNetworkImageHttpClientProvider = null);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPadding);
    final theme = familyTheme();
    for (final size in [
      (const Size(390, 844), 1.0),
      (const Size(320, 844), 2.0),
      (const Size(844, 390), 2.0),
    ]) {
      t.view.physicalSize = size.$1;
      t.view.devicePixelRatio = 1;
      t.view.padding = const FakeViewPadding(bottom: 24);
      final key = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('ja'),
            supportedLocales: const [Locale('ja'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: theme.copyWith(
              textTheme: theme.textTheme.apply(
                fontFamily: 'RoundPhotoJapanese',
              ),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(size.$2)),
              child: child!,
            ),
            home: FriendActivityPage(
              repository: ClosedFriends()..hasPhoto = true,
              owner: 'friend',
              selectedId: 'workout',
            ),
          ),
        ),
      );
      await settlePhotos(t);
      await t.tap(find.byKey(const Key('viewFriendProfilePhoto')));
      await settlePhotos(t);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
      expect(find.byKey(const Key('friendProfilePhotoCircle')), findsOneWidget);
      Future<void> capture(String section) async {
        await t.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          try {
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File(
              '/tmp/setkeep_round_photo_qa/'
              '$section-${size.$1.width.toInt()}x${size.$1.height.toInt()}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(
              data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            );
          } finally {
            image.dispose();
          }
        });
      }

      await capture('round-preview');
      await t.tap(find.byKey(const Key('dismissFriendProfilePhoto')));
      await settlePhotos(t);
      expect(find.byKey(const Key('friendProfilePhotoPreview')), findsNothing);
      await capture('returned-calendar');
      expect(t.takeException(), isNull);
    }
    await t.pumpWidget(const SizedBox.shrink());
    debugNetworkImageHttpClientProvider = null;
  });
}
