import 'package:countdown_todo/features/habits/models/habit_goal.dart';
import 'package:countdown_todo/features/habits/services/habit_adaptation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HabitAdaptationService', () {
    test('识别已有的中文喝水习惯并提供可解释的饮水目标', () {
      final adaptation = HabitAdaptationService.forHabit(
        HabitGoal(
          uuid: 'water',
          name: '每天喝水',
          sourceType: HabitSourceType.quantityCheckIn,
        ),
      );

      expect(adaptation, isNotNull);
      expect(adaptation!.targetSuggestions.map((e) => e.value), [
        1500,
        1600,
        1700,
      ]);
      expect(adaptation.suggestedQuickValues, [200, 300, 500]);
      expect(adaptation.citations, hasLength(4));
      expect(adaptation.explanation, contains('总水摄入'));
    });

    test('识别英文 hydration 名称', () {
      final adaptation = HabitAdaptationService.forDraft(
        sourceType: HabitSourceType.quantityCheckIn,
        name: 'Daily Hydration',
      );

      expect(adaptation?.kind, HabitAdaptationKind.hydration);
    });

    test('识别俯卧撑并提供分组训练建议', () {
      final adaptation = HabitAdaptationService.forDraft(
        sourceType: HabitSourceType.quantityCheckIn,
        name: 'Push-ups',
      );

      expect(adaptation?.kind, HabitAdaptationKind.pushUp);
      expect(adaptation?.targetSuggestions.map((e) => e.value), [
        8,
        16,
        24,
        36,
      ]);
      expect(adaptation?.suggestedQuickValues, [8, 12, 16]);
      expect(adaptation?.targetUnit, '个');
      expect(adaptation?.citations, hasLength(5));
      expect(adaptation?.explanation, contains('自重抗阻训练'));
    });

    test('识别跑步并提供按分钟累计的每周运动量建议', () {
      final adaptation = HabitAdaptationService.forHabit(
        HabitGoal(
          uuid: 'running',
          name: '跑步',
          sourceType: HabitSourceType.quantityCheckIn,
        ),
      );

      expect(adaptation?.kind, HabitAdaptationKind.running);
      expect(adaptation?.targetUnit, '分钟');
      expect(adaptation?.targetSuggestions.map((e) => e.value), [
        20,
        30,
        45,
        60,
      ]);
      expect(adaptation?.suggestedQuickValues, [20, 30, 45]);
      expect(adaptation?.citations, hasLength(4));
      expect(adaptation?.headline, contains('每周 3 次'));
      expect(adaptation?.explanation, contains('75 分钟'));
    });

    test('识别阅读并提供专注与理解闭环建议', () {
      final adaptation = HabitAdaptationService.forHabit(
        HabitGoal(
          uuid: 'reading',
          name: '阅读',
          sourceType: HabitSourceType.pomodoroTag,
        ),
      );

      expect(adaptation?.kind, HabitAdaptationKind.reading);
      expect(adaptation?.targetUnit, '分钟');
      expect(adaptation?.targetSuggestions.map((e) => e.value), [
        15,
        25,
        30,
        45,
        60,
      ]);
      expect(adaptation?.suggestedQuickValues, [15, 25, 30]);
      expect(adaptation?.citations, hasLength(4));
      expect(adaptation?.headline, contains('25–30 分钟'));
      expect(adaptation?.explanation, contains('间隔复习'));
    });

    test('识别学习并提供主动回忆与间隔复习建议', () {
      final adaptation = HabitAdaptationService.forDraft(
        sourceType: HabitSourceType.pomodoroTag,
        name: '备考学习',
      );

      expect(adaptation?.kind, HabitAdaptationKind.learning);
      expect(adaptation?.targetUnit, '分钟');
      expect(adaptation?.targetSuggestions.map((e) => e.value), [
        25,
        45,
        60,
        90,
      ]);
      expect(adaptation?.suggestedQuickValues, [25, 45, 60]);
      expect(adaptation?.citations, hasLength(2));
      expect(adaptation?.headline, contains('主动回忆'));
    });

    test('识别单词并提供复习优先的词汇目标', () {
      final adaptation = HabitAdaptationService.forHabit(
        HabitGoal(
          uuid: 'vocabulary',
          name: '背单词',
          sourceType: HabitSourceType.quantityCheckIn,
        ),
      );

      expect(adaptation?.kind, HabitAdaptationKind.vocabulary);
      expect(adaptation?.targetUnit, '个');
      expect(adaptation?.targetSuggestions.map((e) => e.value), [
        10,
        20,
        30,
        40,
        60,
      ]);
      expect(adaptation?.suggestedQuickValues, [10, 20, 30]);
      expect(adaptation?.citations, hasLength(2));
      expect(adaptation?.explanation, contains('复习'));
    });

    test('识别冥想并提供短时起步与安全提示', () {
      final adaptation = HabitAdaptationService.forDraft(
        sourceType: HabitSourceType.pomodoroTag,
        name: 'Mindfulness meditation',
      );

      expect(adaptation?.kind, HabitAdaptationKind.meditation);
      expect(adaptation?.targetUnit, '分钟');
      expect(adaptation?.targetSuggestions.map((e) => e.value), [
        5,
        10,
        15,
        20,
      ]);
      expect(adaptation?.suggestedQuickValues, [5, 10, 15]);
      expect(adaptation?.citations, hasLength(1));
      expect(adaptation?.safetyNote, contains('推迟就医'));
    });

    test('识别早起并给出基于睡眠时长的时间起点', () {
      final adaptation = HabitAdaptationService.forDraft(
        sourceType: HabitSourceType.timeCheckIn,
        name: '每天早起',
      );

      expect(adaptation?.kind, HabitAdaptationKind.earlyWake);
      expect(adaptation?.targetSuggestions.map((e) => e.displayValue), [
        '06:30',
        '07:00',
        '07:30',
        '08:00',
      ]);
      expect(adaptation?.headline, contains('7–9 小时'));
      expect(adaptation?.citations, hasLength(5));
    });

    test('识别独立时长型睡眠时长并提供 7–9 小时起点', () {
      final adaptation = HabitAdaptationService.forHabit(
        HabitGoal(
          uuid: 'sleep-duration',
          name: '睡眠时长',
          sourceType: HabitSourceType.durationCheckIn,
        ),
      );

      expect(adaptation?.kind, HabitAdaptationKind.sleepDuration);
      expect(adaptation?.targetSuggestions.map((e) => e.value), [7, 8, 9]);
      expect(adaptation?.targetUnit, '小时');
      expect(adaptation?.citations, hasLength(5));
    });

    test('识别早睡并提供跨午夜友好的时间起点', () {
      final adaptation = HabitAdaptationService.forDraft(
        sourceType: HabitSourceType.timeCheckIn,
        name: '早点睡',
      );

      expect(adaptation?.kind, HabitAdaptationKind.earlySleep);
      expect(adaptation?.targetSuggestions.last.displayValue, '00:00');
      expect(adaptation?.explanation, contains('目标入睡时间'));
      expect(adaptation?.citations, hasLength(5));
    });

    test('从早睡目标反推早起目标，默认 8 小时并保留 7–9 小时区间', () {
      final suggestion = HabitAdaptationService.pairSuggestionFor(
        sourceKind: HabitAdaptationKind.earlySleep,
        sourceName: '早睡',
        sourceMinute: 23 * 60 + 30,
      );

      expect(suggestion?.targetKind, HabitAdaptationKind.earlyWake);
      expect(suggestion?.recommendedMinute, 7 * 60 + 30);
      expect(suggestion?.rangeStartMinute, 6 * 60 + 30);
      expect(suggestion?.rangeEndMinute, 8 * 60 + 30);
    });

    test('从早起目标反推早睡目标时正确处理跨午夜', () {
      final suggestion = HabitAdaptationService.pairSuggestionFor(
        sourceKind: HabitAdaptationKind.earlyWake,
        sourceName: '早起',
        sourceMinute: 7 * 60,
      );

      expect(suggestion?.targetKind, HabitAdaptationKind.earlySleep);
      expect(suggestion?.recommendedMinute, 23 * 60);
      expect(suggestion?.rangeStartMinute, 22 * 60);
      expect(suggestion?.rangeEndMinute, 0);
    });

    test('非数量型或非领域习惯不误触发适配', () {
      expect(
        HabitAdaptationService.forDraft(
          sourceType: HabitSourceType.timeCheckIn,
          name: '喝水时间',
        ),
        isNull,
      );
      expect(
        HabitAdaptationService.forDraft(
          sourceType: HabitSourceType.quantityCheckIn,
          name: '整理房间',
        ),
        isNull,
      );
    });
  });
}
