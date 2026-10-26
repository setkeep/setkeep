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
    thumbnailAssetPath: 'assets/exercise_thumbnails/smith_bench_press_v1.png',
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
  'smith_squat': ExerciseMedia(
    exerciseId: 'smith_squat',
    provider: 'setkeep_original',
    providerAssetId: 'smith_squat_wrist_v2_white',
    mediaType: 'video',
    assetPath: 'assets/exercise_videos/smith_squat_wrist_v2_white.mp4',
    thumbnailAssetPath:
        'assets/exercise_thumbnails/smith_squat_wrist_v2_white.png',
  ),
  'decline_barbell_press': ExerciseMedia(
    exerciseId: 'decline_barbell_press',
    provider: 'setkeep_original',
    providerAssetId: 'decline_barbell_press_v1',
    mediaType: 'video',
    assetPath: 'assets/exercise_videos/decline_barbell_press_v1.mp4',
    thumbnailAssetPath:
        'assets/exercise_thumbnails/decline_barbell_press_v1.png',
  ),
  'split_squat': ExerciseMedia(
    exerciseId: 'split_squat',
    provider: 'setkeep_original',
    providerAssetId: 'split_squat_v1',
    mediaType: 'video',
    assetPath: 'assets/exercise_videos/split_squat_v1.mp4',
    thumbnailAssetPath: 'assets/exercise_thumbnails/split_squat_v1.png',
  ),
  'rear_raise': ExerciseMedia(
    exerciseId: 'rear_raise',
    provider: 'setkeep_original',
    providerAssetId: 'rear_raise_v1',
    mediaType: 'video',
    assetPath: 'assets/exercise_videos/rear_raise_v1.mp4',
    thumbnailAssetPath: 'assets/exercise_thumbnails/rear_raise_v1.png',
  ),
  'reverse_curl': ExerciseMedia(
    exerciseId: 'reverse_curl',
    provider: 'setkeep_original',
    providerAssetId: 'reverse_curl_coordination_v2',
    mediaType: 'video',
    assetPath: 'assets/exercise_videos/reverse_curl_coordination_v2.mp4',
    thumbnailAssetPath:
        'assets/exercise_thumbnails/reverse_curl_coordination_v2.png',
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
