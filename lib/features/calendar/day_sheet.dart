import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../domain/schedule.dart';
import 'day_style.dart';
import 'recipe_picker.dart';

Future<void> showDaySheet(BuildContext context, DateTime date) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => DayDetails(date: date),
    );

String _servingsLabel(double s) => s == s.roundToDouble() ? '${s.toInt()}' : s.toString();

class DayDetails extends ConsumerWidget {
  const DayDetails({super.key, required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = dateKey(date);
    final repo = ref.watch(mealRepositoryProvider);
    final weekly = ref.watch(weeklyScheduleProvider).value ?? const <int, DayType>{};
    final overrides = ref.watch(dayOverridesProvider).value ?? const <String, DayOverride>{};
    final entries = ref.watch(entriesProvider((key, key))).value ?? const <MealEntry>[];

    final override = overrides[key];
    final type = override?.dayType ?? weekly[date.weekday] ?? DayType.free;
    final slots = {...slotsFor(type), ...entries.map((e) => e.slot)}.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final consumed = entries.where((e) => e.state == MealState.consumed);
    final kcal = consumed.fold<double>(0, (s, e) => s + (e.kcal ?? 0));
    final allLocked = entries.isNotEmpty && entries.every((e) => e.locked);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Row(children: [
            Expanded(
              child: Text(
                  '${weekdayNames[date.weekday - 1]}, ${date.day} ${monthNames[date.month - 1]} ${date.year}',
                  style: Theme.of(context).textTheme.titleLarge),
            ),
            if (entries.isNotEmpty)
              IconButton(
                tooltip: allLocked ? 'Unlock day' : 'Lock day',
                icon: Icon(allLocked ? Icons.lock : Icons.lock_open),
                onPressed: () => repo.setDayLocked(key, !allLocked),
              ),
          ]),
          const SizedBox(height: 8),
          SegmentedButton<DayType>(
            showSelectedIcon: false,
            segments: [
              for (final t in DayType.values)
                ButtonSegment(value: t, label: Text(t.label), icon: Icon(t.icon, size: 16)),
            ],
            selected: {type},
            onSelectionChanged: (s) => repo.setDayTypeOverride(key, s.first),
          ),
          if (override?.dayType != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.restore, size: 16),
                label: Text('Reset to default (${(weekly[date.weekday] ?? DayType.free).label})'),
                onPressed: () => repo.setDayTypeOverride(key, null),
              ),
            ),
          const SizedBox(height: 8),
          _NoteField(key: ValueKey('note$key${override?.note}'), initial: override?.note, onSave: (v) => repo.setDayNote(key, v)),
          const SizedBox(height: 8),
          for (final slot in slots) ...[
            _SlotSection(
              date: key,
              slot: slot,
              entries: entries.where((e) => e.slot == slot).toList(),
              isOffice: type == DayType.office,
            ),
          ],
          const Divider(height: 24),
          Text('Recorded calories: ${kcal.round()} kcal',
              style: Theme.of(context).textTheme.titleMedium),
          Text(
              'Only consumed meals are counted. This may not be your full daily intake.',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _NoteField extends StatefulWidget {
  const _NoteField({super.key, this.initial, required this.onSave});
  final String? initial;
  final ValueChanged<String> onSave;

  @override
  State<_NoteField> createState() => _NoteFieldState();
}

class _NoteFieldState extends State<_NoteField> {
  late final _c = TextEditingController(text: widget.initial ?? '');

  @override
  Widget build(BuildContext context) => TextField(
        controller: _c,
        decoration: const InputDecoration(
            labelText: 'Note (optional)', border: OutlineInputBorder(), isDense: true),
        onSubmitted: widget.onSave,
        onTapOutside: (_) => widget.onSave(_c.text),
      );
}

class _SlotSection extends ConsumerWidget {
  const _SlotSection({required this.date, required this.slot, required this.entries, required this.isOffice});
  final String date;
  final MealSlot slot;
  final List<MealEntry> entries;
  final bool isOffice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(mealRepositoryProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(slot.label, style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        PopupMenuButton<String>(
          icon: const Icon(Icons.add_circle_outline),
          tooltip: 'Add meal',
          onSelected: (v) async {
            if (v == 'recipe') {
              final id = await pickRecipe(context, slot: slot);
              if (id != null) await repo.addRecipeEntry(date: date, slot: slot, recipeId: id);
            } else {
              final m = await askExternalMeal(context,
                  initialTitle: isOffice && slot == MealSlot.lunch ? 'Meal at work' : '');
              if (m != null) {
                await repo.addExternalEntry(
                  date: date,
                  slot: slot,
                  title: m.title,
                  kcal: m.kcal,
                  protein: m.protein,
                  carbs: m.carbs,
                  fat: m.fat,
                  state: MealState.planned,
                );
              }
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'recipe', child: Text('From recipe')),
            PopupMenuItem(value: 'external', child: Text('Without recipe (e.g. at work)')),
          ],
        ),
      ]),
      if (entries.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
              isOffice && slot == MealSlot.lunch ? 'Nothing planned (meal at work?)' : 'Nothing planned',
              style: Theme.of(context).textTheme.bodySmall),
        ),
      for (final e in entries) _EntryCard(entry: e),
      const SizedBox(height: 8),
    ]);
  }
}

