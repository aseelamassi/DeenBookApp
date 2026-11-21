import 'package:deenbook/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> mobile(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('pending subscription after login shows status, not plans', (tester) async {
    await mobile(tester);
    final session = (await tester.runAsync(() => fakeSession(
      active: false,
      override: (request) {
        if (request.path == '/api/subscription/activation') {
          return response({'request': {
            'id': 'pending-1',
            'status': 'Pending',
            'months': 3,
            'amount': 150,
            'senderName': 'صاحب الحوالة',
          }});
        }
        return null;
      },
    )))!;
    await tester.pumpWidget(DeenBookApp(session: session));
    await tester.pumpAndSettle();
    expect(find.text('طلب اشتراك قيد المراجعة'), findsOneWidget);
    expect(find.textContaining('3 أشهر'), findsOneWidget);
    expect(find.text('تحديث حالة الطلب'), findsOneWidget);
    expect(find.text('اختر مدة الاشتراك'), findsNothing);
    expect(find.text('أرسلت التحويل — إرسال طلب التفعيل'), findsNothing);
    expect(find.text('الرئيسية'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TC-10 expired trial: successful renewal opens full pending review immediately', (tester) async {
    await mobile(tester);
    var submissions = 0;
    var statusReads = 0;
    final session = (await tester.runAsync(() => fakeSession(
      active: false,
      override: (request) {
        if (request.path == '/api/subscription/activation') {
          statusReads++;
          // Mimic a stale GET: the initial and subsequent reads still have no
          // pending request. The successful POST itself must drive the UI.
          return response({'request': null});
        }
        if (request.path == '/api/subscription/activation-request' &&
            request.method == 'POST') {
          submissions++;
          return response({
            'id': 'renewal-1',
            'status': 'Pending',
            'months': 3,
            'amount': 150,
          });
        }
        return null;
      },
    )))!;

    await tester.pumpWidget(DeenBookApp(session: session));
    await tester.pumpAndSettle();
    expect(find.text('اختر مدة الاشتراك'), findsOneWidget);
    expect(find.text('طلب اشتراك قيد المراجعة'), findsNothing);

    await tester.scrollUntilVisible(find.byType(TextField), 250);
    final senderField = find.byType(TextField).first;
    await tester.enterText(senderField, 'محمد صاحب الحوالة');
    await tester.testTextInput.hide();
    await tester.pumpAndSettle();
    final submitButton = find.text('أرسلت التحويل — إرسال طلب التفعيل');
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(submissions, 1);
    expect(statusReads, 1); // No extra GET needed after successful POST.
    expect(find.text('طلب اشتراك قيد المراجعة'), findsOneWidget);
    expect(find.text('تحديث حالة الطلب'), findsOneWidget);
    expect(find.textContaining('محمد صاحب الحوالة'), findsWidgets);
    expect(find.text('اختر مدة الاشتراك'), findsNothing);
    expect(find.text('طلب التحويل قيد المراجعة لدى الإدارة'), findsNothing);
    expect(find.text('أرسلت التحويل — إرسال طلب التفعيل'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inactive account without pending request can renew', (tester) async {
    await mobile(tester);
    final session = (await tester.runAsync(() => fakeSession(active: false)))!;
    await tester.pumpWidget(DeenBookApp(session: session));
    await tester.pumpAndSettle();
    expect(find.text('اختر مدة الاشتراك'), findsOneWidget);
    expect(find.text('طلب اشتراك قيد المراجعة'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown activation status never prompts duplicate payment', (tester) async {
    await mobile(tester);
    final session = (await tester.runAsync(() => fakeSession(
      active: false,
      override: (request) {
        if (request.path == '/api/subscription/activation') {
          return response({'message': 'Server failure'}, status: 500);
        }
        return null;
      },
    )))!;
    await tester.pumpWidget(DeenBookApp(session: session));
    await tester.pumpAndSettle();
    expect(find.text('تعذّر التحقق من حالة طلب الاشتراك'), findsOneWidget);
    expect(find.text('إعادة التحقق'), findsOneWidget);
    expect(find.text('اختر مدة الاشتراك'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
