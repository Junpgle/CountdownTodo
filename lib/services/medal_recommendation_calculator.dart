part of 'medal_recommendation_service.dart';

MedalProgress _calculateMedalProgress(
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
  int earnedCount = 0;
  DateTime? firstEarnedAt;
  DateTime? earnedAt;

  switch (medal.id) {
    // === 原有勋章逻辑 ===
    case 'focus_starter':
      earned = summary.pomodoroCount >= 1;
      progress = earned ? 1.0 : (summary.pomodoroCount.clamp(0, 1).toDouble());
      stepsRemaining = earned ? 0 : 1;
      nextMilestone = earned ? '已获得' : '需要 1 次 Pomodoro';
      if (earned) {
        earnedCount = summary.pomodoroCount;
        firstEarnedAt = summary.actualStartTime;
        earnedAt = summary.actualEndTime;
      }
      break;

    case 'two_hour_guardian':
      progress = (totalFocusMinutes / 120).clamp(0.0, 1.0);
      earned = totalFocusMinutes >= 120;
      stepsRemaining = earned ? 0 : (120 - totalFocusMinutes);
      nextMilestone = earned ? '已获得' : '还需要 ${(120 - totalFocusMinutes)} 分钟';
      break;

    case 'eight_hour_trek':
      progress = (totalFocusMinutes / 480).clamp(0.0, 1.0);
      earned = totalFocusMinutes >= 480;
      stepsRemaining = earned ? 0 : (480 - totalFocusMinutes);
      nextMilestone = earned ? '已获得' : '还需要 ${(480 - totalFocusMinutes)} 分钟';
      break;

    case 'deep_worker':
      earned = summary.longestPomodoroMinutes >= 60;
      progress = (summary.longestPomodoroMinutes / 60).clamp(0.0, 1.0);
      stepsRemaining = earned ? 0 : 1;
      nextMilestone = earned
          ? '已获得'
          : '单次最长已达 ${summary.longestPomodoroMinutes} 分钟';
      break;

    case 'long_focus_specialist':
      earned = summary.longestPomodoroMinutes >= 90;
      progress = (summary.longestPomodoroMinutes / 90).clamp(0.0, 1.0);
      stepsRemaining = earned ? 0 : 1;
      nextMilestone = earned
          ? '已获得'
          : '单次最长已达 ${summary.longestPomodoroMinutes} 分钟';
      break;

    case 'stable_output':
      final lowInterruption = summary.interruptionRate <= 0.1;
      earned = lowInterruption && summary.pomodoroCount >= 3;
      progress = earned ? 1.0 : (summary.pomodoroCount / 3).clamp(0.0, 0.9);
      stepsRemaining = earned ? 0 : 1;
      nextMilestone = earned
          ? '已获得'
          : '中断率 ${(summary.interruptionRate * 100).toStringAsFixed(1)}%，需 ≤10%';
      break;

    case 'task_harvester':
      earned = completedCount >= 1;
      progress = earned ? 1.0 : 0.0;
      stepsRemaining = earned ? 0 : 1;
      nextMilestone = earned ? '已获得' : '完成第一个任务';
      if (earned) {
        earnedCount = completedCount;
        firstEarnedAt = summary.actualStartTime;
        earnedAt = summary.actualEndTime;
      }
      break;

    case 'plan_fulfiller':
      final rate = totalCount > 0 ? completedCount / totalCount : 0.0;
      progress = (rate / 0.8).clamp(0.0, 1.0);
      earned = rate >= 0.8 && totalCount >= 3;
      stepsRemaining = earned ? 0 : 1;
      nextMilestone = earned
          ? '已获得'
          : '当前完成率 ${(rate * 100).toStringAsFixed(0)}%，需达 80%';
      break;

    case 'early_deliverer':
      earned = earlyCompletionCount >= 1;
      progress = earned ? 1.0 : 0.0;
      stepsRemaining = earned ? 0 : 1;
      nextMilestone = earned ? '已获得' : '还需提前完成 1 个任务';
      break;

    case 'ddl_tamer':
      earned = deadlineSprintCount >= 1;
      progress = earned ? 1.0 : 0.0;
      stepsRemaining = earned ? 0 : 1;
      nextMilestone = earned ? '已获得' : '在 DDL 前完成 1 个任务';
      break;

    case 'night_efficiency_king':
      final isNightOwl = summary.peakHour >= 20 || summary.peakHour <= 5;
      earned = isNightOwl && totalFocusMinutes > 30;
      progress = earned ? 1.0 : 0.0;
      stepsRemaining = earned ? 0 : 1;
      nextMilestone = earned ? '已获得 (高峰: ${summary.peakHour}:00)' : '探索你的高效时段';
      break;

    case 'golden_hour':
      earned = summary.peakHour > 0;
      progress = earned ? 1.0 : 0.0;
      stepsRemaining = earned ? 0 : 1;
      nextMilestone = earned ? '已获得 (高峰: ${summary.peakHour}:00)' : '分析你的专注规律';
      break;

    case 'long_distance_runner':
      progress = (summary.consecutiveActiveDays / 3).clamp(0.0, 1.0);
      earned = summary.consecutiveActiveDays >= 3;
      stepsRemaining = earned ? 0 : (3 - summary.consecutiveActiveDays);
      nextMilestone = earned
          ? '已获得'
          : '当前连续活跃 ${summary.consecutiveActiveDays} 天';
      break;

    case 'learning_polymath':
      final subjectCount = summary.subjectDistribution.length;
      progress = (subjectCount / 4).clamp(0.0, 1.0);
      earned = subjectCount >= 4;
      stepsRemaining = earned ? 0 : (4 - subjectCount);
      nextMilestone = earned ? '已获得' : '当前涉及 $subjectCount 个学科，需 4 个';
      break;

    case 'main_line_pusher':
      final ratio = MedalRecommendationService._calculateTopSubjectRatio(
        summary,
      );
      progress = (ratio / 45).clamp(0.0, 1.0);
      earned = ratio >= 45 && totalFocusMinutes > 60;
      stepsRemaining = earned ? 0 : 1;
      nextMilestone = earned
          ? '已获得'
          : '最高主题占比 ${ratio.toStringAsFixed(0)}%，需达 45%';
      break;

    case 'knowledge_scout':
      progress = (summary.searchCount / 3).clamp(0.0, 1.0);
      earned = summary.searchCount >= 3;
      stepsRemaining = earned ? 0 : (3 - summary.searchCount);
      nextMilestone = earned ? '已获得' : '当前检索 ${summary.searchCount} 次，需 3 次';
      break;

    case 'exam_prep_sprinter':
      progress = (summary.examPrepCount / 3).clamp(0.0, 1.0);
      earned = summary.examPrepCount >= 3;
      stepsRemaining = earned ? 0 : (3 - summary.examPrepCount);
      nextMilestone = earned ? '已获得' : '当前备考 ${summary.examPrepCount} 次，需 3 次';
      break;

    case 'course_companion':
      earned = courseCount >= 1;
      progress = earned ? 1.0 : 0.0;
      stepsRemaining = earned ? 0 : 1;
      nextMilestone = earned ? '已获得' : '记录第一节课';
      break;

    case 'full_course_survivor':
      earned = maxDailyCourseCount >= 5;
      progress = (maxDailyCourseCount / 5).clamp(0.0, 1.0);
      stepsRemaining = earned ? 0 : 1;
      nextMilestone = earned ? '已获得' : '单日最高 $maxDailyCourseCount 节课，需 5 节';
      break;

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
      break;

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
      break;

    // === 新增扩展勋章逻辑 ===
    case 'focus_expert':
      progress = (totalFocusMinutes / (24 * 60)).clamp(0.0, 1.0);
      earned = totalFocusMinutes >= 24 * 60;
      stepsRemaining = earned ? 0 : (24 * 60 - totalFocusMinutes);
      nextMilestone = earned
          ? '已获得'
          : '还需要 ${(24 * 60 - totalFocusMinutes)} 分钟';
      break;

    case 'focus_legend':
      progress = (totalFocusMinutes / (100 * 60)).clamp(0.0, 1.0);
      earned = totalFocusMinutes >= 100 * 60;
      stepsRemaining = earned ? 0 : (100 * 60 - totalFocusMinutes);
      nextMilestone = earned
          ? '已获得'
          : '还需要 ${(100 * 60 - totalFocusMinutes)} 分钟';
      break;

    case 'pomo_runner':
      progress = (summary.pomodoroCount / 50).clamp(0.0, 1.0);
      earned = summary.pomodoroCount >= 50;
      stepsRemaining = earned ? 0 : (50 - summary.pomodoroCount);
      nextMilestone = earned ? '已获得' : '还需要 ${(50 - summary.pomodoroCount)} 个';
      if (earned) earnedCount = summary.pomodoroCount ~/ 50;
      break;

    case 'pomo_marathon':
      progress = (summary.pomodoroCount / 200).clamp(0.0, 1.0);
      earned = summary.pomodoroCount >= 200;
      stepsRemaining = earned ? 0 : (200 - summary.pomodoroCount);
      nextMilestone = earned ? '已获得' : '还需要 ${(200 - summary.pomodoroCount)} 个';
      if (earned) earnedCount = summary.pomodoroCount ~/ 200;
      break;

    case 'ultra_focus':
      earned = summary.longestPomodoroMinutes >= 120;
      progress = (summary.longestPomodoroMinutes / 120).clamp(0.0, 1.0);
      nextMilestone = earned
          ? '已获得'
          : '单次最高 ${summary.longestPomodoroMinutes} 分钟';
      break;

    case 'distraction_immune':
      earned = summary.interruptionRate == 0 && summary.pomodoroCount >= 5;
      progress = (summary.pomodoroCount / 5).clamp(0.0, 1.0);
      nextMilestone = earned ? '已获得' : '连续 5 次无中断';
      break;

    case 'task_millionaire':
      progress = (completedCount / 50).clamp(0.0, 1.0);
      earned = completedCount >= 50;
      if (earned) earnedCount = completedCount ~/ 50;
      nextMilestone = earned ? '已获得' : '还需完成 ${(50 - completedCount)} 个';
      break;

    case 'task_emperor':
      progress = (completedCount / 500).clamp(0.0, 1.0);
      earned = completedCount >= 500;
      if (earned) earnedCount = completedCount ~/ 500;
      nextMilestone = earned ? '已获得' : '还需完成 ${(500 - completedCount)} 个';
      break;

    case 'early_bird':
      int earlySessions = summary.hourlyDistribution
          .sublist(5, 8)
          .fold(0, (a, b) => a + b);
      progress = (earlySessions / 10).clamp(0.0, 1.0);
      earned = earlySessions >= 10;
      nextMilestone = earned ? '已获得' : '还需 ${(10 - earlySessions)} 次早起专注';
      break;

    case 'night_owl':
      int lateSessions = summary.hourlyDistribution
          .sublist(0, 4)
          .fold(0, (a, b) => a + b);
      progress = (lateSessions / 10).clamp(0.0, 1.0);
      earned = lateSessions >= 10;
      nextMilestone = earned ? '已获得' : '还需 ${(10 - lateSessions)} 次深夜专注';
      break;

    case 'weekend_warrior':
      earned = summary.weekendFocusMinutes >= 300;
      progress = (summary.weekendFocusMinutes / 300).clamp(0.0, 1.0);
      stepsRemaining = earned ? 0 : 1;
      nextMilestone = earned ? '已获得' : '周末累计专注超 5 小时即可获得';
      break;

    case 'productivity_spike':
      earned = summary.mostProductiveDayCompletedCount >= 10;
      progress = (summary.mostProductiveDayCompletedCount / 10).clamp(0.0, 1.0);
      stepsRemaining = earned ? 0 : 1;
      nextMilestone = earned ? '已获得' : '单日完成任务数量达标即可获得';
      break;

    case 'perfect_week':
      progress = (summary.consecutiveActiveDays / 7).clamp(0.0, 1.0);
      earned = summary.consecutiveActiveDays >= 7;
      nextMilestone = earned
          ? '已获得'
          : '当前连续活跃 ${summary.consecutiveActiveDays} 天';
      break;

    case 'persistence_hero':
      progress = (summary.consecutiveActiveDays / 30).clamp(0.0, 1.0);
      earned = summary.consecutiveActiveDays >= 30;
      nextMilestone = earned
          ? '已获得'
          : '当前连续活跃 ${summary.consecutiveActiveDays} 天';
      break;

    case 'monthly_checkin':
      earned = summary.consecutiveActiveDays >= 20;
      progress = (summary.consecutiveActiveDays / 20).clamp(0.0, 1.0);
      nextMilestone = earned
          ? '已获得'
          : '活跃天数还需 ${20 - summary.consecutiveActiveDays} 天';
      break;

    case 'steady_pulse':
      {
        final trend = summary.dailyTrend;
        final streak = summary.consecutiveActiveDays;
        bool stable = false;
        if (trend.length >= 5) {
          final last5 = trend.sublist(trend.length - 5);
          final mean = last5.fold<double>(0, (a, b) => a + b) / 5;
          if (mean > 0) {
            final variance =
                last5
                    .map((v) => (v - mean) * (v - mean))
                    .fold<double>(0, (a, b) => a + b) /
                5;
            final cv = sqrt(variance) / mean;
            stable = cv < 0.2;
          }
        }
        earned = stable && streak >= 5;
        progress = earned
            ? 1.0
            : (streak / 5).clamp(0.0, 0.9) * (stable ? 1.0 : 0.6);
        stepsRemaining = earned ? 0 : 1;
        nextMilestone = earned ? '已获得' : '每日专注时长波动较大，需连续 5 天保持稳定';
      }
      break;

    case 'efficiency_demon':
      earned = summary.interruptionRate <= 0.05 && totalFocusMinutes > 120;
      progress = earned
          ? 1.0
          : ((summary.interruptionRate <= 0.05 && totalFocusMinutes > 60)
                ? 0.8
                : 0.5);
      nextMilestone = earned
          ? '已获得'
          : '中断率 ${(summary.interruptionRate * 100).toStringAsFixed(1)}%，专注需超 120 分钟';
      break;

    case 'screen_time_slayer':
      earned =
          summary.interruptionRate <= 0.1 && summary.consecutiveActiveDays >= 7;
      progress = earned
          ? 1.0
          : (1.0 - summary.interruptionRate) *
                (summary.consecutiveActiveDays / 7).clamp(0.0, 1.0);
      stepsRemaining = earned ? 0 : 1;
      nextMilestone = earned ? '已获得' : '保持低分心率连续 7 天即可获得';
      break;

    case 'knowledge_glutton':
      progress = (summary.searchCount / 50).clamp(0.0, 1.0);
      earned = summary.searchCount >= 50;
      if (earned) earnedCount = summary.searchCount ~/ 50;
      nextMilestone = earned ? '已获得' : '还需检索 ${50 - summary.searchCount} 次';
      break;

    case 'exam_conqueror':
      progress = (summary.examPrepCount / 20).clamp(0.0, 1.0);
      earned = summary.examPrepCount >= 20;
      if (earned) earnedCount = summary.examPrepCount ~/ 20;
      nextMilestone = earned ? '已获得' : '还需备考 ${20 - summary.examPrepCount} 次';
      break;

    case 'deep_diver':
      progress = (summary.deepWorkCount / 10).clamp(0.0, 1.0);
      earned = summary.deepWorkCount >= 10;
      if (earned) earnedCount = summary.deepWorkCount ~/ 10;
      nextMilestone = earned ? '已获得' : '还需深度专注 ${10 - summary.deepWorkCount} 次';
      break;

    case 'course_veteran':
      progress = (courseCount / 50).clamp(0.0, 1.0);
      earned = courseCount >= 50;
      if (earned) earnedCount = courseCount ~/ 50;
      nextMilestone = earned ? '已获得' : '还需上课 ${50 - courseCount} 节';
      break;

    case 'no_skip_champion':
      earned = summary.todoCompletionRate >= 0.95 && totalCount > 5;
      progress = earned
          ? 1.0
          : (totalCount > 0
                ? (summary.todoCompletionRate *
                      (totalCount / 6).clamp(0.0, 1.0))
                : 0.0);
      nextMilestone = earned
          ? '已获得'
          : '完成率 ${(summary.todoCompletionRate * 100).toStringAsFixed(0)}%，需达 95% 且任务数 > 5';
      break;

    case 'sync_pioneer':
      earned = true;
      progress = 1.0;
      nextMilestone = '已开启云端生活';
      break;

    case 'island_resident':
      earned = totalFocusMinutes >= 600;
      progress = (totalFocusMinutes / 600).clamp(0.0, 1.0);
      nextMilestone = earned ? '已获得' : '岛屿停留时长还需 ${600 - totalFocusMinutes} 分钟';
      break;

    case 'focus_streak_5':
      {
        final hourly = summary.hourlyDistribution;
        final maxInHour = hourly.isEmpty ? 0 : hourly.reduce(max);
        earned = maxInHour >= 5;
        progress = (maxInHour / 5).clamp(0.0, 1.0);
        stepsRemaining = earned ? 0 : 1;
        nextMilestone = earned ? '已获得' : '单日内连续 5 个番茄钟即可获得';
      }
      break;

    case 'multi_tasker':
      earned = summary.subjectDistribution.length >= 3;
      progress = (summary.subjectDistribution.length / 3).clamp(0.0, 1.0);
      nextMilestone = '全能学习选手';
      break;

    case 'early_finisher_50':
      progress = (earlyCompletionCount / 50).clamp(0.0, 1.0);
      earned = earlyCompletionCount >= 50;
      if (earned) earnedCount = earlyCompletionCount ~/ 50;
      nextMilestone = earned
          ? '已获得'
          : '还需提前完成 ${50 - earlyCompletionCount} 个任务';
      break;

    case 'deadline_survivor_20':
      progress = (deadlineSprintCount / 20).clamp(0.0, 1.0);
      earned = deadlineSprintCount >= 20;
      if (earned) earnedCount = deadlineSprintCount ~/ 20;
      nextMilestone = earned
          ? '已获得'
          : '还需在 DDL 当天完成 ${20 - deadlineSprintCount} 个任务';
      break;

    // === Category: Subject Specialists (10个) ===
    case 'subject_mathematician':
      final mathMins =
          (summary.subjectDistribution['数学'] ?? 0) +
          (summary.subjectDistribution['理科'] ?? 0);
      progress = (mathMins / (20 * 60)).clamp(0.0, 1.0);
      earned = mathMins >= 20 * 60;
      nextMilestone = earned
          ? '已获得'
          : '数学理科类还需专注 ${(20 * 60 - mathMins).toInt()} 分钟';
      break;
    case 'subject_linguist':
      final langMins = summary.subjectDistribution['语言'] ?? 0;
      progress = (langMins / (20 * 60)).clamp(0.0, 1.0);
      earned = langMins >= 20 * 60;
      nextMilestone = earned
          ? '已获得'
          : '语言类还需专注 ${(20 * 60 - langMins).toInt()} 分钟';
      break;
    case 'subject_coder':
      final codeMins =
          (summary.subjectDistribution['编程'] ?? 0) +
          (summary.subjectDistribution['计算机'] ?? 0);
      progress = (codeMins / (20 * 60)).clamp(0.0, 1.0);
      earned = codeMins >= 20 * 60;
      nextMilestone = earned
          ? '已获得'
          : '编程类还需专注 ${(20 * 60 - codeMins).toInt()} 分钟';
      break;
    case 'subject_artist':
      final artMins =
          (summary.subjectDistribution['艺术'] ?? 0) +
          (summary.subjectDistribution['设计'] ?? 0);
      progress = (artMins / (20 * 60)).clamp(0.0, 1.0);
      earned = artMins >= 20 * 60;
      nextMilestone = earned
          ? '已获得'
          : '艺术类还需专注 ${(20 * 60 - artMins).toInt()} 分钟';
      break;
    case 'subject_scientist':
      final sciMins =
          (summary.subjectDistribution['科学'] ?? 0) +
          (summary.subjectDistribution['实验'] ?? 0);
      progress = (sciMins / (20 * 60)).clamp(0.0, 1.0);
      earned = sciMins >= 20 * 60;
      nextMilestone = earned
          ? '已获得'
          : '科学类还需专注 ${(20 * 60 - sciMins).toInt()} 分钟';
      break;
    case 'subject_historian':
      final histMins =
          (summary.subjectDistribution['历史'] ?? 0) +
          (summary.subjectDistribution['社科'] ?? 0);
      progress = (histMins / (20 * 60)).clamp(0.0, 1.0);
      earned = histMins >= 20 * 60;
      nextMilestone = earned
          ? '已获得'
          : '历史社科类还需专注 ${(20 * 60 - histMins).toInt()} 分钟';
      break;
    case 'subject_athlete':
      final fitMins =
          (summary.subjectDistribution['体育'] ?? 0) +
          (summary.subjectDistribution['健身'] ?? 0);
      progress = (fitMins / (20 * 60)).clamp(0.0, 1.0);
      earned = fitMins >= 20 * 60;
      nextMilestone = earned
          ? '已获得'
          : '体育健身类还需专注 ${(20 * 60 - fitMins).toInt()} 分钟';
      break;
    case 'subject_musician':
      final musicMins = summary.subjectDistribution['音乐'] ?? 0;
      progress = (musicMins / (20 * 60)).clamp(0.0, 1.0);
      earned = musicMins >= 20 * 60;
      nextMilestone = earned
          ? '已获得'
          : '音乐类还需专注 ${(20 * 60 - musicMins).toInt()} 分钟';
      break;
    case 'subject_bookworm':
      final readMins =
          (summary.subjectDistribution['阅读'] ?? 0) +
          (summary.subjectDistribution['文学'] ?? 0);
      progress = (readMins / (20 * 60)).clamp(0.0, 1.0);
      earned = readMins >= 20 * 60;
      nextMilestone = earned
          ? '已获得'
          : '文学类还需专注 ${(20 * 60 - readMins).toInt()} 分钟';
      break;
    case 'subject_polyglot':
      final deepSubjects = summary.subjectDistribution.values
          .where((v) => v >= 5 * 60)
          .length;
      progress = (deepSubjects / 5).clamp(0.0, 1.0);
      earned = deepSubjects >= 5;
      nextMilestone = earned ? '已获得' : '当前 $deepSubjects 个学科达 5 小时，需 5 个';
      break;

    // === Category: Habit Masters (10个) ===
    case 'habit_early_riser':
      // 假设通过 hourlyDistribution[5-7] 模拟晨间天数统计
      int earlyDays =
          summary.hourlyDistribution.sublist(5, 8).fold(0, (a, b) => a + b) ~/
          2; // 近似
      progress = (earlyDays / 30).clamp(0.0, 1.0);
      earned = earlyDays >= 30;
      nextMilestone = earned ? '已获得' : '还需早起专注 ${30 - earlyDays} 天';
      break;
    case 'habit_night_reader':
      int nightDays =
          summary.hourlyDistribution
              .sublist(23)
              .fold(0, (a, b) => a + (b > 0 ? 1 : 0)) +
          summary.hourlyDistribution
              .sublist(0, 2)
              .fold(0, (a, b) => a + (b > 0 ? 1 : 0));
      progress = (nightDays / 30).clamp(0.0, 1.0);
      earned = nightDays >= 30;
      nextMilestone = earned ? '已获得' : '还需深夜专注 ${30 - nightDays} 天';
      break;
    case 'habit_lunch_warrior':
      int lunchDays = summary.hourlyDistribution
          .sublist(12, 14)
          .fold(0, (a, b) => a + (b > 0 ? 1 : 0));
      progress = (lunchDays / 20).clamp(0.0, 1.0);
      earned = lunchDays >= 20;
      nextMilestone = earned ? '已获得' : '还需午间专注 ${20 - lunchDays} 天';
      break;
    case 'habit_streak_100':
      progress = (summary.consecutiveActiveDays / 100).clamp(0.0, 1.0);
      earned = summary.consecutiveActiveDays >= 100;
      stepsRemaining = earned ? 0 : 1;
      nextMilestone = earned ? '已获得' : '连续活跃 100 天即可获得';
      break;
    case 'habit_weekly_streak_10':
      earned = summary.consecutiveActiveDays >= 70;
      progress = (summary.consecutiveActiveDays / 70).clamp(0.0, 1.0);
      stepsRemaining = earned ? 0 : 1;
      nextMilestone = earned ? '已获得' : '连续 10 周每周活跃即可获得';
      break;
    case 'habit_monthly_champion':
      earned = summary.monthlyActiveDays >= 28;
      progress = (summary.monthlyActiveDays / 28).clamp(0.0, 1.0);
      stepsRemaining = earned ? 0 : 1;
      nextMilestone = earned ? '已获得' : '本月活跃 28 天即可获得';
      break;
    case 'habit_year_companion':
      {
        final spanDays =
            summary.actualStartTime != null && summary.actualEndTime != null
            ? CalendarDateMath.daysBetween(
                summary.actualStartTime!,
                summary.actualEndTime!,
              )
            : 0;
        progress = (spanDays / 365).clamp(0.0, 1.0);
        earned = spanDays >= 365;
        stepsRemaining = earned ? 0 : 1;
        nextMilestone = earned ? '已获得' : '累计使用 365 天即可获得';
      }
      break;
    case 'habit_streak_resurrection':
      earned = summary.consecutiveActiveDays >= 7;
      progress = (summary.consecutiveActiveDays / 7).clamp(0.0, 1.0);
      nextMilestone = '断签后的强势回归';
      break;
    case 'habit_weekend_pro':
      earned =
          summary.consecutiveActiveDays >= 28 &&
          summary.weekendFocusMinutes >= 960;
      progress =
          ((summary.consecutiveActiveDays / 28) *
                  (summary.weekendFocusMinutes / 960))
              .clamp(0.0, 1.0);
      stepsRemaining = earned ? 0 : 1;
      nextMilestone = earned ? '已获得' : '连续 4 个周末高强度专注即可获得';
      break;
    case 'habit_rhythm_master':
      earned = summary.consecutiveActiveDays >= 7;
      progress = (summary.consecutiveActiveDays / 7).clamp(0.0, 1.0);
      nextMilestone = earned
          ? '已获得'
          : '当前连续 ${summary.consecutiveActiveDays} 天，需 7 天';
      break;

    // === Category: Productivity Ninja (10个) ===
    case 'ninja_speed_demon':
      earned = earlyCompletionCount > 5;
      progress = (earlyCompletionCount / 5).clamp(0.0, 1.0);
      nextMilestone = earned ? '已获得' : '还需提前完成 ${5 - earlyCompletionCount} 个任务';
      break;
    case 'ninja_bulk_completer':
      earned = completedCount >= 5;
      progress = (completedCount / 5).clamp(0.0, 1.0);
      nextMilestone = earned ? '已获得' : '还需完成 ${5 - completedCount} 个任务';
      break;
    case 'ninja_focus_block_4':
      earned = totalFocusMinutes >= 4 * 60;
      progress = (totalFocusMinutes / 240).clamp(0.0, 1.0);
      break;
    case 'ninja_focus_block_8':
      earned = totalFocusMinutes >= 8 * 60;
      progress = (totalFocusMinutes / 480).clamp(0.0, 1.0);
      break;
    case 'ninja_deep_diver_3h':
      earned = summary.longestPomodoroMinutes >= 180;
      progress = (summary.longestPomodoroMinutes / 180).clamp(0.0, 1.0);
      break;
    case 'ninja_zero_distraction':
      earned = distractionScreenSeconds == 0 && totalFocusMinutes > 60;
      progress = earned ? 1.0 : 0.0;
      break;
    case 'ninja_planned_perfection':
      earned = totalCount > 0 && completedCount == totalCount;
      progress = earned ? 1.0 : 0.0;
      break;
    case 'ninja_inbox_zero':
      earned = totalCount > 0 && completedCount == totalCount;
      progress = totalCount > 0
          ? (completedCount / totalCount).clamp(0.0, 1.0)
          : 0.0;
      nextMilestone = earned ? '已获得' : '还有 ${totalCount - completedCount} 个未完成';
      break;
    case 'ninja_consistency_king':
      earned = summary.consecutiveActiveDays >= 7;
      progress = (summary.consecutiveActiveDays / 7).clamp(0.0, 1.0);
      nextMilestone = earned
          ? '已获得'
          : '当前连续 ${summary.consecutiveActiveDays} 天，需 7 天';
      break;
    case 'ninja_efficiency_max':
      final effRatio = screenTimeSeconds > 0
          ? (productiveScreenSeconds / screenTimeSeconds)
          : 0.0;
      earned = effRatio >= 0.98;
      progress = effRatio;
      break;

    // === Category: Academic Excellence (10个) ===
    case 'academic_course_100':
      progress = (courseCount / 100).clamp(0.0, 1.0);
      earned = courseCount >= 100;
      break;
    case 'academic_exam_overlord':
      progress = (summary.examPrepCount / 50).clamp(0.0, 1.0);
      earned = summary.examPrepCount >= 50;
      break;
    case 'academic_search_guru':
      progress = (summary.searchCount / 100).clamp(0.0, 1.0);
      earned = summary.searchCount >= 100;
      break;
    case 'academic_early_finish_diamond':
      progress = (earlyCompletionCount / 100).clamp(0.0, 1.0);
      earned = earlyCompletionCount >= 100;
      break;
    case 'academic_no_skip_month':
      earned = summary.consecutiveActiveDays >= 30;
      progress = (summary.consecutiveActiveDays / 30).clamp(0.0, 1.0);
      nextMilestone = earned
          ? '已获得'
          : '当前连续 ${summary.consecutiveActiveDays} 天，需 30 天';
      break;
    case 'academic_full_house_7':
      earned = maxDailyCourseCount >= 7;
      progress = (maxDailyCourseCount / 7).clamp(0.0, 1.0);
      break;
    case 'academic_bridge_builder':
      earned = summary.searchCount >= 20 && summary.pomodoroCount >= 20;
      progress = ((summary.searchCount / 20 + summary.pomodoroCount / 20) / 2)
          .clamp(0.0, 1.0);
      nextMilestone = earned
          ? '已获得'
          : '检索 ${summary.searchCount}/20，专注 ${summary.pomodoroCount}/20';
      break;
    case 'academic_library_phantom':
      final libMins = summary.subjectDistribution['图书馆'] ?? 0;
      progress = (libMins / (50 * 60)).clamp(0.0, 1.0);
      earned = libMins >= 50 * 60;
      break;
    case 'academic_top_of_class':
      earned = totalFocusMinutes > 5000;
      progress = (totalFocusMinutes / 5000).clamp(0.0, 1.0);
      nextMilestone = earned ? '已获得' : '还需专注 ${5000 - totalFocusMinutes} 分钟';
      break;
    case 'academic_deep_thinker':
      progress = (summary.deepWorkCount / 50).clamp(0.0, 1.0);
      earned = summary.deepWorkCount >= 50;
      break;

    // === Category: App Explorer (10个) ===
    case 'explorer_widget_loyalist':
      earned = true; // 无法直接检测，暂定已体验
      progress = 1.0;
      break;
    case 'explorer_island_pro_100':
      progress = (totalFocusMinutes / 6000).clamp(0.0, 1.0);
      earned = totalFocusMinutes >= 6000;
      break;
    case 'explorer_sync_master':
      earned = true;
      progress = 1.0;
      break;
    case 'explorer_countdown_master':
      earned = true;
      progress = 1.0;
      break;
    case 'explorer_reminder_loyalist':
      earned = true;
      progress = 1.0;
      break;
    case 'explorer_report_analyzer':
      earned = true;
      progress = 1.0;
      break;
    case 'explorer_multi_subject_10':
      earned = summary.subjectDistribution.length >= 10;
      progress = (summary.subjectDistribution.length / 10).clamp(0.0, 1.0);
      break;
    case 'explorer_pathfinder_10':
      earned = summary.searchCount >= 10;
      progress = (summary.searchCount / 10).clamp(0.0, 1.0);
      nextMilestone = earned ? '已获得' : '还需探索 ${10 - summary.searchCount} 个领域';
      break;
    case 'explorer_night_watch':
      int lateSessions = summary.hourlyDistribution
          .sublist(2, 5)
          .fold(0, (a, b) => a + b);
      earned = lateSessions > 0;
      progress = earned ? 1.0 : 0.0;
      break;
    case 'explorer_app_pioneer':
      earned = true;
      progress = 1.0;
      break;

    default:
      progress = 0.0;
      stepsRemaining = 1;
      nextMilestone = '待实现';
      break;
  }

  return MedalProgress(
    medal: medal,
    progress: progress,
    earned: earned,
    nextMilestone: nextMilestone,
    stepsRemaining: stepsRemaining,
    earnedCount: earnedCount,
    firstEarnedAt: firstEarnedAt,
    earnedAt: earnedAt,
  );
}
