import 'dart:convert';

import 'storage.dart';
import 'offline_projection.dart';

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
      final byId = {for (final record in records) '${record['id']}': record};
      for (final value in values) { byId['${value['id']}'] = value; }
      await storage.write(key, jsonEncode(byId.values.toList()));
    });
  }

  Future<List<Map<String, dynamic>>> indexedItems(String shopId, String path) async {
    if (shopId.isEmpty || !_indexed(path)) return [];
    final raw = await storage.read(_collectionKey(shopId, path));
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> confirmCatalog(String shopId, String collection, String id, dynamic response, {bool deleted = false}) => _locked(() async {
    final rows = await indexedItems(shopId, collection);
    final matching = rows.where((r) => '${r['id']}' == id);
    final old = matching.isEmpty ? null : matching.first;
    rows.removeWhere((r) => '${r['id']}' == id);
    if (!deleted && response is Map) rows.add({...?old, ...Map<String,dynamic>.from(response)});
    await storage.write(_collectionKey(shopId, collection), jsonEncode(rows));
    await storage.write('catalog.changed.$shopId.$collection', '1');
    if (['/api/customers','/api/suppliers'].contains(collection) && !deleted && response is Map) {
      await saveSnapshot(shopId, '/api/parties/$id', null, response);
    }
  });

  Future<bool> catalogChanged(String shopId, String collection) async =>
      await storage.read('catalog.changed.$shopId.$collection') != null;

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
    final changed = _indexed(path) && await catalogChanged(shopId,path);
    final changedLedger = path.endsWith('/statement') && await catalogChanged(shopId,'/api/transactions');
    if (exact != null && path != '/api/transactions' && !changed && !changedLedger) return exact;
    if (_indexed(path)) {
      final records = await indexedItems(shopId, path);
      if (records.isEmpty && !changed) return exact;
      final term = '${query?['search'] ?? ''}'.toLowerCase().trim();
      var matches = records.where((r) => term.isEmpty ||
          ['name', 'nickname', 'phone', 'sku'].any((k) =>
            '${r[k] ?? ''}'.toLowerCase().contains(term))).toList();
      final filter = '${query?['filter'] ?? ''}';
      if (filter == 'debt' || filter == 'owing') matches = matches.where((r) => (r['balance'] as num? ?? 0) > 0).toList();
      if (filter == 'credit') matches = matches.where((r) => (r['balance'] as num? ?? 0) < 0).toList();
      if (filter == 'settled') matches = matches.where((r) => (r['balance'] as num? ?? 0) == 0).toList();
      if (filter == 'creditLimit' && path == '/api/customers') {
        matches = matches.where((r) {
          final limit = (r['creditLimit'] as num?) ?? 0;
          return limit > 0 && (r['balance'] as num? ?? 0) >= limit * .8;
        }).toList();
      }
      if (filter == 'scheduled') matches = matches.where((r) => '${r[path == '/api/suppliers' ? 'deliveryDays' : 'paymentSchedule'] ?? ''}'.isNotEmpty).toList();
      if (filter == 'today' && path == '/api/suppliers') {
        const ar = ['الاثنين','الثلاثاء','الأربعاء','الخميس','الجمعة','السبت','الأحد'];
        const en = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
        final day = DateTime.now().weekday - 1;
        matches = matches.where((r) => '${r['deliveryDays'] ?? ''}'.contains(ar[day]) || '${r['deliveryDays'] ?? ''}'.contains(en[day])).toList();
      }
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
          if (query?['includeVoided'] != true && r['voidedAt'] != null) return false;
          if (query?['kind'] != null && r['kind'] != query!['kind']) return false;
          if (query?['partyId'] != null && r['partyId'] != query!['partyId']) return false;
          if (query?['pending'] != null && (r['pendingConfirmation'] == true) != query!['pending']) return false;
          return OfflineProjection.isInsideDate(r,query);
        }).toList();
      }
      if (query?['sort'] == 'name') matches.sort((a,b) => '${a['name'] ?? ''}'.compareTo('${b['name'] ?? ''}'));
      if (query?['sort'] == 'balance') matches.sort((a,b) => (b['balance'] as num? ?? 0).compareTo(a['balance'] as num? ?? 0));
      if (query?['sort'] == 'balanceAsc') matches.sort((a,b) => (a['balance'] as num? ?? 0).compareTo(b['balance'] as num? ?? 0));
      if (query?['sort'] == 'recent') matches.sort((a,b) => '${b['lastActivity'] ?? ''}'.compareTo('${a['lastActivity'] ?? ''}'));
      // Return the full cached index for transaction lists. The projection
      // layer applies paging after inserting the locally pending movements.
      if (path == '/api/transactions') {
        matches.sort((a,b) { final c='${b['occurredAt']}'.compareTo('${a['occurredAt']}'); return c!=0?c:'${b['id']}'.compareTo('${a['id']}'); });
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
    if (path.startsWith('/api/parties/') && path.endsWith('/statement') && changedLedger) {
      final id=path.split('/')[3];
      final party=await findParty(shopId,id);
      if(party!=null) {
        final rows=(await indexedItems(shopId,'/api/transactions')).where((e)=>e['partyId']==id && OfflineProjection.isInsideDate(e,query)).toList()..sort((a,b)=>'${a['occurredAt']}'.compareTo('${b['occurredAt']}'));
        return {'party':party,'entries':rows,'openingBalance':query?['from']==null?party['openingBalance']:null,'closingBalance':query?['to']==null?party['balance']:null,'offlinePartial':true};
      }
    }
    if (path.startsWith('/api/parties/') && !path.endsWith('/statement')) {
      final id = path.split('/').last;
      return findParty(shopId, id);
    }
    return null;
  }

  String _workerRenamesKey(String shopId, String ownerId) => 'outbox.workerRenames.$shopId.$ownerId';

  Future<List<Map<String, dynamic>>> readWorkerRenames(String shopId, String? ownerId) async {
    if (shopId.isEmpty || ownerId == null || ownerId.isEmpty) return [];
    final raw = await storage.read(_workerRenamesKey(shopId, ownerId));
    return raw == null ? [] : (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
  Future<void> queueWorkerRename(String shopId, String ownerId, String id, String expected, String name) => _locked(() async {
    final records = await readWorkerRenames(shopId, ownerId);
    // Preserve the original expected name for repeated offline edits. A new
    // intent supersedes the previous local draft, not other device changes.
    final matches = records.where((e) => e['workerId'] == id);
    final existing = matches.isEmpty ? null : matches.first;
    records.removeWhere((e) => e['workerId'] == id);
    records.add({'kind': 'WorkerRename', 'workerId': id, 'expectedName': existing?['expectedName'] ?? expected,
      'workerName': name, 'savedAt': DateTime.now().toUtc().toIso8601String()});
    await storage.write(_workerRenamesKey(shopId, ownerId), jsonEncode(records));
  });
  Future<void> recordWorkerRenameError(String shopId, String ownerId, String id, String name, String error) => _locked(() async {
    final records = await readWorkerRenames(shopId, ownerId);
    for (final e in records) { if (e['workerId'] == id && e['workerName'] == name) e['lastError'] = error; }
    await storage.write(_workerRenamesKey(shopId, ownerId), jsonEncode(records));
  });
  Future<void> confirmWorkerRename(String shopId, String ownerId, String id, String name, {bool discard = false}) => _locked(() async {
    final records = await readWorkerRenames(shopId, ownerId);
    if (!discard) {
      final snapshot = await readSnapshot(shopId, '/api/workers', null);
      if (snapshot is Map && snapshot['workers'] is List) {
        await saveSnapshot(shopId, '/api/workers', null, {...snapshot,
          'workers': (snapshot['workers'] as List).map((w) => w is Map && '${w['id']}' == id ? {...w, 'name': name} : w).toList()});
      }
    }
    // An edit that happened while this request was in flight is still pending.
    for (final e in records) {
      if (!discard && e['workerId'] == id && e['workerName'] != name) e['expectedName'] = name;
    }
    records.removeWhere((e) => e['workerId'] == id && (discard || e['workerName'] == name));
    await storage.write(_workerRenamesKey(shopId, ownerId), jsonEncode(records));
  });

  String _workerDeletesKey(String shopId, String ownerId) =>
      'outbox.workerDeletes.$shopId.$ownerId';

  Future<List<Map<String, dynamic>>> readWorkerDeletes(
    String shopId, String? ownerId,
  ) async {
    if (shopId.isEmpty || ownerId == null || ownerId.isEmpty) return [];
    final raw = await storage.read(_workerDeletesKey(shopId, ownerId));
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> queueWorkerDelete(String shopId, String ownerId,
      String workerId, String workerName) => _locked(() async {
    if (shopId.isEmpty || ownerId.isEmpty || workerId.isEmpty) {
      throw StateError('معرّف المحل أو المالك أو العامل غير متاح');
    }
    final records = await readWorkerDeletes(shopId, ownerId);
    if (records.any((e) => e['workerId'] == workerId)) return;
    records.add({
      'kind': 'WorkerDelete',
      'workerId': workerId,
      'workerName': workerName,
      'savedAt': DateTime.now().toUtc().toIso8601String(),
    });
    await storage.write(_workerDeletesKey(shopId, ownerId), jsonEncode(records));
  });

  Future<void> recordWorkerDeleteError(String shopId, String ownerId,
      String workerId, String message) => _locked(() async {
    final records = await readWorkerDeletes(shopId, ownerId);
    for (final record in records) {
      if (record['workerId'] == workerId) record['lastError'] = message;
    }
    await storage.write(_workerDeletesKey(shopId, ownerId), jsonEncode(records));
  });

  Future<void> cancelWorkerDelete(String shopId, String ownerId,
      String workerId) => _locked(() async {
    final records = await readWorkerDeletes(shopId, ownerId);
    records.removeWhere((e) => e['workerId'] == workerId);
    await storage.write(_workerDeletesKey(shopId, ownerId), jsonEncode(records));
  });

  Future<void> saveWorkerSnapshot(String shopId, dynamic response) =>
      _locked(() => saveSnapshot(shopId, '/api/workers', null, response));

  Future<void> confirmWorkerDelete(String shopId, String ownerId,
      String workerId) => _locked(() async {
    // Update the durable base snapshot BEFORE removing the pending operation.
    // A restart without internet must not resurrect a confirmed deletion.
    final snapshot = await readSnapshot(shopId, '/api/workers', null);
    if (snapshot is Map && snapshot['workers'] is List) {
      await saveSnapshot(shopId, '/api/workers', null, {
        ...snapshot,
        'workers': (snapshot['workers'] as List)
            .where((w) => w is! Map || '${w['id']}' != workerId).toList(),
      });
    }
    final records = await readWorkerDeletes(shopId, ownerId);
    records.removeWhere((e) => e['workerId'] == workerId);
    await storage.write(_workerDeletesKey(shopId, ownerId), jsonEncode(records));
  });

  String _outboxKey(String shopId) => 'outbox.$shopId';

  Future<List<Map<String, dynamic>>> readOutbox(String shopId) async {
    if (shopId.isEmpty) return [];
    final raw = await storage.read(_outboxKey(shopId));
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> addTransaction(String shopId, Map<String, dynamic> body, {String? userId}) =>
      _locked(() async {
        if (shopId.isEmpty || '${body['operationId'] ?? ''}'.isEmpty) {
          throw StateError('لا يمكن حفظ حركة دون محل ومعرّف عملية');
        }
        final records = await readOutbox(shopId);
        final id = '${body['operationId']}';
        final existing = records.where((e) => e['operationId'] == id);
        if (existing.isNotEmpty) {
          if (existing.first['userId'] != userId || jsonEncode(existing.first['body']) != jsonEncode(body)) {
            throw StateError('معرّف العملية مرتبط بمحتوى مختلف');
          }
          return;
        }
        records.add({
          'operationId': id,
          'userId': userId,
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
