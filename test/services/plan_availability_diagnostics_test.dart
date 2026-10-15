import 'dart:io';
import 'dart:math';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/models/plan_weekly_availability.dart';
import 'package:countdown_todo/services/plan_availability_service.dart';
import 'package:countdown_todo/services/plan_continuous_range_service.dart';
import 'package:flutter_test/flutter_test.dart';

final day = DateTime(2026, 10, 13), now = DateTime(2026, 10, 12, 7);
DateTime at(int m) => DateTime(day.year, day.month, day.day, m ~/ 60, m % 60);
PlanAvailabilityQuery q({
  int minutes = 75,
  int start = 540,
  int end = 720,
  int before = 0,
  int after = 0,
  PlanWeeklyContext? weekly,
  List<PlanDailyTimeWindow> avoid = const [],
}) => PlanAvailabilityQuery(
  username: 'diagnostic',
  todoId: 'task',
  date: day,
  minutes: minutes,
  windowStart: start,
  windowEnd: end,
  bufferBefore: before,
  bufferAfter: after,
  weekly: weekly,
  avoidWindows: avoid,
);
PlanBusyInterval b(int start, int end) =>
    PlanBusyInterval(at(start), at(end), source: PlanBusySource.fixedSchedule);
PlanAvailabilitySnapshot snapshot({
  List<PlanBusyInterval> busy = const [],
  DateTime? due,
  bool allDay = false,
  bool done = false,
}) => PlanAvailabilitySnapshot(
  todo: TodoItem(
    id: 'task',
    title: '合成任务',
    dueDate: due,
    isAllDay: allDay,
    isDone: done,
  ),
  busy: busy,
  coverage: '合成',
);
PlanWeeklyContext policy(List<PlanWeeklyWindow> windows) => PlanWeeklyContext(
  PlanWeeklyRules(enabled: true, days: List.generate(7, (_) => windows)),
);
List<int> times(List<PlanTimeSlot> slots) => [
  for (final s in slots) ...[
    s.start.millisecondsSinceEpoch,
    s.end.millisecondsSinceEpoch,
  ],
];

// Frozen pre-round-14 algorithm: independent compatibility oracle.
List<PlanTimeSlot> reference(
  PlanAvailabilityQuery query,
  PlanAvailabilitySnapshot s,
) {
  final start = at(query.windowStart), end = at(query.windowEnd);
  final allowed = query.weekly?.active == true
      ? [
          for (final w in query.weekly!.rules!.days[day.weekday - 1])
            PlanTimeSlot(at(w.start), at(w.end)),
        ]
      : [PlanTimeSlot(day, at(1440))];
  final blocked =
      [
            for (final b in s.busy) query.buffered(b),
            ...query.avoidWindows.map((w) => w.onDate(day)),
          ]
          .where((r) => r.end.isAfter(start) && r.start.isBefore(end))
          .map(
            (r) => PlanTimeSlot(
              r.start.isBefore(start) ? start : r.start,
              r.end.isAfter(end) ? end : r.end,
            ),
          )
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));
  final merged = <PlanTimeSlot>[];
  for (final r in blocked) {
    if (merged.isEmpty || r.start.isAfter(merged.last.end)) {
      merged.add(r);
    } else if (r.end.isAfter(merged.last.end)) {
      merged[merged.length - 1] = PlanTimeSlot(merged.last.start, r.end);
    }
  }
  final gaps = <PlanTimeSlot>[];
  var cursor = start;
  void add(DateTime end) {
    for (final w in allowed) {
      final a = cursor.isBefore(w.start) ? w.start : cursor;
      final z = end.isAfter(w.end) ? w.end : end;
      if (!a.add(Duration(minutes: query.minutes)).isAfter(z)) {
        gaps.add(PlanTimeSlot(a, z));
      }
    }
  }

  for (final r in merged) {
    add(r.start);
    cursor = r.end;
  }
  add(end);
  final slots = [
    for (final g in gaps.take(query.resultLimit))
      PlanTimeSlot(g.start, g.start.add(Duration(minutes: query.minutes))),
  ];
  for (var n = 1; slots.length < query.resultLimit; n++) {
    var added = false;
    for (final g in gaps) {
      final a = g.start.add(Duration(minutes: n * query.minutes));
      final z = a.add(Duration(minutes: query.minutes));
      if (!z.isAfter(g.end)) {
        slots.add(PlanTimeSlot(a, z));
        added = true;
        if (slots.length == query.resultLimit) break;
      }
    }
    if (!added) break;
  }
  return slots..sort((a, b) => a.start.compareTo(b.start));
}

