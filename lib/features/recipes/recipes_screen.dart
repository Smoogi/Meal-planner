import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../data/recipe_repository.dart';
import 'categories_screen.dart';
import 'image_store.dart';
import 'ingredients_screen.dart';
import 'recipe_detail_screen.dart';
import 'recipe_edit_screen.dart';

class RecipesScreen extends ConsumerStatefulWidget {
  const RecipesScreen({super.key});

  @override
  ConsumerState<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends ConsumerState<RecipesScreen> {
  String _query = '';
  bool _favoritesOnly = false;
  int? _categoryId;
  MealSlot? _slot;

  @override
  Widget build(BuildContext context) {
    final recipes = ref.watch(recipesProvider);
    final cats = ref.watch(categoriesProvider).value ?? const <Category>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recipes'),
        actions: [
          IconButton(
            tooltip: 'Ingredients',
            icon: const Icon(Icons.egg_alt_outlined),
            onPressed: () => Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(builder: (_) => const IngredientsScreen())),
          ),
          IconButton(
            tooltip: 'Categories',
            icon: const Icon(Icons.label_outline),
            onPressed: () => Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(builder: (_) => const CategoriesScreen())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context, rootNavigator: true)
            .push(MaterialPageRoute(builder: (_) => const RecipeEditScreen())),
        icon: const Icon(Icons.add),
        label: const Text('New recipe'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SearchBar(
              hintText: 'Search recipes',
              leading: const Icon(Icons.search),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _chip('Favorites', _favoritesOnly,
                    (v) => setState(() => _favoritesOnly = v)),
                _chip('Marenda', _slot == MealSlot.marenda,
                    (v) => setState(() => _slot = v ? MealSlot.marenda : null)),
                _chip('Lunch', _slot == MealSlot.lunch,
                    (v) => setState(() => _slot = v ? MealSlot.lunch : null)),
                for (final c in cats)
                  _chip(c.name, _categoryId == c.id,
                      (v) => setState(() => _categoryId = v ? c.id : null)),
              ],
            ),
          ),
          Expanded(
            child: recipes.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (all) {
                final items = all.where((r) {
                  if (_favoritesOnly && !r.recipe.isFavorite) return false;
                  if (_categoryId != null && !r.categoryIds.contains(_categoryId)) return false;
                  if (_slot != null && !r.slots.contains(_slot)) return false;
                  if (_query.isNotEmpty && !r.recipe.name.toLowerCase().contains(_query)) {
                    return false;
                  }
                  return true;
                }).toList();
                if (items.isEmpty) {
                  return Center(
                      child: Text(all.isEmpty
                          ? 'No recipes yet. Tap "New recipe".'
                          : 'No recipes match the filters.'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _RecipeTile(item: items[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, ValueChanged<bool> onSel) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: FilterChip(label: Text(label), selected: selected, onSelected: onSel),
      );
}

class _RecipeTile extends ConsumerWidget {
  const _RecipeTile({required this.item});
  final RecipeListItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = item.recipe;
    final n = item.perServing;
    final sub = [
      if (n != null) '${n.kcal.round()} kcal/serving${item.incomplete ? ' (partial)' : ''}',
      if (r.prepMinutes != null || r.cookMinutes != null)
        '${(r.prepMinutes ?? 0) + (r.cookMinutes ?? 0)} min',
    ].join(' · ');
    return ListTile(
      leading: RecipeThumb(path: r.imagePath, size: 52),
      title: Text(r.name),
      subtitle: sub.isEmpty ? null : Text(sub),
      trailing: IconButton(
        icon: Icon(r.isFavorite ? Icons.favorite : Icons.favorite_border,
            color: r.isFavorite ? Colors.redAccent : null),
        onPressed: () =>
            ref.read(recipeRepositoryProvider).setFavorite(r.id, !r.isFavorite),
      ),
      onTap: () => Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(builder: (_) => RecipeDetailScreen(recipeId: r.id))),
    );
  }
}

class RecipeThumb extends ConsumerWidget {
  const RecipeThumb({super.key, required this.path, this.size = 48});
  final String? path;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final file = path == null ? null : ImageStore.resolveSync(path!);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: size,
        height: size,
        child: file != null && File(file).existsSync()
            ? Image.file(File(file), fit: BoxFit.cover)
            : ColoredBox(
                color: scheme.secondaryContainer,
                child: Icon(Icons.restaurant, color: scheme.onSecondaryContainer)),
      ),
    );
  }
}
