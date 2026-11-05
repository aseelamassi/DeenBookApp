import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:deenbook/core/api.dart';
import 'package:deenbook/core/session.dart';
import 'package:deenbook/core/storage.dart';

class MemoryStorage implements Storage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class Adapter implements HttpClientAdapter {
  Adapter(this.handle);
  final FutureOr<ResponseBody> Function(RequestOptions) handle;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return await handle(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody response(Object? data, {int status = 200}) =>
    ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
Json token([String label = 'one']) => {
  'accessToken': 'access-$label',
  'expiresAt': DateTime.now()
      .add(const Duration(minutes: 30))
      .toIso8601String(),
  'refreshToken': 'refresh-$label',
  'refreshTokenExpiresAt': DateTime.now()
      .add(const Duration(days: 20))
      .toIso8601String(),
  'tokenType': 'Bearer',
};
Json party({bool supplier = false}) => {
  'id': supplier ? 'supplier-1' : 'customer-1',
  'name': supplier ? 'شركة النور للتوريد' : 'أحمد محمود',
  'kind': supplier ? 'Supplier' : 'Customer',
  'balance': 125.5,
  'openingBalance': 0,
  'phone': '0599000001',
  'nickname': '',
  'representative': '',
  'category': '',
  'deliveryDays': '',
  'acceptedMethods': '',
  'paymentSchedule': '',
};
Json page(List<Json> items) => {
  'items': items,
  'total': items.length,
  'pageNumber': 1,
  'pageSize': 30,
};
Json entry() => {
  'id': 'entry-1',
  'partyId': 'customer-1',
  'operationId': 'op-1',
  'kind': 'Debt',
  'amount': 125.5,
  'paidNow': 0,
  'delta': 125.5,
  'method': 'Cash',
  'occurredAt': '2026-10-19T10:00:00Z',
  'note': 'أصناف متنوعة',
  'reference': '',
};
Future<Session> fakeSession({
  bool login = true,
  bool active = true,
  bool populated = false,
  MemoryStorage? store,
  FutureOr<ResponseBody?> Function(RequestOptions)? override,
}) async {
  final storage = store ?? MemoryStorage();
  final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'));
  dio.httpClientAdapter = Adapter((r) async {
    final custom = await override?.call(r);
    if (custom != null) return custom;
    switch (r.path) {
      case '/api/capabilities':
        return response({'ledgerVersion': 2});
      case '/api/customers/overview':
      case '/api/suppliers/overview':
        return response({
          'total': populated ? 1 : 0,
          'outstanding': populated ? 125.5 : 0,
          'owing': populated ? 1 : 0,
          'credit': 0,
          'settled': 0,
          'scheduled': 0,
          'categories': [],
        });
      case '/api/auth/login':
      case '/api/auth/refresh':
        return response(token());
      case '/api/subscription':
        return response({
          'id': 'shop-1',
          'name': 'محل الأمانة',
          'active': active,
          'suspended': false,
          // Keep visual fixtures active independently of the test run date.
          'paidUntil': '2099-11-20T00:00:00Z',
        });
      case '/api/settings':
        return response({
          'name': 'محل الأمانة',
          'ownerName': 'صاحب المحل',
          'phone': '0599000001',
        });
      case '/api/dashboard':
        return response({
          'summary': {
            'receivables': populated ? 650 : 0,
            'payables': populated ? 250 : 0,
            'received': 0,
            'paid': 0,
          },
          'topDebtors': populated ? [party()] : [],
          'supplierBalances': [],
          'supplierDeliveries': [],
        });
      case '/api/transactions':
        return response(page(populated ? [entry()] : []));
      case '/api/customers':
        return response(page(populated ? [party()] : []));
      case '/api/suppliers':
        return response(page(populated ? [party(supplier: true)] : []));
      case '/api/products':
        return response(page([]));
      case '/api/products/categories':
        return response({'items': []});
      case '/api/reports/summary':
        return response({
          'receivables': 650,
          'payables': 250,
          'received': 100,
          'paid': 50,
        });
      case '/api/reports/cashflow':
        return response({
          'customerCashIn': 100,
          'supplierCashOut': 50,
          'netCash': 50,
          'entries': [],
        });
    }
    if (r.path.endsWith('/statement')) {
      return response({
        'party': party(),
        'openingBalance': 0,
        'closingBalance': 125.5,
        'entries': populated ? [entry()] : [],
      });
    }
    if (r.path.startsWith('/api/parties/')) {
      return response(party(supplier: r.path.contains('supplier')));
    }
    return response({}, status: 204);
  });
  final session = Session(Api(storage, client: dio));
  if (login) {
    await session.login('+970599000001', 'test-password');
  } else {
    await session.initialize();
  }
  return session;
}
