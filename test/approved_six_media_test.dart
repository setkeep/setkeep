import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/exercise_form_catalog.dart';
import 'package:setkeep/exercise_media.dart';

const approved = {
  'pallof_press': 4,
  'bayesian_curl': 3,
  'wall_sit': 2,
  'chest_supported_dumbbell_row': 5,
  'reverse_lunge': 4,
  'decline_dumbbell_fly': 5,
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'six approved versions resolve to existing IDs and bundled files',
    () async {
      final assets = (await AssetManifest.loadFromAssetBundle(rootBundle))
          .listAssets();
      final originals = ExerciseMediaCatalog.entries.where(
        (e) => e.provider == 'setkeep_original',
      );
      expect(originals.map((e) => e.exerciseId).toSet(), approved.keys.toSet());
      for (final entry in approved.entries) {
        expect(ExerciseFormCatalog.byId[entry.key], isNotNull);
        final media = ExerciseMediaCatalog.forExerciseId(entry.key)!;
        final name = '${entry.key}_white_v${entry.value}';
        expect(media.provider, 'setkeep_original');
        expect(media.assetPath, 'assets/exercise_videos/$name.mp4');
        expect(
          media.thumbnailAssetPath,
          'assets/exercise_thumbnails/$name.png',
        );
        expect(
          assets,
          containsAll([media.assetPath, media.thumbnailAssetPath]),
        );
        expect(await ExerciseMediaCatalog.isAvailable(media), isTrue);
      }
    },
  );
  test(
    'all purchased identities keep their provider and files without collisions',
    () {
      final manifest = jsonDecode(
        File('tool/vital_media/mapping.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      for (final item in manifest['mappings'] as List) {
        final id = item['exerciseId'] as String;
        expect(approved, isNot(contains(id)));
        final media = ExerciseMediaCatalog.entries.singleWhere(
          (e) => e.exerciseId == id,
        );
        expect(media.provider, 'vital_animations');
        expect(media.providerAssetId, item['providerAssetId']);
        expect(
          media.assetPath,
          'assets/vital_videos/${item['providerAssetId']}.mp4',
        );
      }
      expect(
        ExerciseMediaCatalog.entries.map((e) => e.exerciseId).toSet().length,
        ExerciseMediaCatalog.entries.length,
      );
    },
  );
}
