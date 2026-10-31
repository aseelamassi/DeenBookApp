import 'package:flutter/material.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../ui/theme.dart';
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
      child: Width(
        max: 470,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(26, 48, 26, 32),
          children: [
            const Center(
              child: CircleAvatar(
                radius: 38,
                backgroundColor: navy,
                child: Icon(
                  Icons.auto_stories_rounded,
                  color: Colors.white,
                  size: 38,
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'دفتر الأمانة',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
                color: navy,
              ),
            ),
            const Text(
              'حسابات محلك، مرتّبة وبأمان',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 38),
            const Heading('أهلاً برجعتك'),
            const Text(
              'سجّل دخولك لتتابع حسابات المحل.',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 24),
            AutofillGroup(
              child: Form(
                key: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      textDirection: TextDirection.ltr,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(
                        labelText: 'رقم الجوال',
                        hintText: '059xxxxxxx',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                      validator: (v) => phoneNumber(v ?? '') == null
                          ? 'أدخل رقم جوال صحيحاً يبدأ بـ 059 أو 056'
                          : null,
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: password,
                      obscureText: hidden,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => busy ? null : submit(),
                      decoration: InputDecoration(
                        labelText: 'كلمة المرور',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: hidden
                              ? 'إظهار كلمة المرور'
                              : 'إخفاء كلمة المرور',
                          onPressed: () => setState(() => hidden = !hidden),
                          icon: Icon(
                            hidden
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'أدخل كلمة المرور' : null,
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () =>
                            open(context, const AccountHelp(reset: true)),
                        child: const Text('نسيت كلمة المرور؟'),
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
                      label: 'تسجيل الدخول',
                      onPressed: submit,
                      busy: busy,
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton(
                      onPressed: () => open(context, const AccountHelp()),
                      child: const Text('ليس لديك حساب؟ اطلب اشتراكاً'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              'دخول واحد إلى بيانات محلك المحفوظة سحابياً.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}
