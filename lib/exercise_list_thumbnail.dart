import 'package:flutter/material.dart';

import 'design/family_theme.dart';
import 'exercise_media.dart';

/// One fixed-size image slot for an exercise row. Only explicit thumbnails are
/// shown; exercises without one use the existing SETKEEP mark.
class ExerciseListThumbnail extends StatelessWidget {
  const ExerciseListThumbnail({super.key, this.exerciseId, this.onTap});

  final String? exerciseId;
  final VoidCallback? onTap;

  static const double size = 56;

  @override
  Widget build(BuildContext context) {
    final prefix = FamilyPalette.of(context).assetPrefix;
    final path = ExerciseMediaCatalog.forExerciseId(exerciseId)
        ?.thumbnailAssetPath;
    return Semantics(
      label: onTap != null
          ? '種目のフォームガイドを開く'
          : path == null
          ? 'SETKEEPロゴの仮画像'
          : '種目画像',
      image: onTap == null,
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox.square(
          key: const Key('exerciseListThumbnail'),
          dimension: size,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: path == null
                  ? _placeholder(prefix)
                  : Image.asset(
                      '$prefix$path',
                      fit: BoxFit.contain,
                      errorBuilder: (_, error, stackTrace) =>
                          _placeholder(prefix),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(String prefix) => ClipRect(
    child: Transform.scale(
      scale: 1.3,
      child: Image.asset(
        '${prefix}assets/brand/setkeep_splash_mark.png',
        fit: BoxFit.contain,
        color: const Color(0xFFAFB5B4),
        colorBlendMode: BlendMode.srcIn,
      ),
    ),
  );
}
