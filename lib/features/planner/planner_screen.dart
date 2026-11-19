import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../data/meal_repository.dart';
import '../../domain/planner/planner_models.dart';
import '../../domain/schedule.dart';
import '../calendar/day_sheet.dart';
import '../calendar/day_style.dart';
import '../calendar/recipe_picker.dart';
import 'planner_settings_form.dart';

class PlannerScreen extends ConsumerStatefulWidget {
  const PlannerScreen({super.key});

  @override
  ConsumerState<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends ConsumerState<PlannerScreen> {
  late DateTime _start = _today();
  late DateTime _end = addDays(_today(), 6);
  PlanResult? _report;
  bool _busy = false;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: _start, end: _end),
    );
    if (r != null) {
      setState(() {
        _start = r.start;
        _end = r.end;
      });
    }
  }

  Future<void> _generate() async {
    setState(() => _busy = true);
    try {
      final res = await ref.read(plannerServiceProvider).generate(
            start: _start,
            end: _end,
            settings: ref.read(plannerSettingsProvider),
            weekStartsOn: ref.read(firstDayOfWeekProvider),
          );
      if (mounted) setState(() => _report = res);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = (dateKey(_start), dateKey(_end));
    final entries = ref.watch(entriesProvider(key)).value ?? const <MealEntry>[];
    final weekly = ref.watch(weeklyScheduleProvider).value ?? const <int, DayType>{};
    final overrides = ref.watch(dayOverridesProvider).value ?? const <String, DayOverride>{};
    final types = {
      for (final o in overrides.values)
        if (o.dayType != null) o.date: o.dayType!
    };
    final days = daysBetween(_start, _end) + 1;
    final unlockedPlanned =
        entries.where((e) => !e.locked && e.state == MealState.planned).length;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Planner'),
        actions: [
          IconButton(
            tooltip: 'Planner settings',
            icon: const Icon(Icons.tune),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              showDragHandle: true,
              builder: (_) => DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.85,
                maxChildSize: 0.95,
                builder: (_, c) => ListView(
                    controller: c,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: const [PlannerSettingsForm()]),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.date_range),
                  label: Text('${dateKey(_start)}  →  ${dateKey(_end)}  ($days days)'),
                  onPressed: _pickRange,
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: _busy
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.auto_awesome),
                      label: Text(unlockedPlanned > 0 ? 'Regenerate' : 'Generate plan'),
                      onPressed: _busy || days > 120 ? null : _generate,
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(
                    'Locked, prepared, consumed and skipped meals are kept. '
                    'Only unlocked planned meals are replaced.',
                    style: text.bodySmall),
              ]),
            ),
          ),
          if (_report != null) _ReportCard(result: _report!),
          const SizedBox(height: 8),
          if (days > 120)
            const Text('Pick a range of at most 120 days.')
          else
            for (var i = 0; i < days; i++)
              _DayRow(
                date: addDays(_start, i),
                type: effectiveDayType(addDays(_start, i), weekly, types),
                entries: entries.where((e) => e.date == dateKey(addDays(_start, i))).toList(),
              ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.result});
  final PlanResult result;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ok = result.fullySatisfied;
    return Card(
      color: ok ? scheme.primaryContainer : scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(ok ? Icons.check_circle_outline : Icons.info_outline),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  ok
                      ? 'Plan generated: ${result.meals.length} meals, all preferences satisfied.'
                      : 'Plan generated: ${result.meals.length} meals. '
                          '${result.notes.length} preference(s) could not be fully met:',
                  style: Theme.of(context).textTheme.titleSmall),
            ),
          ]),
          for (final n in result.notes.take(12))
            Padding(padding: const EdgeInsets.only(top: 4, left: 32), child: Text('• ${n.message}')),
          if (result.notes.length > 12)
            Padding(
                padding: const EdgeInsets.only(top: 4, left: 32),
                child: Text('…and ${result.notes.length - 12} more')),
        ]),
      ),
    );
  }
}

class _DayRow extends ConsumerWidget {
  const _DayRow({required this.date, required this.type, required this.entries});
  final DateTime date;
  final DayType type;
  final List<MealEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(mealRepositoryProvider);
    final text = Theme.of(context).textTheme;
    final slots = {...slotsFor(type), ...entries.map((e) => e.slot)}.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showDaySheet(context, date),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('${weekdayShort[date.weekday - 1]} ${date.day} ${monthNames[date.month - 1].substring(0, 3)}',
                  style: text.titleSmall),
              const SizedBox(width: 8),
              Icon(type.icon, size: 16, color: type.color(context)),
              const SizedBox(width: 4),
              Text(type.label, style: text.labelSmall),
            ]),
            for (final slot in slots)
              if (entries.any((x) => x.slot == slot))
                for (final e in entries.where((x) => x.slot == slot)) _line(context, repo, e, slot)
              else
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('${slot.label}: —', style: text.bodySmall),
                ),
          ]),
        ),
      ),
    );
  }

  Widget _line(BuildContext context, MealRepository repo, MealEntry e, MealSlot slot) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: [
        SizedBox(width: 64, child: Text(slot.label, style: text.labelMedium)),
        Expanded(
          child: Text(
              '${e.title ?? 'Meal'}${e.isLeftover ? '  (leftover)' : ''}',
              style: e.state == MealState.skipped
                  ? text.bodyMedium?.copyWith(decoration: TextDecoration.lineThrough)
                  : text.bodyMedium),
        ),
        Icon(e.state.icon, size: 16, color: e.state.color(context)),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: e.locked ? 'Unlock' : 'Lock',
          icon: Icon(e.locked ? Icons.lock : Icons.lock_open, size: 18),
          onPressed: () => repo.setLocked(e.id, !e.locked),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Replace',
          icon: const Icon(Icons.swap_horiz, size: 18),
          onPressed: () async {
            final id = await pickRecipe(context, slot: e.slot);
            if (id != null) await repo.replaceRecipe(e.id, id);
          },
        ),
      ]),
    );
  }
}
