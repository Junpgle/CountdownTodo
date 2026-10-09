import 'package:countdown_todo/features/habits/services/habit_sleep_log_migration_service.dart';
import 'package:countdown_todo/models.dart';
import 'package:flutter_test/flutter_test.dart';

TimeLogItem _sleepLog(DateTime start, DateTime end) => TimeLogItem(
      title: '睡眠',
      startTime: start.millisecondsSinceEpoch,
      endTime: end.millisecondsSinceEpoch,
    );

void main() {
  test('一年窗口按本地日历日期保留截止日凌晨记录', () {
    final proposal = HabitSleepLogMigrationService.buildProposal(
      now: DateTime(2026, 11, 2, 12),
      logs: [
        _sleepLog(
          DateTime(2025, 11, 2, 0, 30),
          DateTime(2025, 11, 2, 7, 30),
        ),
        _sleepLog(
          DateTime(2025, 11, 3, 0, 30),
          DateTime(2025, 11, 3, 7, 30),
        ),
      ],
    );

    expect(proposal, isNotNull);
    expect(proposal!.observedNights, 2);
  });
}
