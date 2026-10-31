import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/session.dart';
import '../services/export.dart';
import '../services/subscription_contact.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

class Plans extends StatelessWidget {
  const Plans({super.key, required this.selected, required this.select});
  final int selected;
  final ValueChanged<int> select;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final i in [1, 3])
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => select(i),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: selected == i ? const Color(0xFFF0EFF9) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected == i ? navy : const Color(0xFFE0E2EE),
                  width: selected == i ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    selected == i
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: navy,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          i == 1 ? 'شهر واحد' : '3 أشهر',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          i == 1 ? 'اشتراك شهري' : 'وفّر 30 شيكل',
                          style: TextStyle(
                            color: i == 3 ? orange : muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  amount(i == 1 ? 60 : 150, size: 22),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}

class AccountHelp extends StatefulWidget {
  const AccountHelp({super.key, this.reset = false});
  final bool reset;
  @override
  State<AccountHelp> createState() => _AccountHelpState();
}

class _AccountHelpState extends State<AccountHelp> {
  int selected = 3;
  final name = TextEditingController(), phone = TextEditingController();
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.reset ? 'استعادة الدخول' : 'اشتراك جديد'),
    ),
    body: Width(
      max: 560,
      child: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Heading(widget.reset ? 'نساعدك ترجع لحسابك' : 'ابدأ دفتر محلك'),
          Text(
            widget.reset
                ? 'تواصل مع إدارة الخدمة لاستعادة الوصول إلى حسابك.'
                : hasSupportContact
                ? 'اختر مدة الاشتراك، ثم افتح واتساب وأرسل الطلب للإدارة للحصول على طريقة الدفع وبيانات الدخول.'
                : 'اختر مدة الاشتراك وجهّز تفاصيل طلبك. التواصل مع الإدارة من التطبيق غير متاح حالياً؛ عرض الطلب أو نسخه لا يرسله.',
            style: const TextStyle(color: muted),
          ),
          const SizedBox(height: 24),
          Form(
            key: form,
            child: Column(
              children: [
                if (!widget.reset) field(name, 'اسم المحل', required: true),
                field(
                  phone,
                  'رقم الجوال',
                  keyboard: TextInputType.phone,
                  validator: (v) => phoneNumber(v ?? '') == null
                      ? 'أدخل رقم جوال صحيحاً'
                      : null,
                ),
              ],
            ),
          ),
          if (!widget.reset)
            Plans(
              selected: selected,
              select: (v) => setState(() => selected = v),
            ),
          const SizedBox(height: 16),
          BusyButton(
            label: hasSupportContact
                ? 'متابعة عبر واتساب'
                : widget.reset
                ? 'عرض طلب المساعدة'
                : 'عرض طلب الاشتراك',
            onPressed: () {
              if (form.currentState!.validate()) {
                contact(
                  context,
                  widget.reset
                      ? 'أحتاج لاستعادة الدخول للرقم ${phoneNumber(phone.text)}'
                      : subscriptionRequestText(
                          shopName: name.text,
                          phone: phoneNumber(phone.text),
                          months: selected,
                        ),
                );
              }
            },
          ),
          const SizedBox(height: 16),
          const Text(
            'لا يُفعّل الاشتراك قبل تأكيد الدفع من الإدارة.',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key, this.gate = false});
  final bool gate;
  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  int selected = 3;
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final s = Scope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('الاشتراك والتجديد'),
        automaticallyImplyLeading: !widget.gate,
      ),
      body: Width(
        max: 600,
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.workspace_premium_outlined,
                    size: 40,
                    color: s.active ? navy : orange,
                  ),
                  const SizedBox(height: 12),
                  Heading(
                    s.active
                        ? 'اشتراكك فعّال'
                        : s.status?['suspended'] == true
                        ? 'الحساب موقوف'
                        : 'جدّد اشتراكك للمتابعة',
                  ),
                  Text(s.shopName),
                  Text(
                    'صالح حتى ${day(s.status?['paidUntil'])}',
                    style: const TextStyle(color: muted),
                  ),
                  if (!s.active)
                    const Text(
                      'بيانات محلك محفوظة. تواصل مع الإدارة لاستعادة الوصول.',
                    ),
                ],
              ),
            ),
            const Heading('اختر مدة الاشتراك'),
            Plans(
              selected: selected,
              select: (v) => setState(() => selected = v),
            ),
            BusyButton(
              label: hasSupportContact
                  ? 'متابعة التجديد عبر واتساب'
                  : 'عرض طلب التجديد',
              onPressed: () => contact(
                context,
                subscriptionRequestText(
                  shopName: s.shopName,
                  months: selected,
                  phone: s.settings?['phone'] as String?,
                  renewal: true,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              hasSupportContact
                  ? 'أرسل الرسالة من واتساب لإكمال الطلب. تأكيد الدفع والتفعيل يتمان من الإدارة.'
                  : 'لم يُرسل أي طلب. التواصل من التطبيق غير متاح حالياً؛ يمكنك عرض التفاصيل ونسخها.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      await s.reload();
                      if (mounted) setState(() => busy = false);
                    },
              icon: const Icon(Icons.refresh),
              label: const Text('تحديث حالة الاشتراك'),
            ),
            if (widget.gate)
              TextButton(
                onPressed: () async {
                  try {
                    await s.api.logout();
                  } catch (e) {
                    if (context.mounted) message(context, e);
                  }
                },
                child: const Text('تسجيل الخروج من جميع الأجهزة'),
              ),
          ],
        ),
      ),
    );
  }
}

