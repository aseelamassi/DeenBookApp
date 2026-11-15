// Weight quantities are stored as thousandths of a kilogram (one gram).
// Amounts are in agorot (1/100 NIS). No floating-point totals.
int totalForGrams(int pricePerKgCents, int grams) {
  if (pricePerKgCents <= 0 || grams <= 0) return 0;
  return (pricePerKgCents * grams + 500) ~/ 1000;
}

int gramsForAmount(int pricePerKgCents, int targetCents) {
  if (pricePerKgCents <= 0 || targetCents <= 0) return 0;
  return (targetCents * 1000 / pricePerKgCents).round();
}

String weightLabel(int grams) {
  if (grams == 250) return 'ربع كيلو (250 غرام)';
  if (grams == 500) return 'نصف كيلو (500 غرام)';
  if (grams == 1000) return 'كيلو (1000 غرام)';
  return '$grams غرام';
}

bool soldByWeight(Map<String, dynamic> product) {
  final mode = '${product['pricingMode'] ?? ''}';
  return mode == 'Weight' ||
      (mode.isEmpty && ['كغم', 'كيلو', 'kg'].contains('${product['unit']}'));
}
