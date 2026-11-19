import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../app_paths.dart';
import '../seed_ingredients.dart';
import 'tables.dart';

export 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [
  Ingredients,
  Recipes,
  RecipeIngredients,
  Categories,
  RecipeCategories,
  RecipeMealTypes,
  WeeklySchedule,
  DayOverrides,
  PrepBatches,
  MealEntries,
  MealEntryItems,
  AppSettings,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase()
      : super(driftDatabase(
          name: 'meal_planner',
          native: DriftNativeOptions(databasePath: AppPaths.dbPath)));

  /// For tests: pass an in-memory executor.
  AppDatabase.forTesting(super.executor);

  /// Bump on every schema change and add a step in [migration].
  @override
  int get schemaVersion => 1;

  static const defaultCategories = [
    'Meat',
    'Fish',
    'Seafood',
    'Vegetables',
    'Pasta',
    'Rice',
    'Soup',
    'Eggs',
    'Vegetarian',
    'Other',
  ];

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement(
              'CREATE INDEX idx_entries_date_slot ON meal_entries (date, slot)');
          await customStatement(
              'CREATE INDEX idx_entries_recipe_date ON meal_entries (recipe_id, date)');
          await customStatement(
              'CREATE INDEX idx_entries_batch ON meal_entries (batch_id)');
          await _seed();
        },
        // Add `onUpgrade: (m, from, to) async { ... }` steps when schemaVersion grows.
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<void> _seed() async {
    await batch((b) {
      b.insertAll(categories, [
        for (var i = 0; i < defaultCategories.length; i++)
          CategoriesCompanion.insert(
              name: defaultCategories[i], sortOrder: Value(i)),
      ]);
      b.insertAll(ingredients, seedIngredients);
      // Mon-Fri alternating WFH/Office, weekend free (user-editable).
      const week = [
        DayType.wfh,
        DayType.office,
        DayType.wfh,
        DayType.office,
        DayType.wfh,
        DayType.free,
        DayType.free,
      ];
      b.insertAll(weeklySchedule, [
        for (var i = 0; i < 7; i++)
          WeeklyScheduleCompanion.insert(weekday: Value(i + 1), dayType: week[i]),
      ]);
    });
  }
}


