import 'package:countdown_todo/features/habits/models/habit_checkin.dart';
import 'package:countdown_todo/features/habits/models/habit_goal.dart';
import 'package:countdown_todo/features/habits/services/habit_drink_log_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HabitDrinkLogService.summarizeDrinkLogs', () {
    HabitGoal makeGoal({String name = '戒掉饮料'}) {
      return HabitGoal(
        uuid: 'habit_drink_1',
        name: name,
        icon: '🥤',
        sourceType: HabitSourceType.recurringTodo,
        displayMode: HabitDisplayMode.habitOnly,
      );
    }

    HabitCheckIn makeCheckIn({
      required String uuid,
      required String dayKey,
      String? note,
      HabitCheckInSource source = HabitCheckInSource.manual,
      bool isDeleted = false,
    }) {
      return HabitCheckIn(
        uuid: uuid,
        habitUuid: 'habit_drink_1',
        occurredAt: DateTime(2026, 11, 23, 12).millisecondsSinceEpoch,
        logicalDate: dayKey,
        timezoneOffsetMinutes: 480,
        value: 1,
        note: note,
        source: source,
        isDeleted: isDeleted,
      );
    }

    test('统计累计与近 7 天饮品次数、天数及品类明细', () {
      final goal = makeGoal();
      final referenceDate = DateTime(2026, 11, 23);
      final checkIns = [
        // 超过 7 天（2026-11-10）喝了 1 杯奶茶
        makeCheckIn(uuid: 'c1', dayKey: '2026-11-10', note: '🧋 奶茶'),
        // 近 7 天边界（2026-11-17）喝了 1 杯奶茶 + 1 杯饮料
        makeCheckIn(uuid: 'c2', dayKey: '2026-11-17', note: '🧋 奶茶'),
        makeCheckIn(uuid: 'c3', dayKey: '2026-11-17', note: '🥤 饮料'),
        // 今天（2026-11-23）喝了 1 杯咖啡
        makeCheckIn(uuid: 'c4', dayKey: '2026-11-23', note: '☕ 咖啡'),
        // 今日未喝饮料成功打卡（无饮品 note），不应计入喝饮料次数
        makeCheckIn(uuid: 'c5', dayKey: '2026-11-22', note: null),
        // 已删除与跳过记录不应计入
        makeCheckIn(
          uuid: 'c6',
          dayKey: '2026-11-21',
          note: '🧋 奶茶',
          isDeleted: true,
        ),
        makeCheckIn(
          uuid: 'c7',
          dayKey: '2026-11-20',
          note: '🧋 奶茶',
          source: HabitCheckInSource.skip,
        ),
      ];

      final stats = HabitDrinkLogService.summarizeDrinkLogs(
        goal: goal,
        allCheckIns: checkIns,
        referenceDate: referenceDate,
      );

      expect(stats.totalDrinks, 4);
      expect(stats.totalDrinkDays, 3);
      expect(stats.last7DaysDrinks, 3);
      expect(stats.last7DaysDrinkDays, 2);
      expect(stats.breakdown, hasLength(3));

      final milkTea = stats.breakdown.firstWhere((e) => e.icon == '🧋');
      expect(milkTea.label, '奶茶');
      expect(milkTea.totalCount, 2);
      expect(milkTea.last7DaysCount, 1);

      final soda = stats.breakdown.firstWhere((e) => e.icon == '🥤');
      expect(soda.totalCount, 1);
      expect(soda.last7DaysCount, 1);
    });

    test('非戒饮习惯返回空统计', () {
      final stats = HabitDrinkLogService.summarizeDrinkLogs(
        goal: makeGoal(name: '每日阅读'),
        allCheckIns: [
          makeCheckIn(uuid: 'c1', dayKey: '2026-11-23', note: '☕ 咖啡'),
        ],
      );

      expect(stats.totalDrinks, 0);
      expect(stats.last7DaysDrinks, 0);
      expect(stats.breakdown, isEmpty);
    });
  });
}
