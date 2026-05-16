import 'dart:math';
import 'package:flutter/material.dart';
import '../models.dart';
import 'timeline_service.dart';
import 'pomodoro_service.dart';

/// ML-based analysis result for timeline data
class TimelineMLInsight {
  final String title;
  final String description;
  final double confidence; // [0, 1]
  final String category; // 'focus', 'completion', 'efficiency', 'pattern'
  final IconData icon;
  final List<String> supportingData;

  const TimelineMLInsight({
    required this.title,
    required this.description,
    required this.confidence,
    required this.category,
    this.icon = Icons.insights_rounded,
    this.supportingData = const [],
  });
}

/// Focus pattern prediction result
class FocusPatternPrediction {
  final int predictedOptimalHour; // 0-23
  final double confidence;
  final String
      patternType; // 'morning', 'afternoon', 'evening', 'night', 'distributed'
  final List<int> recommendedHours;
  final String reason;

  const FocusPatternPrediction({
    required this.predictedOptimalHour,
    required this.confidence,
    required this.patternType,
    required this.recommendedHours,
    required this.reason,
  });
}

/// Task completion prediction
class TaskCompletionPrediction {
  final double completionProbability; // [0, 1]
  final String riskLevel; // 'low', 'medium', 'high'
  final List<String> riskFactors;
  final List<String> recommendations;
  final double confidence;

  const TaskCompletionPrediction({
    required this.completionProbability,
    required this.riskLevel,
    required this.riskFactors,
    required this.recommendations,
    required this.confidence,
  });
}

/// ML service for timeline data analysis
class TimelineMLService {
  static final TimelineMLService instance = TimelineMLService._();
  TimelineMLService._();

  // Complexity keyword dictionaries for task analysis
  static const _highComplexityKeywords = [
    '复杂',
    '项目',
    '设计',
    '开发',
    '研究',
    '调研',
    '报告',
    '论文',
    '方案',
    '架构',
    '系统',
    '分析',
    '规划',
    '重构',
    '优化',
    '算法',
    '数据库',
    '部署',
    '迁移',
    '实现',
    '编写',
    '撰写',
    '策划',
    '毕业',
    '考试',
    '竞赛',
    '实验',
    '建模',
    '仿真',
  ];

  static const _lowComplexityKeywords = [
    '购买',
    '打印',
    '发送',
    '回复',
    '简单',
    '快速',
    '顺便',
    '清理',
    '备份',
    '下载',
    '上传',
    '提交',
    '确认',
    '浏览',
    '签收',
    '签到',
    '打卡',
    '取快递',
    '买东西',
    '发消息',
  ];

