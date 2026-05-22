import 'dart:math';

import '../models.dart';
import '../models/ai_todo_action.dart';
import 'pomodoro_service.dart';
import 'suggestion_feedback_service.dart';

class TodoClassificationSuggestion {
  const TodoClassificationSuggestion({
    this.groupId,
    this.groupName,
    required this.priority,
    required this.priorityLabel,
    required this.tags,
    required this.confidence,
    required this.reason,
    this.reminderMinutes,
  });

  final String? groupId;
  final String? groupName;
  final int priority;
  final String priorityLabel;
  final List<String> tags;
  final double confidence;
  final String reason;
  final int? reminderMinutes;

  bool get hasGroup => groupId != null && groupId!.isNotEmpty;
}

class TodoClassificationService {
  static const _urgentKeywords = [
    '今天',
    '今晚',
    '马上',
    '立刻',
    '尽快',
    '紧急',
    '截止',
    'ddl',
    'deadline',
    'due',
    '考试',
    '面试',
    '提交',
  ];

  static const _importantKeywords = [
    '重要',
    '汇报',
    '报告',
    '论文',
    '项目',
    '复习',
    '实验',
    '作业',
    '会议',
    '合同',
    '申请',
  ];

  static const _tagProfiles = <String, List<String>>{
    '学习': ['学习', '复习', '作业', '考试', '课程', '实验', '论文', '刷题', '阅读'],
    '工作': ['工作', '会议', '项目', '汇报', '周报', '需求', '开发', '测试', '上线'],
    '生活': ['生活', '购物', '买', '取', '快递', '缴费', '家务', '清理', '维修'],
    '健康': ['健康', '运动', '跑步', '健身', '医院', '体检', '吃药', '睡觉'],
    '财务': ['财务', '报销', '账单', '发票', '转账', '预算', '银行'],
  };

  static Future<TodoClassificationSuggestion> recommendForText({
    required String title,
    String remark = '',
    required List<TodoGroup> groups,
    List<TodoItem> history = const [],
    Map<String, int> categoryReminderDefaults = const {},
    DateTime? dueDate,
  }) async {
    final text = '${title.trim()} ${remark.trim()}'.trim();
    final textTokens = _tokenList(text);

    // Load feedback weights in parallel
    final groupFeedbackFuture = SuggestionFeedbackService.getAllPosteriors(
      keywords: textTokens,
      suggestionType: 'group',
    );
    final tagFeedbackFuture = SuggestionFeedbackService.getAllPosteriors(
      keywords: textTokens,
      suggestionType: 'tag',
    );
    final priorityFeedbackFuture = SuggestionFeedbackService.getAllPosteriors(
      keywords: textTokens,
      suggestionType: 'priority',
    );

    final groupFeedback = await groupFeedbackFuture;
    final tagFeedback = await tagFeedbackFuture;
    final priorityFeedback = await priorityFeedbackFuture;

    final priority = _classifyPriority(text, dueDate, priorityFeedback);
    final tags = _classifyTags(text, tagFeedback);
    final groupScore = _scoreGroups(text, groups, history, groupFeedback);
    final group = groupScore.group;
    final confidence = groupScore.confidence;
    final reminderMinutes =
        group != null && categoryReminderDefaults.containsKey(group.id)
            ? categoryReminderDefaults[group.id]
            : _reminderForPriority(priority);

    return TodoClassificationSuggestion(
      groupId: confidence >= 0.18 ? group?.id : null,
      groupName: confidence >= 0.18 ? group?.name : null,
      priority: priority,
      priorityLabel: _priorityLabel(priority),
      tags: tags,
      confidence: confidence,
      reason: _buildReason(group, confidence, priority, tags),
      reminderMinutes: reminderMinutes,
    );
  }

  static Future<List<AiTodoAction>> buildCategorizeActions({
    required List<TodoItem> todos,
    required List<TodoGroup> groups,
    Map<String, int> categoryReminderDefaults = const {},
    int limit = 6,
  }) async {
    if (groups.where((g) => !g.isDeleted).isEmpty) return const [];
    // Prioritize unclassified todos (no groupId)
    final sortedTodos = [...todos]..sort((a, b) {
        final aEmpty = (a.groupId == null || a.groupId!.isEmpty) ? 0 : 1;
        final bEmpty = (b.groupId == null || b.groupId!.isEmpty) ? 0 : 1;
        return aEmpty.compareTo(bEmpty);
      });
    final actions = <AiTodoAction>[];
    for (final todo in sortedTodos) {
      if (todo.isDeleted || todo.isDone) continue;
      final suggestion = await recommendForText(
        title: todo.title,
        remark: todo.remark ?? '',
        groups: groups,
        history: todos,
        categoryReminderDefaults: categoryReminderDefaults,
        dueDate: todo.dueDate,
      );
      final isUnclassified = todo.groupId == null || todo.groupId!.isEmpty;
      final minConfidence = isUnclassified ? 0.20 : 0.34;
      if (!suggestion.hasGroup ||
          suggestion.groupId == todo.groupId ||
          suggestion.confidence < minConfidence) {
        continue;
      }
      actions.add(
        AiTodoAction(
          type: AiTodoActionType.categorizeTodo,
          todoId: todo.id,
          title: todo.title,
          groupId: suggestion.groupId,
          reminderMinutes: suggestion.reminderMinutes,
          metadata: {
            'groupName': suggestion.groupName,
            'classificationConfidence': suggestion.confidence,
            'priority': suggestion.priority,
            'priorityLabel': suggestion.priorityLabel,
            'tags': suggestion.tags,
            'reason': suggestion.reason,
          },
        ),
      );
      if (actions.length >= limit) break;
    }
    return actions;
  }

