import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/session.dart';
import '../services/export.dart';
import '../services/subscription_contact.dart';
import '../ui/theme.dart';
import '../ui/design.dart';
import 'sync_center.dart';
import '../ui/widgets.dart';

class Plans extends StatelessWidget {
  const Plans({super.key, required this.selected, required this.select});
  final int selected;
  final ValueChanged<int> select;
  @override
  Widget build(BuildContext c) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final i in [1, 3]) ...[
        if (i == 3) const SizedBox(width: 10),
        Expanded(
          child: Semantics(
            selected: selected == i,
            button: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => select(i),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: selected == i ? lavender : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: selected == i ? navy : lineColor,
                    width: selected == i ? 2 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            i == 1 ? 'شهر واحد' : '3 أشهر',
                            style: appText(12, weight: FontWeight.w900),
                          ),
                        ),
                        Icon(
                          selected == i
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: navy,
                          size: 18,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FittedBox(child: amount(i == 1 ? 60 : 150, size: 30)),
                    Text(
                      i == 1 ? 'شيكل / شهر' : 'شيكل / 3 أشهر',
                      style: appText(10, color: secondaryText),
                    ),
                    const SizedBox(height: 12),
                    SoftTag(
                      i == 1 ? 'مرونة شهرية' : 'الأوفر · خصم 30 ₪',
                      color: i == 1 ? navy : orange,
                      background: i == 1 ? lavender : paleOrange,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
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
  int selected = 3, step = 0;
  bool trial = true;
  final name = TextEditingController(),
      phone = TextEditingController(),
      owner = TextEditingController();
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    owner.dispose();
    super.dispose();
  }

  String get request => widget.reset
      ? 'أحتاج لاستعادة الدخول للرقم ${phoneNumber(phone.text)}'
      : [
          if (trial)
            'مرحباً، أرغب بفتح حساب جديد لمحل ${name.text.trim()} وتجربة مجانية لمدة 14 يوماً.\nرقم الجوال: ${phoneNumber(phone.text)}'
          else
            subscriptionRequestText(
              shopName: name.text,
              phone: phoneNumber(phone.text),
              months: selected,
            ),
          if (owner.text.trim().isNotEmpty)
            'اسم صاحب المحل: ${owner.text.trim()}',
        ].join('\n');
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          const BrandHeader(back: true),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (!widget.reset) ...[
                  Row(
                    children: [
                      for (var i = 0; i < 3; i++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Column(
                              children: [
                                Container(
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: i <= step ? orange : lineColor,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  [
                                    'بيانات المحل',
                                    'اختر الخطة',
                                    'مراجعة الطلب',
                                  ][i],
                                  style: appText(
                                    10,
                                    color: i == step ? navy : muted,
                                    weight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 28),
                ],
                Text(
                  widget.reset
                      ? 'نساعدك ترجع لحسابك'
                      : [
                          'خلّينا نتعرّف على محلك',
                          'ابدأ بالطريقة التي تناسبك',
                          'طلبك جاهز للمراجعة',
                        ][step],
                  style: appText(22, weight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.reset
                      ? 'تواصل مع إدارة الخدمة لاستعادة الوصول إلى حسابك.'
                      : [
                          'أدخل بيانات المحل ورقم الجوال الذي ستستخدمه للدخول.',
                          'جرّب دفتر دين 14 يوماً مجاناً، أو اختر اشتراكك.',
                          'راجع التفاصيل ثم أرسلها لإدارة الخدمة لإنشاء الحساب.',
                        ][step],
                  style: appText(12, color: secondaryText),
                ),
                const SizedBox(height: 24),
                if (widget.reset || step == 0)
                  Form(
                    key: form,
                    child: Column(
                      children: [
                        if (!widget.reset) ...[
                          field(owner, 'اسم صاحب المحل', required: true),
                          field(name, 'اسم المحل', required: true),
                        ],
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
                if (!widget.reset && step == 1) ...[
                  InkWell(
                    onTap: () => setState(() => trial = true),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: trial ? green : const Color(0xFFA7F3D0),
                          width: trial ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.card_giftcard_outlined,
                            color: green,
                            size: 32,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'جرّب مجاناً لمدة 14 يوم',
                                  style: appText(
                                    14,
                                    color: green,
                                    weight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  'تبدأ التجربة عند إنشاء حسابك',
                                  style: appText(11, color: green),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            trial
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: green,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Heading('خطط الاشتراك'),
                  Plans(
                    selected: trial ? 0 : selected,
                    select: (v) => setState(() {
                      selected = v;
                      trial = false;
                    }),
                  ),
                ],
                if (!widget.reset && step == 2)
                  Surface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.text.trim(),
                          style: appText(16, weight: FontWeight.w900),
                        ),
                        Text(
                          owner.text.trim(),
                          style: appText(12, color: secondaryText),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          phoneNumber(phone.text) ?? phone.text,
                          textDirection: TextDirection.ltr,
                        ),
                        const Divider(height: 28),
                        SoftTag(
                          trial
                              ? 'تجربة مجانية · 14 يوم'
                              : selected == 1
                              ? 'شهر واحد · 60 ₪'
                              : '3 أشهر · 150 ₪',
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'إنشاء الحساب وتفعيل الاشتراك يتمان من الإدارة. لم يُرسل الطلب بعد.',
                          style: appText(11, color: secondaryText),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                BusyButton(
                  label: widget.reset || step == 2
                      ? (hasSupportContact
                            ? 'متابعة عبر واتساب'
                            : widget.reset
                            ? 'عرض طلب المساعدة'
                            : 'عرض طلب الاشتراك')
                      : 'متابعة ←',
                  onPressed: () {
                    if ((widget.reset || step == 0) &&
                        !form.currentState!.validate()) {
                      return;
                    }
                    if (widget.reset || step == 2) {
                      contact(context, request);
                    } else {
                      setState(() => step++);
                    }
                  },
                ),
                if (!widget.reset && step > 0)
                  TextButton(
                    onPressed: () => setState(() => step--),
                    child: const Text('رجوع للخطوة السابقة'),
                  ),
                const SizedBox(height: 20),
                Text(
                  widget.reset
                      ? 'لن نطلب كلمة مرورك في رسالة.'
                      : 'حساب واحد للمحل وبيانات محفوظة سحابياً. لا حاجة لإرسال رمز تحقق.',
                  textAlign: TextAlign.center,
                  style: appText(11, color: muted),
                ),
              ],
            ),
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
        max: 480,
        child: ListView(
          padding: const EdgeInsets.all(16),
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
                    s.isTrial && s.active
                        ? 'تجربتك المجانية فعّالة'
                        : s.active
                        ? 'اشتراكك فعّال'
                        : s.status?['suspended'] == true
                        ? 'الحساب موقوف'
                        : 'جدّد اشتراكك للمتابعة',
                  ),
                  Text(s.shopName),
                  Text(
                    s.isTrial
                        ? 'متبقي ${s.trialDaysRemaining} يوم من التجربة — تنتهي ${day(s.status?['paidUntil'])}'
                        : 'صالح حتى ${day(s.status?['paidUntil'])}',
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
            const SizedBox(height: 20),
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
  Widget build(BuildContext context) {
    final s = Scope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('العاملون والصلاحيات')),
      body: Width(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            BrandCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'فريق المحل',
                    style: appText(
                      18,
                      color: Colors.white,
                      weight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'حسابات العاملين مرتبطة بدفتر المحل نفسه.',
                    style: appText(11, color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Surface(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: lavender,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.person_outline, color: navy),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${s.settings?['ownerName'] ?? 'صاحب المحل'}',
                          style: appText(14, weight: FontWeight.w900),
                        ),
                        Text(s.shopName, style: appText(11, color: muted)),
                        const SizedBox(height: 8),
                        const SoftTag('صاحب المحل · صلاحيات الإدارة'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Empty(
              'حسابات العاملين',
              'إضافة العاملين وإدارة صلاحياتهم غير متاحة في الإصدار الحالي. حساب صاحب المحل هو الحساب المدعوم حالياً.',
              icon: Icons.badge_outlined,
            ),
          ],
        ),
      ),
    );
  }
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
    appBar: AppBar(title: const Text('إعدادات المحل')),
    body: Width(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Heading('معلومات المحل'),
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
          const SizedBox(height: 20),
          Surface(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_outline, color: navy),
              title: const Text('تغيير كلمة المرور'),
              subtitle: const Text('حماية الوصول إلى حساب المحل'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => open(context, const PasswordScreen()),
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
        padding: const EdgeInsets.all(16),
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
        padding: const EdgeInsets.all(16),
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
                      final data = await Scope.of(
                        context,
                      ).api.get('/api/backup/export');
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
          Surface(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.sync, color: navy),
              title: const Text('المزامنة والحركات المحفوظة'),
              subtitle: Text(
                '${Scope.of(context).pendingSync} حركة بانتظار المزامنة',
              ),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => open(context, const SyncCenterScreen()),
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
