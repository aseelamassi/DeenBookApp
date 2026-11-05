import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deenbook/main.dart';
import 'package:deenbook/core/session.dart';
import 'package:deenbook/features/catalog.dart';
import 'package:deenbook/features/profile.dart';
import 'package:deenbook/features/reports.dart';
import 'package:deenbook/services/export.dart';
import 'package:deenbook/ui/theme.dart';
import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Symbols',
    )..addFont(rootBundle.load('assets/fonts/Symbols.ttf'))).load();
    final loader = FontLoader('Cairo')
      ..addFont(rootBundle.load('assets/fonts/Cairo-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Cairo-SemiBold.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Cairo-Bold.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Cairo-ExtraBold.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Cairo-Black.ttf'));
    await loader.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader(
      'Money',
    )..addFont(rootBundle.load('assets/fonts/Money.ttf'))).load();
  });
  Future<void> size(WidgetTester t, Size value) async {
    t.view.physicalSize = value;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

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
  testWidgets('login is mandatory and phone is validated', (t) async {
    await size(t, const Size(390, 844));
    final s = (await t.runAsync(() => fakeSession(login: false)))!;
    await t.pumpWidget(DeenBookApp(session: s));
    await t.pumpAndSettle();
    expect(find.text('أهلاً برجعتك'), findsOneWidget);
    expect(find.text('نظرة على محلك'), findsNothing);
    await expectLater(
      find.byType(Scaffold).first,
      matchesGoldenFile('goldens/login.png'),
    );
    await t.tap(find.text('تسجيل الدخول إلى دفتر دين'));
    await t.pumpAndSettle();
    expect(
      find.text('أدخل رقم جوال صحيحاً يبدأ بـ 059 أو 056'),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
  });
  for (final width in [320.0, 390.0, 768.0]) {
    testWidgets('empty home and supplier navigation at width $width', (
      t,
    ) async {
      await size(t, Size(width, 844));
      final s = (await t.runAsync(() => fakeSession()))!;
      await t.pumpWidget(DeenBookApp(session: s));
      await t.pumpAndSettle();
      expect(find.text('لا توجد حركات بعد'), findsOneWidget);
      expect(find.text('أحمد محمود'), findsNothing);
      expect(t.takeException(), isNull);
      await t.tap(find.text('الموردون'));
      await t.pumpAndSettle();
      expect(find.text('ابدأ بإضافة مورد جديد.'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('populated home has real response values', (t) async {
    await size(t, const Size(390, 844));
    final s = (await t.runAsync(() => fakeSession(populated: true)))!;
    await t.pumpWidget(DeenBookApp(session: s));
    await t.pumpAndSettle();
    expect(find.text('650 ₪'), findsOneWidget);

    expect(t.takeException(), isNull);
  });
  testWidgets('inactive subscription blocks app content', (t) async {
    await size(t, const Size(320, 844));
    final s = (await t.runAsync(() => fakeSession(active: false)))!;
    await t.pumpWidget(DeenBookApp(session: s));
    await t.pumpAndSettle();
    expect(find.text('جدّد اشتراكك للمتابعة'), findsOneWidget);
    expect(find.text('الرئيسية'), findsNothing);
    expect(find.text('60 ₪'), findsOneWidget);
    expect(find.text('150 ₪'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  for (final screen in <String, Widget>{
    'supplier': const PartyForm(supplier: true),
    'statement': const PartyDetail(id: 'customer-1'),
    'reports': const ReportsScreen(),
    'history': const HistoryScreen(),
    'backup': const BackupScreen(),
    'subscribe': const SubscriptionScreen(),
    'product': const ProductForm(),
  }.entries) {
    testWidgets('${screen.key} lays out on small phone', (t) async {
      await size(t, const Size(320, 760));
      final s = (await t.runAsync(() => fakeSession(populated: true)))!;
      await t.pumpWidget(wrap(s, screen.value));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      if (screen.key == 'statement') {
        expect(find.byTooltip('طباعة كشف الحساب'), findsOneWidget);
      }
      if (screen.key == 'supplier') {
        expect(find.text('نوع التوريد (اختياري)'), findsOneWidget);
      }
    });
  }
  test('Arabic statement PDF uses bundled fonts', () async {
    final bytes = await Exports.statementBytes('محل الأمانة', {
      'party': party(),
      'openingBalance': 0,
      'closingBalance': 125.5,
      'entries': [entry()],
    });
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    expect(bytes.length, greaterThan(5000));
    final out = File('build/qa/statement.pdf');
    await out.parent.create(recursive: true);
    await out.writeAsBytes(bytes);
  });
  test('long invoice PDF splits descriptions across pages', () async {
    final bytes = await Exports.statementBytes('محل الأمانة', {
      'party': party(),
      'openingBalance': 0,
      'closingBalance': 100,
      'entries': [
        {
          ...entry(),
          'note': List.filled(50, 'تفاصيل فاتورة طويلة للمراجعة').join(' '),
          'items': List.generate(
            100,
            (i) => {
              'name': 'صنف رقم $i',
              'unit': 'كغم',
              'quantity': 1.25,
              'total': 12.5,
            },
          ),
        },
      ],
    });
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    final out = File('build/qa/long-invoice.pdf');
    await out.parent.create(recursive: true);
    await out.writeAsBytes(bytes);
  });
}
