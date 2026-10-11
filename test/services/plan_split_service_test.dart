import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/models/plan_split.dart';
import 'package:countdown_todo/services/plan_availability_service.dart';
import 'package:countdown_todo/services/plan_split_service.dart';
import 'package:flutter_test/flutter_test.dart';

final day = DateTime(2026, 10, 12), now = DateTime(2026, 10, 11);
DateTime at(int h, [int m = 0]) => DateTime(2026, 10, 12, h, m);
PlanSplitQuery query({
  int total = 90,
  int maximum = 45,
  int days = 1,
  int before = 0,
  int after = 0,
  int start = 480,
  int end = 1320,
  List<PlanDailyTimeWindow> avoid = const [],
}) => PlanSplitQuery(
  PlanAvailabilityQuery(
    username: 'default',
    todoId: 'todo',
    date: day,
    minutes: total,
    windowStart: start,
    windowEnd: end,
    bufferBefore: before,
    bufferAfter: after,
    avoidWindows: avoid,
  ),
  days: days,
  maximum: maximum,
);
PlanSplitSnapshot snapshot({
  List<PlanBusyInterval> busy = const [],
  TodoItem? todo,
  int days = 1,
}) => PlanSplitSnapshot(
  List.generate(
    days,
    (_) => PlanAvailabilitySnapshot(
      todo: todo ?? TodoItem(id: 'todo', title: '长任务'),
      busy: busy,
      coverage: '合成',
    ),
  ),
);
PlanBusyInterval busy(int h1, int m1, int h2, int m2) => PlanBusyInterval(
  at(h1, m1),
  at(h2, m2),
  source: PlanBusySource.fixedSchedule,
);
void main() {
  test(
    '90 minutes fits two separate 45 minute gaps despite no continuous match',
    () {
      final q = query(start: 480, end: 660),
          s = snapshot(busy: [busy(8, 45, 10, 15)]);
      expect(
        PlanAvailabilityService.find(q.base, s.days.first, now: now).slots,
        isEmpty,
      );
      final r = PlanSplitService.find(q, s, now: now);
      expect(r.groups.first.map((s) => s.minutes), [45, 45]);
      expect(r.groups.first.map((s) => s.start), [at(8), at(10, 15)]);
      expect(PlanSplitService.accepts(q, r.groups.first, s, now: now), isTrue);
    },
  );
  test('short tail redistributed 50 = 35 + 15, never 45 + 5', () {
    final r = PlanSplitService.find(query(total: 50), snapshot(), now: now);
    expect(
      r.groups.any((g) => g.first.minutes == 35 && g.last.minutes == 15),
      isTrue,
    );
    expect(r.groups.length, 5);
    expect(
      r.groups
          .map(
            (g) => g
                .map(
                  (s) =>
                      s.start.millisecondsSinceEpoch.toString() +
                      s.end.millisecondsSinceEpoch.toString(),
                )
                .join(),
          )
          .toSet()
          .length,
      5,
    );
  });
  test('new segments share max asymmetric buffer rather than sum', () {
    final q = query(
          total: 60,
          maximum: 30,
          before: 10,
          after: 5,
          start: 480,
          end: 550,
        ),
        s = snapshot();
    final r = PlanSplitService.find(q, s, now: now);
    expect(
      r.groups.single[1].start.difference(r.groups.single[0].end).inMinutes,
      10,
    );
    expect(PlanSplitService.accepts(q, r.groups.single, s, now: now), isTrue);
  });
  test('avoidance is not padded, real busy is padded exactly once', () {
    final q = query(
      total: 60,
      maximum: 30,
      before: 10,
      after: 5,
      start: 480,
      end: 660,
      avoid: [const PlanDailyTimeWindow('休息', 540, 570)],
    );
    final s = snapshot(busy: [busy(10, 10, 11, 0)]);
    final r = PlanSplitService.find(q, s, now: now);
    for (final g in r.groups) {
      expect(PlanSplitService.accepts(q, g, s, now: now), isTrue);
    }
    expect(r.groups, isNotEmpty);
  });
  test('minimum, maximum, counts and total are strict', () {
    for (final q in [
      query(total: 29),
      query(total: 721),
      query(maximum: 14),
      query(days: 8),
      query(total: 181, maximum: 30),
    ]) {
      expect(
        PlanSplitService.find(q, snapshot(days: q.days), now: now).groups,
        isEmpty,
      );
    }
    expect(
      PlanSplitService.accepts(
        query(total: 60),
        [PlanTimeSlot(at(8), at(9))],
        snapshot(),
        now: now,
      ),
      isFalse,
    );
  });
  test('date-only deadline permits its full day, timed deadline clips', () {
    final dateOnly = snapshot(
      todo: TodoItem(id: 'todo', title: 'task', dueDate: day, isAllDay: true),
    );
    expect(
      PlanSplitService.find(query(), dateOnly, now: now).groups,
      isNotEmpty,
    );
    final timed = snapshot(
      todo: TodoItem(id: 'todo', title: 'task', dueDate: at(8, 50)),
    );
    expect(PlanSplitService.find(query(), timed, now: now).groups, isEmpty);
  });
  test('multi day range is explicit and no segment crosses midnight', () {
    final q = query(total: 90, maximum: 45, days: 3, start: 480, end: 525),
        s = snapshot(days: 3);
    final r = PlanSplitService.find(q, s, now: now);
    expect(r.groups.first.last.start, DateTime(2026, 10, 13, 8));
    for (final g in r.groups) {
      expect(PlanSplitService.accepts(q, g, s, now: now), isTrue);
    }
  });
  test('incomplete computation is distinguished from no free time', () {
    final r = PlanSplitService.find(
      query(),
      snapshot(),
      now: now,
      operationLimit: 1,
    );
    expect(r.incomplete, isTrue);
    expect(r.message, contains('搜索未完成'));
  });
  test(
    'completed, deleted, wrong todo and past date cannot generate groups',
    () {
      for (final t in [
        TodoItem(id: 'todo', title: 'task', isDone: true),
        TodoItem(id: 'todo', title: 'task', isDeleted: true),
        TodoItem(id: 'other', title: 'task'),
      ]) {
        expect(
          PlanSplitService.find(query(), snapshot(todo: t), now: now).groups,
          isEmpty,
        );
      }
      expect(
        PlanSplitService.find(
          query(),
          snapshot(),
          now: DateTime(2026, 10, 13),
        ).groups,
        isEmpty,
      );
    },
  );
  test('minute ceiling retains absolute instant and exact integer length', () {
    final v = DateTime.fromMillisecondsSinceEpoch(1793511060123);
    final ceil = PlanAvailabilityService.minuteCeiling(v);
    expect(ceil.difference(v).inMilliseconds, 59877);
    expect(ceil.second, 0);
  });
  test(
    'DST repeated hour preserves later absolute instant and elapsed minutes',
    () {
      final first = DateTime.utc(2026, 11, 1, 5, 30).toLocal(),
          second = DateTime.utc(2026, 11, 1, 6, 30).toLocal();
      if (first.timeZoneOffset == second.timeZoneOffset)
        return; // Dedicated TZ run below covers the fold.
      expect(first.hour, 1);
      expect(second.hour, 1);
      final rounded = PlanAvailabilityService.minuteCeiling(
        second.add(const Duration(seconds: 1)),
      );
      expect(rounded, second.add(const Duration(minutes: 1)));
      expect(rounded.timeZoneOffset, second.timeZoneOffset);
      final date = DateTime(2026, 11, 1);
      final q = PlanSplitQuery(
        PlanAvailabilityQuery(
          username: 'default',
          todoId: 'todo',
          date: date,
          minutes: 60,
          windowStart: 60,
          windowEnd: 180,
        ),
        maximum: 30,
      );
      final snaps = snapshot();
      final r = PlanSplitService.find(q, snaps, now: second);
      expect(r.groups, isNotEmpty);
      expect(r.groups.first.first.start, second);
      expect(
        PlanSplitService.accepts(q, r.groups.first, snaps, now: second),
        isTrue,
      );
    },
  );
}
