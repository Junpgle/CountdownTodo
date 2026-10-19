import 'dart:math';
import 'database_helper.dart';
import 'medal_recommendation_service.dart';

/// Thompson Sampling bandit for medal recommendations
/// Uses Beta(alpha, beta) distributions to learn which medals
/// users are most likely to pursue after being recommended.
class MedalBanditService {
  static final MedalBanditService instance = MedalBanditService._();
  MedalBanditService._();

  final Random _rng = Random();

  static const int _successWindowDays = 30;
  static const int _staleResetDays = 90;
  static const double _failurePenalty = 0.3;

  /// Sample from Beta distribution for each medal
  Future<Map<String, double>> sampleAll(List<String> medalIds) async {
    final result = <String, double>{};
    try {
      final db = await DatabaseHelper.instance.database;
      final records = await db.query('medal_recommendations');

      final recordMap = <String, Map<String, dynamic>>{};
      for (final r in records) {
        recordMap[r['medal_id'] as String] = r;
      }

      for (final id in medalIds) {
        final record = recordMap[id];
        final alpha = (record?['alpha'] as num?)?.toDouble() ?? 1.0;
        final beta = (record?['beta_'] as num?)?.toDouble() ?? 1.0;
        result[id] = sampleBeta(alpha, beta);
      }
    } catch (e) {
      // debugPrint('Bandit sampleAll failed: $e');
      // Fallback: uniform samples
      for (final id in medalIds) {
        result[id] = _rng.nextDouble();
      }
    }
    return result;
  }

  /// Get total observation count for a medal (alpha + beta - 2, minus initial prior)
  Future<int> getObservationCount(String medalId) async {
    final counts = await getObservationCounts([medalId]);
    return counts[medalId] ?? 0;
  }

  /// Reads observation counts for several medals with a bounded number of
  /// database queries.
  Future<Map<String, int>> getObservationCounts(List<String> medalIds) async {
    final counts = <String, int>{for (final id in medalIds) id: 0};
    if (counts.isEmpty) return counts;

    try {
      final db = await DatabaseHelper.instance.database;
      const chunkSize = 900;
      final uniqueIds = counts.keys.toList(growable: false);
      for (var offset = 0; offset < uniqueIds.length; offset += chunkSize) {
        final end = offset + chunkSize < uniqueIds.length
            ? offset + chunkSize
            : uniqueIds.length;
        final ids = uniqueIds.sublist(offset, end);
        final records = await db.query(
          'medal_recommendations',
          columns: const ['medal_id', 'alpha', 'beta_'],
          where: 'medal_id IN (${List.filled(ids.length, '?').join(', ')})',
          whereArgs: ids,
        );
        for (final record in records) {
          final id = record['medal_id'] as String;
          final alpha = (record['alpha'] as num?)?.toDouble() ?? 1.0;
          final beta = (record['beta_'] as num?)?.toDouble() ?? 1.0;
          counts[id] = max(0, (alpha + beta - 2).toInt());
        }
      }
    } catch (e) {
      // Keep missing or failed reads at the prior observation count of zero.
    }
    return counts;
  }

  /// Update bandit parameters based on whether recommended medals were earned
  Future<void> updateOutcomes(List<MedalProgress> allProgresses) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      final thirtyDaysAgo = now - _successWindowDays * 24 * 3600 * 1000;
      final ninetyDaysAgo = now - _staleResetDays * 24 * 3600 * 1000;

      final records = await db.query('medal_recommendations');
      Map<String, MedalProgress>? progressByMedalId;

