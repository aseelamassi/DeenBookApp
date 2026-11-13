/// Deterministic, read-only presentation of locally durable financial entries.
/// These entries are NOT server-confirmed. The operationId travels unchanged
/// on every retry; never fabricate a server entry ID.
class OfflineProjection {
  static Map<String, dynamic> entry(Map<String, dynamic> body) {
    final kind = '${body['kind'] ?? ''}';
    final amount = (body['amount'] as num? ?? 0).toDouble();
    final discount = (body['discount'] as num? ?? 0).toDouble();
    final paid = (body['paidNow'] as num? ?? 0).toDouble();
    final waiting = body['pendingConfirmation'] == true;
    final delta = waiting ? 0.0 : switch (kind) {
      'Debt' || 'Purchase' => amount - discount - paid,
      'Payment' || 'Return' => -amount,
      _ => 0.0,
    };
    return {
      ...body,
      'id': 'local:${body['operationId']}',
      'delta': delta,
      'offlinePending': true,
      'createdByName': 'محفوظ محليًا — بانتظار المزامنة',
      'occurredAt': body['occurredAt'] ?? DateTime.now().toUtc().toIso8601String(),
      'items': body['items'] ?? [],
    };
  }

  static List<Map<String, dynamic>> pendingEntries(List<Map<String, dynamic>> outbox) => [
    for (final record in outbox)
      if (record['body'] is Map)
        {
          ...entry(Map<String, dynamic>.from(record['body'] as Map)),
          if (record['blocked'] == true) ...{
            'offlineBlocked': true,
            // A rejected operation is retained for review, but must not be
            // presented as an accepted financial balance adjustment.
            'delta': 0.0,
          },
        },
  ];

  static num partyDelta(String partyId, List<Map<String, dynamic>> pending) =>
      pending.where((e) => '${e['partyId']}' == partyId)
          .fold<double>(0, (total, e) => total + (e['delta'] as num? ?? 0).toDouble());

  static bool isInsideDate(Map<String, dynamic> entry, Map<String, dynamic>? query) {
    if (query == null) return true;
    final timestamp = DateTime.tryParse('${entry['occurredAt'] ?? ''}');
    if (timestamp == null) return true;
    final local = timestamp.toLocal();
    final from = DateTime.tryParse('${query['from'] ?? ''}');
    final to = DateTime.tryParse('${query['to'] ?? ''}');
    if (from != null && local.isBefore(DateTime(from.year, from.month, from.day))) return false;
    if (to != null && !local.isBefore(DateTime(to.year, to.month, to.day + 1))) return false;
    return true;
  }

  static Map<String, dynamic> transactionList(
    Map<String, dynamic> base,
    List<Map<String, dynamic>> pending,
    Map<String, dynamic>? query,
    Map<String, String> partyKinds,
  ) {
    final selected = pending.where((e) {
      if (!isInsideDate(e, query)) return false;
      if (query?['kind'] != null && '${query!['kind']}' != '${e['kind']}') return false;
      if (query?['partyId'] != null && '${query!['partyId']}' != '${e['partyId']}') return false;
      if (query?['pending'] == true && e['pendingConfirmation'] != true) return false;
      final selectedKind = '${query?['partyKind'] ?? ''}';
      if (selectedKind.isNotEmpty) {
        final actual = partyKinds['${e['partyId']}'] ??
            (e['kind'] == 'Purchase' ? 'Supplier' : e['kind'] == 'Debt' ? 'Customer' : '');
        if (actual != selectedKind) return false;
      }
      return true;
    }).toList();
    final normal = (base['items'] as List? ?? []).whereType<Map>().map(
      (item) => Map<String, dynamic>.from(item),
    ).toList();
    final ids = normal.map((e) => '${e['operationId'] ?? ''}').toSet();
    final added = selected.where((e) => !ids.contains('${e['operationId']}')).toList();
    final page = (query?['page'] as num?)?.toInt() ?? 1;
    final size = (query?['size'] as num?)?.toInt() ?? 30;
    final fromIndex = base['offlinePartial'] == true;
    final combined = [...(page == 1 || fromIndex ? added.reversed : <Map<String, dynamic>>[]), ...normal];
    return {
      ...base,
      'items': fromIndex ? combined.skip((page - 1) * size).take(size).toList() : combined,
      'total': (base['total'] as num? ?? normal.length).toInt() + added.length,
      'localPendingCount': added.length,
    };
  }

  static Map<String, dynamic> statement(
    Map<String, dynamic> base, String partyId, List<Map<String, dynamic>> pending,
    Map<String, dynamic>? query,
  ) {
    final entries = (base['entries'] as List? ?? []).whereType<Map>().map(
      (e) => Map<String, dynamic>.from(e),
    ).toList();
    final existingOperations = entries.map((e) => '${e['operationId'] ?? ''}').toSet();
    final added = pending.where((e) =>
        '${e['partyId']}' == partyId && isInsideDate(e, query) &&
        !existingOperations.contains('${e['operationId']}')).toList();
    final combined = [...entries, ...added];
    final balance = (base['currentBalance'] as num? ?? base['balance'] as num? ?? 0).toDouble();
    return {
      ...base,
      'entries': combined,
      'currentBalance': balance + added.fold<double>(0, (a, e) => a + (e['delta'] as num? ?? 0).toDouble()),
      'closingBalance': (base['closingBalance'] as num? ?? balance) +
          added.fold<double>(0, (a, e) => a + (e['delta'] as num? ?? 0).toDouble()),
      'localPendingCount': added.length,
    };
  }
}
