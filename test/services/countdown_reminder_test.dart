import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/countdown_reminder_helper.dart';
import 'package:countdown_todo/services/focus_do_not_disturb_service.dart';
import 'package:countdown_todo/services/item_semantics_service.dart';
import 'package:countdown_todo/services/notification_service.dart';
import 'package:countdown_todo/services/reminder_schedule_service.dart';
import 'package:countdown_todo/services/storage/app_settings_storage.dart';
import 'package:countdown_todo/utils/time_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('ItemSemanticsService.countdownCategoryForTitle', () {
    test(
      'recognizes holiday, exam, anniversary, birthday, travel, deadline',
      () {
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
      },
    );
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
      expect(reminders[0]['countdownDateStr'], '2026-11-21');
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
      expect(reminders[1]['countdownDateStr'], '2026-11-25');
      expect(reminders[1]['notifId'], 70002);
      expect(
        DateTime.fromMillisecondsSinceEpoch(
          reminders[1]['triggerAtMs'] as int,
          isUtc: true,
        ).toLocal(),
        DateTime(2026, 11, 25, 8, 0),
      );
    });

    test('skips countdown when target day was already dismissed', () {
      final now = DateTime(2026, 11, 21, 7, 30);
      final limit = now.add(const Duration(days: 7));
      final reminders = ReminderScheduleService.buildCountdownReminders(
        countdowns: [
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
        ],
        now: now,
        limit: limit,
        dismissedDateKeys: const {'cd-1@2026-11-21'},
      );

      expect(reminders, hasLength(1));
      expect(reminders.single['countdownId'], 'cd-2');
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

  group('CountdownReminderHelper', () {
    test('resolves countdown by explicit countdownId', () {
      final target = CountdownItem(
        id: 'cd-anniversary',
        title: '恋爱纪念日',
        targetDate: DateTime(2026, 11, 27, 10, 0),
      );
      final other = CountdownItem(
        id: 'cd-exam',
        title: '高等数学考试',
        targetDate: DateTime(2026, 11, 27, 10, 0),
      );

      final matched = CountdownReminderHelper.findCountdownToComplete(
        countdowns: [other, target],
        countdownId: 'cd-anniversary',
        notifId: CountdownReminderHelper.liveNotificationId('cd-exam'),
        now: DateTime(2026, 11, 27, 9, 30),
      );

      expect(matched?.id, 'cd-anniversary');
    });

    test('resolves countdown by live notification id preferring today', () {
      final today = DateTime(2026, 11, 27, 9, 30);
      final completed = CountdownItem(
        id: 'cd-done',
        title: '已完成倒数日',
        targetDate: today,
        isCompleted: true,
      );
      final dueToday = CountdownItem(
        id: 'cd-birthday',
        title: '妈妈生日',
        targetDate: DateTime(2026, 11, 27, 20, 0),
      );

      final matched = CountdownReminderHelper.findCountdownToComplete(
        countdowns: [completed, dueToday],
        notifId: CountdownReminderHelper.liveNotificationId(dueToday.id),
        now: today,
      );

      expect(matched?.id, dueToday.id);
      expect(
        CountdownReminderHelper.findCountdownToComplete(
          countdowns: [completed, dueToday],
          notifId: CountdownReminderHelper.liveNotificationId(completed.id),
          now: today,
        )?.id,
        isNull,
      );
    });

    test('resolves countdown by scheduled alarm id via reminder registry', () {
      final cd1 = CountdownItem(
        id: 'cd-1',
        title: '期末考试',
        targetDate: DateTime(2026, 11, 28, 0, 0),
      );
      final cd2 = CountdownItem(
        id: 'cd-2',
        title: '发工资',
        targetDate: DateTime(2026, 11, 27, 0, 0),
      );

      final matched = CountdownReminderHelper.findCountdownToComplete(
        countdowns: [cd1, cd2],
        notifId: 70002,
        scheduledReminders: const [
          {'notifId': 70001, 'type': 'countdown', 'countdownId': 'cd-1'},
          {'notifId': 70002, 'type': 'countdown', 'countdownId': 'cd-2'},
        ],
        now: DateTime(2026, 11, 27, 9, 0),
      );

      expect(matched?.id, 'cd-2');
      expect(
        CountdownReminderHelper.scheduledNotifIdsForCountdown('cd-2', const [
          {'notifId': 70001, 'type': 'countdown', 'countdownId': 'cd-1'},
          {'notifId': 70002, 'type': 'countdown', 'countdownId': 'cd-2'},
        ]),
        [70002],
      );
    });

    test('prunes dismissed keys keeping newest dates', () {
      final pruned = CountdownReminderHelper.pruneDismissedKeys([
        'a@2026-11-01',
        'b@2026-11-27',
        'c@2026-11-15',
      ], maxEntries: 2);

      expect(pruned, ['b@2026-11-27', 'c@2026-11-15']);
    });
  });

  group('CountdownReminderPrefs and NotificationService suppression', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('persists dismissed state and clears per countdown', () async {
      await CountdownReminderPrefs.markDismissed('cd-1', '2026-11-27');
      await CountdownReminderPrefs.markDismissed('cd-2', '2026-11-27');

      expect(
        await CountdownReminderPrefs.isDismissed('cd-1', '2026-11-27'),
        isTrue,
      );
      expect(
        await CountdownReminderPrefs.isDismissed('cd-2', '2026-11-27'),
        isTrue,
      );

      await CountdownReminderPrefs.clearForCountdown('cd-1');

      expect(
        await CountdownReminderPrefs.isDismissed('cd-1', '2026-11-27'),
        isFalse,
      );
      expect(
        await CountdownReminderPrefs.isDismissed('cd-2', '2026-11-27'),
        isTrue,
      );
    });

    test('showCountdownLiveActivity skips countdowns dismissed today and resumes when cleared', () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const notifChannel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      const macStatusChannel = MethodChannel('countdown_todo/macos_status_bar');
      if (Platform.isMacOS) {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        MacOSFlutterLocalNotificationsPlugin.registerWith();
      }
      final calls = <String>[];
      messenger.setMockMethodCallHandler(notifChannel, (call) async {
        calls.add('notif:${call.method}');
        if (call.method == 'initialize') return true;
        return null;
      });
      messenger.setMockMethodCallHandler(macStatusChannel, (call) async {
        calls.add('mac:${call.method}');
        return null;
      });
      addTearDown(() async {
        await FocusDoNotDisturbService.setActive(false, force: true);
        messenger.setMockMethodCallHandler(notifChannel, null);
        messenger.setMockMethodCallHandler(macStatusChannel, null);
        debugDefaultTargetPlatformOverride = null;
      });

      await AppSettingsStorage.setLiveActivityNotificationEnabled(true);
      await AppSettingsStorage.setCountdownNotificationEnabled(true);
      await FocusDoNotDisturbService.setActive(false, force: true);

      final targetDay = DateTime(2026, 11, 27, 18, 0);
      final afterEight = DateTime(2026, 11, 27, 9, 30);
      final dateStr = AppTimeFormats.date(targetDay);
      final countdown = CountdownItem(
        id: 'cd-today',
        title: '纪念日',
        targetDate: targetDay,
      );

      await NotificationService.markCountdownDismissed(
        countdownId: countdown.id,
        dateStr: dateStr,
      );
      calls.clear();
      expect(
        await NotificationService.showCountdownLiveActivity(
          countdown,
          now: afterEight,
        ),
        isFalse,
      );
      expect(calls, isEmpty);

      await NotificationService.clearCountdownReminderState(countdown.id);
      calls.clear();
      expect(
        await NotificationService.showCountdownLiveActivity(
          countdown,
          now: afterEight,
        ),
        isTrue,
      );
      expect(calls, isNotEmpty);
    });
  });
}
