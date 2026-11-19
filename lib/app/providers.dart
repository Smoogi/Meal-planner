import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/database.dart';
import '../data/meal_repository.dart';
import '../data/planner_service.dart';
import '../data/planner_settings.dart';
import '../data/recipe_repository.dart';
import '../data/settings_repository.dart';

/// Single shared database for all modules.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void set(ThemeMode mode) => state = mode;
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

final recipeRepositoryProvider =
    Provider((ref) => RecipeRepository(ref.watch(databaseProvider)));

final recipesProvider = StreamProvider<List<RecipeListItem>>(
    (ref) => ref.watch(recipeRepositoryProvider).watchRecipes());

final settingsRepositoryProvider =
    Provider((ref) => SettingsRepository(ref.watch(databaseProvider)));

final settingsProvider = StreamProvider<Map<String, String>>(
    (ref) => ref.watch(settingsRepositoryProvider).watchAll());

final mealRepositoryProvider = Provider((ref) => MealRepository(
    ref.watch(databaseProvider), ref.watch(recipeRepositoryProvider)));

final weeklyScheduleProvider = StreamProvider<Map<int, DayType>>(
    (ref) => ref.watch(mealRepositoryProvider).watchWeekly());

final dayOverridesProvider = StreamProvider<Map<String, DayOverride>>(
    (ref) => ref.watch(mealRepositoryProvider).watchOverrides());

/// Entries between two inclusive date keys.
final entriesProvider = StreamProvider.family<List<MealEntry>, (String, String)>(
    (ref, range) => ref.watch(mealRepositoryProvider).watchEntries(range.$1, range.$2));

final categoriesProvider = StreamProvider<List<Category>>(
    (ref) => ref.watch(recipeRepositoryProvider).watchCategories());

final ingredientsProvider = StreamProvider<List<Ingredient>>(
    (ref) => ref.watch(recipeRepositoryProvider).watchIngredients());

final plannerSettingsProvider = Provider<PlannerSettings>(
    (ref) => PlannerSettings.fromMap(ref.watch(settingsProvider).value ?? const {}));

final plannerServiceProvider = Provider((ref) => PlannerService(
    ref.watch(databaseProvider),
    ref.watch(recipeRepositoryProvider),
    ref.watch(mealRepositoryProvider)));

/// First day of week from settings (1 = Monday ... 7 = Sunday).
final firstDayOfWeekProvider = Provider<int>((ref) =>
    int.tryParse((ref.watch(settingsProvider).value ?? const {})['calendar.firstDayOfWeek'] ?? '') ?? 1);
