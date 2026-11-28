import 'package:deenbook/core/api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const entryId = 'b6e58a10-723e-4ca2-981c-35b8c0a79fb7';

  for (final populated in [false, true]) {
    test('ledger reads work with no pending writes; populated=$populated', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'));
      final api = Api(MemoryStorage(), client: dio);
      var online = true;
      List<Json> movements(bool supplier) => populated
          ? [<String, dynamic>{
              ...entry(),
              'id': entryId,
              'partyId': supplier ? 'supplier-1' : 'customer-1',
              'kind': supplier ? 'Purchase' : 'Debt',
            }]
          : <Json>[];
      dio.httpClientAdapter = Adapter((r) {
        if (!online) {
          throw DioException(requestOptions: r,
              type: DioExceptionType.connectionError);
        }
        if (r.path == '/api/auth/login') return response(token());
        if (r.path == '/api/subscription') {
          return response({
            'id': 'shop-1', 'userId': 'owner-1', 'isOwner': true,
            'active': true, 'paidUntil': '2099-01-01T00:00:00Z',
          });
        }
        if (r.path == '/api/dashboard') {
          return response({'summary': {'receivables': 125.5}});
        }
        if (r.path == '/api/customers') return response(page([party()]));
        if (r.path == '/api/suppliers') {
          return response(page([party(supplier: true)]));
        }
        if (r.path == '/api/transactions') {
          final supplier = r.queryParameters['partyKind'] == 'Supplier';
          return response(page(movements(supplier)));
        }
        if (r.path.endsWith('/statement')) {
          final supplier = r.path.contains('supplier-1');
          return response({
            'party': party(supplier: supplier),
            'entries': movements(supplier),
            'openingBalance': 0, 'closingBalance': 125.5,
          });
        }
        return response({});
      });
      await api.login('0599000001', 'password');
      await api.get('/api/subscription');
      expect(await api.pendingCount(), 0);
      await api.get('/api/customers');
      await api.get('/api/suppliers');
      expect((await api.get('/api/dashboard'))['summary'], isA<Map>());
      // Test online reads before switching to cached data. The dashboard
      // itself also uses the customer transaction-list endpoint.
      for (final kind in ['Customer', 'Supplier']) {
        final report = await api.get('/api/transactions',
            query: {'partyKind': kind, 'includeVoided': true});
        expect(report['items'], hasLength(populated ? 1 : 0));
        final id = kind == 'Customer' ? 'customer-1' : 'supplier-1';
        final statement = await api.get('/api/parties/$id/statement');
        expect(statement['entries'], hasLength(populated ? 1 : 0));
        expect(statement['closingBalance'], 125.5);
      }
      if (populated) {
        await api.offlineCatalog.enqueue('shop-1', 'owner-1', 'POST',
            '/api/transactions/$entryId/void', {'reason': 'test'}, null);
        final statement = await api.get('/api/parties/customer-1/statement');
        expect((statement['entries'] as List).single['offlineLedgerAction'], 'void');
        expect(statement['closingBalance'], 125.5);
        final report = await api.get('/api/transactions',
            query: {'partyKind': 'Customer', 'includeVoided': true});
        expect((report['items'] as List).single['offlineLedgerAction'], 'void');
      }
      online = false;
      final cached = await api.get('/api/parties/customer-1/statement');
      expect(cached['entries'], hasLength(populated ? 1 : 0));
      expect(cached['closingBalance'], 125.5);
      expect(api.isOffline, isTrue);
    });
  }

  test('invalid response objects are still rejected', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'));
    final api = Api(MemoryStorage(), client: dio);
    dio.httpClientAdapter = Adapter((r) => response(<Object>[]));
    await expectLater(api.get('/api/transactions'), throwsA(isA<ApiFailure>()));
  });
}
