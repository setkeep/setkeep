import 'package:flutter/services.dart';

import 'exercise_form_catalog.dart';

part 'vital_media_catalog.g.dart';

// Original guides occupy only identities without a purchased mapping.
const Map<String, ExerciseMedia> _setkeepOriginalMedia = {
  'pallof_press': ExerciseMedia(
    exerciseId: 'pallof_press',
    provider: 'setkeep_original',
    providerAssetId: 'pallof_press_white_v4',
    mediaType: 'video',
    assetPath: 'assets/exercise_videos/pallof_press_white_v4.mp4',
    thumbnailAssetPath: 'assets/exercise_thumbnails/pallof_press_white_v4.png',
  ),
  'bayesian_curl': ExerciseMedia(
    exerciseId: 'bayesian_curl',
    provider: 'setkeep_original',
    providerAssetId: 'bayesian_curl_white_v3',
    mediaType: 'video',
    assetPath: 'assets/exercise_videos/bayesian_curl_white_v3.mp4',
    thumbnailAssetPath: 'assets/exercise_thumbnails/bayesian_curl_white_v3.png',
  ),
  'wall_sit': ExerciseMedia(
    exerciseId: 'wall_sit',
    provider: 'setkeep_original',
    providerAssetId: 'wall_sit_white_v2',
    mediaType: 'video',
    assetPath: 'assets/exercise_videos/wall_sit_white_v2.mp4',
    thumbnailAssetPath: 'assets/exercise_thumbnails/wall_sit_white_v2.png',
  ),
  'chest_supported_dumbbell_row': ExerciseMedia(
    exerciseId: 'chest_supported_dumbbell_row',
    provider: 'setkeep_original',
    providerAssetId: 'chest_supported_dumbbell_row_white_v5',
    mediaType: 'video',
    assetPath:
        'assets/exercise_videos/chest_supported_dumbbell_row_white_v5.mp4',
    thumbnailAssetPath:
        'assets/exercise_thumbnails/chest_supported_dumbbell_row_white_v5.png',
  ),
  'reverse_lunge': ExerciseMedia(
    exerciseId: 'reverse_lunge',
    provider: 'setkeep_original',
    providerAssetId: 'reverse_lunge_white_v4',
    mediaType: 'video',
    assetPath: 'assets/exercise_videos/reverse_lunge_white_v4.mp4',
    thumbnailAssetPath: 'assets/exercise_thumbnails/reverse_lunge_white_v4.png',
  ),
  'decline_dumbbell_fly': ExerciseMedia(
    exerciseId: 'decline_dumbbell_fly',
    provider: 'setkeep_original',
    providerAssetId: 'decline_dumbbell_fly_white_v5',
    mediaType: 'video',
    assetPath: 'assets/exercise_videos/decline_dumbbell_fly_white_v5.mp4',
    thumbnailAssetPath:
        'assets/exercise_thumbnails/decline_dumbbell_fly_white_v5.png',
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
  static List<ExerciseMedia> get entries => List.unmodifiable([
    ..._vitalMedia.values,
    ..._setkeepOriginalMedia.values,
  ]);

  static ExerciseMedia? forExerciseId(String? exerciseId) {
    if (exerciseId == null) return null;
    // Purchased mappings take precedence if a future catalog adds a collision.
    final canonical = ExerciseFormCatalog.canonicalId(exerciseId);
    final media = _vitalMedia[canonical] ?? _setkeepOriginalMedia[canonical];
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
