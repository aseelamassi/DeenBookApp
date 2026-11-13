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

  Future<List<Json>> load() async {
    final session = Scope.of(context);
    final api = session.api;
    return api.offlineVault.readOutbox(api.savedShopId);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    future ??= load();
  }

  Future<void> synchronize() async {
    final session = Scope.of(context);
    final sent = await session.synchronize();
    if (!mounted) return;
    setState(() => future = load());
    message(
      context,
      session.syncError ??
          (sent > 0
              ? 'تم إرسال $sent حركة وتأكيد حفظها'
              : 'لا توجد حركات جديدة للمزامنة'),
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
            const Heading('الحركات المحفوظة على الجهاز'),
            const Text(
              'هذه الحركات محفوظة على الجهاز وتظهر في سجل الحساب والرصيد المحلي، لكنها لم تُؤكّد على الخادم بعد. لا تدخل في التقارير السحابية حتى تكتمل المزامنة.',
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
                    'كل الحركات متزامنة',
                    'لا توجد حركات محفوظة على الجهاز بانتظار الإرسال.',
                    icon: Icons.cloud_done_outlined,
                  );
                }
                return Column(
                  children: [
                    for (final record in records)
                      Surface(
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
                                  if (mounted) setState(() => future = load());
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
              'عند انقطاع الإنترنت تعود المزامنة للمحاولة تلقائياً عند فتح التطبيق أو رجوعه للواجهة، وضمن محاولات دورية أثناء الاستخدام.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
