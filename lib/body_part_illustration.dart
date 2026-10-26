import 'design/family_theme.dart';

import 'package:flutter/material.dart';

/// Display labels only; stored category keys remain unchanged.
String bodyPartCategoryLabel(String category) => switch (category) {
  '脚' => '下半身',
  '腹' => '腹筋',
  _ => category,
};

/// Consistent human renders for body-part and activity categories.
class BodyPartIllustration extends StatelessWidget {
  const BodyPartIllustration({super.key, required this.category});
  final String category;
  static const assets = {
    '胸': 'chest',
    '背中': 'back',
    '肩': 'shoulders',
    '腕': 'arms',
    '脚': 'legs',
    '腹': 'abs',
    '有酸素': 'cardio',
    'HYROX': 'hyrox',
  };
  @override
  Widget build(BuildContext context) {
    final label = bodyPartCategoryLabel(category);
    final asset = assets[category];
    return Semantics(
      label: '$labelの部位イラスト',
      image: true,
      child: ExcludeSemantics(
        child: SizedBox.expand(
          key: Key('bodyPartIllustration$category'),
          child: asset == null
              ? const Icon(
                  Icons.monitor_heart_outlined,
                  size: 46,
                  color: Color(0xFFD4162A),
                )
              : Image.asset(
                  '${FamilyPalette.of(context).assetPrefix}assets/category_muscles/$asset.png',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                ),
        ),
      ),
    );
  }
}

class BodyPartCategoryCard extends StatelessWidget {
  const BodyPartCategoryCard({
    super.key,
    required this.category,
    required this.label,
    required this.count,
    required this.onTap,
  });
  final String category;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 10),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    clipBehavior: Clip.antiAlias,
    child: Semantics(
      button: true,
      label: '$label、$count種目',
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        key: Key('exerciseCategory$category'),
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final imageWidth = (constraints.maxWidth * .34).clamp(84.0, 128.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: imageWidth,
                    height: 104,
                    child: BodyPartIllustration(category: category),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF101820),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '$count種目',
                            style: const TextStyle(
                              fontSize: 15,
                              color: Color(0xFF666D68),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF263238),
                    size: 24,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}
