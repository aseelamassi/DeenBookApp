import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'storage.dart';
import 'offline.dart';

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
  String? _shopId;
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

  Future<void> rememberStatus(Json data) async {
    final id = data['id'];
    if (id is! String || id.isEmpty) return;
    _shopId = id;
    if (!_offlineMode) {
      await storage.write('offline.identity', jsonEncode({
        'shopId': id,
        'verifiedAt': DateTime.now().toUtc().toIso8601String(),
      }));
      await offlineVault.saveSnapshot(id, '/api/subscription', null, data);
    }
  }

  Future<bool> _restoreOfflineIdentity() async {
    try {
      final raw = await storage.read('offline.identity');
      if (raw == null) return false;
      final identity = jsonDecode(raw) as Map;
      final id = identity['shopId'];
      final verified = DateTime.tryParse('${identity['verifiedAt']}');
      if (id is! String || id.isEmpty || verified == null ||
          DateTime.now().toUtc().difference(verified.toUtc()) >
              const Duration(days: 7) ||
          DateTime.now().toUtc().isBefore(verified.toUtc().subtract(const Duration(minutes: 5)))) {
        return false;
      }
      final status = await offlineVault.readSnapshot(id, '/api/subscription', null);
      final until = status is Map ? DateTime.tryParse('${status['paidUntil']}') : null;
      if (status is! Map || status['suspended'] == true || until == null ||
          !until.isAfter(DateTime.now().toUtc())) return false;
      _shopId = id;
      _setOffline(true);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<int> pendingCount() async =>
      (await offlineVault.readOutbox(savedShopId)).length;

  /// Returns the number of successfully synchronized operations. Failed
  /// operations are retained, never silently dropped or assigned new IDs.
  Future<int> synchronize() async {
    if (_shopId == null) return 0;
    if (_access == null) await refresh();
    if (_access == null) throw ApiFailure('الاتصال بالخادم غير متاح للمزامنة.');
    var completed = 0;
    final entries = await offlineVault.readOutbox(_shopId!);
    for (final entry in entries) {
      if (entry['blocked'] == true) continue;
      final body = Map<String, dynamic>.from(entry['body'] as Map);
      try {
        final response = await request('POST', '/api/transactions', body: body);
        if (response is Map && response['queued'] == true) break;
        completed++;
      } on ApiFailure catch (e) {
        if ([400, 404, 409, 422].contains(e.status)) continue;
        rethrow;
      }
    }
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

  Future<void> login(String phone, String password) async {
    final generation = ++_generation;
    _shopId = null;
    _setOffline(false);
    try {
      final result = await dio.post(
        '/api/auth/login',
        data: {'phoneNumber': phone, 'password': password},
      );
      await _accept(_responseObject(result.data), generation);
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
      try {
        await refresh();
      } on ApiFailure catch (e) {
        if (e.status == null && await _restoreOfflineIdentity()) return;
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
  }) async {
    final generation = _generation;
    final original = _access;
    final readable = method == 'GET';
    final queuedTransaction = method == 'POST' &&
        path == '/api/transactions' && body is Map<String, dynamic> &&
        body['operationId'] is String && _shopId != null;
    final transactionBody = queuedTransaction ? Map<String, dynamic>.from(body as Map) : null;
    if (queuedTransaction) {
      // Durable write first. Sending and crash recovery reuse the same ID.
      await offlineVault.addTransaction(_shopId!, transactionBody!);
    }

    Future<dynamic> snapshotOrThrow(ApiFailure error) async {
      if (readable && _shopId != null && error.status == null) {
        final saved = await offlineVault.readSnapshot(_shopId!, path, query);
        if (saved != null) {
          _setOffline(true);
          return saved;
        }
      }
      if (queuedTransaction && error.status == null) {
        _setOffline(true);
        return {'queued': true, 'operationId': transactionBody!['operationId']};
      }
      throw error;
    }

    if (_access == null) {
      return snapshotOrThrow(ApiFailure('البيانات غير متاحة محلياً. اتصل بالإنترنت أولاً.'));
    }
    Future<Response<dynamic>> send() => dio.request(
      path,
      data: body,
      queryParameters: query,
      options: Options(
        method: method,
        headers: {'Authorization': 'Bearer $_access'},
      ),
    );
    try {
      Response<dynamic> result;
      try {
        result = await send();
      } on DioException catch (e) {
        if (e.response?.statusCode != 401 || original == null ||
            generation != _generation) rethrow;
        if (_access == original) await refresh();
        if (generation != _generation || _access == null) {
          throw ApiFailure('انتهت الجلسة.', status: 401);
        }
        result = await send();
      }
      if (generation != _generation) throw ApiFailure('تغيّرت جلسة الدخول.');
      _setOffline(false);
      if (readable && _shopId != null) {
        await offlineVault.saveSnapshot(_shopId!, path, query, result.data);
      }
      if (queuedTransaction) {
        await offlineVault.removeTransaction(_shopId!, '${transactionBody!['operationId']}');
      }
      return result.data;
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
      if (queuedTransaction && _shopId != null &&
          [400, 404, 409, 422].contains(failure.status)) {
        await offlineVault.blockTransaction(_shopId!,
            '${transactionBody!['operationId']}', failure.message);
      }
      return snapshotOrThrow(failure);
    } on ApiFailure catch (e) {
      return snapshotOrThrow(e);
    }
  }

  Future<Json> get(String path, {Json? query}) async =>
      _responseObject(await request('GET', path, query: query));
  Future<void> logout() async {
    if ((await pendingCount()) != 0) {
      throw ApiFailure('توجد حركات لم تتزامن بعد. زامنها قبل تسجيل الخروج حتى لا يتعطل إرسالها.');
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
    _setOffline(false);
    await storage.delete('offline.identity');
    onSignedOut?.call();
    await _write(() => storage.delete('session'));
  }
}
