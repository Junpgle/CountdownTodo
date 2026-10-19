import 'dart:convert';
import 'dart:io';

import 'package:countdown_todo/screens/team_management_screen.dart';
import 'package:countdown_todo/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late HttpServer server;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/api/teams') {
        request.response.write(jsonEncode({'success': true, 'teams': []}));
      } else if (request.uri.path == '/api/teams/invitations') {
        request.response.write(jsonEncode({'invitations': []}));
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write(jsonEncode({'success': false}));
      }
      await request.response.close();
    });
    ApiService.setBaseUrlOverride('http://127.0.0.1:${server.port}');
  });

  tearDown(() async {
    ApiService.clearBaseUrlOverride();
    await server.close(force: true);
  });

  testWidgets('pasted invite copy is reduced to its invite code', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return null;
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: TeamManagementScreen(username: 'invite-test-user'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('加入团队'));
    await tester.pumpAndSettle();

    final inviteField = find.byType(TextField).last;
    await tester.enterText(inviteField, '邀请您加入「测试」团队进行协作。邀请码：[ABC123]');

    expect(tester.widget<TextField>(inviteField).controller!.text, 'ABC123');
  });
}
