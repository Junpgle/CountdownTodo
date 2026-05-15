import 'package:flutter/material.dart';
import 'timeline_service.dart';

/// 勋章信息定义
class MedalInfo {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final String category; // 'focus', 'completion', 'persistence', 'efficiency', 'breadth'
  final int priority; // 1 (most motivating) to 5
  
  MedalInfo({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.category,
    required this.priority,
  });
}

/// 勋章进度信息
class MedalProgress {
  final MedalInfo medal;
  final double progress; // 0.0 to 1.0
  final bool earned;
  final String nextMilestone; // "还需要 X..." or "已获得"
  final int stepsRemaining; // 用于排序的步数，越小越容易
  final DateTime? earnedAt;

  MedalProgress({
    required this.medal,
    required this.progress,
    required this.earned,
    required this.nextMilestone,
    required this.stepsRemaining,
    this.earnedAt,
  });
}

/// 勋章推荐结果
class MedalRecommendation {
  final List<MedalProgress> topRecommendations; // 前3个最容易达成的
  final List<MedalProgress> allMedals; // 所有勋章及进度
  final List<MedalProgress> earnedMedals; // 已获得的勋章

  MedalRecommendation({
    required this.topRecommendations,
    required this.allMedals,
    required this.earnedMedals,
  });
}

