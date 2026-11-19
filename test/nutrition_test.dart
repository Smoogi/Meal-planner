import 'package:flutter_test/flutter_test.dart';
import 'package:meal_planner/domain/nutrition.dart';
import 'package:meal_planner/domain/units.dart';

void main() {
  const rice = IngredientFacts(
      base: BaseUnit.gram, kcal: 360, protein: 7, carbs: 79, fat: 0.6);
  const oil = IngredientFacts(
      base: BaseUnit.milliliter, kcal: 810, fat: 91, gramsPerMl: 0.91);
  const egg = IngredientFacts(
      base: BaseUnit.gram, kcal: 143, protein: 12.6, gramsPerPiece: 55);
  const noData = IngredientFacts(base: BaseUnit.gram);

  test('grams and kilograms', () {
    expect(lineNutrition(200, QuantityUnit.g, rice)!.kcal, closeTo(720, 1e-9));
    expect(lineNutrition(0.2, QuantityUnit.kg, rice)!.kcal, closeTo(720, 1e-9));
  });

  test('ml to g needs density; never assumed', () {
    const water = IngredientFacts(base: BaseUnit.gram, kcal: 100);
    expect(convertToBase(100, QuantityUnit.ml, water), isNull);
    expect(convertToBase(100, QuantityUnit.ml, const IngredientFacts(base: BaseUnit.gram, kcal: 1, gramsPerMl: 1.03)),
        closeTo(103, 1e-9));
  });

  test('liquid ingredient in litres and in grams', () {
    expect(lineNutrition(1, QuantityUnit.l, oil)!.kcal, closeTo(8100, 1e-9));
    // 91 g of oil = 100 ml
    expect(lineNutrition(91, QuantityUnit.g, oil)!.kcal, closeTo(810, 1e-9));
  });

  test('pieces use the ingredient weight, not a global default', () {
    expect(lineNutrition(2, QuantityUnit.piece, egg)!.kcal, closeTo(143 * 1.1, 1e-9));
    expect(convertToBase(2, QuantityUnit.piece, rice), isNull);
  });

  test('piece-based ingredient', () {
    const bar = IngredientFacts(base: BaseUnit.piece, kcal: 200, gramsPerPiece: 40);
    expect(lineNutrition(3, QuantityUnit.piece, bar)!.kcal, 600);
    expect(lineNutrition(80, QuantityUnit.g, bar)!.kcal, closeTo(400, 1e-9));
  });

  test('Bolognese: 2800 kcal / 4 servings = 700; 1.5 servings = 1050', () {
    const big = IngredientFacts(base: BaseUnit.gram, kcal: 280);
    final r = calculateRecipe([RecipeLine(1000, QuantityUnit.g, big)], 4);
    expect(r.total.kcal, closeTo(2800, 1e-9));
    expect(r.perServing.kcal, closeTo(700, 1e-9));
    expect(r.perServing.scale(1.5).kcal, closeTo(1050, 1e-9));
  });

  test('incomplete data is flagged but recipe stays usable', () {
    final r = calculateRecipe([
      RecipeLine(100, QuantityUnit.g, rice),
      RecipeLine(100, QuantityUnit.g, noData),
      RecipeLine(2, QuantityUnit.piece, rice),
    ], 2);
    expect(r.isIncomplete, isTrue);
    expect(r.incompleteLines, 2);
    expect(r.hasData, isTrue);
    expect(r.perServing.kcal, closeTo(180, 1e-9));
  });

  test('manual overrides apply per field', () {
    final n = applyOverrides(const Nutrition(kcal: 500, protein: 20), kcal: 650);
    expect(n.kcal, 650);
    expect(n.protein, 20);
  });
}
