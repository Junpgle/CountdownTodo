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
      final rows = await db.rawQuery(
        '''
        SELECT
          SUM(CASE WHEN accepted = 1 THEN 1 ELSE 0 END) AS accepted_count,
          COUNT(*) AS total_count
        FROM suggestion_feedback
        WHERE keyword IN ($placeholders)
          AND suggestion_type = ?
          AND suggested_value = ?
      ''',
        [
          ...keywords.map((k) => k.toLowerCase()),
          suggestionType,
          suggestedValue,
        ],
      );

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
      final rows = await db.rawQuery(
        '''
        SELECT
          suggested_value,
          SUM(CASE WHEN accepted = 1 THEN 1 ELSE 0 END) AS accepted_count,
          COUNT(*) AS total_count
        FROM suggestion_feedback
        WHERE keyword IN ($placeholders)
          AND suggestion_type = ?
        GROUP BY suggested_value
        HAVING total_count >= 2
      ''',
        [...keywords.map((k) => k.toLowerCase()), suggestionType],
      );

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

  /// Get posterior acceptance rates for several suggestion types in one query.
  static Future<Map<String, Map<String, double>>> getAllPosteriorsByTypes({
    required List<String> keywords,
    required List<String> suggestionTypes,
  }) async {
    final result = <String, Map<String, double>>{
      for (final type in suggestionTypes) type: <String, double>{},
    };
    if (keywords.isEmpty || result.isEmpty) return result;

    try {
      final db = await DatabaseHelper.instance.database;
      final keywordPlaceholders = List.filled(keywords.length, '?').join(',');
      final typePlaceholders = List.filled(result.length, '?').join(',');
      final rows = await db.rawQuery(
        '''
        SELECT
          suggestion_type,
          suggested_value,
          SUM(CASE WHEN accepted = 1 THEN 1 ELSE 0 END) AS accepted_count,
          COUNT(*) AS total_count
        FROM suggestion_feedback
        WHERE keyword IN ($keywordPlaceholders)
          AND suggestion_type IN ($typePlaceholders)
        GROUP BY suggestion_type, suggested_value
        HAVING COUNT(*) >= 2
      ''',
        [...keywords.map((keyword) => keyword.toLowerCase()), ...result.keys],
      );

      for (final row in rows) {
        final type = row['suggestion_type'] as String;
        final value = row['suggested_value'] as String;
        final accepted = (row['accepted_count'] as int?) ?? 0;
        final total = (row['total_count'] as int?) ?? 0;
        result[type]?[value] = (accepted + 1) / (total + 2);
      }
    } catch (e) {
      debugPrint('SuggestionFeedback.getAllPosteriorsByTypes error: $e');
      for (final type in result.keys) {
        result[type] = await getAllPosteriors(
          keywords: keywords,
          suggestionType: type,
        );
      }
    }
    return result;
  }

  /// Loads feedback for several independent keyword sets in bounded queries.
  static Future<List<Map<String, Map<String, double>>>>
  getAllPosteriorsForQueries({
    required List<List<String>> keywordSets,
    required List<String> suggestionTypes,
  }) async {
    final types = suggestionTypes.toSet().toList(growable: false);
    final results = List.generate(
      keywordSets.length,
      (_) => <String, Map<String, double>>{
        for (final type in types) type: <String, double>{},
      },
    );
    if (types.isEmpty) return results;

    final queryIndexes = <int>[];
    final normalizedKeywords = <String>[];
    for (var queryIndex = 0; queryIndex < keywordSets.length; queryIndex++) {
      final uniqueKeywords = keywordSets[queryIndex]
          .map((keyword) => keyword.toLowerCase())
          .toSet();
      for (final keyword in uniqueKeywords) {
        queryIndexes.add(queryIndex);
        normalizedKeywords.add(keyword);
      }
    }
    if (normalizedKeywords.isEmpty) return results;

    final counts = List.generate(
      keywordSets.length,
      (_) => <String, Map<String, List<int>>>{
        for (final type in types) type: <String, List<int>>{},
      },
    );
    try {
      final db = await DatabaseHelper.instance.database;
      final typePlaceholders = List.filled(types.length, '?').join(',');
      const chunkSize = 900;
      for (
        var offset = 0;
        offset < normalizedKeywords.length;
        offset += chunkSize
      ) {
        final end = offset + chunkSize < normalizedKeywords.length
            ? offset + chunkSize
            : normalizedKeywords.length;
        final values = List.generate(
          end - offset,
          (index) => '(${queryIndexes[offset + index]}, ?)',
        ).join(', ');
        final rows = await db.rawQuery(
          '''
          WITH query_keywords(query_index, keyword) AS (VALUES $values)
          SELECT
            q.query_index,
            f.suggestion_type,
            f.suggested_value,
            SUM(CASE WHEN f.accepted = 1 THEN 1 ELSE 0 END) AS accepted_count,
            COUNT(*) AS total_count
          FROM query_keywords AS q
          JOIN suggestion_feedback AS f ON f.keyword = q.keyword
          WHERE f.suggestion_type IN ($typePlaceholders)
          GROUP BY q.query_index, f.suggestion_type, f.suggested_value
          ''',
          [...normalizedKeywords.sublist(offset, end), ...types],
        );

        for (final row in rows) {
          final queryIndex = (row['query_index'] as num).toInt();
          final type = row['suggestion_type'] as String;
          final value = row['suggested_value'] as String;
          final stats = counts[queryIndex][type]!.putIfAbsent(
            value,
            () => [0, 0],
          );
          stats[0] += (row['accepted_count'] as int?) ?? 0;
          stats[1] += (row['total_count'] as int?) ?? 0;
        }
      }

      for (var queryIndex = 0; queryIndex < counts.length; queryIndex++) {
        for (final type in types) {
          for (final entry in counts[queryIndex][type]!.entries) {
            final accepted = entry.value[0];
            final total = entry.value[1];
            if (total < 2) continue;
            results[queryIndex][type]![entry.key] =
                (accepted + 1) / (total + 2);
          }
        }
      }
    } catch (e) {
      debugPrint('SuggestionFeedback.getAllPosteriorsForQueries error: $e');
      for (var queryIndex = 0; queryIndex < keywordSets.length; queryIndex++) {
        results[queryIndex] = await getAllPosteriorsByTypes(
          keywords: keywordSets[queryIndex],
          suggestionTypes: types,
        );
      }
    }
    return results;
  }

  /// Blend a rule score with feedback posterior.
  /// [ruleWeight] controls how much the original rule score matters vs feedback.
  static double blendScore(
    double ruleScore,
    double? posterior, {
    double ruleWeight = 0.6,
  }) {
    if (posterior == null) return ruleScore;
    return ruleWeight * ruleScore + (1 - ruleWeight) * posterior;
  }
}
