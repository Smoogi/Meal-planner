import '../units.dart';

/// A recipe as seen by the planner (no database types).
class PlannerRecipe {
  const PlannerRecipe({
    required this.id,
    required this.name,
    required this.slots,
    this.categoryIds = const {},
    this.isFavorite = false,
    this.servings = 1,
  });
  final int id;
  final String name;
  final Set<MealSlot> slots;
  final Set<int> categoryIds;
  final bool isFavorite;

  /// Portions one cooking yields (used for multi-day cooking).
  final double servings;
}

class PlannerConfig {
  const PlannerConfig({
    required this.start,
    required this.end,
    this.cooldownDays = 14,
    this.favoriteWeight = 2.0,
    this.discoveryWeight = 1.0,
    this.maxConsecutiveDays = 2,
    this.multiDayChance = 0.25,
    this.multiDayMaxDays = 2,
    this.leftoversOnOfficeDays = false,
    this.leftoverMaxAgeDays = 3,
    this.categoryTargetsPerWeek = const {},
    this.weekStartsOn = DateTime.monday,
  });

  /// Inclusive local dates.
  final DateTime start, end;

  /// Minimum days between two cookings of the same recipe (soft).
  final int cooldownDays;

  /// Multiplier (>= 1) applied to favorite recipes.
  final double favoriteWeight;

  /// 0 = off. Strength of the bonus for recipes not cooked for a long time.
  final double discoveryWeight;

  /// Most consecutive days the same recipe may appear.
  final int maxConsecutiveDays;

  /// Probability that a freshly chosen recipe is cooked for several days.
  final double multiDayChance;

  /// Total days one cooking feeds (cooking day included).
  final int multiDayMaxDays;
  final bool leftoversOnOfficeDays;
  final int leftoverMaxAgeDays;

  /// categoryId -> desired meals per week (soft).
  final Map<int, int> categoryTargetsPerWeek;
  final int weekStartsOn;
}

/// An entry that must stay as it is (locked, or already prepared/consumed/skipped).
class FixedMeal {
  const FixedMeal({
    required this.date,
    required this.slot,
    this.recipeId,
    this.isLeftover = false,
  });
  final DateTime date;
  final MealSlot slot;
  final int? recipeId;
  final bool isLeftover;
}

/// A cooked batch that still has portions available.
class OpenBatch {
  const OpenBatch({
    required this.batchId,
    required this.recipeId,
    required this.cookedOn,
    required this.remaining,
  });
  final int batchId;
  final int recipeId;
  final DateTime cookedOn;
  final int remaining;
}

class PlannerInput {
  const PlannerInput({
    required this.recipes,
    required this.config,
    required this.dayTypes,
    this.fixed = const [],
    this.lastCooked = const {},
    this.openBatches = const [],
    this.categoryNames = const {},
  });
  final Map<int, String> categoryNames;
  final List<PlannerRecipe> recipes;
  final PlannerConfig config;

  /// Day type for every date key in range.
  final Map<String, DayType> dayTypes;

  /// Fixed meals in the range, plus context shortly before it (for
  /// consecutive-day and weekly-balance checks).
  final List<FixedMeal> fixed;

  /// Last date each recipe was actually cooked (leftovers excluded).
  final Map<int, DateTime> lastCooked;
  final List<OpenBatch> openBatches;
}

class PlannedMeal {
  const PlannedMeal({
    required this.date,
    required this.slot,
    required this.recipeId,
    this.isLeftover = false,
    this.cookingKey,
    this.existingBatchId,
  });
  final DateTime date;
  final MealSlot slot;
  final int recipeId;
  final bool isLeftover;

  /// Groups a cooking and its planned leftovers (new batch). Null = single day.
  final int? cookingKey;

  /// Leftover taken from an already existing batch.
  final int? existingBatchId;
}

enum PlanNoteKind { noRecipes, noSuitableRecipe, cooldownRelaxed, repeatRelaxed, categoryShortfall, info }

class PlanNote {
  const PlanNote(this.kind, this.message, {this.date, this.slot});
  final PlanNoteKind kind;
  final String message;
  final DateTime? date;
  final MealSlot? slot;

  @override
  String toString() => message;
}

class PlanResult {
  const PlanResult(this.meals, this.notes);
  final List<PlannedMeal> meals;
  final List<PlanNote> notes;

  /// True when every preference was met without relaxing anything.
  bool get fullySatisfied => notes.isEmpty;
}

