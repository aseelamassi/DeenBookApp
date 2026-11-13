import 'package:flutter_test/flutter_test.dart';
import 'package:deenbook/core/offline_projection.dart';

void main() {
  final debt = <String, dynamic>{
    'operationId': 'debt-1', 'partyId': 'customer-1',
    'kind': 'Debt', 'amount': 120, 'paidNow': 20,
    'discount': 0, 'occurredAt': '2026-11-13T10:00:00Z',
    'items': <dynamic>[],
  };
  final supplierInvoice = <String, dynamic>{
    'operationId': 'supplier-1', 'partyId': 'supplier-1',
    'kind': 'Purchase', 'amount': 270, 'paidNow': 0,
    'occurredAt': '2026-11-13T10:01:00Z',
    'items': [
      {'name': 'كرتونة زيت', 'quantity': 1, 'unitPrice': 270,
        'unit': 'كرتونة', 'total': 270},
    ],
  };

  test('queued debt appears immediately and adjusts account balance', () {
    final local = OfflineProjection.pendingEntries([
      {'operationId': 'debt-1', 'body': debt},
    ]);
    expect(local.single['id'], 'local:debt-1');
    expect(local.single['offlinePending'], true);
    expect(OfflineProjection.partyDelta('customer-1', local), 100);
    final list = OfflineProjection.transactionList(
      {'items': <dynamic>[], 'total': 0}, local,
      {'partyKind': 'Customer', 'page': 1, 'size': 30},
      {'customer-1': 'Customer'},
    );
    expect(list['total'], 1);
    expect((list['items'] as List).single['operationId'], 'debt-1');
  });

  test('supplier invoice is detailed and payment subtracts liability', () {
    final local = OfflineProjection.pendingEntries([
      {'operationId': 'supplier-1', 'body': supplierInvoice},
      {'operationId': 'payment-1', 'body': {
        'operationId': 'payment-1', 'partyId': 'supplier-1',
        'kind': 'Payment', 'amount': 50,
      }},
    ]);
    expect(OfflineProjection.partyDelta('supplier-1', local), 220);
    final statement = OfflineProjection.statement(
      {'entries': <dynamic>[], 'openingBalance': 0},
      'supplier-1', local, null,
    );
    expect((statement['entries'] as List).length, 2);
    expect(((statement['entries'] as List).first['items'] as List).single['name'],
        'كرتونة زيت');
  });

  test('blocked operations remain visible but do not inflate balances', () {
    final local = OfflineProjection.pendingEntries([
      {'operationId': 'debt-1', 'body': debt, 'blocked': true},
    ]);
    expect(local.single['offlineBlocked'], true);
    expect(OfflineProjection.partyDelta('customer-1', local), 0);
  });

  test('cached response pages do not get paginated twice', () {
    final local = OfflineProjection.pendingEntries([
      {'operationId': 'debt-1', 'body': debt},
    ]);
    final secondPage = OfflineProjection.transactionList(
      {'items': [
        {'id': 'server-page-2', 'partyId': 'customer-1', 'kind': 'Debt'},
      ], 'total': 31},
      local, {'page': 2, 'size': 30},
      {'customer-1': 'Customer'},
    );
    expect((secondPage['items'] as List).length, 1);
    expect((secondPage['items'] as List).single['id'], 'server-page-2');
  });
}
