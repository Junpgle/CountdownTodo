import 'dart:math';
import 'package:flutter/foundation.dart';
import 'database_helper.dart';

/// Result of a time estimation prediction
class TimeEstimationResult {
  final int estimatedMinutes;
  final double confidence; // [0, 1]
  final String reason;
  final List<String> similarTitles;

  const TimeEstimationResult({
    required this.estimatedMinutes,
    required this.confidence,
    required this.reason,
    this.similarTitles = const [],
  });
}

/// A historical data point for estimation
class _HistoricalRecord {
  final String title;
  final int actualMinutes;
  final int createdAt;
  final String? tagUuids;
  final String? todoUuid;

  const _HistoricalRecord({
    required this.title,
    required this.actualMinutes,
    required this.createdAt,
    this.tagUuids,
    this.todoUuid,
  });
}

/// Predicts todo duration based on historical data, keyword similarity,
/// and complexity analysis.
class TimeEstimationService {
  // CJK Unified Ideographs range
  static final _cjkRange = RegExp('[\\u4e00-\\u9fff]+');
  static final _cjkOrAlnum = RegExp('[^\\u4e00-\\u9fffa-z0-9 ]');
  static final _englishWord = RegExp('[a-z]+');

  // Complexity keyword dictionaries
  static const _highComplexityKeywords = [
    '复杂', '项目', '设计', '开发', '研究', '调研', '报告', '论文',
    '方案', '架构', '系统', '分析', '规划', '重构', '优化', '算法',
    '数据库', '部署', '迁移', '实现', '编写', '撰写', '策划',
    '毕业', '考试', '竞赛', '实验', '建模', '仿真',
  ];

  static const _mediumComplexityKeywords = [
    '学习', '练习', '复习', '整理', '准备', '检查', '测试',
    '阅读', '翻译', '总结', '修改', '更新', '配置', '安装',
    '调试', 'review', '巩固', '梳理', '作业', '课程',
  ];

  static const _lowComplexityKeywords = [
    '购买', '打印', '发送', '回复', '简单', '快速', '顺便',
    '清理', '备份', '下载', '上传', '提交', '确认', '浏览',
    '签收', '签到', '打卡', '取快递', '买东西', '发消息',
  ];

  // Decay factor for recency weighting (30-day half-life)
  static const _halfLifeDays = 30.0;
  static const _ln2 = 0.6931471805599453;

  /// Main entry point: estimate how long a todo will take.
  static Future<TimeEstimationResult> estimate(
    String title, {
    String? groupId,
    String? categoryTagId,
  }) async {
    if (title.trim().isEmpty) {
      return const TimeEstimationResult(
        estimatedMinutes: 30,
        confidence: 0.1,
        reason: '请输入标题以获取预估',
      );
    }

    try {
      // Load historical data
      final records = await _loadHistoricalRecords();

      debugPrint('TimeEstimation: loaded ${records.length} historical records');

      // Cold start: not enough data — use keyword-only heuristic
      if (records.length < 3) {
        debugPrint('TimeEstimation: cold start (< 3 records)');
        return _coldStartEstimate(title);
      }

      // Layer 1: Keyword similarity
      final similarityResult = _similarityEstimate(title, records);

      // Layer 2: Complexity keyword scoring
      final complexityResult = _complexityEstimate(title, records);

      // Layer 3: Category/tag average
      final categoryResult = await _categoryEstimate(
        records,
        groupId: groupId,
        categoryTagId: categoryTagId,
      );

      // Determine weights based on data volume
      final w = _getWeights(records.length);

      final combined = (w[0] * similarityResult.$1 +
              w[1] * complexityResult.$1 +
              w[2] * categoryResult.$1)
          .round();

      final combinedConfidence = w[0] * similarityResult.$2 +
          w[1] * complexityResult.$2 +
          w[2] * categoryResult.$2;

      final reason = _buildReason(
        similarityResult,
        complexityResult,
        categoryResult,
        w,
      );

      debugPrint(
          'TimeEstimation: result=$combined min, confidence=${combinedConfidence.toStringAsFixed(2)}, '
          'sim=${similarityResult.$1.toStringAsFixed(0)}, cxp=${complexityResult.$1.toStringAsFixed(0)}, '
          'cat=${categoryResult.$1.toStringAsFixed(0)}');

      return TimeEstimationResult(
        estimatedMinutes: max(5, combined),
        confidence: combinedConfidence.clamp(0.0, 1.0),
        reason: reason,
        similarTitles: similarityResult.$3,
      );
    } catch (e) {
      debugPrint('TimeEstimationService error: $e');
      return _coldStartEstimate(title);
    }
  }

