import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_planner/data/db/database.dart';
import 'package:meal_planner/data/meal_repository.dart';
import 'package:meal_planner/data/recipe_repository.dart';
import 'package:meal_planner/domain/schedule.dart';

void main() {
  late AppDatabase db;
  late RecipeRepository recipes;
  late MealRepository meals;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    recipes = RecipeRepository(db);
    meals = MealRepository(db, recipes);
  });
  tearDown(() => db.close());

  Future<int> bolognese() => recipes.save(RecipeDraft(name: 'Bolognese', servings: 4, kcalOverride: 700));

  group('schedule', () {
    test('slots per day type', () {
      expect(slotsFor(DayType.wfh), [MealSlot.marenda, MealSlot.lunch]);
      expect(slotsFor(DayType.free), [MealSlot.marenda, MealSlot.lunch]);
      expect(slotsFor(DayType.office), [MealSlot.lunch]);
    });

    test('override wins and never changes the weekly default', () async {
      final tue = DateTime(2026, 11, 24); // Tuesday
      expect(tue.weekday, DateTime.tuesday);
      var weekly = await meals.getWeekly();
      expect(effectiveDayType(tue, weekly, await meals.getOverrideTypes()), DayType.office);

      await meals.setDayTypeOverride(dateKey(tue), DayType.wfh);
      weekly = await meals.getWeekly();
      expect(effectiveDayType(tue, weekly, await meals.getOverrideTypes()), DayType.wfh);
      expect(weekly[DateTime.tuesday], DayType.office); // unchanged
      // another Tuesday is unaffected
      final nextTue = tue.add(const Duration(days: 7));
      expect(effectiveDayType(nextTue, weekly, await meals.getOverrideTypes()), DayType.office);

      await meals.setDayTypeOverride(dateKey(tue), null);
      expect(effectiveDayType(tue, weekly, await meals.getOverrideTypes()), DayType.office);
    });

    test('note survives clearing the override and vice versa', () async {
      await meals.setDayTypeOverride('2026-12-01', DayType.free);
      await meals.setDayNote('2026-12-01', 'Birthday');
      await meals.setDayTypeOverride('2026-12-01', null);
      expect((await db.select(db.dayOverrides).get()).single.note, 'Birthday');
      await meals.setDayNote('2026-12-01', '');
      expect(await db.select(db.dayOverrides).get(), isEmpty);
    });

    test('date helpers are DST safe', () {
      expect(dateKey(addDays(DateTime(2026, 3, 28), 2)), '2026-03-30');
      expect(daysBetween(DateTime(2026, 10, 24), DateTime(2026, 10, 26)), 2);
    });
  });

  group('entries', () {
    test('planned meals do not count as consumed; snapshot taken on consume', () async {
      final r = await bolognese();
      final id = await meals.addRecipeEntry(date: '2026-11-20', slot: MealSlot.lunch, recipeId: r, servings: 1.5);
      var e = (await meals.getEntry(id))!;
      expect(e.state, MealState.planned);
      expect(e.kcal, closeTo(1050, 1e-9));

      await meals.setState(id, MealState.consumed);
      e = (await meals.getEntry(id))!;
      expect(e.state, MealState.consumed);
      expect(e.kcal, closeTo(1050, 1e-9));
    });

    test('later recipe edits never change a consumed entry', () async {
      final r = await bolognese();
      final id = await meals.addRecipeEntry(date: '2026-11-20', slot: MealSlot.lunch, recipeId: r);
      await meals.setState(id, MealState.consumed);
      final d = (await recipes.getDraft(r))!..kcalOverride = 900..name = 'Bolognese v2';
      await recipes.save(d);
      final e = (await meals.getEntry(id))!;
      expect(e.kcal, 700);
      expect(e.title, 'Bolognese');
      await recipes.delete(r);
      final after = (await meals.getEntry(id))!;
      expect(after.recipeId, isNull);
      expect(after.kcal, 700);
    });

    test('changing servings of a consumed entry scales its snapshot', () async {
      final r = await bolognese();
      final id = await meals.addRecipeEntry(date: '2026-11-20', slot: MealSlot.lunch, recipeId: r);
      await meals.setState(id, MealState.consumed);
      await meals.setServings(id, 2);
      expect((await meals.getEntry(id))!.kcal, 1400);
    });

    test('external meal needs no recipe', () async {
      final id = await meals.addExternalEntry(
          date: '2026-11-21', slot: MealSlot.lunch, title: 'Chicken with rice', kcal: 750);
      final e = (await meals.getEntry(id))!;
      expect(e.kind, EntryKind.external);
      expect(e.recipeId, isNull);
      expect(e.kcal, 750);
      expect(e.state, MealState.consumed);
    });

    test('consuming a fresh recipe entry records one batch; leftovers do not', () async {
      final r = await bolognese();
      final wed = await meals.addRecipeEntry(date: '2026-11-18', slot: MealSlot.lunch, recipeId: r);
      await meals.setState(wed, MealState.consumed);
      final batch = (await meals.getEntry(wed))!.batchId!;
      expect((await db.select(db.prepBatches).get()).length, 1);
      expect(await meals.remainingPortions(batch), 3);

      final thu = await meals.addRecipeEntry(
          date: '2026-11-19', slot: MealSlot.lunch, recipeId: r, batchId: batch, isLeftover: true);
      await meals.setState(thu, MealState.consumed);
      expect((await db.select(db.prepBatches).get()).length, 1); // still one cooking
      expect(await meals.remainingPortions(batch), 2);

      final item = (await recipes.loadAll()).single;
      expect(item.prepCount, 1);
      expect(item.lastPrepared, '2026-11-18');
    });

    test('replacing a recipe resets to planned and drops the batch link', () async {
      final r1 = await bolognese();
      final r2 = await recipes.save(RecipeDraft(name: 'Soup', kcalOverride: 300));
      final id = await meals.addRecipeEntry(date: '2026-11-20', slot: MealSlot.lunch, recipeId: r1);
      await meals.setState(id, MealState.consumed);
      await meals.replaceRecipe(id, r2);
      final e = (await meals.getEntry(id))!;
      expect(e.recipeId, r2);
      expect(e.state, MealState.planned);
      expect(e.batchId, isNull);
      expect(e.kcal, 300);
    });

    test('locking a whole day', () async {
      final r = await bolognese();
      await meals.addRecipeEntry(date: '2026-11-20', slot: MealSlot.lunch, recipeId: r);
      await meals.addRecipeEntry(date: '2026-11-20', slot: MealSlot.marenda, recipeId: r);
      await meals.addRecipeEntry(date: '2026-11-21', slot: MealSlot.lunch, recipeId: r);
      await meals.setDayLocked('2026-11-20', true);
      final all = await db.select(db.mealEntries).get();
      expect(all.where((e) => e.locked).length, 2);
      expect(all.firstWhere((e) => e.date == '2026-11-21').locked, isFalse);
    });

    test('unused Value import guard', () {
      expect(const Value(1).value, 1);
    });
  });
}
