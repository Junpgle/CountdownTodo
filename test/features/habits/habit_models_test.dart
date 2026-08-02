import 'package:countdown_todo/features/habits/models/habit_checkin.dart';
import 'package:countdown_todo/features/habits/models/habit_goal.dart';
import 'package:countdown_todo/features/habits/models/habit_goal_rule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HabitGoal 模型', () {
    test('toJson/fromJson 往返一致', () {
      final goal = HabitGoal(
        uuid: '11111111-1111-1111-1111-111111111111',
        name: '每天喝水',
        icon: '💧',
        sourceType: HabitSourceType.quantityCheckIn,
        sourceIds: const ['a', 'b'],
        currentRuleUuid: '22222222-2222-2222-2222-222222222222',
        displayMode: HabitDisplayMode.habitOnly,
        sortOrder: 3,
        createdAt: 1000,
        updatedAt: 2000,
      );
      final json = goal.toJson();
      expect(json['source_type'], 2);
      expect(json['source_ids'], '["a","b"]');
      final restored = HabitGoal.fromJson(json);
      expect(restored.uuid, goal.uuid);
      expect(restored.name, '每天喝水');
      expect(restored.sourceType, HabitSourceType.quantityCheckIn);
      expect(restored.sourceIds, ['a', 'b']);
      expect(restored.sortOrder, 3);
      expect(restored.createdAt, 1000);
      expect(restored.updatedAt, 2000);
    });

    test('source_ids 兼容 List 与 JSON 字符串', () {
      final fromList = HabitGoal.fromJson({
        'uuid': 'x',
        'source_ids': ['a']
      });
      expect(fromList.sourceIds, ['a']);
      final fromString =
          HabitGoal.fromJson({'uuid': 'x', 'source_ids': '["a","b"]'});
      expect(fromString.sourceIds, ['a', 'b']);
      final missing = HabitGoal.fromJson({'uuid': 'x'});
      expect(missing.sourceIds, isEmpty);
    });

    test('markAsChanged 递增版本号', () {
      final goal = HabitGoal(uuid: 'x', name: 't');
      final v = goal.version;
      goal.markAsChanged();
      expect(goal.version, v + 1);
    });

    test('defaultFocusMinutes 可空往返', () {
      final goal = HabitGoal(
        uuid: '11111111-1111-1111-1111-111111111111',
        name: '阅读',
        sourceType: HabitSourceType.pomodoroTag,
        defaultFocusMinutes: 45,
      );
      final restored = HabitGoal.fromJson(goal.toJson());
      expect(restored.defaultFocusMinutes, 45);

      final empty = HabitGoal(uuid: 'x', name: 'y');
      expect(empty.defaultFocusMinutes, null);
      expect(
        HabitGoal.fromJson(empty.toJson()).defaultFocusMinutes,
        null,
      );
    });
  });

  group('HabitGoalRuleRevision 模型', () {
    test('toJson/fromJson 往返一致', () {
      final rule = HabitGoalRuleRevision(
        uuid: '33333333-3333-3333-3333-333333333333',
        habitUuid: 'h1',
        effectiveFromDate: '2026-08-01',
        effectiveToDate: '2026-08-31',
        periodType: HabitPeriodType.weekdays,
        weekdaysMask: 31,
        targetValue: 30,
        unit: 'ml',
        targetTimeMinute: 7 * 60 + 30,
        timeComparison: HabitTimeComparison.before,
        timeToleranceMinutes: 15,
        dayBoundaryMinute: 4 * 60,
        quickValues: const [200, 250, 300],
        reminderPolicy: const HabitReminderPolicy(
          fixedTimes: [600, 1080],
          progressReminder: true,
        ),
        createdAt: 1000,
        updatedAt: 2000,
      );
      final restored = HabitGoalRuleRevision.fromJson(rule.toJson());
      expect(restored.uuid, rule.uuid);
      expect(restored.periodType, HabitPeriodType.weekdays);
      expect(restored.weekdaysMask, 31);
      expect(restored.targetValue, 30);
      expect(restored.targetTimeMinute, 7 * 60 + 30);
      expect(restored.timeToleranceMinutes, 15);
      expect(restored.dayBoundaryMinute, 4 * 60);
      expect(restored.quickValues, [200, 250, 300]);
      expect(restored.reminderPolicy.fixedTimes, [600, 1080]);
      expect(restored.reminderPolicy.progressReminder, true);
      expect(restored.reminderPolicy.nearEndReminder, false);
    });

    test('同步字段（deviceId / hasConflict / conflictData）往返一致', () {
      final rule = HabitGoalRuleRevision(
        uuid: '33333333-3333-3333-3333-333333333334',
        habitUuid: 'h1',
        deviceId: 'device_b',
        createdAt: 1000,
        updatedAt: 2000,
        hasConflict: true,
        conflictData: {'uuid': 'rule-x', 'version': 1, 'target_value': 250},
      );
      final json = rule.toJson();
      expect(json['device_id'], 'device_b');
      expect(json['has_conflict'], 1);
      expect(json['conflict_data'], isA<String>());

      final restored = HabitGoalRuleRevision.fromJson(json);
      expect(restored.deviceId, 'device_b');
      expect(restored.hasConflict, true);
      expect(restored.conflictData?['target_value'], 250);

      final fromString = HabitGoalRuleRevision.fromJson({
        'uuid': 'x',
        'has_conflict': true,
        'conflict_data': '{"version":2}',
      });
      expect(fromString.hasConflict, true);
      expect(fromString.conflictData?['version'], 2);
    });

    test('coversDate 判断生效范围', () {
      final rule = HabitGoalRuleRevision(
        habitUuid: 'h1',
        effectiveFromDate: '2026-08-01',
        effectiveToDate: '2026-08-31',
      );
      expect(rule.coversDate('2026-08-15'), true);
      expect(rule.coversDate('2026-07-31'), false);
      expect(rule.coversDate('2026-09-01'), false);
      final open = HabitGoalRuleRevision(
        habitUuid: 'h1',
        effectiveFromDate: '2026-08-01',
      );
      expect(open.coversDate('2027-01-01'), true);
    });
  });

  group('HabitCheckIn 模型', () {
    test('toJson/fromJson 往返一致', () {
      final checkIn = HabitCheckIn(
        uuid: '44444444-4444-4444-4444-444444444444',
        habitUuid: 'h1',
        ruleRevisionUuid: 'r1',
        occurredAt: 1722841200000,
        logicalDate: '2026-08-05',
        timezoneOffsetMinutes: 480,
        value: 250,
        note: '早上的水',
        source: HabitCheckInSource.widget,
        dedupeKey: 'habit-checkin/h1/notif',
        createdAt: 1000,
        updatedAt: 2000,
      );
      final restored = HabitCheckIn.fromJson(checkIn.toJson());
      expect(restored.uuid, checkIn.uuid);
      expect(restored.logicalDate, '2026-08-05');
      expect(restored.timezoneOffsetMinutes, 480);
      expect(restored.value, 250);
      expect(restored.note, '早上的水');
      expect(restored.source, HabitCheckInSource.widget);
      expect(restored.dedupeKey, 'habit-checkin/h1/notif');
    });

    test('localOccurredAt 还原时区', () {
      final checkIn = HabitCheckIn(
        habitUuid: 'h1',
        occurredAt: DateTime.utc(2026, 8, 5, 1, 30).millisecondsSinceEpoch,
        logicalDate: '2026-08-05',
        timezoneOffsetMinutes: 480,
      );
      final local = checkIn.localOccurredAt;
      expect(local.hour, 9);
      expect(local.minute, 30);
    });

    test('未知 source 回退为 manual', () {
      final checkIn = HabitCheckIn.fromJson(
          {'uuid': 'x', 'habit_uuid': 'h', 'source': 'unknown_xyz'});
      expect(checkIn.source, HabitCheckInSource.manual);
    });
  });
}
