import 'dart:math';

import 'time_estimation_repository.dart';

enum TimeEstimationSource { history, heuristic, readFailure, empty }

enum TimeEstimationReference { sufficient, moderate, limited }

/// Confidence is an internal evidence score, never a calibrated probability.
class TimeEstimationResult {
  final int estimatedMinutes;
  final double confidence;
  final String reason;
  final List<String> similarTitles;
  final List<TimeEstimationSample> samples;
  final TimeEstimationSource source;
  final String? username;
  final int incompleteCount, noActualCount;

  const TimeEstimationResult({
    required this.estimatedMinutes,
    required this.confidence,
    required this.reason,
    this.similarTitles = const [],
    this.samples = const [],
    this.source = TimeEstimationSource.heuristic,
    this.username,
    this.incompleteCount = 0,
    this.noActualCount = 0,
  });

  TimeEstimationReference get reference =>
      source != TimeEstimationSource.history
      ? TimeEstimationReference.limited
      : samples.length >= 5 && confidence >= .6
      ? TimeEstimationReference.sufficient
      : samples.length >= 3 && confidence >= .35
      ? TimeEstimationReference.moderate
      : TimeEstimationReference.limited;

  String get referenceLabel => switch (reference) {
    TimeEstimationReference.sufficient => '历史参考较充分',
    TimeEstimationReference.moderate => '历史参考一般',
    TimeEstimationReference.limited => '参考较少，可调整',
  };
}

class _WeightedSample {
  const _WeightedSample(this.sample, this.similarity, this.recency);
  final TimeEstimationSample sample;
  final double similarity, recency;
  double get weight => similarity * recency;
}

/// Local, read-only estimates from complete tasks with measured focus time.
class TimeEstimationService {
  // CJK Unified Ideographs range
  static final _cjkRange = RegExp('[\\u4e00-\\u9fff]+');
  static final _cjkOrAlnum = RegExp('[^\\u4e00-\\u9fffa-z0-9 ]');
  static final _englishWord = RegExp('[a-z]+');

  // Complexity keyword dictionaries
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

