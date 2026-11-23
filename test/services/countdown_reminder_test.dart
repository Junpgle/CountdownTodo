import 'package:flutter_test/flutter_test.dart';
import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/item_semantics_service.dart';
import 'package:countdown_todo/services/reminder_schedule_service.dart';

void main() {
  group('ItemSemanticsService.countdownCategoryForTitle', () {
    test('recognizes holiday, exam, anniversary, birthday, travel, deadline', () {
      expect(
        ItemSemanticsService.countdownCategoryForTitle('国庆放假'),
        'holiday',
      );
      expect(
        ItemSemanticsService.countdownCategoryForTitle('高等数学期末考试'),
        'exam',
      );
      expect(
        ItemSemanticsService.countdownCategoryForTitle('恋爱三周年纪念日'),
        'anniversary',
      );
      expect(
        ItemSemanticsService.countdownCategoryForTitle('妈妈生日'),
        'birthday',
      );
      expect(
        ItemSemanticsService.countdownCategoryForTitle('回家高铁出发'),
        'travel',
      );
      expect(
        ItemSemanticsService.countdownCategoryForTitle('论文提交截止 DDL'),
        'deadline',
      );
      expect(
        ItemSemanticsService.countdownCategoryForTitle('普通倒数日'),
        'default',
      );
    });
  });

  group('ReminderScheduleService.buildCountdownReminders', () {
    test('schedules 08:00 reminder on target day within window', () {
      final now = DateTime(2026, 11, 21, 7, 30);
      final limit = now.add(const Duration(days: 7));
      final countdowns = [
        CountdownItem(
          id: 'cd-1',
          title: '妈妈生日',
          targetDate: DateTime(2026, 11, 21, 18, 0),
        ),
        CountdownItem(
          id: 'cd-2',
          title: '期末考试',
          targetDate: DateTime(2026, 11, 25, 0, 0),
        ),
        CountdownItem(
          id: 'cd-completed',
          title: '已完成纪念日',
          targetDate: DateTime(2026, 11, 22, 0, 0),
          isCompleted: true,
        ),
        CountdownItem(
          id: 'cd-deleted',
          title: '已删除放假',
          targetDate: DateTime(2026, 11, 22, 0, 0),
          isDeleted: true,
        ),
        CountdownItem(
          id: 'cd-far',
          title: '明年春节放假',
          targetDate: DateTime(2026, 12, 10, 0, 0),
        ),
      ];

      final reminders = ReminderScheduleService.buildCountdownReminders(
        countdowns: countdowns,
        now: now,
        limit: limit,
      );

      expect(reminders, hasLength(2));
      expect(reminders[0]['type'], 'countdown');
      expect(reminders[0]['countdownCategory'], 'birthday');
      expect(reminders[0]['notifId'], 70001);
      expect(
        DateTime.fromMillisecondsSinceEpoch(
          reminders[0]['triggerAtMs'] as int,
          isUtc: true,
        ).toLocal(),
        DateTime(2026, 11, 21, 8, 0),
      );

      expect(reminders[1]['type'], 'countdown');
      expect(reminders[1]['countdownCategory'], 'exam');
      expect(reminders[1]['notifId'], 70002);
      expect(
        DateTime.fromMillisecondsSinceEpoch(
          reminders[1]['triggerAtMs'] as int,
          isUtc: true,
        ).toLocal(),
        DateTime(2026, 11, 25, 8, 0),
      );
    });

    test('skips countdown when 08:00 on target day has already passed', () {
      final now = DateTime(2026, 11, 21, 9, 0);
      final limit = now.add(const Duration(days: 7));
      final reminders = ReminderScheduleService.buildCountdownReminders(
        countdowns: [
          CountdownItem(
            id: 'cd-past-8am',
            title: '国庆放假',
            targetDate: DateTime(2026, 11, 21, 23, 0),
          ),
        ],
        now: now,
        limit: limit,
      );

      expect(reminders, isEmpty);
    });
  });
}
