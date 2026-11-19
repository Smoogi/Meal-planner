import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../data/recipe_repository.dart';
import '../../domain/nutrition.dart';
import 'image_store.dart';
import 'recipes_screen.dart' show RecipeThumb;

double? _num(String s) => double.tryParse(s.trim().replaceAll(',', '.'));
String _fmt(double? v) =>
    v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());

class RecipeEditScreen extends ConsumerStatefulWidget {
  const RecipeEditScreen({super.key, this.recipeId});
  final int? recipeId;

  @override
  ConsumerState<RecipeEditScreen> createState() => _RecipeEditScreenState();
}

class _RecipeEditScreenState extends ConsumerState<RecipeEditScreen> {
  final _form = GlobalKey<FormState>();
  RecipeDraft? _d;
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _instr = TextEditingController();
  final _prep = TextEditingController();
  final _cook = TextEditingController();
  final _servings = TextEditingController(text: '1');
  final _kcal = TextEditingController();
  final _prot = TextEditingController();
  final _carb = TextEditingController();
  final _fat = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(recipeRepositoryProvider);
    final d = widget.recipeId == null
        ? RecipeDraft()
        : await repo.getDraft(widget.recipeId!) ?? RecipeDraft();
    _name.text = d.name;
    _desc.text = d.description ?? '';
    _instr.text = d.instructions;
    _prep.text = d.prepMinutes?.toString() ?? '';
    _cook.text = d.cookMinutes?.toString() ?? '';
    _servings.text = _fmt(d.servings);
    _kcal.text = _fmt(d.kcalOverride);
    _prot.text = _fmt(d.proteinOverride);
    _carb.text = _fmt(d.carbsOverride);
    _fat.text = _fmt(d.fatOverride);
    setState(() => _d = d);
  }

  @override
  void dispose() {
    for (final c in [_name, _desc, _instr, _prep, _cook, _servings, _kcal, _prot, _carb, _fat]) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncDraft() {
    final d = _d!;
    d.name = _name.text.trim();
    d.description = _desc.text.trim().isEmpty ? null : _desc.text.trim();
    d.instructions = _instr.text;
    d.prepMinutes = int.tryParse(_prep.text.trim());
    d.cookMinutes = int.tryParse(_cook.text.trim());
    d.servings = _num(_servings.text) ?? 1;
    d.kcalOverride = _num(_kcal.text);
    d.proteinOverride = _num(_prot.text);
    d.carbsOverride = _num(_carb.text);
    d.fatOverride = _num(_fat.text);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    _syncDraft();
    if (_d!.slots.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Pick at least one meal type.')));
      return;
    }
    await ref.read(recipeRepositoryProvider).save(_d!);
    if (mounted) Navigator.of(context).pop(true);
  }

  RecipeNutritionResult? _calc(List<Ingredient> all) {
    final d = _d!;
    final byId = {for (final i in all) i.id: i};
    final lines = <RecipeLine>[
      for (final l in d.lines)
        if (byId[l.ingredientId] != null)
          RecipeLine(l.quantity, l.unit, factsOf(byId[l.ingredientId]!)),
    ];
    if (lines.isEmpty) return null;
    return calculateRecipe(lines, _num(_servings.text) ?? 1);
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final cats = ref.watch(categoriesProvider).value ?? const <Category>[];
    final ings = ref.watch(ingredientsProvider).value ?? const <Ingredient>[];
    final calc = _calc(ings);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.recipeId == null ? 'New recipe' : 'Edit recipe'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              RecipeThumb(path: d.imagePath, size: 72),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.image_outlined),
                label: Text(d.imagePath == null ? 'Add image' : 'Change image'),
                onPressed: () async {
                  final path = await ImageStore.pickAndStore();
                  if (path != null) setState(() => d.imagePath = path);
                },
              ),
              if (d.imagePath != null)
                IconButton(
                    onPressed: () => setState(() => d.imagePath = null),
                    icon: const Icon(Icons.close)),
            ]),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _desc,
              decoration:
                  const InputDecoration(labelText: 'Description (optional)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _numField(_prep, 'Prep (min)', integer: true)),
              const SizedBox(width: 8),
              Expanded(child: _numField(_cook, 'Cook (min)', integer: true)),
              const SizedBox(width: 8),
              Expanded(child: _numField(_servings, 'Servings', onChanged: () => setState(() {}))),
            ]),
            const SizedBox(height: 16),
            Text('Suitable for', style: Theme.of(context).textTheme.titleSmall),
            Wrap(spacing: 8, children: [
              for (final s in MealSlot.values)
                FilterChip(
                  label: Text(s == MealSlot.marenda ? 'Marenda' : 'Lunch'),
                  selected: d.slots.contains(s),
                  onSelected: (v) => setState(() => v ? d.slots.add(s) : d.slots.remove(s)),
                ),
            ]),
            const SizedBox(height: 16),
            Text('Categories', style: Theme.of(context).textTheme.titleSmall),
            Wrap(spacing: 8, children: [
              for (final c in cats)
                FilterChip(
                  label: Text(c.name),
                  selected: d.categoryIds.contains(c.id),
                  onSelected: (v) =>
                      setState(() => v ? d.categoryIds.add(c.id) : d.categoryIds.remove(c.id)),
                ),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: Text('Ingredients', style: Theme.of(context).textTheme.titleMedium)),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.add),
                label: const Text('Add'),
                onPressed: ings.isEmpty ? null : () => _addLine(ings),
              ),
            ]),
            for (var i = 0; i < d.lines.length; i++) _lineTile(d.lines[i], ings, i),
            const SizedBox(height: 8),
            _NutritionCard(calc: calc, overrideKcal: _num(_kcal.text)),
            const SizedBox(height: 8),
            ExpansionTile(
              title: const Text('Manual nutrition override (per serving)'),
              subtitle: const Text('Leave empty to use the calculated value'),
              childrenPadding: const EdgeInsets.all(8),
              children: [
                Row(children: [
                  Expanded(child: _numField(_kcal, 'kcal', onChanged: () => setState(() {}))),
                  const SizedBox(width: 8),
                  Expanded(child: _numField(_prot, 'Protein g')),
                  const SizedBox(width: 8),
                  Expanded(child: _numField(_carb, 'Carbs g')),
                  const SizedBox(width: 8),
                  Expanded(child: _numField(_fat, 'Fat g')),
                ]),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _instr,
              minLines: 4,
              maxLines: 12,
              decoration: const InputDecoration(
                  labelText: 'Preparation instructions', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _numField(TextEditingController c, String label,
          {bool integer = false, VoidCallback? onChanged}) =>
      TextFormField(
        controller: c,
        keyboardType: TextInputType.numberWithOptions(decimal: !integer),
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        onChanged: onChanged == null ? null : (_) => onChanged(),
      );

  Widget _lineTile(DraftLine l, List<Ingredient> ings, int index) {
    final ing = ings.where((i) => i.id == l.ingredientId).firstOrNull;
    final conv = ing == null
        ? null
        : lineNutrition(l.quantity, l.unit, factsOf(ing));
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ListTile(
        title: Text(ing?.name ?? 'Unknown ingredient'),
        subtitle: Text(
            '${_fmt(l.quantity)} ${l.unit.label}'
            '${conv == null ? '  ⚠ cannot calculate' : '  ·  ${conv.kcal.round()} kcal'}',
            style: conv == null ? TextStyle(color: Theme.of(context).colorScheme.error) : null),
        onTap: () => _editLine(l, ings),
        trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => setState(() => _d!.lines.removeAt(index))),
      ),
    );
  }

  Future<void> _addLine(List<Ingredient> ings) async {
    final line = DraftLine(ingredientId: ings.first.id, quantity: 100, unit: QuantityUnit.g);
    final ok = await _editLine(line, ings, isNew: true);
    if (ok) setState(() => _d!.lines.add(line));
  }

  Future<bool> _editLine(DraftLine l, List<Ingredient> ings, {bool isNew = false}) async {
    var ingId = l.ingredientId;
    var unit = l.unit;
    final qty = TextEditingController(text: _fmt(l.quantity));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(isNew ? 'Add ingredient' : 'Edit ingredient'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownMenu<int>(
              initialSelection: ingId,
              expandedInsets: EdgeInsets.zero,
              enableFilter: true,
              requestFocusOnTap: true,
              label: const Text('Ingredient'),
              dropdownMenuEntries: [
                for (final i in ings) DropdownMenuEntry(value: i.id, label: i.name)
              ],
              onSelected: (v) {
                if (v != null) {
                  ingId = v;
                  // Default the unit to the ingredient's natural unit.
                  final b = ings.firstWhere((i) => i.id == v).baseUnit;
                  setS(() => unit = switch (b) {
                        BaseUnit.gram => QuantityUnit.g,
                        BaseUnit.milliliter => QuantityUnit.ml,
                        BaseUnit.piece => QuantityUnit.piece,
                      });
                }
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
                items: [
                  for (final u in QuantityUnit.values)
                    DropdownMenuItem(value: u, child: Text(u.label))
                ],
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
        l.ingredientId = ingId;
        l.unit = unit;
        l.quantity = _num(qty.text) ?? l.quantity;
      });
      return true;
    }
    return false;
  }
}

class _NutritionCard extends StatelessWidget {
  const _NutritionCard({required this.calc, this.overrideKcal});
  final RecipeNutritionResult? calc;
  final double? overrideKcal;

  @override
  Widget build(BuildContext context) {
    final c = calc;
    if (c == null) {
      return const Card(
          child: Padding(
              padding: EdgeInsets.all(12),
              child: Text('Add ingredients to calculate nutrition.')));
    }
    final n = c.perServing;
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Calculated per serving', style: Theme.of(context).textTheme.titleSmall),
          Text('${n.kcal.round()} kcal · P ${n.protein.toStringAsFixed(1)} g · '
              'C ${n.carbs.toStringAsFixed(1)} g · F ${n.fat.toStringAsFixed(1)} g'),
          if (c.isIncomplete)
            Text(
                '${c.incompleteLines} of ${c.lineCount} ingredients are missing data '
                '(nutrition or unit conversion), so this is partial.',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (overrideKcal != null) Text('Overridden: ${overrideKcal!.round()} kcal'),
        ]),
      ),
    );
  }
}
