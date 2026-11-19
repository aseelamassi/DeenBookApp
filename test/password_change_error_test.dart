import 'package:flutter_test/flutter_test.dart';
import 'package:deenbook/features/profile.dart';

void main() {
  test('translates the API incorrect current password error', () {
    expect(
      passwordChangeErrorText('Incorrect password.'),
      'كلمة المرور الحالية غير صحيحة. تأكد منها وحاول مرة أخرى.',
    );
    expect(
      passwordChangeErrorText(' incorrect PASSWORD! '),
      'كلمة المرور الحالية غير صحيحة. تأكد منها وحاول مرة أخرى.',
    );
  });

  test('preserves other server errors for troubleshooting', () {
    expect(passwordChangeErrorText('Network unavailable'), 'Network unavailable');
    expect(passwordChangeErrorText('انتهت الجلسة'), 'انتهت الجلسة');
  });
}
