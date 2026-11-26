import 'package:deenbook/core/session.dart';
import 'package:deenbook/features/profile.dart';
import 'package:deenbook/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  void viewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<Session> worker({bool active = true}) async {
    final session = await fakeSession(active: active);
    session.status = {
      ...?session.status,
      'isOwner': false,
      'userName': 'سارة أحمد',
      'userPhone': '+970599123456',
    };
    session.changed();
    return session;
  }

  test('TC-48: existing worker without a saved name shows their phone', () {
    expect(workerDisplayName({'name': '', 'phoneNumber': '+970599123456'}),
        '+970599123456');
    expect(workerDisplayName({'name': 'سارة', 'phoneNumber': '0591111111'}),
        'سارة');
  });

  testWidgets('TC-48: worker identity appears in header and drawer; no subscription', (tester) async {
    viewport(tester);
    final session = (await tester.runAsync(worker))!;
    await tester.pumpWidget(DeenBookApp(session: session));
    await tester.pumpAndSettle();
    expect(find.textContaining('المستخدم: سارة أحمد'), findsOneWidget);
    await tester.tap(find.byTooltip('البروفايل'));
    await tester.pumpAndSettle();
    expect(find.text('المستخدم الحالي: سارة أحمد (عامل)'), findsOneWidget);
    expect(find.text('ملفي الشخصي'), findsOneWidget);
    expect(find.text('الاشتراك والتجديد'), findsNothing);
    expect(find.text('العاملون'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TC-48: worker profile shows own name/phone and password action', (tester) async {
    viewport(tester);
    final session = (await tester.runAsync(worker))!;
    await tester.pumpWidget(Scope(
      session: session,
      child: const MaterialApp(home: WorkerProfileScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('سارة أحمد'), findsOneWidget);
    expect(find.text('+970599123456'), findsOneWidget);
    expect(find.text('تغيير كلمة المرور'), findsOneWidget);
    expect(find.text('حفظ البيانات'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TC-48: expired worker account cannot open renewal/payment flow', (tester) async {
    viewport(tester);
    final session = (await tester.runAsync(() => worker(active: false)))!;
    await tester.pumpWidget(DeenBookApp(session: session));
    await tester.pumpAndSettle();
    expect(find.text('اشتراك المحل بحاجة إلى تجديد'), findsOneWidget);
    expect(find.text('اختر مدة الاشتراك'), findsNothing);
    expect(find.text('أرسلت التحويل — إرسال طلب التفعيل'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TC-48: adding a worker has a required name field', (tester) async {
    viewport(tester);
    final session = (await tester.runAsync(fakeSession))!;
    await tester.pumpWidget(Scope(
      session: session,
      child: const MaterialApp(home: WorkersScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('اسم العامل'), findsOneWidget);
    expect(find.text('رقم جوال العامل'), findsOneWidget);
    expect(find.textContaining('كلمة مرور العامل'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Worker rename survives closing the focused dialog', (tester) async {
    viewport(tester);
    var workerName = 'سارة';
    final savedNames = <String>[];
    final session = (await tester.runAsync(() => fakeSession(override: (request) {
      if (request.path == '/api/workers/worker-1/name') {
        expect(request.method, 'PUT');
        workerName = request.data['name'] as String;
        savedNames.add(workerName);
        return response({'name': workerName});
      }
      if (request.path == '/api/workers') {
        return response({
          'workers': [
            {'id': 'worker-1', 'name': workerName, 'enabled': true},
          ],
        });
      }
      return null;
    })))!;
    await tester.pumpWidget(Scope(
      session: session,
      child: const MaterialApp(home: WorkersScreen()),
    ));
    await tester.pumpAndSettle();

    final dialogField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.tap(find.text('تعديل الاسم'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(dialogField).controller!.text, 'سارة');
    await tester.enterText(dialogField, 'اسم ملغى');
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(savedNames, isEmpty);

    await tester.tap(find.text('تعديل الاسم'));
    await tester.pumpAndSettle();
    await tester.enterText(dialogField, '  سارة أحمد  ');
    await tester.tap(find.text('حفظ الاسم'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(savedNames, ['سارة أحمد']);
    expect(find.text('سارة أحمد'), findsOneWidget);
  });
}
