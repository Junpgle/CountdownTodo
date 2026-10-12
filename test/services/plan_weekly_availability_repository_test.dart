@TestOn('vm')
library;

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/models/plan_split.dart';
import 'package:countdown_todo/models/plan_weekly_availability.dart';
import 'package:countdown_todo/services/plan_weekly_availability_preferences.dart';
import 'package:countdown_todo/services/plan_availability_repository.dart';
import 'package:countdown_todo/services/plan_availability_service.dart';
import 'package:countdown_todo/services/plan_split_service.dart';
import 'package:countdown_todo/services/plan_todo_guard.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/plan_availability_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlanAvailabilityFixture f;
  late PlanAvailabilityRepository repo;
  const identity = PlanTodoIdentity(PlanAvailabilityFixture.username, 0);
  final day = PlanAvailabilityFixture.day, now = PlanAvailabilityFixture.now;
  setUp(() async {
    f = PlanAvailabilityFixture();
    await f.initialize();
    repo = PlanAvailabilityRepository(databaseOverride: f.db, clock: () => now);
  });
  tearDown(() async => f.dispose());
  Future<PlanWeeklyRules> install({bool empty = false}) async {
    final loaded = await PlanWeeklyAvailabilityPreferences.load(
      identity.username,
    );
    final rules = PlanWeeklyRules(
      enabled: true,
      days: List.generate(
        7,
        (_) =>
            empty ? <PlanWeeklyWindow>[] : [const PlanWeeklyWindow(540, 720)],
      ),
    );
    await PlanWeeklyAvailabilityPreferences.save(
      identity,
      rules,
      expectedKey: loaded.key,
    );
    return rules;
  }

  PlanAvailabilityQuery q(
    PlanWeeklyRules rules, {
    int minutes = 60,
    bool ignored = false,
  }) => PlanAvailabilityQuery(
    username: identity.username,
    todoId: 'todo-target',
    date: day,
    minutes: minutes,
    weekly: PlanWeeklyContext(rules, ignored: ignored),
  );
  TodoPlanBlock block(String id, PlanTimeSlot slot) => TodoPlanBlock(
    id: id,
    todoId: 'todo-target',
    startTime: slot.start.millisecondsSinceEpoch,
    endTime: slot.end.millisecondsSinceEpoch,
    plannedMinutes: slot.minutes,
  );
  Future<void> emptyWrites() async {
    expect(await f.db.query('todo_plan_blocks'), isEmpty);
    expect(await f.db.query('op_logs'), isEmpty);
  }

  test('single save rejects policy changed after recommendation with no business writes', () async {
    final rules = await install(), query = q(await install());
    final s = await repo.read(query),
        slot = PlanAvailabilityService.find(
          query,
          await repo.read(query),
          now: now,
        ).slots.first;
    await install(empty: true);
    await expectLater(
      repo.save(
        PlanAvailabilitySelection(query, slot, s),
        block('single', slot),
        sync: false,
      ),
      throwsA(isA<PlanAvailabilityException>()),
    );
    expect(rules.enabled, isTrue);
    await emptyWrites();
  });
  test('single write guard rechecks after callback changes policy', () async {
    final query = q(await install()), s = await repo.read(q(await install()));
    final slot = PlanAvailabilityService.find(query, s, now: now).slots.first;
    await expectLater(
      repo.save(
        PlanAvailabilitySelection(query, slot, s),
        block('single', slot),
        sync: false,
        beforeWrite: (_) async {
          await install(empty: true);
        },
      ),
      throwsA(isA<PlanAvailabilityException>()),
    );
    await emptyWrites();
  });
  test(
    'split write guard rejects whole group after callback changes policy',
    () async {
      final query = PlanSplitQuery(q(await install(), minutes: 90)),
          s = await repo.readSplit(
            PlanSplitQuery(q(await install(), minutes: 90)),
          );
      final slots = PlanSplitService.find(query, s, now: now).groups.first;
      await expectLater(
        repo.saveSplit(
          PlanSplitSelection(query, slots, s),
          [for (var i = 0; i < slots.length; i++) block('part-$i', slots[i])],
          sync: false,
          beforeWrite: (_) async {
            await install(empty: true);
          },
        ),
        throwsA(isA<PlanAvailabilityException>()),
      );
      await emptyWrites();
    },
  );
  test(
    'unchanged policy saves one group and emits one oplog per segment',
    () async {
      final query = PlanSplitQuery(q(await install(), minutes: 90)),
          s = await repo.readSplit(
            PlanSplitQuery(q(await install(), minutes: 90)),
          );
      final slots = PlanSplitService.find(query, s, now: now).groups.first;
      final saved = await repo.saveSplit(PlanSplitSelection(query, slots, s), [
        for (var i = 0; i < slots.length; i++) block('part-$i', slots[i]),
      ], sync: false);
      expect(saved.length, slots.length);
      expect((await f.db.query('op_logs')).length, slots.length);
    },
  );
  test('manual times outside weekly policy save; explicit exemption still rejects new occupancy', () async {
    final rules = await install(empty: true);
    final manual = q(rules).withWeekly(null),
        s = await repo.read(q(rules).withWeekly(null));
    final slot = PlanTimeSlot(
      DateTime(day.year, day.month, day.day, 18),
      DateTime(day.year, day.month, day.day, 19),
    );
    await repo.save(
      PlanAvailabilitySelection(manual, slot, s),
      block('manual', slot),
      sync: false,
    );
    final exempt = q(rules, ignored: true);
    await expectLater(
      repo.save(
        PlanAvailabilitySelection(exempt, slot, s),
        block('exempt', slot),
        sync: false,
      ),
      throwsA(isA<PlanAvailabilityException>()),
    );
    expect((await f.db.query('todo_plan_blocks')).length, 1);
  });
}
