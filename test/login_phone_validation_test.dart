import 'package:flutter_test/flutter_test.dart';
import 'package:deenbook/features/auth.dart';

void main() {
  test('login phone validation explains incomplete international number', () {
    expect(
      loginPhoneError('+970595679'),
      'رقم الجوال غير مكتمل: أدخل 9 أرقام بعد رمز الدولة',
    );
  });

  test('login phone validation explains incomplete local number', () {
    expect(
      loginPhoneError('059123'),
      'رقم الجوال غير مكتمل: أدخل 10 أرقام',
    );
  });

  test('login phone validation accepts existing supported formats', () {
    for (final number in [
      '0591234567',
      '0561234567',
      '+970591234567',
      '+970561234567',
      '+972591234567',
      '00970591234567',
    ]) {
      expect(loginPhoneError(number), isNull, reason: number);
    }
  });

  test('login phone validation differentiates wrong format and empty input', () {
    expect(loginPhoneError(''), 'أدخل رقم الجوال');
    expect(loginPhoneError('0581234567'), contains('رقم غير صحيح'));
  });
}
