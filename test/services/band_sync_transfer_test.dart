import 'dart:async';
import 'dart:convert';

import 'package:countdown_todo/services/band_sync_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.math_quiz_app/band_communication');
  final packets = <Map<String, dynamic>>[];
  int? failedBatch;
  void Function(Map<String, dynamic>)? onPacket;

  Future<void> sendNativeEvent(String method, Object? arguments) async {
    final message = const StandardMethodCodec().encodeMethodCall(
      MethodCall(method, arguments),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      message,
      (ByteData? _) {},
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    packets.clear();
    failedBatch = null;
    onPacket = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'sendMessage') {
        final payload = jsonDecode(
          (call.arguments as Map)['data'] as String,
        ) as Map<String, dynamic>;
        packets.add(payload);
        onPacket?.call(payload);
        return payload['batchNum'] != failedBatch;
      }
      return true;
    });
    await BandSyncService.init();
    await BandSyncService.setServiceEnabled(true);
    await sendNativeEvent('onDeviceConnected', {
      'nodeId': 'test-band',
      'name': 'Test band',
    });
  });

  tearDown(() async {
    await BandSyncService.setServiceEnabled(false);
    BandSyncService.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('manual and band-requested sync use the same bounded batches', () async {
    final items = List.generate(6, (index) => {'id': '$index'});
    expect(await BandSyncService.syncTodos(items), isTrue);
    expect(packets.map((packet) => packet['batchNum']), [1, 2]);
    expect(packets.map((packet) => packet['totalBatches']), [2, 2]);
    expect(packets.map((packet) => (packet['data'] as List).length), [5, 1]);
    final manualTransferId = packets.first['transferId'];
    expect(manualTransferId, isNotEmpty);
    expect(packets.last['transferId'], manualTransferId);

    packets.clear();
    final automaticSent = Completer<void>();
    onPacket = (packet) {
      if (packet['batchNum'] == 2 && !automaticSent.isCompleted) {
        automaticSent.complete();
      }
    };
    BandSyncService.setSyncDataProvider((type) async => items);
    await sendNativeEvent('onMessageReceived', {
      'data': jsonEncode({'type': 'todo', 'action': 'request_sync'}),
    });
    await automaticSent.future.timeout(const Duration(seconds: 3));
    expect(packets.map((packet) => packet['batchNum']), [1, 2]);
    expect(packets.map((packet) => (packet['data'] as List).length), [5, 1]);
    expect(packets.first['transferId'], isNot(manualTransferId));
    expect(packets.last['transferId'], packets.first['transferId']);
  });

  test('failed SDK send retries its batch and stops later batches', () async {
    failedBatch = 2;
    final items = List.generate(11, (index) => {'id': '$index'});

    expect(await BandSyncService.syncTodos(items), isFalse);
    expect(packets.map((packet) => packet['batchNum']), [1, 2, 2, 2]);
    expect(packets.any((packet) => packet['batchNum'] == 3), isFalse);
  });

  test('oversized item aborts before any batch is sent', () async {
    final oversized = <String, dynamic>{};
    for (var index = 0; index < 200; index++) {
      oversized['field_$index'] = 'x' * 512;
    }

    expect(
        await BandSyncService.syncTodos([
          {'id': 'small'},
          oversized
        ]),
        isFalse);
    expect(packets, isEmpty);
  });

  test('new band reports failure when complete storage is rejected', () async {
    await sendNativeEvent('onMessageReceived', {
      'data': jsonEncode({
        'type': 'band_info',
        'version': 'test',
        'version_code': 8,
        'supports_sync_result': true,
      }),
    });
    expect(BandSyncService.supportsSyncResult, isTrue);

    final packetSent = Completer<void>();
    onPacket = (_) => packetSent.complete();
    final syncing = BandSyncService.syncTodos([
      {'id': 'one'}
    ]);
    await packetSent.future;
    final transferId = packets.single['transferId'];
    var completed = false;
    syncing.then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);

    await sendNativeEvent('onMessageReceived', {
      'data': jsonEncode({
        'type': 'sync_result',
        'syncType': 'todo',
        'transferId': transferId,
        'success': false,
      }),
    });
    expect(await syncing, isFalse);
  });

  test('new band reports success only after its storage receipt', () async {
    await sendNativeEvent('onMessageReceived', {
      'data': jsonEncode({
        'type': 'band_info',
        'version': 'test',
        'version_code': 8,
        'supports_sync_result': true,
      }),
    });
    final packetSent = Completer<void>();
    onPacket = (_) => packetSent.complete();
    final syncing = BandSyncService.syncTodos([
      {'id': 'one'}
    ]);
    await packetSent.future;

    await sendNativeEvent('onMessageReceived', {
      'data': jsonEncode({
        'type': 'sync_result',
        'syncType': 'todo',
        'transferId': packets.single['transferId'],
        'success': true,
      }),
    });
    expect(await syncing, isTrue);
  });
}
