import 'package:countdown_todo/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DataRefreshSignal', () {
    test('merges scoped domains inside the debounce window', () async {
      final before = StorageService.scopedDataRefreshNotifier.value.revision;

      StorageService.triggerRefresh(const {DataRefreshDomain.todos});
      StorageService.triggerRefresh(
        const {DataRefreshDomain.countdowns, DataRefreshDomain.courses},
      );

      await Future<void>.delayed(const Duration(milliseconds: 150));
      final signal = StorageService.scopedDataRefreshNotifier.value;
      expect(signal.revision, before + 1);
      expect(
        signal.domains,
        const {
          DataRefreshDomain.todos,
          DataRefreshDomain.countdowns,
          DataRefreshDomain.courses,
        },
      );
      expect(signal.affects(DataRefreshDomain.todos), isTrue);
      expect(signal.affects(DataRefreshDomain.habits), isFalse);
    });

    test('full refresh supersedes scoped domains', () async {
      StorageService.triggerRefresh(const {DataRefreshDomain.todos});
      StorageService.triggerRefresh();
      StorageService.triggerRefresh(const {DataRefreshDomain.courses});

      await Future<void>.delayed(const Duration(milliseconds: 150));
      final signal = StorageService.scopedDataRefreshNotifier.value;
      expect(signal.domains, const {DataRefreshDomain.all});
      expect(signal.affects(DataRefreshDomain.habits), isTrue);
    });

    test('pomodoro refresh stays scoped to focus-dependent consumers',
        () async {
      StorageService.triggerRefresh(const {DataRefreshDomain.pomodoro});

      await Future<void>.delayed(const Duration(milliseconds: 150));
      final signal = StorageService.scopedDataRefreshNotifier.value;
      expect(signal.domains, const {DataRefreshDomain.pomodoro});
      expect(signal.affects(DataRefreshDomain.pomodoro), isTrue);
      expect(signal.affects(DataRefreshDomain.todos), isFalse);
    });

    test('team cleanup domains refresh every affected dashboard consumer',
        () async {
      StorageService.triggerRefresh(const {
        DataRefreshDomain.todos,
        DataRefreshDomain.todoGroups,
        DataRefreshDomain.countdowns,
        DataRefreshDomain.fixedSchedules,
        DataRefreshDomain.courses,
        DataRefreshDomain.timeLogs,
        DataRefreshDomain.planBlocks,
      });

      await Future<void>.delayed(const Duration(milliseconds: 150));
      final signal = StorageService.scopedDataRefreshNotifier.value;
      expect(
        signal.domains,
        const {
          DataRefreshDomain.todos,
          DataRefreshDomain.todoGroups,
          DataRefreshDomain.countdowns,
          DataRefreshDomain.fixedSchedules,
          DataRefreshDomain.courses,
          DataRefreshDomain.timeLogs,
          DataRefreshDomain.planBlocks,
        },
      );
      expect(signal.affects(DataRefreshDomain.courses), isTrue);
      expect(signal.affects(DataRefreshDomain.timeLogs), isTrue);
      expect(signal.affects(DataRefreshDomain.planBlocks), isTrue);
    });
  });
}
