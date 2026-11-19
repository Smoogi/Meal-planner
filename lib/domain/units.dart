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
