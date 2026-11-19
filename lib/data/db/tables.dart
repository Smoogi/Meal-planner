import 'package:drift/drift.dart';

/// Base unit an ingredient's nutrition values refer to.
enum BaseUnit { gram, milliliter, piece }

enum DayType { wfh, office, free }

enum MealSlot { marenda, lunch }

enum MealState { planned, prepared, consumed, skipped }

/// recipe = from a recipe, external = eaten elsewhere (e.g. office lunch),
/// items = built from individual ingredients.
enum EntryKind { recipe, external, items }

class Ingredients extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();
  IntColumn get baseUnit => intEnum<BaseUnit>()();
  // Nutrition per 100 g / 100 ml / 1 piece (depending on baseUnit).
  RealColumn get kcal => real().nullable()();
  RealColumn get protein => real().nullable()();
  RealColumn get carbs => real().nullable()();
  RealColumn get fat => real().nullable()();
  // Optional conversions; never assumed when null.
  RealColumn get gramsPerPiece => real().nullable()();
  RealColumn get gramsPerMl => real().nullable()();
}

class Recipes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get imagePath => text().nullable()(); // relative to app docs dir
  TextColumn get instructions => text().withDefault(const Constant(''))();
  IntColumn get prepMinutes => integer().nullable()();
  IntColumn get cookMinutes => integer().nullable()();
  RealColumn get servings => real().withDefault(const Constant(1))();
  // Manual per-serving overrides; null = calculate from ingredients.
  RealColumn get kcalOverride => real().nullable()();
  RealColumn get proteinOverride => real().nullable()();
  RealColumn get carbsOverride => real().nullable()();
  RealColumn get fatOverride => real().nullable()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

class RecipeIngredients extends Table {
  IntColumn get recipeId =>
      integer().references(Recipes, #id, onDelete: KeyAction.cascade)();
  IntColumn get ingredientId => integer().references(Ingredients, #id)();
  RealColumn get quantity => real()();
  IntColumn get unit => intEnum<BaseUnit>()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {recipeId, ingredientId};
}

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

class RecipeCategories extends Table {
  IntColumn get recipeId =>
      integer().references(Recipes, #id, onDelete: KeyAction.cascade)();
  IntColumn get categoryId =>
      integer().references(Categories, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {recipeId, categoryId};
}

/// "Both" = two rows (marenda + lunch).
class RecipeMealTypes extends Table {
  IntColumn get recipeId =>
      integer().references(Recipes, #id, onDelete: KeyAction.cascade)();
  IntColumn get slot => intEnum<MealSlot>()();

  @override
  Set<Column> get primaryKey => {recipeId, slot};
}

/// Default weekly schedule: weekday 1 (Mon) .. 7 (Sun).
class WeeklySchedule extends Table {
  IntColumn get weekday => integer()();
  IntColumn get dayType => intEnum<DayType>()();

  @override
  Set<Column> get primaryKey => {weekday};
}

/// Per-date override. [date] is local 'yyyy-MM-dd'.
class DayOverrides extends Table {
  TextColumn get date => text()();
  IntColumn get dayType => intEnum<DayType>().nullable()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {date};
}

/// One cooking session; leftovers are entries linked to it.
class PrepBatches extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get recipeId => integer().nullable().references(Recipes, #id,
      onDelete: KeyAction.setNull)();
  TextColumn get cookedOn => text()(); // yyyy-MM-dd
  RealColumn get portionsMade => real()();
}

/// Single source of truth for Planner, Calendar and Calories.
class MealEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get date => text()(); // yyyy-MM-dd
  IntColumn get slot => intEnum<MealSlot>()();
  IntColumn get state => intEnum<MealState>()();
  IntColumn get kind => intEnum<EntryKind>()();
  IntColumn get recipeId => integer().nullable().references(Recipes, #id,
      onDelete: KeyAction.setNull)();
  IntColumn get batchId => integer().nullable().references(PrepBatches, #id,
      onDelete: KeyAction.setNull)();
  BoolColumn get isLeftover => boolean().withDefault(const Constant(false))();
  BoolColumn get locked => boolean().withDefault(const Constant(false))();
  RealColumn get servings => real().withDefault(const Constant(1))();
  TextColumn get title => text().nullable()(); // snapshot of recipe name / free text
  // Nutrition snapshot for the whole entry (servings already applied).
  RealColumn get kcal => real().nullable()();
  RealColumn get protein => real().nullable()();
  RealColumn get carbs => real().nullable()();
  RealColumn get fat => real().nullable()();
  TextColumn get notes => text().nullable()();
}

/// Individual food items for EntryKind.items.
class MealEntryItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get entryId =>
      integer().references(MealEntries, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  RealColumn get quantity => real()();
  IntColumn get unit => intEnum<BaseUnit>()();
  RealColumn get kcal => real().nullable()();
  RealColumn get protein => real().nullable()();
  RealColumn get carbs => real().nullable()();
  RealColumn get fat => real().nullable()();
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()(); // JSON-encoded

  @override
  Set<Column> get primaryKey => {key};
}
