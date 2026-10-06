import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Shared monthly grid for personal and friend workout history.
class WorkoutMonthCalendar extends StatelessWidget {
  const WorkoutMonthCalendar({
    super.key,
    required this.visibleMonth,
    required this.selectedDay,
    required this.recordedDates,
    required this.onSelectDay,
  });
  final DateTime visibleMonth;
  final DateTime? selectedDay;
  final Iterable<DateTime> recordedDates;
  final void Function(DateTime, bool) onSelectDay;
  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  @override
  Widget build(BuildContext context) {
    final leadingEmptyDays =
        DateTime(visibleMonth.year, visibleMonth.month).weekday - 1;
    final daysInMonth = DateTime(
      visibleMonth.year,
      visibleMonth.month + 1,
      0,
    ).day;
    return Card(
      key: const Key('monthlyCalendar'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                for (final day
                    in (Localizations.localeOf(context).languageCode == 'en'
                        ? ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                        : ['月', '火', '水', '木', '金', '土', '日']))
                  Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF777F78),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisExtent: 44,
              ),
              itemCount: leadingEmptyDays + daysInMonth,
              itemBuilder: (context, index) {
                if (index < leadingEmptyDays) return const SizedBox();
                final day = index - leadingEmptyDays + 1;
                final date = DateTime(
                  visibleMonth.year,
                  visibleMonth.month,
                  day,
                );
                final hasWorkout = recordedDates.any(
                  (day) => _sameDay(day, date),
                );
                final selected =
                    selectedDay != null && _sameDay(selectedDay!, date);
                return InkWell(
                  key: Key('calendarDay$day'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onSelectDay(date, selected),
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF101820)
                          : hasWorkout
                          ? const Color(0xFFC7F36B).withValues(alpha: 0.42)
                          : null,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '$day',
                              style: TextStyle(
                                fontWeight: hasWorkout
                                    ? FontWeight.w900
                                    : FontWeight.w500,
                                color: selected ? Colors.white : null,
                              ),
                            ),
                          ),
                        ),
                        if (hasWorkout)
                          Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.primaryGreen
                                  : const Color(0xFF101820),
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
