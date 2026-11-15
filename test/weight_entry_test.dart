import 'package:flutter_test/flutter_test.dart';
import 'package:deenbook/core/ledger.dart';

void main() {
  test('amount-mode purchases keep the mode flag in local drafts', () {
    const line = InvoiceLine(
      id: '11111111-1111-1111-1111-111111111111',
      name: 'جبنة بيضاء',
      unit: 'كغم',
      price: 2800,
      quantity: 714,
      byAmount: true,
    );
    expect(line.total, 1999);
    final restored = InvoiceLine.fromJson(line.toJson());
    expect(restored.byAmount, true);
    expect(restored.quantity, 714);
    expect(restored.total, 1999);
  });
  test('older ledger snapshots remain valid without a mode field', () {
    const line = InvoiceLine(
      id: '11111111-1111-1111-1111-111111111111',
      name: 'عدس',
      unit: 'كغم',
      price: 2000,
      quantity: 500,
    );
    expect(line.toJson().containsKey('byAmount'), false);
    expect(InvoiceLine.fromJson(line.toJson()).byAmount, false);
  });
}
