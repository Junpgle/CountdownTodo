import 'dart:convert';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/pomodoro_service.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/plan_availability_fixture.dart';

class _PomodoroFetchClient extends http.BaseClient {
  _PomodoroFetchClient(this.records);

  final List<Map<String, dynamic>> records;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(records))),
      200,
      headers: const {'content-type': 'application/json'},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlanAvailabilityFixture fixture;

  setUp(() async {
    fixture = PlanAvailabilityFixture();
    await fixture.initialize();
  });

  tearDown(() async {
    await fixture.dispose();
  });

  test(
    'editing, rebinding, and deleting a record updates linked plan totals',
    () async {
      await fixture.block(_block('plan-a'));
      await fixture.block(_block('plan-b'));

      final initial = _record(planBlockId: 'plan-a', actualDuration: 600);
      await Future.wait([
        PomodoroService.addRecord(initial, isSyncSource: true),
        PomodoroService.addRecord(initial, isSyncSource: true),
      ]);

      expect(await _actualSeconds('plan-a'), 600);
      expect(await _recordIds('plan-a'), [initial.uuid]);

      await PomodoroService.updateRecord(_copyRecord(initial, note: '补充备注'));
      expect(await _actualSeconds('plan-a'), 600);
      expect(await _recordIds('plan-a'), [initial.uuid]);

      final longer = _copyRecord(initial, actualDuration: 900, note: '补充备注');
      await PomodoroService.updateRecord(longer);
      expect(await _actualSeconds('plan-a'), 900);

      final rebound = _copyRecord(longer, planBlockId: 'plan-b');
      await PomodoroService.updateRecord(rebound);
      expect(await _actualSeconds('plan-a'), 0);
      expect(await _recordIds('plan-a'), isEmpty);
      expect(await _actualSeconds('plan-b'), 900);
      expect(await _recordIds('plan-b'), [initial.uuid]);

      await PomodoroService.deleteRecord(initial.uuid);
      expect(await _actualSeconds('plan-b'), 0);
      expect(await _recordIds('plan-b'), isEmpty);
    },
  );

  test('merging a cloud record updates its linked plan progress', () async {
    final stalePlanSnapshot = _block('plan-a', plannedMinutes: 10);
    await fixture.block(stalePlanSnapshot);
    final remote = _record(planBlockId: 'plan-a', actualDuration: 600);

    expect(await PomodoroService.mergeRecordsLww([remote]), isTrue);

    // The enclosing account sync later persists the plan-block snapshot it
    // loaded before merging Pomodoro records. Reconcile after that save.
    await StorageService.savePlanBlocks(
      PlanAvailabilityFixture.username,
      [stalePlanSnapshot],
      sync: false,
      isSyncSource: true,
    );
    expect((await _blockFromStorage('plan-a')).actualFocusSeconds, 0);

    await PomodoroService.reconcilePlanBlockProgress(
      PlanAvailabilityFixture.username,
    );

    final block = await _blockFromStorage('plan-a');
    expect(block.actualFocusSeconds, 600);
    expect(block.pomodoroRecordIds, [remote.uuid]);
    expect(block.status, TodoPlanStatus.finished);
  });

  test('downloading cloud records updates linked plan progress', () async {
    await fixture.block(_block('plan-a', plannedMinutes: 10));
    final remote = _record(planBlockId: 'plan-a', actualDuration: 600);
    final client = _PomodoroFetchClient([remote.toJson()]);

    expect(
      await PomodoroService.syncRecordsFromCloud(fromMs: 0, client: client),
      isTrue,
    );

    final block = await _blockFromStorage('plan-a');
    expect(block.actualFocusSeconds, 600);
    expect(block.pomodoroRecordIds, [remote.uuid]);
    expect(block.status, TodoPlanStatus.finished);
    client.close();
  });
}

TodoPlanBlock _block(String id, {int plannedMinutes = 20}) => TodoPlanBlock(
  id: id,
  todoId: 'todo-target',
  titleSnapshot: '合成规划',
  startTime: 1000,
  endTime: 2_000_000,
  plannedMinutes: plannedMinutes,
);

PomodoroRecord _record({
  String? planBlockId,
  int actualDuration = 600,
  String? note,
}) => PomodoroRecord(
  uuid: 'linked-pomodoro-record',
  todoUuid: 'todo-target',
  todoTitle: '复习高数',
  startTime: 10_000,
  endTime: 610_000,
  plannedDuration: 600,
  actualDuration: actualDuration,
  planBlockId: planBlockId,
  note: note,
  createdAt: 500,
  updatedAt: 1000,
);

PomodoroRecord _copyRecord(
  PomodoroRecord source, {
  String? planBlockId,
  int? actualDuration,
  String? note,
}) => PomodoroRecord(
  uuid: source.uuid,
  todoUuid: source.todoUuid,
  todoTitle: source.todoTitle,
  tagUuids: source.tagUuids,
  startTime: source.startTime,
  endTime: source.endTime,
  plannedDuration: source.plannedDuration,
  actualDuration: actualDuration ?? source.actualDuration,
  status: source.status,
  deviceId: source.deviceId,
  planBlockId: planBlockId ?? source.planBlockId,
  note: note ?? source.note,
  totalPauseSeconds: source.totalPauseSeconds,
  pauseIntervals: source.pauseIntervals,
  isDeleted: source.isDeleted,
  version: source.version,
  createdAt: source.createdAt,
  updatedAt: source.updatedAt,
);

Future<int> _actualSeconds(String blockId) async =>
    (await _blockFromStorage(blockId)).actualFocusSeconds;

Future<List<String>> _recordIds(String blockId) async =>
    (await _blockFromStorage(blockId)).pomodoroRecordIds;

Future<TodoPlanBlock> _blockFromStorage(String blockId) async {
  final blocks = await StorageService.getPlanBlocks(
    PlanAvailabilityFixture.username,
    includeDeleted: true,
  );
  return blocks.singleWhere((block) => block.uuid == blockId);
}
