/// Elapsed 24-hour days, bounded by the server policy and subscription.
class OfflineGrace {
  const OfflineGrace(this.verifiedAt, this.now, {this.clockUntrusted = false,
    this.days = 7, this.paidUntil});
  final DateTime? verifiedAt;
  final DateTime now;
  final bool clockUntrusted;
  final int days;
  final DateTime? paidUntil;
  static const maximum = Duration(days: 7);
  int get limitDays => days.clamp(1, 7).toInt();
  static int parseDays(Object? value) => value is int && value >= 1 && value <= 7 ? value : 7;
  Duration? get elapsed => verifiedAt == null ? null : now.toUtc().difference(verifiedAt!.toUtc());
  bool get expired {
    final age = elapsed;
    return clockUntrusted || age == null || age.isNegative ||
        !now.toUtc().isBefore(expiresAt!);
  }
  int? get reminderDay {
    final age = elapsed;
    if (age == null || age.isNegative) return null;
    if (expired) return limitDays;
    if (age.inDays < (limitDays - 2).clamp(1, 7)) return null;
    return age.inDays;
  }
  DateTime? get expiresAt {
    final expiry = verifiedAt?.toUtc().add(Duration(days: limitDays));
    if (expiry != null && paidUntil != null && paidUntil!.isBefore(expiry)) return paidUntil!.toUtc();
    return expiry;
  }
}