void main() {
  test('two 45-minute fragments remain references, not 75-minute choices', () {
    final query = q(), s = snapshot(busy: [b(585, 675)]);
    final result = PlanAvailabilityService.find(query, s, now: now);
    expect(result.slots, isEmpty);
    expect(result.diagnostics!.reason, PlanAvailabilityReason.fragmented);
    expect(result.diagnostics!.longestMinutes, 45);
    expect(result.diagnostics!.totalMinutes, 90);
    expect(result.diagnostics!.fragments.length, 2);
    expect(() => result.diagnostics!.fragments.clear(), throwsUnsupportedError);
  });
  test(
    'overlaps subtract once in explicit stage order; buffers add only new loss',
    () {
      final d = PlanAvailabilityService.diagnose(
        q(
          before: 10,
          after: 5,
          avoid: [const PlanDailyTimeWindow('休息', 600, 630)],
        ),
        snapshot(busy: [b(615, 645), b(630, 660)]),
        now: now,
      );
      expect(d.stages.map((s) => s.minutes), [180, 180, 180, 150, 120, 110]);
      expect(d.totalMinutes, 110);
      expect(d.longestMinutes, 60);
    },
  );
  test('exact-length slot accepted; one minute more is fragmented', () {
    final s = snapshot(busy: [b(540, 645)]);
    final exact = PlanAvailabilityService.find(q(), s, now: now);
    expect(exact.slots.single.minutes, 75);
    expect(
      PlanAvailabilityService.accepts(
        PlanAvailabilitySelection(q(), exact.slots.single, s),
        s,
        now: now,
      ),
      isTrue,
    );
    expect(
      PlanAvailabilityService.find(q(minutes: 76), s, now: now).slots,
      isEmpty,
    );
  });
  test(
    'distinguishes invalid, ended, deadline, weekly-empty and no intersection',
    () {
      PlanAvailabilityReason reason(
        PlanAvailabilityQuery query, {
        PlanAvailabilitySnapshot? s,
        DateTime? clock,
      }) => PlanAvailabilityService.diagnose(
        query,
        s ?? snapshot(),
        now: clock ?? now,
      ).reason;
      expect(reason(q(minutes: 0)), PlanAvailabilityReason.invalid);
      expect(reason(q(), clock: at(721)), PlanAvailabilityReason.rangeEnded);
      expect(
        reason(q(), s: snapshot(due: at(530))),
        PlanAvailabilityReason.deadline,
      );
      expect(reason(q(weekly: policy([]))), PlanAvailabilityReason.weeklyNone);
      expect(
        reason(q(weekly: policy([const PlanWeeklyWindow(800, 900)]))),
        PlanAvailabilityReason.weeklyOutside,
      );
      expect(
        reason(q(), s: snapshot(busy: [b(500, 750)])),
        PlanAvailabilityReason.noTime,
      );
      expect(
        reason(q(weekly: const PlanWeeklyContext(null))),
        PlanAvailabilityReason.invalid,
      );
      for (final result in [
        PlanAvailabilityService.diagnose(q(), snapshot(due: at(530)), now: now),
        PlanAvailabilityService.diagnose(q(), snapshot(), now: at(721)),
      ]) {
        expect(result.stages.last.label, '当前时刻与截止裁剪后');
        expect(result.stages.last.minutes, 0);
      }
    },
  );
  test('seconds round starts upward and floor each fragment separately', () {
    final s = snapshot(
      due: at(720).add(const Duration(seconds: 30)),
      busy: [
        PlanBusyInterval(
          at(600),
          at(645).add(const Duration(seconds: 20)),
          source: PlanBusySource.course,
        ),
      ],
    );
    final d = PlanAvailabilityService.diagnose(
      q(end: 721),
      s,
      now: at(540).add(const Duration(seconds: 1)),
    );
    expect(d.fragments.first.start, at(541));
    expect(d.fragments.last.start, at(646));
    expect(d.totalMinutes, 59 + 74);
  });
  test('date-only due includes full local due day', () {
    final result = PlanAvailabilityService.find(
      q(),
      snapshot(due: day, allDay: true),
      now: now,
    );
    expect(result.slots, isNotEmpty);
  });
  test(
    '300 seeded schedules preserve original candidate timestamps and order',
    () {
      final random = Random(1400);
      for (var i = 0; i < 300; i++) {
        final query = q(
          start: 480,
          end: 1320,
          minutes: 10 + random.nextInt(110),
          before: random.nextInt(30),
          after: random.nextInt(30),
          weekly: i.isEven
              ? policy([
                  const PlanWeeklyWindow(480, 720),
                  const PlanWeeklyWindow(840, 1320),
                ])
              : null,
          avoid: i % 3 == 0 ? [const PlanDailyTimeWindow('午餐', 690, 750)] : [],
        );
        final s = snapshot(
          busy: List.generate(15, (_) {
            final a = 420 + random.nextInt(960);
            return b(a, a + 1 + random.nextInt(100));
          }),
        );
        expect(
          times(PlanAvailabilityService.find(query, s, now: now).slots),
          times(reference(query, s)),
          reason: 'schedule $i',
        );
      }
    },
  );
  test(
    'next-day query carries exclusion, overrides, keys and weekly context',
    () {
      final original = PlanAvailabilityQuery(
        username: 'a',
        todoId: 'x',
        date: day,
        minutes: 75,
        excludeBlockId: 'old',
        bufferBefore: 10,
        bufferAfter: 5,
        bufferOverride: true,
        bufferDefaultsKey: '10:5',
        avoidanceOverride: true,
        avoidanceDefaultsKey: 'avoid',
        weekly: policy([]),
      );
      final copy = original.onDate(DateTime(2027, 1, 1), limit: 5);
      expect(copy.excludeBlockId, 'old');
      expect(copy.bufferOverride, isTrue);
      expect(copy.avoidanceDefaultsKey, 'avoid');
      expect(copy.weekly, same(original.weekly));
      expect(copy.minutes, 75);
      expect(copy.bufferBefore, 10);
      expect(copy.bufferAfter, 5);
    },
  );
  test(
    'range chooses one per date first, then earliest extras, at most five',
    () {
      final queries = [
        for (var i = 1; i <= 3; i++)
          q().onDate(DateTime(day.year, day.month, day.day + i), limit: 5),
      ];
      final result = PlanContinuousRangeService.find(
        queries,
        [for (final _ in queries) snapshot()],
        now: now,
        start: queries.first.date,
        end: DateTime(day.year, day.month, day.day + 4),
        coverage: '合成',
      );
      expect(result.selections.length, 5);
      expect(result.selections.map((s) => s.query.date.day).toSet().length, 3);
      expect(result.selections.every((s) => s.slot.minutes == 75), isTrue);
      expect(result.selections.map((s) => s.slot.start).toSet().length, 5);
    },
  );
  test('range never returns partial results on invalid day', () {
    final queries = [q().onDate(at(1440)), q().onDate(at(2880))];
    expect(
      () => PlanContinuousRangeService.find(
        queries,
        [snapshot(), snapshot(done: true)],
        now: now,
        start: at(1440),
        end: at(4320),
        coverage: '合成',
      ),
      throwsA(isA<PlanAvailabilityException>()),
    );
  });
  test('actual DST minutes and ambiguous weekly boundaries', () {
    final zone = Platform.environment['TZ'];
    if (zone != 'America/New_York' && zone != 'Australia/Lord_Howe') return;
    final d = zone == 'America/New_York'
        ? DateTime(2026, 3, 8)
        : DateTime(2026, 10, 4);
    PlanAvailabilityQuery dst(List<PlanWeeklyWindow> windows) =>
        q(minutes: 180, start: 0, end: 240, weekly: policy(windows)).onDate(d);
    final result = PlanAvailabilityService.diagnose(
      dst([const PlanWeeklyWindow(0, 240)]),
      snapshot(),
      now: DateTime(d.year, d.month, d.day - 1),
    );
    expect(result.totalMinutes, zone == 'America/New_York' ? 180 : 210);
    final invalid = PlanAvailabilityService.diagnose(
      dst([const PlanWeeklyWindow(120, 240)]),
      snapshot(),
      now: DateTime(d.year, d.month, d.day - 1),
    );
    expect(invalid.reason, PlanAvailabilityReason.invalid);
    final fold = zone == 'America/New_York'
        ? DateTime(2026, 11, 1)
        : DateTime(2026, 4, 5);
    final ambiguous = dst([const PlanWeeklyWindow(90, 240)]).onDate(fold);
    expect(
      PlanAvailabilityService.diagnose(
        ambiguous,
        snapshot(),
        now: DateTime(fold.year, fold.month, fold.day - 1),
      ).reason,
      PlanAvailabilityReason.invalid,
    );
  });
}
