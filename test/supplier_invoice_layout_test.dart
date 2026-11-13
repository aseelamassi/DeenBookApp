import 'package:deenbook/core/ledger.dart';
import 'package:deenbook/features/supplier_invoice_items.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('supplier invoice entry remains readable on a narrow RTL phone',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final lines = <InvoiceLine>[];
    final packCounts = <String, int>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, rebuild) => SingleChildScrollView(
                child: SupplierInvoiceItems(
                  lines: lines,
                  packCounts: packCounts,
                  onPackCountChanged: (id, count) => packCounts[id] = count,
                  onChanged: () => rebuild(() {}),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(lines, hasLength(1));
    final nameKey = ValueKey('supplier-name-${lines.first.id}');
    final quantityKey = ValueKey('supplier-quantity-${lines.first.id}');
    final priceKey = ValueKey('supplier-unit-price-${lines.first.id}');
    expect(find.byKey(nameKey), findsOneWidget);
    expect(find.byKey(quantityKey), findsOneWidget);
    expect(find.byKey(priceKey), findsOneWidget);
    expect(tester.getSize(find.byKey(quantityKey)).width, greaterThan(80));

    await tester.ensureVisible(find.byKey(priceKey));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(priceKey)).width, greaterThan(100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick template updates the invoice-only editable field',
      (tester) async {
    final lines = <InvoiceLine>[];
    final packCounts = <String, int>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, rebuild) => SingleChildScrollView(
                child: SupplierInvoiceItems(
                  lines: lines,
                  packCounts: packCounts,
                  onPackCountChanged: (id, count) => packCounts[id] = count,
                  onChanged: () => rebuild(() {}),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ شوال أرز 25 كجم'));
    await tester.pumpAndSettle();
    expect(lines.first.name, 'شوال أرز 25 كجم');
    final nameField = tester.widget<TextFormField>(
      find.byKey(ValueKey('supplier-name-${lines.first.id}')),
    );
    expect(nameField.controller?.text, 'شوال أرز 25 كجم');
    expect(tester.takeException(), isNull);
  });
}