  static Future<List<String>> recommendPomodoroTagUuidsForTodo({
    required TodoItem todo,
    required List<PomodoroTag> tags,
    List<PomodoroRecord> history = const [],
    List<TodoItem> todoHistory = const [],
    List<TodoGroup> groups = const [],
    int limit = 3,
  }) async {
    final activeTags = tags.where((t) => !t.isDeleted).toList();
    if (activeTags.isEmpty || limit <= 0) return const [];

    final scores = <String, double>{};
    void addScore(String uuid, double score) {
      if (uuid.isEmpty || !activeTags.any((t) => t.uuid == uuid)) return;
      scores[uuid] = (scores[uuid] ?? 0) + score;
    }

    final sameTodoRecords = history
        .where((r) =>
            !r.isDeleted && r.todoUuid == todo.id && r.tagUuids.isNotEmpty)
        .toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
    for (var i = 0; i < sameTodoRecords.length && i < 12; i++) {
      final record = sameTodoRecords[i];
      final recencyBoost = max(0.0, 2.0 - i * 0.15);
      final durationBoost =
          min(2.0, (record.effectiveDuration / 1800).clamp(0, 2).toDouble());
      for (final uuid in record.tagUuids) {
        addScore(uuid, 7.0 + recencyBoost + durationBoost);
      }
    }

    final text = '${todo.title.trim()} ${(todo.remark ?? '').trim()}'.trim();
    final lowerText = text.toLowerCase();
    final suggestion = await recommendForText(
      title: todo.title,
      remark: todo.remark ?? '',
      groups: groups,
      history: todoHistory,
      dueDate: todo.dueDate,
    );
    final suggestedTagNames =
        suggestion.tags.map(_normalizeTagName).where((e) => e.isNotEmpty);

    for (final tag in activeTags) {
      final tagName = tag.name.trim();
      if (tagName.isEmpty) continue;
      final normalizedTag = _normalizeTagName(tagName);

      if (lowerText.contains(tagName.toLowerCase())) {
        addScore(tag.uuid, 5.0);
      }

      for (final suggested in suggestedTagNames) {
        if (_tagNameMatches(normalizedTag, suggested)) {
          addScore(tag.uuid, 4.5);
        }
      }

      final profile = _tagProfiles[tagName];
      if (profile != null) {
        addScore(tag.uuid, _keywordHits(text, profile) * 3.0);
      }

      final group = groups.cast<TodoGroup?>().firstWhere(
            (g) => g?.id == todo.groupId,
            orElse: () => null,
          );
      final groupName = group?.name.trim();
      if (groupName != null &&
          groupName.isNotEmpty &&
          _tagNameMatches(normalizedTag, _normalizeTagName(groupName))) {
        addScore(tag.uuid, 3.0);
      }
    }

    if (scores.isEmpty) return const [];
    final sorted = activeTags.where((t) => scores.containsKey(t.uuid)).toList()
      ..sort((a, b) {
        final scoreCompare = scores[b.uuid]!.compareTo(scores[a.uuid]!);
        if (scoreCompare != 0) return scoreCompare;
        return a.name.compareTo(b.name);
      });
    return sorted.take(limit).map((t) => t.uuid).toList();
  }

  static _GroupScore _scoreGroups(
    String text,
    List<TodoGroup> groups,
    List<TodoItem> history,
    Map<String, double> groupFeedback,
  ) {
    final availableGroups = groups.where((g) => !g.isDeleted).toList();
    if (availableGroups.isEmpty || text.trim().isEmpty) {
      return const _GroupScore(null, 0);
    }
    final textTokens = _tokens(text);
    TodoGroup? bestGroup;
    var bestScore = 0.0;
    var secondScore = 0.0;

    for (final group in availableGroups) {
      var score = _similarity(textTokens, _tokens(group.name)) * 2.2;
      for (final entry in _tagProfiles.entries) {
        if (group.name.contains(entry.key) ||
            entry.key.contains(group.name.trim())) {
          score += _keywordHits(text, entry.value) * 0.42;
        }
      }
      final relatedHistory =
          history.where((t) => t.groupId == group.id && !t.isDeleted).take(24);
      for (final todo in relatedHistory) {
        score += _similarity(textTokens, _tokens(todo.title)) * 0.32;
      }
      // Blend with feedback posterior
      final posterior = groupFeedback[group.id];
      if (posterior != null) {
        score = SuggestionFeedbackService.blendScore(score, posterior);
      }
      if (score > bestScore) {
        secondScore = bestScore;
        bestScore = score;
        bestGroup = group;
      } else if (score > secondScore) {
        secondScore = score;
      }
    }

    final confidence = (bestScore <= 0)
        ? 0.0
        : ((bestScore - secondScore * 0.45) / (bestScore + 1.4)).clamp(0, 1);
    return _GroupScore(bestGroup, confidence.toDouble());
  }

