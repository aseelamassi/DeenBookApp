import 'package:flutter/material.dart';

import '../core/session.dart';
import '../ui/widgets.dart';

/// Exports are based on server records only; an outbox pending sync does not
/// invalidate already confirmed server transactions. Never silently mix the
/// local outbox into the authoritative financial report.
class ReportExportGuard {
  const ReportExportGuard._();

  static bool available({
    required bool loading,
    required bool exporting,
    required String? error,
  }) => !loading && !exporting && error == null;

  static String pendingNotice(int count) =>
      'تنبيه: هناك $count حركة محفوظة على الجهاز بانتظار المزامنة؛ '
      'هذه الحركات غير مشمولة في هذا التقرير. الأرقام تخص بيانات الخادم فقط.';

  static Future<bool> confirmServerOnly(
    BuildContext context,
    Session session,
  ) async {
    if (session.isOffline) {
      message(
        context,
        'التصدير يحتاج اتصالاً بالخادم لجلب جميع الحركات. '
        'اتصل بالإنترنت ثم حدّث التقرير. الحركات غير المتزامنة محفوظة على الجهاز.',
      );
      return false;
    }
    if (session.pendingSync == 0) return true;
    return confirm(
      context,
      'تصدير بيانات الخادم فقط',
      '${pendingNotice(session.pendingSync)}\n\n'
      'يمكنك المتابعة بطباعة أو مشاركة الحركات المتزامنة فقط، '
      'أو الإلغاء ومزامنة الحركات أولاً.',
    );
  }
}
