import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deenbook/core/api.dart';
import 'package:deenbook/core/format.dart';
import 'package:deenbook/core/storage.dart';
import 'package:deenbook/core/session.dart';
import 'support/fakes.dart';

class UnavailableStorage extends MemoryStorage {
  @override
  Future<String?> read(String key) => Future.error(StateError('unavailable'));
  @override
  Future<void> delete(String key) => Future.error(StateError('unavailable'));
}

void main() {
  test('secure storage failure leaves a recoverable startup state', () async {
    final session = Session(Api(UnavailableStorage(), client: Dio()));
    await session.initialize();
    expect(session.loading, false);
    expect(session.startupError, isNotNull);
  });
  for (final value in [
    '0599000001',
    '٥٩٩٠٠٠٠٠١',
    '+970599000001',
    '00970599000001',
    '+972599000001',
    '۰۵۹۹۰۰۰۰۰۱',
  ]) {
    test(
      'normalizes phone $value',
      () => expect(phoneNumber(value), '+970599000001'),
    );
  }
  for (final value in ['059', 'abc', '+12025551234', '0589000001']) {
    test('rejects phone $value', () => expect(phoneNumber(value), isNull));
  }
  test('money uses exact cents and limits precision', () {
    expect(cents('١٢٣٫٤٥'), 12345);
    expect(cents('0.01'), 1);
    expect(cents('1.999'), isNull);
    expect(cents('1e3'), isNull);
    expect(cents('1000000000'), isNull);
    expect(cents('-20.5', signed: true), -2050);
    expect(cents('-1'), isNull);
  });
  test('date period ends at next local midnight', () {
    final p = period(DateTime(2026, 10, 1), DateTime(2026, 10, 31));
    expect(p['to'], DateTime(2026, 11, 1).toUtc().toIso8601String());
  });
  test('release URL must be HTTPS without credentials', () {
    expect(
      () => validateBaseUrl('http://example.test', release: true),
      throwsFormatException,
    );
    expect(
      () => validateBaseUrl('https://u:p@example.test'),
      throwsFormatException,
    );
    expect(validateBaseUrl('https://example.test/'), 'https://example.test');
  });
  test(
    'payment choices match requested methods',
    () => expect(methods.keys, ['Cash', 'JawwalPay', 'PalPay', 'Bank']),
  );
  test(
    'simultaneous 401 requests rotate once and persist before replay',
    () async {
      final store = MemoryStorage();
      var refreshes = 0;
      final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'));
      dio.httpClientAdapter = Adapter((r) async {
        if (r.path.endsWith('/login')) return response(token());
        if (r.path.endsWith('/refresh')) {
          refreshes++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return response(token('two'));
        }
        if (r.headers['Authorization'] == 'Bearer access-one') {
          return response({}, status: 401);
        }
        expect(
          jsonDecode(store.values['session']!)['refreshToken'],
          'refresh-two',
        );
        return response({'ok': true});
      });
      final api = Api(store, client: dio);
      await api.login('0599000001', 'test');
      await Future.wait(List.generate(8, (_) => api.get('/api/dashboard')));
      expect(refreshes, 1);
      expect(store.values['session'], isNot(contains('accessToken')));
    },
  );
  test('refresh timeout preserves stored credentials for offline recovery', () async {
    final store = MemoryStorage();
    var refreshes = 0;
    final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'));
    dio.httpClientAdapter = Adapter((r) {
      if (r.path.endsWith('/login')) return response(token());
      refreshes++;
      throw DioException(
        requestOptions: r,
        type: DioExceptionType.receiveTimeout,
      );
    });
    final api = Api(store, client: dio);
    await api.login('phone', 'test');
    await expectLater(api.refresh(), throwsA(isA<ApiFailure>()));
    expect(api.signedIn, true);
    expect(store.values['session'], isNotNull);
    await expectLater(api.refresh(), throwsA(isA<ApiFailure>()));
    expect(refreshes, 2);
  });
  test('logout while refresh is in flight cannot resurrect session', () async {
    final gate = Completer<void>(), started = Completer<void>();
    final store = MemoryStorage();
    final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'));
    dio.httpClientAdapter = Adapter((r) async {
      if (r.path.endsWith('/login')) return response(token());
      started.complete();
      await gate.future;
      return response(token('two'));
    });
    final api = Api(store, client: dio);
    await api.login('phone', 'test');
    final pending = expectLater(api.refresh(), throwsA(isA<ApiFailure>()));
    await started.future;
    await api.clear();
    gate.complete();
    await pending;
    expect(api.signedIn, false);
    expect(store.values, isEmpty);
  });
  test('403 keeps authentication and triggers subscription recheck', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'));
    dio.httpClientAdapter = Adapter(
      (r) => r.path.endsWith('/login')
          ? response(token())
          : response({}, status: 403),
    );
    final api = Api(MemoryStorage(), client: dio);
    var denied = 0;
    api.onForbidden = () => denied++;
    await api.login('phone', 'test');
    await expectLater(api.get('/api/dashboard'), throwsA(isA<ApiFailure>()));
    expect(api.signedIn, true);
    expect(denied, 1);
  });
  test('financial 500 is not automatically retried', () async {
    var writes = 0;
    final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'));
    dio.httpClientAdapter = Adapter((r) {
      if (r.path == '/api/auth/login') return response(token());
      writes++;
      return response({}, status: 500);
    });
    final api = Api(MemoryStorage(), client: dio);
    await api.login('phone', 'password');
    await expectLater(
      api.request('POST', '/api/transactions', body: {'operationId': 'stable'}),
      throwsA(isA<ApiFailure>()),
    );
    expect(writes, 1);
  });
  test(
    'pending transaction survives recreation and is scoped to shop',
    () async {
      final storage = MemoryStorage();
      await PendingOperation(
        storage,
        'shop-a',
      ).save({'operationId': 'one', 'amount': 123.45});
      expect(await PendingOperation(storage, 'shop-b').read(), isNull);
      expect(
        (await PendingOperation(storage, 'shop-a').read())!['operationId'],
        'one',
      );
    },
  );
  test('restore uses refresh only', () async {
    final storage = MemoryStorage();
    storage.values['session'] = jsonEncode({
      'refreshToken': 'saved',
      'refreshTokenExpiresAt': DateTime.now()
          .add(const Duration(days: 1))
          .toIso8601String(),
    });
    final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'));
    dio.httpClientAdapter = Adapter((r) {
      expect(r.path, '/api/auth/refresh');
      expect(r.data, {'refreshToken': 'saved'});
      return response(token('restored'));
    });
    final api = Api(storage, client: dio);
    await api.restore();
    expect(api.signedIn, true);
  });
}
