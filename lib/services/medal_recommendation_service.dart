import 'dart:math';

import 'package:flutter/material.dart';

import '../utils/calendar_date_math.dart';
import 'medal_bandit_service.dart';
import 'medal_feature_extractor.dart';
import 'timeline_service.dart';

part 'medal_recommendation_catalog.dart';
part 'medal_recommendation_calculator.dart';

/// 勋章信息定义
class MedalInfo {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final String
  category; // 'focus', 'completion', 'persistence', 'efficiency', 'breadth'
  final int priority; // 1 (most motivating) to 5
  final bool isRepeatable;

  MedalInfo({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.category,
    required this.priority,
    this.isRepeatable = false,
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
  final DateTime? firstEarnedAt;
  final int earnedCount;

  MedalProgress({
    required this.medal,
    required this.progress,
    required this.earned,
    required this.nextMilestone,
    required this.stepsRemaining,
    this.earnedAt,
    this.firstEarnedAt,
    this.earnedCount = 0,
  });
}

/// 勋章推荐结果
class MedalRecommendation {
  final List<MedalProgress> topRecommendations; // 前3个最容易达成的
  final List<MedalProgress> allMedals; // 所有勋章及进度
  final List<MedalProgress> earnedMedals; // 已获得的勋章
  final bool isML; // 是否使用了 ML 推荐
  final Map<String, String> recommendReasons; // medalId → 推荐理由

  MedalRecommendation({
    required this.topRecommendations,
    required this.allMedals,
    required this.earnedMedals,
    this.isML = false,
    this.recommendReasons = const {},
  });
}

class MedalRecommendationService {
  // 定义所有 50 个勋章
  static final List<MedalInfo> allMedals = _allMedalCatalog;

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
  ) => _calculateMedalProgress(
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

  /// 计算顶部主题的占比
  static double _calculateTopSubjectRatio(TimelineSummary summary) {
    if (summary.subjectDistribution.isEmpty) return 0.0;
    final total = summary.subjectDistribution.values.fold<double>(
      0.0,
      (sum, val) => sum + val,
    );
    if (total == 0) return 0.0;
    final topValue = summary.subjectDistribution.values.fold<double>(
      0.0,
      (max, val) => val > max ? val : max,
    );
    return (topValue / total) * 100;
  }

  /// 生成推荐（获取未获得的勋章，按步数排序）
  static List<MedalProgress> recommendNext(List<MedalProgress> allProgresses) {
    final unearned = allProgresses
        .where((p) => !p.earned && p.progress < 1.0)
        .toList();
    unearned.sort((a, b) => a.stepsRemaining.compareTo(b.stepsRemaining));
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

    final earned = allProgresses.where((p) => p.earned).toList();
    final recommendations = recommendNext(allProgresses);

    return MedalRecommendation(
      topRecommendations: recommendations,
      allMedals: allProgresses,
      earnedMedals: earned,
    );
  }

  /// ML-enhanced recommendation: feature scoring + Thompson Sampling bandit
  /// Returns a full [MedalRecommendation] with isML=true and per-medal reasons.
  static Future<MedalRecommendation> recommendNextML(
    List<MedalProgress> allProgresses,
    TimelineSummary summary,
    int totalFocusMinutes,
    int completedCount,
    int totalCount,
    int earlyCompletionCount,
    int deadlineSprintCount,
    int screenTimeSeconds,
    int productiveScreenSeconds,
    int distractionScreenSeconds,
  ) async {
    try {
      final earned = allProgresses.where((p) => p.earned).toList();
      // Exclude anomalies: progress >= 1.0 but not marked earned
      final unearned = allProgresses
          .where((p) => !p.earned && p.progress < 1.0)
          .toList();
      if (unearned.isEmpty) {
        return MedalRecommendation(
          topRecommendations: [],
          allMedals: allProgresses,
          earnedMedals: earned,
          isML: true,
        );
      }

      // 1. Extract user features
      final features = MedalFeatureExtractor.extractFeatures(
        summary,
        totalFocusMinutes,
        completedCount,
        totalCount,
        earlyCompletionCount,
        deadlineSprintCount,
        screenTimeSeconds,
        productiveScreenSeconds,
        distractionScreenSeconds,
      );

      // 2. Compute earned medals per category for diversity bonus
      final earnedPerCategory = <String, int>{};
      for (final p in earned) {
        earnedPerCategory[p.medal.category] =
            (earnedPerCategory[p.medal.category] ?? 0) + 1;
      }

      // 3. Get bandit samples
      final banditService = MedalBanditService.instance;
      final banditSamples = await banditService.sampleAll(
        unearned.map((p) => p.medal.id).toList(),
      );

      // 4. Update outcomes from previous recommendations
      await banditService.updateOutcomes(allProgresses);
      final observationCounts = await banditService.getObservationCounts(
        unearned.map((p) => p.medal.id).toList(growable: false),
      );

      // 5. Score each medal and generate reasons
      final scored = <_ScoredEntry>[];
      for (final progress in unearned) {
        final breakdown = MedalFeatureExtractor.scoreMedalWithBreakdown(
          progress,
          features,
          earnedPerCategory,
        );
        final banditSample = banditSamples[progress.medal.id] ?? 0.5;
        final totalObs = observationCounts[progress.medal.id] ?? 0;
        final combined = _combinedScore(
          breakdown.total,
          banditSample,
          totalObs,
        );
        final reason = _generateReason(
          breakdown,
          progress,
          banditSample,
          totalObs,
        );
        scored.add(
          _ScoredEntry(progress: progress, score: combined, reason: reason),
        );
      }

      // 6. Sort by combined score descending, take top 3
      scored.sort((a, b) => b.score.compareTo(a.score));
      final top3 = scored.take(3).toList();

      // 7. Record impressions for bandit learning
      await banditService.recordImpressions(
        top3.map((s) => s.progress.medal.id).toList(),
      );

      // 8. Build reasons map
      final reasons = <String, String>{};
      for (final entry in top3) {
        reasons[entry.progress.medal.id] = entry.reason;
      }

      return MedalRecommendation(
        topRecommendations: top3.map((s) => s.progress).toList(),
        allMedals: allProgresses,
        earnedMedals: earned,
        isML: true,
        recommendReasons: reasons,
      );
    } catch (e) {
      // debugPrint('ML recommendation failed, falling back: $e');
      final fallback = recommendNext(allProgresses);
      return MedalRecommendation(
        topRecommendations: fallback,
        allMedals: allProgresses,
        earnedMedals: allProgresses.where((p) => p.earned).toList(),
        isML: false,
      );
    }
  }

  static String _generateReason(
    ScoreBreakdown breakdown,
    MedalProgress progress,
    double banditSample,
    int totalObs,
  ) {
    final parts = <String>[];

    // Proximity: strongest signal
    if (breakdown.proximity > 0.7) {
      parts.add('已完成 ${(progress.progress * 100).toInt()}%，距离解锁很近');
    } else if (breakdown.proximity > 0.4) {
      parts.add('进度 ${(progress.progress * 100).toInt()}%，稳步推进中');
    }

    // Category affinity
    if (breakdown.affinity > 0.6) {
      final catLabel = _categoryLabel(progress.medal.category);
      parts.add('匹配你擅长的$catLabel领域');
    }

    // Velocity: recent activity
    if (breakdown.velocity > 0.6) {
      parts.add('你最近在这个领域很活跃');
    }

    // Diversity: under-explored category
    if (breakdown.diversity > 0.6) {
      parts.add('拓展新的成就领域');
    }

    // Challenge preference
    if (breakdown.challenge > 0.7 && progress.medal.priority >= 4) {
      parts.add('适合你挑战高难度的习惯');
    } else if (breakdown.challenge > 0.7 && progress.medal.priority <= 2) {
      parts.add('轻松入门，建立信心');
    }

    // Bandit learning signal
    if (totalObs >= 10 && banditSample > 0.65) {
      parts.add('历史数据表明你倾向完成此类勋章');
    }

    if (parts.isEmpty) {
      parts.add('综合评估推荐');
    }

    return parts.join('；');
  }

  static String _categoryLabel(String category) {
    switch (category) {
      case 'focus':
        return '专注';
      case 'completion':
        return '完成';
      case 'persistence':
        return '坚持';
      case 'efficiency':
        return '效率';
      case 'breadth':
        return '广度';
      default:
        return category;
    }
  }

  /// Blend feature score with bandit sample.
  /// Cold start: 100% feature. After 50+ observations: 60% feature / 40% bandit.
  static double _combinedScore(
    double featureScore,
    double banditSample,
    int totalObservations,
  ) {
    final banditConfidence = (totalObservations / 50.0).clamp(0.0, 1.0);
    final banditWeight = 0.4 * banditConfidence;
    final featureWeight = 1.0 - banditWeight;
    return featureWeight * featureScore + banditWeight * banditSample;
  }
}

class _ScoredEntry {
  final MedalProgress progress;
  final double score;
  final String reason;
  const _ScoredEntry({
    required this.progress,
    required this.score,
    required this.reason,
  });
}
