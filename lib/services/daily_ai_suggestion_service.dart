import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'ai_chat_service.dart';
import 'ai_memory_service.dart';
import 'chat_storage_service.dart';
import 'llm_service.dart';
import 'minor_mode_service.dart';
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
    await prefs.setString(
      _scoped(_cacheKey, username),
      jsonEncode(suggestion.toJson()),
    );
    await prefs.setString(
      _scoped(_lastTriggeredDateKey, username),
      suggestion.dateKey,
    );
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
      final memoryPromptBlock = await AiMemoryService.loadPromptBlock(username);
      final messages = buildPromptMessages(
        now: current,
        todos: todos,
        countdowns: countdowns,
        planBlocks: planBlocks,
        fixedSchedules: fixedSchedules,
        courses: courses,
        memoryPromptBlock: memoryPromptBlock,
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
    String memoryPromptBlock = '',
  }) {
    final todayStart = DateTime(now.year, now.month, now.day);
    final tomorrowStart = todayStart.add(const Duration(days: 1));
    final upcomingEnd = todayStart.add(const Duration(days: 4));
    final todayKey = formatDateKey(now);
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final weekdayLabel = weekdays[now.weekday - 1];

    final activeTodos = todos
        .where((t) => !t.isDeleted && !t.isDone && !t.isSkipped)
        .toList();

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
      '当前时间：${DateFormat('yyyy-MM-dd HH:mm').format(now)} $weekdayLabel',
    );
    buffer.writeln();

    void appendTodos(String label, List<TodoItem> list, int limit) {
      if (list.isEmpty) return;
      buffer.writeln('【$label】');
      for (final todo in list.take(limit)) {
        final dueText = todo.dueDate == null
            ? '未设截止日期'
            : DateFormat('MM-dd HH:mm').format(todo.dueDate!.toLocal());
        final remark = todo.remark?.trim();
        final remarkPart = (remark != null && remark.isNotEmpty)
            ? ' | 备注:$remark'
            : '';
        buffer.writeln('- [id:${todo.id}] ${todo.title} ($dueText$remarkPart)');
      }
      buffer.writeln();
    }

    appendTodos('已逾期未完成待办', overdueTodos, 8);
    appendTodos('今日到期/今日待办', todayTodos, 12);
    appendTodos('未来3天到期待办', upcomingTodos, 8);
    appendTodos('未安排日期的待办', unscheduledTodos, 8);

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
        buffer.writeln('- 规划 $start-$end $title');
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

    if (activeTodos.isEmpty &&
        todayCourses.isEmpty &&
        todaySchedules.isEmpty &&
        todayPlans.isEmpty &&
        upcomingCountdowns.isEmpty) {
      buffer.writeln('当前暂无待办、课程、日程或近期倒数日。请给出一条轻量、积极的今日启动建议。');
    }

    if (memoryPromptBlock.trim().isNotEmpty) {
      buffer.writeln();
      buffer.writeln(memoryPromptBlock.trim());
    }

    const systemPrompt = '''
你是用户的个人效率与生活节奏伙伴。每天首次打开 App 时，根据用户当前时段、待办、逾期事项、课程、固定日程、规划块与倒数日，给出温暖、有人文关怀且可执行、不啰嗦的「今日行动建议」。

请严格输出纯 JSON 对象（不要使用 Markdown 代码块，不要输出额外解释），格式如下：
{
  "summary": "1-2句中文总览：带一句自然贴心的问候或节奏关怀（如结合早晚时段、任务轻重提醒劳逸结合），并点明今天最重要的重点（不超过65字）",
  "items": [
    {
      "title": "建议今天做的具体事项标题（不超过20字）",
      "reason": "简短理由、建议时段或温和提醒，如：今晚23:59截止 / 午休后精力更好时推进（不超过24字）",
      "priority": "high | medium | low",
      "todoId": "若对应上方某条待办，填其 id；否则填 null"
    }
  ]
}

规则：
1. 语气真诚温和、适当体恤用户状态，不空洞说教，也不制造焦虑；任务较多或已逾期时鼓励先挑最关键的一两件轻装推进，避免一次性压垮自己。
2. 结合当前时间与日程密度：若日程已很满或已到傍晚/夜间，优先建议关键收尾与休息留白，不要硬塞额外负担。
3. items 数量为 2 到 5 条；若用户几乎没有待办，可给 1 到 3 条轻松、照顾身心的今日节奏建议。
4. 优先关注已逾期、今日到期、近期倒数日关联事项，并避开已占用的课程/固定日程时段。
5. 只输出合法 JSON。''';

    return [
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': buffer.toString().trim()},
    ];
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
