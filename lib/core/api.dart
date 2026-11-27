import 'dart:typed_data';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'storage.dart';
import 'offline.dart';
import 'offline_catalog.dart';
import 'offline_projection.dart';
import 'offline_grace.dart';
import 'sync_reminders.dart';

typedef Json = Map<String, dynamic>;
const defaultApiBaseUrl = 'https://api-deenbook.runasp.net';

class ApiFailure implements Exception {
  ApiFailure(this.message, {this.status});
  final String message;
  final int? status;
  bool get uncertain => status == null || status! >= 500 || status == 409;
  @override
  String toString() => message;
  factory ApiFailure.from(DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    String? message;
    if (data is Map && status != null && status < 500) {
      final errors = data['errors'];
      if (errors is Map) {
        message = errors.values.expand((e) => e is List ? e : [e]).join('\n');
      }
      if (errors is List) message = errors.join('\n');
      if (message?.trim().isEmpty == true) message = null;
      for (final key in ['message', 'detail', 'title']) {
        final value = data[key];
        if (message == null && value is String && value.trim().isNotEmpty) {
          message = value;
        }
      }
    }
    final tlsFailure =
        e.type == DioExceptionType.badCertificate ||
        [
          'handshakeexception',
          'certificate_verify_failed',
        ].any((part) => '${e.error}'.toLowerCase().contains(part));
    return ApiFailure(
      (message?.trim().isNotEmpty == true ? message : null) ??
          switch (status) {
            401 => 'بيانات الدخول غير صحيحة أو انتهت الجلسة.',
            403 => 'تعذّر الوصول. تحقق من حالة الاشتراك.',
            404 =>
              'مسار الخدمة غير متاح. تواصل مع الإدارة للتحقق من رابط التطبيق.',
            409 => 'تعارض في الحفظ. تحقق من كشف الحساب قبل إنشاء حركة جديدة.',
            429 => 'محاولات كثيرة. انتظر قليلاً ثم حاول مجدداً.',
            int code when code >= 500 =>
              'خادم الخدمة غير متاح حالياً. حاول بعد قليل.',
            int code when code >= 300 && code < 400 =>
              'عنوان الخدمة يحتاج إلى تحديث. تواصل مع الإدارة.',
            null when tlsFailure =>
              'تعذّر إنشاء اتصال آمن بالخادم. تواصل مع الإدارة.',
            null => switch (e.type) {
              DioExceptionType.connectionTimeout ||
              DioExceptionType.receiveTimeout ||
              DioExceptionType.sendTimeout =>
                'انتهت مهلة انتظار الخادم. حاول بعد قليل.',
              DioExceptionType.cancel => 'أُلغي الطلب.',
              _ =>
                'تعذّر الوصول إلى خادم الخدمة. قد تكون الخدمة غير متاحة أو الاتصال بها محجوباً. حاول لاحقاً.',
            },
            _ => 'تعذّر إتمام الطلب. حاول مجدداً.',
          },
      status: status,
    );
  }
}

String validateBaseUrl(String raw, {bool release = kReleaseMode}) {
  final u = Uri.tryParse(raw.trim());
  if (u == null ||
      !['https', 'http'].contains(u.scheme) ||
      u.host.isEmpty ||
      u.userInfo.isNotEmpty ||
      u.hasQuery ||
      u.hasFragment) {
    throw const FormatException(
      'اضبط API_BASE_URL على رابط HTTPS صالح للخادم.',
    );
  }
  if (release && u.scheme != 'https') {
    throw const FormatException(
      'إصدار التطبيق النهائي يحتاج رابط HTTPS. فعّل HTTPS على الاستضافة ثم أعد بناء التطبيق.',
    );
  }
  var path = u.path.replaceAll(RegExp(r'/+$'), '');
  // Every endpoint already starts with /api. Accept common copied URL forms
  // without producing /api/api, including the punctuation in a pasted link.
  path = path.replaceFirst(RegExp(r'/api\.?$', caseSensitive: false), '');
  return u.replace(path: path).toString();
}

Json _responseObject(dynamic data) {
  if (data is Map<String, dynamic>) return data;
  throw ApiFailure(
    'استجابة الخادم غير صالحة. تواصل مع الإدارة للتحقق من الخدمة.',
  );
}

