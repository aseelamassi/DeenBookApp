import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/session.dart';
import '../ui/theme.dart';
import '../ui/design.dart';
import '../ui/widgets.dart';
import 'profile.dart';

/// Validation copy only; normalization and the server request remain unchanged.
String? loginPhoneError(String? input) {
  final value = digits(input ?? '')
      .trim()
      .replaceAll(RegExp(r'[\s()\-]'), '');
  if (value.isEmpty) return 'أدخل رقم الجوال';
  if (phoneNumber(value) != null) return null;

  if (value.startsWith('+970') || value.startsWith('+972') ||
      value.startsWith('00970') || value.startsWith('00972')) {
    final prefixLength = value.startsWith('00') ? 5 : 4;
    if (value.length - prefixLength < 9) {
      return 'رقم الجوال غير مكتمل: أدخل 9 أرقام بعد رمز الدولة';
    }
  } else if (value.startsWith('059') || value.startsWith('056')) {
    if (value.length < 10) {
      return 'رقم الجوال غير مكتمل: أدخل 10 أرقام';
    }
  } else if (value.startsWith('59') || value.startsWith('56')) {
    if (value.length < 9) {
      return 'رقم الجوال غير مكتمل: أدخل 9 أرقام';
    }
  }
  return 'رقم غير صحيح. مثال: 0591234567 أو +970591234567';
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final phone = TextEditingController(), password = TextEditingController();
  final form = GlobalKey<FormState>();
  bool busy = false, hidden = true;
  String? error;
  @override
  void dispose() {
    phone.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await Scope.of(context).login(phoneNumber(phone.text)!, password.text);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          const BrandHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'دخول المالك والعاملين — دفتر دين',
                  style: appText(12, color: orange, weight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'أهلاً برجعتك',
                  style: appText(24, weight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  'سجّل دخولك وتابع حسابات محلك من مكان واحد.',
                  style: appText(12, color: secondaryText),
                ),
                const SizedBox(height: 24),
                AutofillGroup(
                  child: Form(
                    key: form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Text(
                              'رقم الجوال',
                              style: appText(12, weight: FontWeight.w800),
                            ),
                            const Spacer(),
                            const SoftTag('حساب المحل'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          key: const Key('login-phone'),
                          controller: phone,
                          keyboardType: TextInputType.phone,
                          textDirection: TextDirection.ltr,
                          autofillHints: const [AutofillHints.username],
                          decoration: const InputDecoration(
                            hintText: '059xxxxxxx أو +97059xxxxxxx',
                          ),
                          validator: loginPhoneError,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'كلمة المرور',
                          style: appText(12, weight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          key: const Key('login-password'),
                          controller: password,
                          obscureText: hidden,
                          autofillHints: const [AutofillHints.password],
                          onFieldSubmitted: (_) => busy ? null : submit(),
                          decoration: InputDecoration(
                            hintText: 'أدخل كلمة المرور',
                            suffixIcon: TextButton(
                              onPressed: () => setState(() => hidden = !hidden),
                              child: Text(
                                hidden ? 'إظهار' : 'إخفاء',
                                style: appText(
                                  11,
                                  color: navy,
                                  weight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          validator: (v) => v == null || v.isEmpty
                              ? 'أدخل كلمة المرور'
                              : null,
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () =>
                                open(context, const AccountHelp(reset: true)),
                            child: Text(
                              'نسيت كلمة المرور؟',
                              style: appText(11, color: secondaryText),
                            ),
                          ),
                        ),
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        BusyButton(
                          label: 'تسجيل الدخول إلى دفتر دين',
                          onPressed: submit,
                          busy: busy,
                        ),
                        const SizedBox(height: 20),
                        TextButton(
                          onPressed: () => open(context, const AccountHelp()),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: 'محلك جديد معنا؟ ',
                                  style: appText(
                                    13,
                                    color: navy,
                                    weight: FontWeight.w700,
                                  ),
                                ),
                                TextSpan(
                                  text: 'إنشاء حساب للمحل',
                                  style: appText(
                                    14,
                                    color: orange,
                                    weight: FontWeight.w900,
                                  ).copyWith(decoration: TextDecoration.underline),
                                ),
                              ],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'تدخل إلى نفس حساب المحل وبياناته المحفوظة، من أي جهاز.',
                  textAlign: TextAlign.center,
                  style: appText(11, color: muted),
                ),
              ],
            ),
          ),
          Container(
            color: Colors.white,
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            child: Text(
              '● دفتر دين — حساب شخصي · دفتر مشترك للمحل',
              textAlign: TextAlign.center,
              style: appText(10, color: secondaryText, weight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ),
  );
}
