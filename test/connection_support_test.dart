import 'package:deenbook/core/api.dart';
import 'package:deenbook/services/subscription_contact.dart';
import 'package:deenbook/ui/theme.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Symbols',
    )..addFont(rootBundle.load('assets/fonts/Symbols.ttf'))).load();
    await (FontLoader('Cairo')
          ..addFont(rootBundle.load('assets/fonts/Cairo-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Cairo-SemiBold.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Cairo-Bold.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Cairo-ExtraBold.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Cairo-Black.ttf')))
        .load();
  });

  for (final suffix in ['', '/', '/api', '/api/', '/api.']) {
    test(
      'login reaches one API prefix for base URL ending "$suffix"',
      () async {
        final api = Api(
          MemoryStorage(),
          baseUrl: ' https://example.test$suffix ',
        );
        api.dio.httpClientAdapter = Adapter((request) {
          expect(request.uri.toString(), 'https://example.test/api/auth/login');
          return response(token());
        });
        await api.login('0599000001', 'test');
        expect(api.signedIn, isTrue);
      },
    );
  }
  test('server subdirectory survives normalization', () async {
    final api = Api(MemoryStorage(), baseUrl: 'https://example.test/shop/api/');
    api.dio.httpClientAdapter = Adapter((request) {
      if (request.uri.path == '/shop/api/auth/login') return response(token());
      expect(request.uri.path, '/shop/api/subscription');
      return response({'active': false});
    });
    await api.login('0599000001', 'password');
    expect(await api.get('/api/subscription'), {'active': false});
  });
  test('shipping default is the published secure API host', () {
    final api = Api(MemoryStorage());
    expect(api.dio.options.baseUrl, 'https://api-deenbook.runasp.net');
    expect(api.dio.options.followRedirects, isFalse);
  });
  test('HTTP is not silently upgraded or permitted in release', () {
    expect(
      validateBaseUrl('http://api-deenbook.runasp.net/api.', release: false),
      'http://api-deenbook.runasp.net',
    );
    expect(
      () => validateBaseUrl('http://api-deenbook.runasp.net', release: true),
      throwsFormatException,
    );
  });
  test(
    'HTML at a wrong endpoint produces a readable error and no session',
    () async {
      final storage = MemoryStorage();
      final api = Api(storage, baseUrl: 'https://example.test');
      api.dio.httpClientAdapter = Adapter(
        (request) => ResponseBody.fromString('<html>Hosting page</html>', 200),
      );
      await expectLater(
        api.login('0599000001', 'test'),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.message,
            'message',
            contains('غير صالحة'),
          ),
        ),
      );
      expect(api.signedIn, isFalse);
      expect(storage.values, isEmpty);
    },
  );
  test('malformed auth JSON cannot create a session', () async {
    final api = Api(MemoryStorage(), baseUrl: 'https://example.test');
    api.dio.httpClientAdapter = Adapter(
      (request) => response({'message': 'ok'}),
    );
    await expectLater(
      api.login('0599000001', 'test'),
      throwsA(isA<ApiFailure>()),
    );
    expect(api.signedIn, isFalse);
  });
  test('connection, timeout, TLS, route and server failures stay distinct', () {
    final request = RequestOptions(path: '/api/auth/login');
    String failure(
      DioExceptionType type, {
      int? status,
      Object? error,
      Object? data,
    }) => ApiFailure.from(
      DioException(
        requestOptions: request,
        type: type,
        error: error,
        response: status == null
            ? null
            : Response(requestOptions: request, statusCode: status, data: data),
      ),
    ).message;
    expect(failure(DioExceptionType.connectionError), contains('خادم الخدمة'));
    expect(failure(DioExceptionType.receiveTimeout), contains('مهلة'));
    expect(failure(DioExceptionType.badCertificate), contains('اتصال آمن'));
    expect(
      failure(
        DioExceptionType.unknown,
        error: 'HandshakeException: CERTIFICATE_VERIFY_FAILED',
      ),
      contains('اتصال آمن'),
    );
    expect(
      failure(DioExceptionType.badResponse, status: 404),
      contains('مسار الخدمة'),
    );
    expect(
      failure(DioExceptionType.badResponse, status: 307),
      contains('عنوان الخدمة'),
    );
    expect(
      failure(
        DioExceptionType.badResponse,
        status: 503,
        data: {'detail': 'internal secret'},
      ),
      'خادم الخدمة غير متاح حالياً. حاول بعد قليل.',
    );
    expect(
      failure(
        DioExceptionType.badResponse,
        status: 400,
        data: {'detail': 'رقم الجوال غير صحيح'},
      ),
      'رقم الجوال غير صحيح',
    );
  });
  test(
    'support number accepts international notation and rejects invalid values',
    () {
      for (final number in [
        '+970 599-000-001',
        '00970599000001',
        '970599000001',
      ]) {
        expect(normalizeSupportPhone(number), '970599000001');
      }
      for (final number in [
        '',
        '0599000001',
        '970XXXXXXXXX',
        'https://wa.me/123',
      ]) {
        expect(normalizeSupportPhone(number), isNull);
      }
    },
  );
  test('subscription request uses selected duration and exact plan price', () {
    final monthly = subscriptionRequestText(
      shopName: 'محل الأمانة',
      months: 1,
      phone: '0599000001',
    );
    final quarterly = subscriptionRequestText(
      shopName: 'محل الأمانة',
      months: 3,
      renewal: true,
    );
    expect(monthly, contains('شهر واحد، بقيمة 60 شيكل'));
    expect(monthly, contains('0599000001'));
    expect(quarterly, contains('ثلاثة أشهر، بقيمة 150 شيكل'));
    expect(quarterly, contains('تجديد الاشتراك'));
    expect(quarterly, isNot(contains('180')));
  });

  final requestText = subscriptionRequestText(
    shopName: 'محل الأمانة',
    months: 3,
    phone: '0599000001',
  );
  Widget harness({String phone = '', Future<bool> Function(Uri)? launcher}) =>
      MaterialApp(
        theme: appTheme(),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => contact(
                  context,
                  requestText,
                  supportPhone: phone,
                  launcher: launcher,
                ),
                child: const Text('عرض الطلب'),
              ),
            ),
          ),
        ),
      );
  testWidgets(
    'missing support opens honest fallback and copies only on request',
    (t) async {
      t.view.physicalSize = const Size(320, 760);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      String? clipboard;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboard = (call.arguments as Map)['text'] as String;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await t.pumpWidget(harness());
      await t.tap(find.text('عرض الطلب'));
      await t.pumpAndSettle();
      expect(find.text('لم يُرسل الطلب'), findsOneWidget);
      expect(clipboard, isNull);
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(AlertDialog),
        matchesGoldenFile('goldens/subscription-request-unavailable.png'),
      );
      await t.tap(find.text('نسخ التفاصيل'));
      await t.pumpAndSettle();
      expect(clipboard, requestText);
      expect(find.text('تم نسخ التفاصيل فقط؛ لم يُرسل الطلب.'), findsOneWidget);
    },
  );
  testWidgets(
    'WhatsApp draft targets administration without claiming delivery',
    (t) async {
      Uri? launched;
      await t.pumpWidget(
        harness(
          phone: '+970599000001',
          launcher: (uri) async {
            launched = uri;
            return true;
          },
        ),
      );
      await t.tap(find.text('عرض الطلب'));
      await t.pumpAndSettle();
      expect(launched?.host, 'wa.me');
      expect(launched?.path, '/970599000001');
      expect(launched?.queryParameters['text'], requestText);
      expect(
        find.text('فُتح رابط واتساب. اضغط «إرسال» هناك لإكمال الطلب.'),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
  testWidgets(
    'launcher failure keeps the request unsent and shows contact number',
    (t) async {
      await t.pumpWidget(
        harness(phone: '970599000001', launcher: (_) async => false),
      );
      await t.tap(find.text('عرض الطلب'));
      await t.pumpAndSettle();
      expect(find.text('لم يُرسل الطلب'), findsOneWidget);
      expect(find.text('+970599000001'), findsOneWidget);
      await t.tap(find.text('إغلاق'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
}
