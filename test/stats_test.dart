import 'package:flutter_test/flutter_test.dart';
import 'package:meal_planner/domain/stats.dart';

void main() {
  const meals = [
    ConsumedMeal(date: '2026-11-16', recipeId: 1, title: 'Bolognese', kcal: 700, protein: 35, carbs: 80, fat: 25),
    ConsumedMeal(date: '2026-11-16', title: 'Office chicken', kcal: 750),
    ConsumedMeal(date: '2026-11-17', recipeId: 1, title: 'Bolognese', kcal: 700, protein: 35, carbs: 80, fat: 25),
    ConsumedMeal(date: '2026-11-23', recipeId: 2, title: 'Soup', kcal: 300, protein: 10, carbs: 30, fat: 10),
    ConsumedMeal(date: '2026-12-02', recipeId: 2, title: 'Soup', kcal: 300),
  ];

  test('daily totals only contain days with meals', () {
    final d = dailyTotals(meals);
    expect(d.keys.length, 4);
    expect(d['2026-11-16']!.kcal, 1450);
    expect(d['2026-11-16']!.meals, 2);
  });

  test('average is over recorded days, not calendar days', () {
    final s = summarize(dailyTotals(meals));
    expect(s.daysWithData, 4);
    expect(s.avgKcalPerRecordedDay, closeTo((1450 + 700 + 300 + 300) / 4, 1e-9));
  });

  test('macro split uses 4/4/9 kcal per gram and sums to 1', () {
    final t = const Totals(protein: 25, carbs: 50, fat: 10);
    final m = t.macroSplit!;
    expect(m.protein + m.carbs + m.fat, closeTo(1, 1e-9));
    expect(m.protein, closeTo(100 / 390, 1e-9));
    expect(const Totals(kcal: 500).macroSplit, isNull);
  });

  test('weekly and monthly grouping', () {
    final d = dailyTotals(meals);
    final w = groupByWeek(d);
    expect(w['2026-11-16']!.kcal, 2150); // Mon 16 .. Sun 22
    expect(w['2026-11-23']!.kcal, 300);
    final m = groupByMonth(d);
    expect(m['2026-11']!.kcal, 2450);
    expect(m['2026-12']!.kcal, 300);
  });

  test('top recipes ignore meals without a recipe', () {
    final top = topRecipes(meals);
    expect(top.first.name, 'Bolognese');
    expect(top.first.times, 2);
    expect(top.length, 2);
  });
}
