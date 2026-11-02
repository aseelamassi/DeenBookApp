import 'dart:convert';

import 'storage.dart';

/// Encrypted local snapshots and a durable, shop-scoped transaction outbox.
/// The Storage implementation uses Android/iOS secure storage; this is NOT
/// a server-authoritative balance or a replacement for online validation.
class OfflineVault {
  OfflineVault(this.storage);
  final Storage storage;
  Future<void> _serial = Future.value();

  Future<void> _locked(Future<void> Function() action) {
    final next = _serial.catchError((_) {}).then((_) => action());
    _serial = next;
    return next;
  }

  String _snapshotKey(String shopId, String path, Map<String, dynamic>? query) {
    final parameters = query == null ? <String, dynamic>{} : Map<String, dynamic>.from(query);
    final keys = parameters.keys.toList()..sort();
    final normalized = {for (final key in keys) key: parameters[key]};
    final encoded = base64Url.encode(utf8.encode('$path|${jsonEncode(normalized)}'));
    return 'snapshot.$shopId.$encoded';
  }

  Future<void> saveSnapshot(String shopId, String path, Map<String, dynamic>? query,
      dynamic response) async {
    if (shopId.isEmpty) return;
    await storage.write(_snapshotKey(shopId, path, query), jsonEncode(response));
  }

  Future<dynamic> readSnapshot(String shopId, String path,
      Map<String, dynamic>? query) async {
    if (shopId.isEmpty) return null;
    final json = await storage.read(_snapshotKey(shopId, path, query));
    if (json == null) return null;
    return jsonDecode(json);
  }

  String _outboxKey(String shopId) => 'outbox.$shopId';

  Future<List<Map<String, dynamic>>> readOutbox(String shopId) async {
    if (shopId.isEmpty) return [];
    final raw = await storage.read(_outboxKey(shopId));
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> addTransaction(String shopId, Map<String, dynamic> body) =>
      _locked(() async {
        if (shopId.isEmpty || '${body['operationId'] ?? ''}'.isEmpty) {
          throw StateError('لا يمكن حفظ حركة دون محل ومعرّف عملية');
        }
        final records = await readOutbox(shopId);
        final id = '${body['operationId']}';
        final existing = records.where((e) => e['operationId'] == id);
        if (existing.isNotEmpty) {
          if (jsonEncode(existing.first['body']) != jsonEncode(body)) {
            throw StateError('معرّف العملية مرتبط بمحتوى مختلف');
          }
          return;
        }
        records.add({
          'operationId': id,
          'savedAt': DateTime.now().toUtc().toIso8601String(),
          'body': body,
        });
        await storage.write(_outboxKey(shopId), jsonEncode(records));
      });

  Future<void> blockTransaction(String shopId, String operationId,
      String error) => _locked(() async {
        final records = await readOutbox(shopId);
        for (final record in records) {
          if (record['operationId'] == operationId) {
            record['blocked'] = true;
            record['lastError'] = error;
          }
        }
        await storage.write(_outboxKey(shopId), jsonEncode(records));
      });

  Future<void> removeTransaction(String shopId, String operationId) =>
      _locked(() async {
        final records = await readOutbox(shopId);
        records.removeWhere((record) => record['operationId'] == operationId);
        await storage.write(_outboxKey(shopId), jsonEncode(records));
      });
}
