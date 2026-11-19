import 'package:drift/drift.dart';

import '../domain/nutrition.dart';
import 'db/database.dart';
import 'recipe_repository.dart';

/// Owns the weekly schedule, day overrides and all meal entries. Planner,
/// Calendar and Calories all read/write through here (one source of truth).
class MealRepository {
  MealRepository(this.db, this.recipes);
  final AppDatabase db;
  final RecipeRepository recipes;

  // ---------------------------------------------------------------- schedule

  Stream<Map<int, DayType>> watchWeekly() => db
      .select(db.weeklySchedule)
      .watch()
      .map((rows) => {for (final r in rows) r.weekday: r.dayType});

  Future<Map<int, DayType>> getWeekly() async =>
      {for (final r in await db.select(db.weeklySchedule).get()) r.weekday: r.dayType};

  Future<void> setWeekly(int weekday, DayType type) => db
      .into(db.weeklySchedule)
      .insertOnConflictUpdate(WeeklyScheduleCompanion.insert(weekday: Value(weekday), dayType: type));

  Stream<Map<String, DayOverride>> watchOverrides() => db
      .select(db.dayOverrides)
      .watch()
      .map((rows) => {for (final r in rows) r.date: r});

  Future<Map<String, DayType>> getOverrideTypes() async => {
        for (final r in await db.select(db.dayOverrides).get())
          if (r.dayType != null) r.date: r.dayType!
      };

  /// Sets or clears (null) the day-type override for one date only.
  /// Never touches the weekly schedule.
  Future<void> setDayTypeOverride(String date, DayType? type) async {
    final existing =
        await (db.select(db.dayOverrides)..where((o) => o.date.equals(date))).getSingleOrNull();
    if (type == null && (existing?.note == null || existing!.note!.isEmpty)) {
      await (db.delete(db.dayOverrides)..where((o) => o.date.equals(date))).go();
      return;
    }
    await db.into(db.dayOverrides).insertOnConflictUpdate(DayOverridesCompanion(
        date: Value(date), dayType: Value(type), note: Value(existing?.note)));
  }

  Future<void> setDayNote(String date, String? note) async {
    final existing =
        await (db.select(db.dayOverrides)..where((o) => o.date.equals(date))).getSingleOrNull();
    final n = (note == null || note.trim().isEmpty) ? null : note.trim();
    if (n == null && existing?.dayType == null) {
      await (db.delete(db.dayOverrides)..where((o) => o.date.equals(date))).go();
      return;
    }
    await db.into(db.dayOverrides).insertOnConflictUpdate(DayOverridesCompanion(
        date: Value(date), dayType: Value(existing?.dayType), note: Value(n)));
  }

  // ----------------------------------------------------------------- entries

  Stream<List<MealEntry>> watchEntries(String fromInclusive, String toInclusive) =>
      (db.select(db.mealEntries)
            ..where((e) => e.date.isBetweenValues(fromInclusive, toInclusive))
            ..orderBy([(e) => OrderingTerm.asc(e.date), (e) => OrderingTerm.asc(e.slot), (e) => OrderingTerm.asc(e.id)]))
          .watch();

  Future<List<MealEntry>> entriesBetween(String from, String to) =>
      (db.select(db.mealEntries)
            ..where((e) => e.date.isBetweenValues(from, to))
            ..orderBy([(e) => OrderingTerm.asc(e.date), (e) => OrderingTerm.asc(e.slot)]))
          .get();

  /// Nutrition of [servings] servings of a recipe at this moment (a snapshot).
  Future<({String name, Nutrition? n})?> snapshotRecipe(int recipeId, double servings) async {
    final item = (await recipes.loadAll()).where((r) => r.recipe.id == recipeId).firstOrNull;
    if (item == null) return null;
    return (name: item.recipe.name, n: item.perServing?.scale(servings));
  }

  Future<int> addRecipeEntry({
    required String date,
    required MealSlot slot,
    required int recipeId,
    double servings = 1,
    MealState state = MealState.planned,
    bool locked = false,
    int? batchId,
    bool isLeftover = false,
  }) async {
    final snap = await snapshotRecipe(recipeId, servings);
    if (snap == null) throw ArgumentError('Recipe $recipeId not found');
    return db.into(db.mealEntries).insert(MealEntriesCompanion.insert(
          date: date,
          slot: slot,
          state: state,
          kind: EntryKind.recipe,
          recipeId: Value(recipeId),
          batchId: Value(batchId),
          isLeftover: Value(isLeftover),
          locked: Value(locked),
          servings: Value(servings),
          title: Value(snap.name),
          kcal: Value(snap.n?.kcal),
          protein: Value(snap.n?.protein),
          carbs: Value(snap.n?.carbs),
          fat: Value(snap.n?.fat),
        ));
  }

  /// A meal without a recipe (e.g. provided at the office, or eaten out).
  Future<int> addExternalEntry({
    required String date,
    required MealSlot slot,
    required String title,
    double? kcal,
    double? protein,
    double? carbs,
    double? fat,
    MealState state = MealState.consumed,
    bool locked = false,
  }) =>
      db.into(db.mealEntries).insert(MealEntriesCompanion.insert(
            date: date,
            slot: slot,
            state: state,
            kind: EntryKind.external,
            title: Value(title),
            kcal: Value(kcal),
            protein: Value(protein),
            carbs: Value(carbs),
            fat: Value(fat),
            locked: Value(locked),
          ));

