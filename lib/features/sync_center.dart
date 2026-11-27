import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../ui/widgets.dart';

/// Local queue is not an accounting ledger. These items only affect server
/// balances when synchronization is confirmed by the backend.
class SyncCenterScreen extends StatefulWidget {
  const SyncCenterScreen({super.key});

  @override
  State<SyncCenterScreen> createState() => _SyncCenterScreenState();
}

class _SyncCenterScreenState extends State<SyncCenterScreen> {
  Future<List<Json>>? future;
  Session? _session;
  int _revision = -1;

  Future<List<Json>> load() async {
    final session = Scope.of(context);
    final api = session.api;
    return [
      ...await api.currentOutbox(),
      ...await api.pendingWorkerDeletes(),
      ...await api.pendingWorkerRenames(),
      ...await api.pendingCatalog(),
    ];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = Scope.of(context);
    if (session != _session) {
      _session?.removeListener(_onSessionChanged);
      _session = session;
      _revision = session.revision;
      session.addListener(_onSessionChanged);
    }
    future ??= load();
  }

  void _onSessionChanged() {
    if (!mounted || _session == null || _revision == _session!.revision) return;
    _revision = _session!.revision;
    setState(() { future = load(); });
  }

  @override
  void dispose() {
    _session?.removeListener(_onSessionChanged);
    super.dispose();
  }

  Future<void> synchronize() async {
    final session = Scope.of(context);
    final sent = await session.synchronize();
    if (!mounted) return;
    setState(() {
      future = load();
    });
    message(
      context,
      session.syncError ??
          (sent > 0
              ? 'تمت مزامنة $sent عملية'
              : session.pendingSync > 0
                  ? 'توجد عمليات ما زالت بانتظار المزامنة'
                  : 'لا توجد عمليات جديدة للمزامنة'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = Scope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('مركز المزامنة')),
      body: Width(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Heading('العمليات المحفوظة على الجهاز'),
            const Text(
              'تظهر الحركات المالية المعلقة في السجل المحلي فقط حتى تأكيد الخادم. طلبات حذف العاملين لا تصبح نافذة على الأجهزة الأخرى إلا بعد المزامنة.',
            ),
            FutureBuilder<int>(
              future: session.api.legacyPendingCount(),
              builder: (context, snapshot) => (snapshot.data ?? 0) > 0
                  ? Text('توجد ${snapshot.data} حركة من إصدار قديم بلا هوية مؤكدة. محفوظة دون إرسال؛ تواصل مع الدعم لمراجعتها.', style: const TextStyle(color: Colors.red))
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),
            BusyButton(
              label: session.syncing ? 'تجري المزامنة' : 'مزامنة الآن',
              icon: Icons.sync,
              busy: session.syncing,
              onPressed: synchronize,
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<Json>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Empty(
                    'تعذّر قراءة الحركات المحلية',
                    '${snapshot.error}',
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final records = snapshot.data!;
                if (records.isEmpty) {
                  return const Empty(
                    'كل العمليات متزامنة',
                    'لا توجد عمليات محفوظة على الجهاز بانتظار الإرسال.',
                    icon: Icons.cloud_done_outlined,
                  );
                }
                return Column(
                  children: [
                    for (final record in records)
                      if (record['kind'] == 'CatalogMutation')
                        Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Text('بيانات المحل: ${record['method']} — ${record['collection']}'),
                          Text('${(record['body'] as Map)['name'] ?? record['entityId']}'),
                          Text('تاريخ التسجيل: ${day(record['savedAt'])}'),
                          Text(record['lastError'] == null ? 'بانتظار المزامنة' : 'تحتاج مراجعة: ${record['lastError']}'),
                          if (record['lastError'] != null) ...[
                            const Text('العملية محفوظة؛ لم تُعتمد على الخادم. لا تحذف التطبيق.'),
                            TextButton(onPressed:session.syncing ? null : () async {
                              final sure = await confirm(context,'إلغاء الطلب المرفوض','لن يتم إرسال هذا التعديل المحلي. هل تريد الإلغاء؟');
                              if (!sure || !context.mounted) return;
                              try { await session.api.discardRejectedCatalog('${record['operationId']}'); await session.updatePending(); }
                              catch(e) { if(context.mounted) message(context,e); }
                            },child:const Text('إلغاء الطلب المرفوض')),
                          ],
                        ]))
                      else if (record['kind'] == 'WorkerRename')
                        Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Text('تعديل اسم عامل: ${record['workerName'] ?? ''}'),
                          Text(record['lastError'] == null ? 'بانتظار المزامنة' : '${record['lastError']}'),
                          if (record['lastError'] != null) TextButton(onPressed: session.syncing ? null : () async {
                            final sure = await confirm(context, 'إلغاء التعديل المحلي', 'سيبقى اسم العامل الموجود على الخادم. هل تريد الإلغاء؟');
                            if (!sure || !context.mounted) return;
                            try { await session.api.discardWorkerRename('${record['workerId']}'); await session.updatePending(); }
                            catch (e) { if (context.mounted) message(context, '$e'); }
                          }, child: const Text('إلغاء التعديل المحلي')),
                        ]))
                      else if (record['kind'] == 'WorkerDelete')
                        Surface(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('حذف عامل: ${record['workerName'] ?? ''}',
                                style: Theme.of(context).textTheme.titleMedium),
                            Text('تاريخ التسجيل: ${day(record['savedAt'])}'),
                            const Text('الحالة: بانتظار تأكيد الخادم'),
                            if (record['lastError'] != null)
                              Text('${record['lastError']}', style: const TextStyle(color: Colors.red)),
                          ],
                        ))
                      else Surface(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              kinds[(record['body'] as Map)['kind']] ??
                                  'حركة مالية',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            amount((record['body'] as Map)['amount']),
                            Text('تاريخ التسجيل: ${day(record['savedAt'])}'),
                            if (record['blocked'] == true) ...[
                              const Text(
                                'الحالة: تحتاج مراجعة — الخادم رفض الحركة',
                                style: TextStyle(color: Colors.red),
                              ),
                              if (record['lastError'] != null)
                                Text('${record['lastError']}'),
                              TextButton.icon(
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('حذف الحركة بعد التحقق'),
                                onPressed: () async {
                                  final sure = await confirm(
                                    context,
                                    'حذف حركة مرفوضة',
                                    'تحقق من كشف الحساب أولاً. هل تريد حذف السجل المحلي للحركة المرفوضة؟',
                                  );
                                  if (!sure || !context.mounted) return;
                                  final session = Scope.of(context);
                                  final api = session.api;
                                  await api.offlineVault.removeTransaction(
                                    api.savedShopId,
                                    '${record['operationId']}',
                                  );
                                  await session.updatePending();
                                  if (mounted) setState(() {
                                    future = load();
                                  });
                                },
                              ),
                            ] else
                              const Text('الحالة: بانتظار تأكيد الخادم'),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
            if (session.syncError != null)
              Surface(child: Text('آخر محاولة: ${session.syncError}')),
            const Text(
              'تُحفظ الحركات على الجهاز عند انقطاع الإنترنت. تعود المزامنة تلقائياً عند رجوع الاتصال، وعند فتح التطبيق أو رجوعه للواجهة، مع إعادة محاولة دورية أثناء الاستخدام. ويمكنك الضغط على «مزامنة الآن».',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
