import 'dart:async';

import 'package:countdown_todo/services/pomodoro_sync_service.dart';
import 'package:countdown_todo/services/storage/app_settings_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _TestChannel implements WebSocketChannel {
  final incoming = StreamController<dynamic>.broadcast();
  final Completer<void> _readyCompleter;
  @override
  final int? closeCode;
  bool closed = false;
  late final _TestSink _sink = _TestSink(() {
    closed = true;
  });

  _TestChannel({Completer<void>? readyCompleter, this.closeCode})
    : _readyCompleter = readyCompleter ?? (Completer<void>()..complete());

  @override
  Stream<dynamic> get stream => incoming.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  Future<void> get ready => _readyCompleter.future;

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

  test('offline mode blocks forceReconnect and manualReconnect', () async {
    SharedPreferences.setMockInitialValues({'app_offline_mode_enabled': true});
    await AppSettingsStorage.setOfflineModeEnabled(true);
    var connectCalls = 0;
    final service = PomodoroSyncService.forTesting((_) {
      connectCalls++;
      return _TestChannel();
    });

    await service.forceReconnect('1', 'dev-1', authToken: 'tok');
    await service.manualReconnect();

    expect(connectCalls, 0);
    expect(service.connectionState, SyncConnectionState.disconnected);
    await service.forceDisconnect();
    service.dispose();
  });

  test('superseded connect attempt closes stale channel cleanly', () async {
    SharedPreferences.setMockInitialValues({'app_offline_mode_enabled': false});
    await AppSettingsStorage.setOfflineModeEnabled(false);
    final firstReady = Completer<void>();
    final firstChannelRequested = Completer<void>();
    final channels = <_TestChannel>[];
    final service = PomodoroSyncService.forTesting((_) {
      final channel = channels.isEmpty
          ? _TestChannel(readyCompleter: firstReady)
          : _TestChannel();
      channels.add(channel);
      if (channels.length == 1 && !firstChannelRequested.isCompleted) {
        firstChannelRequested.complete();
      }
      return channel;
    });

    final firstFuture = service.forceReconnect('1', 'dev-1', authToken: 't1');
    await firstChannelRequested.future;
    expect(channels.length, 1);

    await service.forceReconnect('1', 'dev-1', authToken: 't2');
    expect(channels.length, 2);
    expect(service.connectionState, SyncConnectionState.connected);

    firstReady.complete();
    await firstFuture;

    expect(channels[0].closed, isTrue);
    expect(channels[1].closed, isFalse);

    await service.forceDisconnect();
    service.dispose();
    for (final ch in channels) {
      await ch.incoming.close();
    }
  });

  test('auth close code 4001 suppresses automatic reconnect until explicit connect', () async {
    SharedPreferences.setMockInitialValues({'app_offline_mode_enabled': false});
    await AppSettingsStorage.setOfflineModeEnabled(false);
    final channels = <_TestChannel>[];
    final service = PomodoroSyncService.forTesting((_) {
      final ch = _TestChannel(closeCode: 4001);
      channels.add(ch);
      return ch;
    });

    await service.ensureConnected('1', 'dev-1', authToken: 'bad');
    expect(channels.length, 1);

    await channels.first.incoming.close();
    await Future<void>.delayed(Duration.zero);
    expect(service.connectionState, SyncConnectionState.disconnected);

    // Explicit ensureConnected resets auth-revoked flag and connects again.
    await service.ensureConnected('1', 'dev-1', authToken: 'fresh');
    expect(channels.length, 2);

    await service.forceDisconnect();
    service.dispose();
    for (final ch in channels) {
      await ch.incoming.close();
    }
  });
}
