import 'dart:math';
import '../models/medal_ml_models.dart';
import 'medal_recommendation_service.dart';
import 'timeline_service.dart';

/// Extracts user behavior features and scores medals for ML-enhanced recommendations
class MedalFeatureExtractor {
  static const _categories = ['focus', 'completion', 'persistence', 'efficiency', 'breadth'];

  /// Extract user profile features from timeline summary + external params
  static UserProfileFeatures extractFeatures(
    TimelineSummary summary,
    int totalFocusMinutes,
    int completedCount,
    int totalCount,
    int earlyCompletionCount,
    int deadlineSprintCount,
    int screenTimeSeconds,
    int productiveScreenSeconds,
    int distractionScreenSeconds,
  ) {
    final affinity = <String, double>{};
    final velocity = <String, double>{};

    // Layer 1: Category affinities
    affinity['focus'] = _focusAffinity(summary, totalFocusMinutes);
    affinity['completion'] = _completionAffinity(summary, completedCount, totalCount, earlyCompletionCount, deadlineSprintCount);
    affinity['persistence'] = _persistenceAffinity(summary);
    affinity['efficiency'] = _efficiencyAffinity(summary, screenTimeSeconds, productiveScreenSeconds, distractionScreenSeconds);
    affinity['breadth'] = _breadthAffinity(summary);

    // Layer 2: Velocity = affinity * recencyFactor
    final recencyFactor = _computeRecencyFactor(summary);
    for (final cat in _categories) {
      velocity[cat] = (affinity[cat]! * recencyFactor).clamp(0.0, 1.0);
    }

    // Layer 3: Behavioral traits
    final motivationType = _deriveMotivationType(affinity, summary);
    final challengePreference = _computeChallengePreference(summary);
    final diversityNeed = _computeDiversityNeed(summary);

    return UserProfileFeatures(
      categoryAffinity: affinity,
      categoryVelocity: velocity,
      motivationType: motivationType,
      challengePreference: challengePreference,
      diversityNeed: diversityNeed,
      computedAt: DateTime.now(),
    );
  }

  /// Score a single medal based on user features
  static double scoreMedal(
    MedalProgress medal,
    UserProfileFeatures features,
    Map<String, int> earnedPerCategory,
  ) {
    // Dynamic weights based on motivation type
    final weights = _getWeights(features.motivationType);

    // Proximity: how close to completion (0-1)
    final proximity = medal.progress;

    // Affinity: user's natural strength in this category
    final affinity = features.categoryAffinity[medal.medal.category] ?? 0.5;

    // Velocity: current activity momentum in this category
    final vel = features.categoryVelocity[medal.medal.category] ?? 0.5;

    // Diversity bonus: encourage under-explored categories
    final maxEarned = earnedPerCategory.values.fold<int>(0, max);
    final earnedInCat = earnedPerCategory[medal.medal.category] ?? 0;
    final diversity = maxEarned > 0 ? (1.0 - earnedInCat / maxEarned).clamp(0.0, 1.0) : 0.5;

    // Challenge bonus: match difficulty to preference
    final challenge = _challengeBonus(medal.medal.priority, features.challengePreference);

    final score = weights['proximity']! * proximity
        + weights['affinity']! * affinity
        + weights['velocity']! * vel
        + weights['diversity']! * diversity
        + weights['challenge']! * challenge;

    return score.clamp(0.0, 1.0);
  }

  /// Score a medal and return individual component breakdown for reason generation
  static ScoreBreakdown scoreMedalWithBreakdown(
    MedalProgress medal,
    UserProfileFeatures features,
    Map<String, int> earnedPerCategory,
  ) {
    final proximity = medal.progress;
    final affinity = features.categoryAffinity[medal.medal.category] ?? 0.5;
    final vel = features.categoryVelocity[medal.medal.category] ?? 0.5;

    final maxEarned = earnedPerCategory.values.fold<int>(0, max);
    final earnedInCat = earnedPerCategory[medal.medal.category] ?? 0;
    final diversity = maxEarned > 0 ? (1.0 - earnedInCat / maxEarned).clamp(0.0, 1.0) : 0.5;

    final challenge = _challengeBonus(medal.medal.priority, features.challengePreference);

    final weights = _getWeights(features.motivationType);
    final total = (weights['proximity']! * proximity
        + weights['affinity']! * affinity
        + weights['velocity']! * vel
        + weights['diversity']! * diversity
        + weights['challenge']! * challenge).clamp(0.0, 1.0);

    return ScoreBreakdown(
      proximity: proximity,
      affinity: affinity,
      velocity: vel,
      diversity: diversity,
      challenge: challenge,
      total: total,
    );
  }

