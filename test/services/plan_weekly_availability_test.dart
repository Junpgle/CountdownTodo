@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/models/plan_weekly_availability.dart';
import 'package:countdown_todo/models/plan_split.dart';
import 'package:countdown_todo/services/plan_availability_service.dart';
import 'package:countdown_todo/services/plan_split_service.dart';
import 'package:countdown_todo/services/plan_weekly_availability_preferences.dart';
import 'package:countdown_todo/services/plan_todo_guard.dart';
import 'package:countdown_todo/services/plan_editor_draft_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

PlanWeeklyRules rules(List<PlanWeeklyWindow> windows, {bool enabled = true}) =>
    PlanWeeklyRules(enabled: enabled, days: List.generate(7, (_) => windows));
final day = DateTime(2026, 10, 12), now = DateTime(2026, 10, 11);
DateTime at(int hour, [int minute = 0]) => DateTime(2026, 10, 12, hour, minute);
PlanAvailabilityQuery query(
  PlanWeeklyContext? weekly, {
  int minutes = 60,
  DateTime? date,
  int before = 0,
  int after = 0,
  List<PlanDailyTimeWindow> avoid = const [],
}) => PlanAvailabilityQuery(
  username: 'weekly',
  todoId: 'target',
  date: date ?? day,
  minutes: minutes,
  windowStart: 0,
  windowEnd: 1440,
  weekly: weekly,
  bufferBefore: before,
  bufferAfter: after,
  avoidWindows: avoid,
);
PlanAvailabilitySnapshot snapshot({
  List<PlanBusyInterval> busy = const [],
  TodoItem? todo,
}) => PlanAvailabilitySnapshot(
  todo: todo ?? TodoItem(id: 'target', title: 'test'),
  busy: busy,
  coverage: 'synthetic',
);