class MedalRecommendationService {
  // 定义所有 21+ 个勋章
  static final List<MedalInfo> allMedals = [
    // === Focus Medals (专注相关) ===
    MedalInfo(
      id: 'focus_starter',
      title: '专注启动者',
      description: '记录第一次 Pomodoro',
      icon: Icons.play_circle_outline_rounded,
      color: Colors.green,
      category: 'focus',
      priority: 1,
    ),
    MedalInfo(
      id: 'two_hour_guardian',
      title: '两小时守门员',
      description: '累计专注时长 120 分钟',
      icon: Icons.hourglass_bottom_rounded,
      color: Colors.blue,
      category: 'focus',
      priority: 2,
    ),
    MedalInfo(
      id: 'eight_hour_trek',
      title: '八小时长征',
      description: '累计专注时长 480 分钟',
      icon: Icons.terrain_rounded,
      color: Colors.brown,
      category: 'focus',
      priority: 3,
    ),
    MedalInfo(
      id: 'deep_worker',
      title: '深度工作者',
      description: '完成第一个深度专注（≥60分钟）',
      icon: Icons.diamond_outlined,
      color: Colors.purple,
      category: 'focus',
      priority: 2,
    ),
    MedalInfo(
      id: 'long_focus_specialist',
      title: '长专注选手',
      description: '单次专注达到 90 分钟',
      icon: Icons.workspace_premium_rounded,
      color: Colors.amber,
      category: 'focus',
      priority: 3,
    ),
    MedalInfo(
      id: 'stable_output',
      title: '稳定输出',
      description: '中断率 ≤10% 且至少 3 次专注',
      icon: Icons.shield_moon_rounded,
      color: Colors.indigoAccent,
      category: 'focus',
      priority: 2,
    ),

    // === Completion Medals (完成相关) ===
    MedalInfo(
      id: 'task_harvester',
      title: '任务收割者',
      description: '完成第一个任务',
      icon: Icons.task_alt_rounded,
      color: Colors.green,
      category: 'completion',
      priority: 1,
    ),
    MedalInfo(
      id: 'plan_fulfiller',
      title: '计划兑现者',
      description: '任务完成率达到 80%',
      icon: Icons.fact_check_outlined,
      color: Colors.lightGreen,
      category: 'completion',
      priority: 2,
    ),
    MedalInfo(
      id: 'early_deliverer',
      title: '提前交付者',
      description: '至少提前完成 1 个任务',
      icon: Icons.rocket_launch_outlined,
      color: Colors.cyan,
      category: 'completion',
      priority: 2,
    ),
    MedalInfo(
      id: 'ddl_tamer',
      title: 'DDL 驯服者',
      description: '在截止前完成至少 1 个任务',
      icon: Icons.flag_outlined,
      color: Colors.redAccent,
      category: 'completion',
      priority: 3,
    ),

    // === Persistence Medals (坚持相关) ===
    MedalInfo(
      id: 'night_efficiency_king',
      title: '深夜效率王',
      description: '高效时段在夜间（20:00-05:00）',
      icon: Icons.nightlight_round,
      color: Colors.indigo,
      category: 'persistence',
      priority: 3,
    ),
    MedalInfo(
      id: 'golden_hour',
      title: '黄金时刻',
      description: '发现你的高效时间段',
      icon: Icons.wb_sunny_outlined,
      color: Colors.orange,
      category: 'persistence',
      priority: 2,
    ),
    MedalInfo(
      id: 'long_distance_runner',
      title: '长跑型选手',
      description: '连续活跃至少 3 天',
      icon: Icons.local_fire_department_outlined,
      color: Colors.deepOrange,
      category: 'persistence',
      priority: 2,
    ),

    // === Breadth Medals (广度相关) ===
    MedalInfo(
      id: 'learning_polymath',
      title: '学习多面手',
      description: '涉猎 4+ 个不同主题',
      icon: Icons.hub_outlined,
      color: Colors.teal,
      category: 'breadth',
      priority: 3,
    ),
    MedalInfo(
      id: 'main_line_pusher',
      title: '主线推进者',
      description: '单个主题占比达到 45%',
      icon: Icons.route_outlined,
      color: Colors.deepPurple,
      category: 'breadth',
      priority: 2,
    ),

    // === Learning Medals (学习相关) ===
    MedalInfo(
      id: 'knowledge_scout',
      title: '知识侦察兵',
      description: '进行 3+ 次知识检索',
      icon: Icons.travel_explore_rounded,
      color: Colors.teal,
      category: 'breadth',
      priority: 2,
    ),
    MedalInfo(
      id: 'exam_prep_sprinter',
      title: '备考冲刺者',
      description: '3+ 次备考相关活动',
      icon: Icons.school_outlined,
      color: Colors.red,
      category: 'completion',
      priority: 3,
    ),

    // === Course Medals (课程相关) ===
    MedalInfo(
      id: 'course_companion',
      title: '课表同行者',
      description: '记录第一节课',
      icon: Icons.event_note_outlined,
      color: Colors.blueGrey,
      category: 'persistence',
      priority: 2,
    ),
    MedalInfo(
      id: 'full_course_survivor',
      title: '满课生存者',
      description: '单日课程数达到 5 节',
      icon: Icons.view_day_outlined,
      color: Colors.deepOrange,
      category: 'persistence',
      priority: 3,
    ),

    // === Screen Time Medals (屏幕时间相关) ===
    MedalInfo(
      id: 'screen_master',
      title: '屏幕掌控者',
      description: '生产力应用占比达到 50%',
      icon: Icons.desktop_windows_outlined,
      color: Colors.blueGrey,
      category: 'efficiency',
      priority: 2,
    ),
    MedalInfo(
      id: 'low_distraction_mode',
      title: '低分心模式',
      description: '分心应用占比 ≤15%',
      icon: Icons.visibility_off_outlined,
      color: Colors.grey,
      category: 'efficiency',
      priority: 3,
    ),
  ];

