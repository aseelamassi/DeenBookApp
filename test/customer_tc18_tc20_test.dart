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
    // No second red warning outline should appear inside the outer card.
    // The balance area may keep a tinted background, but not a border.
    final balanceAreas = find
        .ancestor(of: find.text('عليه دين'), matching: find.byType(Container))
        .evaluate()
        .map((element) => element.widget)
        .whereType<Container>()
        .where((container) =>
            container.decoration is BoxDecoration &&
            (container.decoration! as BoxDecoration).color == creditRosePale);
    expect(balanceAreas, isNotEmpty);
    for (final area in balanceAreas) {
      final decoration = area.decoration! as BoxDecoration;
      expect(decoration.border, isNull,
          reason: 'Only the outer customer card should have a warning border');
    }
    expect(find.text('عليه دين'), findsOneWidget);
    expect(find.text('تسجيل دين'), findsOneWidget);
    expect(find.text('قبض دفعة'), findsOneWidget);
    expect(find.text('كشف الحساب'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TC-20 reopens search at end even when Android keeps focus',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = (await tester.runAsync(sessionWithNearLimit))!;
    await tester.pumpWidget(wrap(session));
    await tester.pumpAndSettle();

    final searchField = find.byKey(const Key('catalog-search'));
    await tester.enterText(searchField, 'محمد');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(searchField);
    expect(field.onTapAlwaysCalled, isTrue,
        reason: 'Android may dismiss the keyboard without removing focus');
    final controller = field.controller!;
    final searchFocus = field.focusNode!;
    expect(searchFocus.hasFocus, isTrue);

    // Simulate Android Back: the keyboard closes while focus is retained.
    tester.testTextInput.hide();
    await tester.pump();
    expect(searchFocus.hasFocus, isTrue);
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length - 1,
    );
    await tester.tap(searchField);
    await tester.pump();
    expect(controller.selection.baseOffset, controller.text.length);

    // A second tap should also repair the selection, not just the first one.
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length - 1,
    );
    await tester.tap(searchField);
    await tester.pump();
    expect(controller.selection.baseOffset, controller.text.length);
    expect(controller.text, 'محمد');
    expect(tester.takeException(), isNull);
  });

  testWidgets('TC-20 search cursor follows focus after keyboard closes',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = (await tester.runAsync(sessionWithNearLimit))!;
    await tester.pumpWidget(wrap(session));
    await tester.pumpAndSettle();

    final searchField = find.byKey(const Key('catalog-search'));
    await tester.enterText(searchField, 'أحمد');
    final field = tester.widget<TextField>(searchField);
    final controller = field.controller!;
    final focus = field.focusNode!;

    focus.unfocus();
    await tester.pump();
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length - 1,
    );
    focus.requestFocus();
    await tester.pump();
    expect(controller.selection.baseOffset, controller.text.length);
    expect(controller.text, 'أحمد');
    expect(tester.takeException(), isNull);
  });
}