class FailingStore extends InMemorySharedPreferencesStore {
  FailingStore() : super.withData({'flutter.current_login_user': 'weekly'});
  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'current_login_user': 'weekly',
    }),
  );
  test('initial policy is disabled and every day all day', () {
    final r = PlanWeeklyRules.initial();
    expect(r.enabled, isFalse);
    expect(r.days.length, 7);
    expect(List.generate(7, (i) => r.summary(i + 1)), List.filled(7, '全天'));
  });
  test(
    'sort, merge overlap and adjacency; immutable input and stable fingerprint',
    () {
      final input = [
        const PlanWeeklyWindow(840, 1080),
        const PlanWeeklyWindow(600, 720),
        const PlanWeeklyWindow(540, 600),
        const PlanWeeklyWindow(900, 1140),
      ];
      final r = rules(input);
      input.clear();
      expect(r.days.first.map((w) => w.label), ['09:00–12:00', '14:00–19:00']);
      expect(() => r.days.first.clear(), throwsUnsupportedError);
      expect(
        PlanWeeklyRules.fromJson(jsonDecode(r.fingerprint)).fingerprint,
        r.fingerprint,
      );
    },
  );
  test(
    'strict day count, four windows, integer bounds and unsupported formats',
    () {
      for (final w in [
        const PlanWeeklyWindow(-1, 60),
        const PlanWeeklyWindow(1440, 1440),
        const PlanWeeklyWindow(120, 60),
        const PlanWeeklyWindow(0, 1441),
      ]) {
        expect(() => rules([w]), throwsFormatException);
      }
      expect(
        () => rules(List.filled(5, const PlanWeeklyWindow(0, 1))),
        throwsFormatException,
      );
      for (final json in [
        null,
        {},
        {'version': 2, 'enabled': false, 'days': List.filled(7, [])},
        {'version': 1, 'enabled': true, 'days': List.filled(6, [])},
        {
          'version': 1,
          'enabled': true,
          'days': List.filled(7, [
            [1.5, 60],
          ]),
        },
      ]) {
        expect(() => PlanWeeklyRules.fromJson(json), throwsFormatException);
      }
    },
  );
  test('disabled and manual calculation retain full query range; explicit exemption only weekly', () {
    for (final c in [
      null,
      PlanWeeklyContext(rules([], enabled: false)),
      PlanWeeklyContext(rules([]), ignored: true),
    ]) {
      final q = query(c);
      expect(
        PlanAvailabilityService.find(q, snapshot(), now: now).slots.length,
        5,
      );
    }
    final q = query(
      PlanWeeklyContext(rules([]), ignored: true),
      before: 10,
      avoid: [const PlanDailyTimeWindow('rest', 0, 120)],
    );
    final s = snapshot(
      busy: [PlanBusyInterval(at(2), at(3), source: PlanBusySource.course)],
    );
    expect(
      PlanAvailabilityService.find(q, s, now: now).slots.first.start,
      at(3, 10),
    );
  });
  test(
    'single recommendation stays inside one allowed range, never bridges lunch',
    () {
      final q = query(
        PlanWeeklyContext(
          rules([
            const PlanWeeklyWindow(540, 720),
            const PlanWeeklyWindow(840, 960),
          ]),
        ),
      );
      final s = snapshot(), r = PlanAvailabilityService.find(q, s, now: now);
      expect(r.slots.map((w) => w.start.hour), [9, 10, 11, 14, 15]);
      expect(
        r.slots.every(
          (w) => PlanAvailabilityService.accepts(
            PlanAvailabilitySelection(q, w, s),
            s,
            now: now,
          ),
        ),
        isTrue,
      );
      expect(
        PlanAvailabilityService.accepts(
          PlanAvailabilitySelection(q, PlanTimeSlot(at(11, 30), at(12, 30)), s),
          s,
          now: now,
        ),
        isFalse,
      );
    },
  );
  test(
    'weekly boundary adds no buffer; busy/avoidance/now/deadline still clip',
    () {
      final c = PlanWeeklyContext(rules([const PlanWeeklyWindow(540, 720)]));
      final q = query(c, before: 15, after: 10, minutes: 30);
      expect(
        PlanAvailabilityService.find(q, snapshot(), now: now).slots.first.start,
        at(9),
      );
      final s = snapshot(
        busy: [
          PlanBusyInterval(at(8), at(9), source: PlanBusySource.fixedSchedule),
        ],
        todo: TodoItem(id: 'target', title: 'test', dueDate: at(10, 40)),
      );
      final r = PlanAvailabilityService.find(
        q,
        s,
        now: at(9, 20).add(const Duration(seconds: 1)),
      );
      expect(r.slots.first.start, at(9, 21));
      expect(r.slots.last.end.isAfter(at(10, 40)), isFalse);
      expect(
        PlanAvailabilityService.find(
          query(c, avoid: [const PlanDailyTimeWindow('rest', 540, 660)]),
          s,
          now: now,
        ).slots,
        isEmpty,
      );
    },
  );
  test(
    'empty weekday has a specific message; query intersection does not expand',
    () {
      final q = query(PlanWeeklyContext(rules([])));
      expect(
        PlanAvailabilityService.find(q, snapshot(), now: now).message,
        '周一未设置可安排时间',
      );
      final r = rules([const PlanWeeklyWindow(0, 60)]);
      final limited = PlanAvailabilityQuery(
        username: 'weekly',
        todoId: 'target',
        date: day,
        minutes: 30,
        weekly: PlanWeeklyContext(r),
      );
      expect(
        PlanAvailabilityService.find(limited, snapshot(), now: now).slots,
        isEmpty,
      );
    },
  );
  test('end 24:00 is next local midnight; DST gap and fold are rejected', () {
    expect(PlanWeeklyRules.boundary(day, 1440), DateTime(2026, 10, 13));
    if (Platform.environment['TZ'] == 'Australia/Lord_Howe') {
      expect(
        () => PlanWeeklyRules.boundary(DateTime(2026, 10, 4), 135),
        throwsFormatException,
      );
      expect(
        () => PlanWeeklyRules.boundary(DateTime(2026, 4, 5), 105),
        throwsFormatException,
      );
      final transition = DateTime(2026, 10, 4);
      final timed = query(
        PlanWeeklyContext(rules([const PlanWeeklyWindow(60, 240)])),
        date: transition,
        minutes: 150,
      );
      final result = PlanAvailabilityService.find(
        timed,
        snapshot(),
        now: DateTime(2026, 10, 3),
      );
      expect(result.slots.single.minutes, 150);
      expect(result.slots.single.end.hour, 4);
    }
    if (Platform.environment['TZ'] == 'America/New_York') {
      expect(
        () => PlanWeeklyRules.boundary(DateTime(2026, 3, 8), 150),
        throwsFormatException,
      );
      expect(
        () => PlanWeeklyRules.boundary(DateTime(2026, 11, 1), 90),
        throwsFormatException,
      );
      expect(PlanWeeklyRules.boundary(DateTime(2026, 3, 8), 180).hour, 3);
      final transition = DateTime(2026, 3, 8);
      final timed = query(
        PlanWeeklyContext(rules([const PlanWeeklyWindow(60, 240)])),
        date: transition,
        minutes: 120,
      );
      final result = PlanAvailabilityService.find(
        timed,
        snapshot(),
        now: DateTime(2026, 3, 7),
      );
      expect(result.slots.single.minutes, 120);
      expect(result.slots.single.end.hour, 4);

      final q = query(
        PlanWeeklyContext(rules([const PlanWeeklyWindow(90, 150)])),
        date: DateTime(2026, 11, 1),
      );
      expect(
        PlanAvailabilityService.invalidReason(
          q,
          snapshot().todo,
          DateTime(2026, 10, 31),
        ),
        contains('夏令时'),
      );
    }
  });
  test(
    'split follows each weekday, skips excluded day and preserves total',
    () {
      final days = List.generate(7, (_) => <PlanWeeklyWindow>[]);
      days[0] = [const PlanWeeklyWindow(540, 600)];
      days[2] = [const PlanWeeklyWindow(840, 900)];
      final q = PlanSplitQuery(
        query(
          PlanWeeklyContext(PlanWeeklyRules(enabled: true, days: days)),
          minutes: 120,
        ),
        days: 3,
        maximum: 60,
      );
      final s = PlanSplitSnapshot(List.generate(3, (_) => snapshot()));
      final r = PlanSplitService.find(q, s, now: now);
      expect(r.groups, isNotEmpty);
      expect(r.groups.first.map((w) => w.start.weekday), [1, 3]);
      expect(r.groups.first.fold<int>(0, (n, w) => n + w.minutes), 120);
      expect(PlanSplitService.accepts(q, r.groups.first, s, now: now), isTrue);
    },
  );
  test(
    'account settings use one separate JSON and reject stale editors',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('plan_availability_buffers_weekly', 'untouched');
      final old = await PlanWeeklyAvailabilityPreferences.load('weekly');
      const identity = PlanTodoIdentity('weekly', 0);
      await PlanWeeklyAvailabilityPreferences.save(
        identity,
        rules([]),
        expectedKey: old.key,
      );
      await expectLater(
        PlanWeeklyAvailabilityPreferences.save(
          identity,
          rules([const PlanWeeklyWindow(0, 60)]),
          expectedKey: old.key,
        ),
        throwsA(isA<PlanAvailabilityException>()),
      );
      expect(
        (await PlanWeeklyAvailabilityPreferences.load('weekly'))
            .rules!
            .days
            .first,
        isEmpty,
      );
      expect(
        (await PlanWeeklyAvailabilityPreferences.load('other')).rules!.enabled,
        isFalse,
      );
      expect(prefs.getString('plan_availability_buffers_weekly'), 'untouched');
    },
  );
  test(
    'identity changes cannot write; failed writes do not poison queue',
    () async {
      final old = await PlanWeeklyAvailabilityPreferences.load('weekly');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('current_user_id', 2);
      await expectLater(
        PlanWeeklyAvailabilityPreferences.save(
          const PlanTodoIdentity('weekly', 0),
          rules([]),
          expectedKey: old.key,
        ),
        throwsA(isA<PlanAvailabilityException>()),
      );
      await prefs.setInt('current_user_id', 0);
      await PlanWeeklyAvailabilityPreferences.save(
        const PlanTodoIdentity('weekly', 0),
        rules([]),
        expectedKey: old.key,
      );
      expect(
        (await PlanWeeklyAvailabilityPreferences.load('weekly')).rules!.enabled,
        isTrue,
      );
    },
  );
  test(
    'read corruption is explicit, reset requires captured raw state',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        PlanWeeklyAvailabilityPreferences.storageKey('weekly'),
        '{',
      );
      final bad = await PlanWeeklyAvailabilityPreferences.load('weekly');
      expect(bad.rules, isNull);
      expect(bad.error, isNotNull);
      await PlanWeeklyAvailabilityPreferences.save(
        const PlanTodoIdentity('weekly', 0),
        PlanWeeklyRules.initial(),
        expectedKey: bad.key,
      );
      expect(
        (await PlanWeeklyAvailabilityPreferences.load('weekly')).error,
        isNull,
      );
    },
  );
  test(
    'false preference write reports failure and does not announce revision',
    () async {
      SharedPreferencesStorePlatform.instance = FailingStore();
      SharedPreferences.resetStatic();
      final old = await PlanWeeklyAvailabilityPreferences.load('weekly'),
          revision = PlanWeeklyAvailabilityPreferences.revision.value;
      await expectLater(
        PlanWeeklyAvailabilityPreferences.save(
          const PlanTodoIdentity('weekly', 0),
          rules([]),
          expectedKey: old.key,
        ),
        throwsA(isA<PlanAvailabilityException>()),
      );
      expect(PlanWeeklyAvailabilityPreferences.revision.value, revision);
      expect(
        (await PlanWeeklyAvailabilityPreferences.load('weekly')).rules!.enabled,
        isFalse,
      );
    },
  );
  test('recommended query rejects changed policy, manual and explicit weekly exemption stay selective', () async {
    final old = await PlanWeeklyAvailabilityPreferences.load('weekly');
    final q = query(PlanWeeklyContext(old.rules));
    await PlanWeeklyAvailabilityPreferences.validateQuery(q);
    await PlanWeeklyAvailabilityPreferences.save(
      const PlanTodoIdentity('weekly', 0),
      rules([]),
      expectedKey: old.key,
    );
    await expectLater(
      PlanWeeklyAvailabilityPreferences.validateQuery(q),
      throwsA(isA<PlanAvailabilityException>()),
    );
    await PlanWeeklyAvailabilityPreferences.validateQuery(q.withWeekly(null));
    await PlanWeeklyAvailabilityPreferences.validateQuery(
      q.withWeekly(const PlanWeeklyContext(null, ignored: true)),
    );
  });
  test(
    'old and new draft metadata round-trip without restoring global settings',
    () {
      final f = PlanDraftFields(
        todoId: 'target',
        title: 'test',
        start: at(9).millisecondsSinceEpoch,
        end: at(10).millisecondsSinceEpoch,
        remark: 'keep',
        reminder: 5,
        pomodoro: 25,
        rounds: 2,
        origin: 'todo',
        offsetMinutes: 0,
        scheduleOrigin: 'recommended',
        weeklyKey: rules([]).fingerprint,
        weeklyIgnored: true,
      );
      final json = f.toJson(), restored = PlanDraftFields.fromJson(json);
      expect(restored.scheduleOrigin, 'recommended');
      expect(restored.weeklyIgnored, isTrue);
      expect(restored.weeklyKey, f.weeklyKey);
      json.remove('scheduleOrigin');
      json.remove('weeklyKey');
      json.remove('weeklyIgnored');
      expect(PlanDraftFields.fromJson(json).scheduleOrigin, 'legacy');
      json['weeklyIgnored'] = 'true';
      expect(() => PlanDraftFields.fromJson(json), throwsFormatException);
    },
  );
}