  // === Data Loading ===

  static Future<List<_HistoricalRecord>> _loadHistoricalRecords() async {
    final db = await DatabaseHelper.instance.database;
    final records = <_HistoricalRecord>[];

    // Primary: todo_plan_blocks — prefer actual focus time, fall back to planned
    try {
      final planBlocks = await db.rawQuery('''
        SELECT title_snapshot, planned_minutes, actual_focus_seconds, created_at, todo_uuid
        FROM todo_plan_blocks
        WHERE is_deleted = 0
          AND title_snapshot IS NOT NULL
          AND title_snapshot != ''
          AND (actual_focus_seconds > 0 OR planned_minutes > 0)
        ORDER BY created_at DESC
        LIMIT 500
      ''');

      for (final row in planBlocks) {
        final title = row['title_snapshot'] as String?;
        final actualSecs = row['actual_focus_seconds'] as int? ?? 0;
        final plannedMins = row['planned_minutes'] as int? ?? 0;
        // Prefer actual, fall back to planned
        final minutes = actualSecs > 0 ? (actualSecs / 60).round() : plannedMins;
        if (title != null && title.isNotEmpty && minutes > 0) {
          records.add(_HistoricalRecord(
            title: title,
            actualMinutes: minutes,
            createdAt: row['created_at'] as int? ?? 0,
            todoUuid: row['todo_uuid'] as String?,
          ));
        }
      }
    } catch (e) {
      debugPrint('TimeEstimation: plan_blocks query error: $e');
    }

    // Secondary: pomodoro_records with todo_title
    try {
      final pomodoros = await db.rawQuery('''
        SELECT todo_title, actual_duration, planned_duration, tag_uuids, created_at
        FROM pomodoro_records
        WHERE is_deleted = 0
          AND todo_title IS NOT NULL
          AND todo_title != ''
          AND (actual_duration > 0 OR planned_duration > 0)
        ORDER BY created_at DESC
        LIMIT 300
      ''');

      for (final row in pomodoros) {
        final title = row['todo_title'] as String?;
        final actualSecs = row['actual_duration'] as int? ?? 0;
        final plannedSecs = row['planned_duration'] as int? ?? 0;
        final seconds = actualSecs > 0 ? actualSecs : plannedSecs;
        if (title != null && title.isNotEmpty && seconds > 0) {
          records.add(_HistoricalRecord(
            title: title,
            actualMinutes: (seconds / 60).round(),
            createdAt: row['created_at'] as int? ?? 0,
            tagUuids: row['tag_uuids'] as String?,
          ));
        }
      }
    } catch (e) {
      debugPrint('TimeEstimation: pomodoro_records query error: $e');
    }

    // Deduplicate by title, keep most recent
    final deduped = <String, _HistoricalRecord>{};
    for (final r in records) {
      final key = r.title.trim().toLowerCase();
      if (!deduped.containsKey(key) || r.createdAt > deduped[key]!.createdAt) {
        deduped[key] = r;
      }
    }

    return deduped.values.toList();
  }

  // === Layer 1: Keyword Similarity ===

