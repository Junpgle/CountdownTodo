import 'dart:math';

import '../models/plan_availability.dart';
import '../models/plan_split.dart';
import 'plan_availability_service.dart';

/// Pure, bounded search. Earliest start dominates later starts in the same gap.
abstract final class PlanSplitService {
  static PlanSplitResult find(
    PlanSplitQuery query,
    PlanSplitSnapshot snapshot, {
    required DateTime now,
    int operationLimit = 200000,
  }) {
    final invalid = query.invalidReason;
    if (invalid != null) return PlanSplitResult(const [], message: invalid);
    if (snapshot.days.length != query.days) {
      return const PlanSplitResult([], message: '范围数据不完整，请重新查找');
    }
    final gaps = <PlanTimeSlot>[];
    for (var i = 0; i < query.days; i++) {
      final result = PlanAvailabilityService.freeGaps(
        query.day(i),
        snapshot.days[i],
        now: now,
      );
      // Past dates/invalid tasks are errors; later days past the deadline just add no gaps.
      final reason = PlanAvailabilityService.invalidReason(
        query.day(i),
        snapshot.days[i].todo,
        now,
      );
      if (reason != null) return PlanSplitResult(const [], message: reason);
      gaps.addAll(result.slots);
    }
    final answers = <List<PlanTimeSlot>>[];
    final seen = <String>{};
    final spacing = max(query.base.bufferBefore, query.base.bufferAfter);
    var operations = 0, exhausted = false;
    for (var count = 2; count <= 6 && answers.length < 5; count++) {
      final failed = <String>{};
      bool search(
        int gapIndex,
        DateTime? cursor,
        int remaining,
        int parts,
        List<PlanTimeSlot> path,
      ) {
        if (++operations > operationLimit) {
          exhausted = true;
          return false;
        }
        if (parts == 0) {
          if (remaining != 0) return false;
          final key = path
              .map(
                (p) =>
                    '${p.start.millisecondsSinceEpoch}:${p.end.millisecondsSinceEpoch}',
              )
              .join(',');
          if (seen.add(key)) answers.add(List.unmodifiable(path));
          return true;
        }
        if (remaining < parts * 15 || remaining > parts * query.maximum) {
          return false;
        }
        final key =
            '$gapIndex:${cursor?.millisecondsSinceEpoch}:$remaining:$parts';
        if (failed.contains(key)) return false;
        var found = false;
        for (var i = gapIndex; i < gaps.length; i++) {
          final gap = gaps[i];
          final start = cursor != null && cursor.isAfter(gap.start)
              ? cursor
              : gap.start;
          final upper = min(
            min(query.maximum, remaining - (parts - 1) * 15),
            gap.end.difference(start).inMinutes,
          );
          final lower = max(15, remaining - (parts - 1) * query.maximum);
          for (var duration = upper; duration >= lower; duration--) {
            final end = start.add(Duration(minutes: duration));
            found =
                search(
                  i,
                  end.add(Duration(minutes: spacing)),
                  remaining - duration,
                  parts - 1,
                  [...path, PlanTimeSlot(start, end)],
                ) ||
                found;
            if (answers.length >= 5 || exhausted) return found;
          }
        }
        if (!found) failed.add(key);
        return found;
      }

      search(0, null, query.total, count, const []);
      if (exhausted) break;
    }
    answers.sort((a, b) {
      var c = a.length.compareTo(b.length);
      if (c != 0) return c;
      c = a.last.end.compareTo(b.last.end);
      if (c != 0) return c;
      for (var i = 0; i < a.length; i++) {
        c = a[i].start.compareTo(b[i].start);
        if (c != 0) return c;
      }
      return 0;
    });
    return PlanSplitResult(
      List.unmodifiable(answers),
      incomplete: exhausted,
      message: exhausted
          ? '搜索未完成，请缩小日期或时长范围后重试'
          : answers.isEmpty
          ? '当前条件未找到完整的${query.total}分钟方案（每段15–${query.maximum}分钟，最多6段）'
          : null,
    );
  }

  static bool accepts(
    PlanSplitQuery query,
    List<PlanTimeSlot> slots,
    PlanSplitSnapshot snapshot, {
    required DateTime now,
  }) {
    if (query.invalidReason != null ||
        snapshot.days.length != query.days ||
        slots.length < 2 ||
        slots.length > 6 ||
        slots.fold<int>(0, (sum, s) => sum + s.minutes) != query.total) {
      return false;
    }
    for (var i = 0; i < slots.length; i++) {
      final slot = slots[i];
      if (slot.minutes < 15 ||
          slot.minutes > query.maximum ||
          slot.end.difference(slot.start).inMilliseconds !=
              slot.minutes * 60000) {
        return false;
      }
      if (i > 0 &&
          slot.start.isBefore(
            slots[i - 1].end.add(
              Duration(
                minutes: max(query.base.bufferBefore, query.base.bufferAfter),
              ),
            ),
          )) {
        return false;
      }
      final index = List.generate(query.days, (n) => n).where((n) {
        final date = query.day(n).date;
        return date.year == slot.start.year &&
            date.month == slot.start.month &&
            date.day == slot.start.day;
      }).firstOrNull;
      if (index == null ||
          !PlanAvailabilityService.accepts(
            PlanAvailabilitySelection(
              query.day(index, minutes: slot.minutes),
              slot,
              snapshot.days[index],
            ),
            snapshot.days[index],
            now: now,
          )) {
        return false;
      }
    }
    return true;
  }
}
