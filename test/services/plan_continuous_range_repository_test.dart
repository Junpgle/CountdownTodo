@TestOn('vm')
library;

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/models/plan_weekly_availability.dart';
import 'package:countdown_todo/services/plan_availability_repository.dart';
import 'package:countdown_todo/services/plan_availability_service.dart';
import 'package:countdown_todo/services/device_calendar_read_service.dart';
import 'package:countdown_todo/services/plan_weekly_availability_preferences.dart';
import 'package:countdown_todo/services/plan_todo_guard.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/plan_availability_fixture.dart';

class _AfterReadRepository extends PlanAvailabilityRepository {
  _AfterReadRepository(Database db, this.afterRead)
    : super(databaseOverride: db, clock: () => PlanAvailabilityFixture.now);
  final Future<void> Function() afterRead;
  @override
  Future<PlanAvailabilitySnapshot> read(
    PlanAvailabilityQuery q, {
    bool forceRefresh = false,
    bool requireCalendar = false,
  }) async {
    final result = await super.read(
      q,
      forceRefresh: forceRefresh,
      requireCalendar: requireCalendar,
    );
    await afterRead();
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlanAvailabilityFixture f;
  late PlanAvailabilityRepository repo;
  final day = PlanAvailabilityFixture.day, now = PlanAvailabilityFixture.now;
  DateTime date(int offset, [int h = 0, int m = 0]) =>
      DateTime(day.year, day.month, day.day + offset, h, m);
  PlanAvailabilityQuery q({
    int before = 0,
    int after = 0,
    String? exclude,
    PlanWeeklyContext? weekly,
    bool appOnly = false,
    DateTime? preparationEnd,
  }) => PlanAvailabilityQuery(
    username: PlanAvailabilityFixture.username,
    todoId: 'todo-target',
    date: day,
    minutes: 75,
    windowStart: 0,
    windowEnd: 1440,
    bufferBefore: before,
    bufferAfter: after,
    excludeBlockId: exclude,
    weekly: weekly,
    appOnly: appOnly,
    preparationEnd: preparationEnd,
  );
  setUp(() async {
    f = PlanAvailabilityFixture();
    await f.initialize();
    repo = PlanAvailabilityRepository(databaseOverride: f.db, clock: () => now);
  });
  tearDown(() async => f.dispose());
  Future<void> noWrites() async {
    expect(await f.db.query('op_logs'), isEmpty);
  }

  test(
    'next seven local days, five diverse complete choices and zero writes',
    () async {
      final r = await repo.readFollowingDays(q());
      expect(r.start, date(1));
      expect(r.end, date(8));
      expect(r.selections.length, 5);
      expect(r.selections.map((s) => s.query.date).toSet().length, 5);
      expect(r.selections.every((s) => s.slot.minutes == 75), isTrue);
      expect(r.currentSnapshot?.todo.id, 'todo-target');
      expect(await f.db.query('todo_plan_blocks'), isEmpty);
      await noWrites();
    },
  );
  test(
    'preparation search includes today and clips the final day to the event',
    () async {
      final boundary = date(2, 10, 0);
      final r = await repo.readPreparationWindow(q(preparationEnd: boundary));
      expect(r.start, date(0));
      expect(r.end, date(3));
      expect(r.selections, isNotEmpty);
      expect(
        r.selections.every((choice) => !choice.slot.end.isAfter(boundary)),
        isTrue,
      );
      expect(
        r.selections.every((choice) => choice.query.preparationEnd == boundary),
        isTrue,
      );
      expect(await f.db.query('todo_plan_blocks'), isEmpty);
      await noWrites();
    },
  );
  test('preparation page ends at the fixed schedule day when it starts at midnight', () async {
    final boundary = date(2);
    final r = await repo.readPreparationWindow(q(preparationEnd: boundary));
    expect(r.end, date(2));
    expect(
      r.selections.every((choice) => choice.slot.end.isBefore(boundary)),
      isTrue,
    );
    await noWrites();
  });
  test('local calendar construction crosses month and year', () async {
    final r = await repo.readFollowingDays(q().onDate(DateTime(2026, 12, 31)));
    expect(r.start, DateTime(2027, 1, 1));
    expect(r.end, DateTime(2027, 1, 8));
    expect(r.selections.map((s) => s.query.date.day), [1, 2, 3, 4, 5]);
  });

  test(
    'calendar reads once, uses boundary buffers, cross-day events excluded',
    () async {
      DeviceCalendarReadService.debugIsSupportedOverride = true;
      await DeviceCalendarReadService.setEnabled(true);
      var reads = 0;
      Map? arguments;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('countdown_todo/device_calendar_read'),
            (call) async {
              if (call.method == 'checkPermission') return true;
              reads++;
              arguments = call.arguments as Map;
              return [
                {
                  'id': 'prior',
                  'startMs': date(0, 22).millisecondsSinceEpoch,
                  'endMs': date(0, 23, 55).millisecondsSinceEpoch,
                  'allDay': false,
                },
                {
                  'id': 'cross-day',
                  'startMs': date(2, 8).millisecondsSinceEpoch,
                  'endMs': date(3, 8).millisecondsSinceEpoch,
                  'allDay': false,
                },
              ];
            },
          );
      final r = await repo.readFollowingDays(q(before: 10, after: 5));
      expect(reads, 1);
      expect(arguments!['startMs'], date(-1, 23, 50).millisecondsSinceEpoch);
      expect(arguments!['endMs'], date(8, 0, 5).millisecondsSinceEpoch);
      expect(r.selections.first.slot.start, date(1, 0, 5));
      expect(r.selections[1].slot.start, date(2));
      expect(
        r.selections.every((s) => s.snapshot.deviceCalendarIncluded),
        isTrue,
      );
      expect(r.currentSnapshot?.deviceCalendarIncluded, isTrue);
      await noWrites();
    },
  );
  test(
    'calendar failure is an error; explicit app-only search remains marked',
    () async {
      DeviceCalendarReadService.debugIsSupportedOverride = true;
      await DeviceCalendarReadService.setEnabled(true);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('countdown_todo/device_calendar_read'),
            (call) async {
              if (call.method == 'checkPermission') return true;
              throw PlatformException(code: 'unavailable');
            },
          );
      await expectLater(
        repo.readFollowingDays(q()),
        throwsA(isA<PlanAvailabilityException>()),
      );
      final r = await repo.readFollowingDays(q(appOnly: true));
      expect(r.coverage, contains('未计入手机日历'));
      expect(r.selections.every((s) => s.query.appOnly), isTrue);
      await noWrites();
    },
  );
  test(
    'deadline clips days and slots, date-only deadline retains its due day',
    () async {
      await f.db.update(
        'todos',
        {'due_date': date(2, 1).millisecondsSinceEpoch},
        where: 'uuid=?',
        whereArgs: ['todo-target'],
      );
      var r = await repo.readFollowingDays(q());
      expect(r.end, date(3));
      expect(
        r.selections.every((s) => !s.slot.end.isAfter(date(2, 1))),
        isTrue,
      );
      await f.db.update(
        'todos',
        {'is_all_day': 1, 'due_date': date(2).millisecondsSinceEpoch},
        where: 'uuid=?',
        whereArgs: ['todo-target'],
      );
      r = await repo.readFollowingDays(q());
      expect(r.selections.any((s) => s.query.date == date(2)), isTrue);
      await noWrites();
    },
  );
  test('expired follow-up deadline does not read calendar', () async {
    await f.db.update(
      'todos',
      {'due_date': date(1).millisecondsSinceEpoch},
      where: 'uuid=?',
      whereArgs: ['todo-target'],
    );
    DeviceCalendarReadService.debugIsSupportedOverride = true;
    await DeviceCalendarReadService.setEnabled(true);
    var reads = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('countdown_todo/device_calendar_read'),
          (_) async {
            reads++;
            return true;
          },
        );
    final r = await repo.readFollowingDays(q());
    expect(r.end, r.start);
    expect(r.selections, isEmpty);
    expect(reads, 0);
  });
  test('deadline changing during source read invalidates the range', () async {
    DeviceCalendarReadService.debugIsSupportedOverride = true;
    await DeviceCalendarReadService.setEnabled(true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('countdown_todo/device_calendar_read'),
          (call) async {
            if (call.method == 'checkPermission') return true;
            await f.db.update(
              'todos',
              {'due_date': date(2, 1).millisecondsSinceEpoch},
              where: 'uuid=?',
              whereArgs: ['todo-target'],
            );
            return [];
          },
        );

    await expectLater(
      repo.readFollowingDays(q()),
      throwsA(
        isA<PlanAvailabilityException>().having(
          (error) => error.message,
          'message',
          contains('待办截止已变化'),
        ),
      ),
    );
    await noWrites();
  });
  test(
    'weekly weekday rules respected and stale preference rejects adoption',
    () async {
      final saved = await PlanWeeklyAvailabilityPreferences.load(
        PlanAvailabilityFixture.username,
      );
      final rules = PlanWeeklyRules(
        enabled: true,
        days: List.generate(
          7,
          (i) => i == 5 || i == 6
              ? <PlanWeeklyWindow>[]
              : [const PlanWeeklyWindow(540, 720)],
        ),
      );
      const identity = PlanTodoIdentity(PlanAvailabilityFixture.username, 0);
      await PlanWeeklyAvailabilityPreferences.save(
        identity,
        rules,
        expectedKey: saved.key,
      );
      final r = await repo.readFollowingDays(
        q(weekly: PlanWeeklyContext(rules)),
      );
      expect(r.selections.every((s) => s.query.date.weekday <= 5), isTrue);
      expect(r.selections.first.slot.start.hour, 9);
      final current = await PlanWeeklyAvailabilityPreferences.load(
        identity.username,
      );
      await PlanWeeklyAvailabilityPreferences.save(
        identity,
        PlanWeeklyRules.initial(),
        expectedKey: current.key,
      );
      await expectLater(
        repo.revalidateContinuous(r.selections.first),
        throwsA(isA<PlanAvailabilityException>()),
      );
      await noWrites();
    },
  );
  test('editing UUID excluded across dates; new occupancy rejects adoption and save', () async {
    final block = TodoPlanBlock(
      id: 'editing',
      todoId: 'todo-target',
      startTime: date(1).millisecondsSinceEpoch,
      endTime: date(2).millisecondsSinceEpoch,
      plannedMinutes: 1440,
    );
    await f.block(block);
    final r = await repo.readFollowingDays(q(exclude: 'editing'));
    expect(r.selections.first.slot.start, date(1));
    await f.fixed('new', date(1), date(1, 2));
    await expectLater(
      repo.revalidateContinuous(r.selections.first),
      throwsA(isA<PlanAvailabilityException>()),
    );
    final choice = r.selections.first;
    await expectLater(
      repo.save(
        choice,
        TodoPlanBlock(
          id: 'attempt',
          todoId: 'todo-target',
          startTime: choice.slot.start.millisecondsSinceEpoch,
          endTime: choice.slot.end.millisecondsSinceEpoch,
          plannedMinutes: 75,
        ),
        sync: false,
      ),
      throwsA(isA<PlanAvailabilityException>()),
    );
    expect(await f.db.query('todo_plan_blocks'), hasLength(1));
    await noWrites();
  });
  test('deadline changed after source read still rejects adoption', () async {
    final choice = (await repo.readFollowingDays(q())).selections.first;
    final changing = _AfterReadRepository(f.db, () async {
      await f.db.update(
        'todos',
        {'due_date': choice.slot.start.millisecondsSinceEpoch},
        where: 'uuid=?',
        whereArgs: ['todo-target'],
      );
    });
    await expectLater(
      changing.revalidateContinuous(choice),
      throwsA(isA<PlanAvailabilityException>()),
    );
    await noWrites();
  });

  test('adoption rechecks completion, account and member identity', () async {
    final choice = (await repo.readFollowingDays(q())).selections.first;
    await f.db.update(
      'todos',
      {'is_completed': 1},
      where: 'uuid=?',
      whereArgs: ['todo-target'],
    );
    await expectLater(
      repo.revalidateContinuous(choice),
      throwsA(isA<PlanAvailabilityException>()),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_login_user', 'other');
    await expectLater(
      repo.readFollowingDays(q()),
      throwsA(isA<PlanAvailabilityException>()),
    );
    await noWrites();
  });
  test(
    'successful explicit save writes exactly one planning block and oplog',
    () async {
      final choice = await repo.revalidateContinuous(
        (await repo.readFollowingDays(q())).selections.first,
      );
      final saved = await repo.save(
        choice,
        TodoPlanBlock(
          id: 'accepted',
          todoId: 'todo-target',
          startTime: choice.slot.start.millisecondsSinceEpoch,
          endTime: choice.slot.end.millisecondsSinceEpoch,
          plannedMinutes: 75,
        ),
        sync: false,
      );
      expect(saved.startTime, choice.slot.start.millisecondsSinceEpoch);
      expect(await f.db.query('todo_plan_blocks'), hasLength(1));
      expect(await f.db.query('op_logs'), hasLength(1));
      expect(
        PlanAvailabilityService.accepts(choice, choice.snapshot, now: now),
        isTrue,
      );
    },
  );
}
