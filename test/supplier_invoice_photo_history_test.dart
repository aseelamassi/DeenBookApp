import 'package:deenbook/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> movement({
  String kind = 'Purchase',
  bool? hasInvoicePhoto,
  String? invoicePhotoBase64,
}) => {
  'id': 'invoice-1',
  'kind': kind,
  'amount': 42.0,
  'discount': 0,
  'paidNow': 0,
  'method': 'Cash',
  'occurredAt': '2026-11-21T10:00:00Z',
  'items': <dynamic>[],
  if (hasInvoicePhoto != null) 'hasInvoicePhoto': hasInvoicePhoto,
  if (invoicePhotoBase64 != null) 'invoicePhotoBase64': invoicePhotoBase64,
};

void main() {
  test('TC-37: synced photo appears in the generic movement list', () {
    expect(supplierInvoiceHasPhoto(movement(hasInvoicePhoto: true)), isTrue);
  });

  test('TC-37: offline photo attached to a queued movement is visible', () {
    expect(supplierInvoiceHasPhoto(movement(invoicePhotoBase64: 'ZmFrZQ==')), isTrue);
  });

  test('TC-37: no attachment is shown for no-photo invoices or other movements', () {
    expect(supplierInvoiceHasPhoto(movement()), isFalse);
    expect(supplierInvoiceHasPhoto(movement(hasInvoicePhoto: false)), isFalse);
    expect(supplierInvoiceHasPhoto(movement(kind: 'Debt', hasInvoicePhoto: true)), isFalse);
  });

  testWidgets('TC-37: an invoice photo badge appears even when supplier=false', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(
        child: entryTile(movement(hasInvoicePhoto: true)),
      )),
    ));
    expect(find.byKey(const Key('supplier-invoice-photo-action')), findsOneWidget);
    expect(find.text('عرض صورة الفاتورة الورقية'), findsOneWidget);
  });

  testWidgets('TC-37: no badge for invoices without a picture', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: entryTile(movement())),
    ));
    expect(find.byKey(const Key('supplier-invoice-photo-action')), findsNothing);
  });

  testWidgets('TC-37: a locally saved photo opens a fullscreen zoom viewer', (tester) async {
    // Valid one-pixel PNG, used only to exercise the local-image route.
    final encoded = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+XkWQAAAAASUVORK5CYII=';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(
        child: entryTile(movement(invoicePhotoBase64: encoded)),
      )),
    ));
    await tester.tap(find.byKey(const Key('supplier-invoice-photo-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('supplier-invoice-photo-fullscreen')), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('صورة الفاتورة الورقية'), findsOneWidget);
  });
}
