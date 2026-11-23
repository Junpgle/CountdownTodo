import 'dart:async';
import 'dart:convert';

import 'package:countdown_todo/screens/settings_screen.dart';
import 'package:countdown_todo/services/band_sync_service.dart';
import 'package:countdown_todo/services/pomodoro_sync_service.dart';
import 'package:countdown_todo/services/storage/app_settings_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _TestChannel implements WebSocketChannel {
  final incoming = StreamController<dynamic>.broadcast();
  bool closed = false;
  late final _TestSink _sink = _TestSink(() {
    closed = true;
  });

  @override
  Stream<dynamic> get stream => incoming.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  int? get closeCode => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSink implements WebSocketSink {
  final void Function() onClose;
  _TestSink(this.onClose);

  @override
  void add(dynamic data) {}

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    onClose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bandChannel = MethodChannel('com.math_quiz_app/band_communication');

  Future<void> sendBandNativeEvent(String method, Object? arguments) async {
    final message = const StandardMethodCodec().encodeMethodCall(
      MethodCall(method, arguments),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(bandChannel.name, message, (ByteData? _) {});
  }

  group('BandSyncService listeners', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(bandChannel, (_) async => true);
    });

    tearDown(() async {
      await BandSyncService.setServiceEnabled(false);
      BandSyncService.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(bandChannel, null);
    });

    test('registered listener receives events until removed', () async {
      await BandSyncService.init();
      await BandSyncService.setServiceEnabled(true);

      final connected = <String>[];
      final messages = <Map<String, dynamic>>[];
      var disconnectedCount = 0;

      final listener = BandSyncListener(
        onDeviceConnected: (info) => connected.add(info['name'].toString()),
        onDeviceDisconnected: () => disconnectedCount++,
        onMessageReceived: messages.add,
      );
      BandSyncService.addListener(listener);

      await sendBandNativeEvent('onDeviceConnected', {
        'nodeId': 'n1',
        'name': 'Band 9',
      });
      await sendBandNativeEvent('onMessageReceived', {
        'data': jsonEncode({'type': 'pong', 'value': 1}),
      });
      expect(connected, ['Band 9']);
      expect(messages, [
        {'type': 'pong', 'value': 1},
      ]);

      BandSyncService.removeListener(listener);

      await sendBandNativeEvent('onMessageReceived', {
        'data': jsonEncode({'type': 'pong', 'value': 2}),
      });
      await sendBandNativeEvent('onDeviceDisconnected', null);
      expect(messages.length, 1);
      expect(disconnectedCount, 0);
    });
  });

  group('PomodoroSyncService stale sync focus handler stack', () {
    test(
      'routes to top-most registered handler and falls back on unregister',
      () async {
        SharedPreferences.setMockInitialValues({
          'app_offline_mode_enabled': false,
        });
        await AppSettingsStorage.setOfflineModeEnabled(false);
        final ch = _TestChannel();
        final service = PomodoroSyncService.forTesting((_) => ch);

        await service.ensureConnected('1', 'dev-1', authToken: 'tok');

        final calls = <String>[];
        void handlerA(CrossDevicePomodoroState state) {
          calls.add('A:${state.sessionUuid}');
        }

        void handlerB(CrossDevicePomodoroState state) {
          calls.add('B:${state.sessionUuid}');
        }

        service.registerStaleSyncFocusHandler(handlerA);
        service.registerStaleSyncFocusHandler(handlerB);

        ch.incoming.add(
          jsonEncode({
            'action': 'SYNC_FOCUS',
            'sourceDevice': 'flutter_dev-1',
            'sessionUuid': 's1',
          }),
        );
        await Future<void>.delayed(Duration.zero);
        expect(calls, ['B:s1']);

        service.unregisterStaleSyncFocusHandler(handlerB);
        ch.incoming.add(
          jsonEncode({
            'action': 'SYNC_FOCUS',
            'sourceDevice': 'flutter_dev-1',
            'sessionUuid': 's2',
          }),
        );
        await Future<void>.delayed(Duration.zero);
        expect(calls, ['B:s1', 'A:s2']);

        service.unregisterStaleSyncFocusHandler(handlerA);
        ch.incoming.add(
          jsonEncode({
            'action': 'SYNC_FOCUS',
            'sourceDevice': 'flutter_dev-1',
            'sessionUuid': 's3',
          }),
        );
        await Future<void>.delayed(Duration.zero);
        expect(calls, ['B:s1', 'A:s2']);

        await service.forceDisconnect();
        service.dispose();
        await ch.incoming.close();
      },
    );
  });

  testWidgets('SettingsScreen mounts and disposes cleanly', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('题目设置'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
