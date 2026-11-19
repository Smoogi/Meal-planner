import 'package:drift/drift.dart';

import '../domain/planner/planner_engine.dart';
import '../domain/planner/planner_models.dart';
import '../domain/schedule.dart';
import 'db/database.dart';
import 'meal_repository.dart';
import 'planner_settings.dart';
import 'recipe_repository.dart';

/// Connects the pure planner engine to the shared meal records: reads
/// context, runs the engine and replaces only unlocked, still-planned meals.
class PlannerService {
  PlannerService(this.db, this.recipes, this.meals);
  final AppDatabase db;
  final RecipeRepository recipes;
  final MealRepository meals;

  static bool _isReplaceable(MealEntry e) => !e.locked && e.state == MealState.planned;

  Future<PlanResult> generate({
    required DateTime start,
    required DateTime end,
    required PlannerSettings settings,
    int weekStartsOn = DateTime.monday,
    int? seed,
  }) async {
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    final items = await recipes.loadAll();
    final categories = await db.select(db.categories).get();
    final weekly = await meals.getWeekly();
    final overrides = await meals.getOverrideTypes();

    final dayTypes = <String, DayType>{
      for (var d = s; !d.isAfter(e); d = addDays(d, 1))
        dateKey(d): effectiveDayType(d, weekly, overrides),
    };

    // Context: a week before the range through its end.
    final ctxFrom = dateKey(addDays(s, -7));
    final all = await meals.entriesBetween(ctxFrom, dateKey(e));
    final removable = <int>{
      for (final x in all)
        if (x.date.compareTo(dateKey(s)) >= 0 && _isReplaceable(x)) x.id
    };
    final fixed = [
      for (final x in all)
        if (!removable.contains(x.id))
          FixedMeal(
              date: parseDateKey(x.date),
              slot: x.slot,
              recipeId: x.recipeId,
              isLeftover: x.isLeftover),
    ];

    final lastCooked = <int, DateTime>{
      for (final it in items)
        if (it.lastPrepared != null) it.recipe.id: parseDateKey(it.lastPrepared!),
    };

    final open = await _openBatches(s, settings, excludeEntryIds: removable);

    final input = PlannerInput(
      recipes: [
        for (final it in items)
          PlannerRecipe(
            id: it.recipe.id,
            name: it.recipe.name,
            slots: it.slots,
            categoryIds: it.categoryIds,
            isFavorite: it.recipe.isFavorite,
            servings: it.recipe.servings,
          ),
      ],
      config: settings.toConfig(s, e, weekStartsOn: weekStartsOn),
      dayTypes: dayTypes,
      fixed: fixed,
      lastCooked: lastCooked,
      openBatches: open,
      categoryNames: {for (final c in categories) c.id: c.name},
    );

    final result = generatePlan(input, seed: seed ?? DateTime.now().microsecondsSinceEpoch & 0x7fffffff);

    final itemById = {for (final it in items) it.recipe.id: it};
    await db.transaction(() async {
      final touchedBatches = <int>{};
      if (removable.isNotEmpty) {
        final rows = await (db.select(db.mealEntries)..where((t) => t.id.isIn(removable))).get();
        touchedBatches.addAll(rows.map((r) => r.batchId).whereType<int>());
        await (db.delete(db.mealEntries)..where((t) => t.id.isIn(removable))).go();
      }
      // Drop batches that only existed for deleted planned meals.
      for (final b in touchedBatches) {
        final left = await (db.select(db.mealEntries)..where((t) => t.batchId.equals(b))).get();
        if (left.isEmpty) await (db.delete(db.prepBatches)..where((t) => t.id.equals(b))).go();
      }

      final batchByKey = <int, int>{};
      for (final m in result.meals) {
        final it = itemById[m.recipeId];
        if (it == null) continue;
        int? batchId = m.existingBatchId;
        if (m.cookingKey != null) {
          batchId = batchByKey[m.cookingKey!];
          if (batchId == null && !m.isLeftover) {
            batchId = await db.into(db.prepBatches).insert(PrepBatchesCompanion.insert(
                recipeId: Value(it.recipe.id),
                cookedOn: dateKey(m.date),
                portionsMade: it.recipe.servings));
            batchByKey[m.cookingKey!] = batchId;
          }
        }
        final n = it.perServing;
        await db.into(db.mealEntries).insert(MealEntriesCompanion.insert(
              date: dateKey(m.date),
              slot: m.slot,
              state: MealState.planned,
              kind: EntryKind.recipe,
              recipeId: Value(it.recipe.id),
              batchId: Value(batchId),
              isLeftover: Value(m.isLeftover),
              title: Value(it.recipe.name),
              kcal: Value(n?.kcal),
              protein: Value(n?.protein),
              carbs: Value(n?.carbs),
              fat: Value(n?.fat),
            ));
      }
    });
    return result;
  }

  Future<List<OpenBatch>> _openBatches(DateTime start, PlannerSettings s,
      {required Set<int> excludeEntryIds}) async {
    final from = dateKey(addDays(start, -3));
    final batches = await (db.select(db.prepBatches)
          ..where((b) => b.cookedOn.isBiggerOrEqualValue(from) & b.cookedOn.isSmallerOrEqualValue(dateKey(start))))
        .get();
    final out = <OpenBatch>[];
    for (final b in batches) {
      if (b.recipeId == null) continue;
      final linked = await (db.select(db.mealEntries)..where((e) => e.batchId.equals(b.id))).get();
      // Only batches that were really cooked.
      final cooked = linked.any((e) => e.state == MealState.prepared || e.state == MealState.consumed);
      if (!cooked) continue;
      final used = linked
          .where((e) => !excludeEntryIds.contains(e.id) && e.state != MealState.skipped)
          .fold<double>(0, (sum, e) => sum + e.servings);
      final remaining = (b.portionsMade - used).floor();
      if (remaining >= 1) {
        out.add(OpenBatch(
            batchId: b.id,
            recipeId: b.recipeId!,
            cookedOn: parseDateKey(b.cookedOn),
            remaining: remaining));
      }
    }
    return out;
  }
}
