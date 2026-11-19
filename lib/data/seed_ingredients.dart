import 'package:drift/drift.dart' show Value;

import 'db/database.dart';

/// Approximate common values (editable in the app). Per 100 g, per 100 ml for
/// liquids, as noted. (name, kcal, protein, carbs, fat, base, gramsPerPiece, gramsPerMl)
const _g = BaseUnit.gram;
const _ml = BaseUnit.milliliter;

final List<IngredientsCompanion> seedIngredients = [
  for (final r in const [
    ('Chicken breast', 120.0, 22.5, 0.0, 2.6, _g, null, null),
    ('Beef mince', 215.0, 18.0, 0.0, 15.0, _g, null, null),
    ('Pork loin', 143.0, 21.0, 0.0, 6.0, _g, null, null),
    ('Salmon', 208.0, 20.0, 0.0, 13.0, _g, null, null),
    ('Cod', 82.0, 18.0, 0.0, 0.7, _g, null, null),
    ('Squid', 92.0, 15.6, 3.1, 1.4, _g, null, null),
    ('Shrimp', 85.0, 20.0, 0.0, 0.5, _g, null, null),
    ('Egg', 143.0, 12.6, 0.7, 9.5, _g, 55.0, null),
    ('Pasta (dry)', 350.0, 12.0, 72.0, 1.5, _g, null, null),
    ('Rice (dry)', 360.0, 7.0, 79.0, 0.6, _g, null, null),
    ('Potato', 77.0, 2.0, 17.0, 0.1, _g, 150.0, null),
    ('Tomato', 18.0, 0.9, 3.9, 0.2, _g, 120.0, null),
    ('Onion', 40.0, 1.1, 9.3, 0.1, _g, 110.0, null),
    ('Carrot', 41.0, 0.9, 9.6, 0.2, _g, 70.0, null),
    ('Zucchini', 17.0, 1.2, 3.1, 0.3, _g, 200.0, null),
    ('Spinach', 23.0, 2.9, 3.6, 0.4, _g, null, null),
    ('Mushrooms', 22.0, 3.1, 3.3, 0.3, _g, null, null),
    ('Bell pepper', 31.0, 1.0, 6.0, 0.3, _g, 150.0, null),
    ('Garlic', 149.0, 6.4, 33.0, 0.5, _g, 4.0, null),
    ('Olive oil', 810.0, 0.0, 0.0, 91.0, _ml, null, 0.91),
    ('Butter', 717.0, 0.9, 0.1, 81.0, _g, null, null),
    ('Milk (whole)', 62.0, 3.2, 4.8, 3.4, _ml, null, 1.03),
    ('Parmesan', 392.0, 36.0, 3.2, 26.0, _g, null, null),
    ('Mozzarella', 280.0, 28.0, 3.0, 17.0, _g, null, null),
    ('Bread', 265.0, 9.0, 49.0, 3.2, _g, 30.0, null),
    ('Flour', 364.0, 10.0, 76.0, 1.0, _g, null, null),
    ('Lentils (dry)', 353.0, 25.0, 60.0, 1.1, _g, null, null),
    ('Chickpeas (canned)', 139.0, 7.0, 20.0, 2.6, _g, null, null),
    ('Tomato passata', 32.0, 1.4, 5.6, 0.2, _ml, null, 1.05),
    ('Sugar', 400.0, 0.0, 100.0, 0.0, _g, null, null),
    ('Banana', 89.0, 1.1, 23.0, 0.3, _g, 120.0, null),
    ('Apple', 52.0, 0.3, 14.0, 0.2, _g, 180.0, null),
  ])
    IngredientsCompanion.insert(
      name: r.$1,
      baseUnit: r.$6,
      kcal: Value(r.$2),
      protein: Value(r.$3),
      carbs: Value(r.$4),
      fat: Value(r.$5),
      gramsPerPiece: Value(r.$7),
      gramsPerMl: Value(r.$8),
    ),
];