  static int _classifyPriority(
    String text,
    DateTime? dueDate,
    Map<String, double> priorityFeedback,
  ) {
    var score = 1;
    if (_keywordHits(text, _importantKeywords) > 0) score++;
    if (_keywordHits(text, _urgentKeywords) > 0) score += 2;
    if (dueDate != null) {
      final hours = dueDate.difference(DateTime.now()).inHours;
      if (hours <= 12) {
        score += 2;
      } else if (hours <= 48) {
        score++;
      }
    }
    final clamped = score.clamp(1, 5);
    // Adjust with feedback: shift toward historically accepted priority levels
    if (priorityFeedback.isNotEmpty) {
      double weighted = 0;
      double totalW = 0;
      for (final entry in priorityFeedback.entries) {
        final p = int.tryParse(entry.key);
        if (p == null) continue;
        weighted += p * entry.value;
        totalW += entry.value;
      }
      if (totalW > 0) {
        final feedbackAvg = weighted / totalW;
        return ((0.6 * clamped + 0.4 * feedbackAvg).round()).clamp(1, 5);
      }
    }
    return clamped;
  }

  static String _priorityLabel(int priority) {
    if (priority >= 4) return '高优先级';
    if (priority >= 3) return '中高优先级';
    if (priority == 2) return '普通优先级';
    return '低压力';
  }

  static int _reminderForPriority(int priority) {
    if (priority >= 4) return 30;
    if (priority >= 3) return 15;
    return 5;
  }

  static List<String> _classifyTags(
    String text,
    Map<String, double> tagFeedback,
  ) {
    final tags = <String>[];
    for (final entry in _tagProfiles.entries) {
      if (_keywordHits(text, entry.value) > 0) tags.add(entry.key);
    }
    if (_keywordHits(text, _urgentKeywords) > 0) tags.add('紧急');
    if (_keywordHits(text, _importantKeywords) > 0) tags.add('重要');

    // Boost tags that users historically accepted
    if (tagFeedback.isNotEmpty) {
      for (final entry in tagFeedback.entries) {
        if (entry.value > 0.6 && !tags.contains(entry.key)) {
          tags.add(entry.key);
        }
      }
    }

    return tags.take(4).toList();
  }

  static String _normalizeTagName(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

  static bool _tagNameMatches(String a, String b) {
    if (a.isEmpty || b.isEmpty) return false;
    return a == b || a.contains(b) || b.contains(a);
  }

  static String _buildReason(
    TodoGroup? group,
    double confidence,
    int priority,
    List<String> tags,
  ) {
    final parts = <String>[];
    if (group != null && confidence >= 0.18) {
      parts.add('匹配到「${group.name}」语义');
    }
    parts.add(_priorityLabel(priority));
    if (tags.isNotEmpty) parts.add('标签: ${tags.join('、')}');
    return parts.join(' · ');
  }

  static int _keywordHits(String text, List<String> keywords) {
    final lower = text.toLowerCase();
    return keywords.where((k) => lower.contains(k.toLowerCase())).length;
  }

  static Set<String> _tokens(String text) {
    final normalized = text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final tokens = <String>{};
    for (final match in RegExp(r'[a-z0-9]+').allMatches(normalized)) {
      final token = match.group(0);
      if (token != null && token.length >= 2) tokens.add(token);
    }
    final cjk = RegExp(r'[\u4e00-\u9fff]').allMatches(normalized).toList();
    for (var i = 0; i < cjk.length; i++) {
      tokens.add(cjk[i].group(0)!);
      if (i + 1 < cjk.length) {
        tokens.add('${cjk[i].group(0)!}${cjk[i + 1].group(0)!}');
      }
    }
    return tokens;
  }

  static List<String> _tokenList(String text) => _tokens(text).toList();

  static double _similarity(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final intersection = a.intersection(b).length;
    final union = a.union(b).length;
    return union == 0 ? 0 : intersection / max(1, union);
  }
}

class _GroupScore {
  const _GroupScore(this.group, this.confidence);

  final TodoGroup? group;
  final double confidence;
}
