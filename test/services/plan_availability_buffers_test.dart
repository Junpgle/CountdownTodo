import 'dart:convert';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/services/plan_availability_preferences.dart';
import 'package:countdown_todo/services/missed_plan_recovery_service.dart';
import 'package:countdown_todo/services/plan_conflict_review_service.dart';
import 'package:countdown_todo/services/plan_availability_repository.dart';
import 'package:countdown_todo/services/plan_availability_service.dart';
import 'package:countdown_todo/services/device_calendar_read_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../support/plan_availability_fixture.dart';

final day = PlanAvailabilityFixture.day, now = PlanAvailabilityFixture.now;
DateTime at(int h, [int m = 0]) => day.add(Duration(hours: h, minutes: m));
PlanAvailabilityQuery query({
  int before = 10,
  int after = 5,
  int start = 600,
  int end = 660,
  int minutes = 30,
  bool override = false,
  bool avoidanceOverride = false,
  String? defaults,
  String? avoidanceDefaults,
  String? exclude,
  List<PlanDailyTimeWindow> avoid = const [],
}) => PlanAvailabilityQuery(
  username: PlanAvailabilityFixture.username,
  todoId: 'todo-target',
  date: day,
  minutes: minutes,
  windowStart: start,
  windowEnd: end,
  bufferBefore: before,
  bufferAfter: after,
  bufferOverride: override,
  bufferDefaultsKey: defaults,
  avoidanceOverride: avoidanceOverride,
  avoidanceDefaultsKey: avoidanceDefaults,
  excludeBlockId: exclude,
  avoidWindows: avoid,
);
PlanAvailabilitySnapshot snapshot(List<PlanBusyInterval> busy) =>
    PlanAvailabilitySnapshot(
      todo: TodoItem(id: 'todo-target', title: '任务'),
      busy: busy,
      coverage: '合成',
    );
PlanBusyInterval busy(DateTime start, DateTime end) =>
    PlanBusyInterval(start, end, source: PlanBusySource.fixedSchedule);
List<PlanTimeSlot> find(PlanAvailabilityQuery q, PlanAvailabilitySnapshot s) =>
    PlanAvailabilityService.find(q, s, now: now).slots;
bool accepts(
  PlanAvailabilityQuery q,
  PlanAvailabilitySnapshot s,
  DateTime start,
) => PlanAvailabilityService.accepts(
  PlanAvailabilitySelection(
    q,
    PlanTimeSlot(start, start.add(Duration(minutes: q.minutes))),
    s,
  ),
  s,
  now: now,
);