      for (final record in records) {
        final medalId = record['medal_id'] as String;
        final lastShownAt = record['last_shown_at'] as int;
        final lastOutcomeAt = record['last_outcome_at'] as int;

        // Reset stale entries (not shown in 90 days)
        if (lastShownAt < ninetyDaysAgo && lastShownAt > 0) {
          await db.update(
              'medal_recommendations',
              {
                'alpha': 1.0,
                'beta_': 1.0,
                'impression_count': 0,
                'success_count': 0,
                'last_shown_at': 0,
                'last_outcome_at': now,
                'updated_at': now,
              },
              where: 'medal_id = ?',
              whereArgs: [medalId]);
          continue;
        }

        // Only process if shown after last outcome check
        if (lastShownAt <= lastOutcomeAt) continue;

        final progressIndex =
            progressByMedalId ??= _indexProgresses(allProgresses);
        final progress = progressIndex[medalId];
        if (progress == null) continue;

        double alphaDelta = 0;
        double betaDelta = 0;
        int successDelta = 0;

        if (progress.earned) {
          alphaDelta = 1.0;
          successDelta = 1;
        } else if (lastShownAt < thirtyDaysAgo) {
          betaDelta = _failurePenalty;
        } else {
          continue; // Still within observation window
        }

        final currentAlpha = (record['alpha'] as num?)?.toDouble() ?? 1.0;
        final currentBeta = (record['beta_'] as num?)?.toDouble() ?? 1.0;

        await db.update(
            'medal_recommendations',
            {
              'alpha': max(1.0, currentAlpha + alphaDelta),
              'beta_': max(1.0, currentBeta + betaDelta),
              'success_count': (record['success_count'] as int) + successDelta,
              'last_outcome_at': now,
              'updated_at': now,
            },
            where: 'medal_id = ?',
            whereArgs: [medalId]);
      }
    } catch (e) {
      // debugPrint('Bandit updateOutcomes failed: $e');
    }
  }

  Map<String, MedalProgress> _indexProgresses(
    List<MedalProgress> progresses,
  ) {
    final byId = <String, MedalProgress>{};
    for (final progress in progresses) {
      byId.putIfAbsent(progress.medal.id, () => progress);
    }
    return byId;
  }

  /// Record that these medals were shown as recommendations
  Future<void> recordImpressions(List<String> medalIds) async {
    if (medalIds.isEmpty) return;

    try {
      final db = await DatabaseHelper.instance.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      final uniqueIds = medalIds.toSet().toList(growable: false);
      final existingById = <String, Map<String, Object?>>{};
      const queryChunkSize = 500;
      for (var start = 0; start < uniqueIds.length; start += queryChunkSize) {
        final end = start + queryChunkSize < uniqueIds.length
            ? start + queryChunkSize
            : uniqueIds.length;
        final ids = uniqueIds.sublist(start, end);
        final rows = await db.query(
          'medal_recommendations',
          columns: const ['medal_id', 'impression_count'],
          where: 'medal_id IN (${List.filled(ids.length, '?').join(', ')})',
          whereArgs: ids,
        );
        for (final row in rows) {
          final id = row['medal_id']?.toString();
          if (id != null) existingById[id] = row;
        }
      }

      for (final id in medalIds) {
        final existing = existingById[id];
        if (existing == null) {
          await db.insert('medal_recommendations', {
            'medal_id': id,
            'alpha': 1.0,
            'beta_': 1.0,
            'impression_count': 1,
            'success_count': 0,
            'last_shown_at': now,
            'last_outcome_at': 0,
            'feature_score_cache': 0.0,
            'updated_at': now,
          });
          existingById[id] = {'impression_count': 1};
        } else {
          final impressionCount =
              (existing['impression_count'] as int) + 1;
          await db.update(
              'medal_recommendations',
              {
                'impression_count': impressionCount,
                'last_shown_at': now,
                'updated_at': now,
              },
              where: 'medal_id = ?',
              whereArgs: [id]);
          existingById[id] = {
            ...existing,
            'impression_count': impressionCount,
          };
        }
      }
    } catch (e) {
      // debugPrint('Bandit recordImpressions failed: $e');
    }
  }

  // === Beta Distribution Sampling (Pure Dart) ===

  /// Sample from Beta(alpha, beta) using Gamma sampling
  double sampleBeta(double alpha, double beta) {
    final x = _sampleGamma(alpha);
    final y = _sampleGamma(beta);
    return x / (x + y);
  }

  /// Sample from Gamma(shape) using Marsaglia and Tsang's method
  double _sampleGamma(double shape) {
    if (shape < 1.0) {
      // For shape < 1, use the relation: Gamma(a) = Gamma(a+1) * U^(1/a)
      return _sampleGamma(shape + 1.0) * pow(_rng.nextDouble(), 1.0 / shape);
    }

    final d = shape - 1.0 / 3.0;
    final c = 1.0 / sqrt(9.0 * d);

    while (true) {
      double x;
      double v;
      do {
        x = _nextNormal();
        v = 1.0 + c * x;
      } while (v <= 0);

      v = v * v * v;
      final u = _rng.nextDouble();

      if (u < 1.0 - 0.0331 * x * x * x * x) {
        return d * v;
      }
      if (log(u) < 0.5 * x * x + d * (1.0 - v + log(v))) {
        return d * v;
      }
    }
  }

  /// Sample from standard normal distribution using Box-Muller transform
  double _nextNormal() {
    final u1 = _rng.nextDouble();
    final u2 = _rng.nextDouble();
    return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
  }
}
