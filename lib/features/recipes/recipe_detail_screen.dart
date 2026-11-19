import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../data/recipe_repository.dart';
import 'recipe_edit_screen.dart';
import 'recipes_screen.dart' show RecipeThumb;

class RecipeDetailScreen extends ConsumerWidget {
  const RecipeDetailScreen({super.key, required this.recipeId});
  final int recipeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(recipeRepositoryProvider);
    final item = ref.watch(recipesProvider).value?.where((r) => r.recipe.id == recipeId).firstOrNull;
    final cats = ref.watch(categoriesProvider).value ?? const <Category>[];
    final ings = ref.watch(ingredientsProvider).value ?? const <Ingredient>[];
    if (item == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final r = item.recipe;
    final n = item.perServing;

    return Scaffold(
      appBar: AppBar(
        title: Text(r.name),
        actions: [
          IconButton(
            icon: Icon(r.isFavorite ? Icons.favorite : Icons.favorite_border),
            onPressed: () => repo.setFavorite(r.id, !r.isFavorite),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => RecipeEditScreen(recipeId: r.id))),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'dup') {
                final id = await repo.duplicate(r.id);
                if (id != null && context.mounted) {
                  Navigator.of(context).pushReplacement(MaterialPageRoute(
                      builder: (_) => RecipeEditScreen(recipeId: id)));
                }
              } else if (v == 'del') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete recipe?'),
                    content: const Text(
                        'Meals already logged keep their recorded nutrition. This cannot be undone.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                    ],
                  ),
                );
                if (ok == true) {
                  await repo.delete(r.id);
                  if (context.mounted) Navigator.of(context).pop();
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'dup', child: Text('Duplicate')),
              PopupMenuItem(value: 'del', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: FutureBuilder<RecipeDraft?>(
        future: repo.getDraft(recipeId),
        builder: (context, snap) {
          final d = snap.data;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Center(child: RecipeThumb(path: r.imagePath, size: 160)),
            const SizedBox(height: 12),
            if (r.description != null) Text(r.description!),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final c in cats.where((c) => item.categoryIds.contains(c.id)))
                Chip(label: Text(c.name)),
              for (final s in item.slots)
                Chip(label: Text(s == MealSlot.marenda ? 'Marenda' : 'Lunch')),
            ]),
            const SizedBox(height: 8),
            Text([
              if (r.prepMinutes != null) 'Prep ${r.prepMinutes} min',
              if (r.cookMinutes != null) 'Cook ${r.cookMinutes} min',
              '${r.servings == r.servings.roundToDouble() ? r.servings.toInt() : r.servings} servings',
            ].join(' · ')),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Per serving', style: Theme.of(context).textTheme.titleSmall),
                  n == null
                      ? const Text('No nutrition data yet.')
                      : Text('${n.kcal.round()} kcal · P ${n.protein.toStringAsFixed(1)} g · '
                          'C ${n.carbs.toStringAsFixed(1)} g · F ${n.fat.toStringAsFixed(1)} g'),
                  if (item.incomplete)
                    const Text('Some ingredients are missing data, so this is partial.'),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Text('Ingredients', style: Theme.of(context).textTheme.titleMedium),
            if (d != null)
              for (final l in d.lines)
                ListTile(
                  dense: true,
                  title: Text(ings.where((i) => i.id == l.ingredientId).firstOrNull?.name ?? '?'),
                  trailing: Text(
                      '${l.quantity == l.quantity.roundToDouble() ? l.quantity.toInt() : l.quantity} ${l.unit.label}'),
                ),
            const SizedBox(height: 12),
            if (r.instructions.trim().isNotEmpty) ...[
              Text('Instructions', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(r.instructions),
            ],
            const SizedBox(height: 12),
            Text(
                'Prepared ${item.prepCount} time(s)'
                '${item.lastPrepared != null ? ' · last on ${item.lastPrepared}' : ''}',
                style: Theme.of(context).textTheme.bodySmall),
          ]);
        },
      ),
    );
  }
}
