import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../data/recipe_repository.dart';
import '../../domain/nutrition.dart';
import '../calendar/day_style.dart';
import '../calendar/recipe_picker.dart';

Future<void> showLogMealSheet(BuildContext context, String date, {MealSlot slot = MealSlot.lunch}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => LogMealSheet(date: date, initialSlot: slot),
    );

double? _num(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

class LogMealSheet extends ConsumerStatefulWidget {
  const LogMealSheet({super.key, required this.date, this.initialSlot = MealSlot.lunch});
  final String date;
  final MealSlot initialSlot;

  @override
  ConsumerState<LogMealSheet> createState() => _LogMealSheetState();
}

class _ItemDraft {
  _ItemDraft(this.ingredientId, this.quantity, this.unit);
  int ingredientId;
  double quantity;
  QuantityUnit unit;
}

class _LogMealSheetState extends ConsumerState<LogMealSheet> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  late MealSlot _slot = widget.initialSlot;

  // Recipe tab
  int? _recipeId;
  final _servings = TextEditingController(text: '1');

  // Quick tab
  final _qTitle = TextEditingController();
  final _qKcal = TextEditingController();
  final _qP = TextEditingController();
  final _qC = TextEditingController();
  final _qF = TextEditingController();

  // Ingredients tab
  final _iTitle = TextEditingController();
  final List<_ItemDraft> _items = [];

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [_servings, _qTitle, _qKcal, _qP, _qC, _qF, _iTitle]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final repo = ref.read(mealRepositoryProvider);
    switch (_tabs.index) {
      case 0:
        final s = _num(_servings.text);
        if (_recipeId == null || s == null || s <= 0) return _msg('Pick a recipe and enter servings.');
        final id = await repo.addRecipeEntry(
            date: widget.date, slot: _slot, recipeId: _recipeId!, servings: s);
        await repo.setState(id, MealState.consumed);
      case 1:
        if (_qTitle.text.trim().isEmpty) return _msg('Enter a meal name.');
        final kcal = _num(_qKcal.text);
        if (kcal == null) return _msg('Enter the calories.');
        await repo.addExternalEntry(
          date: widget.date,
          slot: _slot,
          title: _qTitle.text.trim(),
          kcal: kcal,
          protein: _num(_qP.text),
          carbs: _num(_qC.text),
          fat: _num(_qF.text),
        );
      case 2:
        final ings = {for (final i in ref.read(ingredientsProvider).value ?? const <Ingredient>[]) i.id: i};
        if (_items.isEmpty) return _msg('Add at least one ingredient.');
        var total = Nutrition.zero;
        final companions = <MealEntryItemsCompanion Function(int)>[];
        for (final it in _items) {
          final ing = ings[it.ingredientId];
          if (ing == null) continue;
          final n = lineNutrition(it.quantity, it.unit, factsOf(ing));
          if (n != null) total = total + n;
          companions.add((entryId) => MealEntryItemsCompanion.insert(
                entryId: entryId,
                name: ing.name,
                quantity: it.quantity,
                unit: it.unit,
                kcal: Value(n?.kcal),
                protein: Value(n?.protein),
                carbs: Value(n?.carbs),
                fat: Value(n?.fat),
              ));
        }
        final title = _iTitle.text.trim().isEmpty
            ? _items.map((i) => ings[i.ingredientId]?.name ?? '?').take(3).join(', ')
            : _iTitle.text.trim();
        await repo.addItemsEntry(
            date: widget.date, slot: _slot, title: title, items: companions, total: total);
    }
    if (mounted) Navigator.pop(context);
  }

  void _msg(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(child: Text('Log meal · ${widget.date}', style: Theme.of(context).textTheme.titleMedium)),
              SegmentedButton<MealSlot>(
                showSelectedIcon: false,
                segments: [for (final s in MealSlot.values) ButtonSegment(value: s, label: Text(s.label))],
                selected: {_slot},
                onSelectionChanged: (v) => setState(() => _slot = v.first),
              ),
            ]),
          ),
          TabBar(controller: _tabs, tabs: const [
            Tab(text: 'Recipe'),
            Tab(text: 'Quick'),
            Tab(text: 'Ingredients'),
          ]),
          Expanded(
            child: TabBarView(controller: _tabs, children: [_recipeTab(), _quickTab(), _itemsTab()]),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: _save, child: const Text('Save as consumed'))),
          ),
        ]),
      ),
    );
  }

  Widget _recipeTab() {
    final recipes = ref.watch(recipesProvider).value ?? const [];
    final sel = recipes.where((r) => r.recipe.id == _recipeId).firstOrNull;
    final s = _num(_servings.text) ?? 0;
    final n = sel?.perServing;
    return ListView(padding: const EdgeInsets.all(16), children: [
      OutlinedButton.icon(
        icon: const Icon(Icons.restaurant_menu),
        label: Text(sel?.recipe.name ?? 'Choose recipe'),
        onPressed: () async {
          final id = await pickRecipe(context, slot: _slot);
          if (id != null) setState(() => _recipeId = id);
        },
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _servings,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Servings eaten', border: OutlineInputBorder()),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      if (n != null)
        Text('${(n.kcal * s).round()} kcal · P ${(n.protein * s).toStringAsFixed(1)} g · '
            'C ${(n.carbs * s).toStringAsFixed(1)} g · F ${(n.fat * s).toStringAsFixed(1)} g')
      else if (sel != null)
        const Text('This recipe has no nutrition data yet; it will be logged without calories.'),
    ]);
  }

  Widget _quickTab() {
    Widget num(TextEditingController c, String l) => Expanded(
          child: TextField(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: l, border: const OutlineInputBorder()),
          ),
        );
    return ListView(padding: const EdgeInsets.all(16), children: [
      TextField(
        controller: _qTitle,
        decoration: const InputDecoration(
            labelText: 'Meal (e.g. Chicken with rice)', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 12),
      Row(children: [num(_qKcal, 'Calories (kcal)')]),
      const SizedBox(height: 12),
      Row(children: [num(_qP, 'Protein g'), const SizedBox(width: 8), num(_qC, 'Carbs g'), const SizedBox(width: 8), num(_qF, 'Fat g')]),
      const SizedBox(height: 8),
      const Text('No recipe needed. Macros are optional.'),
    ]);
  }

  Widget _itemsTab() {
    final ings = ref.watch(ingredientsProvider).value ?? const <Ingredient>[];
    final byId = {for (final i in ings) i.id: i};
    var total = Nutrition.zero;
    var missing = 0;
    for (final it in _items) {
      final ing = byId[it.ingredientId];
      final n = ing == null ? null : lineNutrition(it.quantity, it.unit, factsOf(ing));
      if (n == null) {
        missing++;
      } else {
        total = total + n;
      }
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      TextField(
        controller: _iTitle,
        decoration: const InputDecoration(labelText: 'Name (optional)', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 8),
      for (var i = 0; i < _items.length; i++)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(byId[_items[i].ingredientId]?.name ?? '?'),
          subtitle: Text('${_items[i].quantity} ${_items[i].unit.label}'),
          onTap: () => _editItem(_items[i], ings),
          trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => setState(() => _items.removeAt(i))),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Add ingredient'),
          onPressed: ings.isEmpty
              ? null
              : () async {
                  final d = _ItemDraft(ings.first.id, 100, QuantityUnit.g);
                  if (await _editItem(d, ings)) setState(() => _items.add(d));
                },
        ),
      ),
      if (_items.isNotEmpty)
        Text('Total: ${total.kcal.round()} kcal · P ${total.protein.toStringAsFixed(1)} g · '
            'C ${total.carbs.toStringAsFixed(1)} g · F ${total.fat.toStringAsFixed(1)} g'
            '${missing > 0 ? '\n$missing item(s) could not be calculated and are not included.' : ''}'),
    ]);
  }

  Future<bool> _editItem(_ItemDraft d, List<Ingredient> ings) async {
    var ingId = d.ingredientId;
    var unit = d.unit;
    final qty = TextEditingController(text: d.quantity.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Ingredient'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownMenu<int>(
              initialSelection: ingId,
              expandedInsets: EdgeInsets.zero,
              enableFilter: true,
              requestFocusOnTap: true,
              dropdownMenuEntries: [for (final i in ings) DropdownMenuEntry(value: i.id, label: i.name)],
              onSelected: (v) {
                if (v == null) return;
                ingId = v;
                setS(() => unit = switch (ings.firstWhere((i) => i.id == v).baseUnit) {
                      BaseUnit.gram => QuantityUnit.g,
                      BaseUnit.milliliter => QuantityUnit.ml,
                      BaseUnit.piece => QuantityUnit.piece,
                    });
              },
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: qty,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Quantity', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<QuantityUnit>(
                value: unit,
                items: [for (final u in QuantityUnit.values) DropdownMenuItem(value: u, child: Text(u.label))],
                onChanged: (v) => setS(() => unit = v ?? unit),
              ),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
          ],
        ),
      ),
    );
    if (ok == true) {
      setState(() {
        d.ingredientId = ingId;
        d.unit = unit;
        d.quantity = _num(qty.text) ?? d.quantity;
      });
      return true;
    }
    return false;
  }
}
