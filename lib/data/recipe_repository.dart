import 'package:drift/drift.dart';

import '../domain/nutrition.dart';
import 'db/database.dart';

IngredientFacts factsOf(Ingredient i) => IngredientFacts(
      base: i.baseUnit,
      kcal: i.kcal,
      protein: i.protein,
      carbs: i.carbs,
      fat: i.fat,
      gramsPerPiece: i.gramsPerPiece,
      gramsPerMl: i.gramsPerMl,
    );

/// Resolved per-serving nutrition for a recipe (overrides applied).
Nutrition? recipePerServing(Recipe r, RecipeNutritionResult calc) {
  final hasOverride = r.kcalOverride != null ||
      r.proteinOverride != null ||
      r.carbsOverride != null ||
      r.fatOverride != null;
  if (!calc.hasData && !hasOverride) return null;
  return applyOverrides(calc.perServing,
      kcal: r.kcalOverride,
      protein: r.proteinOverride,
      carbs: r.carbsOverride,
      fat: r.fatOverride);
}

class RecipeListItem {
  RecipeListItem({
    required this.recipe,
    required this.categoryIds,
    required this.slots,
    required this.perServing,
    required this.incomplete,
    required this.prepCount,
    required this.lastPrepared,
  });
  final Recipe recipe;
  final Set<int> categoryIds;
  final Set<MealSlot> slots;
  final Nutrition? perServing;
  final bool incomplete;
  final int prepCount;
  final String? lastPrepared;
}

class DraftLine {
  DraftLine({required this.ingredientId, required this.quantity, required this.unit});
  int ingredientId;
  double quantity;
  QuantityUnit unit;
}

/// Editable copy of a recipe.
class RecipeDraft {
  RecipeDraft({
    this.id,
    this.name = '',
    this.description,
    this.imagePath,
    this.instructions = '',
    this.prepMinutes,
    this.cookMinutes,
    this.servings = 1,
    this.kcalOverride,
    this.proteinOverride,
    this.carbsOverride,
    this.fatOverride,
    this.isFavorite = false,
    Set<int>? categoryIds,
    Set<MealSlot>? slots,
    List<DraftLine>? lines,
  })  : categoryIds = categoryIds ?? {},
        slots = slots ?? {MealSlot.lunch},
        lines = lines ?? [];

  int? id;
  String name;
  String? description, imagePath;
  String instructions;
  int? prepMinutes, cookMinutes;
  double servings;
  double? kcalOverride, proteinOverride, carbsOverride, fatOverride;
  bool isFavorite;
  Set<int> categoryIds;
  Set<MealSlot> slots;
  List<DraftLine> lines;
}

class RecipeRepository {
  RecipeRepository(this.db);
  final AppDatabase db;

  Stream<void> _changes() => db
      .tableUpdates(TableUpdateQuery.onAllTables([
        db.recipes,
        db.recipeCategories,
        db.recipeMealTypes,
        db.recipeIngredients,
        db.ingredients,
        db.prepBatches,
      ]));

  Stream<List<RecipeListItem>> watchRecipes() async* {
    yield await loadAll();
    await for (final _ in _changes()) {
      yield await loadAll();
    }
  }

  Future<List<RecipeListItem>> loadAll() async {
    final recipes = await (db.select(db.recipes)
          ..where((r) => r.archived.equals(false))
          ..orderBy([(r) => OrderingTerm.asc(r.name)]))
        .get();
    final cats = await db.select(db.recipeCategories).get();
    final slots = await db.select(db.recipeMealTypes).get();
    final ings = {for (final i in await db.select(db.ingredients).get()) i.id: i};
    final lines = await db.select(db.recipeIngredients).get();
    final batches = await db.select(db.prepBatches).get();

    final catsBy = <int, Set<int>>{};
    for (final c in cats) {
      (catsBy[c.recipeId] ??= {}).add(c.categoryId);
    }
    final slotsBy = <int, Set<MealSlot>>{};
    for (final s in slots) {
      (slotsBy[s.recipeId] ??= {}).add(s.slot);
    }
    final linesBy = <int, List<RecipeLine>>{};
    for (final l in lines) {
      final ing = ings[l.ingredientId];
      if (ing == null) continue;
      (linesBy[l.recipeId] ??= []).add(RecipeLine(l.quantity, l.unit, factsOf(ing)));
    }
    final countBy = <int, int>{};
    final lastBy = <int, String>{};
    for (final b in batches) {
      final rid = b.recipeId;
      if (rid == null) continue;
      countBy[rid] = (countBy[rid] ?? 0) + 1;
      final cur = lastBy[rid];
      if (cur == null || b.cookedOn.compareTo(cur) > 0) lastBy[rid] = b.cookedOn;
    }

    return [
      for (final r in recipes)
        () {
          final calc = calculateRecipe(linesBy[r.id] ?? const [], r.servings);
          return RecipeListItem(
            recipe: r,
            categoryIds: catsBy[r.id] ?? {},
            slots: slotsBy[r.id] ?? {},
            perServing: recipePerServing(r, calc),
            incomplete: calc.isIncomplete,
            prepCount: countBy[r.id] ?? 0,
            lastPrepared: lastBy[r.id],
          );
        }(),
    ];
  }

