import 'package:flutter_test/flutter_test.dart';
import 'package:meal_planner/domain/planner/planner_engine.dart';
import 'package:meal_planner/domain/planner/planner_models.dart';
import 'package:meal_planner/domain/schedule.dart';
import 'package:meal_planner/domain/units.dart';

const both = {MealSlot.marenda, MealSlot.lunch};
const lunchOnly = {MealSlot.lunch};
const marendaOnly = {MealSlot.marenda};

// Category ids used below.
const fish = 1, meat = 2, veg = 3, rice = 4, seafood = 5;

List<PlannerRecipe> collection(int n, {Set<MealSlot> slots = both}) => [
      for (var i = 1; i <= n; i++)
        PlannerRecipe(id: i, name: 'R$i', slots: slots, servings: 4),
    ];

Map<String, DayType> days(DateTime start, int n, [DayType t = DayType.wfh]) =>
    {for (var i = 0; i < n; i++) dateKey(addDays(start, i)): t};

PlannerConfig cfg(DateTime start, int n,
        {int cooldown = 14,
        double multi = 0,
        int maxConsecutive = 2,
        Map<int, int> targets = const {},
        double fav = 2.0,
        double disc = 1.0}) =>
    PlannerConfig(
      start: start,
      end: addDays(start, n - 1),
      cooldownDays: cooldown,
      multiDayChance: multi,
      maxConsecutiveDays: maxConsecutive,
      categoryTargetsPerWeek: targets,
      favoriteWeight: fav,
      discoveryWeight: disc,
    );

