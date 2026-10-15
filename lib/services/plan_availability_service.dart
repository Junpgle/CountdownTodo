import '../models.dart';
import '../models/plan_availability.dart';
import '../models/plan_weekly_availability.dart';

/// Pure interval calculation. Neither recommendations nor adoption write data.
abstract final class PlanAvailabilityService {
  static bool canReschedule(TodoPlanBlock block) =>
      !block.isDeleted &&
      {
        TodoPlanStatus.planned,
        TodoPlanStatus.reminded,
        TodoPlanStatus.delayed,
      }.contains(block.status);

  static bool occupies(TodoPlanBlock block) =>
      !block.isDeleted &&
      {
        TodoPlanStatus.planned,
        TodoPlanStatus.reminded,
        TodoPlanStatus.delayed,
        TodoPlanStatus.focusing,
      }.contains(block.status);

  static DateTime minuteCeiling(DateTime value) {
    final minute = value.subtract(
      Duration(
        seconds: value.second,
        milliseconds: value.millisecond,
        microseconds: value.microsecond,
      ),
    );
    return value.isAfter(minute)
        ? minute.add(const Duration(minutes: 1))
        : minute;
  }

  static String? invalidReason(
    PlanAvailabilityQuery query,
    TodoItem? todo,
    DateTime now,
  ) {
    if (todo == null || todo.id != query.todoId) return '请选择待办项目';
    if (todo.isDeleted || todo.isDone) return '该待办已完成或删除，请重新选择';
    if (query.windowStart < 0 ||
        query.windowEnd > 1440 ||
        query.windowEnd <= query.windowStart) {
      return '请设置有效的可安排时间范围';
    }
    if (query.minutes <= 0 ||
        query.minutes > query.windowEnd - query.windowStart) {
      return '需要时长必须大于零，且不能超过可安排范围';
    }
    if (query.bufferBefore < 0 ||
        query.bufferBefore > 120 ||
        query.bufferAfter < 0 ||
        query.bufferAfter > 120) {
      return '前后缓冲须为0–120分钟的整数';
    }
    if (query.resultLimit < 1 || query.resultLimit > 20) {
      return '推荐数量需在 1–20 个之间';
    }
    if (query.avoidWindows.any(
      (range) =>
          range.startMinutes < 0 ||
          range.endMinutes > 1440 ||
          range.endMinutes <= range.startMinutes,
    )) {
      return '请设置有效的避让时段，结束须晚于开始';
    }
    if (query.weekly != null &&
        !query.weekly!.ignored &&
        query.weekly!.rules == null) {
      return '每周可安排时间无法读取，请修复规则或明确选择本次不使用';
    }
    if (query.weekly?.active ?? false) {
      try {
        for (final w in query.weekly!.rules!.days[query.date.weekday - 1]) {
          PlanWeeklyRules.boundary(query.date, w.start);
          PlanWeeklyRules.boundary(query.date, w.end);
        }
      } on FormatException catch (error) {
        return error.message;
      }
    }
    final today = DateTime(now.year, now.month, now.day);
    if (query.dayStart.isBefore(today)) return '所选日期已过去，请选择今天或之后的日期';
    return null;
  }

  static DateTime? deadline(TodoItem todo) {
    final due = todo.dueDate?.toLocal();
    return due == null
        ? null
        : todo.isDateOnly
        ? DateTime(due.year, due.month, due.day + 1)
        : due;
  }

  static List<PlanTimeSlot> _subtract(
    List<PlanTimeSlot> input,
    Iterable<PlanTimeSlot> blocked,
  ) {
    final sorted = blocked.where((b) => b.end.isAfter(b.start)).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final merged = <PlanTimeSlot>[];
    for (final b in sorted) {
      if (merged.isEmpty || b.start.isAfter(merged.last.end)) {
        merged.add(b);
      } else if (b.end.isAfter(merged.last.end)) {
        merged[merged.length - 1] = PlanTimeSlot(merged.last.start, b.end);
      }
    }
    final result = <PlanTimeSlot>[];
    var i = 0;
    for (final gap in input) {
      var cursor = gap.start;
      while (i < merged.length && !merged[i].end.isAfter(cursor)) {
        i++;
      }
      while (i < merged.length && merged[i].start.isBefore(gap.end)) {
        final b = merged[i];
        if (b.start.isAfter(cursor)) result.add(PlanTimeSlot(cursor, b.start));
        if (!b.end.isBefore(gap.end)) {
          cursor = gap.end;
          break;
        }
        if (b.end.isAfter(cursor)) cursor = b.end;
        i++;
      }
      if (gap.end.isAfter(cursor)) result.add(PlanTimeSlot(cursor, gap.end));
    }
    return result;
  }

