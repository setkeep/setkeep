import 'support/signed_in_auth.dart';

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/design/app_colors.dart';
import 'package:setkeep/main.dart';

(int, int) pngSize(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  return (data.getUint32(16), data.getUint32(20));
}

void main() {
  test('SNS lockup has transparent spacing and no tagline artwork', () async {
    final codec = await ui.instantiateImageCodec(
      File('assets/brand/setkeep_share_lockup.png').readAsBytesSync(),
    );
    final image = (await codec.getNextFrame()).image;
    final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    int alphaAt(int x, int y) => rgba.getUint8((y * image.width + x) * 4 + 3);
    expect((image.width, image.height), (1280, 696));
    expect(alphaAt(0, 0), 0);
    expect(alphaAt(640, 480), 0); // No white card between mark and wordmark.
    expect(alphaAt(640, 580), greaterThan(200)); // SETKEEP wordmark.
    expect(alphaAt(640, 695), 0); // No source tagline below it.
    var antialiasedPixels = 0;
    for (var offset = 3; offset < rgba.lengthInBytes; offset += 4) {
      final alpha = rgba.getUint8(offset);
      if (alpha > 0 && alpha < 255) antialiasedPixels++;
    }
    expect(antialiasedPixels, greaterThan(500));
    final vector = File('assets/brand/setkeep_share_vector.svg')
        .readAsStringSync();
    expect(vector, contains('viewBox="0 0 320 174"'));
    expect(vector, contains('<path'));
    expect(vector, isNot(contains('<image')));
    expect(vector, isNot(contains('<text'))); // Preserve custom lettering.
    image.dispose();
    codec.dispose();
  });

  testWidgets('app theme matches the pre-brand-color theme from 1de3c7d', (
    tester,
  ) async {
    late MaterialApp app;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          app = const SetkeepApp(
            auth: SignedInTestAuth(),
          ).build(context) as MaterialApp;
          return const SizedBox();
        },
      ),
    );
    // Historical theme: preserve generated foregrounds and disabled states too.
    expect(
      app.theme,
      ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFC7F36B),
          primary: const Color(0xFF101820),
          secondary: const Color(0xFFC7F36B),
          surface: const Color(0xFFF4F5F0),
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F5F0),
        fontFamily: '.SF Pro Display',
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: Colors.white,
        ),
      ),
    );
    expect(app.themeMode, ThemeMode.system);
    expect(app.darkTheme, isNull);
  });

  test('SETKEEP green palette uses the approved brand color', () {
    expect(AppColors.primaryGreen, const Color(0xFFC7F36B));
    expect(AppColors.primaryGreenStrong, const Color(0xFF83AD30));
    expect(AppColors.primaryGreenDeep, const Color(0xFF6B8E23));
    expect(AppColors.primaryGreenSoft, const Color(0xFFE9F4D1));
    expect(AppColors.primaryGreenVerySoft, const Color(0xFFEFF2EA));
  });

  test('launcher icon sets contain the required source dimensions', () {
    expect(
      pngSize(
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
        'Icon-App-1024x1024@1x.png',
      ),
      (1024, 1024),
    );
    for (final entry in {
      'mipmap-mdpi': 48,
      'mipmap-hdpi': 72,
      'mipmap-xhdpi': 96,
      'mipmap-xxhdpi': 144,
      'mipmap-xxxhdpi': 192,
    }.entries) {
      expect(pngSize('android/app/src/main/res/${entry.key}/ic_launcher.png'), (
        entry.value,
        entry.value,
      ));
    }
  });

  test('native splash lockups use the approved general and trainer artwork', () {
    final android = File(
      'android/app/src/main/res/drawable/launch_background.xml',
    ).readAsStringSync();
    final ios = File('ios/Runner/Base.lproj/LaunchScreen.storyboard')
        .readAsStringSync();
    final trainerAndroid = File(
      'apps/setkeep_trainer/android/app/src/main/res/drawable/launch_background.xml',
    ).readAsStringSync();
    final trainerIos = File(
      'apps/setkeep_trainer/ios/Runner/Base.lproj/LaunchScreen.storyboard',
    ).readAsStringSync();
    final artwork = File('tool/export_native_splash.swift').readAsStringSync();

    expect(android, contains('@color/setkeep_background'));
    expect(android, contains('@drawable/launch_logo'));
    expect(android, contains('@drawable/launch_progress'));
    expect(ios, contains('image="LaunchImage"'));
    expect(ios, contains('splash-track'));
    expect(ios, isNot(contains('splash-accent')));
    for (final theme in [
      'android/app/src/main/res/values-v31/styles.xml',
      'android/app/src/main/res/values-night-v31/styles.xml',
      'apps/setkeep_trainer/android/app/src/main/res/values-v31/styles.xml',
      'apps/setkeep_trainer/android/app/src/main/res/values-night-v31/styles.xml',
    ]) {
      expect(
        File(theme).readAsStringSync(),
        contains('windowSplashScreenBrandingImage'),
      );
    }
    expect(trainerAndroid, contains('@color/trainer_background'));
    expect(trainerAndroid, contains('@drawable/launch_logo'));
    expect(trainerAndroid, contains('@drawable/launch_progress'));
    expect(trainerIos, contains('image="LaunchImage"'));
    expect(trainerIos, contains('splash-track'));
    expect(trainerIos, isNot(contains('splash-accent')));
    expect(artwork, contains('assets/brand/setkeep_splash_lockup_source.png'));
    expect(artwork, contains('drawWord("TRAINER"'));
    expect(pngSize('assets/brand/setkeep_splash_lockup_source.png'), (
      460,
      270,
    ));
    for (final prefix in ['', 'apps/setkeep_trainer/']) {
      final logicalSize = prefix.isEmpty ? 240 : 180;
      for (final scale in [1, 2, 3]) {
        final suffix = scale == 1 ? '' : '@${scale}x';
        expect(
          pngSize(
            '${prefix}ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage$suffix.png',
          ),
          (logicalSize * scale, logicalSize * scale),
        );
      }
      for (final density in {
        'mdpi': 180,
        'hdpi': 270,
        'xhdpi': 360,
        'xxhdpi': 540,
        'xxxhdpi': 720,
      }.entries) {
        expect(
          pngSize(
            '${prefix}android/app/src/main/res/drawable-${density.key}/launch_logo.png',
          ),
          (density.value, density.value),
        );
        expect(
          pngSize(
            '${prefix}android/app/src/main/res/drawable-${density.key}/launch_progress.png',
          ),
          ((density.value * 200 ~/ 180), (density.value * 80 ~/ 180)),
        );
      }
    }
  });

  test('native progress artwork starts with an empty track', () async {
    for (final prefix in ['', 'apps/setkeep_trainer/']) {
      final codec = await ui.instantiateImageCodec(
        File(
          '${prefix}android/app/src/main/res/drawable-mdpi/launch_progress.png',
        ).readAsBytesSync(),
      );
      final image = (await codec.getNextFrame()).image;
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      (int, int, int) rgb(int x, int y) {
        final i = (y * image.width + x) * 4;
        return (
          bytes.getUint8(i),
          bytes.getUint8(i + 1),
          bytes.getUint8(i + 2),
        );
      }

      expect(rgb(15, 39), rgb(100, 39));
      expect(rgb(100, 39), rgb(185, 39));
      image.dispose();
      codec.dispose();
    }
  });
}
