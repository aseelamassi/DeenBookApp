import 'package:deenbook/core/contact_phone.dart';
import 'package:deenbook/core/session.dart';
import 'package:deenbook/features/catalog.dart';
import 'package:deenbook/features/profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  void phoneViewport(WidgetTester t) {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  Widget wrap(Session session, Widget child) => Scope(
        session: session,
        child: MaterialApp(home: child),
      );

  test('TC-53: optional contact validates 10-digit local and +970/+972', () {
    expect(partyContactPhoneError(null), isNull);
    expect(partyContactPhoneError(''), isNull);
    for (final value in [
      '0591234567',
      '0561234567',
      '+970591234567',
      '+972591234567',
      '٠٥٩١٢٣٤٥٦٧',
    ]) {
      expect(partyContactPhoneError(value), isNull, reason: value);
    }
    for (final value in ['059123', '059123456', '059abc1234', '1234567890', '+97259']) {
      expect(partyContactPhoneError(value), isNotNull, reason: value);
      expect(internationalContactPhone(value), isNull, reason: value);
    }
    expect(internationalContactPhone('+123456789'), isNull);
  });

  for (final isSupplier in [false, true]) {
    testWidgets('TC-53: incorrect phone keeps ${isSupplier ? 'supplier' : 'customer'} form open and blocks API', (t) async {
      phoneViewport(t);
      var posted = 0;
      final session = (await t.runAsync(() => fakeSession(override: (r) {
        if (r.path == (isSupplier ? '/api/suppliers' : '/api/customers') &&
            r.method == 'POST') {
          posted++;
          return response(party(supplier: isSupplier));
        }
        return null;
      })))!;
      await t.pumpWidget(wrap(session, PartyForm(supplier: isSupplier)));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextFormField, 'الاسم'), 'محل تجريبي');
      await t.enterText(
          find.widgetWithText(TextFormField, 'رقم الجوال (اختياري)'), '059123');
      final save = find.text(isSupplier ? 'حفظ المورد' : 'حفظ الزبون');
      await t.ensureVisible(save);
      await t.pumpAndSettle();
      await t.tap(save);
      await t.pumpAndSettle();
      expect(find.textContaining('رقم الجوال غير مكتمل'), findsWidgets);
      expect(posted, 0);
      expect(find.byType(PartyForm), findsOneWidget);
      expect(
          t.widget<TextFormField>(find.widgetWithText(TextFormField, 'الاسم')).controller!.text,
          'محل تجريبي');
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('TC-49: owner sees accurate cloud recovery steps and archive disclaimer', (t) async {
    phoneViewport(t);
    final session = (await t.runAsync(fakeSession))!;
    await t.pumpWidget(wrap(session, const BackupScreen()));
    await t.pumpAndSettle();
    expect(find.text('الحفظ واستعادة البيانات'), findsOneWidget);
    expect(find.text('كيف تستعيد بياناتك على جهاز آخر؟'), findsOneWidget);
    expect(find.textContaining('سجّل الدخول برقم جوالك'), findsOneWidget);
    expect(find.textContaining('الحركات التي لم تُزامَن'), findsOneWidget);
    expect(find.text('تنزيل ملف JSON أرشيفي'), findsOneWidget);
    expect(find.textContaining('لا يدعم استيراد JSON'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('TC-49: worker sees sync recovery but not full archive export', (t) async {
    phoneViewport(t);
    final session = (await t.runAsync(fakeSession))!;
    session.status = {...?session.status, 'isOwner': false};
    session.changed();
    await t.pumpWidget(wrap(session, const BackupScreen()));
    await t.pumpAndSettle();
    expect(find.text('كيف تستعيد بياناتك على جهاز آخر؟'), findsOneWidget);
    expect(find.text('تنزيل ملف JSON أرشيفي'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
