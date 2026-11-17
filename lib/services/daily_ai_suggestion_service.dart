import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/habits/models/habit_progress.dart';
import '../features/habits/repositories/habit_repository.dart';
import '../features/habits/services/habit_progress_calculator.dart';
import '../features/thirty_day_challenge/repositories/thirty_day_challenge_repository.dart';
import '../models.dart';
import 'ai_chat_service.dart';
import 'ai_memory_service.dart';
import 'chat_storage_service.dart';
import 'llm_service.dart';
import 'minor_mode_service.dart';
import 'pomodoro_service.dart';
import 'storage/storage_key_scope.dart';

enum DailyAiSuggestionPriority { high, medium, low }

class DailyAiSuggestionItem {
  final String title;
  final String reason;
  final DailyAiSuggestionPriority priority;
  final String? todoId;
  final bool isAddedToTodo;

  const DailyAiSuggestionItem({
    required this.title,
    this.reason = '',
    this.priority = DailyAiSuggestionPriority.medium,
    this.todoId,
    this.isAddedToTodo = false,
  });

  DailyAiSuggestionItem copyWith({
    String? title,
    String? reason,
    DailyAiSuggestionPriority? priority,
    String? todoId,
    bool? isAddedToTodo,
  }) {
    return DailyAiSuggestionItem(
      title: title ?? this.title,
      reason: reason ?? this.reason,
      priority: priority ?? this.priority,
      todoId: todoId ?? this.todoId,
      isAddedToTodo: isAddedToTodo ?? this.isAddedToTodo,
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'reason': reason,
    'priority': priority.name,
    if (todoId != null) 'todoId': todoId,
    'isAddedToTodo': isAddedToTodo,
  };

  factory DailyAiSuggestionItem.fromJson(Map<String, dynamic> json) {
    final rawPriority = (json['priority']?.toString() ?? '').toLowerCase();
    final priority = switch (rawPriority) {
      'high' => DailyAiSuggestionPriority.high,
      'low' => DailyAiSuggestionPriority.low,
      _ => DailyAiSuggestionPriority.medium,
    };
    final rawTodoId = json['todoId']?.toString().trim();
    return DailyAiSuggestionItem(
      title: (json['title']?.toString() ?? '').trim(),
      reason: (json['reason']?.toString() ?? '').trim(),
      priority: priority,
      todoId: rawTodoId == null || rawTodoId.isEmpty ? null : rawTodoId,
      isAddedToTodo: json['isAddedToTodo'] == true,
    );
  }
}

class DailyAiSuggestion {
  final String dateKey;
  final String summary;
  final List<DailyAiSuggestionItem> items;
  final int generatedAtMs;
  final bool isDismissed;
  final bool isExpanded;

  const DailyAiSuggestion({
    required this.dateKey,
    required this.summary,
    required this.items,
    required this.generatedAtMs,
    this.isDismissed = false,
    this.isExpanded = true,
  });

  DailyAiSuggestion copyWith({
    String? dateKey,
    String? summary,
    List<DailyAiSuggestionItem>? items,
    int? generatedAtMs,
    bool? isDismissed,
    bool? isExpanded,
  }) {
    return DailyAiSuggestion(
      dateKey: dateKey ?? this.dateKey,
      summary: summary ?? this.summary,
      items: items ?? this.items,
      generatedAtMs: generatedAtMs ?? this.generatedAtMs,
      isDismissed: isDismissed ?? this.isDismissed,
      isExpanded: isExpanded ?? this.isExpanded,
    );
  }

  Map<String, dynamic> toJson() => {
    'dateKey': dateKey,
    'summary': summary,
    'items': items.map((item) => item.toJson()).toList(),
    'generatedAtMs': generatedAtMs,
    'isDismissed': isDismissed,
    'isExpanded': isExpanded,
  };

  factory DailyAiSuggestion.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final items = <DailyAiSuggestionItem>[];
    if (rawItems is List) {
      for (final raw in rawItems) {
        if (raw is Map) {
          final parsed = DailyAiSuggestionItem.fromJson(
            Map<String, dynamic>.from(raw),
          );
          if (parsed.title.isNotEmpty) {
            items.add(parsed);
          }
        }
      }
    }
    return DailyAiSuggestion(
      dateKey: json['dateKey']?.toString() ?? '',
      summary: (json['summary']?.toString() ?? '').trim(),
      items: items,
      generatedAtMs: (json['generatedAtMs'] as num?)?.toInt() ?? 0,
      isDismissed: json['isDismissed'] == true,
      isExpanded: json['isExpanded'] != false,
    );
  }
}

enum DailyAiContextOption {
  completedTodos('completed_todos', '今日已完成待办', '帮助 AI 了解今日已完成进度，避免重复建议'),
  freeSlots('free_slots', '今日剩余可用空档', '根据课程、日程与规划块自动计算今天剩余空闲时段'),
  pomodoro('pomodoro', '番茄钟专注记录', '纳入今日与昨日番茄专注次数、时长及关联任务'),
  timeLogs('time_logs', '今日时间日志', '纳入今日时间日志记录与累计时长'),
  habits('habits', '今日习惯打卡', '纳入当前计划内的习惯名称与今日打卡进度'),
  challenge('challenge', '30 天挑战进度', '纳入进行中的 30 天挑战进度与可选任务'),
  yesterdayAndTomorrow('yesterday_tomorrow', '昨日与明早节律', '纳入昨日完成数量与明早课程/日程预览'),
  recentFeedback('recent_feedback', '近期建议采纳反馈', '记录近期采纳或忽略的建议，减少重复推荐'),
  memory('memory', '个人记忆', '纳入你在 AI 记忆中保存的偏好与背景信息');

  final String key;
  final String title;
  final String subtitle;

  const DailyAiContextOption(this.key, this.title, this.subtitle);
}

class DailyAiSuggestionContextConfig {
  final Map<DailyAiContextOption, bool> _values;

  const DailyAiSuggestionContextConfig([
    Map<DailyAiContextOption, bool> values = const {},
  ]) : _values = values;

  bool isEnabled(DailyAiContextOption option) => _values[option] ?? true;

  int get enabledCount =>
      DailyAiContextOption.values.where(isEnabled).length;

  DailyAiSuggestionContextConfig copyWithOption(
    DailyAiContextOption option,
    bool enabled,
  ) {
    return DailyAiSuggestionContextConfig({
      ..._values,
      option: enabled,
    });
  }

  Map<String, dynamic> toJson() => {
    for (final option in DailyAiContextOption.values)
      option.key: isEnabled(option),
  };

