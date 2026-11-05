import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deenbook/core/session.dart';
import 'package:deenbook/main.dart';
import 'package:deenbook/features/auth.dart';
import 'package:deenbook/features/catalog.dart';
import 'package:deenbook/features/profile.dart';
import 'package:deenbook/features/reports.dart';
import 'package:deenbook/features/transaction.dart';
import 'package:deenbook/features/sync_center.dart';
import 'package:deenbook/ui/theme.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
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
      'Symbols',
    )..addFont(rootBundle.load('assets/fonts/Symbols.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  void viewport(WidgetTester t, double w) {
    t.view.physicalSize = Size(w, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  Future<Session> fixture() => fakeSession(
    populated: true,
    override: (r) {
      if (r.path == '/api/products') {
        return response(
          page([
            {
              'id': 'p1',
              'name': 'حليب طازج',
              'unit': 'لتر',
              'salePrice': 6.5,
              'purchasePrice': 5,
              'category': 'ألبان',
            },
            {
              'id': 'p2',
              'name': 'أرز بسمتي',
              'unit': 'كغم',
              'salePrice': 12,
              'purchasePrice': 10,
              'category': 'مواد تموينية',
            },
            {
              'id': 'p3',
              'name': 'خبز عربي',
              'unit': 'ربطة',
              'salePrice': 4,
              'purchasePrice': 3,
              'category': 'مخبوزات',
            },
          ]),
        );
      }
      if (r.path == '/api/products/categories') {
        return response({
          'items': ['ألبان', 'مواد تموينية', 'مخبوزات'],
        });
      }
      if (r.path == '/api/transactions') {
        return response({
          ...page([entry()]),
          'overview': {
            'invoices': 125.5,
            'received': 0,
            'paid': 0,
            'pendingCount': 0,
          },
        });
      }
      return null;
    },
  );
  Widget wrap(
    Session s,
    Widget screen, {
    double scale = 1,
    bool route = true,
  }) => Scope(
    session: s,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      initialRoute: route ? '/preview' : '/',
      routes: {
        '/': (_) => route ? const Scaffold() : screen,
        '/preview': (_) => screen,
      },
    ),
  );
  final screens = <String, Widget>{
    'login': const LoginScreen(),
    'registration': const AccountHelp(),
    'customers': const Scaffold(
      body: SafeArea(child: CatalogScreen(mode: 'customers')),
    ),
    'suppliers': const Scaffold(
      body: SafeArea(child: CatalogScreen(mode: 'suppliers')),
    ),
    'products': const Scaffold(
      body: SafeArea(child: CatalogScreen(mode: 'products')),
    ),
    'debt': TransactionScreen(party: party()),
    'payment': TransactionScreen(kind: 'Payment', party: party()),
    'customer-form': const PartyForm(supplier: false),
    'supplier-form': const PartyForm(supplier: true),
    'product-form': const ProductForm(),
    'statement': const PartyDetail(id: 'customer-1'),
    'history': const HistoryScreen(),
    'subscription': const SubscriptionScreen(),
    'workers': const WorkersScreen(),
    'settings': const SettingsScreen(),
    'backup': const BackupScreen(),
    'sync': const SyncCenterScreen(),
  };
  for (final w in [390.0, 320.0]) {
    for (final e in screens.entries) {
      testWidgets('${e.key} reference layout $w', (t) async {
        viewport(t, w);
        final s = (await t.runAsync(fixture))!;
        await t.pumpWidget(
          wrap(
            s,
            e.value,
            route: ![
              'login',
              'customers',
              'suppliers',
              'products',
            ].contains(e.key),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        if (w == 390) {
          await expectLater(
            find.byType(Scaffold).last,
            matchesGoldenFile('goldens/gemini-${e.key}.png'),
          );
        }
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
      });
    }
  }
  testWidgets('home drawer and quick actions', (t) async {
    viewport(t, 390);
    final s = (await t.runAsync(fixture))!;
    await t.pumpWidget(DeenBookApp(session: s));
    await t.pumpAndSettle();
    await expectLater(
      find.byType(Scaffold).first,
      matchesGoldenFile('goldens/gemini-home.png'),
    );
    await t.tap(find.byTooltip('البروفايل'));
    await t.pumpAndSettle();
    await expectLater(
      find.byType(Scaffold).first,
      matchesGoldenFile('goldens/gemini-drawer.png'),
    );
    Navigator.of(t.element(find.byType(Drawer))).pop();
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('إضافة حركة'));
    await t.pumpAndSettle();
    await expectLater(
      find.byType(Navigator).first,
      matchesGoldenFile('goldens/gemini-quick.png'),
    );
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  });
  testWidgets('long shop name and larger text on narrow phone', (t) async {
    viewport(t, 320);
    final s = (await t.runAsync(fixture))!;
    s.settings = {
      ...?s.settings,
      'name': 'محل المواد الغذائية والتموينية والمنتجات الطازجة',
      'ownerName': 'صاحب المحل والموظف المسؤول عن الحسابات',
    };
    for (final e in [
      const SettingsScreen(),
      const SubscriptionScreen(),
      const HistoryScreen(),
    ]) {
      await t.pumpWidget(wrap(s, e, scale: 1.3));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    }
    await t.pumpWidget(DeenBookApp(session: s));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('البروفايل'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  });

  testWidgets(
    'registration shows a reviewed request and never claims automatic activation',
    (t) async {
      viewport(t, 390);
      final s = (await t.runAsync(fixture))!;
      await t.pumpWidget(wrap(s, const AccountHelp()));
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextFormField, 'اسم صاحب المحل'),
        'مالك الاختبار',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'اسم المحل'),
        'محل الاختبار',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'رقم الجوال'),
        '0599000001',
      );
      t.testTextInput.hide();
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('متابعة ←'));
      await t.tap(find.text('متابعة ←'));
      await t.pumpAndSettle();
      await expectLater(
        find.byType(Scaffold).last,
        matchesGoldenFile('goldens/gemini-registration-plans.png'),
      );
      await t.tap(find.text('شهر واحد'));
      await t.ensureVisible(find.text('متابعة ←'));
      await t.tap(find.text('متابعة ←'));
      await t.pumpAndSettle();
      expect(find.text('شهر واحد · 60 ₪'), findsOneWidget);
      await t.ensureVisible(find.text('عرض طلب الاشتراك'));
      await t.tap(find.text('عرض طلب الاشتراك'));
      await t.pumpAndSettle();
      expect(find.text('لم يُرسل الطلب'), findsOneWidget);
      expect(find.textContaining('بقيمة 60 شيكل'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('transaction stays usable with a keyboard and a large balance', (
    t,
  ) async {
    viewport(t, 320);
    final s = (await t.runAsync(fixture))!;
    await t.pumpWidget(
      wrap(
        s,
        TransactionScreen(
          party: {
            ...party(),
            'name': 'حساب باسم طويل جداً لاختبار التفاف النص في البطاقة',
            'balance': 999999999.99,
          },
        ),
        scale: 1.3,
      ),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    t.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(t.view.resetViewInsets);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    final button = find.text('تأكيد وحفظ المشتريات في دفتر دين ✓');
    expect(t.getBottomRight(button).dy, lessThanOrEqualTo(564));
  });
}
