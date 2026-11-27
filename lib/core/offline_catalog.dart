import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'storage.dart';

/// Durable user-scoped administrative intents. Financial records stay in the
/// original outbox; the sync engine interleaves both queues in creation order.
class OfflineCatalog {
  OfflineCatalog(this.storage);
  final Storage storage;
  Future<void> _tail = Future.value();
  String _key(String shop, String user) => 'outbox.catalog.$shop.$user';
  Future<void> _locked(Future<void> Function() f) {
    final next = _tail.catchError((_) {}).then((_) => f());
    _tail = next;
    return next;
  }
  Future<List<Map<String, dynamic>>> pending(String shop, String? user) async {
    if (shop.isEmpty || user == null || user.isEmpty) return [];
    final value = await storage.read(_key(shop, user));
    return value == null ? [] : (jsonDecode(value) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
  static bool supports(String method, String path) =>
      (method == 'POST' && (path == '/api/workers' || RegExp(r'^/api/transactions/[0-9a-fA-F-]{36}/(confirm|void)$').hasMatch(path))) ||
      (method == 'PUT' && path == '/api/settings') ||
      (method == 'POST' && ['/api/customers','/api/suppliers','/api/products'].contains(path)) ||
      (method == 'PUT' && RegExp(r'^/api/(parties|products)/[0-9a-fA-F-]{36}$').hasMatch(path)) ||
      (method == 'DELETE' && RegExp(r'^/api/products/[0-9a-fA-F-]{36}$').hasMatch(path)) ||
      (method == 'PATCH' && RegExp(r'^/api/customers/[0-9a-fA-F-]{36}/credit-limit$').hasMatch(path));

  static String collection(String method, String path, Map<String, dynamic>? expected) {
    if (path == '/api/settings' || path == '/api/workers') return path;
    if (path.startsWith('/api/transactions/')) return '/api/transactions';
    if (path.startsWith('/api/products')) return '/api/products';
    if (path.startsWith('/api/customers')) return '/api/customers';
    if (path.startsWith('/api/suppliers')) return '/api/suppliers';
    return expected?['kind'] == 'Supplier' ? '/api/suppliers' : '/api/customers';
  }
  static Map<String, dynamic> project(Map<String, dynamic> record, Map<String, dynamic>? base) {
    final body = Map<String, dynamic>.from(record['body'] as Map);
    body.remove('clientId');
    final path = record['collection'];
    if (path == '/api/settings') return {...?base,...body,'offlinePending':true};
    final isParty = path != '/api/products';
    return {
      if (isParty) ...{
        'kind': path == '/api/suppliers' ? 'Supplier' : 'Customer',
        for (final f in ['nickname','phone','alternatePhone','alternateContact','representative','category','deliveryDays','acceptedMethods','paymentSchedule']) f: '',
        'openingBalance': 0, 'balance': body['openingBalance'] ?? 0, 'creditLimit': null,
      } else ...{'category':'عام','purchasePrice':0,'pricingMode':'Piece'},
      ...?base, ...body,
      if (isParty && body.containsKey('creditLimit') && (body['creditLimit'] as num? ?? 0) <= 0) 'creditLimit': null,
      'id': record['entityId'], 'offlinePending': true,
      if (record['lastError'] != null) 'offlineBlocked': true,
    };
  }
  Future<Map<String, dynamic>> enqueue(String shop, String user, String method, String path,
      Map<String, dynamic> body, Map<String, dynamic>? expected) async {
    if (shop.isEmpty || user.isEmpty || !supports(method,path)) throw StateError('عملية محلية غير صالحة');
    if (method != 'POST' && expected == null) throw StateError('حمّل بيانات السجل أولاً');
    final ledgerAction = path.startsWith('/api/transactions/');
    final id = path == '/api/settings' ? shop : ledgerAction ? path.split('/')[3] : method == 'POST' ? const Uuid().v4() : path.split('/')[3];
    final operation = <String,dynamic>{
      'kind':'CatalogMutation', 'operationId':const Uuid().v4(), 'entityId':id,
      'collection':collection(method,path,expected), 'method':method, 'path':path,
      'body':{...body, if (method == 'POST' && !ledgerAction) 'clientId':id},
      if (expected != null) 'expected':expected,
      'savedAt':DateTime.now().toUtc().toIso8601String(),
    };
    await _locked(() async {
      final records = await pending(shop,user);
      if (ledgerAction && records.any((r) => r['collection']=='/api/transactions' && r['entityId']==id)) {
        throw StateError('يوجد طلب معلق لهذه الحركة بالفعل');
      }
      records.add(operation);
      await storage.write(_key(shop,user),jsonEncode(records));
    });
    return operation;
  }
  Future<void> error(String shop,String user,String id,String message) => _locked(() async {
    final records = await pending(shop,user);
    for(final r in records) { if(r['operationId']==id) r['lastError']=message; }
    await storage.write(_key(shop,user),jsonEncode(records));
  });
  Future<void> acknowledge(String shop,String user,String id) => _locked(() async {
    final records = await pending(shop,user);
    records.removeWhere((r)=>r['operationId']==id);
    await storage.write(_key(shop,user),jsonEncode(records));
  });
  static List<Map<String,dynamic>> overlay(String collection,List<Map<String,dynamic>> base,List<Map<String,dynamic>> records) {
    final rows = {for(final r in base) '${r['id']}':r};
    for(final r in records.where((r)=>r['collection']==collection)) {
      final id='${r['entityId']}';
      if(r['method']=='DELETE') { rows.remove(id); }
      else {rows[id]=project(r,rows[id]);}
    }
    return rows.values.toList();
  }
}
