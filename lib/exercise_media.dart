import 'package:flutter/services.dart';

import 'exercise_form_catalog.dart';

part 'vital_media_catalog.g.dart';

// SETKEEP-authored guides stay separate from the purchased Vital manifest.
const Map<String, ExerciseMedia> _setkeepMedia = {
  'smith_bench_press': ExerciseMedia(
    exerciseId: 'smith_bench_press',
    provider: 'setkeep_original',
    providerAssetId: 'smith_bench_press_v1',
    mediaType: 'video',
    assetPath: 'assets/exercise_videos/smith_bench_press_v1.mp4',
    thumbnailAssetPath:
        'assets/exercise_thumbnails/smith_bench_press_v1.png',
  ),
  'smith_incline_press': ExerciseMedia(
    exerciseId: 'smith_incline_press',
    provider: 'setkeep_original',
    providerAssetId: 'smith_incline_press_v11',
    mediaType: 'video',
    assetPath: 'assets/exercise_videos/smith_incline_press_v11.mp4',
    thumbnailAssetPath:
        'assets/exercise_thumbnails/smith_incline_press_v11.png',
  ),
};

/// Optional media is keyed by SETKEEP's stable exercise ID, never the provider ID.
class ExerciseMedia {
  const ExerciseMedia({
    required this.exerciseId,
    required this.provider,
    required this.providerAssetId,
    required this.mediaType,
    required this.assetPath,
    this.thumbnailAssetPath,
    this.videoUrl,
    this.isActive = true,
  });

  final String exerciseId;
  final String provider;
  final String providerAssetId;
  final String mediaType;
  final String assetPath;
  final String? thumbnailAssetPath;
  final Uri? videoUrl;
  final bool isActive;
}

class ExerciseMediaCatalog {
  static List<ExerciseMedia> get entries =>
      List.unmodifiable({..._vitalMedia, ..._setkeepMedia}.values);

  static ExerciseMedia? forExerciseId(String? exerciseId) {
    if (exerciseId == null) return null;
    final canonicalId = ExerciseFormCatalog.canonicalId(exerciseId);
    final media = _setkeepMedia[canonicalId] ?? _vitalMedia[canonicalId];
    return media?.isActive == true ? media : null;
  }

  static Future<bool> isAvailable(
    ExerciseMedia media, {
    AssetBundle? bundle,
  }) async {
    if (media.videoUrl != null) return true;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(
        bundle ?? rootBundle,
      );
      return manifest.listAssets().contains(media.assetPath);
    } catch (_) {
      return false;
    }
  }
}
