import 'schedule.dart';

/// Minimal view of a consumed meal for statistics (decoupled from the DB).
class ConsumedMeal {
  const ConsumedMeal({
    required this.date,
    this.recipeId,
    this.title,
    this.kcal,
    this.protein,
    this.carbs,
    this.fat,
    this.servings = 1,
  });
  final String date; // yyyy-MM-dd
  final int? recipeId;
  final String? title;
  final double? kcal, protein, carbs, fat;
  final double servings;
}

class Totals {
  const Totals({this.kcal = 0, this.protein = 0, this.carbs = 0, this.fat = 0, this.meals = 0});
  final double kcal, protein, carbs, fat;
  final int meals;

  Totals operator +(Totals o) => Totals(
      kcal: kcal + o.kcal,
      protein: protein + o.protein,
      carbs: carbs + o.carbs,
      fat: fat + o.fat,
      meals: meals + o.meals);

  /// Share of energy from each macro (4/4/9 kcal per gram), summing to 1.
  /// Null when no macro data was recorded.
  ({double protein, double carbs, double fat})? get macroSplit {
    final p = protein * 4, c = carbs * 4, f = fat * 9;
    final sum = p + c + f;
    if (sum <= 0) return null;
    return (protein: p / sum, carbs: c / sum, fat: f / sum);
  }
}

Totals _of(ConsumedMeal m) => Totals(
    kcal: m.kcal ?? 0, protein: m.protein ?? 0, carbs: m.carbs ?? 0, fat: m.fat ?? 0, meals: 1);

/// Totals per date (only dates that have at least one consumed meal appear).
Map<String, Totals> dailyTotals(Iterable<ConsumedMeal> meals) {
  final out = <String, Totals>{};
  for (final m in meals) {
    out[m.date] = (out[m.date] ?? const Totals()) + _of(m);
  }
  return out;
}

class PeriodSummary {
  const PeriodSummary({required this.total, required this.daysWithData, required this.avgKcalPerRecordedDay});
  final Totals total;
  final int daysWithData;

  /// Average over days that have recorded meals, NOT over calendar days:
  /// recorded calories are partial (mostly Marenda + Lunch).
  final double avgKcalPerRecordedDay;
}

PeriodSummary summarize(Map<String, Totals> daily) {
  var t = const Totals();
  var days = 0;
  for (final d in daily.values) {
    if (d.kcal > 0) days++;
    t = t + d;
  }
  return PeriodSummary(
      total: t, daysWithData: days, avgKcalPerRecordedDay: days == 0 ? 0 : t.kcal / days);
}

/// Groups daily totals by week (week start in [weekStartsOn]) or month.
Map<String, Totals> groupByWeek(Map<String, Totals> daily, {int weekStartsOn = DateTime.monday}) {
  final out = <String, Totals>{};
  for (final e in daily.entries) {
    final d = parseDateKey(e.key);
    final start = addDays(d, -((d.weekday - weekStartsOn + 7) % 7));
    out[dateKey(start)] = (out[dateKey(start)] ?? const Totals()) + e.value;
  }
  return out;
}

Map<String, Totals> groupByMonth(Map<String, Totals> daily) {
  final out = <String, Totals>{};
  for (final e in daily.entries) {
    final k = e.key.substring(0, 7);
    out[k] = (out[k] ?? const Totals()) + e.value;
  }
  return out;
}

class RecipeCount {
  const RecipeCount(this.name, this.times, this.servings);
  final String name;
  final int times;
  final double servings;
}

/// Most frequently consumed recipes (recipe meals only; leftovers included).
List<RecipeCount> topRecipes(Iterable<ConsumedMeal> meals, {int limit = 10}) {
  final counts = <Object, ({String name, int times, double servings})>{};
  for (final m in meals) {
    if (m.recipeId == null) continue;
    final cur = counts[m.recipeId!];
    counts[m.recipeId!] = (
      name: m.title ?? 'Recipe ${m.recipeId}',
      times: (cur?.times ?? 0) + 1,
      servings: (cur?.servings ?? 0) + m.servings,
    );
  }
  final list = [for (final v in counts.values) RecipeCount(v.name, v.times, v.servings)]
    ..sort((a, b) {
      final c = b.times.compareTo(a.times);
      return c != 0 ? c : a.name.compareTo(b.name);
    });
  return list.take(limit).toList();
}
