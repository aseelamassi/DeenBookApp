import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deenbook/core/session.dart';
import 'package:deenbook/features/catalog.dart';
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
    await (FontLoader('Money')
          ..addFont(rootBundle.load('assets/fonts/Money.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
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

  testWidgets('supplier has invoice and payment but no statement', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final calls = <String>[];
    final session = (await t.runAsync(() => fakeSession(
      populated: true,
      override: (r) {
        calls.add(r.path);
        return null;
      },
    )))!;

    await t.pumpWidget(wrap(session, const Scaffold(
      body: SafeArea(child: CatalogScreen(mode: 'suppliers')),
    )));
    await t.pumpAndSettle();
    expect(find.text('فاتورة'), findsOneWidget);
    expect(find.text('دفعة'), findsOneWidget);
    expect(find.text('كشف الحساب'), findsNothing);

    await t.ensureVisible(find.text('شركة النور للتوريد'));
    await t.tap(find.text('شركة النور للتوريد'));
    await t.pumpAndSettle();

    expect(find.text('بيانات المورد'), findsOneWidget);
    expect(find.text('فاتورة'), findsOneWidget);
    expect(find.text('دفعة'), findsOneWidget);
    expect(find.text('كشف الحساب'), findsNothing);
    expect(calls.where((p) => p.endsWith('/statement')), isEmpty);
    expect(t.takeException(), isNull);
  });

  testWidgets('supplier payment does not show customer receipt prompt', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final session = (await t.runAsync(() => fakeSession()))!;
    await t.pumpWidget(wrap(
      session,
      TransactionScreen(kind: 'Payment', party: party(supplier: true), supplier: true),
    ));
    await t.pumpAndSettle();
    expect(find.text('فتح مسودة إيصال عبر واتساب بعد الحفظ'), findsNothing);
    expect(find.text('دفعة للمورد'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
