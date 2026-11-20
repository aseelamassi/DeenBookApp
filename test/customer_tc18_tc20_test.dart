import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deenbook/core/api.dart';
import 'package:deenbook/core/session.dart';
import 'package:deenbook/features/catalog.dart';
import 'package:deenbook/ui/credit_limit.dart';
import 'package:deenbook/ui/theme.dart';
import 'package:deenbook/ui/widgets.dart';
import 'support/fakes.dart';

void main() {
  Widget wrap(Session session) => Scope(
    session: session,
    child: MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: appTheme(),
      home: const Scaffold(body: CatalogScreen(mode: 'customers')),
    ),
  );

  Future<Session> sessionWithNearLimit() => fakeSession(
    override: (request) {
      if (request.path == '/api/customers') {
        return response(page([
          {
            ...party(),
            'balance': 420,
            'creditLimit': 500,
          },
        ]));
      }
      if (request.path == '/api/customers/overview') {
        return response({
          'total': 1, 'outstanding': 420, 'owing': 1,
          'credit': 0, 'settled': 0, 'scheduled': 0,
          'nearCreditLimit': 1,
        });
      }
      return null;
    },
  );

  testWidgets('TC-18 warning is shown once and border surrounds entire card',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = (await tester.runAsync(sessionWithNearLimit))!;
    await tester.pumpWidget(wrap(session));
    await tester.pumpAndSettle();

    expect(find.text('اقترب من السقف 🔴'), findsOneWidget);
    final accountSurface = tester.widget<Surface>(
      find.ancestor(
        of: find.text('أحمد محمود'),
        matching: find.byType(Surface),
      ).first,
    );
    expect(accountSurface.borderColor, creditRose);
    expect(accountSurface.borderWidth, 2);
    expect(find.text('عليه دين'), findsOneWidget);
    expect(find.text('تسجيل دين'), findsOneWidget);
    expect(find.text('قبض دفعة'), findsOneWidget);
    expect(find.text('كشف الحساب'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TC-20 tapping the search field again places caret after last char',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = (await tester.runAsync(sessionWithNearLimit))!;
    await tester.pumpWidget(wrap(session));
    await tester.pumpAndSettle();

    final search = find.byKey(const Key('catalog-search'));
    await tester.enterText(search, 'محمد');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    tester.testTextInput.hide();
    await tester.pump();
    final controller = tester.widget<TextField>(search).controller!;
    controller.selection = TextSelection.collapsed(offset: controller.text.length - 1);

    await tester.tap(search);
    await tester.pump();
    expect(controller.selection.baseOffset, controller.text.length);
    expect(controller.text, 'محمد');
    expect(tester.takeException(), isNull);
  });
}