  /// 计算单个勋章的进度 (0.0-1.0)
  static MedalProgress calculateMedalProgress(
    MedalInfo medal,
    TimelineSummary summary,
    int totalFocusMinutes,
    int completedCount,
    int totalCount,
    int earlyCompletionCount,
    int deadlineSprintCount,
    int courseCount,
    int maxDailyCourseCount,
    int screenTimeSeconds,
    int productiveScreenSeconds,
    int distractionScreenSeconds,
  ) {
    double progress = 0.0;
    bool earned = false;
    String nextMilestone = '';
    int stepsRemaining = 0;

    switch (medal.id) {
      // Focus medals
      case 'focus_starter':
        earned = summary.pomodoroCount >= 1;
        progress = earned ? 1.0 : (summary.pomodoroCount.toDouble());
        stepsRemaining = earned ? 0 : 1;
        nextMilestone = earned ? '已获得' : '需要 1 次 Pomodoro';

      case 'two_hour_guardian':
        progress = (totalFocusMinutes / 120).clamp(0.0, 1.0);
        earned = totalFocusMinutes >= 120;
        stepsRemaining = earned ? 0 : (120 - totalFocusMinutes);
        nextMilestone = earned
            ? '已获得'
            : '还需要 ${(120 - totalFocusMinutes)} 分钟';

      case 'eight_hour_trek':
        progress = (totalFocusMinutes / 480).clamp(0.0, 1.0);
        earned = totalFocusMinutes >= 480;
        stepsRemaining = earned ? 0 : (480 - totalFocusMinutes);
        nextMilestone = earned
            ? '已获得'
            : '还需要 ${(480 - totalFocusMinutes)} 分钟';

      case 'deep_worker':
        earned = summary.deepWorkCount > 0;
        progress = earned ? 1.0 : (summary.deepWorkCount.toDouble());
        stepsRemaining = earned ? 0 : 1;
        nextMilestone = earned ? '已获得' : '需要 1 次深度专注（≥60分钟）';

      case 'long_focus_specialist':
        progress = (summary.longestPomodoroMinutes / 90).clamp(0.0, 1.0);
        earned = summary.longestPomodoroMinutes >= 90;
        stepsRemaining = earned ? 0 : (90 - summary.longestPomodoroMinutes);
        nextMilestone = earned
            ? '已获得'
            : '最长记录 ${summary.longestPomodoroMinutes} 分钟，还需 ${(90 - summary.longestPomodoroMinutes)} 分钟';

      case 'stable_output':
        final meetsMinPomodoro = summary.pomodoroCount >= 3;
        final meetsInterruption = summary.interruptionRate <= 0.1;
        earned = meetsMinPomodoro && meetsInterruption;
        if (meetsMinPomodoro && meetsInterruption) {
          progress = 1.0;
        } else if (meetsMinPomodoro) {
          progress = (1 - summary.interruptionRate).clamp(0.0, 1.0) * 0.5 + 0.5;
        } else {
          progress = (summary.pomodoroCount / 3).clamp(0.0, 1.0) * 0.5;
        }
        stepsRemaining = earned
            ? 0
            : (meetsMinPomodoro ? 1 : (3 - summary.pomodoroCount));
        nextMilestone = earned
            ? '已获得'
            : '中断率 ${(summary.interruptionRate * 100).toStringAsFixed(1)}%, 需要 ≤10% 且 ≥3 次';

      // Completion medals
      case 'task_harvester':
        earned = completedCount >= 1;
        progress = earned ? 1.0 : 0.0;
        stepsRemaining = earned ? 0 : 1;
        nextMilestone = earned ? '已获得' : '完成第一个任务';

      case 'plan_fulfiller':
        final rate = totalCount > 0 ? completedCount / totalCount : 0.0;
        progress = (rate / 0.8).clamp(0.0, 1.0);
        earned = rate >= 0.8;
        stepsRemaining = earned ? 0 : 1;
        nextMilestone = earned
            ? '已获得'
            : '完成率 ${(rate * 100).toStringAsFixed(0)}%, 需要达到 80%';

      case 'early_deliverer':
        earned = earlyCompletionCount > 0;
        progress = earned ? 1.0 : 0.0;
        stepsRemaining = earned ? 0 : 1;
        nextMilestone =
            earned ? '已获得' : '需要提前完成 1 个任务';

      case 'ddl_tamer':
        earned = deadlineSprintCount > 0;
        progress = earned ? 1.0 : 0.0;
        stepsRemaining = earned ? 0 : 1;
        nextMilestone = earned ? '已获得' : '在截止前完成 1 个任务';

      // Persistence medals
      case 'night_efficiency_king':
        earned = summary.hourlyDistribution.isNotEmpty &&
            (summary.peakHour >= 20 || summary.peakHour <= 5);
        progress = earned ? 1.0 : 0.5;
        stepsRemaining = earned ? 0 : 1;
        nextMilestone = earned
            ? '已获得 (${summary.peakHour}:00 是你的黄金时刻)'
            : '高效时段需在夜间';

      case 'golden_hour':
        earned = summary.hourlyDistribution.any((v) => v > 0);
        progress = earned ? 1.0 : 0.0;
        stepsRemaining = earned ? 0 : 1;
        nextMilestone = earned
            ? '已获得 (${summary.peakHour}:00 是你的高效窗口)'
            : '记录活动以发现高效时段';

      case 'long_distance_runner':
        progress = (summary.consecutiveActiveDays / 3).clamp(0.0, 1.0);
        earned = summary.consecutiveActiveDays >= 3;
        stepsRemaining = earned ? 0 : (3 - summary.consecutiveActiveDays);
        nextMilestone = earned
            ? '已获得'
            : '连续活跃 ${summary.consecutiveActiveDays} 天，还需 ${(3 - summary.consecutiveActiveDays)} 天';

      // Breadth medals
      case 'learning_polymath':
        progress = (summary.subjectDistribution.length / 4).clamp(0.0, 1.0);
        earned = summary.subjectDistribution.length >= 4;
        stepsRemaining = earned ? 0 : (4 - summary.subjectDistribution.length);
        nextMilestone = earned
            ? '已获得'
            : '已覆盖 ${summary.subjectDistribution.length} 个主题，还需 ${(4 - summary.subjectDistribution.length)} 个';

      case 'main_line_pusher':
        final topRatio = _calculateTopSubjectRatio(summary);
        progress = (topRatio / 45).clamp(0.0, 1.0);
        earned = topRatio >= 45;
        stepsRemaining = earned ? 0 : 1;
        nextMilestone = earned
            ? '已获得 (${summary.topSubject} 占 ${topRatio.toStringAsFixed(0)}%)'
            : '主要科目占比 ${topRatio.toStringAsFixed(0)}%，需达 45%';

      case 'knowledge_scout':
        progress = (summary.searchCount / 3).clamp(0.0, 1.0);
        earned = summary.searchCount >= 3;
        stepsRemaining = earned ? 0 : (3 - summary.searchCount);
        nextMilestone = earned
            ? '已获得'
            : '检索 ${summary.searchCount} 次，还需 ${(3 - summary.searchCount)} 次';

      case 'exam_prep_sprinter':
        progress = (summary.examPrepCount / 3).clamp(0.0, 1.0);
        earned = summary.examPrepCount >= 3;
        stepsRemaining = earned ? 0 : (3 - summary.examPrepCount);
        nextMilestone = earned
            ? '已获得'
            : '备考活动 ${summary.examPrepCount} 次，还需 ${(3 - summary.examPrepCount)} 次';

      // Course medals
      case 'course_companion':
        earned = courseCount >= 1;
        progress = earned ? 1.0 : 0.0;
        stepsRemaining = earned ? 0 : 1;
        nextMilestone = earned ? '已获得' : '记录第一节课';

      case 'full_course_survivor':
        progress = (maxDailyCourseCount / 5).clamp(0.0, 1.0);
        earned = maxDailyCourseCount >= 5;
        stepsRemaining = earned ? 0 : (5 - maxDailyCourseCount);
        nextMilestone = earned
            ? '已获得'
            : '最满一天 $maxDailyCourseCount 节课，还需 ${(5 - maxDailyCourseCount)} 节';

      // Screen time medals
      case 'screen_master':
        final masterRatio = screenTimeSeconds > 0
            ? (productiveScreenSeconds / screenTimeSeconds) * 100
            : 0.0;
        progress = (masterRatio / 50).clamp(0.0, 1.0);
        earned = masterRatio >= 50;
        stepsRemaining = earned ? 0 : 1;
        nextMilestone = earned
            ? '已获得 (生产力 ${masterRatio.toStringAsFixed(0)}%)'
            : '生产力应用占比 ${masterRatio.toStringAsFixed(0)}%，需达 50%';

      case 'low_distraction_mode':
        final distractionRatio = screenTimeSeconds > 0
            ? (distractionScreenSeconds / screenTimeSeconds) * 100
            : 0.0;
        progress = ((100 - distractionRatio) / 85).clamp(0.0, 1.0);
        earned = distractionRatio <= 15;
        stepsRemaining = earned ? 0 : 1;
        nextMilestone = earned
            ? '已获得 (分心 ${distractionRatio.toStringAsFixed(0)}%)'
            : '分心应用占比 ${distractionRatio.toStringAsFixed(0)}%，需 ≤15%';

      default:
        progress = 0.0;
        stepsRemaining = 1;
        nextMilestone = '待实现';
    }

    return MedalProgress(
      medal: medal,
      progress: progress,
      earned: earned,
      nextMilestone: nextMilestone,
      stepsRemaining: stepsRemaining,
    );
  }

