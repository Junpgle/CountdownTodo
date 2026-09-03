import 'dart:async';
import 'dart:io';

import 'package:countdown_todo/windows_island/island_ipc_file_watcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IslandIpcFileWatcher', () {
    late Directory tempDirectory;
    late StreamController<FileSystemEvent> events;
    IslandIpcFileWatcher? watcher;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp(
        'countdown_todo_ipc_watcher_',
      );
      events = StreamController<FileSystemEvent>.broadcast(sync: true);
    });

    tearDown(() async {
      watcher?.dispose();
      await events.close();
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('reacts to the target file and coalesces burst events', () async {
      final target = File(
        '${tempDirectory.path}${Platform.pathSeparator}payload.json',
      );
      var callbackCount = 0;
      watcher = IslandIpcFileWatcher(
        resolveFile: () async => target,
        onFileChanged: () async => callbackCount++,
        fallbackInterval: const Duration(hours: 1),
        degradedPollInterval: const Duration(milliseconds: 10),
        eventDebounce: const Duration(milliseconds: 10),
        watchDirectory: (_) => events.stream,
      );

      await watcher!.start();
      expect(callbackCount, 1);

      events
        ..add(FileSystemModifyEvent(
          '${tempDirectory.path}${Platform.pathSeparator}other.json',
          false,
          true,
        ))
        ..add(FileSystemModifyEvent(target.path, false, true))
        ..add(FileSystemModifyEvent(target.path, false, true))
        ..add(FileSystemModifyEvent(target.path, false, true));

      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(callbackCount, 2);
    });

    test('uses fast polling only when directory watching fails', () async {
      final target = File(
        '${tempDirectory.path}${Platform.pathSeparator}actions.json',
      );
      var callbackCount = 0;
      watcher = IslandIpcFileWatcher(
        resolveFile: () async => target,
        onFileChanged: () async => callbackCount++,
        fallbackInterval: const Duration(hours: 1),
        degradedPollInterval: const Duration(milliseconds: 10),
        watchDirectory: (_) => throw const FileSystemException(
          'watch unavailable',
        ),
      );

      await watcher!.start();
      expect(callbackCount, 1);

      await Future<void>.delayed(const Duration(milliseconds: 45));
      expect(callbackCount, greaterThanOrEqualTo(3));
    });

    test('serializes overlapping callbacks', () async {
      final target = File(
        '${tempDirectory.path}${Platform.pathSeparator}payload.json',
      );
      var activeCallbacks = 0;
      var maxActiveCallbacks = 0;
      var callbackCount = 0;
      watcher = IslandIpcFileWatcher(
        resolveFile: () async => target,
        onFileChanged: () async {
          callbackCount++;
          activeCallbacks++;
          maxActiveCallbacks = maxActiveCallbacks < activeCallbacks
              ? activeCallbacks
              : maxActiveCallbacks;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          activeCallbacks--;
        },
        fallbackInterval: const Duration(hours: 1),
        degradedPollInterval: const Duration(milliseconds: 10),
        eventDebounce: Duration.zero,
        watchDirectory: (_) => events.stream,
      );

      await watcher!.start();
      events.add(FileSystemModifyEvent(target.path, false, true));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      events.add(FileSystemModifyEvent(target.path, false, true));

      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(maxActiveCallbacks, 1);
      expect(callbackCount, 3);
    });
  });
}