  /// Entry built from individual food items; nutrition is the sum of items.
  Future<int> addItemsEntry({
    required String date,
    required MealSlot slot,
    required String title,
    required List<MealEntryItemsCompanion Function(int entryId)> items,
    required Nutrition total,
    MealState state = MealState.consumed,
  }) =>
      db.transaction(() async {
        final id = await db.into(db.mealEntries).insert(MealEntriesCompanion.insert(
              date: date,
              slot: slot,
              state: state,
              kind: EntryKind.items,
              title: Value(title),
              kcal: Value(total.kcal),
              protein: Value(total.protein),
              carbs: Value(total.carbs),
              fat: Value(total.fat),
            ));
        for (final mk in items) {
          await db.into(db.mealEntryItems).insert(mk(id));
        }
        return id;
      });

  Future<MealEntry?> getEntry(int id) =>
      (db.select(db.mealEntries)..where((e) => e.id.equals(id))).getSingleOrNull();

  /// Changes an entry's state. Moving a recipe entry to prepared/consumed
  /// refreshes its nutrition snapshot from the current recipe and, for a fresh
  /// cooking (not a leftover), records a preparation batch.
  Future<void> setState(int id, MealState state) async {
    final e = await getEntry(id);
    if (e == null) return;
    var c = MealEntriesCompanion(state: Value(state));
    final isActive = state == MealState.prepared || state == MealState.consumed;
    if (isActive && e.kind == EntryKind.recipe && e.recipeId != null) {
      final snap = await snapshotRecipe(e.recipeId!, e.servings);
      if (snap != null) {
        c = c.copyWith(
          title: Value(snap.name),
          kcal: Value(snap.n?.kcal),
          protein: Value(snap.n?.protein),
          carbs: Value(snap.n?.carbs),
          fat: Value(snap.n?.fat),
        );
      }
      if (e.batchId == null && !e.isLeftover) {
        final recipe = await (db.select(db.recipes)..where((r) => r.id.equals(e.recipeId!))).getSingleOrNull();
        final batchId = await db.into(db.prepBatches).insert(PrepBatchesCompanion.insert(
            recipeId: Value(e.recipeId), cookedOn: e.date, portionsMade: recipe?.servings ?? e.servings));
        c = c.copyWith(batchId: Value(batchId));
      }
    }
    await (db.update(db.mealEntries)..where((t) => t.id.equals(id))).write(c);
  }

  Future<void> setServings(int id, double servings) async {
    final e = await getEntry(id);
    if (e == null || servings <= 0) return;
    var c = MealEntriesCompanion(servings: Value(servings));
    if (e.kind == EntryKind.recipe && e.recipeId != null && e.servings > 0) {
      if (e.state == MealState.planned) {
        final snap = await snapshotRecipe(e.recipeId!, servings);
        if (snap?.n != null) {
          c = c.copyWith(kcal: Value(snap!.n!.kcal), protein: Value(snap.n!.protein), carbs: Value(snap.n!.carbs), fat: Value(snap.n!.fat));
        }
      } else {
        // Keep the historical snapshot proportional to the servings eaten.
        final f = servings / e.servings;
        c = c.copyWith(
          kcal: Value(e.kcal == null ? null : e.kcal! * f),
          protein: Value(e.protein == null ? null : e.protein! * f),
          carbs: Value(e.carbs == null ? null : e.carbs! * f),
          fat: Value(e.fat == null ? null : e.fat! * f),
        );
      }
    }
    await (db.update(db.mealEntries)..where((t) => t.id.equals(id))).write(c);
  }

  /// Replaces the recipe of an entry (manual swap). Resets it to planned unless
  /// [keepState]; drops any batch link because it is a different dish.
  Future<void> replaceRecipe(int id, int recipeId) async {
    final e = await getEntry(id);
    if (e == null) return;
    final snap = await snapshotRecipe(recipeId, e.servings);
    if (snap == null) return;
    await (db.update(db.mealEntries)..where((t) => t.id.equals(id))).write(MealEntriesCompanion(
      kind: const Value(EntryKind.recipe),
      recipeId: Value(recipeId),
      batchId: const Value(null),
      isLeftover: const Value(false),
      state: const Value(MealState.planned),
      title: Value(snap.name),
      kcal: Value(snap.n?.kcal),
      protein: Value(snap.n?.protein),
      carbs: Value(snap.n?.carbs),
      fat: Value(snap.n?.fat),
    ));
  }

  Future<void> setLocked(int id, bool locked) => (db.update(db.mealEntries)..where((t) => t.id.equals(id)))
      .write(MealEntriesCompanion(locked: Value(locked)));

  /// Locks or unlocks every entry on a date.
  Future<void> setDayLocked(String date, bool locked) =>
      (db.update(db.mealEntries)..where((t) => t.date.equals(date)))
          .write(MealEntriesCompanion(locked: Value(locked)));

  Future<void> setNotes(int id, String? notes) => (db.update(db.mealEntries)..where((t) => t.id.equals(id)))
      .write(MealEntriesCompanion(notes: Value(notes)));

  Future<void> deleteEntry(int id) =>
      (db.delete(db.mealEntries)..where((t) => t.id.equals(id))).go();

  // ----------------------------------------------------------------- batches

  /// Portions of a batch not yet linked to any non-skipped entry.
  Future<double> remainingPortions(int batchId) async {
    final b = await (db.select(db.prepBatches)..where((t) => t.id.equals(batchId))).getSingleOrNull();
    if (b == null) return 0;
    final entries = await (db.select(db.mealEntries)
          ..where((e) => e.batchId.equals(batchId) & e.state.equals(MealState.skipped.index).not()))
        .get();
    final used = entries.fold<double>(0, (s, e) => s + e.servings);
    final r = b.portionsMade - used;
    return r < 0 ? 0 : r;
  }
}
