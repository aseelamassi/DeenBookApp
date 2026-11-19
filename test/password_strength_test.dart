import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deenbook/ui/password_strength.dart';

void main() {
  group('password strength guidance', () {
    test('empty password starts without a rating', () {
      expect(assessPasswordStrength('').strength, PasswordStrength.empty);
    });

    test('too short is weak even when characters are varied', () {
      expect(assessPasswordStrength('Aa3!gh').strength, PasswordStrength.weak);
    });

    test('common predictable patterns remain weak', () {
      expect(
        assessPasswordStrength('123456abcdefG!9x').strength,
        PasswordStrength.weak,
      );
    });

    test('twelve character varied password is medium', () {
      expect(
        assessPasswordStrength('Flowers9abc4').strength,
        PasswordStrength.medium,
      );
    });

    test('long varied unique password is strong', () {
      expect(
        assessPasswordStrength('Sunshine!49CloudMoon').strength,
        PasswordStrength.strong,
      );
    });

    test('Arabic letters are accounted for', () {
      expect(
        assessPasswordStrength('مشترياتبعيدة24!').strength,
        PasswordStrength.medium,
      );
    });
  });

  testWidgets('registration indicator updates as password is typed', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            TextField(controller: controller),
            PasswordStrengthIndicator(controller: controller),
          ],
        ),
      ),
    ));

    expect(find.text('لم تُكتب بعد'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pumpAndSettle();
    expect(find.text('ضعيفة'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Flowers9abc4');
    await tester.pumpAndSettle();
    expect(find.text('متوسطة'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Sunshine!49CloudMoon');
    await tester.pumpAndSettle();
    expect(find.text('قوية'), findsOneWidget);
    expect(find.byKey(const Key('registration-password-strength-hint')), findsOneWidget);
  });
}