  // === Category Affinity Calculations ===

  static double _focusAffinity(TimelineSummary s, int totalFocusMinutes) {
    final volume = (totalFocusMinutes / 600).clamp(0.0, 1.0);
    final depth = (s.deepWorkCount / 10).clamp(0.0, 1.0);
    final quality = (1.0 - s.interruptionRate).clamp(0.0, 1.0);
    final consistency = (s.pomodoroCount / 50).clamp(0.0, 1.0);
    return (0.35 * volume + 0.25 * depth + 0.20 * quality + 0.20 * consistency).clamp(0.0, 1.0);
  }

  static double _completionAffinity(
    TimelineSummary s, int completedCount, int totalCount,
    int earlyCompletionCount, int deadlineSprintCount,
  ) {
    final rate = s.todoCompletionRate.clamp(0.0, 1.0);
    final early = (earlyCompletionCount / 10).clamp(0.0, 1.0);
    final volume = (completedCount / 50).clamp(0.0, 1.0);
    final sprint = (deadlineSprintCount / 10).clamp(0.0, 1.0);
    return (0.40 * rate + 0.25 * early + 0.20 * volume + 0.15 * sprint).clamp(0.0, 1.0);
  }

  static double _persistenceAffinity(TimelineSummary s) {
    final streak = (s.consecutiveActiveDays / 30).clamp(0.0, 1.0);
    final dailyRatio = _dailyActivityRatio(s);
    final weekend = _weekendActivityScore(s);
    final nightOwl = _nightOwlScore(s);
    return (0.40 * streak + 0.20 * dailyRatio + 0.20 * weekend + 0.20 * nightOwl).clamp(0.0, 1.0);
  }

  static double _efficiencyAffinity(
    TimelineSummary s, int screenTimeSeconds, int productiveScreenSeconds, int distractionScreenSeconds,
  ) {
    final focus = (1.0 - s.interruptionRate).clamp(0.0, 1.0);
    final screenProd = screenTimeSeconds > 0
        ? (productiveScreenSeconds / screenTimeSeconds).clamp(0.0, 1.0)
        : 0.5;
    final consistency = _consistencyScore(s);
    final completion = s.todoCompletionRate.clamp(0.0, 1.0);
    return (0.30 * focus + 0.25 * screenProd + 0.25 * consistency + 0.20 * completion).clamp(0.0, 1.0);
  }

  static double _breadthAffinity(TimelineSummary s) {
    final subjectCount = (s.subjectDistribution.length / 8).clamp(0.0, 1.0);
    final search = (s.searchCount / 20).clamp(0.0, 1.0);
    final entropy = _subjectEntropy(s);
    final exam = (s.examPrepCount / 10).clamp(0.0, 1.0);
    return (0.35 * subjectCount + 0.25 * search + 0.20 * entropy + 0.20 * exam).clamp(0.0, 1.0);
  }

  // === Helper Functions ===

  static double _dailyActivityRatio(TimelineSummary s) {
    if (s.actualStartTime == null || s.actualEndTime == null) return 0.0;
    final days = s.actualEndTime!.difference(s.actualStartTime!).inDays;
    if (days <= 0) return 1.0;
    return (s.consecutiveActiveDays / days).clamp(0.0, 1.0);
  }

  static double _weekendActivityScore(TimelineSummary s) {
    // Approximate: if streak > 7, user likely has weekend activity
    if (s.consecutiveActiveDays >= 7) return 0.8;
    if (s.consecutiveActiveDays >= 3) return 0.5;
    return 0.2;
  }

  static double _nightOwlScore(TimelineSummary s) {
    if (s.hourlyDistribution.length < 24) return 0.0;
    // Check activity in late hours (20-23, 0-4)
    int lateActivity = 0;
    for (int i = 20; i < 24; i++) {
      lateActivity += s.hourlyDistribution[i];
    }
    for (int i = 0; i < 5; i++) {
      lateActivity += s.hourlyDistribution[i];
    }
    final totalActivity = s.hourlyDistribution.fold<int>(0, (a, b) => a + b);
    if (totalActivity == 0) return 0.0;
    return (lateActivity / totalActivity).clamp(0.0, 1.0);
  }