  static (double, double, List<String>) _similarityEstimate(
    String title,
    List<_HistoricalRecord> records,
  ) {
    final queryTokens = _tokenize(title);
    if (queryTokens.isEmpty) return (0.0, 0.0, []);

    final now = DateTime.now().millisecondsSinceEpoch;
    final scored = <(double, double, String)>[]; // (similarity, recencyWeight, title)

    for (final r in records) {
      final rTokens = _tokenize(r.title);
      if (rTokens.isEmpty) continue;

      // Jaccard similarity
      final intersection = queryTokens.intersection(rTokens).length;
      final union = queryTokens.union(rTokens).length;
      final similarity = union > 0 ? intersection / union : 0.0;

      if (similarity < 0.05) continue;

      // Recency weight (exponential decay)
      final daysSinceCreation =
          (now - r.createdAt) / (24 * 3600 * 1000).toDouble();
      final recencyWeight = exp(-_ln2 * daysSinceCreation / _halfLifeDays);

      scored.add((similarity, recencyWeight, r.title));
    }

    if (scored.isEmpty) return (0.0, 0.0, []);

    // Sort by similarity * recency
    scored.sort((a, b) => (b.$1 * b.$2).compareTo(a.$1 * a.$2));

    // Weighted average of top-K durations
    final topK = scored.take(5).toList();
    double totalWeight = 0;
    double weightedDuration = 0;
    final similarTitles = <String>[];

    for (final (sim, recency, tTitle) in topK) {
      final w = sim * recency;
      totalWeight += w;
      final record = records.firstWhere(
        (r) => r.title == tTitle,
        orElse: () => records.first,
      );
      weightedDuration += w * record.actualMinutes;
      similarTitles.add(tTitle);
    }

    if (totalWeight <= 0) return (0.0, 0.0, []);

    final estimate = weightedDuration / totalWeight;
    final bestSimilarity = topK.first.$1;
    final bestRecency = topK.first.$2;
    final confidence = (bestSimilarity * bestRecency).clamp(0.0, 1.0);

    return (estimate, confidence, similarTitles.take(3).toList());
  }

  // === Layer 2: Complexity Keyword Scoring ===

  static (double, double) _complexityEstimate(
    String title,
    List<_HistoricalRecord> records,
  ) {
    final globalAvg =
        records.map((r) => r.actualMinutes).reduce((a, b) => a + b) /
            records.length;

    double factor = 1.0;
    final lowerTitle = title.toLowerCase();

    for (final kw in _highComplexityKeywords) {
      if (lowerTitle.contains(kw)) {
        factor = max(factor, 1.5);
        break;
      }
    }
    for (final kw in _mediumComplexityKeywords) {
      if (lowerTitle.contains(kw)) {
        factor = max(factor, 1.0);
        break;
      }
    }
    for (final kw in _lowComplexityKeywords) {
      if (lowerTitle.contains(kw)) {
        factor = min(factor, 0.5);
        break;
      }
    }

    return (globalAvg * factor, 0.4);
  }

  // === Layer 3: Category/Tag Average ===

  static Future<(double, double)> _categoryEstimate(
    List<_HistoricalRecord> records, {
    String? groupId,
    String? categoryTagId,
  }) async {
    // Try tag-based grouping first
    if (categoryTagId != null && categoryTagId.isNotEmpty) {
      final tagRecords = records.where((r) {
        if (r.tagUuids == null) return false;
        return r.tagUuids!.contains(categoryTagId);
      }).toList();

      if (tagRecords.length >= 3) {
        final avg = tagRecords
                .map((r) => r.actualMinutes)
                .reduce((a, b) => a + b) /
            tagRecords.length;
        return (avg, 0.5);
      }
    }

    // Try group-based grouping
    if (groupId != null && groupId.isNotEmpty) {
      try {
        final db = await DatabaseHelper.instance.database;
        final groupTodos = await db.query(
          'todos',
          columns: ['uuid'],
          where: 'group_id = ? AND is_deleted = 0',
          whereArgs: [groupId],
        );
        final groupUuids =
            groupTodos.map((r) => r['uuid'] as String).toSet();

        if (groupUuids.isNotEmpty) {
          final groupRecords = records
              .where(
                  (r) => r.todoUuid != null && groupUuids.contains(r.todoUuid))
              .toList();

          if (groupRecords.length >= 3) {
            final avg = groupRecords
                    .map((r) => r.actualMinutes)
                    .reduce((a, b) => a + b) /
                groupRecords.length;
            return (avg, 0.4);
          }
        }
      } catch (_) {
        // Ignore DB errors
      }
    }

    // Fallback: global average
    final globalAvg =
        records.map((r) => r.actualMinutes).reduce((a, b) => a + b) /
            records.length;
    return (globalAvg, 0.2);
  }

