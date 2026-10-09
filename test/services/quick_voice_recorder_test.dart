import 'dart:async';
import 'dart:typed_data';

import 'package:countdown_todo/services/quick_voice_recorder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

class _RecordPlatformFake extends Fake implements RecordPlatform {
  final streams = <StreamController<Uint8List>>[];
  var cancelCalls = 0;
  var startStreamCalls = 0;
  var shouldFailStop = true;

  @override
  Future<void> create(String recorderId) async {}

  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async =>
      true;

  @override
  void setOnConfigChanged(
    String recorderId,
    void Function(RecordConfig config)? handler,
  ) {}

  @override
  Stream<RecordState> onStateChanged(String recorderId) =>
      const Stream<RecordState>.empty();

  @override
  Future<Stream<Uint8List>> startStream(
    String recorderId,
    RecordConfig config,
  ) async {
    startStreamCalls++;
    final controller = StreamController<Uint8List>();
    streams.add(controller);
    return controller.stream;
  }

  @override
  Future<String?> stop(String recorderId) async {
    if (shouldFailStop) {
      shouldFailStop = false;
      throw StateError('platform stop failed');
    }
    return null;
  }

  @override
  Future<void> cancel(String recorderId) async {
    cancelCalls++;
    final stream = streams.isEmpty ? null : streams.last;
    if (stream != null && !stream.isClosed) await stream.close();
  }

  @override
  Future<void> dispose(String recorderId) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecordPlatform originalPlatform;
  late _RecordPlatformFake platform;

  setUp(() {
    originalPlatform = RecordPlatform.instance;
    platform = _RecordPlatformFake();
    RecordPlatform.instance = platform;
  });

  tearDown(() async {
    RecordPlatform.instance = originalPlatform;
    for (final stream in platform.streams) {
      if (!stream.isClosed) await stream.close();
    }
  });

  test(
    'platform stop failure cancels the stream and allows a fresh recording',
    () async {
      final recorder = RecordQuickVoiceRecorder();
      await recorder.start();

      await expectLater(recorder.stop(), throwsA(isA<StateError>()));
      expect(platform.cancelCalls, 1);

      await recorder.start();
      final wav = await recorder.stop();

      expect(platform.startStreamCalls, 2);
      expect(wav.length, 44);
      await recorder.dispose();
    },
  );
}
