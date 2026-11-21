import 'package:deenbook/core/weight_entry_validation.dart';
import 'package:deenbook/core/ledger.dart';
import 'package:deenbook/core/session.dart';
import 'package:deenbook/features/catalog.dart';
import 'package:deenbook/features/invoice_items.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

WeightEntryResult weightInput(String text, {bool inKilos = false}) =>
    validateWeightEntry(
      pricePerKgCents: 2800,
      byAmount: false,
      inKilos: inKilos,
      weightText: text,
      amountText: '',
    );

WeightEntryResult amountInput(String text, {int price = 2800}) =>
    validateWeightEntry(
      pricePerKgCents: price,
      byAmount: true,
      inKilos: false,
      weightText: '',
      amountText: text,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('TC-56: amount and weight are bounded without exceptions', () {
    expect(weightInput('0').canSubmit, false);
    expect(weightInput('abc').grams, 0);
    expect(weightInput('9999999999999999999999').canSubmit, false);
    expect(weightInput('9999999999999999999999').error, contains('الحد الأقصى'));
    expect(weightInput('100000').canSubmit, true);
    expect(weightInput('100001').canSubmit, false);
    expect(weightInput('100').canSubmit, true);
    expect(weightInput('100.001', inKilos: true).canSubmit, false);
    expect(weightInput('100', inKilos: true).canSubmit, true);
    expect(weightInput('٠٫٥', inKilos: true).grams, 500);
    expect(amountInput('0').canSubmit, false);
    expect(amountInput('نص').grams, 0);
    expect(amountInput('999999999999999999999').canSubmit, false);
    expect(amountInput('10001').canSubmit, false);
    expect(amountInput('10000', price: 10000).canSubmit, true);
    expect(amountInput('10').grams, 357);
    expect(amountInput('10').totalCents, 1000);
    expect(amountInput('10', price: 0).canSubmit, false);
    expect(amountInput('0').totalCents, 0);
    expect(amountInput('0').grams, 0);
  });

  testWidgets('TC-55: empty new prices, reject zero, accept sale with blank optional cost', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    var sent = 0;
    Map<String, dynamic>? payload;
    final session = (await t.runAsync(() => fakeSession(override: (r) {
      if (r.path == '/api/products' && r.method == 'POST') {
        sent++;
        payload = Map<String, dynamic>.from(r.data);
        return response({'id': 'product-test'});
      }
      return null;
    })))!;
    await t.pumpWidget(Scope(
      session: session,
      child: const MaterialApp(home: ProductForm()),
    ));
    await t.pumpAndSettle();
    final priceField = find.widgetWithText(TextFormField, 'سعر القطعة / العبوة (₪)');
    expect(t.widget<TextFormField>(priceField).controller!.text, '');
    await t.enterText(find.widgetWithText(TextFormField, 'اسم الصنف'), 'كيس أرز');
    await t.enterText(priceField, '0');
    await t.ensureVisible(find.text('حفظ الصنف'));
    await t.pumpAndSettle();
    await t.tap(find.text('حفظ الصنف'));
    await t.pumpAndSettle();
    expect(sent, 0);
    expect(find.text('أدخل سعر بيع أكبر من صفر'), findsOneWidget);
    await t.ensureVisible(priceField);
    await t.enterText(priceField, '28');
    await t.ensureVisible(find.text('حفظ الصنف'));
    await t.pumpAndSettle();
    await t.tap(find.text('حفظ الصنف'));
    await t.pumpAndSettle();
    expect(sent, 1);
    expect(payload!['salePrice'], 28);
    expect(payload!['purchasePrice'], 0);
    expect(t.takeException(), isNull);
  });

  testWidgets('TC-56: huge weight cannot be accepted in calculator', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    const line = InvoiceLine(id: 'p', name: 'جبنة', unit: 'كغم', price: 2800, quantity: 1000);
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: WeightCalculatorDialog(line: line))));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'الوزن بالغرام'), '99999999999');
    await t.pumpAndSettle();
    expect(find.textContaining('الوزن كبير جدًا'), findsOneWidget);
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'إضافة للفاتورة')).onPressed, isNull);
    expect(find.textContaining('0 غرام'), findsWidgets);
    await t.tap(find.text('أدخل المبلغ'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'مبلغ آخر (₪)'), '99999999999');
    await t.pumpAndSettle();
    expect(find.textContaining('المبلغ كبير جدًا'), findsOneWidget);
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'إضافة للفاتورة')).onPressed, isNull);
    expect(t.takeException(), isNull);
  });
}
