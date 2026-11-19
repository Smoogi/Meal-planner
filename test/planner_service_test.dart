import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_planner/data/db/database.dart';
import 'package:meal_planner/data/meal_repository.dart';
import 'package:meal_planner/data/planner_service.dart';
import 'package:meal_planner/data/planner_settings.dart';
import 'package:meal_planner/data/recipe_repository.dart';
import 'package:meal_planner/data/settings_repository.dart';
import 'package:meal_planner/domain/schedule.dart';

void main() {
  late AppDatabase db;
  late RecipeRepository recipes;
  late MealRepository meals;
  late PlannerService planner;
  final mon = DateTime(2026, 11, 16);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    recipes = RecipeRepository(db);
    meals = MealRepository(db, recipes);
    planner = PlannerService(db, recipes, meals);
    for (var i = 1; i <= 25; i++) {
      await recipes.save(RecipeDraft(
          name: 'Recipe $i',
          servings: 4,
          kcalOverride: 500.0 + i,
          slots: {MealSlot.marenda, MealSlot.lunch}));
    }
  });
  tearDown(() => db.close());

  test('generates entries from the shared tables with snapshots', () async {
    final res = await planner.generate(
        start: mon, end: addDays(mon, 6), settings: const PlannerSettings(multiDayChance: 0), seed: 1);
    final entries = await db.select(db.mealEntries).get();
    expect(entries.length, res.meals.length);
    // Mon,Wed,Fri WFH (2 each) + Tue,Thu office (1 each) + Sat,Sun free (2 each) = 12
    expect(entries.length, 12);
    expect(entries.every((e) => e.state == MealState.planned && e.kcal != null), isTrue);
  });

  test('regenerating keeps locked and consumed meals, replaces the rest', () async {
    await planner.generate(
        start: mon, end: addDays(mon, 6), settings: const PlannerSettings(multiDayChance: 0), seed: 1);
    final first = await db.select(db.mealEntries).get();
    final locked = first.first;
    final consumed = first[1];
    await meals.setLocked(locked.id, true);
    await meals.setState(consumed.id, MealState.consumed);

    await planner.generate(
        start: mon, end: addDays(mon, 6), settings: const PlannerSettings(multiDayChance: 0), seed: 2);
    final after = await db.select(db.mealEntries).get();
    expect(after.length, 12);
    final l = after.firstWhere((e) => e.id == locked.id);
    expect(l.recipeId, locked.recipeId);
    expect(l.locked, isTrue);
    final c = after.firstWhere((e) => e.id == consumed.id);
    expect(c.state, MealState.consumed);
    // at most one entry per (date, slot)
    expect(after.map((e) => '${e.date}${e.slot.index}').toSet().length, after.length);
  });

  test('multi-day cooking: one batch, leftovers linked, portions tracked', () async {
    await planner.generate(
        start: mon,
        end: addDays(mon, 13),
        settings: const PlannerSettings(multiDayChance: 1.0, multiDayMaxDays: 2),
        seed: 3);
    final entries = await db.select(db.mealEntries).get();
    final leftovers = entries.where((e) => e.isLeftover).toList();
    expect(leftovers, isNotEmpty);
    final batches = await db.select(db.prepBatches).get();
    for (final l in leftovers) {
      expect(l.batchId, isNotNull);
      expect(batches.any((b) => b.id == l.batchId), isTrue);
    }
    // Planned-only batches do not count as preparations.
    expect((await recipes.loadAll()).every((r) => r.prepCount == 0), isTrue);

    // Cooking and eating the first meal makes the batch real; leftovers stay leftovers.
    final cook = entries.firstWhere((e) => e.batchId == leftovers.first.batchId && !e.isLeftover);
    await meals.setState(cook.id, MealState.consumed);
    final item = (await recipes.loadAll()).firstWhere((r) => r.recipe.id == cook.recipeId);
    expect(item.prepCount, 1);
    expect(await meals.remainingPortions(cook.batchId!), 2); // 4 made - cook day - 1 leftover
  });

  test('regenerating removes planned batches that no longer have meals', () async {
    const s = PlannerSettings(multiDayChance: 1.0);
    await planner.generate(start: mon, end: addDays(mon, 6), settings: s, seed: 3);
    await planner.generate(
        start: mon, end: addDays(mon, 6), settings: const PlannerSettings(multiDayChance: 0), seed: 4);
    expect(await db.select(db.prepBatches).get(), isEmpty);
  });

  test('cooldown uses history of cooked recipes only', () async {
    // Recipe 1 was cooked and eaten yesterday.
    final id = await meals.addRecipeEntry(
        date: dateKey(addDays(mon, -1)), slot: MealSlot.lunch, recipeId: 1);
    await meals.setState(id, MealState.consumed);
    final res = await planner.generate(
        start: mon,
        end: addDays(mon, 6),
        settings: const PlannerSettings(multiDayChance: 0, cooldownDays: 14),
        seed: 5);
    expect((await recipes.loadAll()).first.lastPrepared, dateKey(addDays(mon, -1)));
    expect(res.notes, isEmpty);
    // Not cooked again within the cooldown...
    expect(res.meals.where((m) => m.recipeId == 1 && !m.isLeftover), isEmpty);
    // ...but the 3 portions still left from yesterday's batch are used as leftovers.
    expect(res.meals.where((m) => m.recipeId == 1 && m.isLeftover).length, 3);
  });

  test('planner settings round-trip through the settings table', () async {
    final repo = SettingsRepository(db);
    const s = PlannerSettings(
        cooldownDays: 30, favoriteWeight: 3.5, categoryTargets: {1: 2, 4: 3}, leftoversOnOfficeDays: true);
    await s.save(repo);
    final back = PlannerSettings.fromMap(await repo.watchAll().first);
    expect(back.cooldownDays, 30);
    expect(back.favoriteWeight, 3.5);
    expect(back.categoryTargets, {1: 2, 4: 3});
    expect(back.leftoversOnOfficeDays, isTrue);
  });
}
