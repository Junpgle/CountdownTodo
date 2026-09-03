import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:countdown_todo/services/band_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.math_quiz_app/band_communication');
  final calls = <String>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return true;
    });
  });

  tearDown(() async {
    await BandSyncService.setServiceEnabled(false);
    BandSyncService.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('band service stays off until explicitly enabled', () async {
    expect(await BandSyncService.isServiceEnabled(), isFalse);

    // Disabled startup configures only the Dart bridge and must not initialize
    // the native wearable SDK.
    expect(await BandSyncService.init(), isTrue);
    expect(calls, isEmpty);

    expect(await BandSyncService.setServiceEnabled(true), isTrue);
    expect(await BandSyncService.isServiceEnabled(), isTrue);
    expect(calls, ['init']);

    expect(await BandSyncService.setServiceEnabled(false), isTrue);
    expect(await BandSyncService.isServiceEnabled(), isFalse);
    expect(calls, ['init', 'shutdown']);
  });

  test('rapid toggles keep the latest enabled state', () async {
    final initStarted = Completer<void>();
    final releaseInit = Completer<bool>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'init') {
        initStarted.complete();
        return releaseInit.future;
      }
      return true;
    });

    await BandSyncService.init();
    final enabling = BandSyncService.setServiceEnabled(true);
    await initStarted.future;

    final disabling = BandSyncService.setServiceEnabled(false);
    final reEnabling = BandSyncService.setServiceEnabled(true);
    releaseInit.complete(true);

    expect(await Future.wait([enabling, disabling, reEnabling]),
        [true, true, true]);
    expect(await BandSyncService.isServiceEnabled(), isTrue);
    expect(calls, ['init']);
  });
}
