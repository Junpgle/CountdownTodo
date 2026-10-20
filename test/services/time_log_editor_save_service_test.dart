import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/time_log_editor_save_service.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/plan_availability_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TimeLogEditorSaveService', () {
    late PlanAvailabilityFixture fixture;

    setUp(() async {
      fixture = PlanAvailabilityFixture();
      await fixture.initialize();
    });

    tearDown(() => fixture.dispose());

    test('只 upsert 本次日志，已有其他日志不被旧快照覆盖', () async {
      final existing = TimeLogItem(
        id: 'keep-existing',
        title: '并发新增的其他日志',
        startTime: 1_800_000_000_000,
        endTime: 1_800_000_060_000,
      );
      final edited = TimeLogItem(
        id: 'edited-log',
        title: '编辑后的标题',
        startTime: 1_800_000_100_000,
        endTime: 1_800_000_160_000,
      );
      await StorageService.saveTimeLogs(PlanAvailabilityFixture.username, [
        existing,
        edited,
      ], sync: false);

      final service = TimeLogEditorSaveService(
        (username, logs) =>
            StorageService.saveTimeLogs(username, logs, sync: false),
        (username) => StorageService.getTimeLogs(username),
      );
      final result = await service.save(
        PlanAvailabilityFixture.username,
        TimeLogItem(
          id: edited.id,
          title: '编辑后的标题（二次保存）',
          startTime: edited.startTime,
          endTime: edited.endTime,
          version: edited.version + 1,
          createdAt: edited.createdAt,
        ),
      );

      expect(result.disposition, TimeLogEditorSaveDisposition.saved);
      final saved = await StorageService.getTimeLogs(
        PlanAvailabilityFixture.username,
      );
      expect(saved.map((log) => log.id), containsAll([existing.id, edited.id]));
      expect(
        saved.singleWhere((log) => log.id == existing.id).title,
        existing.title,
      );
      expect(
        saved.singleWhere((log) => log.id == edited.id).title,
        '编辑后的标题（二次保存）',
      );
    });

    test('写入后返回异常时，读回完全一致的 UUID 判定为已保存', () async {
      final local = <String, TimeLogItem>{};
      var writerReceivedCount = 0;
      final log = TimeLogItem(
        id: 'stable-draft-id',
        title: '稳定草稿',
        tagUuids: const ['tag-a'],
        startTime: 1_800_000_000_000,
        endTime: 1_800_000_060_000,
        createdAt: 1_700_000_000_000,
        updatedAt: 1_800_000_200_000,
      );
      final service = TimeLogEditorSaveService((username, logs) async {
        expect(username, PlanAvailabilityFixture.username);
        expect(logs, hasLength(1));
        writerReceivedCount++;
        local[logs.single.id] = logs.single;
        throw StateError('post-commit cleanup failed');
      }, (username) async => local.values.toList());

      final result = await service.save(PlanAvailabilityFixture.username, log);

      expect(writerReceivedCount, 1);
      expect(
        result.disposition,
        TimeLogEditorSaveDisposition.savedAfterReadBack,
      );
      expect(result.isSaved, isTrue);
      expect(local.keys, [log.id]);
    });

    test('SQLite 已提交后发生异常时，按本机读回确认且容忍空设备字段', () async {
      final log = TimeLogItem(
        id: 'sqlite-read-back',
        title: 'SQLite 已提交',
        startTime: 1_800_000_300_000,
        endTime: 1_800_000_360_000,
      );
      final service = TimeLogEditorSaveService((username, logs) async {
        await StorageService.saveTimeLogs(username, logs, sync: false);
        throw StateError('simulated post-commit cleanup failure');
      }, (username) => StorageService.getTimeLogs(username));

      final result = await service.save(PlanAvailabilityFixture.username, log);

      expect(
        result.disposition,
        TimeLogEditorSaveDisposition.savedAfterReadBack,
      );
      expect(
        (await StorageService.getTimeLogs(PlanAvailabilityFixture.username))
            .single
            .id,
        log.id,
      );
    });

    test('未写入时保留失败状态；读回失败时标为结果未知', () async {
      final log = TimeLogItem(
        id: 'not-saved',
        title: '失败草稿',
        startTime: 1_800_000_000_000,
        endTime: 1_800_000_060_000,
      );
      final failed = TimeLogEditorSaveService(
        (username, logs) async => throw StateError('write failed'),
        (username) async => const <TimeLogItem>[],
      );
      final unknown = TimeLogEditorSaveService(
        (username, logs) async => throw StateError('write status unknown'),
        (username) async => throw StateError('read failed'),
      );

      expect(
        (await failed.save(PlanAvailabilityFixture.username, log)).disposition,
        TimeLogEditorSaveDisposition.failed,
      );
      expect(
        (await unknown.save(PlanAvailabilityFixture.username, log)).disposition,
        TimeLogEditorSaveDisposition.unknown,
      );
    });
  });
}
