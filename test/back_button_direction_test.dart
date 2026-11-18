import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:deenbook/ui/design.dart';

void main() {
  testWidgets('Arabic BrandHeader uses RTL-aware back arrow and returns', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: BrandHeader(back: true)),
                ),
              ),
              child: const Text('فتح صفحة استعادة الحساب'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('فتح صفحة استعادة الحساب'));
    await tester.pumpAndSettle();

    final backIcon = find.byType(BackButtonIcon);
    expect(backIcon, findsOneWidget);
    expect(Directionality.of(tester.element(backIcon)), TextDirection.rtl);
    expect(find.byIcon(Icons.chevron_right), findsNothing);

    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    expect(find.text('فتح صفحة استعادة الحساب'), findsOneWidget);
  });
}
