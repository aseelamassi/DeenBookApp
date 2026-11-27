import 'package:deenbook/core/api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fakes.dart';

void main() {
  test('offline rename survives restart and checks original name', () async {
    final memory = MemoryStorage();
    var online = true;
    var serverName = 'Original';
    final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'));
    dio.httpClientAdapter = Adapter((r) {
      if (!online) throw DioException(requestOptions: r, type: DioExceptionType.connectionError);
      if (r.path.startsWith('/api/auth/')) return response(token());
      if (r.path == '/api/subscription') return response({
        'id': 'shop-1', 'userId': 'owner-1', 'isOwner': true, 'active': true,
        'suspended': false, 'offlineGraceDays': 5, 'offlineWorkerRenameVersion': 1,
        'paidUntil': DateTime.now().toUtc().add(const Duration(days: 10)).toIso8601String(),
      });
      if (r.path == '/api/workers') return response({'workers': [{'id': 'worker-1', 'name': serverName, 'enabled': true}], 'limit': 2});
      if (r.path == '/api/workers/worker-1/name') {
        final body = r.data as Map;
        if (serverName != body['expectedName'] && serverName != body['name']) return response({'message': 'Conflict'}, status: 409);
        serverName = body['name'] as String;
        return response({'id': 'worker-1', 'name': serverName, 'enabled': true});
      }
      return response({});
    });
    var api = Api(memory, client: dio);
    await api.login('0599000001', 'password');
    await api.get('/api/subscription');
    expect(api.offlineGraceDays, 5);
    await api.get('/api/workers');
    online = false;
    await api.get('/api/workers');
    await api.renameWorker('worker-1', 'Original', 'Local');
    await api.renameWorker('worker-1', 'Local', 'Final');
    expect(await api.pendingCount(), 1);
    expect((await api.pendingWorkerRenames()).single['expectedName'], 'Original');
    api = Api(memory, client: dio);
    await api.restore();
    expect(api.offlineGraceDays, 5);
    expect((await api.get('/api/workers'))['workers'][0]['name'], 'Final');
    online = true;
    serverName = 'Other device';
    await expectLater(api.synchronize(), throwsA(isA<ApiFailure>()));
    expect(serverName, 'Other device');
    expect(await api.pendingCount(), 1);
    await api.discardWorkerRename('worker-1');
    expect(await api.pendingCount(), 0);
    await api.get('/api/workers');
    await api.renameWorker('worker-1', 'Other device', 'Final');
    expect(await api.synchronize(), 1);
    expect(serverName, 'Final');
    expect(await api.pendingCount(), 0);
  });
}
