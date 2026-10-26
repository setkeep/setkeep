import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/exercise_form_catalog.dart';
import 'package:setkeep/exercise_media.dart';

void main() {
  test('every existing public 3D form has a reviewed migration decision', () {
    final manifest = jsonDecode(
      File('tool/vital_media/mapping.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final mappings = (manifest['mappings'] as List)
        .cast<Map<String, dynamic>>();
    final review = (manifest['reviewRequired'] as List)
        .cast<Map<String, dynamic>>();
    final previous3d = ExerciseFormCatalog.entries
        .where((form) => form.available)
        .map((form) => form.exerciseId)
        .toSet();
    final migrated = mappings
        .map((entry) => entry['exerciseId'] as String)
        .toSet();
    final unmatched = review
        .map((entry) => entry['exerciseId'] as String)
        .toSet();
    expect(previous3d, hasLength(14));
    expect(previous3d.intersection(migrated), hasLength(10));
    expect(
      unmatched,
      containsAll({'dy_row', 'low_row', 'linear_row', 'high_row'}),
    );
    expect(
      previous3d,
      migrated
          .intersection(previous3d)
          .union(unmatched.intersection(previous3d)),
    );
    expect(mappings, hasLength(109));
    expect(
      mappings.map((entry) => entry['providerAssetId']).toSet(),
      hasLength(108),
    );
    expect(ExerciseFormCatalog.entries, hasLength(221));
    expect(migrated.intersection(unmatched), isEmpty);
    expect(migrated.union(unmatched).length, 200);
    expect(
      ExerciseMediaCatalog.forExerciseId('triceps_pushdown')?.exerciseId,
      'rope_pushdown',
    );
    final sharedRowing = mappings.where(
      (entry) => entry['providerAssetId'] == '0077',
    );
    expect(
      sharedRowing.map((entry) => entry['exerciseId']),
      containsAll({'rowing_machine', 'hyrox_rowing'}),
    );
    for (final entry in mappings) {
      final id = entry['exerciseId'] as String;
      final vitalId = entry['providerAssetId'] as String;
      expect(ExerciseFormCatalog.byId[id], isNotNull);
      final media = ExerciseMediaCatalog.forExerciseId(id)!;
      expect(media.providerAssetId, vitalId);
      expect(media.assetPath, 'assets/vital_videos/$vitalId.mp4');
      expect(media.thumbnailAssetPath, 'assets/vital_thumbnails/$vitalId.png');
    }
    for (final id in unmatched) {
      // An unmatched Vital exercise can have an explicitly authored guide.
      // Keep every other unmatched ID unavailable.
      if (const {
        'smith_incline_press',
        'smith_bench_press',
        'decline_barbell_press',
        'split_squat',
        'rear_raise',
        'reverse_curl',
        'pallof_press',
        'bayesian_curl',
        'wall_sit',
        'chest_supported_dumbbell_row',
        'reverse_lunge',
        'decline_dumbbell_fly',
      }.contains(id)) {
        expect(
          ExerciseMediaCatalog.forExerciseId(id)?.provider,
          'setkeep_original',
        );
      } else {
        expect(ExerciseMediaCatalog.forExerciseId(id), isNull);
      }
    }
    for (final id in ['dy_row', 'low_row', 'linear_row', 'high_row']) {
      final decision = review.singleWhere((entry) => entry['exerciseId'] == id);
      expect(decision['candidateVitalIds'], contains('0157'));
      expect(ExerciseMediaCatalog.forExerciseId(id), isNull);
    }
  });
}
