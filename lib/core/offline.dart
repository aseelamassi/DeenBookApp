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
    final parameters = query == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(query);
    final keys = parameters.keys.toList()..sort();
    final normalized = {for (final key in keys) key: parameters[key]};
    final encoded = base64Url.encode(
      utf8.encode('$path|${jsonEncode(normalized)}'),
    );
    return 'snapshot.$shopId.$encoded';
  }

  Future<void> saveSnapshot(
    String shopId,
    String path,
    Map<String, dynamic>? query,
    dynamic response,
  ) async {
    if (shopId.isEmpty) return;
    await storage.write(
      _snapshotKey(shopId, path, query),
      jsonEncode(response),
    );
  }

  Future<dynamic> readSnapshot(
    String shopId,
    String path,
    Map<String, dynamic>? query,
  ) async {
    if (shopId.isEmpty) return null;
    final json = await storage.read(_snapshotKey(shopId, path, query));
    if (json == null) return null;
    return jsonDecode(json);
  }


  // Keep a filtered-query-independent, shop-isolated local index for listing
  // screens. Individual GET snapshots still represent the exact server query.
  String _collectionKey(String shopId, String path) =>
      'offline.collection.$shopId.${base64Url.encode(utf8.encode(path))}';

  bool _indexed(String path) => const {
    '/api/customers', '/api/suppliers', '/api/products', '/api/transactions',
  }.contains(path);

  Future<void> indexResponse(
    String shopId, String path, Map<String, dynamic>? query, dynamic response,
  ) async {
    if (shopId.isEmpty || !_indexed(path) || response is! Map || response['items'] is! List) return;
    final key = _collectionKey(shopId, path);
    await _locked(() async {
      final existing = await storage.read(key);
      final records = existing == null
          ? <Map<String, dynamic>>[]
          : (jsonDecode(existing) as List)
              .map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final values = (response['items'] as List)
          .whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      // Retain previously downloaded pages, never replace an entire catalog
      // because a search returned one matching record.
      for (final value in values) {
        final index = records.indexWhere((r) => '${r['id']}' == '${value['id']}');
        if (index < 0) {
          records.add(value);
        } else {
          records[index] = value;
        }
      }
      await storage.write(key, jsonEncode(records));
    });
  }

  Future<List<Map<String, dynamic>>> indexedItems(String shopId, String path) async {
    if (shopId.isEmpty || !_indexed(path)) return [];
    final raw = await storage.read(_collectionKey(shopId, path));
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>?> findParty(String shopId, String id) async {
    for (final path in ['/api/customers', '/api/suppliers']) {
      for (final party in await indexedItems(shopId, path)) {
        if ('${party['id']}' == id) {
          return {...party, 'kind': path == '/api/customers' ? 'Customer' : 'Supplier'};
        }
      }
    }
    return null;
  }

  Future<Map<String, String>> partyKinds(String shopId) async {
    final result = <String, String>{};
    for (final path in ['/api/customers', '/api/suppliers']) {
      for (final party in await indexedItems(shopId, path)) {
        result['${party['id']}'] = path == '/api/customers' ? 'Customer' : 'Supplier';
      }
    }
    return result;
  }

  Future<dynamic> readBestSnapshot(
    String shopId, String path, Map<String, dynamic>? query,
  ) async {
    final exact = await readSnapshot(shopId, path, query);
    if (exact != null) return exact;
    if (_indexed(path)) {
      final records = await indexedItems(shopId, path);
      if (records.isEmpty) return null;
      final term = '${query?['search'] ?? ''}'.toLowerCase().trim();
      var matches = records.where((r) => term.isEmpty ||
          ['name', 'nickname', 'phone', 'sku'].any((k) =>
            '${r[k] ?? ''}'.toLowerCase().contains(term))).toList();
      final filter = '${query?['filter'] ?? ''}';
      if (filter == 'debt') matches = matches.where((r) => (r['balance'] as num? ?? 0) > 0).toList();
      if (filter == 'credit') matches = matches.where((r) => (r['balance'] as num? ?? 0) < 0).toList();
      if (filter == 'settled') matches = matches.where((r) => (r['balance'] as num? ?? 0) == 0).toList();
      if (query?['category'] != null) {
        matches = matches.where((r) => '${r['category'] ?? ''}' == '${query!['category']}').toList();
      }
      if (path == '/api/transactions') {
        final wantedKind = '${query?['partyKind'] ?? ''}';
        if (wantedKind == 'Customer' || wantedKind == 'Supplier') {
          final partyIndex = await indexedItems(shopId,
              wantedKind == 'Customer' ? '/api/customers' : '/api/suppliers');
          final ids = partyIndex.map((p) => '${p['id']}').toSet();
          matches = matches.where((r) => ids.contains('${r['partyId']}')).toList();
        }
        matches = matches.where((r) {
          if (query?['kind'] != null && r['kind'] != query!['kind']) return false;
          if (query?['partyId'] != null && r['partyId'] != query!['partyId']) return false;
          if (query?['pending'] == true && r['pendingConfirmation'] != true) return false;
          final from = DateTime.tryParse('${query?['from'] ?? ''}');
          final to = DateTime.tryParse('${query?['to'] ?? ''}');
          final occured = DateTime.tryParse('${r['occurredAt'] ?? ''}')?.toLocal();
          if (occured != null && from != null && occured.isBefore(DateTime(from.year,from.month,from.day))) return false;
          if (occured != null && to != null && !occured.isBefore(DateTime(to.year,to.month,to.day+1))) return false;
          return true;
        }).toList();
      }
      if (query?['sort'] == 'name') matches.sort((a,b) => '${a['name'] ?? ''}'.compareTo('${b['name'] ?? ''}'));
      if (query?['sort'] == 'balance') matches.sort((a,b) => (b['balance'] as num? ?? 0).compareTo(a['balance'] as num? ?? 0));
      // Return the full cached index for transaction lists. The projection
      // layer applies paging after inserting the locally pending movements.
      if (path == '/api/transactions') {
        return {'items': matches, 'total': matches.length, 'offlinePartial': true};
      }
      final page = (query?['page'] as num?)?.toInt() ?? 1;
      final size = (query?['size'] as num?)?.toInt() ?? 30;
      return {
        'items': matches.skip((page - 1) * size).take(size).toList(),
        'total': matches.length,
        'offlinePartial': true,
      };
    }
    if (path.startsWith('/api/parties/') && !path.endsWith('/statement')) {
      final id = path.split('/').last;
      return findParty(shopId, id);
    }
    return null;
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

  Future<void> blockTransaction(
    String shopId,
    String operationId,
    String error,
  ) => _locked(() async {
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
