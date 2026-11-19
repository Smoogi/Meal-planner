import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';

double? _num(String s) => double.tryParse(s.trim().replaceAll(',', '.'));
String _fmt(double? v) =>
    v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());

class IngredientsScreen extends ConsumerStatefulWidget {
  const IngredientsScreen({super.key});

  @override
  ConsumerState<IngredientsScreen> createState() => _IngredientsScreenState();
}

class _IngredientsScreenState extends ConsumerState<IngredientsScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(ingredientsProvider).value ?? const <Ingredient>[];
    final items = all.where((i) => i.name.toLowerCase().contains(_q)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Ingredients')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showIngredientEditor(context, ref),
        child: const Icon(Icons.add),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SearchBar(
            hintText: 'Search ingredients',
            leading: const Icon(Icons.search),
            onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, i) {
              final ing = items[i];
              final per = switch (ing.baseUnit) {
                BaseUnit.gram => '100 g',
                BaseUnit.milliliter => '100 ml',
                BaseUnit.piece => '1 piece',
              };
              return ListTile(
                title: Text(ing.name),
                subtitle: Text(ing.kcal == null
                    ? 'No nutrition data'
                    : '${_fmt(ing.kcal)} kcal per $per · P ${_fmt(ing.protein)} C ${_fmt(ing.carbs)} F ${_fmt(ing.fat)}'),
                onTap: () => showIngredientEditor(context, ref, existing: ing),
              );
            },
          ),
        ),
      ]),
    );
  }
}

Future<void> showIngredientEditor(BuildContext context, WidgetRef ref, {Ingredient? existing}) async {
  final repo = ref.read(recipeRepositoryProvider);
  final name = TextEditingController(text: existing?.name ?? '');
  final kcal = TextEditingController(text: _fmt(existing?.kcal));
  final prot = TextEditingController(text: _fmt(existing?.protein));
  final carb = TextEditingController(text: _fmt(existing?.carbs));
  final fat = TextEditingController(text: _fmt(existing?.fat));
  final gpp = TextEditingController(text: _fmt(existing?.gramsPerPiece));
  final gpm = TextEditingController(text: _fmt(existing?.gramsPerMl));
  var base = existing?.baseUnit ?? BaseUnit.gram;

  Widget field(TextEditingController c, String l) => Expanded(
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: l, border: const OutlineInputBorder()),
        ),
      );

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(existing == null ? 'New ingredient' : 'Edit ingredient'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 8),
            SegmentedButton<BaseUnit>(
              segments: const [
                ButtonSegment(value: BaseUnit.gram, label: Text('per 100 g')),
                ButtonSegment(value: BaseUnit.milliliter, label: Text('per 100 ml')),
                ButtonSegment(value: BaseUnit.piece, label: Text('per piece')),
              ],
              selected: {base},
              onSelectionChanged: (s) => setS(() => base = s.first),
            ),
            const SizedBox(height: 8),
            Row(children: [field(kcal, 'kcal'), const SizedBox(width: 6), field(prot, 'Protein')]),
            const SizedBox(height: 8),
            Row(children: [field(carb, 'Carbs'), const SizedBox(width: 6), field(fat, 'Fat')]),
            const SizedBox(height: 8),
            Row(children: [
              field(gpp, 'g per piece'),
              const SizedBox(width: 6),
              field(gpm, 'g per ml'),
            ]),
            const SizedBox(height: 4),
            const Text(
              'Weight per piece and density are only needed to convert between units.',
              style: TextStyle(fontSize: 12),
            ),
          ]),
        ),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () async {
                final ok = await repo.deleteIngredient(existing.id);
                if (ctx.mounted) Navigator.pop(ctx);
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Ingredient is used by a recipe.')));
                }
              },
              child: const Text('Delete'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              try {
                await repo.saveIngredient(
                  IngredientsCompanion(
                    name: Value(name.text.trim()),
                    baseUnit: Value(base),
                    kcal: Value(_num(kcal.text)),
                    protein: Value(_num(prot.text)),
                    carbs: Value(_num(carb.text)),
                    fat: Value(_num(fat.text)),
                    gramsPerPiece: Value(_num(gpp.text)),
                    gramsPerMl: Value(_num(gpm.text)),
                  ),
                  id: existing?.id,
                );
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (_) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('An ingredient with that name exists.')));
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
