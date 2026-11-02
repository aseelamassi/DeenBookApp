import 'dart:async';
import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/session.dart';
import '../services/receipts.dart';
import '../ui/theme.dart';
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
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Scope.of(context).synchronize();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      Scope.of(context).synchronize();
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
          toolbarHeight: 76,
          leading: Builder(
            builder: (c) => IconButton(
              tooltip: 'البروفايل',
              onPressed: () => Scaffold.of(c).openDrawer(),
              icon: const CircleAvatar(
                backgroundColor: orange,
                child: Icon(Icons.person_outline, color: Colors.white),
              ),
            ),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.shopName,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                session.settings?['ownerName'] ?? 'دفتر الأمانة',
                style: TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'مزامنة البيانات',
              onPressed: session.syncing ? null : () async {
                final count = await session.synchronize();
                if (context.mounted) {
                  message(context, session.syncError ??
                      (count > 0 ? 'تمت مزامنة $count حركة بنجاح' :
                      'لا توجد حركات جديدة للمزامنة'));
                }
              },
              icon: session.syncing
                  ? const SizedBox(width: 19, height: 19,
                      child: CircularProgressIndicator(strokeWidth: 2,
                          color: Colors.white))
                  : Icon(session.isOffline ? Icons.cloud_off_outlined :
                      Icons.sync_rounded),
            ),
            IconButton(
              tooltip: 'حركة بصوتك',
              onPressed: () =>
                  open(context, const TransactionScreen(voice: true)),
              icon: const Icon(Icons.mic_none),
            ),
            IconButton(
              tooltip: 'التقارير الشهرية',
              onPressed: () => open(context, const ReportsScreen()),
              icon: const Icon(Icons.bar_chart_rounded),
            ),
            const SizedBox(width: 6),
          ],
        ),
        drawer: Drawer(
          child: SafeArea(
            child: ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const CircleAvatar(
                        radius: 28,
                        child: Icon(Icons.storefront, size: 30),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        session.shopName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Text(
                        'إدارة المحل والحساب',
                        style: TextStyle(color: muted),
                      ),
                    ],
                  ),
                ),
                ...[
                  (
                    'بيانات المحل',
                    Icons.storefront_outlined,
                    const SettingsScreen(),
                  ),
                  (
                    'الاشتراكات والتجديد',
                    Icons.workspace_premium_outlined,
                    const SubscriptionScreen(),
                  ),
                  ('العاملون', Icons.badge_outlined, const WorkersScreen()),
                  ('التقارير', Icons.bar_chart_rounded, const ReportsScreen()),
                  (
                    'سجل المشتريات والمدفوعات',
                    Icons.receipt_long_outlined,
                    const HistoryScreen(),
                  ),
                  (
                    'النسخ الاحتياطي',
                    Icons.cloud_download_outlined,
                    const BackupScreen(),
                  ),
                  (
                    'تغيير كلمة المرور',
                    Icons.lock_outline,
                    const PasswordScreen(),
                  ),
                ].map(
                  (item) => ListTile(
                    leading: Icon(item.$2),
                    title: Text(item.$1),
                    onTap: () {
                      Navigator.pop(context);
                      open(context, item.$3);
                    },
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.sync_outlined),
                  title: const Text('مركز المزامنة'),
                  subtitle: Text(session.pendingSync == 0
                      ? 'لا توجد حركات بانتظار الإرسال'
                      : '${session.pendingSync} حركة محفوظة على الجهاز'),
                  onTap: () {
                    Navigator.pop(context);
                    open(context, const SyncCenterScreen());
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('تسجيل الخروج'),
                  onTap: () async {
                    Navigator.pop(context);
                    if (!await confirm(
                      context,
                      'تسجيل الخروج',
                      'سيتم إنهاء جلسات هذا الحساب على جميع الأجهزة. هل تريد المتابعة؟',
                    )) {
                      return;
                    }
                    try {
                      await session.api.logout();
                    } catch (e) {
                      if (context.mounted) message(context, e);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (session.isOffline || session.pendingSync > 0)
                Material(
                  color: session.isOffline
                      ? const Color(0xFFFFF0DF)
                      : const Color(0xFFEEF5FF),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Icon(session.isOffline ? Icons.cloud_off_outlined :
                            Icons.cloud_upload_outlined, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(session.isOffline
                            ? 'وضع دون إنترنت: المعروض من آخر تحميل. ${session.pendingSync} حركة تنتظر المزامنة.'
                            : '${session.pendingSync} حركة محفوظة بانتظار المزامنة.',
                            style: const TextStyle(fontSize: 12))),
                        TextButton(onPressed: () => open(context,
                            const SyncCenterScreen()), child: const Text('التفاصيل')),
                      ],
                    ),
                  ),
                ),
              if (session.isTrial)
                Material(
                  color: const Color(0xFFEAF6ED),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    child: Row(children: [
                      const Icon(Icons.workspace_premium_outlined, size: 18),
                      const SizedBox(width: 7),
                      Expanded(child: Text(
                        'تجربة مجانية: متبقي ${session.trialDaysRemaining} يوم',
                        style: const TextStyle(fontSize: 12))),
                      TextButton(onPressed: () => open(context,
                          const SubscriptionScreen()),
                          child: const Text('الاشتراك')),
                    ]),
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
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        floatingActionButton: FloatingActionButton(
          backgroundColor: orange,
          elevation: 0,
          highlightElevation: 0,
          shape: const CircleBorder(side: BorderSide(color: canvas, width: 4)),
          foregroundColor: Colors.white,
          tooltip: 'إضافة حركة',
          onPressed: () => quickAction(context),
          child: const Icon(Icons.add, size: 32),
        ),
        bottomNavigationBar: BottomAppBar(
          height: 76,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          notchMargin: 7,
          shape: const CircularNotchedRectangle(),
          child: Row(
            children: [
              nav(0, 'الرئيسية', Icons.home_outlined),
              nav(1, 'الزبائن', Icons.people_outline),
              const SizedBox(width: 58),
              nav(2, 'الموردون', Icons.local_shipping_outlined),
              nav(3, 'الأصناف', Icons.inventory_2_outlined),
            ],
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
            Icon(icon, color: tab == i ? orange : muted, size: 23),
            const SizedBox(height: 4),
            FittedBox(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 11,
                  color: tab == i ? navy : muted,
                  fontWeight: tab == i ? FontWeight.bold : FontWeight.normal,
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
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 36),
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
                final s = data['summary'] as Map;
                final recent = data['recent'] as List;
                return Column(
                  children: [
                    Surface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ملخص الذمم المالية',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: metric(
                                  'مستحق على الزبائن',
                                  s['receivables'],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: metric(
                                  'مستحق للموردين',
                                  s['payables'],
                                  color: orange,
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
                          child: BusyButton(
                            label: 'تسجيل دين',
                            background: orange,
                            icon: Icons.add,
                            onPressed: () =>
                                open(context, const TransactionScreen()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => open(
                              context,
                              const TransactionScreen(kind: 'Payment'),
                            ),
                            icon: const Icon(Icons.payments_outlined),
                            label: const Text('تسجيل دفعة'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: onCustomers,
                        icon: const Icon(Icons.people_outline),
                        label: const Text('عرض حسابات الزبائن'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Heading('آخر حركات الزبائن'),
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
                          children: recent
                              .map(
                                (e) => entryTile(
                                  Map<String, dynamic>.from(e),
                                  name: data['names'][e['partyId']],
                                  onConfirm: () => Receipts.confirmTransfer(
                                    context,
                                    Map<String, dynamic>.from(e),
                                  ),
                                ),
                              )
                              .toList(),
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
