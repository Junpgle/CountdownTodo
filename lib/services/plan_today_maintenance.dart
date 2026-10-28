import '../models.dart';
import '../storage_service.dart';
import '../utils/calendar_date_math.dart';
import 'pomodoro_service.dart';
import 'plan_todo_guard.dart';

/// Reconciles expired plan states after Pomodoro records or page loads.
class PlanTodayMaintenance {
  static final RegExp _titleWhitespacePattern = RegExp(r'\s+');

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
    final expiredFocusing = blocks.any(
      (block) =>
          !block.isDeleted &&
          block.status == TodoPlanStatus.focusing &&
          block.endTime < now.millisecondsSinceEpoch,
    );
    PomodoroRunState? run;
    var focusStateReadable = true;
    if (expiredFocusing) {
      try {
        run = await PlanTodoGuard.runState(identity);
      } catch (_) {
        await identity.check();
        focusStateReadable = false;
      }
    }
    final records = (results[1] as List<PomodoroRecord>)
        .where(
          (r) =>
              !r.isDeleted &&
              r.startTime >= range.start.millisecondsSinceEpoch &&
              r.startTime < range.endExclusive.millisecondsSinceEpoch,
        )
        .toList();
    final actualSecondsByBlock =
        PomodoroPlanFocusAllocator.actualSecondsByBlock(
          blocks: blocks,
          records: records,
          legacyBlockMatcher: (record, block) {
            if (record.todoUuid?.isNotEmpty == true &&
                record.todoUuid == block.todoId) {
              return true;
            }
            final recordTitle = _normalizeTitle(record.todoTitle);
            final blockTitle = _normalizeTitle(block.titleSnapshot);
            return recordTitle.isNotEmpty && recordTitle == blockTitle;
          },
        );
    for (var blockIndex = 0; blockIndex < blocks.length; blockIndex++) {
      final block = blocks[blockIndex];
      if (block.isDeleted || block.endTime >= now.millisecondsSinceEpoch) {
        continue;
      }
      final actualSeconds = actualSecondsByBlock[blockIndex];
      TodoPlanStatus? nextStatus;
      if (block.status == TodoPlanStatus.planned && actualSeconds <= 0) {
        nextStatus = TodoPlanStatus.missed;
      } else if (block.status == TodoPlanStatus.focusing &&
          focusStateReadable &&
          !_hasActiveFocus(run, block)) {
        if (block.plannedMinutes > 0 &&
            actualSeconds >= block.plannedMinutes * 60 * 0.8) {
          nextStatus = TodoPlanStatus.finished;
        } else if (actualSeconds <= 0) {
          nextStatus = TodoPlanStatus.missed;
        } else {
          nextStatus = TodoPlanStatus.planned;
        }
      }
      if (nextStatus != null) {
        // The decision retains the old cache/matching policy. A concurrent
        // edit or identity change must not be overwritten by this maintenance.
        await StorageService.savePlanBlockEdited(
          username,
          block,
          expectedVersion: block.version,
          expectedUpdatedAt: block.updatedAt,
          newStatus: nextStatus,
          beforeWrite: (_) => identity.check(),
        );
      }
    }
  }

  bool _hasActiveFocus(PomodoroRunState? run, TodoPlanBlock block) {
    if (run == null ||
        (run.phase != PomodoroPhase.focusing &&
            run.phase != PomodoroPhase.remoteWatching)) {
      return false;
    }
    return run.planBlockId == block.uuid || run.todoUuid == block.todoId;
  }

  String _normalizeTitle(String? s) {
    if (s == null) return '';
    return s.replaceAll(_titleWhitespacePattern, '').trim();
  }
}
