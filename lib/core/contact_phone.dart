import 'format.dart';

/// WhatsApp needs an international E.164 number without the leading +.
///
/// A Palestinian local mobile number defaults to +970. An explicit +972
/// (or 00972 / 972) is preserved rather than being rewritten as +970.
/// The domestic trunk zero is removed when a country code is supplied.
String? whatsappContactNumber(String raw) {
  var phone = digits(raw.trim()).replaceAll(RegExp(r'[\s().-]'), '');
  if (phone.isEmpty) return null;

  final hasPlus = phone.startsWith('+');
  final hasInternationalAccess = phone.startsWith('00');
  if (hasPlus) {
    phone = phone.substring(1);
  } else if (hasInternationalAccess) {
    phone = phone.substring(2);
  }
  if (!RegExp(r'^\d+$').hasMatch(phone)) return null;

  for (final countryCode in ['970', '972']) {
    if (!phone.startsWith(countryCode)) continue;
    var national = phone.substring(countryCode.length);
    if (national.startsWith('0')) national = national.substring(1);
    // +970 mobile allocations in this app: 059 / 056.
    // +972 also supports mobile numbers such as 050, 052, 054, 058.
    final pattern = countryCode == '970'
        ? RegExp(r'^5[69]\d{7}$')
        : RegExp(r'^5\d{8}$');
    return pattern.hasMatch(national) ? '$countryCode$national' : null;
  }

  if (hasPlus || hasInternationalAccess) {
    // Explicitly entered foreign numbers keep their own international prefix.
    return RegExp(r'^[1-9]\d{9,14}$').hasMatch(phone) ? phone : null;
  }

  var local = phone;
  if (local.startsWith('0')) local = local.substring(1);
  return RegExp(r'^5[69]\d{7}$').hasMatch(local) ? '970$local' : null;
}

/// Store and copy a complete international number, including the leading +.
String? internationalContactPhone(String raw) {
  final number = whatsappContactNumber(raw);
  return number == null ? null : '+$number';
}

Uri? whatsappContactUri(String phone, String text) {
  final number = whatsappContactNumber(phone);
  return number == null
      ? null
      : Uri.https('wa.me', '/$number', {'text': text});
}

/// Validation for customer and supplier contact phones. The number is optional,
/// but when provided it must be a complete local or international mobile number.
/// The backend applies equivalent validation; old clients cannot bypass it.
String? partyContactPhoneError(String? value) {
  final raw = (value ?? '').trim();
  if (raw.isEmpty) return null;
  if (internationalContactPhone(raw) != null) return null;

  final normalized = digits(raw).replaceAll(RegExp(r'[\s().-]'), '');
  final local = normalized.startsWith('05') ||
      RegExp(r'^5[69]').hasMatch(normalized);
  if (local && RegExp(r'^\d+$').hasMatch(normalized) &&
      normalized.length < (normalized.startsWith('0') ? 10 : 9)) {
    return 'رقم الجوال غير مكتمل: الرقم المحلي 10 أرقام تبدأ بـ 059 أو 056';
  }
  final international = normalized.startsWith('+970') ||
      normalized.startsWith('+972') ||
      normalized.startsWith('00970') ||
      normalized.startsWith('00972') ||
      normalized.startsWith('970') ||
      normalized.startsWith('972');
  if (international) {
    final withoutPrefix = normalized.replaceFirst(
      RegExp(r'^(?:\+|00)?(?:970|972)0?'), '');
    if (RegExp(r'^\d+$').hasMatch(withoutPrefix) &&
        withoutPrefix.length < 9) {
      return 'رقم الجوال غير مكتمل: أدخل 9 أرقام بعد رمز الدولة';
    }
  }
  return 'رقم جوال غير صحيح. مثال: 0591234567 أو +970591234567 أو +972591234567';
}
