import 'dart:convert';
import 'dart:io';

import 'package:countdown_todo/services/lan_sync_service_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scanLanSubnetInIsolate discovers peer and skips local/self', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    server.listen((request) async {
      if (request.uri.path == '/discover') {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(<String, Object?>{
              'deviceId': 'peer-device-1',
              'userId': 'alice',
              'deviceName': 'Test Mac',
              'port': server.port,
            }),
          );
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final discovered = await scanLanSubnetInIsolate(
      localIp: '127.0.0.2',
      port: server.port,
      currentDeviceId: 'my-device',
      targetIpsOverride: const <String>['127.0.0.1', '127.0.0.2'],
    );

    expect(discovered, hasLength(1));
    expect(discovered.first['ip'], '127.0.0.1');
    expect(discovered.first['port'], server.port);
    expect(discovered.first['deviceId'], 'peer-device-1');
    expect(discovered.first['userId'], 'alice');
    expect(discovered.first['deviceName'], 'Test Mac');

    final skippedSelf = await scanLanSubnetInIsolate(
      localIp: '127.0.0.2',
      port: server.port,
      currentDeviceId: 'peer-device-1',
      targetIpsOverride: const <String>['127.0.0.1', '127.0.0.2'],
    );
    expect(skippedSelf, isEmpty);
  });
}
