import 'package:flutter/material.dart';

import 'app_colors.dart';

class SetkeepNavigation extends StatelessWidget {
  const SetkeepNavigation({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  static const labels = ['ホーム', '履歴', '部位', 'マイページ'];
  static const icons = [
    Icons.home_outlined,
    Icons.calendar_month_outlined,
    Icons.accessibility_new_outlined,
    Icons.person_outline_rounded,
  ];
  static const selectedIcons = [
    Icons.home_rounded,
    Icons.calendar_month_rounded,
    Icons.accessibility_new_rounded,
    Icons.person_rounded,
  ];

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: 72,
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: Semantics(
                  selected: i == selectedIndex,
                  button: true,
                  label: labels[i],
                  child: InkWell(
                    onTap: () => onSelected(i),
                    child: Center(
                      child: AnimatedContainer(
                        key: ValueKey('selectedTab$i'),
                        duration: const Duration(milliseconds: 150),
                        width: 71,
                        height: 57,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: i == selectedIndex
                              ? AppColors.primaryGreen
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ExcludeSemantics(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  i == selectedIndex
                                      ? selectedIcons[i]
                                      : icons[i],
                                  size: 24,
                                  color: AppColors.ink,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  labels[i],
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.ink,
                                    fontWeight: i == selectedIndex
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
