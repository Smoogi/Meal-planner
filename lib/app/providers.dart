import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/database.dart';
import '../data/recipe_repository.dart';

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

final categoriesProvider = StreamProvider<List<Category>>(
    (ref) => ref.watch(recipeRepositoryProvider).watchCategories());

final ingredientsProvider = StreamProvider<List<Ingredient>>(
    (ref) => ref.watch(recipeRepositoryProvider).watchIngredients());