  static PlanAvailabilityDiagnostics diagnose(
    PlanAvailabilityQuery query,
    PlanAvailabilitySnapshot snapshot, {
    required DateTime now,
  }) {
    final invalid = invalidReason(query, snapshot.todo, now);
    if (invalid != null) {
      return PlanAvailabilityDiagnostics(
        PlanAvailabilityReason.invalid,
        invalid,
      );
    }
    var start = DateTime(
      query.date.year,
      query.date.month,
      query.date.day,
      query.windowStart ~/ 60,
      query.windowStart % 60,
    );
    var end = DateTime(
      query.date.year,
      query.date.month,
      query.date.day,
      query.windowEnd ~/ 60,
      query.windowEnd % 60,
    );
    final stages = <PlanAvailabilityStage>[];
    void stage(String label, List<PlanTimeSlot> gaps) => stages.add(
      PlanAvailabilityStage(
        label,
        gaps.fold(0, (n, s) => n + (s.minutes > 0 ? s.minutes : 0)),
      ),
    );
    stage('本次窗口', [PlanTimeSlot(start, end)]);
    final current = minuteCeiling(now), due = deadline(snapshot.todo);
    if (current.isAfter(start)) start = current;
    final deadlineLimited = due != null && due.isBefore(end);
    if (due != null && !due.isAfter(start)) {
      stage('当前时刻与截止裁剪后', []);
      return PlanAvailabilityDiagnostics(
        PlanAvailabilityReason.deadline,
        '截止前已无可用时段',
        stages: stages,
      );
    }
    if (deadlineLimited) end = due;
    if (!end.isAfter(start)) {
      stage('当前时刻与截止裁剪后', []);
      return PlanAvailabilityDiagnostics(
        PlanAvailabilityReason.rangeEnded,
        '该时间范围已结束，请调整日期或时间范围',
        stages: stages,
      );
    }
    var gaps = [PlanTimeSlot(start, end)];
    stage('当前时刻与截止裁剪后', gaps);
    final weekly = query.weekly;
    if (weekly?.active == true) {
      final windows = weekly!.rules!.days[query.date.weekday - 1];
      if (windows.isEmpty) {
        stage('每周可安排时间后', []);
        return PlanAvailabilityDiagnostics(
          PlanAvailabilityReason.weeklyNone,
          '${PlanWeeklyRules.weekdays[query.date.weekday - 1]}未设置可安排时间',
          stages: stages,
        );
      }
      gaps = [
        for (final w in windows)
          if (PlanWeeklyRules.boundary(query.date, w.end).isAfter(start) &&
              PlanWeeklyRules.boundary(query.date, w.start).isBefore(end))
            PlanTimeSlot(
              PlanWeeklyRules.boundary(query.date, w.start).isAfter(start)
                  ? PlanWeeklyRules.boundary(query.date, w.start)
                  : start,
              PlanWeeklyRules.boundary(query.date, w.end).isBefore(end)
                  ? PlanWeeklyRules.boundary(query.date, w.end)
                  : end,
            ),
      ];
    }
    stage('每周可安排时间后', gaps);
    if (gaps.isEmpty) {
      return PlanAvailabilityDiagnostics(
        PlanAvailabilityReason.weeklyOutside,
        '每周可安排时间与本次查找范围没有交集',
        stages: stages,
      );
    }
    gaps = _subtract(gaps, query.avoidWindows.map((w) => w.onDate(query.date)));
    stage('避让后', gaps);
    gaps = _subtract(
      gaps,
      snapshot.busy.map((b) => PlanTimeSlot(b.start, b.end)),
    );
    stage('日程占用后', gaps);
    gaps = _subtract(
      gaps,
      snapshot.busy.where((b) => b.end.isAfter(b.start)).map(query.buffered),
    );
    gaps = [
      for (final gap in gaps)
        if (gap.end.isAfter(minuteCeiling(gap.start)))
          PlanTimeSlot(minuteCeiling(gap.start), gap.end),
    ]..sort((a, b) => a.start.compareTo(b.start));
    stage('缓冲与整分钟裁剪后', gaps);
    final enough = gaps.any((g) => g.minutes >= query.minutes);
    final message = enough
        ? null
        : '${deadlineLimited ? '截止前' : '当天'}没有连续 ${query.minutes} 分钟的可用时段${query.hasBuffers ? '（开始前${query.bufferBefore}分钟、结束后${query.bufferAfter}分钟缓冲）' : ''}';
    return PlanAvailabilityDiagnostics(
      enough
          ? PlanAvailabilityReason.available
          : gaps.any((g) => g.minutes > 0)
          ? PlanAvailabilityReason.fragmented
          : PlanAvailabilityReason.noTime,
      message,
      fragments: gaps,
      stages: stages,
    );
  }

