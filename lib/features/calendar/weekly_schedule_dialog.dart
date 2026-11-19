import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import 'day_style.dart';

/// Edits the default weekly schedule (individual dates can still override it).
Future<void> showWeeklyScheduleDialog(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const _WeeklyDialog(),
    );

class _WeeklyDialog extends ConsumerWidget {
  const _WeeklyDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekly = ref.watch(weeklyScheduleProvider).value ?? const <int, DayType>{};
    final repo = ref.watch(mealRepositoryProvider);
    return AlertDialog(
      title: const Text('Default weekly schedule'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var wd = 1; wd <= 7; wd++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                SizedBox(width: 92, child: Text(weekdayNames[wd - 1])),
                Expanded(
                  child: SegmentedButton<DayType>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: [
                      for (final t in DayType.values)
                        ButtonSegment(value: t, label: Text(t.short)),
                    ],
                    selected: {weekly[wd] ?? DayType.free},
                    onSelectionChanged: (s) => repo.setWeekly(wd, s.first),
                  ),
                ),
              ]),
            ),
          const SizedBox(height: 8),
          const Text('W = WFH, O = Office, F = Free day. Changing a single date in the '
              'calendar never changes this default.',
              style: TextStyle(fontSize: 12)),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
    );
  }
}
