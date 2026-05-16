import 'package:flutter/foundation.dart';
import 'database_helper.dart';

/// Tracks user accept/reject feedback on classification suggestions
/// and provides Bayesian-adjusted scores for future recommendations.
class SuggestionFeedbackService {
  /// Record a feedback event.
  static Future<void> record({
    required List<String> keywords,
    required String suggestionType, // 'group', 'priority', 'tag'
    required String suggestedValue,
    required bool accepted,
  }) async {
    if (keywords.isEmpty) return;
    try {
      final db = await DatabaseHelper.instance.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      final batch = db.batch();
      for (final kw in keywords) {
        batch.insert('suggestion_feedback', {
          'keyword': kw.toLowerCase(),
          'suggestion_type': suggestionType,
          'suggested_value': suggestedValue,
          'accepted': accepted ? 1 : 0,
          'created_at': now,
        });
      }
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('SuggestionFeedback.record error: $e');
    }
  }

  /// Get posterior acceptance rate for a specific value given matched keywords.
  /// Returns a score in [0, 1], or null if no feedback data exists.
  static Future<double?> getPosterior({
    required List<String> keywords,
    required String suggestionType,
    required String suggestedValue,
  }) async {
    if (keywords.isEmpty) return null;
    try {
      final db = await DatabaseHelper.instance.database;
      final placeholders = List.filled(keywords.length, '?').join(',');
      final rows = await db.rawQuery('''
        SELECT
          SUM(CASE WHEN accepted = 1 THEN 1 ELSE 0 END) AS accepted_count,
          COUNT(*) AS total_count
        FROM suggestion_feedback
        WHERE keyword IN ($placeholders)
          AND suggestion_type = ?
          AND suggested_value = ?
      ''', [...keywords.map((k) => k.toLowerCase()), suggestionType, suggestedValue]);

      if (rows.isEmpty) return null;
      final acceptedCount = (rows.first['accepted_count'] as int?) ?? 0;
      final totalCount = (rows.first['total_count'] as int?) ?? 0;
      if (totalCount < 2) return null; // need at least 2 data points

      // Beta(1,1) prior: (accepted + 1) / (total + 2)
      return (acceptedCount + 1) / (totalCount + 2);
    } catch (e) {
      debugPrint('SuggestionFeedback.getPosterior error: $e');
      return null;
    }
  }

  /// Get all feedback-weighted scores for a suggestion type, keyed by value.
  static Future<Map<String, double>> getAllPosteriors({
    required List<String> keywords,
    required String suggestionType,
  }) async {
    if (keywords.isEmpty) return {};
    try {
      final db = await DatabaseHelper.instance.database;
      final placeholders = List.filled(keywords.length, '?').join(',');
      final rows = await db.rawQuery('''
        SELECT
          suggested_value,
          SUM(CASE WHEN accepted = 1 THEN 1 ELSE 0 END) AS accepted_count,
          COUNT(*) AS total_count
        FROM suggestion_feedback
        WHERE keyword IN ($placeholders)
          AND suggestion_type = ?
        GROUP BY suggested_value
        HAVING total_count >= 2
      ''', [...keywords.map((k) => k.toLowerCase()), suggestionType]);

      final result = <String, double>{};
      for (final row in rows) {
        final value = row['suggested_value'] as String;
        final accepted = (row['accepted_count'] as int?) ?? 0;
        final total = (row['total_count'] as int?) ?? 0;
        result[value] = (accepted + 1) / (total + 2);
      }
      return result;
    } catch (e) {
      debugPrint('SuggestionFeedback.getAllPosteriors error: $e');
      return {};
    }
  }

  /// Blend a rule score with feedback posterior.
  /// [ruleWeight] controls how much the original rule score matters vs feedback.
  static double blendScore(double ruleScore, double? posterior,
      {double ruleWeight = 0.6}) {
    if (posterior == null) return ruleScore;
    return ruleWeight * ruleScore + (1 - ruleWeight) * posterior;
  }
}
