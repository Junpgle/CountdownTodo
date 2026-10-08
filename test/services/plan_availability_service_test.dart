import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/services/plan_availability_service.dart';
import 'package:flutter_test/flutter_test.dart';

final day = DateTime(2026, 10, 8);
final now = DateTime(2026, 10, 7, 12);
DateTime at(int hour, [int minute = 0]) => DateTime(2026, 10, 8, hour, minute);
PlanBusyInterval busy(
  int start,
  int end, [
  int startMinute = 0,
  int endMinute = 0,
]) => PlanBusyInterval(
  at(start, startMinute),
  at(end, endMinute),
  source: PlanBusySource.planBlock,
);
PlanAvailabilityQuery query({
  int minutes = 45,
  int start = 480,
  int end = 1320,
  DateTime? date,
}) => PlanAvailabilityQuery(
  username: 'fixture',
  todoId: 'todo-target',
  date: date ?? day,
  minutes: minutes,
  windowStart: start,
  windowEnd: end,
);
PlanAvailabilitySnapshot snapshot(
  List<PlanBusyInterval> busy, {
  TodoItem? todo,
}) => PlanAvailabilitySnapshot(
  todo: todo ?? TodoItem(id: 'todo-target', title: '复习高数'),
  busy: busy,
  coverage: '合成来源',
);