  Future<RecipeDraft?> getDraft(int id) async {
    final r = await (db.select(db.recipes)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (r == null) return null;
    final cats = await (db.select(db.recipeCategories)..where((t) => t.recipeId.equals(id))).get();
    final slots = await (db.select(db.recipeMealTypes)..where((t) => t.recipeId.equals(id))).get();
    final lines = await (db.select(db.recipeIngredients)
          ..where((t) => t.recipeId.equals(id))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
    return RecipeDraft(
      id: r.id,
      name: r.name,
      description: r.description,
      imagePath: r.imagePath,
      instructions: r.instructions,
      prepMinutes: r.prepMinutes,
      cookMinutes: r.cookMinutes,
      servings: r.servings,
      kcalOverride: r.kcalOverride,
      proteinOverride: r.proteinOverride,
      carbsOverride: r.carbsOverride,
      fatOverride: r.fatOverride,
      isFavorite: r.isFavorite,
      categoryIds: cats.map((c) => c.categoryId).toSet(),
      slots: slots.map((s) => s.slot).toSet(),
      lines: [
        for (final l in lines)
          DraftLine(ingredientId: l.ingredientId, quantity: l.quantity, unit: l.unit)
      ],
    );
  }

  Future<int> save(RecipeDraft d) => db.transaction(() async {
        final now = DateTime.now();
        final companion = RecipesCompanion(
          name: Value(d.name.trim()),
          description: Value(d.description),
          imagePath: Value(d.imagePath),
          instructions: Value(d.instructions),
          prepMinutes: Value(d.prepMinutes),
          cookMinutes: Value(d.cookMinutes),
          servings: Value(d.servings <= 0 ? 1 : d.servings),
          kcalOverride: Value(d.kcalOverride),
          proteinOverride: Value(d.proteinOverride),
          carbsOverride: Value(d.carbsOverride),
          fatOverride: Value(d.fatOverride),
          isFavorite: Value(d.isFavorite),
          updatedAt: Value(now),
        );
        int id;
        if (d.id == null) {
          id = await db.into(db.recipes).insert(companion);
        } else {
          id = d.id!;
          await (db.update(db.recipes)..where((t) => t.id.equals(id))).write(companion);
          await (db.delete(db.recipeIngredients)..where((t) => t.recipeId.equals(id))).go();
          await (db.delete(db.recipeCategories)..where((t) => t.recipeId.equals(id))).go();
          await (db.delete(db.recipeMealTypes)..where((t) => t.recipeId.equals(id))).go();
        }
        await db.batch((b) {
          b.insertAll(db.recipeIngredients, [
            for (var i = 0; i < d.lines.length; i++)
              RecipeIngredientsCompanion.insert(
                recipeId: id,
                ingredientId: d.lines[i].ingredientId,
                quantity: d.lines[i].quantity,
                unit: d.lines[i].unit,
                sortOrder: Value(i),
              ),
          ]);
          b.insertAll(db.recipeCategories, [
            for (final c in d.categoryIds)
              RecipeCategoriesCompanion.insert(recipeId: id, categoryId: c),
          ]);
          b.insertAll(db.recipeMealTypes, [
            for (final s in d.slots) RecipeMealTypesCompanion.insert(recipeId: id, slot: s),
          ]);
        });
        return id;
      });

  Future<int?> duplicate(int id) async {
    final d = await getDraft(id);
    if (d == null) return null;
    d
      ..id = null
      ..name = '${d.name} (copy)'
      ..isFavorite = false;
    return save(d);
  }

  Future<void> delete(int id) =>
      (db.delete(db.recipes)..where((t) => t.id.equals(id))).go();

  Future<void> setFavorite(int id, bool value) =>
      (db.update(db.recipes)..where((t) => t.id.equals(id)))
          .write(RecipesCompanion(isFavorite: Value(value)));

  // ---- Categories ----
  Stream<List<Category>> watchCategories() => (db.select(db.categories)
        ..orderBy([(c) => OrderingTerm.asc(c.sortOrder), (c) => OrderingTerm.asc(c.name)]))
      .watch();

  Future<int> addCategory(String name) async {
    final n = (await db.select(db.categories).get()).length;
    return db.into(db.categories).insert(
        CategoriesCompanion.insert(name: name.trim(), sortOrder: Value(n)));
  }

  Future<void> renameCategory(int id, String name) =>
      (db.update(db.categories)..where((c) => c.id.equals(id)))
          .write(CategoriesCompanion(name: Value(name.trim())));

  Future<void> deleteCategory(int id) =>
      (db.delete(db.categories)..where((c) => c.id.equals(id))).go();

  // ---- Ingredients ----
  Stream<List<Ingredient>> watchIngredients() => (db.select(db.ingredients)
        ..orderBy([(i) => OrderingTerm.asc(i.name)]))
      .watch();

  Future<int> saveIngredient(IngredientsCompanion c, {int? id}) async {
    if (id == null) return db.into(db.ingredients).insert(c);
    await (db.update(db.ingredients)..where((i) => i.id.equals(id))).write(c);
    return id;
  }

  /// Returns false if the ingredient is still used by a recipe.
  Future<bool> deleteIngredient(int id) async {
    final used = await (db.select(db.recipeIngredients)
          ..where((l) => l.ingredientId.equals(id))
          ..limit(1))
        .get();
    if (used.isNotEmpty) return false;
    await (db.delete(db.ingredients)..where((i) => i.id.equals(id))).go();
    return true;
  }
}
