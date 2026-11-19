import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_planner/data/db/database.dart';
import 'package:meal_planner/data/recipe_repository.dart';

void main() {
  late AppDatabase db;
  late RecipeRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = RecipeRepository(db);
  });
  tearDown(() => db.close());

  Future<int> ingId(String name) async =>
      (await (db.select(db.ingredients)..where((i) => i.name.equals(name))).getSingle()).id;

  test('save, load nutrition, categories and meal types', () async {
    final cats = await db.select(db.categories).get();
    final seafood = cats.firstWhere((c) => c.name == 'Seafood').id;
    final rice = cats.firstWhere((c) => c.name == 'Rice').id;
    final id = await repo.save(RecipeDraft(
      name: 'Squid risotto',
      servings: 2,
      categoryIds: {seafood, rice},
      slots: {MealSlot.marenda, MealSlot.lunch},
      lines: [
        DraftLine(ingredientId: await ingId('Rice (dry)'), quantity: 200, unit: QuantityUnit.g),
        DraftLine(ingredientId: await ingId('Squid'), quantity: 0.3, unit: QuantityUnit.kg),
      ],
    ));
    final item = (await repo.loadAll()).single;
    expect(item.recipe.id, id);
    expect(item.categoryIds, {seafood, rice});
    expect(item.slots, {MealSlot.marenda, MealSlot.lunch});
    // (200g*3.6 + 300g*0.92) / 2
    expect(item.perServing!.kcal, closeTo((720 + 276) / 2, 0.01));
    expect(item.incomplete, isFalse);
  });

  test('manual override wins; recipe without ingredients still usable', () async {
    await repo.save(RecipeDraft(name: 'Mystery stew', kcalOverride: 640));
    final item = (await repo.loadAll()).single;
    expect(item.perServing!.kcal, 640);
  });

  test('duplicate and delete', () async {
    final id = await repo.save(RecipeDraft(name: 'Soup', isFavorite: true));
    final copy = await repo.duplicate(id);
    final all = await repo.loadAll();
    expect(all.length, 2);
    expect(all.firstWhere((r) => r.recipe.id == copy).recipe.name, 'Soup (copy)');
    await repo.delete(id);
    expect((await repo.loadAll()).length, 1);
  });

  test('used ingredient cannot be deleted; deleting category unlinks recipes', () async {
    final rice = await ingId('Rice (dry)');
    final cat = await repo.addCategory('Test');
    await repo.save(RecipeDraft(
      name: 'Plain rice',
      categoryIds: {cat},
      lines: [DraftLine(ingredientId: rice, quantity: 100, unit: QuantityUnit.g)],
    ));
    expect(await repo.deleteIngredient(rice), isFalse);
    await repo.deleteCategory(cat);
    expect((await repo.loadAll()).single.categoryIds, isEmpty);
  });
}
