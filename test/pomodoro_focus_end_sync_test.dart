import 'dart:async';
import 'dart:convert';

import 'package:countdown_todo/services/pomodoro_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _Channel implements WebSocketChannel {
  final incoming = StreamController<dynamic>();
  final sent = <Map<String, dynamic>>[];
  final outgoing = StreamController<Map<String, dynamic>>.broadcast();
  late final _Sink output = _Sink(sent, outgoing.add);

  @override
  Stream<dynamic> get stream => incoming.stream;
  @override
  WebSocketSink get sink => output;
  @override
  Future<void> get ready => Future.value();

  void receive(Map<String, dynamic> message) =>
      incoming.add(jsonEncode(message));
  List<Map<String, dynamic>> get stops =>
      sent.where((message) => message['action'] == 'STOP').toList();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sink implements WebSocketSink {
  final List<Map<String, dynamic>> sent;
  final void Function(Map<String, dynamic>) onSend;
  _Sink(this.sent, this.onSend);
  @override
  void add(dynamic data) {
    final message = jsonDecode(data as String) as Map<String, dynamic>;
    sent.add(message);
    onSend(message);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> flushMessages() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PomodoroSyncService service;
  late List<_Channel> channels;
  PomodoroSyncService createService({
    Duration heartbeat = const Duration(seconds: 30),
    Duration grace = const Duration(seconds: 5),
  }) {
    return PomodoroSyncService.forTesting(
      (_) {
        final channel = _Channel();
        channels.add(channel);
        return channel;
      },
      heartbeatInterval: heartbeat,
      stopDeliveryGrace: grace,
    );
  }

  setUp(() {
    channels = [];
    service = createService();
  });
  tearDown(() async {
    await service.forceDisconnect();
    service.dispose();
    for (final channel in channels) {
      await channel.incoming.close();
      await channel.outgoing.close();
    }
  });
  Future<void> connect({String user = '7'}) async {
    await service.ensureConnected(
      user,
      'flutter_test-device',
      authToken: 'test',
    );
  }

  Future<void> advertiseSupport() async {
    channels.last.receive({
      'action': 'FOCUS_SYNC_CAPABILITIES',
      'end_ack': true,
    });
    await flushMessages();
  }

  void restore(String session) {
    service.sendReconnectSyncSignal(
      sessionUuid: session,
      todoUuid: null,
      todoTitle: null,
      durationSeconds: 0,
      targetEndMs: 0,
      mode: 1,
    );
  }

  test(
    'offline STOP is replayed after safe-server handshake, then ACK removes it',
    () async {
      service.sendStopSignal(sessionUuid: 'ended', todoUuid: 'todo');
      await connect();
      expect(channels.last.stops, isEmpty);
      await advertiseSupport();
      final stop = channels.last.stops.single;
      expect(stop['session_uuid'], 'ended');
      channels.last.receive({
        'action': 'FOCUS_END_ACK',
        'request_id': stop['request_id'],
      });
      await flushMessages();
      await service.forceReconnect('7', 'flutter_test-device');
      await advertiseSupport();
      expect(channels.last.stops, isEmpty);
    },
  );

  test(
    'missing ACK keeps the same request available for reconnect replay',
    () async {
      await connect();
      await advertiseSupport();
      service.sendStopSignal(sessionUuid: 'ended');
      final request = channels.last.stops.single['request_id'];
      await service.forceReconnect('7', 'flutter_test-device');
      await advertiseSupport();
      expect(channels.last.stops.single['request_id'], request);
      channels.last.receive({'action': 'FOCUS_END_ACK', 'request_id': 'other'});
      await flushMessages();
      await service.forceReconnect('7', 'flutter_test-device');
      await advertiseSupport();
      expect(channels.last.stops.single['request_id'], request);
    },
  );

  test(
    'a delayed reconnect callback cannot restore a locally ended session',
    () async {
      await connect();
      service.sendStopSignal(sessionUuid: 'ended');
      restore('ended');
      expect(
        channels.last.sent.where((m) => m['action'] == 'RECONNECT_SYNC'),
        isEmpty,
      );
      restore('new-session');
      expect(channels.last.sent.last['session_uuid'], 'new-session');
    },
  );

  test(
    'background completion gets a delivery window and suspends after ACK',
    () async {
      await connect();
      await advertiseSupport();
      service.setLocalFocusing(true);
      await service.suspendForBackground();
      service.sendStopSignal(sessionUuid: 'background-end');
      service.setLocalFocusing(false);
      await flushMessages();
      expect(service.connectionState, SyncConnectionState.connected);
      channels.last.receive({
        'action': 'FOCUS_END_ACK',
        'request_id': channels.last.stops.single['request_id'],
      });
      await flushMessages();
      expect(service.connectionState, SyncConnectionState.disconnected);
    },
  );

  test(
    'old servers receive current STOP but no unsafe retries on reconnect',
    () async {
      await connect();
      service.sendStopSignal(sessionUuid: 'legacy-end');
      expect(channels.last.stops, hasLength(1));
      await service.forceReconnect('7', 'flutter_test-device');
      expect(channels.last.stops, isEmpty);
    },
  );

  test(
    'switching accounts cannot replay the previous accounts pending STOP',
    () async {
      await connect();
      service.sendStopSignal(sessionUuid: 'previous-user');
      await service.forceReconnect('8', 'flutter_test-device');
      await advertiseSupport();
      expect(channels.last.stops, isEmpty);
    },
  );

  test(
    'an unacknowledged background STOP has a bounded connection window',
    () async {
      service.dispose();
      service = createService(grace: const Duration(milliseconds: 50));
      await connect();
      service.setLocalFocusing(true);
      await service.suspendForBackground();
      final disconnected = service.onConnectionChanged.firstWhere(
        (state) => state == SyncConnectionState.disconnected,
      );
      service.sendStopSignal(sessionUuid: 'legacy-background');
      service.setLocalFocusing(false);
      expect(service.connectionState, SyncConnectionState.connected);
      await disconnected.timeout(const Duration(seconds: 2));
      expect(service.connectionState, SyncConnectionState.disconnected);
    },
  );

  test(
    'heartbeat retries an unacknowledged STOP and stops after ACK',
    () async {
      service.dispose();
      service = createService(heartbeat: const Duration(milliseconds: 50));
      await connect();
      await advertiseSupport();
      service.sendStopSignal(sessionUuid: 'retry-end');
      final request = channels.last.stops.single['request_id'];
      await channels.last.outgoing.stream
          .firstWhere((message) => message['action'] == 'STOP')
          .timeout(const Duration(seconds: 2));
      expect(channels.last.stops.last['request_id'], request);
      channels.last.receive({'action': 'FOCUS_END_ACK', 'request_id': request});
      await flushMessages();
      final acknowledgedCount = channels.last.stops.length;
      await channels.last.outgoing.stream
          .firstWhere((message) => message['action'] == 'HEARTBEAT')
          .timeout(const Duration(seconds: 2));
      expect(channels.last.stops, hasLength(acknowledgedCount));
    },
  );
}
