import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deenbook/core/session.dart';
import 'package:deenbook/features/reports.dart';
import 'package:deenbook/ui/theme.dart';
import 'support/fakes.dart';

void main() {
  testWidgets('customer, supplier and payment tabs allow export confirmation with an outbox', (tester) async {
    tester.view.physicalSize = const Size(430, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final maybeSession = await tester.runAsync(() => fakeSession(
      populated: true,
      override: (RequestOptions request) {
        if (request.path == '/api/transactions') {
          return response({
            ...page([entry()]),
            'overview': {'invoices': 125.5, 'received': 0, 'paid': 0, 'pendingCount': 0},
          });
        }
        return null;
      },
    ));
    expect(maybeSession, isNotNull);
    final session = maybeSession!;
    session.pendingSync = 6;
    await tester.pumpWidget(Scope(
      session: session,
      child: MaterialApp(
        theme: appTheme(),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const HistoryScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    for (final category in ['الزبائن', 'الموردون', 'المدفوعات']) {
      await tester.ensureVisible(find.text(category).first);
      await tester.tap(find.text(category).first);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('تصدير Excel / CSV'));
      await tester.tap(find.text('تصدير Excel / CSV'));
      await tester.pumpAndSettle();
      expect(find.text('تصدير بيانات الخادم فقط'), findsOneWidget);
      expect(find.textContaining('6 حركة محفوظة على الجهاز'), findsWidgets);
      await tester.tap(find.text('إلغاء').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('مشاركة الملخص'));
      await tester.tap(find.text('مشاركة الملخص'));
      await tester.pumpAndSettle();
      expect(find.text('تصدير بيانات الخادم فقط'), findsOneWidget);
      await tester.tap(find.text('إلغاء').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('طباعة').first);
      await tester.pumpAndSettle();
      expect(find.text('تصدير بيانات الخادم فقط'), findsOneWidget);
      await tester.tap(find.text('إلغاء').last);
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });
}