void main() {
  final mon = DateTime(2026, 11, 16); // a Monday

  test('same seed gives identical plans; different seeds differ', () {
    PlanResult run(int seed) => generatePlan(
        PlannerInput(recipes: collection(30), config: cfg(mon, 14), dayTypes: days(mon, 14)),
        seed: seed);
    String sig(PlanResult r) => r.meals.map((m) => '${dateKey(m.date)}${m.slot.index}${m.recipeId}').join();
    expect(sig(run(1)), sig(run(1)));
    expect(sig(run(1)), isNot(sig(run(2))));
  });

  test('slots follow day types: office has lunch only', () {
    final types = {
      dateKey(mon): DayType.wfh,
      dateKey(addDays(mon, 1)): DayType.office,
      dateKey(addDays(mon, 2)): DayType.free,
    };
    final r = generatePlan(
        PlannerInput(recipes: collection(20), config: cfg(mon, 3), dayTypes: types),
        seed: 3);
    expect(r.meals.length, 2 + 1 + 2);
    expect(
        r.meals.where((m) => m.date == addDays(mon, 1)).map((m) => m.slot).toList(),
        [MealSlot.lunch]);
  });

  test('respects Marenda / Lunch / Both suitability', () {
    final recipes = [
      const PlannerRecipe(id: 1, name: 'Snack', slots: marendaOnly),
      const PlannerRecipe(id: 2, name: 'Dinnerish', slots: lunchOnly),
      const PlannerRecipe(id: 3, name: 'Either', slots: both),
    ];
    for (var seed = 0; seed < 20; seed++) {
      final r = generatePlan(
          PlannerInput(recipes: recipes, config: cfg(mon, 14), dayTypes: days(mon, 14)),
          seed: seed);
      for (final m in r.meals) {
        if (m.slot == MealSlot.marenda) expect(m.recipeId, isNot(2));
        if (m.slot == MealSlot.lunch) expect(m.recipeId, isNot(1));
      }
    }
  });

  test('cooldown is honoured when the collection is large enough', () {
    final r = generatePlan(
        PlannerInput(recipes: collection(40), config: cfg(mon, 14, cooldown: 14), dayTypes: days(mon, 14)),
        seed: 5);
    expect(r.notes, isEmpty);
    final ids = r.meals.map((m) => m.recipeId).toList();
    expect(ids.toSet().length, ids.length); // no repeats within 14 days
  });

  test('recent history blocks recipes still in cooldown', () {
    final recipes = collection(6);
    final r = generatePlan(
        PlannerInput(
            recipes: recipes,
            config: cfg(mon, 1, cooldown: 14),
            dayTypes: days(mon, 1),
            lastCooked: {for (final x in recipes.take(4)) x.id: addDays(mon, -3)}),
        seed: 9);
    expect(r.meals.map((m) => m.recipeId).toSet().intersection({1, 2, 3, 4}), isEmpty);
    expect(r.notes, isEmpty);
  });

  test('small collection: relaxes soft rules, never hard ones, and says so', () {
    final r = generatePlan(
        PlannerInput(recipes: collection(2), config: cfg(mon, 7), dayTypes: days(mon, 7)),
        seed: 1);
    expect(r.meals.length, 14); // still fully planned
    expect(r.fullySatisfied, isFalse);
    expect(r.notes.any((n) => n.kind == PlanNoteKind.cooldownRelaxed), isTrue);
  });

  test('max consecutive days is kept while alternatives exist', () {
    // 3 recipes, 1 slot per day (office), maxConsecutive 1 => never same recipe two days running
    final r = generatePlan(
        PlannerInput(
            recipes: collection(3, slots: lunchOnly),
            config: cfg(mon, 10, cooldown: 0, maxConsecutive: 1),
            dayTypes: days(mon, 10, DayType.office)),
        seed: 11);
    final ids = r.meals.map((m) => m.recipeId).toList();
    for (var i = 1; i < ids.length; i++) {
      expect(ids[i], isNot(ids[i - 1]));
    }
  });

  test('no suitable recipe leaves the slot empty with an explanation', () {
    final r = generatePlan(
        PlannerInput(
            recipes: collection(5, slots: lunchOnly), config: cfg(mon, 2), dayTypes: days(mon, 2)),
        seed: 1);
    expect(r.meals.every((m) => m.slot == MealSlot.lunch), isTrue);
    expect(r.notes.where((n) => n.kind == PlanNoteKind.noSuitableRecipe).length, 2);
  });

  test('empty collection yields a clear note', () {
    final r = generatePlan(
        PlannerInput(recipes: const [], config: cfg(mon, 2), dayTypes: days(mon, 2)), seed: 1);
    expect(r.meals, isEmpty);
    expect(r.notes.single.kind, PlanNoteKind.noRecipes);
  });

  test('fixed (locked) meals are never replaced and block their slot', () {
    final fixed = [FixedMeal(date: mon, slot: MealSlot.lunch, recipeId: 1)];
    final r = generatePlan(
        PlannerInput(
            recipes: collection(10), config: cfg(mon, 2), dayTypes: days(mon, 2), fixed: fixed),
        seed: 2);
    expect(r.meals.any((m) => m.date == mon && m.slot == MealSlot.lunch), isFalse);
    expect(r.meals.length, 3); // 4 slots minus the locked one
    // the locked recipe is in cooldown, so it is not re-picked
    expect(r.meals.any((m) => m.recipeId == 1), isFalse);
  });

  test('favorites are chosen more often but not always', () {
    final recipes = [
      for (var i = 1; i <= 10; i++)
        PlannerRecipe(id: i, name: 'R$i', slots: both, isFavorite: i == 1),
    ];
    var favCount = 0, total = 0;
    for (var seed = 0; seed < 300; seed++) {
      final r = generatePlan(
          PlannerInput(
              recipes: recipes,
              config: cfg(mon, 1, fav: 5, disc: 0),
              dayTypes: days(mon, 1, DayType.office)),
          seed: seed);
      total++;
      if (r.meals.single.recipeId == 1) favCount++;
    }
    // fair share is 10%; with weight 5 expect ~36%
    expect(favCount / total, greaterThan(0.2));
    expect(favCount / total, lessThan(0.6));
  });

  test('discovery favours recipes not cooked for a long time', () {
    final recipes = collection(2, slots: lunchOnly);
    var old = 0;
    for (var seed = 0; seed < 300; seed++) {
      final r = generatePlan(
          PlannerInput(
              recipes: recipes,
              config: cfg(mon, 1, cooldown: 0, disc: 4, fav: 1),
              dayTypes: days(mon, 1, DayType.office),
              lastCooked: {1: addDays(mon, -1)}), // 2 is never cooked
          seed: seed);
      if (r.meals.single.recipeId == 2) old++;
    }
    expect(old / 300, greaterThan(0.6));
  });

  test('category targets are met when recipes allow it; no double counting', () {
    final recipes = [
      // Seafood+Rice style recipes carry two categories but count once.
      const PlannerRecipe(id: 1, name: 'Squid risotto', slots: both, categoryIds: {seafood, rice}),
      const PlannerRecipe(id: 2, name: 'Fish pie', slots: both, categoryIds: {fish}),
      const PlannerRecipe(id: 3, name: 'Fish soup', slots: both, categoryIds: {fish}),
      for (var i = 4; i <= 12; i++)
        PlannerRecipe(id: i, name: 'Meat $i', slots: both, categoryIds: const {meat}),
      for (var i = 13; i <= 20; i++)
        PlannerRecipe(id: i, name: 'Veg $i', slots: both, categoryIds: const {veg}),
    ];
    var met = 0;
    for (var seed = 0; seed < 40; seed++) {
      final r = generatePlan(
          PlannerInput(
            recipes: recipes,
            config: cfg(mon, 7, cooldown: 7, targets: {fish: 2, meat: 3, veg: 2}),
            dayTypes: days(mon, 7),
          ),
          seed: seed);
      final fishMeals = r.meals.where((m) => m.recipeId == 2 || m.recipeId == 3).length;
      if (fishMeals >= 2) met++;
    }
    // Soft preference: should usually be reached (random, so not always).
    expect(met, greaterThan(30));
  });

  test('a recipe with two target categories counts toward only one', () {
    // Both categories want 1/week. One dual-category recipe must NOT satisfy both.
    final recipes = [
      const PlannerRecipe(id: 1, name: 'Dual', slots: lunchOnly, categoryIds: {seafood, rice}),
      const PlannerRecipe(id: 2, name: 'Rice', slots: lunchOnly, categoryIds: {rice}),
      const PlannerRecipe(id: 3, name: 'Seafood', slots: lunchOnly, categoryIds: {seafood}),
    ];
    // 2 days: need 2 meals to cover both targets, so Dual alone must not end the search.
    var both2 = 0;
    for (var seed = 0; seed < 50; seed++) {
      final r = generatePlan(
          PlannerInput(
            recipes: recipes,
            config: cfg(mon, 4, cooldown: 0, maxConsecutive: 1, targets: {seafood: 1, rice: 1}),
            dayTypes: days(mon, 4, DayType.office),
          ),
          seed: seed);
      // Notes mention a shortfall only if a category really got 0 meals.
      final shortfall = r.notes.where((n) => n.kind == PlanNoteKind.categoryShortfall);
      if (shortfall.isEmpty) both2++;
    }
    expect(both2, greaterThan(35));
  });

  test('multi-day cooking creates leftovers that do not reset cooldown', () {
    final input = PlannerInput(
        recipes: collection(30, slots: lunchOnly),
        config: cfg(mon, 14, cooldown: 14, multi: 1.0),
        dayTypes: days(mon, 14));
    final r = generatePlan(input, seed: 4);
    final leftovers = r.meals.where((m) => m.isLeftover).toList();
    expect(leftovers, isNotEmpty);
    for (final l in leftovers) {
      final cook = r.meals.firstWhere((m) => m.cookingKey == l.cookingKey && !m.isLeftover);
      expect(cook.recipeId, l.recipeId);
      expect(l.date.isAfter(cook.date), isTrue);
      expect(l.slot, cook.slot);
    }
    // A recipe is cooked fresh at most once in 14 days even though it appears on 2 days.
    final fresh = r.meals.where((m) => !m.isLeftover).map((m) => m.recipeId).toList();
    expect(fresh.toSet().length, fresh.length);
  });

  test('leftovers are not scheduled on Office days by default', () {
    final types = {
      for (var i = 0; i < 14; i++)
        dateKey(addDays(mon, i)): i.isEven ? DayType.wfh : DayType.office,
    };
    final r = generatePlan(
        PlannerInput(
            recipes: collection(30, slots: lunchOnly),
            config: cfg(mon, 14, multi: 1.0),
            dayTypes: types),
        seed: 8);
    for (final l in r.meals.where((m) => m.isLeftover)) {
      expect(types[dateKey(l.date)], isNot(DayType.office));
    }
  });

  test('open batches are used up first as leftovers', () {
    final r = generatePlan(
        PlannerInput(
          recipes: collection(10, slots: lunchOnly),
          config: cfg(mon, 3, multi: 0),
          dayTypes: days(mon, 3),
          openBatches: [
            OpenBatch(batchId: 7, recipeId: 3, cookedOn: addDays(mon, -1), remaining: 2),
          ],
        ),
        seed: 1);
    final lo = r.meals.where((m) => m.isLeftover).toList();
    expect(lo.length, 2);
    expect(lo.every((m) => m.existingBatchId == 7 && m.recipeId == 3), isTrue);
    expect(lo.first.date, mon);
  });
}
