import 'package:flutter_test/flutter_test.dart';
import 'package:deenbook/core/weight_pricing.dart';

void main() {
  test('250g of cheese at 28 NIS/kg is 7 NIS', () {
    expect(totalForGrams(2800, 250), 700);
  });
  test('500g of cheese at 28 NIS/kg is 14 NIS', () {
    expect(totalForGrams(2800, 500), 1400);
  });
  test('10 NIS nuts at 40 NIS/kg is exactly 250g', () {
    expect(gramsForAmount(4000, 1000), 250);
    expect(totalForGrams(4000, 250), 1000);
  });
  test('10 NIS cheese at 28 NIS/kg is 357g and rounds to 10 NIS', () {
    final grams = gramsForAmount(2800, 1000);
    expect(grams, 357);
    expect(totalForGrams(2800, grams), 1000);
  });
  test('20 NIS cheese at 28 NIS/kg rounds to 714g = 19.99 NIS', () {
    final grams = gramsForAmount(2800, 2000);
    expect(grams, 714);
    expect(totalForGrams(2800, grams), 1999);
  });
  test('guard against invalid price or amount', () {
    expect(gramsForAmount(0, 1000), 0);
    expect(totalForGrams(2800, 0), 0);
  });
  test('legacy kg products remain weighted', () {
    expect(soldByWeight({'unit': 'كغم'}), true);
    expect(soldByWeight({'unit': 'قطعة', 'pricingMode': 'Piece'}), false);
    expect(soldByWeight({'unit': 'كغم', 'pricingMode': 'Weight'}), true);
  });
}