  factory DailyAiSuggestionContextConfig.fromJson(Map<String, dynamic> json) {
    final map = <DailyAiContextOption, bool>{};
    for (final option in DailyAiContextOption.values) {
      final raw = json[option.key];
      if (raw is bool) {
        map[option] = raw;
      }
    }
    return DailyAiSuggestionContextConfig(map);
  }
}

class DailyAiSuggestionSnapshot {
  final bool enabled;
  final bool isLoading;
  final bool needsModelConfig;
  final bool showFirstOpenPrompt;
  final bool showManualGenerateCard;
  final DailyAiSuggestion? suggestion;
  final String? errorMessage;

  const DailyAiSuggestionSnapshot({
    this.enabled = false,
    this.isLoading = false,
    this.needsModelConfig = false,
    this.showFirstOpenPrompt = false,
    this.showManualGenerateCard = false,
    this.suggestion,
    this.errorMessage,
  });

  bool get shouldShowOnDashboard {
    if (showFirstOpenPrompt || showManualGenerateCard) return true;
    if (isLoading) return true;
    if (needsModelConfig && enabled) return true;
    if (errorMessage != null && errorMessage!.isNotEmpty) return true;
    final current = suggestion;
    if (current == null || current.isDismissed) return false;
    return current.summary.isNotEmpty || current.items.isNotEmpty;
  }
}

typedef DailyAiChatCompleter = Future<String> Function({
  required String apiUrl,
  required String apiKey,
  required String model,
  required List<Map<String, dynamic>> messages,
  String provider,
  double temperature,
  int maxTokens,
  Duration timeout,
  String usageOperation,
});

typedef DailyAiConfigResolver =
    Future<({String model, String apiKey, String apiUrl, String provider})?>
    Function();

/// Generates and caches an optional daily AI task suggestion on the first app
/// open of each day.
class DailyAiSuggestionService {
  DailyAiSuggestionService._();

  static const String _enabledKey = 'daily_ai_suggestion_enabled';
  static const String _cacheKey = 'daily_ai_suggestion_cache';
  static const String _lastTriggeredDateKey = 'daily_ai_suggestion_last_date';
  static const String _promptDismissedKey =
      'daily_ai_suggestion_prompt_dismissed';
  static const String _manualSectionKeptKey =
      'daily_ai_suggestion_manual_section';
  static const String _feedbackHistoryKey =
      'daily_ai_suggestion_feedback_history';
  static const String _contextOptionsKey =
      'daily_ai_suggestion_context_options';

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static final Map<String, Future<DailyAiSuggestionSnapshot>> _inFlight = {};

  static String formatDateKey(DateTime date) =>
      DateFormat('yyyy-MM-dd').format(date);

  static String _scoped(String baseKey, String? username) =>
      StorageKeyScope.scoped(baseKey, username);

