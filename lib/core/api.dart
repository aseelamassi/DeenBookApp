import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'storage.dart';

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
  String? _access, _refresh;
  DateTime? _refreshExpiry;
  int _generation = 0;
  Future<void>? _refreshing;
  Future<void> _writes = Future.value();
  VoidCallback? onSignedOut, onForbidden;
  bool get signedIn => _access != null;
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
    try {
      final result = await dio.post(
        '/api/auth/login',
        data: {'phoneNumber': phone, 'password': password},
      );
      await _accept(_responseObject(result.data), generation);
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
      await refresh();
    } catch (_) {
      await clear();
    }
  }

  Future<void> refresh() =>
      _refreshing ??= _rotate().whenComplete(() => _refreshing = null);
  Future<void> _rotate() async {
    final generation = _generation;
    try {
      if (_refresh == null ||
          !(_refreshExpiry?.isAfter(DateTime.now()) ?? false)) {
        throw ApiFailure('انتهت الجلسة.');
      }
      final result = await dio.post(
        '/api/auth/refresh',
        data: {'refreshToken': _refresh},
      );
      await _accept(_responseObject(result.data), generation);
    } catch (_) {
      // A lost response can consume a rotating token; never replay that token.
      if (generation == _generation) await clear();
      throw ApiFailure(
        'انتهت جلسة الدخول أو تعذّر تجديدها. سجّل الدخول مجدداً.',
        status: 401,
      );
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
    Future<Response<dynamic>> send() => dio.request(
      path,
      data: body,
      queryParameters: query,
      options: Options(
        method: method,
        headers: {if (_access != null) 'Authorization': 'Bearer $_access'},
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
      return result.data;
    } on DioException catch (e) {
      if (e.response?.statusCode == 403 && path != '/api/subscription') {
        onForbidden?.call();
      }
      if (e.response?.statusCode == 401 && generation == _generation) {
        await clear();
      }
      throw ApiFailure.from(e);
    }
  }

  Future<Json> get(String path, {Json? query}) async =>
      _responseObject(await request('GET', path, query: query));
  Future<void> logout() async {
    await request('POST', '/api/auth/logout');
    await clear();
  }

  Future<void> clear() async {
    ++_generation;
    _access = null;
    _refresh = null;
    _refreshExpiry = null;
    onSignedOut?.call();
    await _write(() => storage.delete('session'));
  }
}
