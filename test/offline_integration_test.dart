import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deenbook/core/api.dart';

import 'support/fakes.dart';

void main() {
  test('offline debt is immediately visible in cached customers and statement', () async {
    final memory = MemoryStorage();
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
      if (r.path == '/api/transactions' && r.method == 'POST') {
        posted.add('${r.data['operationId']}');
        return response({'id': 'confirmed-entry'});
      }
      if (r.path == '/api/subscription') {
        return response({
          'id': 'shop-1', 'name': 'محل', 'active': true,
          'paidUntil': DateTime.now().toUtc().add(const Duration(days: 10)).toIso8601String(),
        });
      }
      if (r.path == '/api/customers') return response(page([party()]));
      if (r.path == '/api/parties/customer-1/statement') {
        return response({
          'party': party(), 'entries': <dynamic>[],
          'openingBalance': 125.5, 'closingBalance': 125.5,
        });
      }
      return response({});
    });

    final api = Api(memory, client: dio);
    await api.login('0599000001', 'password');
    await api.rememberStatus(await api.get('/api/subscription'));
    await api.get('/api/customers', query: {
      'search': '', 'sort': 'balance', 'page': 1, 'size': 30,
    });
    await api.get('/api/parties/customer-1/statement');
    internet = false;
    final locallySaved = await api.request('POST', '/api/transactions', body: {
      'operationId': 'offline-one', 'partyId': 'customer-1',
      'kind': 'Debt', 'amount': 70, 'paidNow': 10,
      'method': 'Cash', 'occurredAt': '2026-11-13T20:00:00Z',
    });
    expect(locallySaved['queued'], true);
    expect(await api.pendingCount(), 1);
    final customers = await api.get('/api/customers', query: {
      'search': 'أحمد', 'sort': 'name', 'page': 1, 'size': 30,
    });
    expect((customers['items'] as List).single['balance'], 185.5);
    final statement = await api.get('/api/parties/customer-1/statement');
    expect((statement['entries'] as List).single['offlinePending'], true);
    expect(statement['closingBalance'], 185.5);

    internet = true;
    expect(await api.synchronize(), 1);
    expect(await api.pendingCount(), 0);
    expect(posted, ['offline-one']);
  });
}