  static Future<bool> isEnabled(String? username) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_scoped(_enabledKey, username)) ?? false;
  }

  static Future<void> setEnabled(String? username, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_scoped(_enabledKey, username), enabled);
    if (enabled) {
      await prefs.remove(_scoped(_promptDismissedKey, username));
    }
    revision.value++;
  }

  static Future<bool> isPromptDismissed(String? username) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_scoped(_promptDismissedKey, username)) ?? false;
  }

  static Future<void> dismissFirstOpenPrompt(String? username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_scoped(_promptDismissedKey, username), true);
    await prefs.setBool(_scoped(_manualSectionKeptKey, username), false);
    revision.value++;
  }

  static Future<bool> isManualSectionKept(String? username) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_scoped(_manualSectionKeptKey, username)) ?? false;
  }

  static Future<void> setManualSectionKept(String? username, bool kept) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_scoped(_manualSectionKeptKey, username), kept);
    if (kept) {
      await prefs.remove(_scoped(_promptDismissedKey, username));
    }
    revision.value++;
  }

  static Future<DailyAiSuggestionContextConfig> loadContextConfig(
    String? username,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scoped(_contextOptionsKey, username));
    if (raw == null || raw.isEmpty) {
      return const DailyAiSuggestionContextConfig();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return DailyAiSuggestionContextConfig.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
    } catch (_) {}
    return const DailyAiSuggestionContextConfig();
  }

  static Future<void> setContextOption(
    String? username,
    DailyAiContextOption option,
    bool enabled,
  ) async {
    final current = await loadContextConfig(username);
    final updated = current.copyWithOption(option, enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _scoped(_contextOptionsKey, username),
      jsonEncode(updated.toJson()),
    );
    revision.value++;
  }

  static Future<DailyAiSuggestion?> loadCachedSuggestion(
    String? username, {
    DateTime? now,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scoped(_cacheKey, username));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final parsed = DailyAiSuggestion.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      final todayKey = formatDateKey(now ?? DateTime.now());
      if (parsed.dateKey != todayKey) return null;
      return parsed;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveCachedSuggestion(
    String? username,
    DailyAiSuggestion suggestion,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = _scoped(_cacheKey, username);
    final previousRaw = prefs.getString(cacheKey);
    if (previousRaw != null && previousRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(previousRaw);
        if (decoded is Map) {
          final previous = DailyAiSuggestion.fromJson(
            Map<String, dynamic>.from(decoded),
          );
          if (previous.dateKey.isNotEmpty &&
              previous.dateKey != suggestion.dateKey) {
            await _archiveFeedbackHistory(prefs, username, previous);
          }
        }
      } catch (_) {}
    }
    await prefs.setString(cacheKey, jsonEncode(suggestion.toJson()));
    await prefs.setString(
      _scoped(_lastTriggeredDateKey, username),
      suggestion.dateKey,
    );
  }

  static Future<void> _archiveFeedbackHistory(
    SharedPreferences prefs,
    String? username,
    DailyAiSuggestion previous,
  ) async {
    final adopted = previous.items
        .where((i) => i.isAddedToTodo)
        .map((i) => i.title)
        .toList();
    final ignored = previous.items
        .where((i) => !i.isAddedToTodo)
        .map((i) => i.title)
        .toList();
    if (adopted.isEmpty && ignored.isEmpty && !previous.isDismissed) return;

    final parts = <String>[];
    if (previous.isDismissed) parts.add('整卡被收起忽略');
    if (adopted.isNotEmpty) {
      parts.add('已采纳加入待办：${adopted.take(3).join('、')}');
    }
    if (ignored.isNotEmpty) {
      parts.add('未采纳：${ignored.take(3).join('、')}');
    }
    final entry = '${previous.dateKey}：${parts.join('；')}';

    final key = _scoped(_feedbackHistoryKey, username);
    final existing = prefs.getStringList(key) ?? const <String>[];
    final updated = <String>[
      ...existing.where((line) => !line.startsWith('${previous.dateKey}：')),
      entry,
    ];
    final trimmed = updated.length > 3
        ? updated.sublist(updated.length - 3)
        : updated;
    await prefs.setStringList(key, trimmed);
  }

  static Future<String> loadRecentFeedbackBlock(String? username) async {
    final prefs = await SharedPreferences.getInstance();
    final entries =
        prefs.getStringList(_scoped(_feedbackHistoryKey, username)) ??
        const <String>[];
    if (entries.isEmpty) return '';
    return '【近期建议反馈（避免重复推荐未采纳项）】\n${entries.map((e) => '- $e').join('\n')}';
  }

  static Future<String> loadHabitSummaryBlock(DateTime now) async {
    final goals = await HabitRepository.getActiveGoals();
    final activeGoals = goals
        .where((g) => !g.isDeleted && !g.isArchived)
        .take(12)
        .toList();
    if (activeGoals.isEmpty) return '';
    final rules = await HabitRepository.getRules();
    final today = DateTime(now.year, now.month, now.day);
    final lines = <String>[];
    for (final goal in activeGoals) {
      final goalRules = rules.where((r) => r.habitUuid == goal.uuid).toList();
      final progress = await HabitProgressCalculator.computeRange(
        habit: goal,
        rules: goalRules,
        from: today,
        to: today,
        now: today,
        periodLevel: true,
      );
      if (progress.isEmpty) continue;
      final item = progress.last;
      if (item.status == HabitDayStatus.notPlanned) continue;
      final statusText = switch (item.status) {
        HabitDayStatus.met => '已完成',
        HabitDayStatus.skipped => '已跳过',
        HabitDayStatus.frozen => '免扣守护中',
        HabitDayStatus.inProgress =>
          item.progress.completionRatio > 0
              ? '进行中(${(item.progress.completionRatio * 100).round()}%)'
              : '待打卡',
        HabitDayStatus.missed => '待补卡',
        HabitDayStatus.notPlanned => '',
      };
      if (statusText.isEmpty) continue;
      lines.add('- ${goal.icon} ${goal.name}：$statusText');
    }
    if (lines.isEmpty) return '';
    return '【今日习惯打卡（共${lines.length}项）】\n${lines.join('\n')}';
  }

  static Future<String> loadChallengeSummaryBlock(
    String? username,
    DateTime now,
  ) async {
    final started = await ThirtyDayChallengeRepository.hasStarted(
      username: username,
    );
    if (!started) return '';
    final paused = await ThirtyDayChallengeRepository.isPaused(
      username: username,
    );
    if (paused) return '';
    final state = await ThirtyDayChallengeRepository.load(username: username);
    if (state.tasks.isEmpty) return '';
    final completedCount = state.tasks.where((t) => t.isCompleted).length;
    final todayKey = formatDateKey(now);
    final doneToday = state.tasks.any(
      (t) =>
          t.isCompleted &&
          t.completedAt != null &&
          formatDateKey(t.completedAt!.toLocal()) == todayKey,
    );
    final unfinished = state.unfinishedTasks
        .take(3)
        .map((t) => t.title)
        .toList();
    final progressPart = '$completedCount/${state.tasks.length}';
    if (doneToday) {
      return '【30天挑战】《${state.challengeTitle}》已完成 $progressPart，今日已打卡完成一项。';
    }
    if (unfinished.isEmpty) {
      return '【30天挑战】《${state.challengeTitle}》已全部完成（$progressPart）。';
    }
    return '【30天挑战】《${state.challengeTitle}》已完成 $progressPart，今日尚未打卡（可选：${unfinished.join('、')}）。';
  }

  static Future<void> setExpanded(
    String? username,
    bool expanded, {
    DateTime? now,
  }) async {
    final cached = await loadCachedSuggestion(username, now: now);
    if (cached == null || cached.isExpanded == expanded) return;
    await _saveCachedSuggestion(
      username,
      cached.copyWith(isExpanded: expanded),
    );
    revision.value++;
  }

  static Future<void> dismissForToday(String? username, {DateTime? now}) async {
    final cached = await loadCachedSuggestion(username, now: now);
    if (cached == null || cached.isDismissed) return;
    await _saveCachedSuggestion(username, cached.copyWith(isDismissed: true));
    revision.value++;
  }

  /// Clears today's cache and trigger marker so the next sync regenerates a
  /// fresh suggestion and surfaces it on the home dashboard.
  static Future<void> requestRegenerate(String? username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_scoped(_cacheKey, username));
    await prefs.remove(_scoped(_lastTriggeredDateKey, username));
    revision.value++;
  }

  static Future<void> markItemAddedToTodo(
    String? username,
    int index, {
    DateTime? now,
  }) async {
    final cached = await loadCachedSuggestion(username, now: now);
    if (cached == null || index < 0 || index >= cached.items.length) return;
    final updatedItems = List<DailyAiSuggestionItem>.from(cached.items);
    updatedItems[index] = updatedItems[index].copyWith(isAddedToTodo: true);
    await _saveCachedSuggestion(username, cached.copyWith(items: updatedItems));
    revision.value++;
  }

  static Future<
    ({String model, String apiKey, String apiUrl, String provider})?
  >
  resolveAiConfig() async {
    final chatConfig = await ChatStorageService.getChatConfig();
    final chatModel = chatConfig?['model']?.trim() ?? '';
    final chatApiKey = chatConfig?['apiKey']?.trim() ?? '';
    if (chatModel.isNotEmpty && chatApiKey.isNotEmpty) {
      return (
        model: chatModel,
        apiKey: chatApiKey,
        apiUrl: chatConfig?['apiUrl']?.trim().isNotEmpty == true
            ? chatConfig!['apiUrl']!.trim()
            : AiChatService.defaultApiUrl,
        provider: chatConfig?['provider']?.trim() ?? '',
      );
    }

    final llmConfig = await LLMService.getConfig();
    if (llmConfig != null && llmConfig.isConfigured) {
      return (
        model: llmConfig.model.trim(),
        apiKey: llmConfig.apiKey.trim(),
        apiUrl: llmConfig.apiUrl.trim(),
        provider: llmConfig.provider.trim(),
      );
    }
    return null;
  }

  /// Ensures today's AI suggestion is generated once per day when enabled.
  /// Set [forceRefresh] to true to regenerate manually for today.
  /// Set [allowWhenDisabled] to true for a one-off "ask AI" invocation when
  /// the daily auto-generation toggle is off.
  static Future<DailyAiSuggestionSnapshot> ensureTodaySuggestion({
    required String? username,
    required List<TodoItem> todos,
    required List<CountdownItem> countdowns,
    required List<TodoPlanBlock> planBlocks,
    required List<FixedScheduleItem> fixedSchedules,
    required List<CourseItem> courses,
    Future<List<PomodoroRecord>> Function()? loadTodayPomodoroRecords,
    Future<List<PomodoroRecord>> Function()? loadYesterdayPomodoroRecords,
    Future<List<TimeLogItem>> Function()? loadTodayTimeLogs,
    Future<String> Function(DateTime now)? loadHabitSummary,
    Future<String> Function(String? username, DateTime now)?
    loadChallengeSummary,
    bool forceRefresh = false,
    bool allowWhenDisabled = false,
    DateTime? now,
    DailyAiChatCompleter? completer,
    DailyAiConfigResolver? configResolver,
  }) {
    final scopeKey = username ?? '';
    final existing = _inFlight[scopeKey];
    if (existing != null && !forceRefresh) return existing;

    final future =
        _runEnsureTodaySuggestion(
          username: username,
          todos: todos,
          countdowns: countdowns,
          planBlocks: planBlocks,
          fixedSchedules: fixedSchedules,
          courses: courses,
          loadTodayPomodoroRecords: loadTodayPomodoroRecords,
          loadYesterdayPomodoroRecords: loadYesterdayPomodoroRecords,
          loadTodayTimeLogs: loadTodayTimeLogs,
          loadHabitSummary: loadHabitSummary,
          loadChallengeSummary: loadChallengeSummary,
          forceRefresh: forceRefresh,
          allowWhenDisabled: allowWhenDisabled,
          now: now,
          completer: completer ?? AiChatService.completeChat,
          configResolver: configResolver ?? resolveAiConfig,
        ).whenComplete(() {
          _inFlight.remove(scopeKey);
        });
    _inFlight[scopeKey] = future;
    return future;
  }

  static Future<DailyAiSuggestionSnapshot> _runEnsureTodaySuggestion({
    required String? username,
    required List<TodoItem> todos,
    required List<CountdownItem> countdowns,
    required List<TodoPlanBlock> planBlocks,
    required List<FixedScheduleItem> fixedSchedules,
    required List<CourseItem> courses,
    required Future<List<PomodoroRecord>> Function()? loadTodayPomodoroRecords,
    required Future<List<PomodoroRecord>> Function()?
    loadYesterdayPomodoroRecords,
    required Future<List<TimeLogItem>> Function()? loadTodayTimeLogs,
    required Future<String> Function(DateTime now)? loadHabitSummary,
    required Future<String> Function(String? username, DateTime now)?
    loadChallengeSummary,
    required bool forceRefresh,
    required bool allowWhenDisabled,
    required DateTime? now,
    required DailyAiChatCompleter completer,
    required DailyAiConfigResolver configResolver,
  }) async {
    final enabled = await isEnabled(username);
    final current = now ?? DateTime.now();
    final todayKey = formatDateKey(current);
    final prefs = await SharedPreferences.getInstance();
    final lastTriggeredDate = prefs.getString(
      _scoped(_lastTriggeredDateKey, username),
    );
    final cached = await loadCachedSuggestion(username, now: current);

    if (!enabled && !allowWhenDisabled) {
      if (cached != null) {
        return DailyAiSuggestionSnapshot(enabled: false, suggestion: cached);
      }
      if (!await MinorModeService.instance.authorizeAiInteraction()) {
        return const DailyAiSuggestionSnapshot(enabled: false);
      }
      final aiConfig = await configResolver();
      if (aiConfig == null) {
        return const DailyAiSuggestionSnapshot(enabled: false);
      }
      if (await isManualSectionKept(username)) {
        return const DailyAiSuggestionSnapshot(
          enabled: false,
          showManualGenerateCard: true,
        );
      }
      final dismissedPrompt = await isPromptDismissed(username);
      if (!dismissedPrompt) {
        return const DailyAiSuggestionSnapshot(
          enabled: false,
          showFirstOpenPrompt: true,
        );
      }
      return const DailyAiSuggestionSnapshot(enabled: false);
    }

    if (!forceRefresh && cached != null && lastTriggeredDate == todayKey) {
      return DailyAiSuggestionSnapshot(enabled: enabled, suggestion: cached);
    }

    if (!await MinorModeService.instance.authorizeAiInteraction()) {
      return DailyAiSuggestionSnapshot(enabled: enabled, suggestion: cached);
    }

    final aiConfig = await configResolver();
    if (aiConfig == null) {
      return DailyAiSuggestionSnapshot(
        enabled: enabled,
        needsModelConfig: true,
      );
    }

    try {
      final contextConfig = await loadContextConfig(username);
      final memoryPromptBlock = contextConfig.isEnabled(DailyAiContextOption.memory)
          ? await AiMemoryService.loadPromptBlock(username)
          : '';
      final recentFeedbackBlock =
          contextConfig.isEnabled(DailyAiContextOption.recentFeedback)
          ? await loadRecentFeedbackBlock(username).catchError((_) => '')
          : '';
      final includePomodoro = contextConfig.isEnabled(
        DailyAiContextOption.pomodoro,
      );
      final todayPomodoroRecords =
          (!includePomodoro || loadTodayPomodoroRecords == null)
          ? const <PomodoroRecord>[]
          : await loadTodayPomodoroRecords().catchError(
              (_) => const <PomodoroRecord>[],
            );
      final yesterdayPomodoroRecords =
          (!includePomodoro ||
              !contextConfig.isEnabled(
                DailyAiContextOption.yesterdayAndTomorrow,
              ) ||
              loadYesterdayPomodoroRecords == null)
          ? const <PomodoroRecord>[]
          : await loadYesterdayPomodoroRecords().catchError(
              (_) => const <PomodoroRecord>[],
            );
      final todayTimeLogs =
          (!contextConfig.isEnabled(DailyAiContextOption.timeLogs) ||
              loadTodayTimeLogs == null)
          ? const <TimeLogItem>[]
          : await loadTodayTimeLogs().catchError(
              (_) => const <TimeLogItem>[],
            );
      final habitSummaryBlock =
          (!contextConfig.isEnabled(DailyAiContextOption.habits) ||
              loadHabitSummary == null)
          ? ''
          : await loadHabitSummary(current).catchError((_) => '');
      final challengeSummaryBlock =
          (!contextConfig.isEnabled(DailyAiContextOption.challenge) ||
              loadChallengeSummary == null)
          ? ''
          : await loadChallengeSummary(username, current).catchError((_) => '');
      final messages = buildPromptMessages(
        now: current,
        todos: todos,
        countdowns: countdowns,
        planBlocks: planBlocks,
        fixedSchedules: fixedSchedules,
        courses: courses,
        todayPomodoroRecords: todayPomodoroRecords,
        yesterdayPomodoroRecords: yesterdayPomodoroRecords,
        todayTimeLogs: todayTimeLogs,
        habitSummaryBlock: habitSummaryBlock,
        challengeSummaryBlock: challengeSummaryBlock,
        recentFeedbackBlock: recentFeedbackBlock,
        memoryPromptBlock: memoryPromptBlock,
        isManualRefresh: forceRefresh,
        contextConfig: contextConfig,
      );
      final rawReply = await completer(
        apiUrl: aiConfig.apiUrl,
        apiKey: aiConfig.apiKey,
        model: aiConfig.model,
        messages: messages,
        provider: aiConfig.provider,
        temperature: 0.4,
        maxTokens: 700,
        timeout: const Duration(seconds: 25),
        usageOperation: 'daily_suggestion',
      );
      final parsed = parseAiResponse(
        rawReply,
        dateKey: todayKey,
        generatedAtMs: current.millisecondsSinceEpoch,
      );
      await _saveCachedSuggestion(username, parsed);
      revision.value++;
      return DailyAiSuggestionSnapshot(enabled: enabled, suggestion: parsed);
    } catch (error) {
      return DailyAiSuggestionSnapshot(
        enabled: enabled,
        suggestion: cached,
        errorMessage: _formatErrorMessage(error),
      );
    }
  }

  static String _formatErrorMessage(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '').trim();
    if (text.length <= 80) return text;
    return '${text.substring(0, 80)}...';
  }

  @visibleForTesting
  static List<Map<String, dynamic>> buildPromptMessages({
    required DateTime now,
    required List<TodoItem> todos,
    required List<CountdownItem> countdowns,
    required List<TodoPlanBlock> planBlocks,
    required List<FixedScheduleItem> fixedSchedules,
    required List<CourseItem> courses,
    List<PomodoroRecord> todayPomodoroRecords = const [],
    List<PomodoroRecord> yesterdayPomodoroRecords = const [],
    List<TimeLogItem> todayTimeLogs = const [],
    String habitSummaryBlock = '',
    String challengeSummaryBlock = '',
    String recentFeedbackBlock = '',
    String memoryPromptBlock = '',
    bool isManualRefresh = false,
    DailyAiSuggestionContextConfig contextConfig =
        const DailyAiSuggestionContextConfig(),
  }) {
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final tomorrowStart = todayStart.add(const Duration(days: 1));
    final yesterdayStartMs = yesterdayStart.millisecondsSinceEpoch;
    final todayStartMs = todayStart.millisecondsSinceEpoch;
    final tomorrowStartMs = tomorrowStart.millisecondsSinceEpoch;
    final tomorrowNoonMs = tomorrowStart
        .add(const Duration(hours: 12))
        .millisecondsSinceEpoch;
    final upcomingEnd = todayStart.add(const Duration(days: 4));
    final todayKey = formatDateKey(now);
    final tomorrowKey = formatDateKey(tomorrowStart);
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final weekdayLabel = weekdays[now.weekday - 1];

    final activeTodos = todos
        .where((t) => !t.isDeleted && !t.isDone && !t.isSkipped)
        .toList();
    final todayDoneTodos = todos.where((t) {
      if (t.isDeleted || !t.isDone) return false;
      final doneAtMs = t.completedAt ?? t.updatedAt;
      return doneAtMs >= todayStartMs && doneAtMs < tomorrowStartMs;
    }).toList();
    final yesterdayDoneCount = todos.where((t) {
      if (t.isDeleted || !t.isDone) return false;
      final doneAtMs = t.completedAt ?? t.updatedAt;
      return doneAtMs >= yesterdayStartMs && doneAtMs < todayStartMs;
    }).length;

    final overdueTodos = <TodoItem>[];
    final todayTodos = <TodoItem>[];
    final upcomingTodos = <TodoItem>[];
    final unscheduledTodos = <TodoItem>[];

    for (final todo in activeTodos) {
      final due = todo.dueDate?.toLocal();
      if (due == null) {
        unscheduledTodos.add(todo);
      } else if (due.isBefore(todayStart)) {
        overdueTodos.add(todo);
      } else if (due.isBefore(tomorrowStart)) {
        todayTodos.add(todo);
      } else if (due.isBefore(upcomingEnd)) {
        upcomingTodos.add(todo);
      }
    }

    overdueTodos.sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
    todayTodos.sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
    upcomingTodos.sort((a, b) => a.dueDate!.compareTo(b.dueDate!));

    final todayCourses =
        courses.where((c) => !c.isDeleted && c.date == todayKey).toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final todaySchedules =
        fixedSchedules.where((s) => !s.isDeleted && s.date == todayKey).toList()
          ..sort((a, b) => (a.startTime ?? 0).compareTo(b.startTime ?? 0));

    final todayPlans =
        planBlocks
            .where(
              (p) =>
                  !p.isDeleted &&
                  p.endTime > todayStart.millisecondsSinceEpoch &&
                  p.startTime < tomorrowStart.millisecondsSinceEpoch,
            )
            .toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final upcomingCountdowns = countdowns.where((c) {
      if (c.isDeleted) return false;
      final target = DateTime(
        c.targetDate.year,
        c.targetDate.month,
        c.targetDate.day,
      );
      final diffDays = target.difference(todayStart).inDays;
      return diffDays >= 0 && diffDays <= 14;
    }).toList()..sort((a, b) => a.targetDate.compareTo(b.targetDate));

    final buffer = StringBuffer();
    buffer.writeln(
      '当前时间：${DateFormat('yyyy-MM-dd HH:mm').format(now)} $weekdayLabel'
      '（${isManualRefresh ? '用户手动刷新/重新评估' : '今日首次生成'}）',
    );
    buffer.writeln();

    void appendTodos(String label, List<TodoItem> list, int limit) {
      if (list.isEmpty) return;
      final countNote = list.length > limit
          ? '共${list.length}条，仅展示前$limit条'
          : '共${list.length}条';
      buffer.writeln('【$label（$countNote）】');
      for (final todo in list.take(limit)) {
        final dueText = todo.dueDate == null
            ? '未设截止日期'
            : DateFormat('MM-dd HH:mm').format(todo.dueDate!.toLocal());
        final recurrencePart = todo.recurrence != RecurrenceType.none
            ? ' | 重复'
            : '';
        final remark = todo.remark?.trim();
        final remarkPart = (remark != null && remark.isNotEmpty)
            ? ' | 备注:$remark'
            : '';
        buffer.writeln(
          '- [id:${todo.id}] ${todo.title} ($dueText$recurrencePart$remarkPart)',
        );
      }
      buffer.writeln();
    }

    appendTodos('已逾期未完成待办', overdueTodos, 8);
    appendTodos('今日到期/今日待办', todayTodos, 12);
    appendTodos('未来3天到期待办', upcomingTodos, 8);
    appendTodos('未安排日期的待办', unscheduledTodos, 8);

    if (contextConfig.isEnabled(DailyAiContextOption.completedTodos) &&
        todayDoneTodos.isNotEmpty) {
      buffer.writeln('【今日已完成待办（共${todayDoneTodos.length}条）】');
      for (final todo in todayDoneTodos.take(8)) {
        buffer.writeln('- ${todo.title}');
      }
      buffer.writeln();
    }

    if (todayCourses.isNotEmpty ||
        todaySchedules.isNotEmpty ||
        todayPlans.isNotEmpty) {
      buffer.writeln('【今日已安排时间（课程/固定日程/规划块）】');
      for (final course in todayCourses) {
        final start = DateFormat('HH:mm').format(
          DateTime.fromMillisecondsSinceEpoch(course.startTime).toLocal(),
        );
        final end = DateFormat(
          'HH:mm',
        ).format(DateTime.fromMillisecondsSinceEpoch(course.endTime).toLocal());
        final room = course.roomName.trim().isNotEmpty
            ? ' @${course.roomName.trim()}'
            : '';
        buffer.writeln('- 课程 $start-$end ${course.courseName}$room');
      }
      for (final schedule in todaySchedules) {
        final timeText = schedule.startTime == null
            ? '时间待定'
            : '${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(schedule.startTime!).toLocal())}'
                  '${schedule.endTime != null ? '-${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(schedule.endTime!).toLocal())}' : ''}';
        buffer.writeln('- 日程 $timeText ${schedule.title}');
      }
      for (final plan in todayPlans) {
        final start = DateFormat(
          'HH:mm',
        ).format(DateTime.fromMillisecondsSinceEpoch(plan.startTime).toLocal());
        final end = DateFormat(
          'HH:mm',
        ).format(DateTime.fromMillisecondsSinceEpoch(plan.endTime).toLocal());
        final title = plan.titleSnapshot?.trim().isNotEmpty == true
            ? plan.titleSnapshot!.trim()
            : '规划块';
        final statusText = _formatPlanStatus(plan.status);
        final todoRef = plan.todoId.trim().isNotEmpty
            ? ' | todoId:${plan.todoId}'
            : '';
        buffer.writeln('- 规划 $start-$end $title ($statusText$todoRef)');
      }
      buffer.writeln();
    }

    final freeSlots = contextConfig.isEnabled(DailyAiContextOption.freeSlots)
        ? _computeRemainingFreeSlots(
            now: now,
            todayStart: todayStart,
            courses: todayCourses,
            schedules: todaySchedules,
            plans: todayPlans,
          )
        : const <({int startMs, int endMs})>[];
    if (freeSlots.isNotEmpty) {
      buffer.writeln('【今日剩余可用空档（至23:00）】');
      for (final slot in freeSlots.take(6)) {
        final start = DateFormat(
          'HH:mm',
        ).format(DateTime.fromMillisecondsSinceEpoch(slot.startMs).toLocal());
        final end = DateFormat(
          'HH:mm',
        ).format(DateTime.fromMillisecondsSinceEpoch(slot.endMs).toLocal());
        final minutes = ((slot.endMs - slot.startMs) / 60000).round();
        buffer.writeln('- $start-$end ($minutes分钟)');
      }
      buffer.writeln();
    }

    final todayPomodoros = contextConfig.isEnabled(DailyAiContextOption.pomodoro)
        ? (todayPomodoroRecords.where((r) {
              if (r.isDeleted) return false;
              final endMs = r.endTime ?? r.startTime;
              return endMs >= todayStartMs && r.startTime < tomorrowStartMs;
            }).toList()
            ..sort((a, b) => a.startTime.compareTo(b.startTime)))
        : const <PomodoroRecord>[];

    final filteredTimeLogs =
        contextConfig.isEnabled(DailyAiContextOption.timeLogs)
        ? (todayTimeLogs.where((log) {
              if (log.isDeleted) return false;
              return log.endTime > todayStartMs &&
                  log.startTime < tomorrowStartMs;
            }).toList()
            ..sort((a, b) => a.startTime.compareTo(b.startTime)))
        : const <TimeLogItem>[];

    if (todayPomodoros.isNotEmpty) {
      final totalFocusMinutes =
          (PomodoroService.totalFocusSeconds(todayPomodoros) / 60).round();
      final completedCount = todayPomodoros
          .where((r) => r.status == PomodoroRecordStatus.completed)
          .length;
      buffer.writeln(
        '【今日番茄钟专注记录（共${todayPomodoros.length}次，完成$completedCount次，累计$totalFocusMinutes分钟）】',
      );
      for (final record in todayPomodoros.take(10)) {
        final start = DateFormat('HH:mm').format(
          DateTime.fromMillisecondsSinceEpoch(record.startTime).toLocal(),
        );
        final endText = record.endTime != null
            ? '-${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(record.endTime!).toLocal())}'
            : '';
        final title = record.todoTitle?.trim().isNotEmpty == true
            ? record.todoTitle!.trim()
            : '自由专注';
        final minutes = (record.effectiveDuration / 60).round();
        final statusLabel = switch (record.status) {
          PomodoroRecordStatus.completed => '已完成',
          PomodoroRecordStatus.interrupted => '已中断',
          PomodoroRecordStatus.switched => '已切换',
        };
        final note = record.note?.trim();
        final notePart = (note != null && note.isNotEmpty)
            ? ' | 备注:$note'
            : '';
        buffer.writeln(
          '- $start$endText $title ($minutes分钟, $statusLabel$notePart)',
        );
      }
      buffer.writeln();
    }

    if (filteredTimeLogs.isNotEmpty) {
      var totalLogMs = 0;
      for (final log in filteredTimeLogs) {
        final clampedStart = log.startTime < todayStartMs
            ? todayStartMs
            : log.startTime;
        final clampedEnd = log.endTime > tomorrowStartMs
            ? tomorrowStartMs
            : log.endTime;
        if (clampedEnd > clampedStart) {
          totalLogMs += clampedEnd - clampedStart;
        }
      }
      final totalLogMinutes = (totalLogMs / 60000).round();
      buffer.writeln(
        '【今日时间日志（共${filteredTimeLogs.length}条，累计$totalLogMinutes分钟）】',
      );
      for (final log in filteredTimeLogs.take(12)) {
        final clampedStart = log.startTime < todayStartMs
            ? todayStartMs
            : log.startTime;
        final clampedEnd = log.endTime > tomorrowStartMs
            ? tomorrowStartMs
            : log.endTime;
        final start = DateFormat(
          'HH:mm',
        ).format(DateTime.fromMillisecondsSinceEpoch(clampedStart).toLocal());
        final end = DateFormat(
          'HH:mm',
        ).format(DateTime.fromMillisecondsSinceEpoch(clampedEnd).toLocal());
        final minutes = ((clampedEnd - clampedStart) / 60000).round();
        final title = log.title.trim().isNotEmpty ? log.title.trim() : '未命名记录';
        final remark = log.remark?.trim();
        final remarkPart = (remark != null && remark.isNotEmpty)
            ? ' | 备注:$remark'
            : '';
        buffer.writeln('- $start-$end $title ($minutes分钟$remarkPart)');
      }
      buffer.writeln();
    }

    if (upcomingCountdowns.isNotEmpty) {
      buffer.writeln('【近期重要倒数日（14天内）】');
      for (final item in upcomingCountdowns.take(5)) {
        final target = DateTime(
          item.targetDate.year,
          item.targetDate.month,
          item.targetDate.day,
        );
        final daysLeft = target.difference(todayStart).inDays;
        buffer.writeln(
          '- ${item.title}（${daysLeft == 0 ? '就是今天' : '还有$daysLeft天'}）',
        );
      }
    }

    final includeRhythm = contextConfig.isEnabled(
      DailyAiContextOption.yesterdayAndTomorrow,
    );
    final filteredYesterdayPomodoros =
        (includeRhythm && contextConfig.isEnabled(DailyAiContextOption.pomodoro))
        ? yesterdayPomodoroRecords
              .where(
                (r) =>
                    !r.isDeleted &&
                    (r.endTime ?? r.startTime) >= yesterdayStartMs &&
                    r.startTime < todayStartMs,
              )
              .toList()
        : const <PomodoroRecord>[];
    final tomorrowMorningItems = <String>[];
    if (includeRhythm) {
      for (final course
          in courses
              .where(
                (c) =>
                    !c.isDeleted &&
                    c.date == tomorrowKey &&
                    c.startTime < tomorrowNoonMs,
              )
              .toList()
            ..sort((a, b) => a.startTime.compareTo(b.startTime))) {
        final start = DateFormat('HH:mm').format(
          DateTime.fromMillisecondsSinceEpoch(course.startTime).toLocal(),
        );
        tomorrowMorningItems.add('明早$start 课程:${course.courseName}');
      }
      for (final schedule
          in fixedSchedules
              .where(
                (s) =>
                    !s.isDeleted &&
                    s.date == tomorrowKey &&
                    (s.startTime == null || s.startTime! < tomorrowNoonMs),
              )
              .toList()
            ..sort((a, b) => (a.startTime ?? 0).compareTo(b.startTime ?? 0))) {
        final start = schedule.startTime == null
            ? '上午'
            : DateFormat('HH:mm').format(
                DateTime.fromMillisecondsSinceEpoch(
                  schedule.startTime!,
                ).toLocal(),
              );
        tomorrowMorningItems.add('明早$start 日程:${schedule.title}');
      }
    }

    if (includeRhythm &&
        (yesterdayDoneCount > 0 ||
            filteredYesterdayPomodoros.isNotEmpty ||
            tomorrowMorningItems.isNotEmpty)) {
      buffer.writeln('【昨日与明日节律参考】');
      if (yesterdayDoneCount > 0) {
        buffer.writeln('- 昨日完成待办：$yesterdayDoneCount 项');
      }
      if (filteredYesterdayPomodoros.isNotEmpty) {
        final yMinutes =
            (PomodoroService.totalFocusSeconds(filteredYesterdayPomodoros) /
                    60)
                .round();
        buffer.writeln(
          '- 昨日番茄专注：${filteredYesterdayPomodoros.length} 次，累计 $yMinutes 分钟',
        );
      }
      if (tomorrowMorningItems.isNotEmpty) {
        buffer.writeln(
          '- 明日上午安排：${tomorrowMorningItems.take(5).join('；')}',
        );
      }
      buffer.writeln();
    }

    if (contextConfig.isEnabled(DailyAiContextOption.habits) &&
        habitSummaryBlock.trim().isNotEmpty) {
      buffer.writeln(habitSummaryBlock.trim());
      buffer.writeln();
    }

    if (contextConfig.isEnabled(DailyAiContextOption.challenge) &&
        challengeSummaryBlock.trim().isNotEmpty) {
      buffer.writeln(challengeSummaryBlock.trim());
      buffer.writeln();
    }

    if (contextConfig.isEnabled(DailyAiContextOption.recentFeedback) &&
        recentFeedbackBlock.trim().isNotEmpty) {
      buffer.writeln(recentFeedbackBlock.trim());
      buffer.writeln();
    }

    if (activeTodos.isEmpty &&
        (!contextConfig.isEnabled(DailyAiContextOption.completedTodos) ||
            todayDoneTodos.isEmpty) &&
        todayCourses.isEmpty &&
        todaySchedules.isEmpty &&
        todayPlans.isEmpty &&
        todayPomodoros.isEmpty &&
        filteredTimeLogs.isEmpty &&
        (!contextConfig.isEnabled(DailyAiContextOption.habits) ||
            habitSummaryBlock.trim().isEmpty) &&
        (!contextConfig.isEnabled(DailyAiContextOption.challenge) ||
            challengeSummaryBlock.trim().isEmpty) &&
        upcomingCountdowns.isEmpty) {
      buffer.writeln('当前暂无待办、课程、日程、习惯或近期倒数日。请给出一条轻量、积极的今日启动建议。');
    }

    if (contextConfig.isEnabled(DailyAiContextOption.memory) &&
        memoryPromptBlock.trim().isNotEmpty) {
      buffer.writeln();
      buffer.writeln(memoryPromptBlock.trim());
    }

    const systemPrompt = '''
你是用户的个人效率与生活节奏伙伴。根据用户当前时段（首次生成或手动刷新）、待办（含今日已完成）、逾期事项、课程、固定日程、规划块、剩余可用空档、今日番茄钟与时间日志、习惯打卡、30天挑战、近期倒数日及昨日/明早节律，给出温暖、有人文关怀且可执行、不啰嗦的「今日行动建议」。

请严格输出纯 JSON 对象（不要使用 Markdown 代码块，不要输出额外解释），格式如下：
{
  "summary": "1-2句中文总览：带一句自然贴心的问候或节奏关怀（如结合早晚时段、今日已专注时长、任务轻重提醒劳逸结合），并点明今天最重要的重点（不超过65字）",
  "items": [
    {
      "title": "建议今天做的具体事项标题（不超过20字）",
      "reason": "简短理由、建议时段或温和提醒，如：今晚23:59截止 / 16:30-18:00空档推进（不超过24字）",
      "priority": "high | medium | low",
      "todoId": "若对应上方某条待办，填其 id；否则填 null"
    }
  ]
}

规则：
1. 语气真诚温和、适当体恤用户状态，不空洞说教，也不制造焦虑；任务较多或已逾期时鼓励先挑最关键的一两件轻装推进，避免一次性压垮自己。
2. 结合当前时间、今日已投入精力（已完成待办/番茄钟/时间日志）与明早安排：若已连续专注较多、日程已很满、已到傍晚/夜间或明早有早课/早会，优先肯定已完成的努力并建议关键收尾与休息留白，不要硬塞额外负担。
3. items 数量为 2 到 5 条；若用户几乎没有待办，可结合习惯打卡、30天挑战或照顾身心的轻量节奏给 1 到 3 条建议。
4. 优先关注已逾期、今日到期、近期倒数日关联事项，结合「今日剩余可用空档」安排时段，避免与已完成的规划块或已有日程冲突，也尽量避免重复推荐近期未采纳的事项。
5. 只输出合法 JSON。''';

    return [
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': buffer.toString().trim()},
    ];
  }

  static String _formatPlanStatus(TodoPlanStatus status) => switch (status) {
    TodoPlanStatus.planned => '待执行',
    TodoPlanStatus.finished => '已完成',
    TodoPlanStatus.delayed => '已延期',
    TodoPlanStatus.cancelled => '已取消',
    TodoPlanStatus.reminded => '已提醒',
    TodoPlanStatus.focusing => '进行中',
    TodoPlanStatus.missed => '未按时完成',
    TodoPlanStatus.skipped => '已跳过',
  };

  static List<({int startMs, int endMs})> _computeRemainingFreeSlots({
    required DateTime now,
    required DateTime todayStart,
    required List<CourseItem> courses,
    required List<FixedScheduleItem> schedules,
    required List<TodoPlanBlock> plans,
  }) {
    final dayMorningMs = todayStart
        .add(const Duration(hours: 7))
        .millisecondsSinceEpoch;
    final dayNightMs = todayStart
        .add(const Duration(hours: 23))
        .millisecondsSinceEpoch;
    final windowStartMs = now.millisecondsSinceEpoch > dayMorningMs
        ? now.millisecondsSinceEpoch
        : dayMorningMs;
    if (windowStartMs >= dayNightMs) return const [];

    final busy = <({int startMs, int endMs})>[];
    for (final c in courses) {
      if (c.endTime > windowStartMs && c.startTime < dayNightMs) {
        busy.add((startMs: c.startTime, endMs: c.endTime));
      }
    }
    for (final s in schedules) {
      if (s.startTime != null &&
          s.endTime != null &&
          s.endTime! > windowStartMs &&
          s.startTime! < dayNightMs) {
        busy.add((startMs: s.startTime!, endMs: s.endTime!));
      }
    }
    for (final p in plans) {
      if (p.status == TodoPlanStatus.cancelled ||
          p.status == TodoPlanStatus.skipped) {
        continue;
      }
      if (p.endTime > windowStartMs && p.startTime < dayNightMs) {
        busy.add((startMs: p.startTime, endMs: p.endTime));
      }
    }

    busy.sort((a, b) => a.startMs.compareTo(b.startMs));
    final merged = <({int startMs, int endMs})>[];
    for (final interval in busy) {
      if (merged.isEmpty || interval.startMs > merged.last.endMs) {
        merged.add(interval);
      } else if (interval.endMs > merged.last.endMs) {
        merged[merged.length - 1] = (
          startMs: merged.last.startMs,
          endMs: interval.endMs,
        );
      }
    }

    const minSlotMs = 15 * 60 * 1000;
    final free = <({int startMs, int endMs})>[];
    var cursor = windowStartMs;
    for (final interval in merged) {
      if (interval.startMs - cursor >= minSlotMs) {
        free.add((startMs: cursor, endMs: interval.startMs));
      }
      if (interval.endMs > cursor) {
        cursor = interval.endMs;
      }
    }
    if (dayNightMs - cursor >= minSlotMs) {
      free.add((startMs: cursor, endMs: dayNightMs));
    }
    return free;
  }

  @visibleForTesting
  static DailyAiSuggestion parseAiResponse(
    String rawReply, {
    required String dateKey,
    required int generatedAtMs,
  }) {
    final cleaned = _stripCodeFence(rawReply.trim());
    final jsonCandidate = _extractJsonObject(cleaned);
    if (jsonCandidate != null) {
      try {
        final decoded = jsonDecode(jsonCandidate);
        if (decoded is Map) {
          final parsed = DailyAiSuggestion.fromJson({
            ...Map<String, dynamic>.from(decoded),
            'dateKey': dateKey,
            'generatedAtMs': generatedAtMs,
            'isDismissed': false,
            'isExpanded': true,
          });
          if (parsed.summary.isNotEmpty || parsed.items.isNotEmpty) {
            return parsed;
          }
        }
      } catch (_) {
        // Fall back to plain text summary below.
      }
    }

    final fallbackSummary = cleaned.isEmpty
        ? '今天保持专注节奏，优先推进最重要的 1-2 件事。'
        : (cleaned.length > 140 ? '${cleaned.substring(0, 140)}...' : cleaned);
    return DailyAiSuggestion(
      dateKey: dateKey,
      summary: fallbackSummary,
      items: const [],
      generatedAtMs: generatedAtMs,
    );
  }

  static String _stripCodeFence(String text) {
    var result = text.trim();
    if (result.startsWith('```')) {
      final firstNewline = result.indexOf('\n');
      if (firstNewline != -1) {
        result = result.substring(firstNewline + 1);
      }
      if (result.endsWith('```')) {
        result = result.substring(0, result.length - 3);
      }
    }
    return result.trim();
  }

  static String? _extractJsonObject(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return null;
    return text.substring(start, end + 1);
  }
}
