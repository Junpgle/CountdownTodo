import 'package:flutter_test/flutter_test.dart';

import 'package:countdown_todo/features/habits/models/habit_goal.dart';
import 'package:countdown_todo/features/habits/services/habit_sleep_log_migration_service.dart';
import 'package:countdown_todo/models.dart';

TimeLogItem _sleepLog({
  required DateTime start,
  required DateTime end,
  String title = '睡眠',
  List<String> tagUuids = const [],
}) {
  return TimeLogItem(
    title: title,
    tagUuids: tagUuids,
    startTime: start.millisecondsSinceEpoch,
    endTime: end.millisecondsSinceEpoch,
  );
}

void main() {
  test('从跨午夜睡眠日志推导中位早睡和早起时间', () {
    final proposal = HabitSleepLogMigrationService.buildProposal(
      now: DateTime(2026, 8, 4, 12),
      logs: [
        _sleepLog(
          start: DateTime(2026, 8, 1, 23, 30),
          end: DateTime(2026, 8, 2, 7),
        ),
        _sleepLog(
          start: DateTime(2026, 8, 2, 23),
          end: DateTime(2026, 8, 3, 6, 30),
        ),
        _sleepLog(
          start: DateTime(2026, 8, 3, 23, 45),
          end: DateTime(2026, 8, 4, 7, 30),
        ),
      ],
    );

    expect(proposal, isNotNull);
    expect(proposal!.observedNights, 3);
    expect(proposal.bedtimeMinute, 1410);
    expect(proposal.wakeMinute, 420);
    expect(proposal.medianSleepMinutes, 450);
    expect(proposal.sleepDurationLabel, '7 小时 30 分钟');
    expect(proposal.createsEarlySleep, isTrue);
    expect(proposal.createsEarlyWake, isTrue);
  });

  test('按标签识别睡眠，排除午休和同一晚较短重复记录', () {
    final proposal = HabitSleepLogMigrationService.buildProposal(
      now: DateTime(2026, 8, 4, 12),
      tagNames: const {'sleep-tag': '夜间作息'},
      logs: [
        _sleepLog(
          title: '日常',
          tagUuids: const ['sleep-tag'],
          start: DateTime(2026, 8, 1, 23),
          end: DateTime(2026, 8, 2, 6),
        ),
        _sleepLog(
          title: '睡眠分段',
          start: DateTime(2026, 8, 1, 23, 30),
          end: DateTime(2026, 8, 2, 2),
        ),
        _sleepLog(
          title: '午休',
          start: DateTime(2026, 8, 2, 13),
          end: DateTime(2026, 8, 2, 15),
        ),
        _sleepLog(
          title: '夜间睡觉',
          start: DateTime(2026, 8, 2, 22, 30),
          end: DateTime(2026, 8, 3, 6, 30),
        ),
      ],
    );

    expect(proposal, isNotNull);
    expect(proposal!.observedNights, 2);
    expect(proposal.matchedLogs, hasLength(2));
    expect(proposal.bedtimeMinute, 1365);
    expect(proposal.wakeMinute, 375);
  });

  test('已有早睡或早起时只建议创建缺少的习惯', () {
    final proposal = HabitSleepLogMigrationService.buildProposal(
      now: DateTime(2026, 8, 4, 12),
      existingGoals: [
        HabitGoal(name: '我的睡眠', sourceType: HabitSourceType.timeCheckIn),
      ],
      logs: [
        _sleepLog(
          start: DateTime(2026, 8, 1, 23),
          end: DateTime(2026, 8, 2, 7),
        ),
        _sleepLog(
          start: DateTime(2026, 8, 2, 23),
          end: DateTime(2026, 8, 3, 7),
        ),
      ],
    );

    expect(proposal, isNotNull);
    expect(proposal!.hasEarlySleep, isTrue);
    expect(proposal.hasEarlyWake, isFalse);
    expect(proposal.createsEarlySleep, isFalse);
    expect(proposal.createsEarlyWake, isTrue);
  });

  test('合并命名的早睡早起习惯不会被重复拆建但仍可导入历史', () {
    final proposal = HabitSleepLogMigrationService.buildProposal(
      now: DateTime(2026, 8, 4, 12),
      existingGoals: [
        HabitGoal(name: '早睡早起', sourceType: HabitSourceType.timeCheckIn),
      ],
      logs: [
        _sleepLog(
          start: DateTime(2026, 8, 1, 23),
          end: DateTime(2026, 8, 2, 7),
        ),
        _sleepLog(
          start: DateTime(2026, 8, 2, 23),
          end: DateTime(2026, 8, 3, 7),
        ),
      ],
    );

    expect(proposal, isNotNull);
    expect(proposal!.createsEarlySleep, isFalse);
    expect(proposal.createsEarlyWake, isFalse);
    expect(proposal.canMigrate, isTrue);
  });

  test('少于两晚有效记录时不主动提示迁移', () {
    final proposal = HabitSleepLogMigrationService.buildProposal(
      now: DateTime(2026, 8, 4, 12),
      logs: [
        _sleepLog(
          start: DateTime(2026, 8, 3, 23),
          end: DateTime(2026, 8, 4, 7),
        ),
      ],
    );

    expect(proposal, isNull);
  });

  test('一年内的历史睡眠日志也可以用于迁移', () {
    final proposal = HabitSleepLogMigrationService.buildProposal(
      now: DateTime(2026, 8, 4, 12),
      logs: [
        _sleepLog(
          start: DateTime(2026, 3, 9, 23),
          end: DateTime(2026, 3, 10, 7),
        ),
        _sleepLog(
          start: DateTime(2026, 3, 16, 23),
          end: DateTime(2026, 3, 17, 7),
        ),
      ],
    );

    expect(proposal, isNotNull);
    expect(proposal!.observedNights, 2);
  });

  test('时间格式化统一为两位小时和分钟', () {
    expect(HabitSleepLogMigrationService.formatMinute(0), '00:00');
    expect(HabitSleepLogMigrationService.formatMinute(7 * 60 + 5), '07:05');
    expect(HabitSleepLogMigrationService.formatMinute(24 * 60 + 10), '00:10');
  });

  test('识别只有 15 / 30 分钟时间格的入睡记录，并支持开始或平均时间', () {
    final proposal = HabitSleepLogMigrationService.buildProposal(
      now: DateTime(2026, 8, 4, 12),
      logs: [
        _sleepLog(
          start: DateTime(2026, 8, 1, 23),
          end: DateTime(2026, 8, 1, 23, 30),
        ),
        _sleepLog(
          start: DateTime(2026, 8, 2, 23),
          end: DateTime(2026, 8, 2, 23, 30),
        ),
        _sleepLog(
          start: DateTime(2026, 8, 3, 23),
          end: DateTime(2026, 8, 3, 23, 30),
        ),
      ],
    );

    expect(proposal, isNotNull);
    expect(proposal!.hasGridOnlyLogs, isTrue);
    expect(proposal.hasReliableWakeTime, isFalse);
    expect(proposal.createsEarlyWake, isFalse);
    expect(proposal.bedtimeMinute, 23 * 60);
    expect(
      proposal
          .forOptions(
            const HabitSleepLogMigrationOptions(
              timeSelection: HabitSleepLogTimeSelection.midpoint,
            ),
          )!
          .bedtimeMinute,
      23 * 60 + 15,
    );
    expect(
      proposal.forOptions(
        const HabitSleepLogMigrationOptions(kind: HabitSleepLogKind.nap),
      ),
      isNull,
    );
  });
}