class Api {
  Api(this.storage, {Dio? client, String? baseUrl})
    : dio =
          client ??
          Dio(
            BaseOptions(
              baseUrl: validateBaseUrl(
                baseUrl ??
                    const String.fromEnvironment(
                      'API_BASE_URL',
                      defaultValue: defaultApiBaseUrl,
                    ),
              ),
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 25),
              sendTimeout: const Duration(seconds: 25),
              followRedirects: false,
            ),
          );
  final Storage storage;
  final Dio dio;
  late final OfflineVault offlineVault = OfflineVault(storage);
  late final OfflineCatalog offlineCatalog = OfflineCatalog(storage);
  int _catalogCacheVersion = 0;
  String? _shopId;
  String? _verifiedOwnerId;
  String? _verifiedUserId;
  DateTime? _verifiedAt;
  DateTime? _maxObservedAt;
  DateTime? _monotonicBase;
  final Stopwatch _graceWatch = Stopwatch();
  bool _clockUntrusted = false;
  DateTime _effectiveNow() {
    final wall = DateTime.now().toUtc();
    final running = _monotonicBase?.add(_graceWatch.elapsed);
    if (running != null && running.isAfter(wall)) return running;
    return wall;
  }
  void _startGraceClock(DateTime base) {
    _monotonicBase = base;
    _graceWatch..reset()..start();
  }
  Future<void> observeOfflineClock() async {
    final verified = _verifiedAt;
    if (verified == null) return;
    final now = DateTime.now().toUtc();
    final previous = _maxObservedAt;
    if (previous != null && now.isBefore(previous.subtract(const Duration(minutes: 2)))) {
      _clockUntrusted = true;
    }
    final effective = _effectiveNow();
    if (previous != null && !_clockUntrusted && effective.difference(previous) < const Duration(minutes: 2)) return;
    _maxObservedAt = previous == null || effective.isAfter(previous) ? effective : previous;
    final generation = _generation;
    final observed = _maxObservedAt!;
    final locked = _clockUntrusted;
    await _write(() async {
      if (generation != _generation || _verifiedAt != verified) return;
      await storage.write('offline.clock', jsonEncode({
        'verifiedAt': verified.toIso8601String(),
        'observedAt': observed.toIso8601String(),
        'untrusted': locked,
      }));
    });
  }
  DateTime? get verifiedAt => _verifiedAt;
  Json? lastVerifiedStatus;
  String? get verifiedUserId => _verifiedUserId;
  int get offlineGraceDays => OfflineGrace.parseDays(lastVerifiedStatus?['offlineGraceDays']);
  OfflineGrace get grace => OfflineGrace(_verifiedAt, _effectiveNow(),
      days: offlineGraceDays,
      paidUntil: _offlineMode ? DateTime.tryParse('${lastVerifiedStatus?['paidUntil'] ?? ''}') : null,
      clockUntrusted: _clockUntrusted || (_maxObservedAt != null &&
        DateTime.now().toUtc().isBefore(_maxObservedAt!.subtract(const Duration(minutes: 2)))));
  bool get offlineExpired => _verifiedAt != null && grace.expired;
  bool _warming = false;
  void _requireOfflineAccess() {
    if (offlineExpired || (_offlineMode && _verifiedAt == null)) {
      throw ApiFailure('انتهت مدة العمل دون إنترنت. اتصل بالخادم للتحقق والمزامنة.', status: 423);
    }
  }
  Future<int>? _synchronizing;
  int _workerCacheVersion = 0;
  bool _offlineMode = false;
  bool get isOffline => _offlineMode;
  VoidCallback? onConnectionChanged;
  String get savedShopId => _shopId ?? '';
  // A locally remembered session can read saved snapshots and queue financial
  // operations, but it cannot perform server-verified administrative writes.
  bool get offlineSession => _offlineMode && _access == null && _shopId != null;

  void _setOffline(bool value) {
    if (_offlineMode == value) return;
    _offlineMode = value;
    onConnectionChanged?.call();
  }

  Future<void> _rememberLiveStatus(Json data) async {
    final id = data['id'];
    if (id is! String || id.isEmpty) return;
    if (_shopId != null && _shopId != id) throw ApiFailure('تغيّر المحل. سجّل الدخول مجدداً.');
    _shopId = id;
    {
      final userId = data['userId'];
      final nextUser = userId is String && userId.isNotEmpty ? userId : null;
      if (_verifiedUserId != null && _verifiedUserId != nextUser) {
        throw ApiFailure('تغيّرت هوية الحساب. سجّل الدخول مجدداً.');
      }
      _verifiedUserId = nextUser;
      _verifiedAt = DateTime.now().toUtc();
      _clockUntrusted = false;
      _maxObservedAt = null;
      _startGraceClock(_verifiedAt!);
      lastVerifiedStatus = Map<String, dynamic>.from(data);
      _verifiedOwnerId = data['isOwner'] == true && userId is String && userId.isNotEmpty
          ? userId : null;
      await storage.write(
        'offline.identity',
        jsonEncode({
          'shopId': id,
          'ownerId': _verifiedOwnerId,
          'userId': _verifiedUserId,
          'verifiedAt': _verifiedAt!.toIso8601String(),
        }),
      );
      await offlineVault.saveSnapshot(id, '/api/subscription', null, data);
      await observeOfflineClock();
      if (data['active'] == true && data['suspended'] != true) {
        await SyncReminders.schedule(_verifiedAt!, days: offlineGraceDays, expiresAt: OfflineGrace(_verifiedAt, _effectiveNow(), days: offlineGraceDays, paidUntil: DateTime.tryParse('${lastVerifiedStatus?['paidUntil'] ?? ''}')).expiresAt);
      } else { await SyncReminders.cancel(); }
    }
  }

  Future<bool> _restoreOfflineIdentity() async {
    try {
      final raw = await storage.read('offline.identity');
      if (raw == null) return false;
      final identity = jsonDecode(raw) as Map;
      final id = identity['shopId'];
      final verified = DateTime.tryParse('${identity['verifiedAt']}');
      if (id is! String ||
          id.isEmpty ||
          verified == null) {
        return false;
      }
      final status = await offlineVault.readSnapshot(
        id,
        '/api/subscription',
        null,
      );
      final until = status is Map
          ? DateTime.tryParse('${status['paidUntil']}')
          : null;
      if (status is! Map ||
          status['suspended'] == true ||
          until == null ||
          !until.isAfter(DateTime.now().toUtc())) {
        return false;
      }
      _shopId = id;
      lastVerifiedStatus = Map<String, dynamic>.from(status);
      _verifiedAt = verified.toUtc();
      _clockUntrusted = false;
      _maxObservedAt = _verifiedAt;
      final clockRaw = await storage.read('offline.clock');
      if (clockRaw != null) {
        try {
          final savedClock = jsonDecode(clockRaw) as Map;
          if (savedClock['verifiedAt'] == _verifiedAt!.toIso8601String()) {
            _maxObservedAt = DateTime.tryParse('${savedClock['observedAt']}')?.toUtc() ?? _verifiedAt;
            _clockUntrusted = savedClock['untrusted'] == true;
          }
        } catch (_) { _clockUntrusted = true; }
      }
      final wall = DateTime.now().toUtc();
      _startGraceClock(_maxObservedAt!.isAfter(wall) ? _maxObservedAt! : wall);
      await observeOfflineClock();
      final userId = identity['userId'] ?? status['userId'];
      _verifiedUserId = userId is String && userId.isNotEmpty && status['userId'] == userId ? userId : null;
      final ownerId = identity['ownerId'];
      _verifiedOwnerId = ownerId is String && ownerId.isNotEmpty &&
          status['isOwner'] == true && status['userId'] == ownerId
          ? ownerId : null;
      _setOffline(true);
      if (!offlineExpired) await SyncReminders.schedule(_verifiedAt!, days: offlineGraceDays, expiresAt: OfflineGrace(_verifiedAt, _effectiveNow(), days: offlineGraceDays, paidUntil: DateTime.tryParse('${lastVerifiedStatus?['paidUntil'] ?? ''}')).expiresAt);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<Json>> pendingWorkerDeletes() =>
      offlineVault.readWorkerDeletes(savedShopId, _verifiedOwnerId);

  Future<List<Json>> currentOutbox() async => (await offlineVault.readOutbox(savedShopId))
      .where((entry) => _verifiedUserId != null && entry['userId'] == _verifiedUserId).toList();

  Future<int> legacyPendingCount() async => (await offlineVault.readOutbox(savedShopId))
      .where((entry) => entry['userId'] == null).length;

  Future<List<Json>> pendingWorkerRenames() => offlineVault.readWorkerRenames(savedShopId, _verifiedOwnerId);

  Future<Json> renameWorker(String id, String expected, String name) async {
    final shop = _shopId;
    final owner = _verifiedOwnerId;
    final generation = _generation;
    if (shop == null || owner == null || !signedIn || id.isEmpty || id.contains('/') || name.trim().isEmpty || name.length > 160) {
      throw ApiFailure('تعذّر التحقق من بيانات العامل وصلاحيات صاحب المحل.');
    }
    _requireOfflineAccess();
    // Only queue if the deployed API advertises conflict-aware rename support.
    if (lastVerifiedStatus?['offlineWorkerRenameVersion'] != 1) {
      return _responseObject(await request('PUT', '/api/workers/$id/name', body: {'name': name}));
    }
    await offlineVault.queueWorkerRename(shop, owner, id, expected, name);
    if (generation != _generation) throw ApiFailure('تغيّرت جلسة الدخول.');
    // A single sync loop performs all administrative writes; never race it.
    return {'queued': true};
  }
  Future<void> discardWorkerRename(String id) async {
    final shop = _shopId; final owner = _verifiedOwnerId;
    if (shop == null || owner == null) throw ApiFailure('صاحب المحل فقط');
    if (_synchronizing != null) throw ApiFailure('انتظر انتهاء المزامنة أولاً.');
    await offlineVault.confirmWorkerRename(shop, owner, id, '', discard: true);
  }

  Future<List<Json>> pendingCatalog() => offlineCatalog.pending(savedShopId, _verifiedUserId);

  Future<List<Json>> _catalogItems(String collection) async => OfflineCatalog.overlay(
      collection, await offlineVault.indexedItems(savedShopId, collection), await pendingCatalog());

  Future<Json?> _catalogParty(String id) async {
    for (final collection in ['/api/customers','/api/suppliers']) {
      for (final row in await _catalogItems(collection)) {
        if ('${row['id']}' == id) return {...row, 'kind':collection == '/api/customers' ? 'Customer' : 'Supplier'};
      }
    }
    return null;
  }

  Future<dynamic> _queueCatalog(String method, String path, Object? body) async {
    final user = _verifiedUserId;
    final shop = _shopId;
    if (user == null || shop == null) throw ApiFailure('تحقق من الحساب أولاً');
    final generation = _generation;
    final data = body is Map ? Map<String,dynamic>.from(body) : <String,dynamic>{};
    if ((path == '/api/workers' || path.endsWith('/void')) && _verifiedOwnerId != user) throw ApiFailure('هذه العملية متاحة للمالك فقط.');
    if (path == '/api/workers') {
      final cached = await offlineVault.readSnapshot(shop,path,null);
      if (cached is! Map) throw ApiFailure('حمّل قائمة العاملين أولاً.');
      final projected = (await _withLocalMovements(path,null,cached)) as Map;
      final active = (projected['workers'] as List).where((w)=>w is Map && w['enabled']==true).toList();
      if (active.length >= 2) throw ApiFailure('يمكن إضافة عاملين اثنين فقط.');
      if (active.any((w)=>w['phoneNumber']==data['phoneNumber'])) throw ApiFailure('رقم الجوال مستخدم.');
    }
    if (path.startsWith('/api/transactions/')) {
      final id = path.split('/')[3];
      final rows = await offlineVault.indexedItems(shop, '/api/transactions');
      final matches = rows.where((r) => '${r['id']}' == id);
      if (matches.isEmpty || matches.first['voidedAt'] != null) throw ApiFailure('حمّل الحركة من الخادم أولاً.');
      if (path.endsWith('/confirm') && matches.first['pendingConfirmation'] != true) throw ApiFailure('الحوالة ليست بانتظار التأكيد.');
    }
    if (method=='PATCH' && _verifiedOwnerId!=user) throw ApiFailure('تعديل سقف الدين للمالك فقط.');
    Json? expected;
    if (path == '/api/settings') {
      if (_verifiedOwnerId != user) throw ApiFailure('تعديل إعدادات المحل متاح للمالك فقط.');
      final cached = await offlineVault.readSnapshot(shop,path,null);
      if (cached is! Map) throw ApiFailure('حمّل إعدادات المحل أولاً.');
      expected = Map<String,dynamic>.from(cached);
      for(final record in await pendingCatalog()) {
        if(record['collection']==path) expected = OfflineCatalog.project(record,expected);
      }
      expected = {for(final f in ['name','ownerName','phone','collectionAccounts']) f:expected![f]};
    } else if (method != 'POST') {
      final id = path.split('/')[3];
      if (path.startsWith('/api/products')) {
        for (final row in await _catalogItems('/api/products')) { if ('${row['id']}' == id) expected = row; }
      } else {
        expected = await _catalogParty(id);
        if (expected == null) {
          final cached = await offlineVault.readSnapshot(shop, '/api/parties/$id', null);
          if (cached is Map) expected = Map<String,dynamic>.from(cached);
        }
      }
      if (expected == null) throw ApiFailure('حمّل بيانات السجل أولاً.');
      if ((await pendingCatalog()).any((r)=>r['entityId']==id && r['lastError']!=null)) throw ApiFailure('راجع التعديل المرفوض في مركز المزامنة أولاً.');
      // Send only editable fields; defaults are explicit for older cached rows.
      expected = path.startsWith('/api/products') ? {
        for (final f in ['name','unit','category','salePrice','purchasePrice','pricingMode']) f:expected![f],
      } : {
        'kind':expected['kind'],
        for (final f in ['name','nickname','phone','alternatePhone','alternateContact','representative','category','deliveryDays','acceptedMethods','paymentSchedule']) f:expected![f] ?? '',
        'openingBalance':expected['openingBalance'] ?? 0, 'creditLimit':expected['creditLimit'],
      };
    }
    if (generation != _generation) throw ApiFailure('تغيّرت جلسة الدخول.');
    final record = await offlineCatalog.enqueue(shop,user,method,path,data,expected);
    if (generation != _generation) throw ApiFailure('تغيّرت جلسة الدخول.');
    if (path == '/api/workers' || path.startsWith('/api/transactions/')) return {'queued':true, 'id':record['entityId']};
    return {...OfflineCatalog.project(record,expected), 'queued':true};
  }

  Future<void> discardRejectedCatalog(String operationId) async {
    if (_synchronizing != null) throw ApiFailure('انتظر انتهاء المزامنة.');
    final actor = _verifiedUserId, shop = _shopId;
    if (actor == null || shop == null) throw ApiFailure('تحقق من الحساب أولاً.');
    final records = await pendingCatalog();
    final matches = records.where((r)=>r['operationId']==operationId);
    if (matches.isEmpty || matches.first['lastError']==null) throw ApiFailure('يمكن إلغاء الطلب المرفوض فقط.');
    final row = matches.first, entity = '${matches.first['entityId']}';
    if (records.any((r)=>r['entityId']==entity && r['operationId']!=operationId && '${r['savedAt']}'.compareTo('${row['savedAt']}')>=0)) {
      throw ApiFailure('توجد تعديلات لاحقة تعتمد على هذا الطلب. تواصل مع الدعم.');
    }
    for(final tx in await currentOutbox()) {
      final body = tx['body'] as Map;
      if ('${body['partyId']}'==entity || ((body['items'] as List?) ?? []).whereType<Map>().any((i)=>'${i['productId']}'==entity)) {
        throw ApiFailure('توجد حركة مالية مرتبطة بالطلب؛ لا يمكن إلغاؤه تلقائياً.');
      }
    }
    await offlineCatalog.acknowledge(shop,actor,operationId);
  }

  Future<int> pendingCount() async =>
      (await currentOutbox()).length +
      (await pendingWorkerDeletes()).length + (await pendingWorkerRenames()).length + (await pendingCatalog()).length;

  /// Only a server-verified owner may enqueue a deletion. The immutable
  /// worker ID, not the reusable phone number, is the retry key.
  Future<Json> deleteWorker(String workerId, String workerName) async {
    final shop = _shopId;
    final owner = _verifiedOwnerId;
    final generation = _generation;
    if (shop == null || owner == null || !signedIn || workerId.isEmpty ||
        workerId.contains('/')) {
      throw ApiFailure('اتصل بالإنترنت بحساب صاحب المحل للتحقق من الصلاحية.');
    }
    _requireOfflineAccess();
    await offlineVault.queueWorkerDelete(shop, owner, workerId, workerName);
    if (generation != _generation) throw ApiFailure('تغيّرت جلسة الدخول.');
    if (isOffline || _access == null) return {'queued': true};
    try {
      await _sendWorkerDelete(shop, owner, workerId, generation);
      return {'queued': false};
    } on ApiFailure catch (e) {
      if (generation != _generation) rethrow;
      if (e.status == null || e.status! >= 500 || e.status == 409 || e.status == 429) {
        if (e.status == null || e.status! >= 500) _setOffline(true);
        await offlineVault.recordWorkerDeleteError(shop, owner, workerId, e.message);
        return {'queued': true};
      }
      // A definitive rejection of a NEW online action is not a deletion.
      // Previously queued deletes are handled by synchronize and retained.
      await offlineVault.cancelWorkerDelete(shop, owner, workerId);
      rethrow;
    }
  }

  Future<void> _sendWorkerDelete(String shop, String owner,
      String workerId, int generation) async {
    if (_generation != generation || _shopId != shop || _verifiedOwnerId != owner) {
      throw ApiFailure('تغيّرت جلسة الدخول.');
    }
    await request('DELETE', '/api/workers/${Uri.encodeComponent(workerId)}', forceOnline: true);
    // Even if the user switches accounts immediately after the HTTP response,
    // acknowledgement belongs only to the original owner's durable queue.
    _workerCacheVersion++;
    await offlineVault.confirmWorkerDelete(shop, owner, workerId);
    await offlineVault.confirmWorkerRename(shop, owner, workerId, '', discard: true);
  }

  Future<Json> localReport(String path, Json? query) async {
    final shop = savedShopId;
    final customers = await offlineVault.indexedItems(shop,'/api/customers');
    final suppliers = await offlineVault.indexedItems(shop,'/api/suppliers');
    final parties = {for(final p in [...customers,...suppliers]) '${p['id']}':p};
    final supplierIds = suppliers.map((p)=>'${p['id']}').toSet();
    final rows = (await offlineVault.indexedItems(shop,'/api/transactions')).where((e)=>e['voidedAt']==null && OfflineProjection.isInsideDate(e,query)).toList();
    int cents(dynamic n) => ((n as num? ?? 0)*100).round();
    int payment(Json e) => e['pendingConfirmation']==true ? 0 : cents(e['kind']=='Payment'?e['amount']:e['paidNow']);
    bool supplier(Json e) => supplierIds.contains('${e['partyId']}');
    final known = rows.where((e)=>parties.containsKey('${e['partyId']}')).toList();
    final cash = known.where((e)=>e['method']=='Cash' && payment(e)>0).toList();
    int sum(Iterable<Json> r) => r.fold<int>(0,(a,e)=>a+payment(e));
    double outstanding(List<Json> r) => r.fold<int>(0,(a,e)=>a+(cents(e['balance'])>0?cents(e['balance']):0))/100;
    final received = sum(known.where((e)=>!supplier(e))), paid = sum(known.where(supplier));
    final cashIn = sum(cash.where((e)=>!supplier(e))), cashOut = sum(cash.where(supplier));
    if(path.endsWith('/summary')) return {'receivables':outstanding(customers),'payables':outstanding(suppliers),'received':received/100,'paid':paid/100,'offlinePartial':true};
    if(path.endsWith('/cashflow')) return {'customerCashIn':cashIn/100,'supplierCashOut':cashOut/100,'netCash':(cashIn-cashOut)/100,'entries':cash,'offlinePartial':true};
    return {'items':rows.where((e)=>['Debt','Purchase'].contains(e['kind'])).map((e)=>{'entry':e,'partyName':parties['${e['partyId']}']?['name']??'حساب سابق'}).toList(),'offlinePartial':true,'truncated':false};
  }

  Future<dynamic> _withLocalMovements(
    String path, Json? query, dynamic raw,
  ) async {
    if (_shopId == null || raw is! Map) return raw;
    if (path == '/api/workers') {
      final pending = await pendingWorkerDeletes();
      final ids = pending.map((e) => '${e['workerId']}').toSet();
      final renames = {for (final r in await pendingWorkerRenames()) '${r['workerId']}': r};
      final additions = (await pendingCatalog()).where((r) => r['collection']=='/api/workers').map((r) {
        final b = r['body'] as Map;
        return {'id':r['entityId'], 'name':b['name'], 'phoneNumber':b['phoneNumber'], 'enabled':true, 'offlineCreate':true};
      }).toList();
      return <String, dynamic>{
        ...Map<String, dynamic>.from(raw),
        'workers': [...additions, ... ((raw['workers'] as List?) ?? [])
            .where((w) => w is Map && !ids.contains('${w['id']}'))
            .map((w) { final worker = w as Map; final pendingRename = renames['${worker['id']}'];
              return pendingRename == null ? worker : {...worker, 'name': pendingRename['workerName'], 'offlinePending': true}; }).where((w) => !additions.any((a) => a['id']==w['id'])).toList()],
        'pendingWorkerDeletes': pending,
      };
    }
    final catalog = await pendingCatalog();
    final outbox = await currentOutbox();
    if (path == '/api/transactions' || path.endsWith('/statement')) {
      final key = path == '/api/transactions' ? 'items' : 'entries';
      final actions = {for(final r in catalog.where((r)=>r['collection']=='/api/transactions')) '${r['entityId']}':r};
      if (raw[key] is List) {
        raw = {...raw, key:(raw[key] as List).map((e) {
          if(e is! Map || !actions.containsKey('${e['id']}')) return e;
          final action = actions['${e['id']}']!;
          return {...e,'offlineLedgerAction':'${action['path']}'.endsWith('/void')?'void':'confirm','offlineActionError':action['lastError']};
        }).toList()};
      }
    }
    if (path == '/api/settings') {
      var settings = Map<String,dynamic>.from(raw);
      for(final record in catalog.where((r)=>r['collection']==path)) settings=OfflineCatalog.project(record,settings);
      return settings;
    }
    final isCatalogList = ['/api/customers','/api/suppliers','/api/products'].contains(path);
    final localCatalog = isCatalogList && (catalog.any((r) => r['collection'] == path) ||
        (_offlineMode && await offlineVault.catalogChanged(savedShopId,path)));
    if (path == '/api/products/categories' && (catalog.any((r) => r['collection'] == '/api/products') || (_offlineMode && await offlineVault.catalogChanged(savedShopId,'/api/products')))) {
      final rows = await _catalogItems('/api/products');
      return {'items': rows.map((p)=>'${p['category'] ?? ''}').where((v)=>v.isNotEmpty).toSet().toList()..sort(), 'offlinePartial':true};
    }
    if (path == '/api/products' && localCatalog) {
      var rows = await _catalogItems(path);
      final term = '${query?['search'] ?? ''}'.trim().toLowerCase();
      rows = rows.where((p) => (term.isEmpty || ['name','unit'].any((f) => '${p[f] ?? ''}'.toLowerCase().contains(term))) &&
          (query?['category'] == null || p['category'] == query!['category'])).toList();
      rows.sort((a,b)=>'${a['name']}'.compareTo('${b['name']}'));
      final page = (query?['page'] as num?)?.toInt() ?? 1, size = (query?['size'] as num?)?.toInt() ?? 30;
      return {...raw,'items':rows.skip((page-1)*size).take(size).toList(),'total':rows.length,'offlinePartial':true};
    }
    if (outbox.isEmpty && catalog.isEmpty && !localCatalog) {
      if (path == '/api/transactions' && raw['offlinePartial'] == true) {
        return OfflineProjection.transactionList(
          Map<String, dynamic>.from(raw), <Map<String, dynamic>>[], query,
          <String, String>{},
        );
      }
      return raw;
    }
    final entries = OfflineProjection.pendingEntries(outbox);
    final base = Map<String, dynamic>.from(raw);
    final kinds = await offlineVault.partyKinds(_shopId!);
    for (final row in catalog) {
      if (['/api/customers','/api/suppliers'].contains(row['collection'])) kinds['${row['entityId']}'] = row['collection'] == '/api/customers' ? 'Customer' : 'Supplier';
    }
    if (path == '/api/transactions') {
      return OfflineProjection.transactionList(base, entries, query, kinds);
    }
    if (path == '/api/customers' || path == '/api/suppliers') {
      final kind = path == '/api/customers' ? 'Customer' : 'Supplier';
      final locallyIndexed = (_offlineMode || localCatalog)
          ? await _catalogItems(path)
          : <Map<String, dynamic>>[];
      final source = (locallyIndexed.isNotEmpty || localCatalog)
          ? locallyIndexed
          : (base['items'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      var adjusted = source.map((p) {
        final id = '${p['id']}';
        if (kinds[id] != kind) return p;
        return {...p, 'balance': (p['balance'] as num? ?? 0) +
            OfflineProjection.partyDelta(id, entries)};
      }).toList();
      if (locallyIndexed.isNotEmpty || localCatalog) {
        final term = '${query?['search'] ?? ''}'.toLowerCase().trim();
        adjusted = adjusted.where((p) => term.isEmpty ||
            ['name', 'nickname', 'phone', 'alternatePhone'].any((f) =>
                '${p[f] ?? ''}'.toLowerCase().contains(term))).toList();
        final filter = '${query?['filter'] ?? ''}';
        if (filter == 'debt' || filter == 'owing') adjusted = adjusted.where((p) => (p['balance'] as num? ?? 0) > 0).toList();
        if (filter == 'credit') adjusted = adjusted.where((p) => (p['balance'] as num? ?? 0) < 0).toList();
        if (filter == 'settled') adjusted = adjusted.where((p) => (p['balance'] as num? ?? 0) == 0).toList();
        if (query?['category'] != null) {
          adjusted = adjusted.where((p) => '${p['category'] ?? ''}' == '${query!['category']}').toList();
        }
        if (filter == 'creditLimit') adjusted = adjusted.where((p) => (p['creditLimit'] as num? ?? 0) > 0 && (p['balance'] as num? ?? 0) >= (p['creditLimit'] as num)*.8).toList();
        if (filter == 'scheduled') adjusted = adjusted.where((p) => '${p[kind == 'Customer' ? 'paymentSchedule' : 'deliveryDays'] ?? ''}'.isNotEmpty).toList();
        if (filter == 'today' && kind == 'Supplier') {
          const ar = ['الاثنين','الثلاثاء','الأربعاء','الخميس','الجمعة','السبت','الأحد'];
          const en = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
          final d = DateTime.now().weekday-1;
          adjusted = adjusted.where((p) => '${p['deliveryDays'] ?? ''}'.contains(ar[d]) || '${p['deliveryDays'] ?? ''}'.contains(en[d])).toList();
        }
        if (query?['sort'] == 'balanceAsc') adjusted.sort((a,b)=>(a['balance'] as num? ?? 0).compareTo(b['balance'] as num? ?? 0));
        if (query?['sort'] == 'recent') adjusted.sort((a,b)=>'${b['lastActivity'] ?? ''}'.compareTo('${a['lastActivity'] ?? ''}'));
        if (query?['sort'] == 'balance' || query?['sort'] == null) {
          adjusted.sort((a,b) => (b['balance'] as num? ?? 0).compareTo(a['balance'] as num? ?? 0));
        } else if (query?['sort'] == 'name') {
          adjusted.sort((a,b) => '${a['name']}'.compareTo('${b['name']}'));
        }
        final count = adjusted.length;
        final page = (query?['page'] as num?)?.toInt() ?? 1;
        final size = (query?['size'] as num?)?.toInt() ?? 30;
        return {...base, 'items': adjusted.skip((page-1)*size).take(size).toList(),
          'total': count, 'offlinePartial': true};
      }
      return {...base, 'items': adjusted};
    }
    if (path.startsWith('/api/parties/') && path.endsWith('/statement')) {
      final id = path.split('/')[3];
      final projected = OfflineProjection.statement(base, id, entries, query);
      if (base['offlinePartial'] == true && base['closingBalance'] == null) projected['closingBalance'] = null;
      if (base['party'] is Map) {
        final originalParty = Map<String,dynamic>.from(base['party'] as Map);
        final party = catalog.any((r)=>r['entityId']==id) ? await _catalogParty(id) ?? originalParty : originalParty;
        return {
          ...projected,
          'party': {...party, 'balance': (party['balance'] as num? ?? 0) +
              OfflineProjection.partyDelta(id, entries)},
        };
      }
      return projected;
    }
    if (path.startsWith('/api/parties/') && !path.endsWith('/statement')) {
      final id = path.split('/').last;
      final row = catalog.any((r)=>r['entityId']==id) ? await _catalogParty(id) ?? base : base;
      return {...row, 'balance': (row['balance'] as num? ?? 0) +
          OfflineProjection.partyDelta(id, entries)};
    }
    if (path == '/api/customers/overview' || path == '/api/suppliers/overview') {
      final kindPath = path.replaceFirst('/overview', '');
      final parties = await _catalogItems(kindPath);
      if (catalog.any((r)=>r['collection']==kindPath)) {
        final rows = parties.map((p)=>{...p,'balance':(p['balance'] as num? ?? 0)+OfflineProjection.partyDelta('${p['id']}',entries)}).toList();
        return {...base,'total':rows.length,'owing':rows.where((p)=>(p['balance'] as num)>0).length,
          'credit':rows.where((p)=>(p['balance'] as num)<0).length,'settled':rows.where((p)=>p['balance']==0).length,
          'outstanding':rows.where((p)=>(p['balance'] as num)>0).fold<num>(0,(a,p)=>a+(p['balance'] as num)),
          'scheduled':rows.where((p)=>'${p[kindPath == '/api/customers'?'paymentSchedule':'deliveryDays'] ?? ''}'.isNotEmpty).length,
          'nearCreditLimit':rows.where((p)=>(p['creditLimit'] as num? ?? 0)>0 && (p['balance'] as num)>=(p['creditLimit'] as num)*.8).length,
          'categories':rows.map((p)=>'${p['category'] ?? ''}').where((v)=>v.isNotEmpty).toSet().toList()..sort(), 'offlinePartial':true};
      }
      var outstandingDifference = 0.0;
      var owingDifference = 0;
      var creditDifference = 0;
      var settledDifference = 0;
      for (final party in parties) {
        final old = (party['balance'] as num? ?? 0).toDouble();
        final next = old + OfflineProjection.partyDelta('${party['id']}', entries);
        outstandingDifference += (next > 0 ? next : 0) - (old > 0 ? old : 0);
        if (old > 0) owingDifference--;
        if (old < 0) creditDifference--;
        if (old == 0) settledDifference--;
        if (next > 0) owingDifference++;
        if (next < 0) creditDifference++;
        if (next == 0) settledDifference++;
      }
      return {
        ...base,
        'outstanding': (base['outstanding'] as num? ?? 0) + outstandingDifference,
        'owing': (base['owing'] as num? ?? 0) + owingDifference,
        'credit': (base['credit'] as num? ?? 0) + creditDifference,
        'settled': (base['settled'] as num? ?? 0) + settledDifference,
      };
    }
    if (path == '/api/dashboard') {
      num receivables = 0, payables = 0;
      final customers = await offlineVault.indexedItems(_shopId!, '/api/customers');
      final suppliers = await offlineVault.indexedItems(_shopId!, '/api/suppliers');
      final seenIds = <String>{};
      for (final (accounts, kind) in [
        (customers, 'Customer'), (suppliers, 'Supplier'),
      ]) {
        for (final party in accounts) {
          final id = '${party['id']}';
          seenIds.add(id);
          final before = (party['balance'] as num? ?? 0).toDouble();
          final after = before + OfflineProjection.partyDelta(id, entries);
          final change = (after > 0 ? after : 0) - (before > 0 ? before : 0);
          if (kind == 'Customer') receivables += change;
          if (kind == 'Supplier') payables += change;
        }
      }
      for (final e in entries.where((e) => !seenIds.contains('${e['partyId']}'))) {
        final kind = kinds['${e['partyId']}'] ??
          (e['kind'] == 'Purchase' ? 'Supplier' : e['kind'] == 'Debt' ? 'Customer' : '');
        if (kind == 'Customer') receivables += (e['delta'] as num? ?? 0);
        if (kind == 'Supplier') payables += (e['delta'] as num? ?? 0);
      }
      final latestDebtors = <String, Map<String, dynamic>>{
        for (final p in customers) '${p['id']}': p,
        // Prefer a fresh server dashboard row over an older local snapshot.
        for (final row in (base['topDebtors'] as List? ?? []).whereType<Map>())
          '${row['id']}': Map<String, dynamic>.from(row),
      };
      final debtors = latestDebtors.values.map((p) => {
        ...p,
        'balance': (p['balance'] as num? ?? 0) +
            OfflineProjection.partyDelta('${p['id']}', entries),
      }).where((p) => (p['balance'] as num? ?? 0) != 0).toList();
      debtors.sort((a,b) => (b['balance'] as num).abs().compareTo((a['balance'] as num).abs()));
      final summary = Map<String, dynamic>.from(base['summary'] as Map? ?? {});
      return {
        ...base,
        'summary': {
          ...summary,
          'receivables': ((summary['receivables'] as num? ?? 0) + receivables).clamp(0, double.infinity),
          'payables': ((summary['payables'] as num? ?? 0) + payables).clamp(0, double.infinity),
        },
        'topDebtors': debtors.take(5).toList(),
        'localPendingCount': entries.length,
      };
    }
    return base;
  }

  // Cache the primary account lists while online, so search and party selection
  // keep working after connectivity is lost, even with changed search terms.
  Future<void> warmOfflineCatalog() async {
    if (_warming || _shopId == null || _access == null || isOffline || offlineExpired) return;
    _warming = true;
    final generation = _generation;
    bool ready() => generation == _generation && !isOffline && !offlineExpired;
    try {
      for (final path in [
        if (_verifiedOwnerId != null) '/api/workers',
        '/api/settings', '/api/dashboard', '/api/customers/overview', '/api/suppliers/overview',
        '/api/products/categories',
      ]) {
        if (!ready()) return;
        try { await get(path); } catch (_) { if (!ready()) return; }
      }
      // Sequential pages keep memory/network pressure low on old phones.
      for (final spec in <(String, Json)>[
        ('/api/products', {'search': ''}),
        ('/api/customers', {'search': '', 'sort': 'name'}),
        ('/api/suppliers', {'search': '', 'sort': 'name'}),
        ('/api/transactions', {'partyKind': 'Customer'}),
        ('/api/transactions', {'partyKind': 'Supplier'}),
      ]) {
        if (!ready()) return;
        try {
          for (var page = 1; ready(); page++) {
            final query = <String, dynamic>{...spec.$2, 'page': page, 'size': 100};
            await get(spec.$1, query: query);
            if (!ready()) return;
            final raw = await offlineVault.readSnapshot(savedShopId, spec.$1, query);
            if (raw is! Map) break;
            final data = raw;
            final items = data['items'];
            if (items is! List || items.isEmpty || !ready()) break;
            final total = (data['total'] as num?)?.toInt();
            final size = (data['pageSize'] as num?)?.toInt() ?? 100;
            if (size <= 0 || items.length < size || (total != null && page * size >= total)) break;
          }
        } catch (_) { if (!ready()) return; }
      }
    } finally { _warming = false; }
  }

  /// Returns the number of successfully synchronized operations. Failed
  /// operations are retained, never silently dropped or assigned new IDs.
  Future<int> synchronize() =>
      _synchronizing ??= _synchronize().whenComplete(() => _synchronizing = null);

  Future<int> _synchronize() async {
    final shop = _shopId;
    final owner = _verifiedOwnerId;
    final generation = _generation;
    if (shop == null) return 0;
    if (_access == null) await refresh();
    if (_access == null || generation != _generation || _shopId != shop) {
      throw ApiFailure('الاتصال بالخادم غير متاح للمزامنة.');
    }
    final status = _responseObject(await request('GET', '/api/subscription', forceOnline: true));
    if (generation != _generation || _shopId != shop || status['id'] != shop) {
      throw ApiFailure('تغيّرت جلسة الدخول.');
    }
    if (status['active'] != true || status['suspended'] == true) {
      throw ApiFailure('الاشتراك غير فعال. العمليات المحلية محفوظة.', status: 403);
    }
    var completed = 0;
    final entries = await offlineVault.readOutbox(shop);
    final workerDeletes = await offlineVault.readWorkerDeletes(shop, owner);
    ApiFailure? workerFailure;
    if (owner != null) {
      for (final entry in workerDeletes) {
        final workerId = '${entry['workerId']}';
        try {
          await _sendWorkerDelete(shop, owner, workerId, generation);
          completed++;
        } on ApiFailure catch (e) {
          if (generation != _generation) rethrow;
          await offlineVault.recordWorkerDeleteError(shop, owner, workerId, e.message);
          workerFailure = e;
          if (e.status == null || e.status! >= 500) {
            _setOffline(true);
            throw e;
          }
          // Keep the request for review/retry. Never claim the server deleted it.
          if (e.status == 401 || e.status == 403) throw e;
        }
      }
    }
    if (owner != null) {
      for (final rename in await offlineVault.readWorkerRenames(shop, owner)) {
        if (generation != _generation || _shopId != shop) throw ApiFailure('تغيّرت جلسة الدخول.');
        final id = '${rename['workerId']}'; final name = '${rename['workerName']}';
        if (workerDeletes.any((e) => e['workerId'] == id)) continue;
        if (rename['lastError'] != null) continue; // explicit review, not silent overwrite
        try {
          await request('PUT', '/api/workers/${Uri.encodeComponent(id)}/name', forceOnline: true,
            body: {'name': name, 'expectedName': rename['expectedName']});
          _workerCacheVersion++;
          await offlineVault.confirmWorkerRename(shop, owner, id, name);
          completed++;
        } on ApiFailure catch (e) {
          if (generation != _generation || e.status == null || e.status! >= 500 || e.status == 429) rethrow;
          await offlineVault.recordWorkerRenameError(shop, owner, id, name, e.message);
          if (e.status == 401 || e.status == 403) rethrow;
          workerFailure = e;
        }
      }
    }
    if (generation != _generation || _shopId != shop) {
      throw ApiFailure('تغيّرت جلسة الدخول.');
    }
    final actor = _verifiedUserId;
    final catalog = await offlineCatalog.pending(shop,actor);
    final ordered = <Json>[...entries.where((e)=>e['userId']==actor && actor!=null), ...catalog];
    ordered.sort((a,b)=>'${a['savedAt']}'.compareTo('${b['savedAt']}'));
    for (final entry in ordered) {
      if (generation != _generation || _shopId != shop || actor != _verifiedUserId) throw ApiFailure('تغيّرت جلسة الدخول.');
      final body = Map<String,dynamic>.from(entry['body'] as Map);
      if (entry['kind'] == 'CatalogMutation') {
        final id = '${entry['operationId']}';
        if (entry['lastError'] != null) throw ApiFailure('راجع عملية بيانات معلقة في مركز المزامنة.');
        try {
          final isSettings = entry['collection']=='/api/settings';
          final response = await request('${entry['method']}', isSettings ? '/api/settings/offline' : '${entry['path']}',
            body:isSettings ? {'settings':body,'expected':entry['expected']} : body, forceOnline:true,
            extraHeaders:{'X-Offline-Operation':id, if(!isSettings && entry['expected']!=null) 'X-Offline-Expected':base64Encode(utf8.encode(jsonEncode(entry['expected'])))});
          if (generation != _generation) throw ApiFailure('تغيّرت جلسة الدخول.');
          if (entry['method']!='DELETE' && (response is! Map || (isSettings ? response['collectionAccounts'] is! List : '${response['id']}'!='${entry['entityId']}'))) {
            throw ApiFailure('رد المزامنة غير مطابق للسجل؛ العملية محفوظة.');
          }
          _catalogCacheVersion++;
          if (entry['collection']=='/api/workers') {
            _workerCacheVersion++;
            final old = await offlineVault.readSnapshot(shop,'/api/workers',null);
            final rows = (old is Map ? old['workers'] as List? : null) ?? [];
            await offlineVault.saveWorkerSnapshot(shop,{'workers':[...rows.where((w)=>w is Map && w['id']!=response['id']),response],'limit':2});
          } else if (entry['collection']=='/api/transactions') {
            await offlineVault.confirmCatalog(shop,'/api/transactions','${entry['entityId']}',response);
            // Refresh affected authoritative balance before acknowledging.
            final party = await request('GET','/api/parties/${response['partyId']}',forceOnline:true);
            if (generation != _generation || _shopId != shop) throw ApiFailure('تغيّرت جلسة الدخول.');
            if (party is! Map) throw ApiFailure('لم يتم تحديث الرصيد بعد.');
            await offlineVault.confirmCatalog(shop,party['kind']=='Supplier'?'/api/suppliers':'/api/customers','${party['id']}',party);
          } else if (isSettings) {
            await offlineVault.saveSnapshot(shop,'/api/settings',null,response);
          } else {
            await offlineVault.confirmCatalog(shop,'${entry['collection']}','${entry['entityId']}',response,deleted:entry['method']=='DELETE');
          }
          await offlineCatalog.acknowledge(shop,actor!,id);
          completed++;
        } on ApiFailure catch(e) {
          if ([400,404,409,422].contains(e.status)) await offlineCatalog.error(shop,actor!,id,e.message);
          rethrow;
        }
      } else {
        if (entry['blocked'] == true) {
          if (catalog.isNotEmpty) throw ApiFailure('راجع الحركة المالية المرفوضة قبل مزامنة التعديلات التالية.');
          continue;
        }
        try {
          final response = await request('POST','/api/transactions',body:body,forceOnline:true);
          if(response is Map && response['queued']==true) break;
          completed++;
        } on ApiFailure catch(e) {
          if ([400,404,409,422].contains(e.status) && catalog.isEmpty) continue;
          rethrow;
        }
      }
    }
    if (workerFailure != null) throw workerFailure;
    return completed;
  }

  String? _access, _refresh;
  DateTime? _refreshExpiry;
  int _generation = 0;
  Future<void>? _refreshing;
  Future<void> _writes = Future.value();
  VoidCallback? onSignedOut, onForbidden;
  bool get signedIn => _access != null || offlineSession;
  Future<void> _write(Future<void> Function() action) {
    final next = _writes.catchError((_) {}).then((_) => action());
    _writes = next;
    return next;
  }

  Future<void> _accept(Json json, int generation) async {
    if (generation != _generation) throw ApiFailure('تغيّرت جلسة الدخول.');
    final access = json['accessToken'];
    final refresh = json['refreshToken'];
    final expiryValue = json['refreshTokenExpiresAt'];
    final expiry = expiryValue is String
        ? DateTime.tryParse(expiryValue)
        : null;
    if (access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty ||
        expiry == null) {
      throw ApiFailure('استجابة تسجيل الدخول غير صالحة. تواصل مع الإدارة.');
    }
    await _write(() async {
      if (generation != _generation) return;
      await storage.write(
        'session',
        jsonEncode({
          'refreshToken': refresh,
          'refreshTokenExpiresAt': expiry.toIso8601String(),
        }),
      );
    });
    if (generation != _generation) throw ApiFailure('تغيّرت جلسة الدخول.');
    _access = access;
    _refresh = refresh;
    _refreshExpiry = expiry;
  }

  /// Public shop signup: never claims approval of a payment.
  Future<Json> registerShop(Json data) async {
    try {
      final result = await dio.post('/api/registration', data: data);
      return _responseObject(result.data);
    } on DioException catch (e) {
      throw ApiFailure.from(e);
    }
  }

  /// Modify an existing pending signup; never invokes registration again.
  /// Owner password is checked by the server before changing transfer details.
  Future<Json> updatePendingRegistration(Json data) async {
    try {
      final result = await dio.put('/api/registration/pending-activation', data: data);
      return _responseObject(result.data);
    } on DioException catch (e) {
      throw ApiFailure.from(e);
    }
  }

  Future<void> login(String phone, String password) async {
    try {
      // Only replace an existing owner's session AFTER the worker password
      // has been accepted. A mistyped password leaves the old session intact.
      final result = await dio.post(
        '/api/auth/login',
        data: {'phoneNumber': phone, 'password': password},
      );
      final tokens = _responseObject(result.data);
      final generation = ++_generation;
      await _accept(tokens, generation);
      _shopId = null;
      _verifiedOwnerId = null;
      _verifiedUserId = null;
      _verifiedAt = null;
      _maxObservedAt = null;
      _clockUntrusted = false;
      _monotonicBase = null;
      _graceWatch.stop();
      lastVerifiedStatus = null;
      await SyncReminders.cancel();
      _setOffline(false);
      // A new identity must not inherit a previous account's offline snapshots.
      await storage.delete('offline.identity');
    } on DioException catch (e) {
      throw ApiFailure.from(e);
    }
  }

  Future<void> restore() async {
    try {
      final raw = await storage.read('session');
      if (raw == null) return;
      final saved = jsonDecode(raw) as Map;
      _refresh = saved['refreshToken'] as String;
      _refreshExpiry = DateTime.parse(saved['refreshTokenExpiresAt'] as String);
      // Load the verified metadata first, even when the refresh succeeds but
      // the following subscription request loses connectivity.
      final restored = await _restoreOfflineIdentity();
      if (!(_refreshExpiry?.isAfter(DateTime.now()) ?? false) && restored) return;
      try {
        await refresh();
      } on ApiFailure catch (e) {
        if (e.status == null && restored) return;
        if (e.status == 401) await clear();
      }
    } catch (_) {
      // Corrupted local login cannot be trusted for offline access.
      await clear();
    }
  }

  Future<void> refresh() =>
      _refreshing ??= _rotate().whenComplete(() => _refreshing = null);
  Future<void> _rotate() async {
    final generation = _generation;
    if (_refresh == null ||
        !(_refreshExpiry?.isAfter(DateTime.now()) ?? false)) {
      // Do not discard the remembered identity or pending transactions when
      // disconnected; online reauthentication is still required to sync.
      if (_shopId != null && await _restoreOfflineIdentity()) {
        throw ApiFailure('انتهت جلسة الخادم؛ الحركات المحلية محفوظة حتى إعادة تسجيل الدخول.');
      }
      await clear();
      throw ApiFailure('انتهت الجلسة.', status: 401);
    }
    try {
      final result = await dio.post(
        '/api/auth/refresh',
        data: {'refreshToken': _refresh},
      );
      await _accept(_responseObject(result.data), generation);
      _setOffline(false);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        if (generation == _generation) await clear();
        throw ApiFailure('انتهت جلسة الدخول. سجّل الدخول مجدداً.', status: 401);
      }
      if (e.response == null) {
        // Do not discard an authenticated device's local data on a network loss.
        // A lost refresh response may rotate the server token; a later 401 then
        // requires reauthentication, rather than unsafe token replay loops.
        if (generation == _generation) _setOffline(true);
      }
      throw ApiFailure.from(e);
    }
  }

  Future<dynamic> request(
    String method,
    String path, {
    Json? query,
    Object? body,
    bool forceOnline = false,
    Map<String,String>? extraHeaders,
  }) async {
    final generation = _generation;
    final original = _access;
    final workerCacheVersion = _workerCacheVersion;
    final catalogCacheVersion = _catalogCacheVersion;
    final readable = method == 'GET';
    final subscription = readable && path == '/api/subscription';
    if (!subscription) _requireOfflineAccess();
    if (readable && path == '/api/workers' && _offlineMode && _verifiedOwnerId == null) {
      throw ApiFailure('اتصل بالإنترنت بحساب صاحب المحل لتحميل العاملين.');
    }
    final newOfflineAction = path == '/api/workers' || path.startsWith('/api/transactions/');
    if (!forceOnline && OfflineCatalog.supports(method,path) && lastVerifiedStatus?['offlineCatalogVersion'] == 1 &&
        (!newOfflineAction || lastVerifiedStatus?['offlineActionVersion']==1)) {
      return _queueCatalog(method,path,body);
    }
    final queuedTransaction =
        method == 'POST' &&
        path == '/api/transactions' &&
        body is Map<String, dynamic> &&
        body['operationId'] is String &&
        _shopId != null;
    final transactionBody = queuedTransaction
        ? Map<String, dynamic>.from(body as Map)
        : null;
    if (queuedTransaction) {
      // Durable write first. Sending and crash recovery reuse the same ID.
      final userId = _verifiedUserId;
      if (userId == null) throw ApiFailure('اتصل بالخادم للتحقق من هوية مسجّل الحركة.');
      await offlineVault.addTransaction(_shopId!, transactionBody!, userId: userId);
      if (generation != _generation) throw ApiFailure('تغيّرت جلسة الدخول.');
      if (!forceOnline && (_offlineMode || (await pendingCatalog()).isNotEmpty)) {
        return {'queued': true, 'operationId': transactionBody!['operationId']};
      }
    }

    Future<dynamic> snapshotOrThrow(ApiFailure error) async {
      if (forceOnline) {
        if (error.status == null || error.status! >= 500) _setOffline(true);
        throw error;
      }
      if (!subscription) _requireOfflineAccess();
      if (readable && _shopId != null &&
          (path != '/api/workers' || _verifiedOwnerId != null) &&
          (error.status == null || error.status! >= 500)) {
        if (['/api/reports/summary','/api/reports/cashflow','/api/reports/purchases'].contains(path)) {
          _setOffline(true);
          return localReport(path,query);
        }
        var saved = await offlineVault.readBestSnapshot(_shopId!, path, query);
        if (saved == null && ['/api/customers','/api/suppliers','/api/products'].contains(path) &&
            (await pendingCatalog()).any((r)=>r['collection']==path)) saved = {'items':[], 'total':0, 'offlinePartial':true};
        if (path.startsWith('/api/parties/') && !path.endsWith('/statement')) {
          final id = path.split('/').last;
          final row = await _catalogParty(id);
          if (row != null && (saved == null || (await pendingCatalog()).any((r)=>r['entityId']==id))) saved = row;
        }
        if (saved == null && path == '/api/transactions') {
          saved = {'items': <dynamic>[], 'total': 0, 'offlinePartial': true};
        }
        if (saved == null && path.startsWith('/api/parties/') &&
            path.endsWith('/statement')) {
          final id = path.split('/')[3];
          final party = await _catalogParty(id);
          if (party != null) {
            saved = {
              'party': party,
              'openingBalance': query?['from'] == null ? party['openingBalance'] : null,
              'closingBalance': query?['to'] == null ? party['balance'] : null,
              'entries': (await offlineVault.indexedItems(_shopId!, '/api/transactions'))
                  .where((e) => '${e['partyId']}' == id && OfflineProjection.isInsideDate(e, query)).toList()
                  ..sort((a,b) => '${a['occurredAt']}'.compareTo('${b['occurredAt']}')),
              'offlinePartial': true,
            };
          }
        }
        if (saved != null) {
          _setOffline(true);
          return _withLocalMovements(path, query, saved);
        }
      }
      if (queuedTransaction && (error.status == null || error.status! >= 500)) {
        _setOffline(true);
        return {'queued': true, 'operationId': transactionBody!['operationId']};
      }
      throw error;
    }

    if (!forceOnline && readable && _shopId != null && path.startsWith('/api/parties/')) {
      final id = path.split('/')[3];
      if ((await pendingCatalog()).any((r)=>r['entityId']==id && r['method']=='POST' && ['/api/customers','/api/suppliers'].contains(r['collection']))) {
        final party = await _catalogParty(id);
        if (party != null) {
          if (!path.endsWith('/statement')) return _withLocalMovements(path,query,party);
          return _withLocalMovements(path,query,{'party':party,'entries':<dynamic>[],
            'openingBalance':party['openingBalance'],'closingBalance':party['balance'],'offlinePartial':true});
        }
      }
    }
    // An already-offline session should display the durable snapshot
    // immediately instead of waiting through another network timeout.
    if (!forceOnline && _offlineMode && readable && _shopId != null) {
      if (['/api/reports/summary','/api/reports/cashflow','/api/reports/purchases'].contains(path)) return localReport(path,query);
      final cached = await offlineVault.readBestSnapshot(_shopId!, path, query);
      if (cached != null) return _withLocalMovements(path, query, cached);
      return snapshotOrThrow(ApiFailure('البيانات غير متاحة محلياً. اتصل بالإنترنت أولاً.'));
    }
    if (_offlineMode && !readable && !forceOnline && !queuedTransaction) {
      throw ApiFailure('هذه العملية تحتاج الاتصال بالخادم حالياً.');
    }
    if (_access == null) {
      return snapshotOrThrow(
        ApiFailure('البيانات غير متاحة محلياً. اتصل بالإنترنت أولاً.'),
      );
    }
    Future<Response<dynamic>> send() => dio.request(
      path,
      data: body,
      queryParameters: query,
      options: Options(
        method: method,
        headers: {'Authorization': 'Bearer $_access', ...?extraHeaders},
      ),
    );
    try {
      Response<dynamic> result;
      try {
        result = await send();
      } on DioException catch (e) {
        if (e.response?.statusCode != 401 ||
            original == null ||
            generation != _generation) {
          rethrow;
        }
        if (_access == original) await refresh();
        if (generation != _generation || _access == null) {
          throw ApiFailure('انتهت الجلسة.', status: 401);
        }
        result = await send();
      }
      if (generation != _generation) throw ApiFailure('تغيّرت جلسة الدخول.');
      if (subscription) await _rememberLiveStatus(_responseObject(result.data));
      _setOffline(false);
      if (readable && _shopId != null) {
        if (path == '/api/workers') {
          // A GET started before a successful DELETE must not overwrite its
          // updated offline snapshot with a stale worker list.
          if (workerCacheVersion == _workerCacheVersion) {
            await offlineVault.saveWorkerSnapshot(_shopId!, result.data);
          } else {
            final saved = await offlineVault.readSnapshot(_shopId!, path, null);
            if (saved != null) return _withLocalMovements(path, query, saved);
          }
        } else {
          final isCatalogRead = path == '/api/settings' || path == '/api/transactions' || path.startsWith('/api/parties/') ||
              path.startsWith('/api/customers') || path.startsWith('/api/suppliers') || path.startsWith('/api/products');
          if (isCatalogRead && catalogCacheVersion != _catalogCacheVersion) {
            // A response that started before a catalog acknowledgement must not resurrect a deleted product.
            final saved = await offlineVault.readBestSnapshot(_shopId!,path,query);
            if (saved != null) return _withLocalMovements(path,query,saved);
            return _withLocalMovements(path,query,result.data);
          }
          await offlineVault.saveSnapshot(_shopId!, path, query, result.data);
          await offlineVault.indexResponse(_shopId!, path, query, result.data);
          if (path.startsWith('/api/parties/') && result.data is Map) {
            final responseMap = result.data as Map;
            if (path.endsWith('/statement') && responseMap['entries'] is List) {
              await offlineVault.indexResponse(_shopId!,'/api/transactions',null,{'items':responseMap['entries']});
            }
            final row = path.endsWith('/statement') ? responseMap['party'] : responseMap;
            if (row is Map) {
            final collection = row['kind']=='Supplier' ? '/api/suppliers' : '/api/customers';
            await offlineVault.indexResponse(_shopId!,collection,null,{'items':[row]});
            }
          }
        }
      }
      if (queuedTransaction) {
        final saved = result.data;
        if (saved is! Map || '${saved['operationId']}'!='${transactionBody!['operationId']}' || '${saved['id'] ?? ''}'.isEmpty) {
          throw ApiFailure('رد حفظ الحركة غير مطابق. ستبقى العملية في قائمة المزامنة.');
        }
        final shop = _shopId!;
        dynamic card;
        try { card = await request('GET','/api/parties/${saved['partyId']}',forceOnline:true); }
        on ApiFailure {
          if (generation != _generation) throw ApiFailure('تغيّرت جلسة الدخول.');
          return {'queued':true,'operationId':transactionBody!['operationId']};
        }
        if (generation != _generation || _shopId != shop) throw ApiFailure('تغيّرت جلسة الدخول.');
        if (card is! Map) throw ApiFailure('لم يتم تحديث الرصيد بعد؛ الحركة محفوظة للمراجعة.');
        await offlineVault.confirmCatalog(shop,'/api/transactions','${saved['id']}',saved);
        await offlineVault.confirmCatalog(shop,card['kind']=='Supplier'?'/api/suppliers':'/api/customers','${card['id']}',card);
        await offlineVault.removeTransaction(
          _shopId!,
          '${transactionBody!['operationId']}',
        );
      }
      return readable ? _withLocalMovements(path, query, result.data) : result.data;
    } on DioException catch (e) {
      if (e.response?.statusCode == 403 && path != '/api/subscription') {
        onForbidden?.call();
      }
      if (e.response?.statusCode == 401 && generation == _generation) {
        await clear();
      }
      final failure = ApiFailure.from(e);
      // Keep rejected financial operations for explicit review, but stop
      // automatic retries. Never silently lose a locally recorded payment.
      if (queuedTransaction &&
          _shopId != null &&
          [400, 404, 409, 422].contains(failure.status)) {
        await offlineVault.blockTransaction(
          _shopId!,
          '${transactionBody!['operationId']}',
          failure.message,
        );
      }
      return snapshotOrThrow(failure);
    } on ApiFailure catch (e) {
      return snapshotOrThrow(e);
    }
  }

  /// Download an authenticated paper-invoice image. Never use a public URL:
  /// invoices contain sensitive supplier information. Cache only after viewing,
  /// scoped to the signed-in shop so it can be viewed offline again.
  Future<Uint8List> getInvoicePhoto(String id) async {
    _requireOfflineAccess();
    final shopId = _shopId;
    if (shopId == null || shopId.isEmpty) {
      throw ApiFailure('حساب المحل غير متاح.');
    }
    final key = 'invoice.photo.$shopId.$id';
    final saved = await storage.read(key);
    if (_access == null || _offlineMode) {
      if (saved != null) return base64Decode(saved);
      throw ApiFailure('صورة الفاتورة غير متاحة دون إنترنت قبل فتحها مرة واحدة.');
    }
    try {
      Future<Response<List<int>>> fetch() => dio.get<List<int>>(
        '/api/transactions/$id/invoice-photo',
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Authorization': 'Bearer $_access'},
        ),
      );
      late Response<List<int>> response;
      try {
        response = await fetch();
      } on DioException catch (e) {
        if (e.response?.statusCode != 401) rethrow;
        await refresh();
        if (_access == null) throw ApiFailure('انتهت جلسة الدخول.');
        response = await fetch();
      }
      final bytes = Uint8List.fromList(response.data ?? <int>[]);
      if (bytes.isEmpty) throw ApiFailure('صورة الفاتورة غير متاحة.');
      await storage.write(key, base64Encode(bytes));
      return bytes;
    } on DioException catch (e) {
      if (saved != null &&
          (e.response?.statusCode == null || e.response!.statusCode! >= 500)) {
        return base64Decode(saved);
      }
      throw ApiFailure.from(e);
    }
  }

  Future<Json> get(String path, {Json? query}) async =>
      _responseObject(await request('GET', path, query: query));
  Future<void> logout() async {
    if ((await pendingCount()) != 0) {
      throw ApiFailure(
        'توجد حركات لم تتزامن بعد. زامنها قبل تسجيل الخروج حتى لا يتعطل إرسالها.',
      );
    }
    if (_access != null) await request('POST', '/api/auth/logout');
    await clear();
  }

  Future<void> clear() async {
    ++_generation;
    _access = null;
    _refresh = null;
    _refreshExpiry = null;
    _shopId = null;
    _verifiedOwnerId = null;
    _verifiedUserId = null;
    _verifiedAt = null;
    _maxObservedAt = null;
    _clockUntrusted = false;
    _monotonicBase = null;
    _graceWatch.stop();
    lastVerifiedStatus = null;
    await SyncReminders.cancel();
    _setOffline(false);
    await storage.delete('offline.identity');
    await storage.delete('offline.clock');
    onSignedOut?.call();
    await _write(() => storage.delete('session'));
  }
}