  static PlanAvailabilityResult freeGaps(
    PlanAvailabilityQuery query,
    PlanAvailabilitySnapshot snapshot, {
    required DateTime now,
  }) {
    final diagnostics = diagnose(query, snapshot, now: now);
    return PlanAvailabilityResult(
      diagnostics.fragments.where((s) => s.minutes >= query.minutes).toList(),
      message: diagnostics.message,
      diagnostics: diagnostics,
    );
  }

  static PlanAvailabilityResult find(
    PlanAvailabilityQuery query,
    PlanAvailabilitySnapshot snapshot, {
    required DateTime now,
  }) {
    final available = freeGaps(query, snapshot, now: now);
    final gaps = available.slots;
    final slots = gaps
        .take(query.resultLimit)
        .map(
          (gap) => PlanTimeSlot(
            gap.start,
            gap.start.add(Duration(minutes: query.minutes)),
          ),
        )
        .toList();
    for (var offset = 1; slots.length < query.resultLimit; offset++) {
      var added = false;
      for (final gap in gaps) {
        final slotStart = gap.start.add(
          Duration(minutes: query.minutes * offset),
        );
        final slotEnd = slotStart.add(Duration(minutes: query.minutes));
        if (!slotEnd.isAfter(gap.end)) {
          slots.add(PlanTimeSlot(slotStart, slotEnd));
          added = true;
          if (slots.length == query.resultLimit) break;
        }
      }
      if (!added) break;
    }
    slots.sort((a, b) => a.start.compareTo(b.start));
    return PlanAvailabilityResult(
      slots,
      message: available.message,
      diagnostics: available.diagnostics,
    );
  }

  static bool accepts(
    PlanAvailabilitySelection selection,
    PlanAvailabilitySnapshot snapshot, {
    required DateTime now,
  }) {
    final slot = selection.slot;
    if (invalidReason(selection.query, snapshot.todo, now) != null ||
        slot.start.isBefore(minuteCeiling(now)) ||
        slot.minutes != selection.query.minutes ||
        !slot.end.isAfter(slot.start)) {
      return false;
    }
    final query = selection.query;
    final lower = DateTime(
      query.date.year,
      query.date.month,
      query.date.day,
      query.windowStart ~/ 60,
      query.windowStart % 60,
    );
    var upper = DateTime(
      query.date.year,
      query.date.month,
      query.date.day,
      query.windowEnd ~/ 60,
      query.windowEnd % 60,
    );
    final due = snapshot.todo.dueDate?.toLocal();
    if (due != null) {
      final deadline = snapshot.todo.isDateOnly
          ? DateTime(due.year, due.month, due.day + 1)
          : due;
      if (deadline.isBefore(upper)) upper = deadline;
    }
    final weekly = query.weekly;
    if (weekly?.active == true &&
        !weekly!.rules!.days[query.date.weekday - 1].any(
          (w) =>
              !slot.start.isBefore(
                PlanWeeklyRules.boundary(query.date, w.start),
              ) &&
              !slot.end.isAfter(PlanWeeklyRules.boundary(query.date, w.end)),
        )) {
      return false;
    }
    return !slot.start.isBefore(lower) &&
        !slot.end.isAfter(upper) &&
        !query.avoidWindows.any((item) {
          final range = item.onDate(query.date);
          return range.start.isBefore(slot.end) &&
              slot.start.isBefore(range.end);
        }) &&
        !snapshot.busy.any((item) {
          final range = query.buffered(item);
          return item.end.isAfter(item.start) &&
              range.start.isBefore(slot.end) &&
              slot.start.isBefore(range.end);
        });
  }
}
