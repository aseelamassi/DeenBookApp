/// Advisory customer debt threshold. Null or zero means an unlimited account.
/// These values are display-only; the backend never blocks a transaction.
enum CreditLimitLevel { unlimited, normal, near, exceeded }

class CreditLimitStatus {
  const CreditLimitStatus({
    required this.limit,
    required this.debt,
    required this.level,
  });

  final double? limit;
  final double debt;
  final CreditLimitLevel level;

  double get used => debt > 0 ? debt : 0;
  double get remaining => limit == null ? 0 : (limit! - used).clamp(0, limit!).toDouble();
  double get excess => limit == null ? 0 : (used - limit!).clamp(0, double.infinity).toDouble();
  int get percent => limit == null ? 0 : (used / limit! * 100).round();
  double get progress => limit == null ? 0 : (used / limit!).clamp(0, 1).toDouble();
  bool get needsWarning => level == CreditLimitLevel.near || level == CreditLimitLevel.exceeded;
  String get label => switch (level) {
    CreditLimitLevel.unlimited => 'حساب مفتوح (بلا سقف)',
    CreditLimitLevel.normal => 'ضمن سقف الدين',
    CreditLimitLevel.near => 'اقترب من السقف 🔴',
    CreditLimitLevel.exceeded => 'تجاوز سقف الدين ⚠️',
  };
}

CreditLimitStatus creditLimitStatus(num balance, dynamic rawLimit) {
  final limit = rawLimit is num ? rawLimit.toDouble() : double.tryParse('$rawLimit');
  final debt = balance.toDouble();
  if (limit == null || !limit.isFinite || limit <= 0) {
    return CreditLimitStatus(limit: null, debt: debt, level: CreditLimitLevel.unlimited);
  }
  return CreditLimitStatus(
    limit: limit,
    debt: debt,
    level: debt >= limit
        ? CreditLimitLevel.exceeded
        : debt >= limit * .8
        ? CreditLimitLevel.near
        : CreditLimitLevel.normal,
  );
}
