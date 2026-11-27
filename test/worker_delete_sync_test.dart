import 'package:deenbook/core/api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  test('worker deletion persists offline, retries same ID and survives restart', () async {
    final memory = MemoryStorage();
    var online = true;
    var reject = false;
    var loseResponse = false;
    var deleted = false;
    var currentOwner = true;
    final calls = <String>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'));
    dio.httpClientAdapter = Adapter((r) {
      if (!online) {
        throw DioException(requestOptions: r, type: DioExceptionType.connectionError);
      }
      if (r.path == '/api/auth/login' || r.path == '/api/auth/refresh') {
        return response(token());
      }
      if (r.path == '/api/subscription') {
        return response({
          'id': 'shop-1', 'isOwner': currentOwner,
          'userId': currentOwner ? 'owner-1' : 'worker-2',
          'active': true, 'suspended': false,
          'paidUntil': DateTime.now().toUtc().add(const Duration(days: 10)).toIso8601String(),
        });
      }
      if (r.path == '/api/workers' && r.method == 'GET') {
        return response({'workers': [
          if (!deleted) {'id': 'worker-1', 'name': 'سارة', 'enabled': true},
          {'id': 'worker-2', 'name': 'أحمد', 'enabled': true},
        ], 'limit': 2});
      }
      if (r.path == '/api/workers/worker-1' && r.method == 'DELETE') {
        calls.add(r.path);
        if (reject) return response({'message': 'رفض الطلب'}, status: 409);
        deleted = true;
        if (loseResponse) {
          loseResponse = false;
          throw DioException(requestOptions: r, type: DioExceptionType.connectionError);
        }
        return ResponseBody.fromString('', 204);
      }
      return response({});
    });
    var api = Api(memory, client: dio);
    await api.login('0599000001', 'password');
    await api.get('/api/subscription');
    expect((await api.get('/api/workers'))['workers'], hasLength(2));
    online = false;
    expect((await api.deleteWorker('worker-1', 'سارة'))['queued'], true);
    // Repeated local deletion must not create another pending operation.
    await api.deleteWorker('worker-1', 'سارة');
    expect(await api.pendingCount(), 1);
    expect(await api.offlineVault.readOutbox('shop-1'), isEmpty);
    expect((await api.get('/api/workers'))['workers'], hasLength(1));
    api = Api(memory, client: dio);
    await api.restore();
    expect(api.offlineSession, true);
    expect(await api.pendingCount(), 1);
    expect((await api.get('/api/workers'))['workers'], hasLength(1));
    online = true;
    reject = true;
    await expectLater(api.synchronize(), throwsA(isA<ApiFailure>()));
    expect(await api.pendingCount(), 1);
    expect((await api.pendingWorkerDeletes()).single['lastError'], 'رفض الطلب');
    reject = false;
    loseResponse = true;
    await expectLater(api.synchronize(), throwsA(isA<ApiFailure>()));
    expect(deleted, true);
    expect(await api.pendingCount(), 1);
    expect(await api.synchronize(), 1);
    expect(await api.pendingCount(), 0);
    expect(calls, List.filled(3, '/api/workers/worker-1'));
    online = false;
    api = Api(memory, client: dio);
    await api.restore();
    expect((await api.get('/api/workers'))['workers'], hasLength(1));
    expect(await api.pendingCount(), 0);
    online = true;
    currentOwner = false;
    await api.login('0599000002', 'password');
    await api.get('/api/subscription');
    await expectLater(api.deleteWorker('worker-2', 'أحمد'), throwsA(isA<ApiFailure>()));
    expect(await api.pendingCount(), 0);
  });
}
