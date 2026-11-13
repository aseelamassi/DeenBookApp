import 'package:flutter_test/flutter_test.dart';
import 'package:deenbook/core/ledger.dart';
import 'package:deenbook/core/format.dart';

void main() {
  test('wholesale invoice uses an unlinked product ID without changing the line', () {
    const line = InvoiceLine(
      id: 'local-only-id',
      name: 'كرتونة زيت',
      unit: 'كرتونة',
      price: 27000,
      quantity: 1000,
    );
    final supplierPayload = line.toSupplierInvoiceJson();
    expect(supplierPayload['productId'], '00000000-0000-0000-0000-000000000000');
    expect(supplierPayload['name'], 'كرتونة زيت');
    expect(supplierPayload['quantity'], 1);
    expect(supplierPayload['unitPrice'], 270);
    expect(supplierPayload['total'], 270);
    expect(line.toJson()['productId'], 'local-only-id');

    // When recovering drafts, distinct invoice-only lines need distinct local
    // editor keys even though neither is connected to a catalog product.
    final restored1 = InvoiceLine.fromJson(supplierPayload);
    final restored2 = InvoiceLine.fromJson(supplierPayload);
    expect(restored1.id, isNot(restored2.id));
    expect(restored1.total, 27000);
  });

  test('negative opening balance is customer credit, not debt', () {
    expect(customerBalanceStatus(-20), 'له رصيد');
    expect(customerBalanceStatus(0), 'خالص');
    expect(customerBalanceStatus(33), 'عليه دين');
  });
}
