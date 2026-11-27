import 'dart:convert';
import 'package:deenbook/core/api.dart';
import 'package:deenbook/core/offline_grace.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fakes.dart';

void main() {
  final verified = DateTime.utc(2026, 11, 20, 12);
  test('grace is exactly seven elapsed days; reminders on 5, 6 and 7', () {
    expect(OfflineGrace(verified, verified.add(const Duration(days: 4, hours: 23))).reminderDay, isNull);
    expect(OfflineGrace(verified, verified.add(const Duration(days: 5))).reminderDay, 5);
    expect(OfflineGrace(verified, verified.add(const Duration(days: 6))).reminderDay, 6);
    expect(OfflineGrace(verified, verified.add(const Duration(days: 7, milliseconds: -1))).expired, false);
    final end = OfflineGrace(verified, verified.add(const Duration(days: 7)));
    expect(end.reminderDay, 7);
    expect(end.expired, true);
    expect(OfflineGrace(verified, verified.subtract(const Duration(seconds: 1))).expired, true);
    expect(OfflineGrace(verified, verified, clockUntrusted: true).expired, true);
  });

  test('administrator policy and subscription expiry shorten the offline lease', () {
    final policy = OfflineGrace(verified, verified.add(const Duration(days: 3)), days: 3);
    expect(policy.expired, true);
    expect(OfflineGrace(verified, verified.add(const Duration(days: 1)), days: 3).reminderDay, 1);
    expect(OfflineGrace(verified, verified.add(const Duration(days: 7)), days: 99).expired, true);
    expect(OfflineGrace(verified, verified.add(const Duration(hours: 12)),
      paidUntil: verified.add(const Duration(hours: 12))).expired, true);
    expect(OfflineGrace.parseDays(null), 7);
  });

  test('expired restart blocks writes and cache reads, retains queue and requires online verification', () async {
    final storage = MemoryStorage();
    var online = true;
    var actor = 'owner-1';
    final posted = <String>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'));
    dio.httpClientAdapter = Adapter((r) {
      if (!online) throw DioException(requestOptions: r, type: DioExceptionType.connectionError);
      if (r.path.startsWith('/api/auth/')) return response(token());
      if (r.path == '/api/subscription') return response({
        'id': 'shop-1', 'userId': actor, 'isOwner': actor == 'owner-1', 'active': true,
        'suspended': false, 'paidUntil': DateTime.now().toUtc().add(const Duration(days: 30)).toIso8601String(),
      });
      if (r.path == '/api/dashboard') return response({'summary': {}});
      if (r.path == '/api/transactions' && r.method == 'POST') {
        posted.add('${r.data['operationId']}'); return response({'id': 'server-entry'});
      }
      return response({});
    });
    var api = Api(storage, client: dio);
    await api.login('0599000001', 'password');
    await api.get('/api/subscription');
    await api.get('/api/dashboard');
    online = false;
    await api.get('/api/dashboard');
    final body = {'operationId': 'one', 'partyId': 'party-1', 'kind': 'Debt', 'amount': 10};
    expect((await api.request('POST', '/api/transactions', body: body))['queued'], true);
    final identity = jsonDecode((await storage.read('offline.identity'))!) as Map;
    identity['verifiedAt'] = DateTime.now().toUtc().subtract(const Duration(days: 7, minutes: 1)).toIso8601String();
    await storage.write('offline.identity', jsonEncode(identity));
    api = Api(storage, client: dio);
    await api.restore();
    expect(api.offlineExpired, true);
    await api.get('/api/subscription'); // cached response cannot renew grace
    expect(api.offlineExpired, true);
    await expectLater(api.get('/api/dashboard'), throwsA(isA<ApiFailure>()));
    await expectLater(api.request('POST', '/api/transactions', body: {...body, 'operationId': 'two'}), throwsA(isA<ApiFailure>()));
    expect(await api.pendingCount(), 1);
    await expectLater(api.synchronize(), throwsA(isA<ApiFailure>()));
    expect(api.offlineExpired, true);
    online = true;
    actor = 'worker-2';
    await api.login('0599000002', 'password');
    await api.get('/api/subscription');
    expect(await api.synchronize(), 0);
    expect(posted, isEmpty);
    expect((await api.offlineVault.readOutbox('shop-1')).length, 1);
    actor = 'owner-1';
    await api.login('0599000001', 'password');
    await api.get('/api/subscription');
    expect(api.offlineExpired, false);
    expect(await api.synchronize(), 1);
    expect(posted, ['one']);
    expect(await api.pendingCount(), 0);
  });
}
