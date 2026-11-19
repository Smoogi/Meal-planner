import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../data/meal_repository.dart';
import '../../data/settings_repository.dart';
import '../../domain/schedule.dart';
import '../calendar/day_style.dart';
import 'log_meal_sheet.dart';
import 'stats_screen.dart';

class CaloriesScreen extends ConsumerStatefulWidget {
  const CaloriesScreen({super.key});

  @override
  ConsumerState<CaloriesScreen> createState() => _CaloriesScreenState();
}

class _CaloriesScreenState extends ConsumerState<CaloriesScreen> {
  DateTime _date = () {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }();

  Future<void> _editTarget(double? current) async {
    final c = TextEditingController(text: current?.round().toString() ?? '');
    final repo = ref.read(settingsRepositoryProvider);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Daily calorie target'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'kcal (leave empty for none)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (r == null) return;
    await repo.set(SettingKeys.calorieTarget, double.tryParse(r) == null ? null : r);
  }

  @override
  Widget build(BuildContext context) {
    final key = dateKey(_date);
    final repo = ref.watch(mealRepositoryProvider);
    final entries = ref.watch(entriesProvider((key, key))).value ?? const <MealEntry>[];
    final settings = ref.watch(settingsProvider).value ?? const {};
    final target = double.tryParse(settings[SettingKeys.calorieTarget] ?? '');
    final text = Theme.of(context).textTheme;

    final consumed = entries.where((e) => e.state == MealState.consumed).toList();
    final pending = entries.where((e) => e.state == MealState.planned || e.state == MealState.prepared).toList();
    final skipped = entries.where((e) => e.state == MealState.skipped).toList();
    double sum(double? Function(MealEntry) f) => consumed.fold(0, (s, e) => s + (f(e) ?? 0));
    final kcal = sum((e) => e.kcal);
    final isToday = key == dateKey(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calories'),
        actions: [
          IconButton(
            tooltip: 'Statistics',
            icon: const Icon(Icons.bar_chart),
            onPressed: () => Navigator.of(context, rootNavigator: true)
                .push(MaterialPageRoute(builder: (_) => const StatsScreen())),
          ),
          IconButton(
            tooltip: 'Daily target',
            icon: const Icon(Icons.flag_outlined),
            onPressed: () => _editTarget(target),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Log meal'),
        onPressed: () => showLogMealSheet(context, key),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        children: [
          Row(children: [
            IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(() => _date = addDays(_date, -1))),
            Expanded(
              child: TextButton(
                onPressed: () async {
                  final d = await showDatePicker(
                      context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime(2100));
                  if (d != null) setState(() => _date = d);
                },
                child: Text(
                    '${isToday ? 'Today · ' : ''}${weekdayShort[_date.weekday - 1]} ${_date.day} ${monthNames[_date.month - 1]} ${_date.year}',
                    style: text.titleMedium),
              ),
            ),
            IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => setState(() => _date = addDays(_date, 1))),
          ]),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Recorded Calories', style: text.labelLarge),
                Text('${kcal.round()} kcal', style: text.displaySmall),
                if (target != null) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: (kcal / target).clamp(0, 1).toDouble()),
                  const SizedBox(height: 4),
                  Text('Target ${target.round()} kcal', style: text.bodySmall),
                ],
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  _macro(context, 'Protein', sum((e) => e.protein)),
                  _macro(context, 'Carbs', sum((e) => e.carbs)),
                  _macro(context, 'Fat', sum((e) => e.fat)),
                ]),
                const SizedBox(height: 12),
                for (final s in MealSlot.values)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(children: [
                      Expanded(child: Text(s.label)),
                      Text('${consumed.where((e) => e.slot == s).fold<double>(0, (a, e) => a + (e.kcal ?? 0)).round()} kcal'),
                    ]),
                  ),
                const SizedBox(height: 8),
                Text('Only logged meals are counted. This is not necessarily your full daily intake.',
                    style: text.bodySmall),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          if (consumed.isNotEmpty) Text('Consumed', style: text.titleMedium),
          for (final e in consumed) _EntryTile(entry: e, repo: repo),
          if (pending.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Planned (not counted yet)', style: text.titleMedium),
            for (final e in pending)
              _EntryTile(
                entry: e,
                repo: repo,
                actions: [
                  TextButton(
                      onPressed: () => repo.setState(e.id, MealState.consumed), child: const Text('Ate it')),
                  TextButton(
                      onPressed: () async {
                        await repo.setState(e.id, MealState.skipped);
                        if (context.mounted) await showLogMealSheet(context, key, slot: e.slot);
                      },
                      child: const Text('Ate something else')),
                  TextButton(
                      onPressed: () => repo.setState(e.id, MealState.skipped), child: const Text('Skip')),
                ],
              ),
          ],
          if (skipped.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Skipped', style: text.titleMedium),
            for (final e in skipped) _EntryTile(entry: e, repo: repo),
          ],
          if (entries.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 24), child: Center(child: Text('Nothing logged for this day.'))),
        ],
      ),
    );
  }

  Widget _macro(BuildContext context, String label, double grams) => Column(children: [
        Text('${grams.toStringAsFixed(0)} g', style: Theme.of(context).textTheme.titleMedium),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]);
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.repo, this.actions = const []});
  final MealEntry entry;
  final MealRepository repo;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    return Card(
      margin: const EdgeInsets.only(top: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(e.state.icon, size: 18, color: e.state.color(context)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.title ?? 'Meal', style: Theme.of(context).textTheme.titleSmall),
                Text(
                    '${e.slot.label} · ${e.kcal == null ? 'no calories' : '${e.kcal!.round()} kcal'}'
                    '${e.kind == EntryKind.recipe ? ' · ${e.servings == e.servings.roundToDouble() ? e.servings.toInt() : e.servings} serving(s)' : ''}'
                    '${e.isLeftover ? ' · leftover' : ''}',
                    style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
            IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => repo.deleteEntry(e.id),
            ),
          ]),
          if (actions.isNotEmpty) Wrap(children: actions),
        ]),
      ),
    );
  }
}