class _AfterReadRepository extends PlanAvailabilityRepository {
  _AfterReadRepository(Database db, this.afterRead)
    : super(databaseOverride: db, clock: () => now);
  final Future<void> Function() afterRead;
  @override
  Future<PlanAvailabilitySnapshot> read(
    PlanAvailabilityQuery query, {
    bool forceRefresh = false,
    bool requireCalendar = false,
  }) async {
    final result = await super.read(
      query,
      forceRefresh: forceRefresh,
      requireCalendar: requireCalendar,
    );
    await afterRead();
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('buffer interval calculation', () {
    final s = snapshot([busy(at(9), at(10)), busy(at(11), at(12))]);
    test('asymmetric intervals retain task length and raw source', () {
      final q = query();
      final slots = find(q, s);
      expect(slots.single.start, at(10, 10));
      expect(slots.single.end, at(10, 40));
      expect(s.busy.first.end, at(10));
      expect(accepts(q, s, at(10, 10)), isTrue);
      expect(accepts(q, s, at(10, 9)), isFalse);
      expect(accepts(q, s, at(10, 25)), isTrue);
      expect(accepts(q, s, at(10, 26)), isFalse);
    });
    test('zero intervals preserve touching boundaries', () {
      final q = query(before: 0, after: 0);
      expect(find(q, s).map((v) => v.start), [at(10), at(10, 30)]);
      expect(accepts(q, s, at(10, 30)), isTrue);
    });
    test('one-sided buffers independently affect respective boundary', () {
      expect(find(query(before: 0), s).first.start, at(10));
      expect(accepts(query(before: 0), s, at(10, 26)), isFalse);
      expect(find(query(after: 0), s).first.start, at(10, 10));
      expect(accepts(query(after: 0), s, at(10, 30)), isTrue);
    });
    test('no artificial padding at empty search edges or deadline', () {
      final empty = snapshot([]);
      expect(find(query(before: 120, after: 120), empty).map((v) => v.start), [
        at(10),
        at(10, 30),
      ]);
      empty.todo.dueDate = at(10, 30);
      expect(find(query(), empty).single.end, at(10, 30));
    });
    test(
      'avoid windows are not expanded and overlapping real buffers merge',
      () {
        final q = query(
          start: 600,
          end: 840,
          avoid: const [PlanDailyTimeWindow('午休', 720, 840)],
        );
        expect(accepts(q, snapshot([]), at(11, 30)), isTrue);
        final merged = snapshot([
          busy(at(9), at(10)),
          busy(at(10, 5), at(10, 20)),
        ]);
        expect(find(q, merged).first.start, at(10, 30));
      },
    );
    test(
      'midnight previous and next intervals affect exact-minute boundaries',
      () {
        final early = query(start: 0, end: 60);
        expect(
          find(early, snapshot([busy(at(-1), at(0))])).first.start,
          at(0, 10),
        );
        final late = query(start: 1380, end: 1440);
        expect(
          accepts(late, snapshot([busy(at(24), at(25))]), at(23, 25)),
          isTrue,
        );
        expect(
          accepts(late, snapshot([busy(at(24), at(25))]), at(23, 26)),
          isFalse,
        );
      },
    );
    for (final value in [-1, 121]) {
      test('rejects invalid interval $value for either side', () {
        expect(find(query(before: value), s), isEmpty);
        expect(find(query(after: value), s), isEmpty);
        expect(accepts(query(before: value), s, at(10, 10)), isFalse);
      });
    }
    test(
      'natural day and padded boundaries across spring and fall clock changes',
      () {
        for (final date in [DateTime(2026, 3, 8), DateTime(2026, 11, 1)]) {
          final q = PlanAvailabilityQuery(
            username: 'x',
            todoId: 'todo-target',
            date: date,
            minutes: 30,
            bufferBefore: 10,
            bufferAfter: 5,
          );
          expect(q.dayEnd, DateTime(date.year, date.month, date.day + 1));
          expect(q.dayStart.difference(q.sourceStart).inMinutes, 10);
          expect(q.sourceEnd.difference(q.dayEnd).inMinutes, 5);
          expect(q.dayEnd.hour, 0);
          final offsetChange =
              q.dayEnd.timeZoneOffset - q.dayStart.timeZoneOffset;
          expect(
            q.dayEnd.difference(q.dayStart),
            const Duration(days: 1) - offsetChange,
          );
        }
      },
    );
    test('UTC boundary uses elapsed minutes and natural-day query bounds', () {
      final date = DateTime.utc(2026, 3, 8);
      final q = PlanAvailabilityQuery(
        username: 'x',
        todoId: 'todo-target',
        date: date,
        minutes: 30,
        windowStart: 0,
        windowEnd: 60,
        bufferBefore: 10,
      );
      final source = busy(
        q.dayStart.subtract(const Duration(minutes: 30)),
        q.dayStart,
      );
      final result = PlanAvailabilityService.find(
        q,
        snapshot([source]),
        now: date.subtract(const Duration(days: 1)),
      );
      expect(result.slots.single.start.difference(q.dayStart).inMinutes, 10);
    });
  });
  group('preferences', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));
    test(
      'version one preserves edited avoidance and initializes zero buffers',
      () async {
        SharedPreferences.setMockInitialValues({
          'plan_availability_avoidance_a': jsonEncode({
            'version': 1,
            'windows': [
              {'label': '午休', 'start': 750, 'end': 810, 'enabled': true},
            ],
          }),
        });
        var p = await PlanAvailabilityPreferences.load('a');
        expect(p.bufferKey, '0:0');
        expect(p.options.first.startMinutes, 750);
        await PlanAvailabilityPreferences.save(
          'a',
          p.options,
          {p.options.first},
          bufferBefore: 10,
          bufferAfter: 5,
        );
        p = await PlanAvailabilityPreferences.load('a');
        expect(p.bufferKey, '10:5');
        expect(p.selectedIndices, {0});
        expect(p.options.first.startMinutes, 750);
        expect((await PlanAvailabilityPreferences.load('b')).bufferKey, '0:0');
      },
    );
    test('corrupt preferences require explicit reset instead of using zero buffers', () async {
      SharedPreferences.setMockInitialValues({
        'plan_availability_avoidance_a': 'not-json',
      });
      final p = await PlanAvailabilityPreferences.load('a');
      expect(p.bufferError, isNotNull);
      await PlanAvailabilityPreferences.save(
        'a',
        p.options,
        {for (final index in p.selectedIndices) p.options[index]},
        bufferBefore: 0,
        bufferAfter: 0,
      );
      final reset = await PlanAvailabilityPreferences.load('a');
      expect(reset.bufferError, isNull);
      expect(reset.bufferKey, '0:0');
    });
    test('rapid writes preserve captured values and old avoidance-only writers keep buffers', () async {
      final windows = PlanAvailabilityPreferences.defaultWindows;
      final a = PlanAvailabilityPreferences.save(
        'a',
        windows,
        {},
        bufferBefore: 5,
        bufferAfter: 10,
      );
      final b = PlanAvailabilityPreferences.save(
        'a',
        windows,
        {windows.last},
        bufferBefore: 17,
        bufferAfter: 0,
      );
      await Future.wait([a, b]);
      await PlanAvailabilityPreferences.save('a', windows, {windows.first});
      final p = await PlanAvailabilityPreferences.load('a');
      expect(p.bufferKey, '17:0');
      expect(p.selectedIndices, {0});
    });
    for (final value in [-1, 121, '10', null]) {
      test(
        'bad buffer $value keeps avoidance and exposes reset error',
        () async {
          SharedPreferences.setMockInitialValues({
            'plan_availability_avoidance_a': jsonEncode({
              'version': 2,
              'buffer_before': value,
              'buffer_after': 5,
              'windows': [
                {'label': '午休', 'start': 750, 'end': 810, 'enabled': true},
              ],
            }),
          });
          var p = await PlanAvailabilityPreferences.load('a');
          expect(p.bufferError, isNotNull);
          expect(p.selectedIndices, {0});
          await PlanAvailabilityPreferences.save(
            'a',
            p.options,
            {p.options.first},
            bufferBefore: 0,
            bufferAfter: 0,
          );
          p = await PlanAvailabilityPreferences.load('a');
          expect(p.bufferError, isNull);
          expect(p.selectedIndices, {0});
        },
      );
    }
  });
  group('real occupancy and guarded save', () {
    late PlanAvailabilityFixture f;
    late PlanAvailabilityRepository repository;
    setUp(() async {
      f = PlanAvailabilityFixture();
      await f.initialize();
      repository = PlanAvailabilityRepository(
        databaseOverride: f.db,
        clock: () => now,
      );
    });
    tearDown(() => f.dispose());
    for (final recovery in [true, false]) {
      test(
        'manual ${recovery ? "missed recovery" : "conflict edit"} retains buffers',
        () async {
          final source = TodoPlanBlock(
            id: 'source',
            todoId: 'todo-target',
            startTime: at(recovery ? -48 : 13).millisecondsSinceEpoch,
            endTime: at(recovery ? -47 : 14).millisecondsSinceEpoch,
            plannedMinutes: 60,
            status: recovery ? TodoPlanStatus.missed : TodoPlanStatus.planned,
          );
          await f.block(source);
          await f.fixed('neighbor', at(9), at(10));
          final original = await f.db.query('todo_plan_blocks');
          final input = TodoPlanBlock(
            id: recovery ? 'recovered' : 'source',
            todoId: 'todo-target',
            startTime: at(10).millisecondsSinceEpoch,
            endTime: at(10, 30).millisecondsSinceEpoch,
            plannedMinutes: 30,
          );
          if (recovery) {
            final service = MissedPlanRecoveryService(
              databaseOverride: f.db,
              clock: () => now,
            );
            final context = await service.read(
              PlanAvailabilityFixture.username,
              source.id,
            );
            await expectLater(
              service.save(
                context,
                input,
                null,
                manualQuery: query(),
                sync: false,
              ),
              throwsA(isA<PlanAvailabilityException>()),
            );
          } else {
            final service = PlanConflictReviewService(
              databaseOverride: f.db,
              clock: () => now,
            );
            final context = await service.prepareEdit(
              PlanAvailabilityFixture.username,
              source.id,
            );
            await expectLater(
              service.save(
                context,
                input,
                null,
                expectedBlock: context.block,
                manualQuery: query(),
                sync: false,
              ),
              throwsA(isA<PlanAvailabilityException>()),
            );
          }
          expect(await f.db.query('todo_plan_blocks'), original);
          expect(await f.db.query('op_logs'), isEmpty);
        },
      );
    }
    Future<PlanAvailabilitySelection> choose(PlanAvailabilityQuery q) async {
      final s = await repository.read(q);
      return PlanAvailabilitySelection(q, find(q, s).first, s);
    }

    TodoPlanBlock draft(PlanAvailabilitySelection s) => TodoPlanBlock(
      id: 'new-buffer-plan',
      todoId: s.query.todoId,
      startTime: s.slot.start.millisecondsSinceEpoch,
      endTime: s.slot.end.millisecondsSinceEpoch,
      plannedMinutes: s.slot.minutes,
    );
    test(
      'real course and fixed schedule give 10:10 with no source mutation',
      () async {
        await f.course('course', day, 900, 1000);
        await f.fixed('fixed', at(11), at(12));
        final choice = await choose(query());
        expect(choice.slot.start, at(10, 10));
        final saved = await repository.save(choice, draft(choice), sync: false);
        expect(saved.plannedMinutes, 30);
        expect(saved.actualFocusSeconds, 0);
        expect(saved.endTime - saved.startTime, 1800000);
        expect((await f.db.query('courses')).single['end_time'], 1000);
        expect(await f.db.query('op_logs'), hasLength(1));
      },
    );
    test(
      'changed avoidance defaults reject an old otherwise-free candidate',
      () async {
        final username = PlanAvailabilityFixture.username;
        final windows = PlanAvailabilityPreferences.defaultWindows;
        await PlanAvailabilityPreferences.save(
          username,
          windows,
          {},
          bufferBefore: 0,
          bufferAfter: 0,
        );
        final initialPreferences = await PlanAvailabilityPreferences.load(
          username,
        );
        final choice = await choose(
          query(
            before: 0,
            after: 0,
            start: 720,
            end: 840,
            defaults: '0:0',
            avoidanceDefaults: initialPreferences.avoidanceKey,
          ),
        );
        await PlanAvailabilityPreferences.save(
          username,
          windows,
          {windows.first},
          bufferBefore: 0,
          bufferAfter: 0,
        );

        await expectLater(
          repository.save(choice, draft(choice), sync: false),
          throwsA(isA<PlanAvailabilityException>()),
        );
        expect(await f.db.query('todo_plan_blocks'), isEmpty);
        expect(await f.db.query('op_logs'), isEmpty);
      },
    );
    test('fresh nonoverlapping occupancy intruding buffer rejects with zero writes', () async {
      final choice = await choose(query());
      await f.fixed('new-neighbor', at(9), at(9, 55));
      await expectLater(
        repository.save(choice, draft(choice), sync: false),
        throwsA(isA<PlanAvailabilityException>()),
      );
      expect(await f.db.query('todo_plan_blocks'), isEmpty);
      expect(await f.db.query('op_logs'), isEmpty);
    });
    test(
      'transaction recheck catches buffer intrusion after fresh read',
      () async {
        final choice = await choose(query());
        final racing = _AfterReadRepository(
          f.db,
          () => f.fixed('racing', at(9), at(9, 55)),
        );
        await expectLater(
          racing.save(choice, draft(choice), sync: false),
          throwsA(isA<PlanAvailabilityException>()),
        );
        expect(await f.db.query('todo_plan_blocks'), isEmpty);
        expect(await f.db.query('op_logs'), isEmpty);
      },
    );
    test(
      'neighbor-day courses fixed schedules and legacy reservations retained',
      () async {
        await f.fixed('prev', at(-1), at(0));
        await f.course('next', at(24), 1, 30);
        final early = await choose(query(start: 0, end: 60));
        expect(early.slot.start, at(0, 10));
        final q = query(start: 1380, end: 1440);
        final s = await repository.read(q);
        expect(s.busy.map((v) => v.id), contains('next'));
        expect(accepts(q, s, at(23, 27)), isFalse);
        final range = await repository.readRange(
          PlanAvailabilityFixture.username,
          day,
        );
        expect(range.days.single.busy, isEmpty);
      },
    );
    test('neighbor legacy intervals and other same-todo plans retained excluding only edit UUID', () async {
      await f.todo(
        'legacy',
        '旧时段',
        legacyStart: at(-1),
        due: at(0).subtract(const Duration(minutes: 1)),
      );
      await f.block(
        TodoPlanBlock(
          id: 'edit',
          todoId: 'todo-target',
          startTime: at(10).millisecondsSinceEpoch,
          endTime: at(10, 30).millisecondsSinceEpoch,
        ),
      );
      await f.block(
        TodoPlanBlock(
          id: 'other',
          todoId: 'todo-target',
          startTime: at(9).millisecondsSinceEpoch,
          endTime: at(10).millisecondsSinceEpoch,
        ),
      );
      final choice = await choose(query(exclude: 'edit'));
      expect(choice.slot.start, at(10, 10));
      final early = await repository.read(query(start: 0, end: 60));
      expect(early.busy.map((v) => v.id), contains('legacy'));
    });
    test('changed remembered defaults reject old selection; explicit override still works', () async {
      final windows = PlanAvailabilityPreferences.defaultWindows;
      await PlanAvailabilityPreferences.save(
        PlanAvailabilityFixture.username,
        windows,
        {},
        bufferBefore: 10,
        bufferAfter: 5,
      );
      final choice = await choose(query(defaults: '10:5'));
      await PlanAvailabilityPreferences.save(
        PlanAvailabilityFixture.username,
        windows,
        {},
        bufferBefore: 30,
        bufferAfter: 15,
      );
      await expectLater(
        repository.save(choice, draft(choice), sync: false),
        throwsA(isA<PlanAvailabilityException>()),
      );
      expect(await f.db.query('op_logs'), isEmpty);
      final explicit = await choose(
        query(before: 0, after: 0, override: true, defaults: '10:5'),
      );
      expect(
        (await repository.save(
          explicit,
          draft(explicit),
          sync: false,
        )).plannedMinutes,
        30,
      );
      expect(
        (await PlanAvailabilityPreferences.load(
          PlanAvailabilityFixture.username,
        )).bufferKey,
        '30:15',
      );
    });
    test('phone boundary range includes same-day late event and excludes original cross-day', () async {
      DeviceCalendarReadService.debugIsSupportedOverride = true;
      await DeviceCalendarReadService.setEnabled(true);
      Map<dynamic, dynamic>? arguments;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('countdown_todo/device_calendar_read'),
            (call) async {
              if (call.method == 'checkPermission') return true;
              arguments = call.arguments as Map;
              return [
                {
                  'id': 'late',
                  'startMs': at(-1, 50).millisecondsSinceEpoch,
                  'endMs': at(0)
                      .subtract(const Duration(minutes: 1))
                      .millisecondsSinceEpoch,
                  'allDay': false,
                },
                {
                  'id': 'cross',
                  'startMs': at(-1).millisecondsSinceEpoch,
                  'endMs': at(1).millisecondsSinceEpoch,
                  'allDay': false,
                },
              ];
            },
          );
      final q = query(start: 0, end: 60);
      final s = await repository.read(q, forceRefresh: true);
      expect(s.busy.map((v) => v.id), ['late']);
      expect(find(q, s).first.start, at(0, 9));
      expect(
        arguments.toString(),
        contains('${q.sourceStart.millisecondsSinceEpoch}'),
      );
    });
  });
}
