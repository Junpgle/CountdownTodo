import 'dart:math';

import '../models.dart';
import '../storage_service.dart';
import '../utils/calendar_date_math.dart';
import 'pomodoro_service.dart';
import 'plan_todo_guard.dart';

/// Existing homepage missed-state policy, isolated from display aggregation.
class PlanTodayMaintenance {
  const PlanTodayMaintenance();
  Future<void> run(String username, DateTime now) async {
    final identity = await PlanTodoIdentity.capture(username);
    final range = CalendarDateMath.dayRange(now);
    final results = await Future.wait([
      StorageService.getPlanBlocksByDay(username, now),
      PomodoroService.getRecordsInRange(range.start, range.endExclusive),
    ]);
    await identity.check();
    final blocks = results[0] as List<TodoPlanBlock>;
    final records = (results[1] as List<PomodoroRecord>)
        .where(
          (r) =>
              !r.isDeleted &&
              r.startTime >= range.start.millisecondsSinceEpoch &&
              r.startTime < range.endExclusive.millisecondsSinceEpoch,
        )
        .toList();
    for (final block in blocks) {
      if (!block.isDeleted &&
          block.status == TodoPlanStatus.planned &&
          _actualSecondsForBlock(block, records) <= 0 &&
          block.endTime < now.millisecondsSinceEpoch) {
        // The decision retains the old cache/matching policy. A concurrent
        // edit or identity change must not be overwritten by this maintenance.
        await StorageService.savePlanBlockEdited(
          username,
          block,
          expectedVersion: block.version,
          expectedUpdatedAt: block.updatedAt,
          newStatus: TodoPlanStatus.missed,
          beforeWrite: (_) => identity.check(),
        );
      }
    }
  }

  bool _timeRangesOverlap(
    int startA,
    int endAExclusive,
    int startB,
    int endBExclusive,
  ) {
    return endAExclusive > startB && startA < endBExclusive;
  }

  String _normalizeTitle(String? s) {
    if (s == null) return '';
    return s.replaceAll(RegExp(r'\s+'), '').trim();
  }

  bool _isRecordAssociatedWithBlock(
    PomodoroRecord record,
    TodoPlanBlock block,
  ) {
    if (record.isDeleted || block.isDeleted) return false;

    if (record.planBlockId != null &&
        record.planBlockId!.isNotEmpty &&
        record.planBlockId == block.uuid) {
      return true;
    }

    if (block.pomodoroRecordIds.contains(record.uuid)) {
      return true;
    }

    if (record.planBlockId?.isNotEmpty == true) {
      return false;
    }

    if (record.todoUuid != null &&
        record.todoUuid!.isNotEmpty &&
        block.todoId.isNotEmpty &&
        record.todoUuid == block.todoId) {
      final recordEnd =
          record.endTime ??
          (record.startTime + record.effectiveDuration * 1000);
      return _timeRangesOverlap(
        record.startTime,
        recordEnd,
        block.startTime,
        block.endTime,
      );
    }

    final recordTitle = _normalizeTitle(record.todoTitle);
    final blockTitle = _normalizeTitle(block.titleSnapshot);
    if (recordTitle.isNotEmpty && blockTitle.isNotEmpty) {
      final recordEnd =
          record.endTime ??
          (record.startTime + record.effectiveDuration * 1000);
      if (_timeRangesOverlap(
            record.startTime,
            recordEnd,
            block.startTime,
            block.endTime,
          ) &&
          recordTitle == blockTitle) {
        return true;
      }
    }

    return false;
  }

  int _actualSecondsForBlock(
    TodoPlanBlock block,
    List<PomodoroRecord> records,
  ) {
    final linkedRecordSeconds = records
        .where((record) => _isRecordAssociatedWithBlock(record, block))
        .fold<int>(0, (sum, record) => sum + record.effectiveDuration);
    return max(block.actualFocusSeconds, linkedRecordSeconds);
  }
}
