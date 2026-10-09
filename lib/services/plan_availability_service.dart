import '../models.dart';
import '../models/plan_availability.dart';

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
    final minute = DateTime(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
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
    final today = DateTime(now.year, now.month, now.day);
    if (query.dayStart.isBefore(today)) return '所选日期已过去，请选择今天或之后的日期';
    return null;
  }

  static PlanAvailabilityResult find(
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
    final ranges =
        [
              ...snapshot.busy
                  .where((item) => item.end.isAfter(item.start))
                  .map((item) => PlanTimeSlot(item.start, item.end)),
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
      final slotStart = minuteCeiling(cursor);
      if (!slotStart.add(Duration(minutes: query.minutes)).isAfter(gapEnd)) {
        gaps.add(PlanTimeSlot(slotStart, gapEnd));
      }
    }

    for (final range in merged) {
      addGap(range.start);
      cursor = range.end;
    }
    addGap(end);
    // Offer different gaps first, then add later non-overlapping alternatives
    // within long gaps. A completely free day can still provide five choices.
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
      message: slots.isEmpty
          ? '${deadlineLimited ? '截止前' : '当天'}没有连续 ${query.minutes} 分钟的可用时段'
          : null,
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
    return !slot.start.isBefore(lower) &&
        !slot.end.isAfter(upper) &&
        !query.avoidWindows.any((item) {
          final range = item.onDate(query.date);
          return range.start.isBefore(slot.end) &&
              slot.start.isBefore(range.end);
        }) &&
        !snapshot.busy.any(
          (item) =>
              item.end.isAfter(item.start) &&
              item.start.isBefore(slot.end) &&
              slot.start.isBefore(item.end),
        );
  }
}
