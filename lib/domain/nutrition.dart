import 'units.dart';

/// Absolute nutrition amounts (kcal, grams of macros).
class Nutrition {
  const Nutrition({this.kcal = 0, this.protein = 0, this.carbs = 0, this.fat = 0});
  final double kcal, protein, carbs, fat;

  static const zero = Nutrition();

  Nutrition operator +(Nutrition o) => Nutrition(
      kcal: kcal + o.kcal,
      protein: protein + o.protein,
      carbs: carbs + o.carbs,
      fat: fat + o.fat);

  Nutrition scale(double f) => Nutrition(
      kcal: kcal * f, protein: protein * f, carbs: carbs * f, fat: fat * f);

  @override
  String toString() => 'Nutrition($kcal kcal, P$protein C$carbs F$fat)';
}

/// Nutrition facts for one ingredient, per 100 g / 100 ml / 1 piece (see [base]).
class IngredientFacts {
  const IngredientFacts({
    required this.base,
    this.kcal,
    this.protein,
    this.carbs,
    this.fat,
    this.gramsPerPiece,
    this.gramsPerMl,
  });
  final BaseUnit base;
  final double? kcal, protein, carbs, fat;
  final double? gramsPerPiece, gramsPerMl;

  bool get hasNutrition => kcal != null;
}

/// Converts [qty] of [unit] to the ingredient's base unit amount.
/// Returns null when the conversion needs data that is missing. Never assumes
/// 1 ml == 1 g or a default weight for a piece.
double? convertToBase(double qty, QuantityUnit unit, IngredientFacts f) {
  // Normalise to one of g / ml / piece first.
  late double amount;
  late BaseUnit from;
  switch (unit) {
    case QuantityUnit.g:
      amount = qty;
      from = BaseUnit.gram;
    case QuantityUnit.kg:
      amount = qty * 1000;
      from = BaseUnit.gram;
    case QuantityUnit.ml:
      amount = qty;
      from = BaseUnit.milliliter;
    case QuantityUnit.l:
      amount = qty * 1000;
      from = BaseUnit.milliliter;
    case QuantityUnit.piece:
      amount = qty;
      from = BaseUnit.piece;
  }
  if (from == f.base) return amount;

  // Go via grams.
  double? grams;
  switch (from) {
    case BaseUnit.gram:
      grams = amount;
    case BaseUnit.milliliter:
      grams = f.gramsPerMl == null ? null : amount * f.gramsPerMl!;
    case BaseUnit.piece:
      grams = f.gramsPerPiece == null ? null : amount * f.gramsPerPiece!;
  }
  if (grams == null) return null;

  switch (f.base) {
    case BaseUnit.gram:
      return grams;
    case BaseUnit.milliliter:
      return f.gramsPerMl == null || f.gramsPerMl == 0 ? null : grams / f.gramsPerMl!;
    case BaseUnit.piece:
      return f.gramsPerPiece == null || f.gramsPerPiece == 0
          ? null
          : grams / f.gramsPerPiece!;
  }
}

/// Nutrition for [qty] [unit] of an ingredient, or null if it cannot be computed.
Nutrition? lineNutrition(double qty, QuantityUnit unit, IngredientFacts f) {
  if (!f.hasNutrition) return null;
  final base = convertToBase(qty, unit, f);
  if (base == null) return null;
  final factor = f.base == BaseUnit.piece ? base : base / 100;
  return Nutrition(
    kcal: (f.kcal ?? 0) * factor,
    protein: (f.protein ?? 0) * factor,
    carbs: (f.carbs ?? 0) * factor,
    fat: (f.fat ?? 0) * factor,
  );
}

class RecipeLine {
  const RecipeLine(this.quantity, this.unit, this.facts);
  final double quantity;
  final QuantityUnit unit;
  final IngredientFacts facts;
}

class RecipeNutritionResult {
  const RecipeNutritionResult({
    required this.total,
    required this.perServing,
    required this.incompleteLines,
    required this.lineCount,
  });
  final Nutrition total;
  final Nutrition perServing;

  /// Number of ingredient lines that could not be included.
  final int incompleteLines;
  final int lineCount;

  bool get isIncomplete => incompleteLines > 0;
  bool get hasData => lineCount > incompleteLines;
}

/// Calculates recipe nutrition from ingredient lines.
RecipeNutritionResult calculateRecipe(List<RecipeLine> lines, double servings) {
  var total = Nutrition.zero;
  var missing = 0;
  for (final l in lines) {
    final n = lineNutrition(l.quantity, l.unit, l.facts);
    if (n == null) {
      missing++;
    } else {
      total = total + n;
    }
  }
  final s = servings <= 0 ? 1.0 : servings;
  return RecipeNutritionResult(
    total: total,
    perServing: total.scale(1 / s),
    incompleteLines: missing,
    lineCount: lines.length,
  );
}

/// Manual per-serving overrides; each null field falls back to the calculated value.
Nutrition applyOverrides(Nutrition calculated,
    {double? kcal, double? protein, double? carbs, double? fat}) {
  return Nutrition(
    kcal: kcal ?? calculated.kcal,
    protein: protein ?? calculated.protein,
    carbs: carbs ?? calculated.carbs,
    fat: fat ?? calculated.fat,
  );
}
