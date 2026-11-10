import 'package:deenbook/core/ledger.dart';
import 'package:deenbook/core/supplier_invoice_note.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invoice note includes carton price, calculated individual cost and number', () {
    final lines = [
      const InvoiceLine(
        id: 'carton', name: 'زيت', unit: 'كرتونة', price: 12000,
        quantity: 2000,
      ),
    ];
    final note = supplierInvoiceDescription(
      invoiceNumber: '814', lines: lines, packCounts: {'carton': 12},
    );
    expect(note, contains('814'));
    expect(note, contains('2 كرتونة زيت'));
    expect(note, contains('120.00'));
    expect(note, contains('10.00'));
    expect(note, contains('240.00'));
  });

  test('invoice notes are bounded with detailed item snapshots preserved separately', () {
    final lines = List.generate(100, (i) => InvoiceLine(
      id: '$i', name: List.filled(3, 'اسم صنف طويل متكرر رقم $i').join(''),
      unit: 'قطعة', price: 100, quantity: 1000,
    ));
    final note = supplierInvoiceDescription(
      invoiceNumber: '', lines: lines, packCounts: {},
    );
    expect(note.length, lessThanOrEqualTo(2000));
    expect(note, contains('تفاصيله محفوظة'));
  });
}