class _EntryCard extends ConsumerWidget {
  const _EntryCard({required this.entry});
  final MealEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(mealRepositoryProvider);
    final e = entry;
    final macro = e.kcal == null
        ? 'no calories recorded'
        : '${e.kcal!.round()} kcal'
            '${e.protein != null ? ' · P ${e.protein!.round()}' : ''}'
            '${e.carbs != null ? ' C ${e.carbs!.round()}' : ''}'
            '${e.fat != null ? ' F ${e.fat!.round()}' : ''}';
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.title ?? 'Meal', style: Theme.of(context).textTheme.titleSmall),
              Text(
                  '${e.kind == EntryKind.recipe ? '${_servingsLabel(e.servings)} serving(s) · ' : ''}$macro'
                  '${e.isLeftover ? ' · leftover' : ''}',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              PopupMenuButton<MealState>(
                tooltip: 'Change state',
                onSelected: (s) => repo.setState(e.id, s),
                itemBuilder: (_) => [
                  for (final s in MealState.values)
                    PopupMenuItem(value: s, child: Text(s.label)),
                ],
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(e.state.icon, size: 16, color: e.state.color(context)),
                  label: Text(e.state.label),
                ),
              ),
            ]),
          ),
          IconButton(
            tooltip: e.locked ? 'Unlock' : 'Lock',
            icon: Icon(e.locked ? Icons.lock : Icons.lock_open, size: 20),
            onPressed: () => repo.setLocked(e.id, !e.locked),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'servings':
                  final c = TextEditingController(text: _servingsLabel(e.servings));
                  final r = await showDialog<double>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Servings'),
                      content: TextField(
                          controller: c,
                          autofocus: true,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                        FilledButton(
                            onPressed: () => Navigator.pop(
                                ctx, double.tryParse(c.text.replaceAll(',', '.'))),
                            child: const Text('OK')),
                      ],
                    ),
                  );
                  if (r != null) await repo.setServings(e.id, r);
                case 'swap':
                  final id = await pickRecipe(context, slot: e.slot);
                  if (id != null) await repo.replaceRecipe(e.id, id);
                case 'delete':
                  await repo.deleteEntry(e.id);
              }
            },
            itemBuilder: (_) => [
              if (e.kind == EntryKind.recipe)
                const PopupMenuItem(value: 'servings', child: Text('Change servings')),
              const PopupMenuItem(value: 'swap', child: Text('Replace with recipe')),
              const PopupMenuItem(value: 'delete', child: Text('Remove')),
            ],
          ),
        ]),
      ),
    );
  }
}
