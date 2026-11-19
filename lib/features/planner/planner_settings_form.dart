import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/planner_settings.dart';

/// Planner preferences. Used on the Planner tab (bottom sheet) and in Settings.
class PlannerSettingsForm extends ConsumerWidget {
  const PlannerSettingsForm({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(plannerSettingsProvider);
    final cats = ref.watch(categoriesProvider).value ?? const [];
    final repo = ref.watch(settingsRepositoryProvider);
    void update(PlannerSettings n) => n.save(repo);
    final text = Theme.of(context).textTheme;

    Widget slider(String title, String valueLabel, double value, double min, double max,
            int divisions, ValueChanged<double> onChanged, {String? help}) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: text.titleSmall)),
            Text(valueLabel, style: text.labelLarge),
          ]),
          Slider(value: value.clamp(min, max), min: min, max: max, divisions: divisions, onChanged: onChanged),
          if (help != null) Text(help, style: text.bodySmall),
          const SizedBox(height: 8),
        ]);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Variety', style: text.titleMedium),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        for (final d in const [7, 14, 30])
          ChoiceChip(
            label: Text('$d days'),
            selected: s.cooldownDays == d,
            onSelected: (_) => update(s.copyWith(cooldownDays: d)),
          ),
      ]),
      slider('Cooldown', '${s.cooldownDays} days', s.cooldownDays.toDouble(), 0, 60, 60,
          (v) => update(s.copyWith(cooldownDays: v.round())),
          help: 'Minimum days before the same recipe is cooked again.'),
      slider('Max consecutive days', '${s.maxConsecutiveDays}', s.maxConsecutiveDays.toDouble(), 1, 5, 4,
          (v) => update(s.copyWith(maxConsecutiveDays: v.round()))),
      const Divider(),
      Text('Weighting', style: text.titleMedium),
      const SizedBox(height: 8),
      slider('Favorite bonus', '×${s.favoriteWeight.toStringAsFixed(1)}', s.favoriteWeight, 1, 5, 8,
          (v) => update(s.copyWith(favoriteWeight: (v * 2).round() / 2))),
      slider('Discovery bonus', s.discoveryWeight.toStringAsFixed(1), s.discoveryWeight, 0, 4, 8,
          (v) => update(s.copyWith(discoveryWeight: (v * 2).round() / 2)),
          help: 'Extra weight for recipes not cooked for a long time (0 = off).'),
      const Divider(),
      Text('Multi-day cooking', style: text.titleMedium),
      const SizedBox(height: 8),
      slider('Chance to cook for several days', '${(s.multiDayChance * 100).round()}%',
          s.multiDayChance, 0, 1, 20, (v) => update(s.copyWith(multiDayChance: (v * 20).round() / 20))),
      slider('Days one cooking covers', '${s.multiDayMaxDays}', s.multiDayMaxDays.toDouble(), 2, 4, 2,
          (v) => update(s.copyWith(multiDayMaxDays: v.round()))),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Leftovers on Office days'),
        value: s.leftoversOnOfficeDays,
        onChanged: (v) => update(s.copyWith(leftoversOnOfficeDays: v)),
      ),
      const Divider(),
      Text('Meals per week by category', style: text.titleMedium),
      Text('Soft preferences: relaxed (and reported) if the recipes cannot satisfy them.',
          style: text.bodySmall),
      for (final c in cats)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(c.name),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: (s.categoryTargets[c.id] ?? 0) > 0
                  ? () => update(s.copyWith(categoryTargets: {
                        ...s.categoryTargets,
                        c.id: (s.categoryTargets[c.id] ?? 0) - 1
                      }))
                  : null,
            ),
            SizedBox(
                width: 24,
                child: Text('${s.categoryTargets[c.id] ?? 0}', textAlign: TextAlign.center)),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: (s.categoryTargets[c.id] ?? 0) < 14
                  ? () => update(s.copyWith(categoryTargets: {
                        ...s.categoryTargets,
                        c.id: (s.categoryTargets[c.id] ?? 0) + 1
                      }))
                  : null,
            ),
          ]),
        ),
    ]);
  }
}