  static const _mediumComplexityKeywords = [
    '学习',
    '练习',
    '复习',
    '整理',
    '准备',
    '检查',
    '测试',
    '阅读',
    '翻译',
    '总结',
    '修改',
    '更新',
    '配置',
    '安装',
    '调试',
    'review',
    '巩固',
    '梳理',
    '作业',
    '课程',
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

  static const halfLifeDays = 30.0;
  static const minimumSimilarity = .35;
  static const maxSimilarSamples = 12;
  static const maxCategorySamples = 20;

  static Future<TimeEstimationResult> estimate(
    String title, {
    String? groupId,
    String? categoryTagId,
    String? username,
    TimeEstimationRepository repository = const TimeEstimationRepository(),
    DateTime Function()? clock,
  }) async {
    final account = username ?? await TimeEstimationRepository.activeUsername();
    await TimeEstimationRepository.checkAccount(account);
    final now = clock?.call() ?? DateTime.now();
    if (title.trim().isEmpty) {
      return _fallback(
        title,
        account,
        TimeEstimationSource.empty,
        '请输入标题以获取预估',
      );
    }
    try {
      final history = await repository.read(account, now);
      await TimeEstimationRepository.checkAccount(account);
      return estimateFromHistory(
        title,
        history,
        now: now,
        username: account,
        groupId: groupId,
        categoryTagId: categoryTagId,
      );
    } on TimeEstimationAccountChanged {
      rethrow;
    } catch (_) {
      await TimeEstimationRepository.checkAccount(account);
      return _fallback(
        title,
        account,
        TimeEstimationSource.readFailure,
        '历史记录读取失败，暂按关键词粗略估算，可手动调整',
      );
    }
  }

  static TimeEstimationResult _fallback(
    String title,
    String? username,
    TimeEstimationSource source,
    String reason, {
    TimeEstimationHistory? history,
  }) {
    final rough = _coldStartEstimate(title);
    return TimeEstimationResult(
      estimatedMinutes: rough.estimatedMinutes,
      confidence: .2,
      reason: reason,
      source: source,
      username: username,
      incompleteCount: history?.incompleteCount ?? 0,
      noActualCount: history?.noActualCount ?? 0,
    );
  }

  /// Pure calculation also makes the evidence snapshot reproducible in tests.
  static TimeEstimationResult estimateFromHistory(
    String title,
    TimeEstimationHistory history, {
    required DateTime now,
    String? username,
    String? groupId,
    String? categoryTagId,
  }) {
    if (title.trim().isEmpty) {
      return _fallback(
        title,
        username,
        TimeEstimationSource.empty,
        '请输入标题以获取预估',
      );
    }
    final tokens = _tokenize(title);
    double recency(TimeEstimationSample sample) => max(
      1e-8,
      pow(
        .5,
        max(0, now.millisecondsSinceEpoch - sample.endedAt) /
            Duration.millisecondsPerDay /
            halfLifeDays,
      ).toDouble(),
    );
    final valid = history.samples
        .where(
          (s) =>
              s.actualSeconds > 0 &&
              s.endedAt > 0 &&
              s.endedAt <= now.millisecondsSinceEpoch &&
              s.title.trim().isNotEmpty,
        )
        .toList();
    final scored = <_WeightedSample>[];
    for (final sample in valid) {
      final candidate = _tokenize(sample.title);
      final union = tokens.union(candidate).length;
      final similarity = _normalize(title) == _normalize(sample.title)
          ? 1.0
          : union == 0
          ? 0.0
          : tokens.intersection(candidate).length / union;
      if (similarity >= minimumSimilarity) {
        scored.add(_WeightedSample(sample, similarity, recency(sample)));
      }
    }
    scored.sort((a, b) {
      final cmp = b.weight.compareTo(a.weight);
      return cmp != 0 ? cmp : a.sample.todoId.compareTo(b.sample.todoId);
    });
    final similar = scored.take(maxSimilarSamples).toList();
    var category = <TimeEstimationSample>[];
    String? categoryReason;
    if (categoryTagId?.isNotEmpty == true) {
      category = valid.where((s) => s.tagIds.contains(categoryTagId)).toList();
      if (category.length >= 3) {
        categoryReason = '同标签';
      } else {
        category.clear();
      }
    }
    if (category.isEmpty && groupId?.isNotEmpty == true) {
      category = valid.where((s) => s.groupId == groupId).toList();
      if (category.length >= 3) {
        categoryReason = '同分组';
      } else {
        category.clear();
      }
    }
    category.sort((a, b) {
      final cmp = b.endedAt.compareTo(a.endedAt);
      return cmp != 0 ? cmp : a.todoId.compareTo(b.todoId);
    });
    category = category.take(maxCategorySamples).toList();
    final used = <String, TimeEstimationSample>{
      for (final item in similar) item.sample.todoId: item.sample,
      for (final item in category) item.todoId: item,
    }.values.toList();
    if (used.isEmpty) {
      return _fallback(
        title,
        username,
        TimeEstimationSource.heuristic,
        history.incompleteCount > 0
            ? '没有可靠的同类完成样本，部分历史记录不完整，按关键词粗略估算'
            : '没有可靠的同类完成样本，按关键词粗略估算',
        history: history,
      );
    }

    // Missing layers carry no weight; renormalize only available layers.
    double weighted = 0, weights = 0;
    if (similar.isNotEmpty) {
      weighted += .75 * _median(similar);
      weights += .75;
    }
    if (category.isNotEmpty) {
      weighted +=
          .25 *
          _median(
            category.map((s) => _WeightedSample(s, 1, recency(s))).toList(),
          );
      weights += .25;
    }
    var minutes = weighted / weights;
    final durations = used.map((s) => s.minutes).toList()..sort();
    final center = durations[durations.length ~/ 2];
    final spread = (durations.last - durations.first) / max(1, center);
    // Sparse or inconsistent history is a weaker signal, without allowing an
    // extreme duration to dominate the robust center.
    final historicalWeight =
        min(1.0, used.length / 3) * (spread > .6 ? .65 : 1.0);
    minutes =
        minutes * historicalWeight +
        _coldStartEstimate(title).estimatedMinutes * (1 - historicalWeight);
    final recent = used.map(recency).reduce((a, b) => a + b) / used.length;
    final strongSimilar = similar
        .where((s) => s.similarity >= .6 && s.recency >= .5)
        .length;
    final score = spread > .6 || used.length < 3
        ? .2
        : strongSimilar >= 5 && recent >= .5 && spread <= .35
        ? .75
        : recent >= .25
        ? .45
        : .2;
    final reasons = <String>[
      if (similar.isNotEmpty) '${similar.length}个相似',
      if (category.isNotEmpty) '${category.length}个$categoryReason',
    ];
    return TimeEstimationResult(
      estimatedMinutes: max(5, minutes.round()),
      confidence: score,
      source: TimeEstimationSource.history,
      username: username,
      samples: List.unmodifiable(used),
      similarTitles: List.unmodifiable(
        similar.map((s) => s.sample.title).toSet().take(3),
      ),
      incompleteCount: history.incompleteCount,
      noActualCount: history.noActualCount,
      reason:
          '参考${reasons.join('、')}已完成待办的累计专注${spread > .6
              ? '；耗时差异较大，已降低历史影响'
              : used.length < 3
              ? '；样本较少，结合关键词估算'
              : recent < .25
              ? '；历史较久，参考有限'
              : ''}',
    );
  }

  static double _median(List<_WeightedSample> samples) {
    final sorted = [...samples]
      ..sort((a, b) => a.sample.minutes.compareTo(b.sample.minutes));
    final halfway = sorted.fold<double>(0, (v, s) => v + s.weight) / 2;
    double total = 0;
    for (final value in sorted) {
      total += value.weight;
      if (total >= halfway) return value.sample.minutes;
    }
    return sorted.last.sample.minutes;
  }

  static String _normalize(String text) => text
      .toLowerCase()
      .replaceAll(_cjkOrAlnum, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static Set<String> _tokenize(String text) {
    final cleaned = _normalize(text);
    final tokens = <String>{};
    for (final m in _englishWord.allMatches(cleaned)) {
      if (m.group(0)!.length >= 2) tokens.add(m.group(0)!);
    }
    for (final m in _cjkRange.allMatches(cleaned)) {
      final seg = m.group(0)!;
      for (var i = 0; i < seg.length; i++) {
        tokens.add(seg[i]);
        if (i + 1 < seg.length) tokens.add(seg.substring(i, i + 2));
      }
    }
    return tokens;
  }

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
}