  static double _consistencyScore(TimelineSummary s) {
    if (s.hourlyDistribution.length < 24) return 0.5;
    final activeHours = s.hourlyDistribution.where((h) => h > 0).toList();
    if (activeHours.length < 2) return 0.5;
    final mean = activeHours.fold<double>(0, (a, b) => a + b) / activeHours.length;
    if (mean == 0) return 0.5;
    final variance = activeHours.map((h) => (h - mean) * (h - mean)).fold<double>(0, (a, b) => a + b) / activeHours.length;
    final stddev = sqrt(variance);
    return (1.0 - (stddev / (mean + 1))).clamp(0.0, 1.0);
  }

  static double _subjectEntropy(TimelineSummary s) {
    if (s.subjectDistribution.isEmpty) return 0.0;
    final total = s.subjectDistribution.values.fold<double>(0, (a, b) => a + b);
    if (total == 0) return 0.0;
    double entropy = 0.0;
    for (final v in s.subjectDistribution.values) {
      if (v > 0) {
        final p = v / total;
        entropy -= p * log(p);
      }
    }
    final maxEntropy = log(max(s.subjectDistribution.length, 2));
    return maxEntropy > 0 ? (entropy / maxEntropy).clamp(0.0, 1.0) : 0.0;
  }

  static double _computeRecencyFactor(TimelineSummary s) {
    if (s.actualStartTime == null || s.actualEndTime == null) return 0.5;
    final spanDays = s.actualEndTime!.difference(s.actualStartTime!).inDays;
    // Shorter range = more recent/active → higher factor
    if (spanDays <= 1) return 1.0;
    if (spanDays <= 7) return 0.9;
    if (spanDays <= 30) return 0.7;
    if (spanDays <= 90) return 0.5;
    return 0.3; // All-time data
  }

  static String _deriveMotivationType(Map<String, double> affinity, TimelineSummary s) {
    final focusCompletion = (affinity['focus']! + affinity['completion']!) / 2;
    final breadthSearch = (affinity['breadth']! + (s.searchCount / 20).clamp(0.0, 1.0)) / 2;
    final efficiency = affinity['efficiency']!;

    if (focusCompletion >= breadthSearch && focusCompletion >= efficiency) return 'achiever';
    if (breadthSearch >= focusCompletion && breadthSearch >= efficiency) return 'explorer';
    return 'optimizer';
  }

  static double _computeChallengePreference(TimelineSummary s) {
    // Users with more deep work and longer streaks tend to prefer challenges
    final deepWorkSignal = (s.deepWorkCount / 10).clamp(0.0, 0.5);
    final streakSignal = (s.consecutiveActiveDays / 30).clamp(0.0, 0.5);
    return (deepWorkSignal + streakSignal).clamp(0.0, 1.0);
  }

  static double _computeDiversityNeed(TimelineSummary s) {
    if (s.subjectDistribution.isEmpty) return 0.5;
    final total = s.subjectDistribution.values.fold<double>(0, (a, b) => a + b);
    if (total == 0) return 0.5;
    final maxRatio = s.subjectDistribution.values.fold<double>(0, (m, v) => max(m, v / total));
    return (1.0 - maxRatio).clamp(0.0, 1.0);
  }

  static double _challengeBonus(int medalPriority, double challengePreference) {
    // High priority medals (4-5) get bonus if user prefers challenge
    // Low priority medals (1-2) get bonus if user doesn't
    if (medalPriority >= 4) return challengePreference;
    if (medalPriority <= 2) return 1.0 - challengePreference;
    return 0.5; // Medium priority is neutral
  }

  static Map<String, double> _getWeights(String motivationType) {
    switch (motivationType) {
      case 'achiever':
        return {'proximity': 0.45, 'affinity': 0.20, 'velocity': 0.15, 'diversity': 0.08, 'challenge': 0.12};
      case 'explorer':
        return {'proximity': 0.30, 'affinity': 0.15, 'velocity': 0.15, 'diversity': 0.25, 'challenge': 0.15};
      case 'optimizer':
        return {'proximity': 0.35, 'affinity': 0.20, 'velocity': 0.20, 'diversity': 0.10, 'challenge': 0.15};
      default:
        return {'proximity': 0.40, 'affinity': 0.25, 'velocity': 0.15, 'diversity': 0.10, 'challenge': 0.10};
    }
  }
}

/// Individual component scores for a medal, used to generate recommendation reasons
class ScoreBreakdown {
  final double proximity;
  final double affinity;
  final double velocity;
  final double diversity;
  final double challenge;
  final double total;

  const ScoreBreakdown({
    required this.proximity,
    required this.affinity,
    required this.velocity,
    required this.diversity,
    required this.challenge,
    required this.total,
  });
}
