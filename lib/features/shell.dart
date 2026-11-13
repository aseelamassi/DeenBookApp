import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../services/receipts.dart';
import '../ui/theme.dart';
import '../ui/design.dart';
import '../core/format.dart';
import '../services/export.dart';
import '../ui/widgets.dart';
import 'catalog.dart';
import 'profile.dart';
import 'reports.dart';
import 'transaction.dart';
import 'sync_center.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int tab = 0;
  Timer? _syncTimer;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    // Keep retrying; successful requests are deduplicated by operationId.
    _syncTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!mounted) return;
      final session = Scope.of(context);
      if (session.pendingSync > 0 || session.isOffline) {
        session.synchronize();
      } else {
        // Refresh remote changes from other workers' devices on the open tab.
        session.changed();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Scope.of(context).synchronize();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      final session = Scope.of(context);
      session.synchronize();
      session.changed();
    }
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = Scope.of(context);
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          backgroundColor: navy,
          foregroundColor: Colors.white,
          toolbarHeight: 68,
          leadingWidth: 70,
          titleSpacing: 0,
          leading: Builder(
            builder: (c) => Padding(
              padding: const EdgeInsetsDirectional.only(start: 16, end: 10),
              child: Center(
                child: InkWell(
                  onTap: () => Scaffold.of(c).openDrawer(),
                  child: Tooltip(
                    message: 'البروفايل',
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: orange,
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(color: Colors.white38, width: 2),
                      ),
                      child: Text(
                        session.shopName.characters.first,
                        style: appText(
                          21,
                          weight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          title: Builder(
            builder: (c) => InkWell(
              onTap: () => Scaffold.of(c).openDrawer(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.shopName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appText(
                      14,
                      weight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'المستخدم: ${session.isOwner ? 'صاحب المحل' : 'عامل'} · ${session.shopName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appText(
                      10,
                      weight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            headerAction(
              Icons.mic_none_rounded,
              'تسجيل صوتي سريع',
              () => open(context, const TransactionScreen(voice: true)),
            ),
            headerAction(
              Icons.insert_chart_outlined_rounded,
              'التقارير',
              () => open(context, const HistoryScreen()),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 3, end: 16),
              child: Center(
                child: InkWell(
                  onTap: () => open(context, const SyncCenterScreen()),
                  child: Container(
                    height: 40,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .14),
                      border: Border.all(color: Colors.white24),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      session.syncing
                          ? 'مزامنة…'
                          : session.isOffline
                          ? 'محلي'
                          : session.pendingSync > 0
                          ? '${session.pendingSync} معلّقة'
                          : 'محفوظ ✓',
                      style: appText(
                        11,
                        weight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        drawer: const ShopDrawer(),
        body: SafeArea(
          child: Column(
            children: [
              if (session.isOffline || session.pendingSync > 0)
                Material(
                  color: session.isOffline
                      ? const Color(0xFFFFF0DF)
                      : const Color(0xFFEEF5FF),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          session.isOffline
                              ? Icons.cloud_off_outlined
                              : Icons.cloud_upload_outlined,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            session.isOffline
                                ? 'وضع دون إنترنت: المعروض من آخر تحميل. ${session.pendingSync} حركة تنتظر المزامنة.'
                                : '${session.pendingSync} حركة محفوظة بانتظار المزامنة.',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              open(context, const SyncCenterScreen()),
                          child: const Text('التفاصيل'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (session.isTrial)
                Material(
                  color: const Color(0xFFEAF6ED),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 7,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.workspace_premium_outlined, size: 18),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            'تجربة مجانية: متبقي ${session.trialDaysRemaining} يوم',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              open(context, const SubscriptionScreen()),
                          child: const Text('الاشتراك'),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: KeyedSubtree(
                  key: ValueKey('$tab:${session.revision}'),
                  child: tab == 0
                      ? HomeScreen(onCustomers: () => setState(() => tab = 1))
                      : CatalogScreen(
                          mode: ['', 'customers', 'suppliers', 'products'][tab],
                        ),
                ),
              ),
            ],
          ),
        ),
        // Keep the quick-action button inside the navigation layout instead of
        // Scaffold.floatingActionButton: SnackBars otherwise move the FAB.
        bottomNavigationBar: SafeArea(
          top: false,
          child: SizedBox(
            height: 82,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                Positioned.fill(
                  top: 16,
                  child: ColoredBox(
                    color: Colors.white,
                    child: Row(
                      children: [
                        nav(0, 'الرئيسية', Icons.home_outlined),
                        nav(1, 'الزبائن', Icons.people_outline),
                        const SizedBox(width: 72),
                        nav(2, 'الموردون', Icons.local_shipping_outlined),
                        nav(3, 'الأصناف', Icons.shopping_bag_outlined),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  child: Material(
                    color: orange,
                    elevation: 3,
                    shape: const CircleBorder(side: BorderSide(color: canvas, width: 4)),
                    child: IconButton(
                      tooltip: 'إضافة حركة',
                      onPressed: () => quickAction(context),
                      icon: const Icon(Icons.add, size: 31, color: Colors.white),
                      constraints: const BoxConstraints.tightFor(width: 64, height: 64),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget nav(int i, String text, IconData icon) => Expanded(
    child: InkWell(
      onTap: () => setState(() => tab = i),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: tab == i ? navy : muted, size: 23),
            const SizedBox(height: 4),
            FittedBox(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 11,
                  color: tab == i ? navy : muted,
                  fontWeight: tab == i ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onCustomers});
  final VoidCallback onCustomers;
  @override
  Widget build(BuildContext context) {
    final session = Scope.of(context);
    return RefreshIndicator(
      onRefresh: () async => session.changed(),
      child: Width(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [
            Remote(
              load: () async {
                final data = await session.api.get('/api/dashboard');
                final recent = await session.api.get(
                  '/api/transactions',
                  query: {
                    'page': 1,
                    'size': session.ledgerV2 ? 5 : 30,
                    if (session.ledgerV2) 'partyKind': 'Customer',
                  },
                );
                final entries = List<Json>.from(
                  (recent['items'] as List).map(
                    (e) => Map<String, dynamic>.from(e),
                  ),
                );
                final names = <String, String>{};
                final customerIds = <String>{};
                await Future.wait(
                  entries.map((e) => e['partyId'] as String).toSet().map((
                    id,
                  ) async {
                    final p = await session.api.get('/api/parties/$id');
                    names[id] = '${p['name']}';
                    if (p['kind'] == 'Customer') customerIds.add(id);
                  }),
                );
                return {
                  ...data,
                  'recent': entries
                      .where((e) => customerIds.contains(e['partyId']))
                      .take(5)
                      .toList(),
                  'names': names,
                };
              },
              builder: (data) {
                final summary = data['summary'] as Map;
                final recent = data['recent'] as List;
                final debtors = (data['topDebtors'] as List? ?? []).take(3);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Surface(
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'ملخص الذمم المالية',
                                  style: appText(16, weight: FontWeight.w800),
                                ),
                              ),
                              SoftTag(
                                session.isOffline
                                    ? 'محفوظ على الجهاز'
                                    : session.pendingSync > 0
                                    ? 'بانتظار المزامنة'
                                    : 'حفظ تلقائي فوري ✓',
                                color: green,
                                background: const Color(0xFFECFDF5),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: BalanceBox(
                                  'لي على الزبائن',
                                  summary['receivables'],
                                  Icons.south_west,
                                  (summary['receivables'] as num? ?? 0) > 0
                                      ? 'مستحقات لدى الزبائن'
                                      : 'لا توجد مستحقات على الزبائن',
                                  orange,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: BalanceBox(
                                  'عليّ للموردين',
                                  summary['payables'],
                                  Icons.north_east,
                                  (summary['payables'] as num? ?? 0) > 0
                                      ? 'مستحقات للموردين'
                                      : 'لا توجد مستحقات للموردين',
                                  navy,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: DesignButton(
                            'تسجيل مشتريات دين',
                            icon: Icons.add,
                            background: orange,
                            foreground: Colors.white,
                            height: 50,
                            onTap: () =>
                                open(context, const TransactionScreen()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DesignButton(
                            'قبض دفعة / سداد',
                            icon: Icons.check,
                            background: navy,
                            foreground: Colors.white,
                            height: 50,
                            onTap: () => open(
                              context,
                              const TransactionScreen(kind: 'Payment'),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (debtors.isNotEmpty)
                      Surface(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.circle,
                                  size: 9,
                                  color: orange,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'أبرز المدينين وحسابات للمتابعة',
                                    style: appText(14, weight: FontWeight.w800),
                                  ),
                                ),
                                TextButton(
                                  onPressed: onCustomers,
                                  child: const Text('عرض الكل'),
                                ),
                              ],
                            ),
                            Text(
                              'ديون الزبائن والأرصدة الدائنة التي تحتاج متابعة',
                              style: appText(
                                11,
                                color: muted,
                                weight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ...debtors.map(
                              (p) => Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF7F8FB),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: lineColor),
                                ),
                                child: InkWell(
                                  onTap: () =>
                                      open(context, PartyDetail(id: p['id'])),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${p['name']}',
                                              style: appText(
                                                14,
                                                weight: FontWeight.w800,
                                              ),
                                            ),
                                            if ('${p['paymentSchedule'] ?? ''}'
                                                .isNotEmpty)
                                              Text(
                                                '${p['paymentSchedule']}',
                                                style: appText(
                                                  11,
                                                  color: muted,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Column(
                                        children: [
                                          amount(
                                            ((p['balance'] as num?) ?? 0).abs(),
                                            size: 16,
                                            color: ((p['balance'] as num?) ?? 0) < 0
                                                ? green : orange,
                                          ),
                                          Text(
                                            customerBalanceStatus(
                                              (p['balance'] as num?) ?? 0,
                                            ),
                                            style: appText(10,
                                                color: ((p['balance'] as num?) ?? 0) < 0
                                                    ? green : muted),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (recent.isEmpty)
                      Empty(
                        'لا توجد حركات بعد',
                        'ابدأ بإضافة زبون، ثم سجّل عليه ديناً أو دفعة. الحركات المزامنة تظهر هنا.',
                        action: OutlinedButton.icon(
                          onPressed: () =>
                              open(context, const PartyForm(supplier: false)),
                          icon: const Icon(Icons.person_add_alt),
                          label: const Text('إضافة زبون'),
                        ),
                      )
                    else
                      Surface(
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.receipt_long_outlined,
                                  size: 18,
                                  color: navy,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'آخر حركات الزبائن',
                                    style: appText(14, weight: FontWeight.w800),
                                  ),
                                ),
                                Text(
                                  'تحديث فوري',
                                  style: appText(11, color: muted),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ...recent.map(
                              (e) => entryTile(
                                Map<String, dynamic>.from(e),
                                name: data['names'][e['partyId']],
                                onConfirm: () => Receipts.confirmTransfer(
                                  context,
                                  Map<String, dynamic>.from(e),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

Widget headerAction(IconData icon, String tooltip, VoidCallback onTap) =>
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Center(
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .14),
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(12),
          ),
          child: IconButton(
            tooltip: tooltip,
            onPressed: onTap,
            icon: Icon(icon, size: 21, color: Colors.white),
            padding: EdgeInsets.zero,
          ),
        ),
      ),
    );

class BalanceBox extends StatelessWidget {
  const BalanceBox(
    this.label,
    this.value,
    this.icon,
    this.caption,
    this.accent, {
    super.key,
  });
  final String label, caption;
  final dynamic value;
  final IconData icon;
  final Color accent;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: lavender,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0xFFD5DAF3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: appText(12))),
            Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 14, color: accent),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FittedBox(child: amount(value, size: 30)),
        ),
        const SizedBox(height: 14),
        Text(
          '• $caption',
          style: appText(10, color: secondaryText, weight: FontWeight.w600),
        ),
      ],
    ),
  );
}

class ShopDrawer extends StatelessWidget {
  const ShopDrawer({super.key});
  @override
  Widget build(BuildContext context) {
    final s = Scope.of(context);
    void go(Widget child) {
      Navigator.pop(context);
      open(context, child);
    }

    Widget tile(
      String title,
      String subtitle,
      IconData icon,
      VoidCallback tap, {
      bool featured = false,
    }) => Padding(
      padding: EdgeInsets.only(bottom: featured ? 10 : 4),
      child: Material(
        color: featured ? lavender : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: featured
              ? const BorderSide(color: Color(0xFFD5DAF3))
              : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: tap,
          child: Padding(
            padding: EdgeInsets.all(featured ? 14 : 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: featured ? Colors.white : const Color(0xFFF7F8FB),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: lineColor),
                  ),
                  child: Icon(icon, color: navy, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: appText(14, weight: FontWeight.w800)),
                      Text(
                        subtitle,
                        style: appText(
                          11,
                          color: muted,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Drawer(
      width: MediaQuery.sizeOf(context).width.clamp(0, 480) * .86,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: navy,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      s.shopName.characters.first,
                      style: appText(
                        26,
                        weight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.shopName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: appText(16, weight: FontWeight.w900),
                        ),
                        Text(
                          'المالك: ${s.settings?['ownerName'] ?? ''}',
                          style: appText(12, color: secondaryText),
                        ),
                        Text(
                          'المستخدم الحالي: المالك',
                          style: appText(11, color: navy),
                        ),
                        const SizedBox(height: 4),
                        SoftTag(
                          s.active ? 'تطبيق دفتر دين نشط ✓' : 'بانتظار التجديد',
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'إغلاق القائمة',
                    icon: const Icon(
                      Icons.close,
                      size: 18,
                      color: secondaryText,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Divider(height: 1),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  tile(
                    'الاشتراك والتجديد',
                    '${s.isTrial ? 'تجربة مجانية' : 'اشتراك المحل'} · حتى ${day(s.status?['paidUntil'])}',
                    Icons.credit_card_outlined,
                    () => go(const SubscriptionScreen()),
                    featured: true,
                  ),
                  if (s.isOwner)
                    tile(
                      'العاملون',
                      'إدارة الفريق والتبديل وقت الدوام',
                      Icons.people_alt_outlined,
                      () => go(const WorkersScreen()),
                      featured: true,
                    ),
                  const SizedBox(height: 14),
                  tile(
                    'الملف الشخصي وإعدادات المحل',
                    'اسم المتجر، الهواتف، إعدادات الحساب',
                    Icons.settings_outlined,
                    () => go(const SettingsScreen()),
                  ),
                  tile(
                    'الحفظ والنسخ الاحتياطي',
                    'فحص وحماية بيانات دفتر دين',
                    Icons.cloud_outlined,
                    () => go(const BackupScreen()),
                  ),
                  tile(
                    'التقارير وكشوف الحسابات',
                    'طباعة وتصدير الحركات',
                    Icons.bar_chart_rounded,
                    () => go(const HistoryScreen()),
                  ),
                  tile(
                    'تصدير نسخة احتياطية محلية',
                    'تنزيل نسخة محلية (.json)',
                    Icons.download_outlined,
                    () async {
                      try {
                        final data = await s.api.get('/api/backup/export');
                        if (context.mounted) {
                          await Exports.backup(data, context);
                        }
                      } catch (e) {
                        if (context.mounted) message(context, e);
                      }
                    },
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                border: Border(top: BorderSide(color: lineColor)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DesignButton(
                    'تسجيل الخروج / تبديل الحساب',
                    background: paleOrange,
                    foreground: orange,
                    onTap: () async {
                      if (!await confirm(
                        context,
                        'تسجيل الخروج',
                        'سيتم تسجيل الخروج من جميع الأجهزة. هل تريد المتابعة؟',
                      )) {
                        return;
                      }
                      try {
                        await s.api.logout();
                      } catch (e) {
                        if (context.mounted) message(context, e);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'تطبيق دفتر دين v1.2.1 · حفظ ومزامنة البيانات',
                    textAlign: TextAlign.center,
                    style: appText(10, color: muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
