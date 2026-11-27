import 'package:flutter/services.dart';

/// Optional platform notification bridge. The foreground banner and seven-day
/// lock remain effective even when permissions are denied or no bridge exists.
class SyncReminders {
  static const _channel = MethodChannel('deenbook/sync_reminders');
  static Future<void> schedule(DateTime verifiedAt, {int days = 7, DateTime? expiresAt}) async {
    try {
      await _channel.invokeMethod<void>('schedule', {'verified': verifiedAt.millisecondsSinceEpoch, 'days': days, 'expires': expiresAt?.millisecondsSinceEpoch ?? verifiedAt.add(Duration(days: days)).millisecondsSinceEpoch});
    } catch (_) { /* Optional platform service must never block verification. */ }
  }
  static Future<void> cancel() async {
    try { await _channel.invokeMethod<void>('cancel'); }
    catch (_) { /* Platform bridge unavailable. */ }
  }
}
