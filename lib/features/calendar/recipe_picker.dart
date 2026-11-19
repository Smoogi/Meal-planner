import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';

/// Lets the user choose a recipe (suitable ones first). Returns its id.
Future<int?> pickRecipe(BuildContext context, {MealSlot? slot}) => showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _RecipePicker(slot: slot),
    );

class _RecipePicker extends ConsumerStatefulWidget {
  const _RecipePicker({this.slot});
  final MealSlot? slot;

  @override
  ConsumerState<_RecipePicker> createState() => _RecipePickerState();
}

class _RecipePickerState extends ConsumerState<_RecipePicker> {
  String _q = '';
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final recipes = ref.watch(recipesProvider).value ?? const [];
    final items = recipes.where((r) {
      if (_q.isNotEmpty && !r.recipe.name.toLowerCase().contains(_q)) return false;
      if (!_all && widget.slot != null && !r.slots.contains(widget.slot)) return false;
      return true;
    }).toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: SearchBar(
            hintText: 'Search recipes',
            leading: const Icon(Icons.search),
            onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
          ),
        ),
        if (widget.slot != null)
          SwitchListTile(
            dense: true,
            title: const Text('Show recipes for any meal type'),
            value: _all,
            onChanged: (v) => setState(() => _all = v),
          ),
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text('No matching recipes.'))
              : ListView.builder(
                  controller: scroll,
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final r = items[i];
                    return ListTile(
                      leading: Icon(r.recipe.isFavorite ? Icons.favorite : Icons.restaurant_menu,
                          color: r.recipe.isFavorite ? Colors.redAccent : null),
                      title: Text(r.recipe.name),
                      subtitle: r.perServing == null
                          ? null
                          : Text('${r.perServing!.kcal.round()} kcal/serving'),
                      onTap: () => Navigator.pop(context, r.recipe.id),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

class ExternalMeal {
  ExternalMeal(this.title, this.kcal, this.protein, this.carbs, this.fat);
  final String title;
  final double? kcal, protein, carbs, fat;
}

/// Asks for a free-text meal with optional calories (no recipe needed).
Future<ExternalMeal?> askExternalMeal(BuildContext context,
    {String initialTitle = '', bool kcalRequired = false}) {
  final title = TextEditingController(text: initialTitle);
  final kcal = TextEditingController();
  final p = TextEditingController();
  final c = TextEditingController();
  final f = TextEditingController();
  double? n(TextEditingController t) => double.tryParse(t.text.trim().replaceAll(',', '.'));
  Widget num(TextEditingController t, String l) => Expanded(
        child: TextField(
          controller: t,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: l, border: const OutlineInputBorder()),
        ),
      );
  return showDialog<ExternalMeal>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Meal without recipe'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Meal (e.g. Chicken with rice)')),
          const SizedBox(height: 12),
          Row(children: [num(kcal, kcalRequired ? 'kcal' : 'kcal (optional)')]),
          const SizedBox(height: 8),
          Row(children: [num(p, 'Protein g'), const SizedBox(width: 6), num(c, 'Carbs g'), const SizedBox(width: 6), num(f, 'Fat g')]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (title.text.trim().isEmpty) return;
            Navigator.pop(ctx, ExternalMeal(title.text.trim(), n(kcal), n(p), n(c), n(f)));
          },
          child: const Text('Add'),
        ),
      ],
    ),
  );
}
