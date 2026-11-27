import 'package:flutter_test/flutter_test.dart';
import 'package:deenbook/core/offline_catalog.dart';
import 'support/fakes.dart';

void main() {
  test('new customer retains local ID across restart and stays user isolated', () async {
    final storage = MemoryStorage();
    final first = OfflineCatalog(storage);
    final record = await first.enqueue('shop','owner','POST','/api/customers', {'name':'عميل جديد','openingBalance':20},null);
    final second = OfflineCatalog(storage);
    final records = await second.pending('shop','owner');
    expect(records.single['operationId'],record['operationId']);
    expect(records.single['body']['clientId'],record['entityId']);
    expect(OfflineCatalog.overlay('/api/customers',[],records).single['balance'],20);
    expect(await second.pending('shop','worker'),isEmpty);
    expect(await second.pending('other-shop','owner'),isEmpty);
    await second.error('shop','owner',record['operationId'] as String,'conflict');
    expect((await first.pending('shop','owner')).single['lastError'],'conflict');
    await second.acknowledge('shop','owner',record['operationId'] as String);
    expect(await first.pending('shop','owner'),isEmpty);
  });
  test('local product creation followed by edit and deletion', () async {
    final catalog = OfflineCatalog(MemoryStorage());
    final created = await catalog.enqueue('s','u','POST','/api/products',{'name':'Tea','salePrice':5,'unit':'piece'},null);
    final id = created['entityId'];
    final before = OfflineCatalog.overlay('/api/products',[],await catalog.pending('s','u')).single;
    await catalog.enqueue('s','u','PUT','/api/products/$id',{'salePrice':8},before);
    final updated = OfflineCatalog.overlay('/api/products',[],await catalog.pending('s','u')).single;
    expect(updated['salePrice'],8);
    await catalog.enqueue('s','u','DELETE','/api/products/$id',{},updated);
    expect(OfflineCatalog.overlay('/api/products',[],await catalog.pending('s','u')),isEmpty);
  });
  test('ledger actions persist, stay user scoped and reject duplicates', () async {
    final storage = MemoryStorage();
    final first = OfflineCatalog(storage);
    const id = 'b6e58a10-723e-4ca2-981c-35b8c0a79fb7';
    final record = await first.enqueue('s','owner','POST','/api/transactions/$id/confirm',{},null);
    expect(record['entityId'],id);
    expect(record['body']['clientId'],isNull);
    final restarted = OfflineCatalog(storage);
    expect((await restarted.pending('s','owner')).single['operationId'],record['operationId']);
    expect(await restarted.pending('s','other'),isEmpty);
    await expectLater(restarted.enqueue('s','owner','POST','/api/transactions/$id/void',{'reason':'test'},null),throwsStateError);
    await restarted.acknowledge('s','owner',record['operationId'] as String);
    expect(await restarted.pending('s','owner'),isEmpty);
  });
  test('worker creation has stable client id and is not projected as a party', () async {
    final storage = MemoryStorage();
    final first = OfflineCatalog(storage);
    final record = await first.enqueue('s','owner','POST','/api/workers',{'name':'Worker','phoneNumber':'0599000003','password':'test-password-123'},null);
    expect(record['collection'],'/api/workers');
    expect(record['body']['clientId'],record['entityId']);
    expect(OfflineCatalog.overlay('/api/customers',[],await first.pending('s','owner')),isEmpty);
    expect((await OfflineCatalog(storage).pending('s','owner')).single['entityId'],record['entityId']);
  });
}
