import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deenbook/core/api.dart';
import 'package:deenbook/core/offline.dart';

import 'support/fakes.dart';

void main() {
  test(
    'outbox is durable, tenant-isolated and deduplicates operationId',
    () async {
      final store = MemoryStorage();
      final first = OfflineVault(store);
      final body = <String, dynamic>{
        'operationId': 'operation-one',
        'partyId': 'party-1',
        'kind': 'Debt',
        'amount': 15.5,
      };
      await first.addTransaction('shop-a', body);
      await first.addTransaction('shop-a', body);
      expect((await OfflineVault(store).readOutbox('shop-a')).length, 1);
      expect(await OfflineVault(store).readOutbox('shop-b'), isEmpty);
      await first.blockTransaction(
        'shop-a',
        'operation-one',
        'invalid request',
      );
      expect((await first.readOutbox('shop-a')).single['blocked'], true);
      await first.removeTransaction('shop-a', 'operation-one');
      expect(await first.readOutbox('shop-a'), isEmpty);
    },
  );

  test(
    'GET falls back to stored snapshot and queue sync reuses the same ID',
    () async {
      final store = MemoryStorage();
      var internet = true;
      final posted = <String>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'));
      dio.httpClientAdapter = Adapter((r) {
        if (r.path == '/api/auth/login') return response(token());
        if (!internet) {
          throw DioException(
            requestOptions: r,
            type: DioExceptionType.connectionError,
          );
        }
        if (r.path == '/api/subscription') {
          return response({
            'id': 'shop-a',
            'name': 'محل التجربة',
            'active': true,
            'suspended': false,
            'paidUntil': DateTime.now()
                .add(const Duration(days: 5))
                .toUtc()
                .toIso8601String(),
            'isTrial': true,
            'trialDaysRemaining': 5,
          });
        }
        if (r.path == '/api/dashboard') {
          return response({
            'summary': {'receivables': 20},
          });
        }
        if (r.path == '/api/transactions' && r.method == 'POST') {
          posted.add('${r.data['operationId']}');
          return response({'id': 'entry-1'});
        }
        return response({});
      });
      final api = Api(store, client: dio);
      await api.login('0599000001', 'test');
      final status = await api.get('/api/subscription');
      await api.rememberStatus(status);
      expect((await api.get('/api/dashboard'))['summary']['receivables'], 20);

      internet = false;
      expect((await api.get('/api/dashboard'))['summary']['receivables'], 20);
      expect(api.isOffline, isTrue);
      final saved = await api.request(
        'POST',
        '/api/transactions',
        body: {
          'operationId': 'once',
          'kind': 'Debt',
          'partyId': 'party-1',
          'amount': 10,
        },
      );
      expect(saved['queued'], isTrue);
      expect(await api.pendingCount(), 1);
      internet = true;
      expect(await api.synchronize(), 1);
      expect(await api.pendingCount(), 0);
      expect(posted, ['once']);
    },
  );

  test(
    'offline session can reopen only while last verification is fresh',
    () async {
      final store = MemoryStorage();
      final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'));
      dio.httpClientAdapter = Adapter((r) {
        if (r.path.endsWith('/login')) return response(token());
        if (r.path == '/api/subscription') {
          return response({
            'id': 'shop-a',
            'name': 'محل',
            'active': true,
            'suspended': false,
            'paidUntil': DateTime.now()
                .add(const Duration(days: 3))
                .toUtc()
                .toIso8601String(),
          });
        }
        return response({});
      });
      final online = Api(store, client: dio);
      await online.login('0599000001', 'password');
      await online.rememberStatus(await online.get('/api/subscription'));
      final offlineDio = Dio(BaseOptions(baseUrl: 'https://test.invalid'));
      offlineDio.httpClientAdapter = Adapter(
        (r) => throw DioException(
          requestOptions: r,
          type: DioExceptionType.connectionError,
        ),
      );
      final restored = Api(store, client: offlineDio);
      await restored.restore();
      expect(restored.signedIn, isTrue);
      expect(restored.isOffline, isTrue);
      expect((await restored.get('/api/subscription'))['name'], 'محل');
    },
  );
}
