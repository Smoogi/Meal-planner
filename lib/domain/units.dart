/// Unit an ingredient's nutrition values refer to (per 100 g, per 100 ml, per 1 piece).
enum BaseUnit {
  gram('g'),
  milliliter('ml'),
  piece('pc');

  const BaseUnit(this.label);
  final String label;
}

/// Unit a quantity is entered in.
enum QuantityUnit {
  g('g'),
  kg('kg'),
  ml('ml'),
  l('l'),
  piece('pc');

  const QuantityUnit(this.label);
  final String label;
}

enum DayType { wfh, office, free }

enum MealSlot { marenda, lunch }

enum MealState { planned, prepared, consumed, skipped }

/// recipe = from a recipe, external = eaten elsewhere (e.g. office lunch),
/// items = built from individual ingredients.
enum EntryKind { recipe, external, items }