void main() {
  test('空闲整天默认提供五个互不重叠方案，可调数量', () {
    for (final limit in [3, 5, 8]) {
      final q = PlanAvailabilityQuery(
        username: 'fixture',
        todoId: 'todo-target',
        date: day,
        minutes: 45,
        resultLimit: limit,
      );
      final result = PlanAvailabilityService.find(q, snapshot([]), now: now);
      expect(result.slots.length, limit);
      for (var i = 1; i < result.slots.length; i++) {
        expect(
          result.slots[i].start.isBefore(result.slots[i - 1].end),
          isFalse,
        );
      }
      expect(
        result.slots.every(
          (slot) => PlanAvailabilityService.accepts(
            PlanAvailabilitySelection(q, slot, snapshot([])),
            snapshot([]),
            now: now,
          ),
        ),
        isTrue,
      );
    }
  });
  test('午休与午餐重叠合并、晚餐和自定义避让同时作用于查找与保存', () {
    final q = PlanAvailabilityQuery(
      username: 'fixture',
      todoId: 'todo-target',
      date: day,
      minutes: 45,
      windowStart: 660,
      windowEnd: 1440,
      resultLimit: 8,
      avoidWindows: const [
        PlanDailyTimeWindow('午休', 720, 840),
        PlanDailyTimeWindow('午餐', 690, 750),
        PlanDailyTimeWindow('晚餐', 1080, 1140),
        PlanDailyTimeWindow('运动', 900, 960),
      ],
    );
    final s = snapshot([]);
    final result = PlanAvailabilityService.find(q, s, now: now);
    expect(result.slots, hasLength(8));
    expect(
      result.slots.every(
        (slot) => PlanAvailabilityService.accepts(
          PlanAvailabilitySelection(q, slot, s),
          s,
          now: now,
        ),
      ),
      isTrue,
    );
    for (final hour in [12, 13, 15, 18]) {
      expect(
        PlanAvailabilityService.accepts(
          PlanAvailabilitySelection(q, PlanTimeSlot(at(hour), at(hour, 45)), s),
          s,
          now: now,
        ),
        isFalse,
      );
    }
    expect(result.slots.first.start, at(14));
  });
  test('避让边界相邻合法，全部避开、碎片不足及无效设置不伪造方案', () {
    final q = PlanAvailabilityQuery(
      username: 'fixture',
      todoId: 'todo-target',
      date: day,
      minutes: 60,
      windowStart: 660,
      windowEnd: 840,
      avoidWindows: const [PlanDailyTimeWindow('午休', 720, 840)],
    );
    final s = snapshot([]);
    expect(
      PlanAvailabilityService.find(q, s, now: now).slots.single.end,
      at(12),
    );
    expect(
      PlanAvailabilityService.accepts(
        PlanAvailabilitySelection(q, PlanTimeSlot(at(11), at(12)), s),
        s,
        now: now,
      ),
      isTrue,
    );
    for (final range in [
      const PlanDailyTimeWindow('全天', 0, 1440),
      const PlanDailyTimeWindow('无效', 800, 700),
    ]) {
      final invalid = PlanAvailabilityQuery(
        username: 'fixture',
        todoId: 'todo-target',
        date: day,
        minutes: 45,
        avoidWindows: [range],
      );
      expect(PlanAvailabilityService.find(invalid, s, now: now).slots, isEmpty);
    }
  });

  test('优先不同空档并补充长空档，默认五条按时间排序', () {
    final result = PlanAvailabilityService.find(
      query(),
      snapshot([busy(9, 10), busy(11, 12), busy(14, 15)]),
      now: now,
    );
    expect(result.slots.map((s) => s.start), [
      at(8),
      at(10),
      at(12),
      at(12, 45),
      at(15),
    ]);
    expect(result.slots.every((s) => s.minutes == 45), isTrue);
  });
  test('乱序重叠、包含及相邻占用正确合并', () {
    final result = PlanAvailabilityService.find(
      query(),
      snapshot([busy(10, 11), busy(9, 10), busy(9, 10, 15, 30), busy(8, 9)]),
      now: now,
    );
    expect(result.slots.first.start, at(11));
  });
  test('窗口恰好等于时长时仅一条合法', () {
    expect(
      PlanAvailabilityService.find(
        query(end: 525),
        snapshot([]),
        now: now,
      ).slots.single.end,
      at(8, 45),
    );
  });
  test('满日占用及无效占用', () {
    expect(
      PlanAvailabilityService.find(
        query(),
        snapshot([busy(0, 24)]),
        now: now,
      ).slots,
      isEmpty,
    );
    expect(
      PlanAvailabilityService.find(
        query(),
        snapshot([busy(9, 9), busy(10, 9)]),
        now: now,
      ).slots.first.start,
      at(8),
    );
  });
  test('跨日占用裁剪，边界相邻不重叠', () {
    final s = snapshot([
      PlanBusyInterval(
        DateTime(2026, 10, 7, 23),
        at(9),
        source: PlanBusySource.fixedSchedule,
      ),
      busy(9, 10),
    ]);
    expect(
      PlanAvailabilityService.find(query(), s, now: now).slots.first.start,
      at(10),
    );
  });
  test('截止点不占用但限制候选结束，日期待办允许当天完成', () {
    final deadline = TodoItem(
      id: 'todo-target',
      title: '作业',
      dueDate: at(8, 30),
      createdDate: at(8, 30).millisecondsSinceEpoch,
    );
    expect(
      PlanAvailabilityService.find(
        query(),
        snapshot([], todo: deadline),
        now: now,
      ).slots,
      isEmpty,
    );
    final dateOnly = TodoItem(
      id: 'todo-target',
      title: '作业',
      dueDate: day,
      isAllDay: true,
    );
    expect(
      PlanAvailabilityService.find(
        query(),
        snapshot([], todo: dateOnly),
        now: now,
      ).slots.first.start,
      at(8),
    );
  });
  test('截止已过与历史日期给出明确原因', () {
    final todo = TodoItem(
      id: 'todo-target',
      title: '作业',
      dueDate: at(7),
      createdDate: at(7).millisecondsSinceEpoch,
    );
    expect(
      PlanAvailabilityService.find(
        query(),
        snapshot([], todo: todo),
        now: now,
      ).message,
      '截止前已无可用时段',
    );
    expect(
      PlanAvailabilityService.find(
        query(date: DateTime(2026, 10, 6)),
        snapshot([]),
        now: now,
      ).message,
      contains('已过去'),
    );
  });
  test('今天向上取整分钟，选择与保存均拒绝过去候选', () {
    final current = at(10, 12).add(const Duration(seconds: 1));
    final q = query();
    final s = snapshot([]);
    final slot = PlanAvailabilityService.find(q, s, now: current).slots.first;
    expect(slot.start, at(10, 13));
    expect(
      PlanAvailabilityService.accepts(
        PlanAvailabilitySelection(q, slot, s),
        s,
        now: at(10, 14),
      ),
      isFalse,
    );
  });
  test('非法时长、倒置窗口、已完成待办均拒绝', () {
    for (final q in [
      query(minutes: 0),
      query(minutes: -1),
      query(minutes: 1000),
      query(start: 600, end: 500),
    ]) {
      expect(
        PlanAvailabilityService.find(q, snapshot([]), now: now).slots,
        isEmpty,
      );
    }
    expect(
      PlanAvailabilityService.find(
        query(),
        snapshot(
          [],
          todo: TodoItem(id: 'todo-target', title: '完成', isDone: true),
        ),
        now: now,
      ).slots,
      isEmpty,
    );
  });
  test('每个规划状态的占用和改期资格正确', () {
    for (final status in TodoPlanStatus.values) {
      final block = TodoPlanBlock(
        todoId: 'todo-target',
        startTime: 1,
        endTime: 2,
        status: status,
      );
      expect(
        PlanAvailabilityService.occupies(block),
        {
          TodoPlanStatus.planned,
          TodoPlanStatus.reminded,
          TodoPlanStatus.delayed,
          TodoPlanStatus.focusing,
        }.contains(status),
      );
      expect(
        PlanAvailabilityService.canReschedule(block),
        {
          TodoPlanStatus.planned,
          TodoPlanStatus.reminded,
          TodoPlanStatus.delayed,
        }.contains(status),
      );
    }
  });
  test('保存不局限当前推荐列表，但必须仍满足范围与无重叠', () {
    final q = query();
    final s = snapshot([]);
    final choice = PlanAvailabilitySelection(
      q,
      PlanTimeSlot(at(12), at(12, 45)),
      s,
    );
    expect(PlanAvailabilityService.accepts(choice, s, now: now), isTrue);
    expect(
      PlanAvailabilityService.accepts(
        choice,
        snapshot([busy(12, 13)]),
        now: now,
      ),
      isFalse,
    );
  });
}
