import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deenbook/core/api.dart';
import 'package:deenbook/core/ledger.dart';
import 'package:deenbook/core/session.dart';
import 'package:deenbook/features/catalog.dart';
import 'package:deenbook/features/invoice_items.dart';
import 'package:deenbook/features/transaction.dart';
import 'package:deenbook/ui/theme.dart';
import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Symbols',
    )..addFont(rootBundle.load('assets/fonts/Symbols.ttf'))).load();
    await (FontLoader('Cairo')
          ..addFont(rootBundle.load('assets/fonts/Cairo-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Cairo-SemiBold.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Cairo-Bold.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Cairo-ExtraBold.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Cairo-Black.ttf')))
        .load();
    await (FontLoader(
      'Money',
    )..addFont(rootBundle.load('assets/fonts/Money.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  Widget wrap(Session s, Widget child) => Scope(
    session: s,
    child: MaterialApp(
      theme: appTheme(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: child,
    ),
  );
  void size(WidgetTester t, [double width = 390]) {
    t.view.physicalSize = Size(width, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  Future<void> tap(WidgetTester t, String label) async {
    t.testTextInput.hide();
    await t.pumpAndSettle();
    await t.ensureVisible(find.text(label));
    await t.pumpAndSettle();
    if (label.startsWith('تأكيد وحفظ')) {
      await t.runAsync(() async {
        await t.tap(find.text(label));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
    } else {
      await t.tap(find.text(label));
    }
    await t.pumpAndSettle();
  }

  Future<void> enter(WidgetTester t, String label, String value) => t.enterText(
    label == 'المبلغ — شيكل'
        ? find.byKey(const Key('transaction-amount'))
        : find.widgetWithText(TextFormField, label),
    value,
  );
  testWidgets('customer credit and secondary contact save with explicit sign', (
    t,
  ) async {
    size(t);
    Json? sent;
    final s = (await t.runAsync(
      () => fakeSession(
        override: (r) {
          if (r.path == '/api/customers' && r.method == 'POST') {
            sent = Map<String, dynamic>.from(r.data);
            return response(party());
          }
          return null;
        },
      ),
    ))!;
    await t.pumpWidget(wrap(s, const PartyForm(supplier: false)));
    await t.pumpAndSettle();
    await enter(t, 'الاسم', 'خالد أحمد');
    await enter(t, 'رقم إضافي (اختياري)', '0569000000');
    await enter(t, 'صاحب الرقم / صلة القرابة (اختياري)', 'الأخ');
    await tap(t, 'رصيد للزبون');
    await enter(t, 'الرصيد الافتتاحي — شيكل', '25.50');
    await tap(t, 'حفظ الزبون');
    expect(sent!['openingBalance'], -25.5);
    expect(sent!['alternateContact'], 'الأخ');
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'pending transfer saves explicit flag and receipt sharing is opt in',
    (t) async {
      size(t);
      Json? sent;
      final s = (await t.runAsync(
        () => fakeSession(
          override: (r) {
            if (r.path == '/api/transactions' && r.method == 'POST') {
              sent = Map<String, dynamic>.from(r.data);
              return response({
                ...entry(),
                ...sent!,
                'pendingConfirmation': true,
              });
            }
            return null;
          },
        ),
      ))!;
      await t.pumpWidget(
        wrap(s, TransactionScreen(kind: 'Payment', party: party())),
      );
      await t.pumpAndSettle();
      await enter(t, 'المبلغ — شيكل', '100');
      await tap(t, 'تحويل بنكي');
      await tap(t, 'الحوالة لم تصل بعد');
      expect(find.text('الرصيد يبقى كما هو حتى وصول الحوالة'), findsOneWidget);
      final share = t.widget<CheckboxListTile>(
        find.widgetWithText(
          CheckboxListTile,
          'فتح مسودة إيصال عبر واتساب بعد الحفظ',
        ),
      );
      expect(share.value, isFalse);
      await tap(t, 'تأكيد وحفظ الدفعة في دفتر دين ✓');
      expect(sent!['pendingConfirmation'], isTrue);
      expect(sent!['method'], 'Bank');
      expect(sent!['reference'], '');
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'customer debt optional payment has no discount or invoice number',
    (t) async {
      size(t);
      Json? sent;
      final s = (await t.runAsync(
        () => fakeSession(
          override: (r) {
            if (r.path == '/api/transactions' && r.method == 'POST') {
              sent = Map<String, dynamic>.from(r.data);
              return response({...entry(), ...sent!});
            }
            return null;
          },
        ),
      ))!;
      await t.pumpWidget(wrap(s, TransactionScreen(party: party())));
      await t.pumpAndSettle();
      await enter(t, 'المبلغ — شيكل', '100');
      await tap(t, 'دفعة مع المشتريات (اختياري)');
      expect(find.text('الخصم — شيكل'), findsNothing);
      expect(find.text('رقم الفاتورة (اختياري)'), findsNothing);
      expect(
        t.widget<TextFormField>(
          find.byKey(const Key('customer-debt-paid-now')),
        ).controller!.text,
        isEmpty,
      );
      await t.enterText(find.byKey(const Key('customer-debt-paid-now')), '90');
      await t.pumpAndSettle();
      await tap(t, 'حاسبة الفكّة السريعة (تسجيل الباقي رصيد)');
      await enter(t, 'المبلغ المسلّم نقداً (اختياري)', '100');
      await tap(t, 'احتساب الباقي رصيداً للزبون');
      await tap(t, 'تأكيد وحفظ المشتريات في دفتر دين ✓');
      expect(sent!['amount'], 100);
      expect(sent!['discount'], 0);
      expect(sent!['invoiceNumber'], isNull);
      expect(sent!['paidNow'], 100);
      expect(sent!['operationId'], isNotEmpty);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('customer debt saves without a payment when optional input is empty', (t) async {
    size(t);
    Json? sent;
    final s = (await t.runAsync(
      () => fakeSession(
        override: (r) {
          if (r.path == '/api/transactions' && r.method == 'POST') {
            sent = Map<String, dynamic>.from(r.data);
            return response({...entry(), ...sent!});
          }
          return null;
        },
      ),
    ))!;
    await t.pumpWidget(wrap(s, TransactionScreen(party: party())));
    await t.pumpAndSettle();
    await enter(t, 'المبلغ — شيكل', '100');
    await tap(t, 'دفعة مع المشتريات (اختياري)');
    expect(
      t.widget<TextFormField>(find.byKey(const Key('customer-debt-paid-now')))
          .controller!.text,
      isEmpty,
    );
    await tap(t, 'تأكيد وحفظ المشتريات في دفتر دين ✓');
    expect(sent!['paidNow'], 0);
    expect(sent!['discount'], 0);
    expect(sent!['invoiceNumber'], isNull);
    expect(t.takeException(), isNull);
  });
  testWidgets('supplier header filters and four sorts fit a small screen', (
    t,
  ) async {
    size(t, 320);
    String? lastSort;
    final s = (await t.runAsync(
      () => fakeSession(
        populated: true,
        override: (r) {
          if (r.path == '/api/suppliers') lastSort = r.queryParameters['sort'];
          return null;
        },
      ),
    ))!;
    await t.pumpWidget(
      wrap(
        s,
        const Scaffold(
          body: SafeArea(child: CatalogScreen(mode: 'suppliers')),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('ترتيب حسب'));
    await t.pumpAndSettle();
    expect(find.text('الأقل رصيداً'), findsOneWidget);
    await tap(t, 'آخر حركة');
    expect(lastSort, 'recent');
    await t.drag(find.byType(ListView), const Offset(0, 800));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'quantity can be calculated from an amount and shows rounded total',
    (t) async {
      size(t);
      final s = (await t.runAsync(() => fakeSession()))!;
      await t.pumpWidget(
        wrap(
          s,
          const Scaffold(
            body: QuantityDialog(
              line: InvoiceLine(
                id: 'p',
                name: 'أرز',
                unit: 'كغم',
                price: 1250,
                quantity: 1000,
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextField, 'أو احسب الكمية من مبلغ — شيكل'),
        '31.25',
      );
      await t.pumpAndSettle();
      expect(find.text('الإجمالي الفعلي: 31.25 ₪'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('debt entry records timestamp on save and shows voice in header',
      (t) async {
    size(t);
    Json? sent;
    final s = (await t.runAsync(
      () => fakeSession(
        override: (r) {
          if (r.path == '/api/transactions' && r.method == 'POST') {
            sent = Map<String, dynamic>.from(r.data);
            return response({...entry(), ...sent!});
          }
          return null;
        },
      ),
    ))!;
    await t.pumpWidget(wrap(s, TransactionScreen(party: party())));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('debt-description-microphone')),
        findsOneWidget);
    expect(find.byTooltip('تغيير التاريخ'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'إملاء وصف الحركة'),
        findsNothing);
    expect(find.textContaining('التاريخ والوقت تلقائيًا'), findsOneWidget);

    await enter(t, 'المبلغ — شيكل', '15');
    await t.enterText(
      find.widgetWithText(TextFormField, 'وصف الحركة (اختياري)'),
      'علبة حليب',
    );
    final before = DateTime.now().toUtc();
    await tap(t, 'تأكيد وحفظ المشتريات في دفتر دين ✓');
    final after = DateTime.now().toUtc();
    expect(sent, isNotNull);
    expect(sent!['note'], 'علبة حليب');
    final savedAt = DateTime.parse(sent!['occurredAt'] as String).toUtc();
    expect(savedAt.isBefore(before.subtract(const Duration(seconds: 2))),
        isFalse);
    expect(savedAt.isAfter(after.add(const Duration(seconds: 2))), isFalse);
    expect(t.takeException(), isNull);
  });

  testWidgets('customer payment searches in-place, saves sender and automatic time', (t) async {
    size(t);
    Json? sent;
    final s = (await t.runAsync(
      () => fakeSession(
        populated: true,
        override: (r) {
          if (r.path == '/api/transactions' && r.method == 'POST') {
            sent = Map<String, dynamic>.from(r.data);
            return response({...entry(), ...sent!});
          }
          return null;
        },
      ),
    ))!;
    await t.pumpWidget(wrap(s, const TransactionScreen(kind: 'Payment')));
    await t.pumpAndSettle();

    // The customer-only payment form contains no supplier toggle and no
    // navigation into the customer catalog to pick a customer.
    expect(find.text('زبون'), findsNothing);
    expect(find.text('مورد'), findsNothing);
    expect(find.byKey(const Key('transaction-party-search')), findsOneWidget);
    expect(find.byTooltip('تغيير التاريخ'), findsNothing);
    expect(find.byKey(const Key('payment-description-microphone')),
        findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'إملاء وصف الحركة'),
        findsNothing);
    expect(find.textContaining('التاريخ والوقت تلقائيًا'), findsOneWidget);
    expect(find.text('اسم الدافع / المستلم (اختياري):'), findsNothing);
    expect(find.byType(Navigator), findsOneWidget);

    await t.tap(find.byKey(const Key('transaction-party-search')));
    await t.pump(const Duration(milliseconds: 240));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('transaction-party-search')), 'أحمد');
    await t.pump(const Duration(milliseconds: 240));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('party-option-customer-1')));
    await t.pumpAndSettle();
    expect(find.textContaining('تم اختيار الزبون'), findsOneWidget);
    expect(find.byType(Navigator), findsOneWidget);

    await enter(t, 'المبلغ — شيكل', '25');
    await tap(t, 'تحويل بنكي');
    final sender = find.widgetWithText(
      TextFormField, 'اسم صاحب الحوالة (اختياري)');
    expect(sender, findsOneWidget);
    expect(find.text('اسم الدافع / المستلم (اختياري):'), findsNothing);
    await t.enterText(sender, 'سارة أحمد');
    await t.enterText(
      find.widgetWithText(TextFormField, 'وصف الحركة (اختياري)'),
      'دفعة من حوالة بنكية',
    );
    final before = DateTime.now().toUtc();
    await tap(t, 'تأكيد وحفظ الدفعة في دفتر دين ✓');
    final after = DateTime.now().toUtc();
    expect(sent!['partyId'], 'customer-1');
    expect(sent!['method'], 'Bank');
    expect(sent!['counterpartyName'], 'سارة أحمد');
    expect(sent!['reference'], 'سارة أحمد');
    expect(sent!['note'], 'دفعة من حوالة بنكية');
    final savedAt = DateTime.parse(sent!['occurredAt'] as String).toUtc();
    expect(savedAt.isBefore(before.subtract(const Duration(seconds: 2))), isFalse);
    expect(savedAt.isAfter(after.add(const Duration(seconds: 2))), isFalse);
    expect(t.takeException(), isNull);
  });

  testWidgets('sender input is conditional, optional, and works for both wallets', (t) async {
    size(t);
    Json? sent;
    final s = (await t.runAsync(() => fakeSession(
      override: (r) {
        if (r.path == '/api/transactions' && r.method == 'POST') {
          sent = Map<String, dynamic>.from(r.data);
          return response({...entry(), ...sent!});
        }
        return null;
      },
    )))!;
    await t.pumpWidget(wrap(s, TransactionScreen(kind: 'Payment', party: party())));
    await t.pumpAndSettle();
    expect(find.text('اسم صاحب الحوالة (اختياري)'), findsNothing);
    await enter(t, 'المبلغ — شيكل', '10');
    await tap(t, 'جوال باي');
    expect(find.widgetWithText(TextFormField, 'اسم صاحب الحوالة (اختياري)'), findsOneWidget);
    await tap(t, 'بال باي');
    expect(find.widgetWithText(TextFormField, 'اسم صاحب الحوالة (اختياري)'), findsOneWidget);
    await tap(t, 'نقداً');
    expect(find.text('اسم صاحب الحوالة (اختياري)'), findsNothing);
    await tap(t, 'بال باي');
    // The payer field is optional: saving without it must still succeed.
    await tap(t, 'تأكيد وحفظ الدفعة في دفتر دين ✓');
    expect(sent!['method'], 'PalPay');
    expect(sent!['reference'], '');
    expect(sent!['counterpartyName'], '');
    expect(t.takeException(), isNull);
  });

  testWidgets('supplier settlement remains a separate flow without the customer microphone', (t) async {
    size(t);
    final s = (await t.runAsync(() => fakeSession()))!;
    await t.pumpWidget(wrap(s, TransactionScreen(
      kind: 'Payment', supplier: true, party: party(supplier: true))));
    await t.pumpAndSettle();
    expect(find.text('سداد دفعة لمورد'), findsOneWidget);
    expect(find.byKey(const Key('payment-description-microphone')), findsNothing);
    expect(find.byTooltip('تغيير التاريخ'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('legacy API does not receive unsupported invoice fields', (
    t,
  ) async {
    size(t);
    Json? sent;
    final s = (await t.runAsync(
      () => fakeSession(
        override: (r) {
          if (r.path == '/api/capabilities') return response({}, status: 404);
          if (r.path == '/api/transactions' && r.method == 'POST') {
            sent = Map<String, dynamic>.from(r.data);
            return response(entry());
          }
          return null;
        },
      ),
    ))!;
    expect(s.ledgerV2, isFalse);
    await t.pumpWidget(wrap(s, TransactionScreen(party: party())));
    await t.pumpAndSettle();
    expect(find.text('من الأصناف'), findsNothing);
    await enter(t, 'المبلغ — شيكل', '10');
    await tap(t, 'تأكيد وحفظ المشتريات في دفتر دين ✓');
    for (final key in [
      'discount',
      'items',
      'pendingConfirmation',
      'counterpartyName',
    ]) {
      expect(sent!.containsKey(key), isFalse);
    }
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'restored modern request cannot silently post against an old API',
    (t) async {
      size(t);
      var posted = false;
      final store = MemoryStorage();
      store.values['pending.shop-1'] = jsonEncode({
        ...entry(),
        'kind': 'Payment',
        'method': 'Bank',
        'pendingConfirmation': true,
        'discount': 0,
        'items': [],
      });
      final s = (await t.runAsync(
        () => fakeSession(
          store: store,
          override: (r) {
            if (r.path == '/api/capabilities') return response({}, status: 404);
            if (r.path == '/api/transactions' && r.method == 'POST') {
              posted = true;
            }
            return null;
          },
        ),
      ))!;
      await t.pumpWidget(wrap(s, const TransactionScreen()));
      await t.pumpAndSettle();
      await tap(t, 'إعادة محاولة حفظ نفس الحركة');
      expect(posted, isFalse);
      expect(store.values['pending.shop-1'], isNotNull);
      expect(find.textContaining('يحتاج الخادم إلى التحديث'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
