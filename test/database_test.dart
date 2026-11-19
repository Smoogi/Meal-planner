import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_planner/data/db/database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('seeds default categories and weekly schedule', () async {
    final cats = await db.select(db.categories).get();
    expect(cats.map((c) => c.name), AppDatabase.defaultCategories);
    final week = await (db.select(db.weeklySchedule)
          ..orderBy([(t) => OrderingTerm.asc(t.weekday)]))
        .get();
    expect(week.length, 7);
    expect(week[1].dayType, DayType.office); // Tuesday
  });

  test('deleting a recipe keeps meal entries and their snapshot', () async {
    final rid = await db.into(db.recipes).insert(
        RecipesCompanion.insert(name: 'Bolognese', servings: const Value(4)));
    await db.into(db.mealEntries).insert(MealEntriesCompanion.insert(
          date: '2026-11-20',
          slot: MealSlot.lunch,
          state: MealState.consumed,
          kind: EntryKind.recipe,
          recipeId: Value(rid),
          title: const Value('Bolognese'),
          kcal: const Value(1050),
        ));
    await (db.delete(db.recipes)..where((r) => r.id.equals(rid))).go();
    final e = await db.select(db.mealEntries).getSingle();
    expect(e.recipeId, isNull);
    expect(e.title, 'Bolognese');
    expect(e.kcal, 1050);
  });
}
