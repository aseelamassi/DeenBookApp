import 'package:flutter_test/flutter_test.dart';
import 'package:deenbook/core/ledger.dart';

void main() {
  test('supplier line sums with three-decimal quantities', () {
    final line = InvoiceLine(
      id: 'example-product',
      name: 'صنف تجريبي',
      unit: 'كغم',
      price: 250,
      quantity: 1500,
    );
    expect(line.total, 375);
    expect(line.withQuantity(2000).total, 500);
  });

  test('carton packs keep the historical price as a snapshot', () {
    const unitPriceInCents = 125;
    const packsInCarton = 12;
    final box = InvoiceLine(
      id: 'example-product',
      name: 'صنف تجريبي',
      unit: 'قطعة',
      price: unitPriceInCents,
      quantity: 1000,
    ).withUnit('كرتونة').withPrice(unitPriceInCents * packsInCarton);
    expect(box.total, 1500);
    expect(box.withQuantity(2000).total, 3000);
    expect(box.toJson()['unitPrice'], 15.0);
    expect(box.toJson()['unit'], 'كرتونة');
  });
}
