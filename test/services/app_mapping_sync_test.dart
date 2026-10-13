@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:countdown_todo/services/api_service.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _LocalHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  late int requests;
  late int statusCode;
  late List<dynamic> body;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    requests = 0;
    statusCode = HttpStatus.ok;
    body = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests++;
      request.response.statusCode = statusCode;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(body));
      await request.response.close();
    });
    ApiService.setBaseUrlOverride('http://127.0.0.1:${server.port}');
  });

  tearDown(() async {
    ApiService.clearBaseUrlOverride();
    await server.close(force: true);
  });

  test('successful empty mappings are cached for seven days', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      await StorageService.syncAppMappings();
      await StorageService.syncAppMappings();
    }, _LocalHttpOverrides());

    final prefs = await SharedPreferences.getInstance();
    expect(requests, 1);
    expect(prefs.getString(StorageService.keyAppMappings), '{}');
    expect(prefs.getInt(StorageService.keyLastMappingsSync), isNotNull);
  });

  test(
    'failed requests do not cache an empty response or throttle retry',
    () async {
      statusCode = HttpStatus.serviceUnavailable;
      await HttpOverrides.runWithHttpOverrides(
        StorageService.syncAppMappings,
        _LocalHttpOverrides(),
      );
      var prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(StorageService.keyLastMappingsSync), isNull);

      statusCode = HttpStatus.ok;
      body = [
        {
          'package_name': 'app.example',
          'mapped_name': 'Example App',
          'category': '工具',
        },
      ];
      await HttpOverrides.runWithHttpOverrides(
        StorageService.syncAppMappings,
        _LocalHttpOverrides(),
      );

      prefs = await SharedPreferences.getInstance();
      expect(requests, 2);
      expect(prefs.getInt(StorageService.keyLastMappingsSync), isNotNull);
      expect(jsonDecode(prefs.getString(StorageService.keyAppMappings)!), {
        'app.example': '工具',
        'Example App': '工具',
      });
    },
  );

  test('future sync timestamp does not block a fresh request', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      StorageService.keyLastMappingsSync,
      DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
    );

    await HttpOverrides.runWithHttpOverrides(
      StorageService.syncAppMappings,
      _LocalHttpOverrides(),
    );

    expect(requests, 1);
    expect(prefs.getInt(StorageService.keyLastMappingsSync), isNotNull);
  });

  test('out-of-range sync timestamp does not block a fresh request', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(StorageService.keyLastMappingsSync, 1 << 62);

    await HttpOverrides.runWithHttpOverrides(
      StorageService.syncAppMappings,
      _LocalHttpOverrides(),
    );

    expect(requests, 1);
    expect(prefs.getInt(StorageService.keyLastMappingsSync), isNotNull);
  });
}