  /// 计算顶部主题的占比
  static double _calculateTopSubjectRatio(TimelineSummary summary) {
    if (summary.subjectDistribution.isEmpty) return 0.0;
    final total = summary.subjectDistribution.values.fold<double>(0.0, (sum, val) {
      final doubleVal = val is int ? val.toDouble() : (val as double);
      return sum + doubleVal;
    });
    if (total == 0) return 0.0;
    final topValue =
        summary.subjectDistribution.values.fold<double>(0.0, (max, val) {
      final doubleVal = val is int ? val.toDouble() : (val as double);
      return doubleVal > max ? doubleVal : max;
    });
    return (topValue / total) * 100;
  }

  /// 生成推荐（获取未获得的勋章，按步数排序）
  static List<MedalProgress> recommendNext(List<MedalProgress> allProgresses) {
    // 只取未获得的勋章
    final unearned = allProgresses.where((p) => !p.earned).toList();

    // 按 stepsRemaining 排序（步数最少的最容易达成）
    unearned.sort((a, b) => a.stepsRemaining.compareTo(b.stepsRemaining));

    // 取前 3 个最容易的
    return unearned.take(3).toList();
  }

  /// 完整推荐流程
  static MedalRecommendation getRecommendations(
    TimelineSummary summary,
    int totalFocusMinutes,
    int completedCount,
    int totalCount,
    int earlyCompletionCount,
    int deadlineSprintCount,
    int courseCount,
    int maxDailyCourseCount,
    int screenTimeSeconds,
    int productiveScreenSeconds,
    int distractionScreenSeconds,
  ) {
    // 计算所有勋章的进度
    final allProgresses = allMedals.map((medal) {
      return calculateMedalProgress(
        medal,
        summary,
        totalFocusMinutes,
        completedCount,
        totalCount,
        earlyCompletionCount,
        deadlineSprintCount,
        courseCount,
        maxDailyCourseCount,
        screenTimeSeconds,
        productiveScreenSeconds,
        distractionScreenSeconds,
      );
    }).toList();

    // 获取已获得和未获得的勋章
    final earned = allProgresses.where((p) => p.earned).toList();
    final recommendations = recommendNext(allProgresses);

    return MedalRecommendation(
      topRecommendations: recommendations,
      allMedals: allProgresses,
      earnedMedals: earned,
    );
  }
}
