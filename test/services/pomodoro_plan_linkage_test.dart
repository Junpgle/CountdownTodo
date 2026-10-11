import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/pomodoro_service.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/plan_availability_fixture.dart';

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
}

TodoPlanBlock _block(String id) => TodoPlanBlock(
  id: id,
  todoId: 'todo-target',
  startTime: 1000,
  endTime: 2_000_000,
  plannedMinutes: 20,
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