class WorkersScreen extends StatelessWidget {
  const WorkersScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('العاملون')),
    body: const Width(
      child: Padding(
        padding: EdgeInsets.all(22),
        child: Empty(
          'حسابات العاملين',
          'إضافة العاملين وإدارة صلاحياتهم غير متاحة في الإصدار الحالي. حساب صاحب المحل هو الحساب المدعوم حالياً.',
          icon: Icons.badge_outlined,
        ),
      ),
    ),
  );
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      owner = TextEditingController(),
      phone = TextEditingController();
  bool ready = false, busy = false;
  String? error;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!ready) {
      final s = Scope.of(context);
      name.text = s.shopName;
      owner.text = s.settings?['ownerName'] ?? '';
      phone.text = s.settings?['phone'] ?? '';
      ready = true;
    }
  }

  @override
  void dispose() {
    name.dispose();
    owner.dispose();
    phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('بيانات المحل')),
    body: Width(
      child: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                field(name, 'اسم المحل', required: true),
                field(owner, 'اسم صاحب المحل'),
                field(
                  phone,
                  'هاتف التواصل',
                  keyboard: TextInputType.phone,
                  max: 30,
                ),
                const Text(
                  'رقم التواصل هنا لا يغيّر رقم تسجيل الدخول.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 20),
                if (error != null) Text(error!),
                BusyButton(
                  label: 'حفظ البيانات',
                  busy: busy,
                  onPressed: () async {
                    if (!form.currentState!.validate()) return;
                    setState(() => busy = true);
                    final s = Scope.of(context);
                    try {
                      final data = await s.api.request(
                        'PUT',
                        '/api/settings',
                        body: {
                          'name': name.text.trim(),
                          'ownerName': owner.text.trim(),
                          'phone': phone.text.trim(),
                        },
                      );
                      s.settings = Map<String, dynamic>.from(data);
                      s.changed();
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (mounted) setState(() => error = '$e');
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class PasswordScreen extends StatefulWidget {
  const PasswordScreen({super.key});
  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  final form = GlobalKey<FormState>();
  final old = TextEditingController(),
      next = TextEditingController(),
      again = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    old.dispose();
    next.dispose();
    again.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('تغيير كلمة المرور')),
    body: Width(
      child: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final e in [
                  (old, 'كلمة المرور الحالية'),
                  (next, 'كلمة المرور الجديدة'),
                  (again, 'تأكيد كلمة المرور'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: TextFormField(
                      controller: e.$1,
                      obscureText: true,
                      decoration: InputDecoration(labelText: e.$2),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'هذا الحقل مطلوب';
                        if (e.$1 == next && v.length < 12) {
                          return 'استخدم 12 حرفاً على الأقل';
                        }
                        if (e.$1 == again && v != next.text) {
                          return 'كلمتا المرور غير متطابقتين';
                        }
                        return null;
                      },
                    ),
                  ),
                const Text(
                  'بعد التغيير ستسجّل الدخول مجدداً على جميع الأجهزة.',
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 18),
                if (error != null) Text(error!),
                BusyButton(
                  label: 'تغيير كلمة المرور',
                  busy: busy,
                  onPressed: () async {
                    if (!form.currentState!.validate()) return;
                    setState(() => busy = true);
                    final s = Scope.of(context);
                    try {
                      await s.api.request(
                        'POST',
                        '/api/auth/change-password',
                        body: {
                          'currentPassword': old.text,
                          'newPassword': next.text,
                        },
                      );
                      await s.api.clear();
                    } catch (e) {
                      if (mounted) setState(() => error = '$e');
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool busy = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('النسخ الاحتياطي')),
    body: Width(
      child: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.cloud_done_outlined, color: navy, size: 42),
                const SizedBox(height: 16),
                const Heading('بيانات محلك محفوظة سحابياً'),
                const Text(
                  'الزبائن والموردون والأصناف والحركات مرتبطة بحساب محلك. يمكنك تصدير نسخة إضافية والاحتفاظ بها عند الحاجة.',
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 18),
                BusyButton(
                  label: 'تصدير نسخة احتياطية',
                  busy: busy,
                  icon: Icons.download_outlined,
                  onPressed: () async {
                    setState(() => busy = true);
                    try {
                      final data = await Scope.of(context).api
                          .get('/api/backup/export');
                      if (context.mounted) await Exports.backup(data, context);
                    } catch (e) {
                      if (context.mounted) message(context, e);
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
                ),
              ],
            ),
          ),
          const Text(
            'الملف يحتوي على بيانات المحل كاملة بصيغة JSON. احفظه في مكان خاص وآمن.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}
