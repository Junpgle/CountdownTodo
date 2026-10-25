@TestOn('vm')
library;

import 'dart:convert';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/services/fixed_schedule_preparation_guard.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/plan_availability_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlanAvailabilityFixture fixture;
  late DateTime startsAt;
  late FixedSchedulePreparationContext context;

  setUp(() async {
    fixture = PlanAvailabilityFixture();
    await fixture.initialize();
    startsAt = PlanAvailabilityFixture.day.add(
      const Duration(days: 2, hours: 10),
    );
    context = FixedSchedulePreparationContext(
      scheduleId: 'preparation-occurrence',
      startTime: startsAt.millisecondsSinceEpoch,
    );
    await fixture.db.insert(
      'fixed_schedules',
      FixedScheduleItem(
        id: context.scheduleId,
        title: '考试',
        date: '2026-10-10',
        startTime: startsAt.millisecondsSinceEpoch,
        endTime: startsAt.add(const Duration(hours: 2)).millisecondsSinceEpoch,
        relatedTodoIds: const ['todo-target'],
      ).toJson(),
    );
  });

  tearDown(() async => fixture.dispose());

  test(
    'accepts the same upcoming occurrence while its todo relationship remains',
    () async {
      await expectLater(
        FixedSchedulePreparationGuard.validate(
          fixture.db,
          context,
          'todo-target',
          now: PlanAvailabilityFixture.now,
        ),
        completes,
      );
    },
  );

  test('rejects a rescheduled occurrence at the write boundary', () async {
    await fixture.db.update(
      'fixed_schedules',
      {
        'start_time': startsAt
            .add(const Duration(hours: 1))
            .millisecondsSinceEpoch,
      },
      where: 'uuid=?',
      whereArgs: [context.scheduleId],
    );
    await expectLater(
      FixedSchedulePreparationGuard.validate(
        fixture.db,
        context,
        'todo-target',
        now: PlanAvailabilityFixture.now,
      ),
      throwsA(isA<PlanAvailabilityException>()),
    );
  });

  test('rejects an occurrence that has already started', () async {
    await expectLater(
      FixedSchedulePreparationGuard.validate(
        fixture.db,
        context,
        'todo-target',
        now: startsAt,
      ),
      throwsA(isA<PlanAvailabilityException>()),
    );
  });

  test('rejects a cancelled or unlinked occurrence', () async {
    await fixture.db.update(
      'fixed_schedules',
      {'status': FixedScheduleStatus.cancelled.index},
      where: 'uuid=?',
      whereArgs: [context.scheduleId],
    );
    await expectLater(
      FixedSchedulePreparationGuard.validate(
        fixture.db,
        context,
        'todo-target',
        now: PlanAvailabilityFixture.now,
      ),
      throwsA(isA<PlanAvailabilityException>()),
    );
    await fixture.db.update(
      'fixed_schedules',
      {
        'status': FixedScheduleStatus.scheduled.index,
        'related_todo_ids': jsonEncode(<String>[]),
      },
      where: 'uuid=?',
      whereArgs: [context.scheduleId],
    );
    await expectLater(
      FixedSchedulePreparationGuard.validate(
        fixture.db,
        context,
        'todo-target',
        now: PlanAvailabilityFixture.now,
      ),
      throwsA(isA<PlanAvailabilityException>()),
    );
  });
}
