import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/session.dart';
import '../ui/theme.dart';
import '../ui/design.dart';
import '../ui/widgets.dart';
import 'profile.dart';

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
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8EDF2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: DesignButton(
                    'الدخول برقم الجوال وكلمة المرور',
                    background: Colors.white,
                    onTap: () => FocusScope.of(context).unfocus(),
                  ),
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
                            hintText: '059xxxxxxx',
                          ),
                          validator: (v) => phoneNumber(v ?? '') == null
                              ? 'أدخل رقم جوال صحيحاً يبدأ بـ 059 أو 056'
                              : null,
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
                          child: Text(
                            'محلك جديد معنا؟ إنشاء حساب للمحل',
                            style: appText(
                              12,
                              color: navy,
                              weight: FontWeight.w800,
                            ),
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
