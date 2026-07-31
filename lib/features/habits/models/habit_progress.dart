import 'habit_checkin.dart';
import 'habit_goal.dart';

/// 单日（或单周期）习惯状态。
enum HabitDayStatus {
  /// 非计划日：不算达标、不算未达标、不增加连续、不打断连续。
  notPlanned,

  /// 进行中：周期尚未结束且尚未达标。
  inProgress,

  /// 达标。
  met,

  /// 未达标：周期已结束但仍未达标。
  missed,

  /// 跳过：默认不增加，也不中断。
  skipped,
}

/// 习惯进度计算结果。
///
/// 对应设计文档第十六节的统一进度计算返回结构。
class HabitProgress {
  /// 周期锚点（每日习惯为逻辑日期 00:00；每周为周一的 00:00；每月为 1 号）。
  final DateTime period;

  /// 当前累计值：
  /// - 完成型：0 或 1；
  /// - 时长型：累计有效时长（秒）；
  /// - 数量型：当日打卡数值之和；
  /// - 时间点型：0（看 [firstRecordAt] / [onTime]）。
  final double currentValue;

  /// 目标值。
  final double targetValue;

  /// 完成比例（0..1 以上，可为 1.0 封顶后的值）。
  final double completionRatio;

  /// 本周期内是否有打卡/记录。
  final bool hasRecord;

  /// 是否达标。
  final bool goalMet;

  /// 是否计划内周期（非计划日不参与统计）。
  final bool isPlanned;

  /// 周期是否已经结束（当天尚未结束时不提前判定失败）。
  final bool isFinished;

  /// 时间点型：实际时间是否符合目标（含允许范围）。
  final bool onTime;

  /// 本周期记录数量。
  final int recordCount;

  /// 本周期最早一条记录的实际发生时间。
  final DateTime? firstRecordAt;

  /// 本周期最晚一条记录的实际发生时间。
  final DateTime? lastRecordAt;

  /// 数量型 / 时间点型当周期打卡明细（详情页使用，可为空）。
  final List<HabitCheckIn>? checkIns;

  const HabitProgress({
    required this.period,
    required this.currentValue,
    required this.targetValue,
    required this.completionRatio,
    required this.hasRecord,
    required this.goalMet,
    required this.isPlanned,
    required this.isFinished,
    this.onTime = false,
    this.recordCount = 0,
    this.firstRecordAt,
    this.lastRecordAt,
    this.checkIns,
  });

  /// 按设计文档规则推导单日状态。
  HabitDayStatus get dayStatus {
    if (!isPlanned) return HabitDayStatus.notPlanned;
    if (goalMet) return HabitDayStatus.met;
    if (!isFinished) return HabitDayStatus.inProgress;
    return HabitDayStatus.missed;
  }

  factory HabitProgress.empty(DateTime period) => HabitProgress(
        period: period,
        currentValue: 0,
        targetValue: 0,
        completionRatio: 0,
        hasRecord: false,
        goalMet: false,
        isPlanned: false,
        isFinished: true,
      );
}

/// 一个习惯在某个日期范围内的逐日进度。
class HabitDayProgress {
  final HabitGoal habit;
  final DateTime logicalDate;
  final HabitDayStatus status;
  final HabitProgress progress;

  const HabitDayProgress({
    required this.habit,
    required this.logicalDate,
    required this.status,
    required this.progress,
  });
}

/// 连续达标与完成率统计。
class HabitStreakSummary {
  /// 当前连续达标（每天习惯按天、每周习惯按周、每月习惯按月）。
  final int currentStreak;

  /// 最长连续达标。
  final int longestStreak;

  /// 近 7 个周期完成率（0..1）。
  final double rate7;

  /// 近 30 个周期完成率（0..1）。
  final double rate30;

  /// 统计窗口内应完成次数（计划内周期数）。
  final int plannedCount;

  /// 统计窗口内实际达标次数。
  final int completedCount;

  /// 统计窗口内逾期次数（计划内且已结束但未达标）。
  final int overdueCount;

  /// 最容易中断的星期（0=周一 … 6=周日），数据不足时为 null。
  final int? weakestWeekday;

  /// 数量型：有记录的已结束计划日内平均数值。
  final double? averageValue;

  /// 时长型：有记录的已结束计划日内平均时长（秒）。
  final double? averageDuration;

  /// 时间点型：有记录的已结束计划日平均实际时间（一天内的分钟数）。
  final double? averageTimeMinute;

  /// 时间点型：准时率（0..1）。
  final double? onTimeRate;

  const HabitStreakSummary({
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.rate7 = 0,
    this.rate30 = 0,
    this.plannedCount = 0,
    this.completedCount = 0,
    this.overdueCount = 0,
    this.weakestWeekday,
    this.averageValue,
    this.averageDuration,
    this.averageTimeMinute,
    this.onTimeRate,
  });
}