  /// Generate ML-based insights for the timeline screen
  Future<List<TimelineMLInsight>> generateInsights({
    required String username,
    required TimelineSummary summary,
    required int totalFocusMinutes,
    required int completedCount,
    required int totalCount,
    required int screenTimeSeconds,
    required int productiveScreenSeconds,
    required int distractionScreenSeconds,
    required int earlyCompletionCount,
    required int deadlineSprintCount,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final insights = <TimelineMLInsight>[];

    try {
      // Load historical data for pattern analysis
      final historicalData =
          await _loadHistoricalData(username, startDate, endDate);

      // 1. Focus pattern analysis
      final focusPattern =
          _analyzeFocusPattern(summary.hourlyDistribution, historicalData);
      if (focusPattern.confidence > 0.3) {
        final totalActivity =
            summary.hourlyDistribution.fold<int>(0, (a, b) => a + b);
        insights.add(TimelineMLInsight(
          title: '专注模式分析',
          description: _buildFocusPatternDescription(
              focusPattern, summary.hourlyDistribution, totalActivity),
          confidence: focusPattern.confidence,
          category: 'focus',
          icon: Icons.psychology_rounded,
          supportingData: [
            '最佳时段: ${focusPattern.predictedOptimalHour}:00',
            '模式: ${focusPattern.patternType}'
          ],
        ));
      }

      // 2. Task completion analysis
      final completionAnalysis = _analyzeTaskCompletion(
        summary,
        completedCount,
        totalCount,
        earlyCompletionCount,
        deadlineSprintCount,
      );
      if (completionAnalysis.confidence > 0.3) {
        insights.add(TimelineMLInsight(
          title: '任务执行分析',
          description: _buildCompletionDescription(
              completionAnalysis,
              completedCount,
              totalCount,
              earlyCompletionCount,
              deadlineSprintCount),
          confidence: completionAnalysis.confidence,
          category: 'completion',
          icon: Icons.task_alt_rounded,
          supportingData: completionAnalysis.riskFactors.take(2).toList(),
        ));
      }

      // 3. Efficiency pattern analysis
      final efficiencyInsight = _analyzeEfficiencyPattern(
        summary,
        screenTimeSeconds,
        productiveScreenSeconds,
        distractionScreenSeconds,
        totalFocusMinutes,
      );
      if (efficiencyInsight != null) {
        insights.add(efficiencyInsight);
      }

      // 4. Consistency analysis
      final consistencyInsight = _analyzeConsistency(summary, historicalData);
      if (consistencyInsight != null) {
        insights.add(consistencyInsight);
      }

      // 5. Subject diversity analysis
      final diversityInsight = _analyzeSubjectDiversity(summary);
      if (diversityInsight != null) {
        insights.add(diversityInsight);
      }

      // Sort by confidence
      insights.sort((a, b) => b.confidence.compareTo(a.confidence));
    } catch (e) {
      debugPrint('TimelineMLService error: $e');
    }

    return insights.take(5).toList();
  }

  /// Predict optimal focus hours based on historical patterns
  FocusPatternPrediction predictFocusPattern(List<int> hourlyDistribution) {
    return _analyzeFocusPattern(hourlyDistribution, []);
  }

  /// Predict task completion likelihood
  TaskCompletionPrediction predictTaskCompletion({
    required String taskTitle,
    required int plannedMinutes,
    required List<TodoItem> historicalTodos,
    required List<PomodoroRecord> historicalPomodoros,
  }) {
    return _predictTaskCompletion(
        taskTitle, plannedMinutes, historicalTodos, historicalPomodoros);
  }

  // === Internal Analysis Methods ===

  Future<List<_HistoricalSnapshot>> _loadHistoricalData(
    String username,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final snapshots = <_HistoricalSnapshot>[];

    try {
      // Load pomodoro records for the past 90 days
      final ninetyDaysAgo = startDate.subtract(const Duration(days: 90));
      final records =
          await PomodoroService.getRecordsInRange(ninetyDaysAgo, endDate);

      // Group by day
      final byDay = <String, List<PomodoroRecord>>{};
      for (final r in records) {
        final date = DateTime.fromMillisecondsSinceEpoch(r.createdAt);
        final key =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        byDay.putIfAbsent(key, () => []).add(r);
      }

      // Create snapshots
      for (final entry in byDay.entries) {
        final dayRecords = entry.value;
        final totalMinutes =
            dayRecords.fold<int>(0, (sum, r) => sum + r.effectiveDuration) ~/
                60;
        final completedCount = dayRecords
            .where((r) => r.status == PomodoroRecordStatus.completed)
            .length;

        snapshots.add(_HistoricalSnapshot(
          date: entry.key,
          focusMinutes: totalMinutes,
          completedSessions: completedCount,
          totalSessions: dayRecords.length,
        ));
      }
    } catch (e) {
      debugPrint('TimelineMLService: historical data load error: $e');
    }

    return snapshots;
  }

  FocusPatternPrediction _analyzeFocusPattern(
    List<int> hourlyDistribution,
    List<_HistoricalSnapshot> historicalData,
  ) {
    if (hourlyDistribution.length < 24) {
      return const FocusPatternPrediction(
        predictedOptimalHour: 9,
        confidence: 0.2,
        patternType: 'distributed',
        recommendedHours: [9, 10, 14, 15],
        reason: '数据不足，默认推荐上午时段',
      );
    }

    final totalActivity = hourlyDistribution.fold<int>(0, (a, b) => a + b);
    if (totalActivity == 0) {
      return const FocusPatternPrediction(
        predictedOptimalHour: 9,
        confidence: 0.2,
        patternType: 'distributed',
        recommendedHours: [9, 10, 14, 15],
        reason: '暂无专注数据',
      );
    }

    // Find peak hours
    final peakHour = hourlyDistribution.indexOf(hourlyDistribution.reduce(max));

    // Determine pattern type
    int morningActivity = 0,
        afternoonActivity = 0,
        eveningActivity = 0,
        nightActivity = 0;
    for (int i = 6; i < 12; i++) {
      morningActivity += hourlyDistribution[i];
    }
    for (int i = 12; i < 18; i++) {
      afternoonActivity += hourlyDistribution[i];
    }
    for (int i = 18; i < 23; i++) {
      eveningActivity += hourlyDistribution[i];
    }
    for (int i = 23; i < 24; i++) {
      nightActivity += hourlyDistribution[i];
    }
    for (int i = 0; i < 6; i++) {
      nightActivity += hourlyDistribution[i];
    }

    String patternType;
    List<int> recommendedHours;

    if (morningActivity > afternoonActivity &&
        morningActivity > eveningActivity) {
      patternType = 'morning';
      recommendedHours = [8, 9, 10, 11];
    } else if (afternoonActivity > morningActivity &&
        afternoonActivity > eveningActivity) {
      patternType = 'afternoon';
      recommendedHours = [14, 15, 16, 17];
    } else if (eveningActivity > morningActivity &&
        eveningActivity > afternoonActivity) {
      patternType = 'evening';
      recommendedHours = [19, 20, 21, 22];
    } else if (nightActivity > totalActivity * 0.3) {
      patternType = 'night';
      recommendedHours = [22, 23, 0, 1];
    } else {
      patternType = 'distributed';
      recommendedHours = [9, 10, 14, 15, 19, 20];
    }

    // Calculate confidence based on data quality
    final peakRatio = hourlyDistribution[peakHour] / totalActivity;
    final confidence = (peakRatio * 2).clamp(0.3, 0.9);

    return FocusPatternPrediction(
      predictedOptimalHour: peakHour,
      confidence: confidence,
      patternType: patternType,
      recommendedHours: recommendedHours,
      reason: '基于$totalActivity次专注数据分析',
    );
  }

  TaskCompletionPrediction _analyzeTaskCompletion(
    TimelineSummary summary,
    int completedCount,
    int totalCount,
    int earlyCompletionCount,
    int deadlineSprintCount,
  ) {
    final riskFactors = <String>[];
    final recommendations = <String>[];
    double completionProb = summary.todoCompletionRate;

    // Adjust based on early completion patterns
    if (earlyCompletionCount > 0) {
      completionProb += 0.1;
      recommendations.add('提前完成习惯良好');
    }

    // Adjust based on deadline sprint patterns
    if (deadlineSprintCount > completedCount * 0.5) {
      completionProb -= 0.15;
      riskFactors.add('较多截止前冲刺');
      recommendations.add('建议提前规划');
    }

    // Determine risk level
    String riskLevel;
    if (completionProb >= 0.7) {
      riskLevel = 'low';
    } else if (completionProb >= 0.4) {
      riskLevel = 'medium';
    } else {
      riskLevel = 'high';
    }

    if (riskFactors.isEmpty) {
      recommendations.add('保持当前节奏');
    }

    return TaskCompletionPrediction(
      completionProbability: completionProb.clamp(0.0, 1.0),
      riskLevel: riskLevel,
      riskFactors: riskFactors,
      recommendations: recommendations,
      confidence: 0.7,
    );
  }

  TaskCompletionPrediction _predictTaskCompletion(
    String taskTitle,
    int plannedMinutes,
    List<TodoItem> historicalTodos,
    List<PomodoroRecord> historicalPomodoros,
  ) {
    final riskFactors = <String>[];
    final recommendations = <String>[];
    double completionProb = 0.7; // Base probability

    // Analyze task complexity
    final lowerTitle = taskTitle.toLowerCase();
    bool isHighComplexity =
        _highComplexityKeywords.any((kw) => lowerTitle.contains(kw));
    bool isLowComplexity =
        _lowComplexityKeywords.any((kw) => lowerTitle.contains(kw));

    if (isHighComplexity) {
      completionProb -= 0.15;
      riskFactors.add('高复杂度任务');
      recommendations.add('建议拆分为小任务');
    } else if (isLowComplexity) {
      completionProb += 0.1;
    }

    // Analyze planned duration
    if (plannedMinutes > 120) {
      completionProb -= 0.1;
      riskFactors.add('计划时长较长');
      recommendations.add('考虑分段执行');
    } else if (plannedMinutes < 30) {
      completionProb += 0.05;
    }

    // Analyze historical completion rate
    if (historicalTodos.isNotEmpty) {
      final completedRate = historicalTodos.where((t) => t.isDone).length /
          historicalTodos.length;
      completionProb = (completionProb + completedRate) / 2;

      if (completedRate < 0.5) {
        riskFactors.add('历史完成率较低');
        recommendations.add('设置更现实的目标');
      }
    }

    // Determine risk level
    String riskLevel;
    if (completionProb >= 0.7) {
      riskLevel = 'low';
    } else if (completionProb >= 0.4) {
      riskLevel = 'medium';
    } else {
      riskLevel = 'high';
    }

    // Add general recommendations
    if (riskFactors.isEmpty) {
      recommendations.add('保持当前节奏');
    }

    return TaskCompletionPrediction(
      completionProbability: completionProb.clamp(0.0, 1.0),
      riskLevel: riskLevel,
      riskFactors: riskFactors,
      recommendations: recommendations,
      confidence: 0.6,
    );
  }

  TimelineMLInsight? _analyzeEfficiencyPattern(
    TimelineSummary summary,
    int screenTimeSeconds,
    int productiveScreenSeconds,
    int distractionScreenSeconds,
    int totalFocusMinutes,
  ) {
    if (screenTimeSeconds <= 0) return null;

    final focusRatio = (totalFocusMinutes * 60) / screenTimeSeconds;
    final productiveRatio = productiveScreenSeconds / screenTimeSeconds;
    final distractionRatio = distractionScreenSeconds / screenTimeSeconds;

    String description;
    double confidence;

    final focusPct = (focusRatio * 100).toStringAsFixed(1);
    final prodPct = (productiveRatio * 100).toStringAsFixed(1);
    final distractPct = (distractionRatio * 100).toStringAsFixed(1);

    if (focusRatio > 0.3 && productiveRatio > 0.6) {
      description = '专注转化率优秀（$focusPct%），屏幕时间高效利用，生产力占比$prodPct%';
      confidence = 0.8;
    } else if (focusRatio > 0.2 && productiveRatio > 0.4) {
      description = '专注转化率$focusPct%，生产力占比$prodPct%，可尝试减少碎片切换提升效率';
      confidence = 0.7;
    } else if (distractionRatio > 0.5) {
      description = '分心应用占比$distractPct%，严重挤压专注时间，建议设置应用限额';
      confidence = 0.75;
    } else {
      description = '专注转化率$focusPct%，生产力占比$prodPct%，建议固定使用习惯提高效率';
      confidence = 0.6;
    }

    return TimelineMLInsight(
      title: '效率模式分析',
      description: description,
      confidence: confidence,
      category: 'efficiency',
      icon: Icons.speed_rounded,
      supportingData: [
        '专注转化率: ${(focusRatio * 100).toStringAsFixed(1)}%',
        '生产力占比: ${(productiveRatio * 100).toStringAsFixed(1)}%',
      ],
    );
  }

  TimelineMLInsight? _analyzeConsistency(
    TimelineSummary summary,
    List<_HistoricalSnapshot> historicalData,
  ) {
    if (historicalData.length < 7) return null;

    // Calculate coefficient of variation for focus minutes
    final focusMinutes =
        historicalData.map((s) => s.focusMinutes.toDouble()).toList();
    final mean = focusMinutes.reduce((a, b) => a + b) / focusMinutes.length;
    if (mean == 0) return null;

    final variance = focusMinutes
            .map((m) => (m - mean) * (m - mean))
            .reduce((a, b) => a + b) /
        focusMinutes.length;
    final stddev = sqrt(variance);
    final cv = stddev / mean;

    String description;
    double confidence;

    final cvPct = (cv * 100).toStringAsFixed(0);
    final meanStr = mean.toStringAsFixed(0);

    if (cv < 0.3) {
      description = '日均专注 $meanStr 分钟，日间波动仅 $cvPct%，习惯高度稳定';
      confidence = 0.85;
    } else if (cv < 0.6) {
      description = '日均专注 $meanStr 分钟，波动系数 $cvPct%，周中有起伏但整体可控';
      confidence = 0.7;
    } else {
      description = '专注波动系数 $cvPct%，每日差异明显，建议固定时段形成规律';
      confidence = 0.75;
    }

    return TimelineMLInsight(
      title: '一致性分析',
      description: description,
      confidence: confidence,
      category: 'pattern',
      icon: Icons.show_chart_rounded,
      supportingData: [
        '连续活跃: ${summary.consecutiveActiveDays}天',
        '波动系数: ${(cv * 100).toStringAsFixed(0)}%',
      ],
    );
  }

  TimelineMLInsight? _analyzeSubjectDiversity(TimelineSummary summary) {
    if (summary.subjectDistribution.isEmpty) return null;

    final total =
        summary.subjectDistribution.values.fold<double>(0, (a, b) => a + b);
    if (total == 0) return null;

    // Calculate entropy
    double entropy = 0.0;
    for (final v in summary.subjectDistribution.values) {
      if (v > 0) {
        final p = v / total;
        entropy -= p * log(p);
      }
    }

    final maxEntropy =
        log(max(summary.subjectDistribution.length, 2).toDouble());
    final normalizedEntropy = maxEntropy > 0 ? entropy / maxEntropy : 0.0;

    String description;
    double confidence;

    final sortedSubjects = summary.subjectDistribution.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topSubject = sortedSubjects.first.key;
    final topCount = sortedSubjects.first.value;
    final topPct = (topCount * 100.0 / total).toStringAsFixed(1);
    final subjectCount = sortedSubjects.length;

    if (normalizedEntropy > 0.8) {
      description = '覆盖 $subjectCount 个学科，最高占比「$topSubject」$topPct%，分布均衡知识面广';
      confidence = 0.75;
    } else if (normalizedEntropy > 0.5) {
      final secondSubject =
          sortedSubjects.length > 1 ? sortedSubjects[1].key : '无';
      description =
          '覆盖 $subjectCount 个学科，「$topSubject」$topPct%，「$secondSubject」为辅';
      confidence = 0.7;
    } else {
      description = '高度集中于「$topSubject」（$topPct%），建议拓展其他领域保持平衡';
      confidence = 0.8;
    }

    return TimelineMLInsight(
      title: '学科分布分析',
      description: description,
      confidence: confidence,
      category: 'pattern',
      icon: Icons.pie_chart_rounded,
      supportingData: [
        '覆盖学科: ${summary.subjectDistribution.length}个',
        '均衡度: ${(normalizedEntropy * 100).toStringAsFixed(0)}%',
      ],
    );
  }

  String _buildFocusPatternDescription(FocusPatternPrediction prediction,
      List<int> hourlyDistribution, int totalActivity) {
    final hourStr = '${prediction.predictedOptimalHour}:00';
    final peakCount = hourlyDistribution[prediction.predictedOptimalHour];
    final peakPct = totalActivity > 0
        ? (peakCount * 100.0 / totalActivity).toStringAsFixed(1)
        : '0.0';

    switch (prediction.patternType) {
      case 'morning':
        return '晨型专注者，$hourStr 峰值 $peakCount 次（占 $peakPct%），上下午效率均集中';
      case 'afternoon':
        return '午后专注者，$hourStr 峰值 $peakCount 次（占 $peakPct%），下午${prediction.recommendedHours.first}:00-${prediction.recommendedHours.last}:00 最活跃';
      case 'evening':
        return '晚间专注者，$hourStr 峰值 $peakCount 次（占 $peakPct%），晚饭后效率明显高于白天';
      case 'night':
        return '夜猫型专注者，深夜活跃 $peakCount 次，凌晨时段效率高于常规时段';
      default:
        return '专注时间分布均匀，$hourStr 最高 $peakCount 次（占 $peakPct%），全天均可安排任务';
    }
  }

  String _buildCompletionDescription(
    TaskCompletionPrediction prediction,
    int completedCount,
    int totalCount,
    int earlyCompletionCount,
    int deadlineSprintCount,
  ) {
    final probStr =
        '${(prediction.completionProbability * 100).toStringAsFixed(0)}%';
    final completeRate = totalCount > 0
        ? (completedCount * 100.0 / totalCount).toStringAsFixed(0)
        : '0';

    switch (prediction.riskLevel) {
      case 'low':
        final parts = <String>[
          '已完成 $completedCount/$totalCount（$completeRate%）'
        ];
        if (earlyCompletionCount > 0) {
          parts.add('提前完成 $earlyCompletionCount 次');
        }
        return '任务完成概率 $probStr，${parts.join('，')}，节奏稳健';
      case 'medium':
        final parts = <String>['已完成 $completedCount/$totalCount'];
        if (deadlineSprintCount > 0) {
          parts.add('$deadlineSprintCount 次截止前冲刺');
        }
        parts.add(prediction.recommendations.first);
        return '完成概率 $probStr，${parts.join('，')}';
      case 'high':
        return '完成概率仅 $probStr（已完成 $completedCount/$totalCount），截止前冲刺 $deadlineSprintCount 次，${prediction.recommendations.first}';
      default:
        return '任务完成概率 $probStr，已完成 $completedCount/$totalCount';
    }
  }
}

/// Historical data snapshot for pattern analysis
class _HistoricalSnapshot {
  final String date;
  final int focusMinutes;
  final int completedSessions;
  final int totalSessions;

  const _HistoricalSnapshot({
    required this.date,
    required this.focusMinutes,
    required this.completedSessions,
    required this.totalSessions,
  });
}
