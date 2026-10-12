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
    final minute = value.subtract(Duration(seconds: value.second,
        milliseconds: value.millisecond, microseconds: value.microsecond));
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
    if (query.weekly != null && !query.weekly!.ignored && query.weekly!.rules == null) {
      return '每周可安排时间无法读取，请修复规则或明确选择本次不使用';
    }
    if (query.weekly?.active ?? false) {
      try {
        for(final w in query.weekly!.rules!.days[query.date.weekday-1]) {
          PlanWeeklyRules.boundary(query.date,w.start);
          PlanWeeklyRules.boundary(query.date,w.end);
        }
      } on FormatException catch (error) { return error.message; }
    }
    final today = DateTime(now.year, now.month, now.day);
    if (query.dayStart.isBefore(today)) return '所选日期已过去，请选择今天或之后的日期';
    return null;
  }

  static PlanAvailabilityResult freeGaps(
    PlanAvailabilityQuery query,
    PlanAvailabilitySnapshot snapshot, {
    required DateTime now,
  }) {
    final invalid = invalidReason(query, snapshot.todo, now);
    if (invalid != null) {
      return PlanAvailabilityResult(const [], message: invalid);
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
    final current = minuteCeiling(now);
    if (current.isAfter(start)) start = current;
    var deadlineLimited = false;
    final due = snapshot.todo.dueDate?.toLocal();
    if (due != null) {
      final deadline = snapshot.todo.isDateOnly
          ? DateTime(due.year, due.month, due.day + 1)
          : due;
      if (deadline.isBefore(end)) {
        end = deadline;
        deadlineLimited = true;
      }
      if (!deadline.isAfter(start)) {
        return const PlanAvailabilityResult([], message: '截止前已无可用时段');
      }
    }
    if (!end.isAfter(start)) {
      return const PlanAvailabilityResult([], message: '该时间范围已结束，请调整日期或时间范围');
    }
    final weekly = query.weekly;
    final allowed = weekly?.active == true
      ? [for(final w in weekly!.rules!.days[query.date.weekday-1])
          PlanTimeSlot(PlanWeeklyRules.boundary(query.date,w.start),PlanWeeklyRules.boundary(query.date,w.end))]
      : [PlanTimeSlot(query.dayStart,query.dayEnd)];
    if(allowed.isEmpty) {
      return PlanAvailabilityResult(const [],message:'${PlanWeeklyRules.weekdays[query.date.weekday-1]}未设置可安排时间');
    }
    final ranges =
        [
              ...snapshot.busy
                  .where((item) => item.end.isAfter(item.start))
                  .map(query.buffered),
              ...query.avoidWindows.map((item) => item.onDate(query.date)),
            ]
            .where(
              (item) => item.end.isAfter(start) && item.start.isBefore(end),
            )
            .map(
              (item) => PlanTimeSlot(
                item.start.isBefore(start) ? start : item.start,
                item.end.isAfter(end) ? end : item.end,
              ),
            )
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    final merged = <PlanTimeSlot>[];
    for (final item in ranges) {
      if (merged.isEmpty || item.start.isAfter(merged.last.end)) {
        merged.add(item);
      } else if (item.end.isAfter(merged.last.end)) {
        merged[merged.length - 1] = PlanTimeSlot(merged.last.start, item.end);
      }
    }
    final gaps = <PlanTimeSlot>[];
    var cursor = start;
    void addGap(DateTime gapEnd) {
      for(final window in allowed) {
        final slotStart = minuteCeiling(cursor.isBefore(window.start) ? window.start : cursor);
        final slotEnd = gapEnd.isAfter(window.end) ? window.end : gapEnd;
        if (!slotStart.add(Duration(minutes: query.minutes)).isAfter(slotEnd)) {
          gaps.add(PlanTimeSlot(slotStart, slotEnd));
        }
      }
    }

    for (final range in merged) {
      addGap(range.start);
      cursor = range.end;
    }
    addGap(end);
    // Offer different gaps first, then add later non-overlapping alternatives
    // within long gaps. A completely free day can still provide five choices.
    return PlanAvailabilityResult(gaps, message: gaps.isEmpty
      ? '${deadlineLimited ? '截止前' : '当天'}没有连续 ${query.minutes} 分钟的可用时段${query.hasBuffers ? '（开始前${query.bufferBefore}分钟、结束后${query.bufferAfter}分钟缓冲）' : ''}' : null);
  }

  static PlanAvailabilityResult find(PlanAvailabilityQuery query,
      PlanAvailabilitySnapshot snapshot, {required DateTime now}) {
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
    return PlanAvailabilityResult(slots, message: available.message);
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
    if(weekly?.active == true && !weekly!.rules!.days[query.date.weekday-1].any((w) =>
      !slot.start.isBefore(PlanWeeklyRules.boundary(query.date,w.start)) &&
      !slot.end.isAfter(PlanWeeklyRules.boundary(query.date,w.end)))) { return false; }
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
