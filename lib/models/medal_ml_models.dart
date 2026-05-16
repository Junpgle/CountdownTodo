// ML-based medal recommendation data models

/// User behavior profile extracted from TimelineSummary + external params
class UserProfileFeatures {
  /// Category affinity scores [0, 1] — one per medal category
  final Map<String, double> categoryAffinity;

  /// Category velocity scores [0, 1] — affinity weighted by recency
  final Map<String, double> categoryVelocity;

  /// Derived motivation type from behavior patterns
  final String motivationType; // 'achiever' | 'explorer' | 'optimizer'

  /// How much the user tends to tackle harder medals [0, 1]
  final double challengePreference;

  /// How much the user spreads across categories [0, 1]
  final double diversityNeed;

  final DateTime computedAt;

  const UserProfileFeatures({
    required this.categoryAffinity,
    required this.categoryVelocity,
    required this.motivationType,
    required this.challengePreference,
    required this.diversityNeed,
    required this.computedAt,
  });
}
