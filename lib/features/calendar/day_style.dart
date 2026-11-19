import 'package:flutter/material.dart';

import '../../data/db/database.dart';

extension DayTypeStyle on DayType {
  String get label => switch (this) {
        DayType.wfh => 'WFH',
        DayType.office => 'Office',
        DayType.free => 'Free day',
      };

  String get short => switch (this) {
        DayType.wfh => 'W',
        DayType.office => 'O',
        DayType.free => 'F',
      };

  IconData get icon => switch (this) {
        DayType.wfh => Icons.home_work_outlined,
        DayType.office => Icons.business_outlined,
        DayType.free => Icons.beach_access_outlined,
      };

  Color color(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return switch (this) {
      DayType.wfh => dark ? const Color(0xFF64B5F6) : const Color(0xFF1976D2),
      DayType.office => dark ? const Color(0xFFFFB74D) : const Color(0xFFEF6C00),
      DayType.free => dark ? const Color(0xFF81C784) : const Color(0xFF2E7D32),
    };
  }
}

extension SlotStyle on MealSlot {
  String get label => this == MealSlot.marenda ? 'Marenda' : 'Lunch';
}

extension StateStyle on MealState {
  String get label => switch (this) {
        MealState.planned => 'Planned',
        MealState.prepared => 'Prepared',
        MealState.consumed => 'Consumed',
        MealState.skipped => 'Skipped',
      };

  IconData get icon => switch (this) {
        MealState.planned => Icons.schedule,
        MealState.prepared => Icons.soup_kitchen_outlined,
        MealState.consumed => Icons.check_circle,
        MealState.skipped => Icons.cancel_outlined,
      };

  Color color(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return switch (this) {
      MealState.planned => s.outline,
      MealState.prepared => s.tertiary,
      MealState.consumed => s.primary,
      MealState.skipped => s.error.withValues(alpha: 0.6),
    };
  }
}

const weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];