  // === Weight Selection ===

  static List<double> _getWeights(int recordCount) {
    if (recordCount < 3) return [0.0, 1.0, 0.0]; // complexity only
    if (recordCount < 10) return [0.35, 0.40, 0.25];
    if (recordCount < 30) return [0.45, 0.30, 0.25];
    return [0.50, 0.30, 0.20];
  }

  // === Tokenization ===

  static Set<String> _tokenize(String text) {
    final tokens = <String>{};
    // Normalize: lowercase, strip punctuation, keep CJK + alphanumeric
    final cleaned = text.toLowerCase().replaceAll(_cjkOrAlnum, ' ').trim();

    if (cleaned.isEmpty) return tokens;

    // English words (min length 2)
    for (final m in _englishWord.allMatches(cleaned)) {
      final w = m.group(0)!;
      if (w.length >= 2) tokens.add(w);
    }

    // Chinese: unigrams + bigrams
    for (final m in _cjkRange.allMatches(cleaned)) {
      final seg = m.group(0)!;
      for (int i = 0; i < seg.length; i++) {
        tokens.add(seg[i]);
      }
      for (int i = 0; i < seg.length - 1; i++) {
        tokens.add(seg.substring(i, i + 2));
      }
    }

    return tokens;
  }

  // === Cold Start ===

  static TimeEstimationResult _coldStartEstimate(String title) {
    final len = title.length;
    int base;
    String reason;

    final lowerTitle = title.toLowerCase();
    bool isHigh = _highComplexityKeywords.any((kw) => lowerTitle.contains(kw));
    bool isMed = _mediumComplexityKeywords.any((kw) => lowerTitle.contains(kw));
    bool isLow = _lowComplexityKeywords.any((kw) => lowerTitle.contains(kw));

    if (isHigh) {
      base = 60;
      reason = '检测到复杂任务关键词，历史数据较少';
    } else if (isMed) {
      base = 30;
      reason = '检测到中等复杂度关键词，历史数据较少';
    } else if (isLow) {
      base = 15;
      reason = '检测到简单任务关键词，历史数据较少';
    } else if (len <= 4) {
      base = 20;
      reason = '历史数据较少，基于标题长度粗略预估';
    } else if (len <= 10) {
      base = 35;
      reason = '历史数据较少，基于标题长度粗略预估';
    } else {
      base = 50;
      reason = '历史数据较少，基于标题长度粗略预估';
    }

    return TimeEstimationResult(
      estimatedMinutes: base,
      confidence: 0.2,
      reason: reason,
    );
  }

  // === Reason Builder ===

  static String _buildReason(
    (double, double, List<String>) similarity,
    (double, double) complexity,
    (double, double) category,
    List<double> weights,
  ) {
    final parts = <String>[];

    if (weights[0] > 0 && similarity.$2 > 0.2 && similarity.$3.isNotEmpty) {
      parts.add('与"${similarity.$3.first}"相似');
    }

    if (weights[1] > 0) {
      parts.add('基于任务复杂度分析');
    }

    if (weights[2] > 0 && category.$2 > 0.25) {
      parts.add('参考同类任务平均耗时');
    }

    if (parts.isEmpty) {
      parts.add('综合分析');
    }

    return parts.join('，');
  }
}
