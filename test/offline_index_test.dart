import 'package:flutter_test/flutter_test.dart';
import 'package:deenbook/core/offline.dart';
import 'support/fakes.dart';

void main() {
  test('offline index keeps previously loaded accounts when search changes', () async {
    final vault = OfflineVault(MemoryStorage());
    await vault.indexResponse('shop-a', '/api/customers', null, {
      'items': [
        {'id': 'c1', 'name': 'ليان', 'balance': 20},
        {'id': 'c2', 'name': 'أحمد', 'balance': 50},
      ],
    });
    await vault.indexResponse('shop-a', '/api/customers', {'search': 'أحمد'}, {
      'items': [ {'id': 'c2', 'name': 'أحمد', 'balance': 60} ],
    });
    final all = await vault.readBestSnapshot('shop-a', '/api/customers',
        {'search': '', 'sort': 'name', 'page': 1, 'size': 30});
    expect((all['items'] as List).length, 2);
    final selected = await vault.readBestSnapshot('shop-a', '/api/customers',
        {'search': 'ليان', 'sort': 'name', 'page': 1, 'size': 30});
    expect((selected['items'] as List).single['name'], 'ليان');
    expect((await vault.indexedItems('shop-b', '/api/customers')), isEmpty);
  });
}
