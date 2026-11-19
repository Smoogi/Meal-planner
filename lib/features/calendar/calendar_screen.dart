import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../data/settings_repository.dart';
import '../../domain/schedule.dart';
import 'day_sheet.dart';
import 'day_style.dart';
import 'weekly_schedule_dialog.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value ?? const {};
    final firstDow = int.tryParse(settings[SettingKeys.firstDayOfWeek] ?? '') ?? 1;
    final showKcal = settingFlag(settings, SettingKeys.calendarShowKcal);
    final weekly = ref.watch(weeklyScheduleProvider).value ?? const <int, DayType>{};
    final overrides = ref.watch(dayOverridesProvider).value ?? const <String, DayOverride>{};
    final overrideTypes = {
      for (final o in overrides.values)
        if (o.dayType != null) o.date: o.dayType!
    };

    // Visible grid: from the week containing the 1st to the week containing the last day.
    final first = DateTime(_month.year, _month.month, 1);
    final last = DateTime(_month.year, _month.month + 1, 0);
    final lead = (first.weekday - firstDow + 7) % 7;
    final gridStart = addDays(first, -lead);
    final trail = (firstDow + 6 - last.weekday + 7) % 7;
    final gridEnd = addDays(last, trail);
    final totalDays = daysBetween(gridStart, gridEnd) + 1;

    final entries = ref
            .watch(entriesProvider((dateKey(gridStart), dateKey(gridEnd))))
            .value ??
        const <MealEntry>[];
    final byDate = <String, List<MealEntry>>{};
    for (final e in entries) {
      (byDate[e.date] ??= []).add(e);
    }

    final today = DateTime.now();
    final dow = [for (var i = 0; i < 7; i++) weekdayShort[(firstDow - 1 + i) % 7]];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          IconButton(
            tooltip: 'Weekly schedule',
            icon: const Icon(Icons.view_week_outlined),
            onPressed: () => showWeeklyScheduleDialog(context),
          ),
          IconButton(
            tooltip: 'Today',
            icon: const Icon(Icons.today),
            onPressed: () => setState(() => _month = DateTime(today.year, today.month)),
          ),
        ],
      ),
      body: Column(children: [
        Row(children: [
          IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1))),
          Expanded(
            child: Text('${monthNames[_month.month - 1]} ${_month.year}',
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
          ),
          IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1))),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            for (final d in dow)
              Expanded(
                  child: Center(
                      child: Text(d, style: Theme.of(context).textTheme.labelMedium))),
          ]),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: LayoutBuilder(builder: (context, c) {
              final rows = totalDays ~/ 7;
              final cellH = c.maxHeight / rows;
              final cellW = c.maxWidth / 7;
              return GridView.count(
                crossAxisCount: 7,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: cellW / cellH,
                children: [
                  for (var i = 0; i < totalDays; i++)
                    _DayCell(
                      date: addDays(gridStart, i),
                      inMonth: addDays(gridStart, i).month == _month.month,
                      isToday: dateKey(addDays(gridStart, i)) == dateKey(today),
                      type: effectiveDayType(addDays(gridStart, i), weekly, overrideTypes),
                      isOverride: overrideTypes.containsKey(dateKey(addDays(gridStart, i))),
                      showKcal: showKcal,
                      entries: byDate[dateKey(addDays(gridStart, i))] ?? const [],
                    ),
                ],
              );
            }),
          ),
        ),
        const _Legend(),
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Wrap(spacing: 14, runSpacing: 4, children: [
          for (final t in DayType.values)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(t.icon, size: 14, color: t.color(context)),
              const SizedBox(width: 4),
              Text(t.label, style: Theme.of(context).textTheme.labelSmall),
            ]),
          Text('● planned  ● consumed  kcal = recorded',
              style: Theme.of(context).textTheme.labelSmall),
        ]),
      );
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.inMonth,
    required this.isToday,
    required this.type,
    required this.isOverride,
    required this.entries,
    this.showKcal = true,
  });
  final DateTime date;
  final bool showKcal;
  final bool inMonth, isToday, isOverride;
  final DayType type;
  final List<MealEntry> entries;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = type.color(context);
    final consumedKcal = entries
        .where((e) => e.state == MealState.consumed)
        .fold<double>(0, (s, e) => s + (e.kcal ?? 0));
    final fade = inMonth ? 1.0 : 0.4;

    return Padding(
      padding: const EdgeInsets.all(1.5),
      child: Material(
        color: color.withValues(alpha: 0.10 * fade),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: isToday
              ? BorderSide(color: scheme.primary, width: 2)
              : isOverride
                  ? BorderSide(color: color.withValues(alpha: 0.7))
                  : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => showDaySheet(context, date),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Opacity(
              opacity: fade,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('${date.day}',
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(fontWeight: isToday ? FontWeight.bold : null)),
                  const Spacer(),
                  Icon(type.icon, size: 12, color: color),
                ]),
                const Spacer(),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  for (final e in entries.take(3))
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(right: 2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: e.state == MealState.planned ? null : e.state.color(context),
                        border: e.state == MealState.planned
                            ? Border.all(color: scheme.outline, width: 1.2)
                            : null,
                      ),
                    ),
                ]),
                if (showKcal && consumedKcal > 0)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('${consumedKcal.round()}',
                        style: Theme.of(context).textTheme.labelSmall),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

