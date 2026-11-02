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
    await (FontLoader('Cairo')
          ..addFont(rootBundle.load('assets/fonts/Cairo-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Cairo-Bold.ttf')))
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
    await t.tap(find.text(label));
    await t.pumpAndSettle();
  }

  Future<void> enter(WidgetTester t, String label, String value) =>
      t.enterText(find.widgetWithText(TextFormField, label), value);
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
      await tap(t, 'نقداً');
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
      await tap(t, 'حفظ الحركة');
      expect(sent!['pendingConfirmation'], isTrue);
      expect(sent!['method'], 'Bank');
      expect(sent!['reference'], '');
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'invoice discount and optional retained cash produce one request',
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
      await enter(t, 'الخصم — شيكل', '10');
      await enter(t, 'المدفوع الآن — شيكل', '90');
      await t.pumpAndSettle();
      await enter(t, 'المبلغ المسلّم نقداً (اختياري)', '100');
      await tap(t, 'احتساب الباقي رصيداً للزبون');
      await tap(t, 'حفظ الحركة');
      expect(sent!['amount'], 100);
      expect(sent!['discount'], 10);
      expect(sent!['paidNow'], 100);
      expect(sent!['operationId'], isNotEmpty);
      expect(t.takeException(), isNull);
    },
  );
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
    await tap(t, 'ترتيب حسب: الأعلى رصيداً');
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
    await tap(t, 'حفظ الحركة');
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
