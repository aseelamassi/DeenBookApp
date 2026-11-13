import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deenbook/core/session.dart';
import 'package:deenbook/features/catalog.dart';
import 'package:deenbook/ui/design.dart';
import 'package:deenbook/ui/theme.dart';
import 'package:deenbook/ui/widgets.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final entry in <({String name, Widget form, String field, String save})>[
    (
      name: 'إضافة زبون',
      form: const PartyForm(supplier: false),
      field: 'الاسم',
      save: 'حفظ الزبون',
    ),
    (
      name: 'إضافة مورد',
      form: const PartyForm(supplier: true),
      field: 'الاسم',
      save: 'حفظ المورد',
    ),
    (
      name: 'إضافة صنف',
      form: const ProductForm(),
      field: 'اسم الصنف',
      save: 'حفظ الصنف',
    ),
  ]) {
    testWidgets('keyboard keeps ${entry.name} usable and scrollable', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);

      final session = (await tester.runAsync(() => fakeSession()))!;
      await tester.pumpWidget(
        Scope(
          session: session,
          child: MaterialApp(
            theme: appTheme(),
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => open(context, entry.form),
                    child: const Text('افتح النموذج'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('افتح النموذج'));
      await tester.pumpAndSettle();

      final nameField = find.widgetWithText(TextFormField, entry.field);
      expect(nameField, findsOneWidget);
      await tester.tap(nameField);
      await tester.enterText(nameField, 'تجربة الإدخال');
      tester.view.viewInsets = const FakeViewPadding(bottom: 330);
      await tester.pumpAndSettle();

      final sheet = find.descendant(
        of: find.byType(FormSheetScaffold),
        matching: find.byType(Scaffold),
      );
      expect(sheet, findsOneWidget);
      final viewportBottom = tester.view.physicalSize.height - 330;
      // The nested Scaffold must not consume the keyboard inset a second time.
      expect(tester.getBottomRight(sheet).dy, lessThanOrEqualTo(viewportBottom + 1));
      expect(tester.getSize(sheet).height, greaterThan(350));
      expect(tester.widget<TextFormField>(nameField).controller!.text,
          'تجربة الإدخال');
      expect(tester.getBottomRight(nameField).dy, lessThanOrEqualTo(viewportBottom + 1));

      // Remaining fields and save action remain accessible via the form list.
      final save = find.text(entry.save);
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      expect(tester.getBottomRight(save).dy, lessThanOrEqualTo(viewportBottom + 1));
      expect(tester.takeException(), isNull);
    });
  }
}
