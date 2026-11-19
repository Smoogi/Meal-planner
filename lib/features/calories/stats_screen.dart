import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../domain/schedule.dart';
import '../../domain/stats.dart';

enum _Range { days, weeks, months }

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  _Range _range = _Range.days;

  ({DateTime from, DateTime to}) _window() {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    return switch (_range) {
      _Range.days => (from: addDays(today, -29), to: today),
      _Range.weeks => (from: addDays(today, -7 * 12 + 1), to: today),
      _Range.months => (from: DateTime(today.year, today.month - 11, 1), to: today),
    };
  }

  @override
  Widget build(BuildContext context) {
    final w = _window();
    final entries = ref.watch(entriesProvider((dateKey(w.from), dateKey(w.to)))).value ?? const <MealEntry>[];
    final firstDow = ref.watch(firstDayOfWeekProvider);
    final consumed = [
      for (final e in entries)
        if (e.state == MealState.consumed)
          ConsumedMeal(
              date: e.date,
              recipeId: e.recipeId,
              title: e.title,
              kcal: e.kcal,
              protein: e.protein,
              carbs: e.carbs,
              fat: e.fat,
              servings: e.servings),
    ];
    final daily = dailyTotals(consumed);
    final summary = summarize(daily);
    final text = Theme.of(context).textTheme;

    // Chart buckets
    final Map<String, Totals> buckets = switch (_range) {
      _Range.days => daily,
      _Range.weeks => groupByWeek(daily, weekStartsOn: firstDow),
      _Range.months => groupByMonth(daily),
    };
    final keys = <String>[];
    switch (_range) {
      case _Range.days:
        for (var d = w.from; !d.isAfter(w.to); d = addDays(d, 1)) {
          keys.add(dateKey(d));
        }
      case _Range.weeks:
        final start = addDays(w.to, -((w.to.weekday - firstDow + 7) % 7));
        for (var i = 11; i >= 0; i--) {
          keys.add(dateKey(addDays(start, -7 * i)));
        }
      case _Range.months:
        for (var i = 11; i >= 0; i--) {
          final m = DateTime(w.to.year, w.to.month - i, 1);
          keys.add('${m.year}-${m.month.toString().padLeft(2, '0')}');
        }
    }
    // For weeks/months show the average per recorded day so buckets are comparable.
    double valueFor(String k) {
      final t = buckets[k];
      if (t == null) return 0;
      if (_range == _Range.days) return t.kcal;
      final daysInBucket = daily.entries
          .where((e) => _range == _Range.weeks
              ? dateKey(addDays(parseDateKey(e.key), -((parseDateKey(e.key).weekday - firstDow + 7) % 7))) == k
              : e.key.startsWith(k))
          .where((e) => e.value.kcal > 0)
          .length;
      return daysInBucket == 0 ? 0 : t.kcal / daysInBucket;
    }

    final scheme = Theme.of(context).colorScheme;
    final split = summary.total.macroSplit;
    final top = topRecipes(consumed);

    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<_Range>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: _Range.days, label: Text('Daily')),
            ButtonSegment(value: _Range.weeks, label: Text('Weekly')),
            ButtonSegment(value: _Range.months, label: Text('Monthly')),
          ],
          selected: {_range},
          onSelectionChanged: (s) => setState(() => _range = s.first),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Average recorded calories', style: text.labelLarge),
              Text('${summary.avgKcalPerRecordedDay.round()} kcal / recorded day', style: text.headlineSmall),
              Text('${summary.daysWithData} day(s) with logged meals Â· ${summary.total.meals} meal(s)',
                  style: text.bodySmall),
              const SizedBox(height: 4),
              Text('Averages ignore days with nothing logged; recorded calories are not full daily intake.',
                  style: text.bodySmall),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Text(
            switch (_range) {
              _Range.days => 'Recorded kcal per day (last 30 days)',
              _Range.weeks => 'Average recorded kcal per logged day, by week',
              _Range.months => 'Average recorded kcal per logged day, by month',
            },
            style: text.titleSmall),
        const SizedBox(height: 8),
        SizedBox(
          height: 200,
          child: BarChart(BarChartData(
            gridData: const FlGridData(drawVerticalLine: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: _range == _Range.days ? 5 : 1,
                  getTitlesWidget: (v, meta) {
                    final i = v.toInt();
                    if (i < 0 || i >= keys.length) return const SizedBox.shrink();
                    final k = keys[i];
                    final label = k.substring(5);
                    return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(label, style: const TextStyle(fontSize: 10)));
                  },
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < keys.length; i++)
                BarChartGroupData(x: i, barRods: [
                  BarChartRodData(
                      toY: valueFor(keys[i]),
                      color: scheme.primary,
                      width: _range == _Range.days ? 5 : 14,
                      borderRadius: BorderRadius.circular(2)),
                ]),
            ],
          )),
        ),
        const SizedBox(height: 20),
        Text('Macronutrient distribution (share of recorded energy)', style: text.titleSmall),
        const SizedBox(height: 8),
        if (split == null)
          const Text('No macronutrient data recorded in this period.')
        else
          Row(children: [
            SizedBox(
              width: 140,
              height: 140,
              child: PieChart(PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 28,
                sections: [
                  PieChartSectionData(value: split.protein, color: scheme.primary, title: '', radius: 36),
                  PieChartSectionData(value: split.carbs, color: scheme.tertiary, title: '', radius: 36),
                  PieChartSectionData(value: split.fat, color: scheme.secondary, title: '', radius: 36),
                ],
              )),
            ),
            const SizedBox(width: 16),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _legend(scheme.primary, 'Protein', split.protein),
              _legend(scheme.tertiary, 'Carbs', split.carbs),
              _legend(scheme.secondary, 'Fat', split.fat),
            ]),
          ]),
        const SizedBox(height: 20),
        Text('Most frequently consumed recipes', style: text.titleSmall),
        if (top.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('No recipe meals recorded.')),
        for (final r in top)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(r.name),
            trailing: Text('${r.times}Ã—'),
          ),
      ]),
    );
  }

  Widget _legend(Color c, String label, double share) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text('$label ${(share * 100).round()}%'),
        ]),
      );
}

