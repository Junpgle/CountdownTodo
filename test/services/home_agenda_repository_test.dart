@TestOn('vm')
library;

import 'dart:async';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/home_agenda_repository.dart';
import 'package:countdown_todo/services/plan_review_repository.dart';
import 'package:countdown_todo/services/device_calendar_read_service.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/plan_availability_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlanAvailabilityFixture f;
  late PlanReviewRepository plans;
  final now = DateTime(2026, 10, 8, 12), day = DateTime(2026, 10, 8);
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 10, 8, hour, minute);
  Future<void> plan(
    String id,
    DateTime start, {
    int minutes = 60,
    TodoPlanStatus status = TodoPlanStatus.planned,
    String todo = 'todo-target',
  }) => f.block(
    TodoPlanBlock(
      id: id,
      todoId: todo,
      titleSnapshot: '规划$id',
      startTime: start.millisecondsSinceEpoch,
      endTime: start.add(Duration(minutes: minutes)).millisecondsSinceEpoch,
      plannedMinutes: minutes,
      status: status,
    ),
  );
  HomeAgendaRepository repository({
    HomeAgendaCourseLoader? courses,
    HomeAgendaFixedLoader? fixed,
    HomeAgendaCalendarLoader? calendar,
  }) => HomeAgendaRepository(
    plans: plans,
    courseLoader: courses ?? (_) async => [],
    fixedLoader: fixed ?? (_, _) async => [],
    calendarLoader: calendar ?? (_) async => [],
  );
  Future<HomeAgendaSnapshot> read(
    HomeAgendaRepository r, {
    List<TodoItem> todos = const [],
  }) => r.read(PlanAvailabilityFixture.username, now: now, todos: todos);
  setUp(() async {
    f = PlanAvailabilityFixture();
    await f.initialize();
    plans = PlanReviewRepository(databaseOverride: f.db, clock: () => now);
  });
  tearDown(() async => f.dispose());

  test('mixed sources sort once, reserve attention and keep planning metrics separate', () async {
    await plan('current', at(11, 30));
    await plan('missed', at(9), status: TodoPlanStatus.missed);
    for (var i = 0; i < 10; i++) {
      await plan('future$i', at(14, i));
    }
    for (var i = 0; i < 7; i++) {
      await plan('done$i', at(1, i), status: TodoPlanStatus.finished);
    }
    final r = repository(
      courses: (_) async => [
        CourseItem(
          uuid: 'c',
          courseName: '合成课程',
          teacherName: '',
          date: '2026-10-08',
          weekday: 4,
          startTime: 1300,
          endTime: 1400,
          weekIndex: 1,
          roomName: 'A302',
        ),
      ],
      fixed: (_, _) async => [
        FixedScheduleItem(
          id: 'f',
          title: '合成会议',
          date: '2026-10-08',
          startTime: at(13, 30).millisecondsSinceEpoch,
          endTime: at(14, 30).millisecondsSinceEpoch,
        ),
      ],
    );
    final data = await read(r);
    expect(data.visible.map((i) => i.id), [
      'plan:current',
      'course:c',
      'fixed:f:2026-10-08',
      'plan:future0',
    ]);
    expect(data.currentCount, 1);
    expect(data.upcomingCount, 12);
    expect(data.attentionCount, 1);
    expect(data.endedCount, 7);
    expect(
      data.plans!.card.rows.length,
      12,
    ); // 1 current, 5 future, 1 attention, 5 history.
    expect(data.plans!.card.overview.plan('n'), 19);
    expect(data.plans!.card.overview.plan('seconds'), 19 * 3600);
    expect(data.nextBoundary, at(12, 30));
    expect(await f.db.query('op_logs'), isEmpty);
  });
  test('same title from different sources survives and unselected linked todo is deduplicated', () async {
    for (var i = 0; i < 8; i++) {
      await plan('p$i', at(13, i), todo: 'linked-$i');
    }
    await f.todo('linked-7', '同名事项', due: at(15), legacyStart: at(14));
    await f.todo('unlinked-todo', '同名事项', due: at(15), legacyStart: at(14));
    final data = await read(
      repository(),
      todos: await StorageService.getTodos(PlanAvailabilityFixture.username),
    );
    expect(data.items.where((i) => i.todo?.id == 'linked-7'), isEmpty);
    expect(
      data.items.where((i) => i.todo?.id == 'unlinked-todo'),
      hasLength(1),
    );
    expect(data.items.map((i) => i.id).toSet().length, data.items.length);
  });
  test('carried plan appears today without entering today budget', () async {
    await plan('carry', DateTime(2026, 10, 7, 23), minutes: 14 * 60);
    await plan('today', at(14));
    final data = await read(repository());
    expect(data.current.single.id, 'plan:carry');
    expect(data.plans!.card.overview.plan('n'), 1);
    expect(data.plans!.card.overview.plan('seconds'), 3600);
    expect(data.nextBoundary, at(13));
  });
  test(
    'all-day and unknown end use separate presentation and local midnight',
    () async {
      await f.todo('all', '全天待办', due: day, allDay: true);
      final data = await read(
        repository(
          fixed: (_, _) async => [
            FixedScheduleItem(
              id: 'tbd',
              title: '结束待定',
              date: '2026-10-08',
              startTime: at(11).millisecondsSinceEpoch,
            ),
            FixedScheduleItem(id: 'all', title: '时间待定', date: '2026-10-08'),
          ],
        ),
        todos: await StorageService.getTodos(PlanAvailabilityFixture.username),
      );
      expect(data.allDay, hasLength(2));
      expect(data.current.single.id, 'fixed:tbd:2026-10-08');
      expect(data.current.single.end, DateTime(2026, 10, 9));
    },
  );
  test(
    'single-source failure retries only that source and keeps others',
    () async {
      var courseReads = 0, calendarReads = 0, fail = true;
      final r = repository(
        courses: (_) async {
          courseReads++;
          return [];
        },
        calendar: (_) async {
          calendarReads++;
          if (fail) throw StateError('calendar failure');
          return [
            DeviceCalendarEvent(
              id: 'e',
              calendarId: 'calendar',
              title: '日历事项',
              start: at(15),
              end: at(16),
              allDay: false,
            ),
          ];
        },
      );
      await plan('p', at(14));
      final first = await read(r);
      expect(first.errors.keys, [HomeAgendaSource.calendar]);
      expect(first.visible.single.id, 'plan:p');
      fail = false;
      final second = await r.read(
        PlanAvailabilityFixture.username,
        now: now,
        todos: [],
        previous: first,
        only: {HomeAgendaSource.calendar},
      );
      expect(courseReads, 1);
      expect(calendarReads, 2);
      expect(second.errors, isEmpty);
      expect(second.visible.map((i) => i.id), [
        'plan:p',
        'calendar:calendar:e:${at(15).millisecondsSinceEpoch}',
      ]);
      expect(await f.db.query('op_logs'), isEmpty);
    },
  );
  test('late source result is rejected after member switch', () async {
    final pending = Completer<List<CourseItem>>(), started = Completer<void>();
    final r = repository(
      courses: (_) {
        started.complete();
        return pending.future;
      },
    );
    final result = read(r);
    await started.future;
    await (await SharedPreferences.getInstance()).setInt('current_user_id', 8);
    pending.complete([]);
    await expectLater(result, throwsException);
  });
  test(
    'all current candidates remain counted when display is capped',
    () async {
      for (var i = 0; i < 12; i++) {
        await plan('overlap$i', at(11, 30));
      }
      final data = await read(repository());
      expect(data.visible, hasLength(5));
      expect(data.currentCount, 12);
      expect(data.hiddenCurrent, 7);
      expect(data.plans!.card.rows, hasLength(5));
    },
  );
}
