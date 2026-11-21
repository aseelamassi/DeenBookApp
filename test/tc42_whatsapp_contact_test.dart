import 'package:flutter_test/flutter_test.dart';
import 'package:deenbook/core/contact_phone.dart';

void main() {
  group('TC-42 international customer contact for WhatsApp', () {
    test('local mobile defaults to +970 on save and WhatsApp', () {
      expect(internationalContactPhone('0591234567'), '+970591234567');
      expect(internationalContactPhone('591234567'), '+970591234567');
      expect(whatsappContactNumber('0561234567'), '970561234567');
      expect(whatsappContactUri('0591234567', 'كشف الحساب')?.path,
          '/970591234567');
    });

    test('explicit +972 is preserved on save and in the WhatsApp URL', () {
      for (final input in [
        '+972591234567',
        '+972 59 123 4567',
        '00972591234567',
        '972591234567',
        '+9720591234567',
      ]) {
        expect(internationalContactPhone(input), '+972591234567',
            reason: input);
        expect(whatsappContactUri(input, 'test')?.path, '/972591234567',
            reason: input);
      }
    });

    test('also supports other +972 mobile prefixes, without 0', () {
      expect(internationalContactPhone('+9720541234567'), '+972541234567');
      expect(whatsappContactUri('+972541234567', 'test')?.path,
          '/972541234567');
    });

    test('handles Arabic/Persian numbers, 00 international prefix', () {
      expect(internationalContactPhone('٠٥٩١٢٣٤٥٦٧'), '+970591234567');
      expect(internationalContactPhone('۰۰۹۷۰۵۹۱۲۳۴۵۶۷'),
          '+970591234567');
    });

    test('does not silently rewrite another explicitly-entered country', () {
      expect(internationalContactPhone('+905321234567'), '+905321234567');
      expect(whatsappContactUri('+905321234567', 'x')?.path,
          '/905321234567');
    });

    test('invalid and incomplete numbers do not produce WhatsApp URLs', () {
      for (final input in ['', '+972', '059', '059123', 'abc', '+9705999']) {
        expect(whatsappContactUri(input, 'test'), isNull, reason: input);
      }
    });

    test('shared statement message survives URI encoding', () {
      const text = 'كشف حساب محمد\nالرصيد: 420 ₪';
      final uri = whatsappContactUri('+972591234567', text)!;
      expect(uri.scheme, 'https');
      expect(uri.host, 'wa.me');
      expect(uri.queryParameters['text'], text);
    });
  });
}
