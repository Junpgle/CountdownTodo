import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../models/ai_todo_action.dart';
import '../services/suggestion_feedback_service.dart';
import '../models/chat_message.dart';
import '../services/ai_action_parser.dart';
import '../services/ai_chat_service.dart';
import '../services/ai_todo_context_builder.dart';
import '../services/ai_todo_action_executor.dart';
import '../services/llm_service.dart';
import '../services/chat_storage_service.dart';
import '../services/pomodoro_control_service.dart';
import '../services/pomodoro_service.dart';
import '../screens/ai_assistant_tutorial_screen.dart';
import '../screens/settings/llm_config_page.dart';
import '../storage_service.dart';
import '../utils/page_transitions.dart';

class TodoChatScreen extends StatefulWidget {
  final String username;
  final List<Map<String, dynamic>> todos;
  final List<TodoGroup> todoGroups;
  final List<CourseItem> courses;
  final List<TimeLogItem> timeLogs;
  final List<PomodoroRecord> pomodoroRecords;
  final List<ConflictInfo> conflicts;
  final List<Team> teams;
  final List<CountdownItem> countdowns;
  final List<PomodoroTag> pomodoroTags;
  final List<AiTodoAction> initialCategorizationActions;
  final Function(TodoItem)? onTodoInserted;
  final Function(List<TodoItem>)? onTodosBatchInserted;
  final Function(List<TodoItem>)? onTodosUpdated;
  final Function(List<TodoItem> inserted, List<TodoItem> updated)?
      onTodosBatchAction;
  final Function(List<TodoGroup> groups)? onTodoGroupsChanged;

  const TodoChatScreen({
    super.key,
    required this.username,
    required this.todos,
    this.todoGroups = const [],
    this.courses = const [],
    this.timeLogs = const [],
    this.pomodoroRecords = const [],
    this.conflicts = const [],
    this.teams = const [],
    this.countdowns = const [],
    this.pomodoroTags = const [],
    this.initialCategorizationActions = const [],
    this.onTodoInserted,
    this.onTodosBatchInserted,
    this.onTodosUpdated,
    this.onTodosBatchAction,
    this.onTodoGroupsChanged,
  });

  @override
  State<TodoChatScreen> createState() => _TodoChatScreenState();
}

class _TodoChatScreenState extends State<TodoChatScreen> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  String _streamingContent = '';
  String _streamingReasoning = '';
  List<String> _suggestions = [];
  String _customPrompt = '';
  bool _promptEnabled = true;
  bool _deepThinking = false;
  String _chatModel = '';
  String _chatApiKey = '';
  String _chatApiUrl = '';
  String _chatProvider = '';
  String _globalModelName = '';
  String _globalProvider = '';
  String _lastRequestSmartContext = '';
  String _pendingManualOriginalText = '';
  String _pendingManualSmartContext = '';
  List<ChatSession> _sessions = [];
  bool _smartContext = true;
  bool _injectMoreContext = false;
  bool _useCustomInjectRange = false;
  DateTime? _customInjectStart;
  DateTime? _customInjectEnd;
  bool _inputHasText = false;
  String _liveSmartContextPreview = '';
  String _liveActionProtocolPreview = '';
  int _liveEstimatedTokens = 0;
  String? _activeSessionId;
  Map<String, int> _categoryReminderDefaults = {};
  List<TodoPlanBlock> _planBlocks = [];
  Completer<void>? _cancelGeneration;
  bool _classificationSuggestionInjected = false;

  // 🚀 宽屏适配相关
  bool _sidebarVisible = true;
  bool _actionRailCollapsed = false;
  bool get _isWide => MediaQuery.of(context).size.width >= 900;
  bool get _hasPendingActionMessages => _pendingActionMessages.isNotEmpty;
  int get _pendingActionCount => _pendingActionMessages.fold<int>(
        0,
        (sum, msg) =>
            sum +
            (msg.todoActions
                    ?.where((action) => !action.isAdded && !action.isIgnored)
                    .length ??
                0),
      );
  bool get _hasActionRailSpace {
    final width = MediaQuery.of(context).size.width;
    const actionRailWidth = 344.0;
    final historyWidth = _sidebarVisible ? 304.0 : 0.0;
    return width >= 900 && width - historyWidth - actionRailWidth >= 520;
  }

  bool get _shouldDetachActions =>
      _hasActionRailSpace && _hasPendingActionMessages;
  bool get _usesActionRail => _shouldDetachActions && !_actionRailCollapsed;

  @override
  void initState() {
    super.initState();
    _inputCtrl.addListener(_handleInputChanged);
    _initSessions();
    _loadPromptSettings();
    _loadChatConfig();
    _loadDeepThinking();
    _loadCategoryDefaults();
    _loadPlanBlocks();
  }

  Future<void> _loadCategoryDefaults() async {
    final username = widget.username;
    final defaults = await StorageService.getCategoryReminderMinutes(username);
    if (mounted) {
      setState(() {
        _categoryReminderDefaults = defaults;
      });
    }
  }

  Future<void> _loadPlanBlocks() async {
    final blocks = await StorageService.getPlanBlocks(widget.username);
    if (!mounted) return;
    setState(() {
      _planBlocks = blocks;
    });
  }

  @override
  void dispose() {
    _inputCtrl.removeListener(_handleInputChanged);
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _handleInputChanged() {
    final text = _inputCtrl.text.trim();
    final hasText = text.isNotEmpty;
    final preview = _buildSmartContextPreview(text);
    final actionPreview = _buildActionProtocolPreview(text);
    final estimatedTokens = _estimateTokensForPendingInput(text);
    if (hasText == _inputHasText &&
        preview == _liveSmartContextPreview &&
        actionPreview == _liveActionProtocolPreview &&
        estimatedTokens == _liveEstimatedTokens) {
      return;
    }
    setState(() {
      _inputHasText = hasText;
      _liveSmartContextPreview = preview;
      _liveActionProtocolPreview = actionPreview;
      _liveEstimatedTokens = estimatedTokens;
    });
  }

  String _buildSmartContextPreview(String userText) {
    if (!_smartContext || userText.isEmpty) return '';
    final contextQueryText = _buildContextQueryText(userText);
    return AiTodoContextBuilder.buildContextInjectionSummary(
          userMessage: contextQueryText,
          courses: widget.courses,
          timeLogs: widget.timeLogs,
          todoGroups: widget.todoGroups,
          pomodoroRecords: widget.pomodoroRecords,
          planBlocks: _planBlocks,
          todos: widget.todos,
          countdowns: widget.countdowns,
          pomodoroTags: widget.pomodoroTags,
          conflicts: widget.conflicts,
          teams: widget.teams,
          now: DateTime.now(),
        ) ??
        '';
  }

  String _buildContextQueryText(String userText) {
    if (_useCustomInjectRange &&
        _customInjectStart != null &&
        _customInjectEnd != null) {
      final start = DateFormat('yyyy-MM-dd').format(_customInjectStart!);
      final end = DateFormat('yyyy-MM-dd').format(_customInjectEnd!);
      return '$userText，并使用自定义注入范围 $start 至 $end';
    }
    if (!_injectMoreContext) return userText;
    if (userText.contains('未来30天')) return userText;
    return '$userText，并扩大到未来30天范围';
  }

  String _buildActionProtocolPreview(String userText) {
    if (userText.isEmpty) return '';
    final prompt = AiTodoContextBuilder.buildActionProtocolPrompt(userText);
    final categories = <String>[];
    void addIf(bool cond, String label) {
      if (cond && !categories.contains(label)) categories.add(label);
    }

    addIf(
      prompt.contains('create_todo') ||
          prompt.contains('update_todo') ||
          prompt.contains('complete_todo') ||
          prompt.contains('delete_todo') ||
          prompt.contains('reschedule_todo') ||
          prompt.contains('bulk_reschedule') ||
          prompt.contains('categorize_todo') ||
          prompt.contains('split_todo') ||
          prompt.contains('merge_todos') ||
          prompt.contains('plan_todos'),
      '待办相关',
    );
    addIf(
      prompt.contains('create_plan_block') ||
          prompt.contains('update_plan_block') ||
          prompt.contains('reschedule_plan_blocks') ||
          prompt.contains('delete_plan_block') ||
          prompt.contains('skip_plan_block') ||
          prompt.contains('start_plan_block_pomodoro'),
      '规划块相关',
    );
    addIf(
      prompt.contains('create_time_log') ||
          prompt.contains('update_time_log') ||
          prompt.contains('delete_time_log') ||
          prompt.contains('start_pomodoro') ||
          prompt.contains('stop_pomodoro'),
      '专注相关',
    );
    addIf(
      prompt.contains('create_countdown') ||
          prompt.contains('update_countdown') ||
          prompt.contains('complete_countdown') ||
          prompt.contains('delete_countdown'),
      '倒计时相关',
    );
    addIf(
      prompt.contains('create_todo_group') ||
          prompt.contains('update_todo_group') ||
          prompt.contains('delete_todo_group'),
      '分类相关',
    );
    addIf(
      prompt.contains('create_pomodoro_tag') ||
          prompt.contains('update_pomodoro_tag') ||
          prompt.contains('delete_pomodoro_tag'),
      '标签相关',
    );

    if (categories.isEmpty) return '动作协议：基础待办相关';
    return '动作协议：${categories.join('、')}';
  }

  Future<void> _pickCustomInjectRange() async {
    final now = DateTime.now();
    final first = DateTime(now.year - 2, 1, 1);
    final last = DateTime(now.year + 2, 12, 31);
    final start = await showDatePicker(
      context: context,
      initialDate: _customInjectStart ?? now,
      firstDate: first,
      lastDate: last,
      helpText: '选择注入开始日期',
    );
    if (start == null || !mounted) return;
    final end = await showDatePicker(
      context: context,
      initialDate: _customInjectEnd ?? start,
      firstDate: start,
      lastDate: last,
      helpText: '选择注入结束日期',
    );
    if (end == null || !mounted) return;
    setState(() {
      _useCustomInjectRange = true;
      _customInjectStart = DateTime(start.year, start.month, start.day);
      _customInjectEnd = DateTime(end.year, end.month, end.day);
      _injectMoreContext = false;
      _liveSmartContextPreview =
          _buildSmartContextPreview(_inputCtrl.text.trim());
      _liveActionProtocolPreview =
          _buildActionProtocolPreview(_inputCtrl.text.trim());
      _liveEstimatedTokens =
          _estimateTokensForPendingInput(_inputCtrl.text.trim());
    });
  }

  int _estimateTokensForPendingInput(String text) {
    if (text.isEmpty) return 0;
    final messages = _buildApiMessages(
      pendingUserText: text,
      trackSmartContext: false,
    );
    return _estimateRequestTokens(messages);
  }

  int _estimateRequestTokens(List<Map<String, String>> messages) {
    var total = 2;
    for (final msg in messages) {
      total += 4;
      total += _estimateTextTokens(msg['role'] ?? '');
      total += _estimateTextTokens(msg['content'] ?? '');
    }
    return total;
  }

  int _estimateTextTokens(String text) {
    if (text.isEmpty) return 0;
    final cjk = RegExp(r'[\u4E00-\u9FFF]').allMatches(text).length;
    final other = text.length - cjk;
    final cjkTokens = (cjk / 1.6).ceil();
    final otherTokens = (other / 4).ceil();
    return cjkTokens + otherTokens;
  }

  Future<void> _initSessions() async {
    var sessions = await ChatStorageService.loadSessions();
    final activeId = await ChatStorageService.getActiveSessionId();

    if (sessions.isEmpty) {
      final newSession = await ChatStorageService.createSession();
      sessions = [newSession];
      if (mounted) {
        setState(() {
          _sessions = sessions;
          _activeSessionId = newSession.id;
        });
        _loadHistory();
      }
    } else {
      if (mounted) {
        setState(() {
          _sessions = sessions;
          _activeSessionId = activeId ?? sessions.first.id;
        });
        _loadHistory();
      }
    }
  }

  Future<void> _switchSession(String sessionId) async {
    await ChatStorageService.setActiveSessionId(sessionId);
    if (mounted) {
      setState(() {
        _activeSessionId = sessionId;
        _messages = [];
        _suggestions = [];
        _streamingContent = '';
      });
    }
    _loadHistory();
  }

  Future<void> _newSession() async {
    final newSession = await ChatStorageService.createSession();
    if (mounted) {
      setState(() {
        _sessions.insert(0, newSession);
        _activeSessionId = newSession.id;
        _messages = [];
        _suggestions = [];
        _streamingContent = '';
      });
    }
  }

  Future<void> _deleteSession(String sessionId) async {
    if (_sessions.length <= 1) {
      await ChatStorageService.deleteSession(sessionId);
      final newSession = await ChatStorageService.createSession();
      if (mounted) {
        setState(() {
          _sessions = [newSession];
          _activeSessionId = newSession.id;
          _messages = [];
          _suggestions = [];
          _streamingContent = '';
        });
      }
      return;
    }

    await ChatStorageService.deleteSession(sessionId);
    final sessions = await ChatStorageService.loadSessions();
    if (mounted) {
      setState(() {
        _sessions = sessions;
        if (_activeSessionId == sessionId) {
          _activeSessionId = sessions.first.id;
          _messages = [];
          _suggestions = [];
          _streamingContent = '';
        }
      });
      if (_activeSessionId != sessionId) {
        _loadHistory();
      }
    }
  }

  Future<void> _loadHistory() async {
    final history = await ChatStorageService.loadHistory(_activeSessionId);
    if (mounted) {
      setState(() => _messages = history);
      _injectInitialCategorizationSuggestion();
      _scrollToBottom();
    }
  }

  void _injectInitialCategorizationSuggestion() {
    if (_classificationSuggestionInjected ||
        widget.initialCategorizationActions.isEmpty ||
        _pendingActionMessages.isNotEmpty) {
      return;
    }
    _classificationSuggestionInjected = true;
    final actions = widget.initialCategorizationActions;
    final lines = actions.map((action) {
      final groupName = action.metadata['groupName']?.toString() ??
          _getGroupName(action.groupId);
      final priority = action.metadata['priorityLabel']?.toString();
      final tags = action.metadata['tags'] is List
          ? (action.metadata['tags'] as List).map((e) => e.toString()).toList()
          : const <String>[];
      final extra = [
        if (priority != null && priority.isNotEmpty) priority,
        if (tags.isNotEmpty) tags.join('、'),
      ].join(' · ');
      return '- ${action.title ?? '未命名待办'} -> $groupName${extra.isEmpty ? '' : ' ($extra)'}';
    }).join('\n');

    _messages.add(
      ChatMessage(
        role: ChatRole.assistant,
        content: '打开时我先做了一轮待办分类扫描，建议这样整理：\n\n$lines',
        todoActions: actions,
      ),
    );
    _actionRailCollapsed = false;
  }

  Future<void> _loadPromptSettings() async {
    final prompt = await ChatStorageService.getCustomPrompt();
    final enabled = await ChatStorageService.isPromptEnabled();
    if (mounted) {
      setState(() {
        _customPrompt = prompt;
        _promptEnabled = enabled;
      });
    }
  }

  Future<void> _loadChatConfig() async {
    final config = await ChatStorageService.getChatConfig();
    final globalConfig = await LLMService.getConfig();
    if (mounted) {
      setState(() {
        if (config != null) {
          _chatModel = config['model'] ?? '';
          _chatApiKey = config['apiKey'] ?? '';
          _chatApiUrl = config['apiUrl'] ?? '';
          _chatProvider = config['provider'] ?? '';
        }
        _globalModelName = globalConfig?.model ?? '';
        _globalProvider = globalConfig?.provider ?? '';
      });
    }
  }

  Future<void> _loadDeepThinking() async {
    final enabled = await ChatStorageService.isDeepThinkingEnabled();
    if (mounted) {
      setState(() => _deepThinking = enabled);
    }
  }

  Future<void> _openTutorialPage() async {
    await Navigator.of(context).push(
      PageTransitions.material(
        builder: (_) => const AiAssistantTutorialScreen(),
      ),
    );
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _buildSystemPrompt() {
    return AiTodoContextBuilder.buildLeanSystemPrompt(
      customPrompt: _customPrompt,
      promptEnabled: _promptEnabled,
    );
  }

  static const int _maxContextMessages = 15;

  List<Map<String, String>> _buildApiMessages({
    String? pendingUserText,
    bool trackSmartContext = true,
  }) {
    final List<Map<String, String>> apiMessages = [
      {'role': 'system', 'content': _buildSystemPrompt()},
    ];
    final protocolSourceText = pendingUserText?.trim().isNotEmpty == true
        ? pendingUserText!.trim()
        : _latestUserTextFromHistory();
    if (protocolSourceText.isNotEmpty) {
      apiMessages.add({
        'role': 'system',
        'content': AiTodoContextBuilder.buildActionProtocolPrompt(
          protocolSourceText,
        ),
      });
    }

    final sourceMessages = <ChatMessage>[
      ..._messages,
      if (pendingUserText != null && pendingUserText.trim().isNotEmpty)
        ChatMessage(role: ChatRole.user, content: pendingUserText.trim()),
    ];

    if (sourceMessages.length <= _maxContextMessages) {
      for (final msg in sourceMessages) {
        apiMessages.add({
          'role': msg.role == ChatRole.user ? 'user' : 'assistant',
          'content': msg.content,
        });
      }
    } else {
      final firstUserMsg = sourceMessages.firstWhere(
        (m) => m.role == ChatRole.user,
        orElse: () => sourceMessages.first,
      );
      apiMessages.add({
        'role': 'user',
        'content': firstUserMsg.content,
      });

      final summaryMsg = _buildContextSummary();
      if (summaryMsg.isNotEmpty) {
        apiMessages.add({
          'role': 'assistant',
          'content': summaryMsg,
        });
      }

      final recentCount = _maxContextMessages - 2;
      final startIndex = sourceMessages.length - recentCount;
      final recentMessages =
          sourceMessages.sublist(startIndex > 0 ? startIndex : 0);
      for (final msg in recentMessages) {
        if (msg.content == firstUserMsg.content) continue;
        apiMessages.add({
          'role': msg.role == ChatRole.user ? 'user' : 'assistant',
          'content': msg.content,
        });
      }
    }

    final smartContext = _injectContext(apiMessages);
    if (trackSmartContext) {
      _lastRequestSmartContext = smartContext;
    }
    return apiMessages;
  }

  String _latestUserTextFromHistory() {
    for (int i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].role == ChatRole.user &&
          _messages[i].content.trim().isNotEmpty) {
        return _messages[i].content.trim();
      }
    }
    return '';
  }

  /// 根据最后一条用户消息的关键词，按需注入课程/时间日志/冲突/团队上下文。
  String _injectContext(List<Map<String, String>> apiMessages) {
    if (!_smartContext) return '';
    // 找到最后一条 user 消息
    int lastUserIdx = -1;
    for (int i = apiMessages.length - 1; i >= 0; i--) {
      if (apiMessages[i]['role'] == 'user') {
        lastUserIdx = i;
        break;
      }
    }
    if (lastUserIdx == -1) return '';

    final userText = apiMessages[lastUserIdx]['content'] ?? '';
    final contextQueryText = _buildContextQueryText(userText);
    final injection = AiTodoContextBuilder.buildContextInjection(
      userMessage: contextQueryText,
      courses: widget.courses,
      timeLogs: widget.timeLogs,
      todoGroups: widget.todoGroups,
      pomodoroRecords: widget.pomodoroRecords,
      planBlocks: _planBlocks,
      todos: widget.todos,
      countdowns: widget.countdowns,
      pomodoroTags: widget.pomodoroTags,
      conflicts: widget.conflicts,
      teams: widget.teams,
      now: DateTime.now(),
    );
    if (injection != null) {
      apiMessages[lastUserIdx] = {
        'role': 'user',
        'content': '$injection\n\n$userText',
      };
      return injection;
    }
    return '';
  }

  String _buildContextSummary() {
    final omittedCount = _messages.length - _maxContextMessages;
    if (omittedCount <= 0) return '';

    final userMsgCount = _messages
        .take(_messages.length - _maxContextMessages)
        .where((m) => m.role == ChatRole.user)
        .length;
    final assistantMsgCount = _messages
        .take(_messages.length - _maxContextMessages)
        .where((m) => m.role == ChatRole.assistant)
        .length;

    return '[已省略 $omittedCount 条历史消息（用户 $userMsgCount 条，助手 $assistantMsgCount 条）。对话已围绕待办事项展开，用户已了解基本功能，继续当前话题即可。]';
  }

  Future<void> _sendMessage() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _isLoading) return;

    String model = _chatModel;
    String apiKey = _chatApiKey;
    String apiUrl = _chatApiUrl;
    String provider = _chatProvider;

    if (model.isEmpty || apiKey.isEmpty) {
      final globalConfig = await LLMService.getConfig();
      if (globalConfig != null && globalConfig.isConfigured) {
        model = globalConfig.model;
        apiKey = globalConfig.apiKey;
        apiUrl = globalConfig.apiUrl;
        provider = globalConfig.provider;
      } else {
        if (!mounted) return;
        final goToSettings = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('未配置大模型'),
            content: const Text(
              '可以先配置API地址和密钥，也可以复制完整提示词到外部AI，稍后把回复粘贴回来识别。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx, false);
                  _copyManualPromptFromInput();
                },
                icon: const Icon(Icons.content_copy_rounded, size: 16),
                label: const Text('复制提示词'),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx, false);
                  _pasteManualReplyFromClipboard();
                },
                icon: const Icon(Icons.assignment_rounded, size: 16),
                label: const Text('粘贴识别'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('去配置'),
              ),
            ],
          ),
        );
        if (goToSettings == true && mounted) {
          await _openLlmConfigPage();
        }
        return;
      }
    }

    if (apiUrl.isEmpty) apiUrl = AiChatService.defaultApiUrl;

    final userMsg = ChatMessage(
      role: ChatRole.user,
      content: text,
    );

    setState(() {
      _messages.add(userMsg);
      _streamingContent = '';
      _isLoading = true;
    });
    await ChatStorageService.addMessage(userMsg);
    _inputCtrl.clear();
    _scrollToBottom();

    _cancelGeneration = Completer<void>();

    try {
      final List<Map<String, String>> apiMessages = _buildApiMessages();
      String fullContent = '';
      String reasoningContent = '';

      await for (final chunk in AiChatService.streamChat(
        apiUrl: apiUrl,
        apiKey: apiKey,
        model: model,
        messages: apiMessages,
        deepThinking: _deepThinking,
        provider: provider,
        cancelToken: _cancelGeneration,
      )) {
        if (chunk.reasoningContent.isNotEmpty) {
          reasoningContent += chunk.reasoningContent;
          if (mounted) {
            setState(() {
              _streamingReasoning = reasoningContent;
            });
            _scrollToBottom();
          }
        }
        if (chunk.content.isNotEmpty) {
          fullContent += chunk.content;
          if (mounted) {
            setState(() {
              _streamingContent = fullContent;
            });
            _scrollToBottom();
          }
        }
      }

      // 用户主动打断：保存已有内容为部分回复
      if (_cancelGeneration?.isCompleted == true) {
        if (fullContent.isNotEmpty || reasoningContent.isNotEmpty) {
          final existingTodoTitles = {
            for (final todo in widget.todos)
              if (todo['id'] != null)
                todo['id'].toString(): '${todo['title'] ?? ''}',
          };
          final todoActions = AiActionParser.extractTodoActions(
            fullContent,
            originalText: text,
            existingTodoTitles: existingTodoTitles,
          );
          final cleanContent = AiActionParser.cleanActionContent(fullContent);
          setState(() {
            final assistantMsg = ChatMessage(
              role: ChatRole.assistant,
              content: '$cleanContent\n\n*(已中断)*',
              rawContent: fullContent,
              reasoningContent: reasoningContent,
              smartContext: _lastRequestSmartContext,
              todoActions: todoActions.isNotEmpty ? todoActions : null,
            );
            _messages.add(assistantMsg);
            _streamingContent = '';
            _streamingReasoning = '';
            _isLoading = false;
            _cancelGeneration = null;
            ChatStorageService.addMessage(assistantMsg);
          });
        } else {
          setState(() {
            _streamingContent = '';
            _streamingReasoning = '';
            _isLoading = false;
            _cancelGeneration = null;
          });
        }
        _scrollToBottom();
        return;
      }

      if (fullContent.isEmpty && reasoningContent.isEmpty) {
        throw Exception('未收到有效回复');
      }

      final existingTodoTitles = {
        for (final todo in widget.todos)
          if (todo['id'] != null)
            todo['id'].toString(): '${todo['title'] ?? ''}',
      };
      final todoActions = AiActionParser.extractTodoActions(
        fullContent,
        originalText: text,
        existingTodoTitles: existingTodoTitles,
      );
      final inlineSuggestions = AiActionParser.extractSuggestions(fullContent);
      final cleanContent = AiActionParser.cleanActionContent(fullContent);

      setState(() {
        final assistantMsg = ChatMessage(
          role: ChatRole.assistant,
          content: cleanContent,
          rawContent: fullContent,
          reasoningContent: reasoningContent,
          smartContext: _lastRequestSmartContext,
          todoActions: todoActions.isNotEmpty ? todoActions : null,
        );

        _messages.add(assistantMsg);
        _streamingContent = '';
        _streamingReasoning = '';
        _isLoading = false;
        _cancelGeneration = null;
        _suggestions = inlineSuggestions.isNotEmpty
            ? inlineSuggestions
            : _getSmartSuggestions();
        if (todoActions.isNotEmpty) {
          _actionRailCollapsed = false;
        }
        ChatStorageService.addMessage(assistantMsg);
      });
      _scrollToBottom();
      _generateSessionTitle();
    } catch (e) {
      if (mounted) {
        setState(() {
          _streamingContent = '';
          _isLoading = false;
          _cancelGeneration = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI回复失败: $e')),
        );
      }
    }
  }

  Future<void> _copyManualPromptFromInput() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;

    final apiMessages = _buildApiMessages(pendingUserText: text);
    final manualPrompt =
        AiTodoContextBuilder.buildManualCopyPrompt(apiMessages);
    _pendingManualOriginalText = text;
    _pendingManualSmartContext = _lastRequestSmartContext;
    await Clipboard.setData(ClipboardData(text: manualPrompt));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制完整提示词，可粘贴到外部AI')),
    );
  }

  Future<void> _pasteManualReplyFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final replyCtrl = TextEditingController(text: data?.text?.trim() ?? '');

    final reply = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('粘贴AI回复并识别'),
        content: SizedBox(
          width: MediaQuery.of(ctx).size.width * 0.86,
          child: TextField(
            controller: replyCtrl,
            maxLines: 12,
            minLines: 6,
            decoration: const InputDecoration(
              hintText: '粘贴外部AI返回的完整内容，包含正文和 ACTION 操作块',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, replyCtrl.text),
            icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
            label: const Text('识别'),
          ),
        ],
      ),
    );
    replyCtrl.dispose();

    if (reply == null || reply.trim().isEmpty) return;
    await _importManualAiReply(reply.trim());
  }

  Future<void> _importManualAiReply(String fullContent) async {
    final originalText = _pendingManualOriginalText.isNotEmpty
        ? _pendingManualOriginalText
        : (_inputCtrl.text.trim().isNotEmpty
            ? _inputCtrl.text.trim()
            : _lastUserContent());
    final smartContext = _pendingManualSmartContext;
    final existingTodoTitles = {
      for (final todo in widget.todos)
        if (todo['id'] != null) todo['id'].toString(): '${todo['title'] ?? ''}',
    };
    final todoActions = AiActionParser.extractTodoActions(
      fullContent,
      originalText: originalText,
      existingTodoTitles: existingTodoTitles,
    );
    final inlineSuggestions = AiActionParser.extractSuggestions(fullContent);
    final cleanContent = AiActionParser.cleanActionContent(fullContent);

    final newMessages = <ChatMessage>[];
    if (originalText.isNotEmpty && _lastUserContent() != originalText) {
      newMessages.add(ChatMessage(role: ChatRole.user, content: originalText));
    }
    final assistantMsg = ChatMessage(
      role: ChatRole.assistant,
      content: cleanContent.isEmpty ? fullContent : cleanContent,
      rawContent: fullContent,
      smartContext: smartContext,
      todoActions: todoActions.isNotEmpty ? todoActions : null,
    );
    newMessages.add(assistantMsg);

    setState(() {
      _messages.addAll(newMessages);
      _streamingContent = '';
      _streamingReasoning = '';
      _isLoading = false;
      _cancelGeneration = null;
      _suggestions = inlineSuggestions.isNotEmpty
          ? inlineSuggestions
          : _getSmartSuggestions();
      if (todoActions.isNotEmpty) {
        _actionRailCollapsed = false;
      }
      if (_inputCtrl.text.trim() == originalText) {
        _inputCtrl.clear();
      }
      _pendingManualOriginalText = '';
      _pendingManualSmartContext = '';
    });
    for (final message in newMessages) {
      await ChatStorageService.addMessage(message);
    }
    _scrollToBottom();
    _generateSessionTitle();
  }

  String _lastUserContent() {
    for (final message in _messages.reversed) {
      if (message.role == ChatRole.user) return message.content;
    }
    return '';
  }

  void _stopGeneration() {
    if (_cancelGeneration != null && !_cancelGeneration!.isCompleted) {
      _cancelGeneration!.complete();
    }
  }

  void _retryLastMessage() {
    // 找到最后一条用户消息
    final lastUserMsg = _messages.lastWhere(
      (m) => m.role == ChatRole.user,
      orElse: () => ChatMessage(role: ChatRole.user, content: ''),
    );
    if (lastUserMsg.content.isEmpty) return;
    // 删除最后一条助手消息（如果有）
    if (_messages.isNotEmpty && _messages.last.role == ChatRole.assistant) {
      _messages.removeLast();
    }
    _inputCtrl.text = lastUserMsg.content;
    _sendMessage();
  }

  Future<void> _generateSessionTitle() async {
    if (_messages.isEmpty) return;
    final session = _sessions.firstWhere(
      (s) => s.id == _activeSessionId,
      orElse: () => ChatSession(title: '新对话'),
    );
    if (session.title != '新对话') return;

    try {
      String model = _chatModel;
      String apiKey = _chatApiKey;
      String apiUrl = _chatApiUrl;

      if (model.isEmpty || apiKey.isEmpty) {
        final globalConfig = await LLMService.getConfig();
        if (globalConfig != null && globalConfig.isConfigured) {
          model = globalConfig.model;
          apiKey = globalConfig.apiKey;
          apiUrl = globalConfig.apiUrl;
        } else {
          return;
        }
      }

      if (apiUrl.isEmpty) apiUrl = AiChatService.defaultApiUrl;

      final firstUserMsg = _messages.firstWhere(
        (m) => m.role == ChatRole.user,
        orElse: () => _messages.first,
      );

      String title = await AiChatService.completeChat(
        apiUrl: apiUrl,
        apiKey: apiKey,
        model: model,
        messages: [
          {
            'role': 'system',
            'content': '请根据用户的第一个问题生成一个简短的对话标题，不超过10个字，只返回标题文本，不要任何其他内容。',
          },
          {
            'role': 'user',
            'content': firstUserMsg.content,
          },
        ],
      );
      title = title.trim().replaceAll('"', '').replaceAll("'", '');
      if (title.length > 15) title = '${title.substring(0, 15)}...';
      if (title.isEmpty) {
        final content = firstUserMsg.content;
        title = content.substring(0, content.length > 15 ? 15 : content.length);
      }

      await ChatStorageService.updateSessionTitle(session.id, title);
      if (mounted) {
        setState(() {
          final idx = _sessions.indexWhere((s) => s.id == session.id);
          if (idx != -1) {
            _sessions[idx].title = title;
            _sessions[idx].updatedAt = DateTime.now();
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空聊天记录'),
        content: const Text('确定要清空所有聊天记录吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ChatStorageService.clearHistory();
      if (mounted) {
        setState(() => _messages = []);
      }
    }
  }

  Future<void> _showPromptSettings() async {
    final promptCtrl = TextEditingController(text: _customPrompt);
    bool enabled = _promptEnabled;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('提示词设置'),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.85,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用自定义提示词'),
                    subtitle: const Text('关闭后将使用默认提示词'),
                    value: enabled,
                    onChanged: (val) {
                      setDialogState(() => enabled = val);
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '提示词内容',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: promptCtrl,
                    maxLines: 12,
                    minLines: 6,
                    enabled: enabled,
                    decoration: InputDecoration(
                      hintText:
                          '输入自定义提示词...\n\n可用变量：\n{now} - 当前时间\n{todos} - 待办清单',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          promptCtrl.text = ChatStorageService.defaultPrompt;
                          setDialogState(() => enabled = true);
                        },
                        icon: const Icon(Icons.restore),
                        label: const Text('恢复默认'),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () {
                          _showPromptPreview(
                            promptCtrl.text,
                            enabled,
                          );
                        },
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text('预览'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                await ChatStorageService.saveCustomPrompt(promptCtrl.text);
                await ChatStorageService.setPromptEnabled(enabled);
                if (mounted) {
                  setState(() {
                    _customPrompt = promptCtrl.text;
                    _promptEnabled = enabled;
                  });
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _showPromptPreview(String prompt, bool enabled) {
    final resolvedPrompt = AiTodoContextBuilder.buildPromptPreview(
      customPrompt: prompt,
      promptEnabled: enabled,
      todos: widget.todos,
      todoGroups: widget.todoGroups,
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示词预览'),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.85,
          height: 400,
          child: SingleChildScrollView(
            child: SelectableText(
              resolvedPrompt,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: _buildResponsiveAppBar(isDark, colorScheme),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 900) {
            return _buildWideLayout(
              isDark,
              colorScheme,
            );
          }
          return _buildMobileLayout(isDark, colorScheme);
        },
      ),
    );
  }

  PreferredSizeWidget _buildResponsiveAppBar(
      bool isDark, ColorScheme colorScheme) {
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 1,
      backgroundColor: colorScheme.surface,
      surfaceTintColor: colorScheme.surfaceTint,
      centerTitle: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        onPressed: () => Navigator.pop(context),
        tooltip: '返回',
      ),
      title: Column(
        children: [
          Text(
            _getCurrentSessionTitle(),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.25),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              _isLoading ? '正在思考...' : 'AI 助手在线',
              key: ValueKey(_isLoading),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.normal,
                color: _isLoading
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(
            _isWide
                ? (_sidebarVisible
                    ? Icons.keyboard_double_arrow_left_rounded
                    : Icons.keyboard_double_arrow_right_rounded)
                : Icons.history_rounded,
            size: 22,
          ),
          onPressed: _isWide
              ? () => setState(() => _sidebarVisible = !_sidebarVisible)
              : _showHistorySidebar,
          tooltip: _isWide ? (_sidebarVisible ? '隐藏侧边栏' : '显示侧边栏') : '历史对话',
        ),
        IconButton(
          icon: const Icon(Icons.add_comment_rounded, size: 22),
          onPressed: _newSession,
          tooltip: '新建对话',
        ),
        IconButton(
          icon: const Icon(Icons.tune_rounded, size: 22),
          onPressed: _showPromptSettings,
          tooltip: '提示词设置',
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildWideLayout(
    bool isDark,
    ColorScheme colorScheme,
  ) {
    final useActionRail = _usesActionRail;
    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          width: _sidebarVisible ? 304 : 0,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(
              right: BorderSide(
                color: colorScheme.outlineVariant.withValues(
                  alpha: _sidebarVisible ? 0.7 : 0,
                ),
              ),
            ),
          ),
          child: ClipRect(
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: _sidebarVisible ? 1 : 0,
              child: SizedBox(
                width: 304,
                child: _buildHistorySidebarContent(context, isWideMode: true),
              ),
            ),
          ),
        ),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: useActionRail ? 760 : 920,
                    ),
                    child: _buildMessageList(isDark, colorScheme),
                  ),
                ),
              ),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    children: [
                      if (!useActionRail)
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) =>
                              SizeTransition(
                            sizeFactor: animation,
                            axisAlignment: 1,
                            child: FadeTransition(
                              opacity: animation,
                              child: child,
                            ),
                          ),
                          child: _suggestions.isNotEmpty && !_isLoading
                              ? _buildSuggestionsArea(colorScheme)
                              : const SizedBox.shrink(),
                        ),
                      _buildInputArea(colorScheme),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (useActionRail)
          SizedBox(
            width: 344,
            child: _buildActionRail(isDark, colorScheme),
          )
        else if (_shouldDetachActions)
          SizedBox(
            width: 48,
            child: _buildCollapsedActionRailHandle(colorScheme),
          ),
      ],
    );
  }

  List<ChatMessage> get _pendingActionMessages {
    return _messages
        .where(
          (msg) =>
              msg.todoActions != null &&
              msg.todoActions!.any(
                (action) => !action.isAdded && !action.isIgnored,
              ),
        )
        .toList()
        .reversed
        .toList();
  }

  Widget _buildActionRail(bool isDark, ColorScheme colorScheme) {
    final actionMessages = _pendingActionMessages;
    final actionCount = _pendingActionCount;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          left: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.68),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome_motion_rounded,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '建议操作',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: actionCount == 0
                      ? const SizedBox.shrink()
                      : Text(
                          '$actionCount',
                          key: ValueKey(actionCount),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.primary,
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  tooltip: '收起建议操作',
                  onPressed: () => setState(() => _actionRailCollapsed = true),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.62),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: actionMessages.isEmpty && _suggestions.isEmpty
                  ? _buildActionRailEmptyState(colorScheme)
                  : ListView(
                      key: ValueKey(
                        '${actionMessages.length}-${_suggestions.length}',
                      ),
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
                      children: [
                        if (actionMessages.isNotEmpty)
                          ...actionMessages.map(
                            (msg) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildMessageTodoActions(msg, isDark),
                            ),
                          ),
                        if (_suggestions.isNotEmpty && !_isLoading) ...[
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              4,
                              actionMessages.isNotEmpty ? 8 : 0,
                              4,
                              10,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.lightbulb_outline_rounded,
                                  size: 16,
                                  color: colorScheme.secondary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '下一步问题',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ..._suggestions.map(
                            (text) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _buildQuickQuestion(
                                text,
                                compact: true,
                                expand: true,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsedActionRailHandle(ColorScheme colorScheme) {
    final count = _pendingActionCount;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          left: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.68),
          ),
        ),
      ),
      child: Center(
        child: Tooltip(
          message: '展开建议操作',
          child: Material(
            color: colorScheme.primaryContainer.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _actionRailCollapsed = false),
              child: SizedBox(
                width: 36,
                height: 96,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.keyboard_double_arrow_left_rounded,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionRailEmptyState(ColorScheme colorScheme) {
    return Center(
      key: const ValueKey('empty-action-rail'),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.fact_check_outlined,
              size: 34,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.58),
            ),
            const SizedBox(height: 12),
            Text(
              '暂无待执行操作',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '模型生成可执行待办后会出现在这里。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLayout(bool isDark, ColorScheme colorScheme) {
    return Column(
      children: [
        Expanded(child: _buildMessageList(isDark, colorScheme)),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => SizeTransition(
            sizeFactor: animation,
            axisAlignment: 1,
            child: FadeTransition(
              opacity: animation,
              child: child,
            ),
          ),
          child: _suggestions.isNotEmpty && !_isLoading
              ? _buildSuggestionsArea(colorScheme)
              : const SizedBox.shrink(),
        ),
        _buildInputArea(colorScheme),
      ],
    );
  }

  Widget _buildMessageList(bool isDark, ColorScheme colorScheme) {
    if (_messages.isEmpty) {
      return _buildEmptyState(colorScheme);
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
      itemCount: _messages.length + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (_isLoading && index == _messages.length) {
          return _StaggeredFadeSlide(
            delay: Duration.zero,
            child: _buildStreamingBubble(isDark),
          );
        }
        final msg = _messages[index];
        return TweenAnimationBuilder<double>(
          key: ValueKey(msg.timestamp.millisecondsSinceEpoch + index),
          duration: const Duration(milliseconds: 500),
          tween: Tween(begin: 0.0, end: 1.0),
          curve: Curves.easeOutQuart,
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, 30 * (1 - value)),
              child: Opacity(
                opacity: value,
                child: child,
              ),
            );
          },
          child: _buildMessageBubble(msg, isDark),
        );
      },
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StaggeredFadeSlide(
                delay: const Duration(milliseconds: 40),
                child: _PulseAvatar(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color:
                          colorScheme.primaryContainer.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.smart_toy_rounded,
                      size: 36,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _StaggeredFadeSlide(
                delay: const Duration(milliseconds: 110),
                child: Text(
                  'AI待办助手',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _StaggeredFadeSlide(
                delay: const Duration(milliseconds: 170),
                child: Text(
                  '可以直接问课程、待办、专注记录，也可以让它帮你生成可执行的任务操作。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.55,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              _StaggeredFadeSlide(
                delay: const Duration(milliseconds: 200),
                child: OutlinedButton.icon(
                  onPressed: _openTutorialPage,
                  icon: const Icon(Icons.menu_book_rounded, size: 18),
                  label: const Text('查看使用教程'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(
                      color: colorScheme.primary.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              _StaggeredFadeSlide(
                child: SizedBox(
                  height: _isWide ? 180 : 140,
                  width: double.infinity,
                  child: _DanmakuSuggestions(
                    suggestions: _getSmartSuggestions(),
                    onTap: (text) {
                      _inputCtrl.text = text;
                      _sendMessage();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionsArea(ColorScheme colorScheme) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.6),
            width: 0.5,
          ),
        ),
      ),
      child: SizedBox(
        height: 50,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: _suggestions.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) => _buildQuickQuestion(
            _suggestions[index],
            compact: true,
          ),
        ),
      ),
    );
  }

  String _getCurrentSessionTitle() {
    final session = _sessions.firstWhere(
      (s) => s.id == _activeSessionId,
      orElse: () => ChatSession(title: 'AI待办助手'),
    );
    return session.title;
  }

  void _showHistorySidebar() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭',
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (ctx, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim1, anim2, child) {
        return Stack(
          children: [
            ModalBarrier(
              color: Colors.black.withValues(
                alpha: 0.3 * anim1.value,
              ),
              dismissible: true,
            ),
            SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(-1, 0),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
              ),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.75,
                  height: MediaQuery.of(context).size.height,
                  margin: const EdgeInsets.only(top: kToolbarHeight + 20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 16,
                        offset: const Offset(4, 0),
                      ),
                    ],
                  ),
                  child: _buildHistorySidebarContent(ctx, isWideMode: false),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHistorySidebarContent(BuildContext context,
      {required bool isWideMode}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, isWideMode ? 18 : 16, 12, 10),
          child: Row(
            children: [
              Text(
                '对话',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                  Icons.delete_sweep_outlined,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
                onPressed: () => _deleteAllSessions(context),
                tooltip: '清空所有历史对话',
              ),
              if (!isWideMode)
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
            ],
          ),
        ),
        Divider(
          height: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
        Expanded(
          child: _sessions.isEmpty
              ? Center(
                  child: Text(
                    '暂无历史对话',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  itemCount: _sessions.length,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  itemBuilder: (context, index) {
                    final session = _sessions[index];
                    final isActive = session.id == _activeSessionId;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Material(
                        color: isActive
                            ? colorScheme.primaryContainer
                                .withValues(alpha: 0.55)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        child: ListTile(
                          dense: isWideMode,
                          minLeadingWidth: 24,
                          horizontalTitleGap: 10,
                          contentPadding:
                              const EdgeInsets.only(left: 12, right: 4),
                          leading: Icon(
                            isActive
                                ? Icons.chat_bubble_rounded
                                : Icons.chat_bubble_outline_rounded,
                            size: 18,
                            color: isActive
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                          title: Text(
                            session.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight:
                                  isActive ? FontWeight.w700 : FontWeight.w500,
                              color: isActive
                                  ? colorScheme.onPrimaryContainer
                                  : colorScheme.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            DateFormat('MM/dd HH:mm').format(
                              session.updatedAt,
                            ),
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            color: colorScheme.onSurfaceVariant,
                            onPressed: () {
                              if (!isWideMode) Navigator.pop(context);
                              _deleteSession(session.id);
                            },
                            tooltip: '删除对话',
                          ),
                          selected: isActive,
                          selectedTileColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          onTap: () {
                            if (!isWideMode) Navigator.pop(context);
                            _switchSession(session.id);
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _deleteAllSessions(BuildContext sidebarCtx) async {
    final confirmed = await showDialog<bool>(
      context: sidebarCtx,
      builder: (ctx) => AlertDialog(
        title: const Text('彻底清空对话历史'),
        content: const Text('确定要删除所有的历史对话吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('全部删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ChatStorageService.clearAllSessions();
      if (!mounted || !sidebarCtx.mounted) return;
      setState(() {
        _sessions = [];
        _messages = [];
        _activeSessionId = '';
        _suggestions = _getSmartSuggestions();
      });
      // 关闭侧边栏
      Navigator.pop(sidebarCtx);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已清空所有历史对话')),
      );
    }
  }

  static const Map<String, String> providerLabels = {
    'zhipu': '智谱AI',
    'mimo': '小米MiMo',
    'deepseek': 'DeepSeek',
    'nvidia_nim': 'NVIDIA NIM',
    'custom': '自定义',
  };

  Widget _buildModelSelector() {
    final inheritedModel =
        _globalModelName.isNotEmpty ? _globalModelName : '未配置';
    final inheritedProvider = _globalProvider.isNotEmpty
        ? providerLabels[_globalProvider] ?? _globalProvider
        : '';
    final labelSuffix =
        inheritedProvider.isNotEmpty ? ' ($inheritedProvider)' : '';
    final labelPrefix = _chatModel.isNotEmpty ? '' : '继承: ';
    String label = _chatModel.isNotEmpty
        ? _chatModel
        : '$labelPrefix$inheritedModel$labelSuffix';

    return PopupMenuButton<String>(
      tooltip: '模型配置',
      icon: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 230),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.model_training_outlined,
              size: 18,
              color: _chatModel.isNotEmpty
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _chatModel.isNotEmpty
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: '__global__',
          child: Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 16,
                color: _chatModel.isEmpty
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '继承全局配置: $inheritedModel$labelSuffix',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        if (_chatModel.isNotEmpty)
          PopupMenuItem(
            value: '__current__',
            enabled: false,
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '当前: $_chatModel',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: '__settings__',
          child: Row(
            children: [
              Icon(Icons.settings_outlined, size: 16),
              SizedBox(width: 8),
              Text('打开LLM配置...'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: '__custom__',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 16),
              SizedBox(width: 8),
              Text('自定义模型...'),
            ],
          ),
        ),
      ],
      onSelected: (value) {
        if (value == '__custom__') {
          _showModelConfig();
        } else if (value == '__settings__') {
          _openLlmConfigPage();
        } else if (value == '__global__') {
          _useGlobalModel();
        }
      },
    );
  }

  Future<void> _useGlobalModel() async {
    await ChatStorageService.clearChatConfig();
    final globalConfig = await LLMService.getConfig();
    if (mounted) {
      setState(() {
        _chatModel = '';
        _chatApiKey = '';
        _chatApiUrl = '';
        _chatProvider = '';
        _globalModelName = globalConfig?.model ?? '';
        _globalProvider = globalConfig?.provider ?? '';
      });
    }
  }

  Future<void> _openLlmConfigPage() async {
    await Navigator.push(
      context,
      PageTransitions.material(builder: (_) => const LLMConfigPage()),
    );
    if (!mounted) return;
    await _loadChatConfig();
  }

  Future<void> _showModelConfig() async {
    final globalConfig = await LLMService.getConfig();
    if (!mounted) return;
    final modelCtrl = TextEditingController(
      text: _chatModel.isNotEmpty ? _chatModel : globalConfig?.model ?? '',
    );
    final apiKeyCtrl = TextEditingController(
      text: _chatApiKey.isNotEmpty ? _chatApiKey : globalConfig?.apiKey ?? '',
    );
    final apiUrlCtrl = TextEditingController(
      text: _chatApiUrl.isEmpty
          ? globalConfig?.apiUrl ??
              'https://open.bigmodel.cn/api/paas/v4/chat/completions'
          : _chatApiUrl,
    );
    String customProvider =
        _chatProvider.isNotEmpty ? _chatProvider : globalConfig?.provider ?? '';
    bool useCustom = _chatModel.isNotEmpty;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('聊天模型配置'),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.85,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('使用独立模型配置'),
                    subtitle: Text(
                      globalConfig?.isConfigured == true
                          ? '关闭后继承全局模型: ${globalConfig!.model}'
                          : '关闭后继承全局配置；当前全局未配置',
                    ),
                    value: useCustom,
                    onChanged: (val) {
                      setDialogState(() => useCustom = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: modelCtrl,
                    enabled: useCustom,
                    decoration: InputDecoration(
                      labelText: '模型名称',
                      hintText: '例如: glm-4.7-flash',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: apiKeyCtrl,
                    enabled: useCustom,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      hintText: '输入你的API密钥',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: apiUrlCtrl,
                    enabled: useCustom,
                    decoration: InputDecoration(
                      labelText: 'API地址 (可选)',
                      hintText:
                          'https://open.bigmodel.cn/api/paas/v4/chat/completions',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: providerLabels.containsKey(customProvider)
                        ? customProvider
                        : null,
                    decoration: InputDecoration(
                      labelText: '提供商 (可选)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: providerLabels.entries
                        .map((e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ))
                        .toList(),
                    onChanged: useCustom
                        ? (val) {
                            setDialogState(() => customProvider = val ?? '');
                          }
                        : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            if (useCustom)
              TextButton(
                onPressed: () async {
                  await ChatStorageService.clearChatConfig();
                  final globalConfig = await LLMService.getConfig();
                  if (mounted) {
                    setState(() {
                      _chatModel = '';
                      _chatApiKey = '';
                      _chatApiUrl = '';
                      _chatProvider = '';
                      _globalModelName = globalConfig?.model ?? '';
                      _globalProvider = globalConfig?.provider ?? '';
                    });
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('清除'),
              ),
            FilledButton(
              onPressed: useCustom
                  ? () async {
                      if (modelCtrl.text.trim().isEmpty) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请输入模型名称')),
                        );
                        return;
                      }
                      if (apiKeyCtrl.text.trim().isEmpty) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请输入API密钥')),
                        );
                        return;
                      }
                      await ChatStorageService.saveChatConfig(
                        model: modelCtrl.text.trim(),
                        apiKey: apiKeyCtrl.text.trim(),
                        apiUrl: apiUrlCtrl.text.trim().isEmpty
                            ? null
                            : apiUrlCtrl.text.trim(),
                        provider: useCustom && customProvider.isNotEmpty
                            ? customProvider
                            : null,
                      );
                      if (mounted) {
                        setState(() {
                          _chatModel = modelCtrl.text.trim();
                          _chatApiKey = apiKeyCtrl.text.trim();
                          _chatApiUrl = apiUrlCtrl.text.trim();
                          _chatProvider = useCustom && customProvider.isNotEmpty
                              ? customProvider
                              : '';
                          _globalModelName = globalConfig?.model ?? '';
                          _globalProvider = globalConfig?.provider ?? '';
                        });
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                    }
                  : null,
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _getSmartSuggestions() {
    final List<String> suggestions = [];

    // 1. 基础引导 (恒定)
    suggestions.addAll([
      '帮我规划今天的待办',
      '怎么使用深度规划？',
      '分析一下我最近的效率',
      '有哪些紧急任务需要处理？',
    ]);

    // 2. 基于课程数据
    if (widget.courses.isNotEmpty) {
      suggestions.add('明天的课程表是什么？');
      suggestions.add('这周我还有多少节课？');
      suggestions.add('帮我把课程同步到待办');
    }

    // 3. 基于待办状态
    if (widget.todos.isNotEmpty) {
      final highPriority =
          widget.todos.where((t) => (t['priority'] ?? 0) >= 2).length;
      if (highPriority > 0) suggestions.add('列出所有高优先级任务');

      final overdue = widget.todos.where((t) {
        final dueDate = t['dueDate'] as String?;
        if (dueDate == null || dueDate.isEmpty) return false;
        final date = DateTime.tryParse(dueDate);
        return date != null && date.isBefore(DateTime.now());
      }).length;
      if (overdue > 0) suggestions.add('有哪些任务已经逾期了？');

      suggestions.add('帮我给这些待办分个类');
      suggestions.add('预测一下我完成所有任务需要多久');
    }

    // 4. 基于专注记录
    if (widget.pomodoroRecords.isNotEmpty) {
      suggestions.add('我这周专注时长达标了吗？');
      suggestions.add('分析我的专注分布情况');
    }

    // 5. 基于倒计时/目标
    if (widget.countdowns.isNotEmpty) {
      suggestions.add('最近的考试/目标还有多久？');
    }

    // 6. 基于规划冲突
    if (widget.conflicts.isNotEmpty) {
      suggestions.add('帮我解决目前的规划冲突');
    }

    // 7. 通用高级技巧
    suggestions.addAll([
      '帮我整理番茄标签',
      '如何提高我的专注力？',
      '整理一下我的时间日志',
      '帮我制定一个复习计划',
      '有哪些建议能让我更自律？',
      '备份我的所有数据',
    ]);

    return suggestions.toSet().toList();
  }

  String _formatTodoTimeRange(
    String? startTime,
    String? dueDate,
    bool isAllDay,
  ) {
    DateTime? start;
    DateTime? end;

    if (startTime != null && startTime.isNotEmpty) {
      start = DateTime.tryParse(startTime);
    }
    if (dueDate != null && dueDate.isNotEmpty) {
      end = DateTime.tryParse(dueDate);
    }

    if (start == null && end == null) return '未设置时间';

    String formatDateTime(DateTime dt, bool showDate, bool showTime) {
      if (showDate && showTime) {
        return DateFormat('MM/dd HH:mm').format(dt);
      } else if (showDate) {
        return DateFormat('MM/dd').format(dt);
      } else {
        return DateFormat('HH:mm').format(dt);
      }
    }

    bool sameDay(DateTime a, DateTime b) {
      return a.year == b.year && a.month == b.month && a.day == b.day;
    }

    if (isAllDay) {
      if (start != null && end != null && sameDay(start, end)) {
        return '全天 ${DateFormat('MM/dd').format(start)}';
      } else if (start != null && end != null) {
        return '全天 ${DateFormat('MM/dd').format(start)} ~ ${DateFormat('MM/dd').format(end)}';
      } else if (start != null) {
        return '全天 ${DateFormat('MM/dd').format(start)}';
      } else if (end != null) {
        return '全天 ${DateFormat('MM/dd').format(end)}';
      }
    }

    if (start != null && end != null) {
      if (sameDay(start, end)) {
        return '${DateFormat('MM/dd').format(start)} ${DateFormat('HH:mm').format(start)} ~ ${DateFormat('HH:mm').format(end)}';
      } else {
        return '${DateFormat('MM/dd HH:mm').format(start)} ~ ${DateFormat('MM/dd HH:mm').format(end)}';
      }
    } else if (start != null) {
      final showTime = start.hour != 0 || start.minute != 0;
      return '开始: ${formatDateTime(start, true, showTime)}';
    } else if (end != null) {
      final showTime = end.hour != 0 || end.minute != 0;
      return '截止: ${formatDateTime(end, true, showTime)}';
    }

    return '未设置时间';
  }

  String _getTodoCurrentFolderName(String? todoId) {
    if (todoId == null) return '未知';
    final matches = widget.todos.where((t) => t['id'] == todoId);
    if (matches.isEmpty) return '默认分类';
    final existing = matches.first;
    final gid = existing['groupId'] as String?;
    if (gid == null || gid.isEmpty) return '默认分类';
    return widget.todoGroups
        .firstWhere((g) => g.id == gid, orElse: () => TodoGroup(name: '未知'))
        .name;
  }

  String _getRecurrenceText(String recurrence) {
    switch (recurrence.toLowerCase()) {
      case 'daily':
        return '每天';
      case 'weekly':
        return '每周';
      case 'monthly':
        return '每月';
      case 'weekdays':
        return '工作日';
      default:
        return recurrence;
    }
  }

  Widget _buildMessageTodoActions(ChatMessage msg, bool isDark) {
    final activeActions = msg.todoActions!
        .where((action) => !action.isAdded && !action.isIgnored)
        .toList();
    if (activeActions.isEmpty) return const SizedBox.shrink();
    final hasExistingMutations =
        activeActions.any((t) => t.mutatesExistingTodo);
    final hasPomodoroActions = activeActions.any((t) => t.isPomodoroAction);
    final hasTimeLogActions = activeActions.any((t) => t.isTimeLogAction);
    final hasCountdownActions = activeActions.any((t) => t.isCountdownAction);
    final hasTagActions = activeActions.any((t) => t.isPomodoroTagAction);

    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _IridescentActionPanel(
        isDark: isDark,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDark
                ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.24)
                : colorScheme.primaryContainer.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.add_task_outlined,
                      color: Theme.of(context).colorScheme.primary,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      hasPomodoroActions
                          ? '建议操作番茄钟'
                          : hasTimeLogActions
                              ? '建议整理专注记录'
                              : hasCountdownActions
                                  ? '建议整理倒计时'
                                  : hasTagActions
                                      ? '建议整理番茄标签'
                                      : hasExistingMutations
                                          ? '建议整理待办'
                                          : '建议添加待办',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              ...activeActions.asMap().entries.map((entry) {
                final todo = entry.value;

                final isSelected = todo.isSelected;
                final currentGroupId = todo.groupId;
                final startTime = todo.startTime;
                final dueDate = todo.dueDate;
                final isAllDay = todo.isAllDay;
                final recurrence = todo.recurrence;
                final timeStr =
                    _formatTodoTimeRange(startTime, dueDate, isAllDay);

                return Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.white.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: isSelected,
                              onChanged: (val) {
                                setState(() {
                                  todo.isSelected = val == true;
                                });
                                _saveHistorySilently();
                              },
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    _buildActionBadge(todo),
                                    Expanded(
                                      child: Text(
                                        todo.title ?? '未命名待办',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                if (todo.mutatesExistingTodo)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      _getMutationHint(todo),
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey
                                              .withValues(alpha: 0.8),
                                          fontStyle: FontStyle.italic),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            tooltip: '编辑执行内容',
                            onPressed: () => _editAction(todo),
                            visualDensity: VisualDensity.compact,
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            tooltip: '忽略此操作',
                            onPressed: () => _ignoreAction(todo),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      // 时间和循环信息
                      Padding(
                        padding: const EdgeInsets.only(left: 28, top: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 13,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.5),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              timeStr,
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                            if (recurrence != 'none') ...[
                              const SizedBox(width: 12),
                              Icon(
                                Icons.repeat,
                                size: 13,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _getRecurrenceText(recurrence),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (todo.remark != null && todo.remark!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 28, top: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.notes,
                                size: 13,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.4),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  todo.remark!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      _buildClassificationMetadata(todo),
                      _buildChangeSummary(todo),
                      if (_isDangerousAction(todo))
                        Padding(
                          padding: const EdgeInsets.only(left: 28, top: 6),
                          child: Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 13,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  _getDangerHint(todo),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context).colorScheme.error,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (todo.isTodoAction)
                        Padding(
                          padding: const EdgeInsets.only(left: 28, top: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.folder_outlined,
                                  size: 13,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String?>(
                                      value: widget.todoGroups.any(
                                        (g) => g.id == currentGroupId,
                                      )
                                          ? currentGroupId
                                          : null,
                                      isDense: true,
                                      icon: const Icon(Icons.arrow_drop_down,
                                          size: 16),
                                      hint: const Text('选择分类',
                                          style: TextStyle(fontSize: 11)),
                                      items: [
                                        const DropdownMenuItem<String?>(
                                          value: null,
                                          child: Text('默认分类',
                                              style: TextStyle(fontSize: 11)),
                                        ),
                                        ...widget.todoGroups.map(
                                          (g) => DropdownMenuItem<String?>(
                                            value: g.id,
                                            child: Text(
                                              g.name,
                                              style:
                                                  const TextStyle(fontSize: 11),
                                            ),
                                          ),
                                        ),
                                      ],
                                      onChanged: (val) {
                                        setState(() {
                                          todo.groupId = val;
                                        });
                                        _saveHistorySilently();
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: msg.todoActions!.any(
                      (t) => t.isSelected && !t.isAdded && !t.isIgnored,
                    )
                        ? () => _addTodosForMessage(msg)
                        : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add_task, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          '执行所选操作 (${activeActions.where((t) => t.isSelected).length})',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClassificationMetadata(AiTodoAction action) {
    final priority = action.metadata['priorityLabel']?.toString();
    final rawTags = action.metadata['tags'];
    final tags = rawTags is List
        ? rawTags.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : const <String>[];
    if ((priority == null || priority.isEmpty) && tags.isEmpty) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 28, top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          if (priority != null && priority.isNotEmpty)
            _buildMiniMetaChip(Icons.flag_rounded, priority, Colors.orange),
          ...tags.map(
            (tag) => _buildMiniMetaChip(
                Icons.sell_outlined, tag, colorScheme.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMetaChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBadge(AiTodoAction action) {
    Color color;
    String label;
    switch (action.type) {
      case AiTodoActionType.createTodo:
        color = Colors.green;
        label = '新增';
        break;
      case AiTodoActionType.completeTodo:
        color = Theme.of(context).colorScheme.primary;
        label = '完成';
        break;
      case AiTodoActionType.deleteTodo:
        color = Colors.red;
        label = '删除';
        break;
      case AiTodoActionType.rescheduleTodo:
        color = Colors.purple;
        label = '改期';
        break;
      case AiTodoActionType.bulkRescheduleTodo:
        color = Colors.purple;
        label = '批改';
        break;
      case AiTodoActionType.updateTodo:
        color = Colors.orange;
        label = '修改';
        break;
      case AiTodoActionType.categorizeTodo:
        color = Colors.orange;
        label = '整理';
        break;
      case AiTodoActionType.planTodos:
        color = Colors.teal;
        label = '规划';
        break;
      case AiTodoActionType.createPlanBlock:
        color = Colors.teal;
        label = '时间块';
        break;
      case AiTodoActionType.updatePlanBlock:
      case AiTodoActionType.reschedulePlanBlocks:
        color = Colors.teal;
        label = '改规划';
        break;
      case AiTodoActionType.deletePlanBlock:
        color = Colors.red;
        label = '删规划';
        break;
      case AiTodoActionType.skipPlanBlock:
        color = Colors.orange;
        label = '跳过';
        break;
      case AiTodoActionType.startPlanBlockPomodoro:
        color = Colors.redAccent;
        label = '开始规划';
        break;
      case AiTodoActionType.splitTodo:
        color = Colors.indigo;
        label = '拆分';
        break;
      case AiTodoActionType.mergeTodos:
        color = Colors.indigo;
        label = '合并';
        break;
      case AiTodoActionType.createTimeLog:
        color = Colors.cyan;
        label = '记录';
        break;
      case AiTodoActionType.updateTimeLog:
        color = Colors.orange;
        label = '改记录';
        break;
      case AiTodoActionType.deleteTimeLog:
        color = Colors.red;
        label = '删记录';
        break;
      case AiTodoActionType.startPomodoro:
        color = Colors.redAccent;
        label = '开始';
        break;
      case AiTodoActionType.stopPomodoro:
        color = Colors.grey;
        label = '停止';
        break;
      case AiTodoActionType.createCountdown:
        color = Colors.deepOrange;
        label = '倒计时';
        break;
      case AiTodoActionType.updateCountdown:
        color = Colors.orange;
        label = '改倒计时';
        break;
      case AiTodoActionType.completeCountdown:
        color = Colors.green;
        label = '达成';
        break;
      case AiTodoActionType.deleteCountdown:
        color = Colors.red;
        label = '删倒计时';
        break;
      case AiTodoActionType.createTodoGroup:
        color = Colors.green;
        label = '分类';
        break;
      case AiTodoActionType.updateTodoGroup:
        color = Colors.orange;
        label = '改分类';
        break;
      case AiTodoActionType.deleteTodoGroup:
        color = Colors.red;
        label = '删分类';
        break;
      case AiTodoActionType.createPomodoroTag:
        color = Colors.cyan;
        label = '标签';
        break;
      case AiTodoActionType.updatePomodoroTag:
        color = Colors.orange;
        label = '改标签';
        break;
      case AiTodoActionType.deletePomodoroTag:
        color = Colors.red;
        label = '删标签';
        break;
      case AiTodoActionType.unknown:
        color = Colors.grey;
        label = '操作';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      margin: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _ignoreAction(AiTodoAction action) {
    setState(() {
      action.isIgnored = true;
      action.isSelected = false;
    });
    _recordIgnoreFeedback(action);
    _saveHistorySilently();
  }

  void _recordIgnoreFeedback(AiTodoAction action) {
    if (action.type != AiTodoActionType.categorizeTodo) return;
    final title = action.title ?? '';
    if (title.isEmpty) return;
    final kws = _extractActionKeywords(title);
    if (kws.isEmpty) return;
    if (action.groupId != null) {
      SuggestionFeedbackService.record(
        keywords: kws,
        suggestionType: 'group',
        suggestedValue: action.groupId!,
        accepted: false,
      );
    }
    final priority = action.metadata['priority'];
    if (priority != null) {
      SuggestionFeedbackService.record(
        keywords: kws,
        suggestionType: 'priority',
        suggestedValue: '$priority',
        accepted: false,
      );
    }
    final tags = action.metadata['tags'];
    if (tags is List) {
      for (final tag in tags) {
        SuggestionFeedbackService.record(
          keywords: kws,
          suggestionType: 'tag',
          suggestedValue: tag.toString(),
          accepted: false,
        );
      }
    }
  }

  List<String> _extractActionKeywords(String text) {
    final lower = text.toLowerCase();
    final tokens = <String>[];
    for (final m in RegExp(r'[a-z0-9]+').allMatches(lower)) {
      if (m.group(0)!.length >= 2) tokens.add(m.group(0)!);
    }
    for (final m in RegExp(r'[一-鿿]+').allMatches(lower)) {
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

  Future<void> _editAction(AiTodoAction action) async {
    final titleCtrl = TextEditingController(text: action.title ?? '');
    final remarkCtrl = TextEditingController(text: action.remark ?? '');
    final startCtrl = TextEditingController(text: action.startTime ?? '');
    final dueCtrl = TextEditingController(text: action.dueDate ?? '');
    final idCtrl = TextEditingController(text: action.todoId ?? '');
    final durationCtrl =
        TextEditingController(text: action.durationMinutes?.toString() ?? '');
    final reminderCtrl =
        TextEditingController(text: action.reminderMinutes?.toString() ?? '');
    final colorCtrl = TextEditingController(text: action.color ?? '');
    final statusCtrl = TextEditingController(text: action.status ?? '');
    final tagCtrl = TextEditingController(text: action.tagUuids.join(','));
    var recurrence = action.recurrence;
    var isAllDay = action.isAllDay;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              _buildActionBadge(action),
              const SizedBox(width: 8),
              const Text('编辑执行内容'),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.86,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (action.mutatesExistingTodo ||
                      action.isTimeLogAction ||
                      action.isCountdownAction ||
                      action.isTodoGroupAction ||
                      action.isPomodoroTagAction)
                    _editField(idCtrl, _idFieldLabel(action)),
                  if (_usesTitle(action))
                    _editField(titleCtrl, _titleLabel(action)),
                  if (_usesRemark(action)) _editField(remarkCtrl, '备注'),
                  if (_usesStartTime(action))
                    _editField(startCtrl, _startTimeLabel(action),
                        hint: 'YYYY-MM-DD HH:mm'),
                  if (_usesDueTime(action))
                    _editField(dueCtrl, _dueTimeLabel(action),
                        hint: 'YYYY-MM-DD HH:mm'),
                  if (_usesDuration(action))
                    _editField(durationCtrl, '时长（分钟）',
                        keyboardType: TextInputType.number),
                  if (_usesReminder(action))
                    _editField(reminderCtrl, '提前提醒（分钟）',
                        keyboardType: TextInputType.number),
                  if (_usesColor(action))
                    _editField(colorCtrl, '颜色', hint: '#3B82F6'),
                  if (_usesStatus(action))
                    _editField(statusCtrl, '状态',
                        hint: 'completed 或 interrupted'),
                  if (_usesTags(action)) _editField(tagCtrl, '番茄标签ID（逗号分隔）'),
                  if (action.isTodoAction) ...[
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('全天'),
                      value: isAllDay,
                      onChanged: (value) =>
                          setDialogState(() => isAllDay = value),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: recurrence,
                      decoration: const InputDecoration(labelText: '循环'),
                      items: const [
                        DropdownMenuItem(value: 'none', child: Text('不循环')),
                        DropdownMenuItem(value: 'daily', child: Text('每天')),
                        DropdownMenuItem(value: 'weekly', child: Text('每周')),
                        DropdownMenuItem(value: 'monthly', child: Text('每月')),
                        DropdownMenuItem(value: 'yearly', child: Text('每年')),
                        DropdownMenuItem(value: 'weekdays', child: Text('工作日')),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => recurrence = value ?? 'none'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  action.todoId = _nullIfBlank(idCtrl.text);
                  action.title = _nullIfBlank(titleCtrl.text);
                  action.remark = _nullIfBlank(remarkCtrl.text);
                  action.startTime = _nullIfBlank(startCtrl.text);
                  action.dueDate = _nullIfBlank(dueCtrl.text);
                  action.durationMinutes = int.tryParse(durationCtrl.text);
                  action.reminderMinutes = int.tryParse(reminderCtrl.text);
                  action.color = _nullIfBlank(colorCtrl.text);
                  action.status = _nullIfBlank(statusCtrl.text);
                  action.tagUuids = tagCtrl.text
                      .split(',')
                      .map((e) => e.trim())
                      .where((e) => e.isNotEmpty)
                      .toList();
                  action.recurrence = recurrence;
                  action.isAllDay = isAllDay;
                });
                _saveHistorySilently();
                Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _editField(
    TextEditingController controller,
    String label, {
    String? hint,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  String? _nullIfBlank(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  bool _usesTitle(AiTodoAction action) =>
      action.type != AiTodoActionType.completeTodo &&
      action.type != AiTodoActionType.deleteTodo &&
      action.type != AiTodoActionType.deleteTimeLog &&
      action.type != AiTodoActionType.stopPomodoro &&
      action.type != AiTodoActionType.completeCountdown &&
      action.type != AiTodoActionType.deleteCountdown &&
      action.type != AiTodoActionType.deleteTodoGroup &&
      action.type != AiTodoActionType.deletePomodoroTag;

  bool _usesRemark(AiTodoAction action) =>
      action.isTodoAction || action.isTimeLogAction || action.isPlanBlockAction;

  bool _usesStartTime(AiTodoAction action) =>
      action.isTodoAction || action.isTimeLogAction || action.isPlanBlockAction;

  bool _usesDueTime(AiTodoAction action) =>
      action.isTodoAction ||
      action.isTimeLogAction ||
      action.isCountdownAction ||
      action.isPlanBlockAction;

  bool _usesDuration(AiTodoAction action) =>
      action.isTimeLogAction ||
      action.isPlanBlockAction ||
      action.type == AiTodoActionType.startPomodoro;

  bool _usesReminder(AiTodoAction action) =>
      action.isTodoAction || action.isPlanBlockAction;

  bool _usesColor(AiTodoAction action) => action.isPomodoroTagAction;

  bool _usesStatus(AiTodoAction action) =>
      action.type == AiTodoActionType.stopPomodoro;

  bool _usesTags(AiTodoAction action) =>
      action.isTimeLogAction || action.isPomodoroAction;

  String _idFieldLabel(AiTodoAction action) {
    if (action.isTimeLogAction) return '专注记录ID';
    if (action.isCountdownAction) return '倒计时ID';
    if (action.isTodoGroupAction) return '分类ID';
    if (action.isPomodoroTagAction) return '标签ID';
    return '待办ID';
  }

  String _titleLabel(AiTodoAction action) {
    if (action.isTodoGroupAction) return '分类名称';
    if (action.isPomodoroTagAction) return '标签名称';
    if (action.isCountdownAction) return '倒计时标题';
    if (action.isTimeLogAction) return '专注记录标题';
    return '标题';
  }

  String _startTimeLabel(AiTodoAction action) {
    if (action.isTimeLogAction) return '开始时间';
    return '开始时间';
  }

  String _dueTimeLabel(AiTodoAction action) {
    if (action.isCountdownAction) return '目标时间';
    if (action.isTimeLogAction) return '结束时间';
    return '截止时间';
  }

  String _getMutationHint(AiTodoAction action) {
    switch (action.type) {
      case AiTodoActionType.completeTodo:
        return '标记为已完成';
      case AiTodoActionType.deleteTodo:
        return '移动到已删除';
      case AiTodoActionType.rescheduleTodo:
        return '调整时间安排';
      case AiTodoActionType.bulkRescheduleTodo:
        return '批量调整时间安排';
      case AiTodoActionType.updateTodo:
        return '更新待办内容';
      case AiTodoActionType.categorizeTodo:
        return '从 [${_getTodoCurrentFolderName(action.todoId)}] 移动';
      case AiTodoActionType.planTodos:
        return '生成计划待办';
      case AiTodoActionType.createPlanBlock:
        return '安排到具体时间块';
      case AiTodoActionType.updatePlanBlock:
        return '修改规划块';
      case AiTodoActionType.deletePlanBlock:
        return '删除规划块';
      case AiTodoActionType.reschedulePlanBlocks:
        return '重排规划块';
      case AiTodoActionType.skipPlanBlock:
        return '跳过规划块';
      case AiTodoActionType.startPlanBlockPomodoro:
        return '开始规划番茄钟';
      case AiTodoActionType.splitTodo:
        return action.sourceTodoIds.isEmpty
            ? '拆分为子任务'
            : '从 [${action.sourceTodoIds.join(', ')}] 拆分';
      case AiTodoActionType.mergeTodos:
        return action.sourceTodoIds.isEmpty
            ? '合并为新待办'
            : '合并 [${action.sourceTodoIds.join(', ')}]';
      case AiTodoActionType.createTimeLog:
        return '新增专注记录';
      case AiTodoActionType.updateTimeLog:
        return '修改专注记录';
      case AiTodoActionType.deleteTimeLog:
        return '删除专注记录';
      case AiTodoActionType.startPomodoro:
        return '开始番茄钟';
      case AiTodoActionType.stopPomodoro:
        return '停止当前番茄钟';
      case AiTodoActionType.createCountdown:
        return '新增倒计时';
      case AiTodoActionType.updateCountdown:
        return '修改倒计时';
      case AiTodoActionType.completeCountdown:
        return '标记倒计时达成';
      case AiTodoActionType.deleteCountdown:
        return '删除倒计时';
      case AiTodoActionType.createTodoGroup:
        return '新增待办分类';
      case AiTodoActionType.updateTodoGroup:
        return '修改待办分类';
      case AiTodoActionType.deleteTodoGroup:
        return '删除待办分类';
      case AiTodoActionType.createPomodoroTag:
        return '新增番茄标签';
      case AiTodoActionType.updatePomodoroTag:
        return '修改番茄标签';
      case AiTodoActionType.deletePomodoroTag:
        return '删除番茄标签';
      case AiTodoActionType.createTodo:
      case AiTodoActionType.unknown:
        return '';
    }
  }

  Widget _buildChangeSummary(AiTodoAction action) {
    if (!action.mutatesExistingTodo || !action.isTodoAction) {
      return const SizedBox.shrink();
    }
    final existing = _findExistingTodo(action.todoId);
    if (existing == null) return const SizedBox.shrink();

    final rows = <String>[];
    void addRow(String label, String before, String after) {
      if (before == after || after.isEmpty) return;
      rows.add('$label: $before -> $after');
    }

    addRow('标题', '${existing['title'] ?? ''}', action.title ?? '');
    addRow('备注', '${existing['remark'] ?? ''}', action.remark ?? '');
    if (action.startTime != null || action.dueDate != null) {
      final beforeTime = _formatTodoTimeRange(
        existing['startTime']?.toString(),
        existing['endTime']?.toString(),
        existing['isAllDay'] == true,
      );
      final afterTime = _formatTodoTimeRange(
        action.startTime ?? existing['startTime']?.toString(),
        action.dueDate ?? existing['endTime']?.toString(),
        action.isAllDay || existing['isAllDay'] == true,
      );
      addRow('时间', beforeTime, afterTime);
    }
    if (action.groupId != null ||
        action.type == AiTodoActionType.categorizeTodo) {
      addRow(
        '分类',
        _getGroupName(existing['groupId']?.toString()),
        _getGroupName(action.groupId),
      );
    }
    if (action.reminderMinutes != null) {
      addRow(
        '提醒',
        '提前${existing['reminderMinutes'] ?? 5}分钟',
        '提前${action.reminderMinutes}分钟',
      );
    }
    if (action.type == AiTodoActionType.completeTodo) {
      addRow('状态', existing['isDone'] == true ? '已完成' : '未完成', '已完成');
    }
    if (action.type == AiTodoActionType.deleteTodo) {
      addRow('删除', existing['isDeleted'] == true ? '已删除' : '未删除', '已删除');
    }

    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 28, top: 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows
              .map(
                (row) => Text(
                  row,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.65),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Map<String, dynamic>? _findExistingTodo(String? todoId) {
    if (todoId == null) return null;
    for (final todo in widget.todos) {
      if (todo['id'] == todoId) return todo;
    }
    return null;
  }

  String _getGroupName(String? groupId) {
    if (groupId == null || groupId.isEmpty) return '默认分类';
    return widget.todoGroups
        .firstWhere((g) => g.id == groupId, orElse: () => TodoGroup(name: '未知'))
        .name;
  }

  bool _isDangerousAction(AiTodoAction action) {
    return action.type == AiTodoActionType.deleteTodo ||
        action.type == AiTodoActionType.deleteTimeLog ||
        action.type == AiTodoActionType.stopPomodoro ||
        action.type == AiTodoActionType.deleteCountdown ||
        action.type == AiTodoActionType.completeCountdown ||
        action.type == AiTodoActionType.deleteTodoGroup ||
        action.type == AiTodoActionType.deletePomodoroTag ||
        action.type == AiTodoActionType.deletePlanBlock ||
        action.type == AiTodoActionType.skipPlanBlock ||
        (action.type == AiTodoActionType.splitTodo &&
            action.deleteSourceTodos) ||
        (action.type == AiTodoActionType.mergeTodos &&
            action.deleteSourceTodos);
  }

  String _getDangerHint(AiTodoAction action) {
    switch (action.type) {
      case AiTodoActionType.deleteTodo:
        return '将删除已有待办，执行前请确认';
      case AiTodoActionType.splitTodo:
        return '拆分后会删除原待办，执行前请确认';
      case AiTodoActionType.mergeTodos:
        return '合并后会删除源待办，执行前请确认';
      case AiTodoActionType.deleteTimeLog:
        return '将删除已有专注记录，执行前请确认';
      case AiTodoActionType.stopPomodoro:
        return '将停止当前番茄钟，执行前请确认';
      case AiTodoActionType.deleteCountdown:
        return '将删除已有倒计时，执行前请确认';
      case AiTodoActionType.completeCountdown:
        return '将标记倒计时达成，执行前请确认';
      case AiTodoActionType.deleteTodoGroup:
        return '将删除待办分类，执行前请确认';
      case AiTodoActionType.deletePomodoroTag:
        return '将删除番茄标签，执行前请确认';
      case AiTodoActionType.deletePlanBlock:
        return '将删除规划块，执行前请确认';
      case AiTodoActionType.skipPlanBlock:
        return '将跳过规划块，执行前请确认';
      case AiTodoActionType.createTodo:
      case AiTodoActionType.updateTodo:
      case AiTodoActionType.completeTodo:
      case AiTodoActionType.rescheduleTodo:
      case AiTodoActionType.bulkRescheduleTodo:
      case AiTodoActionType.categorizeTodo:
      case AiTodoActionType.planTodos:
      case AiTodoActionType.createPlanBlock:
      case AiTodoActionType.updatePlanBlock:
      case AiTodoActionType.reschedulePlanBlocks:
      case AiTodoActionType.startPlanBlockPomodoro:
      case AiTodoActionType.unknown:
      case AiTodoActionType.createTimeLog:
      case AiTodoActionType.updateTimeLog:
      case AiTodoActionType.startPomodoro:
      case AiTodoActionType.createCountdown:
      case AiTodoActionType.updateCountdown:
      case AiTodoActionType.createTodoGroup:
      case AiTodoActionType.updateTodoGroup:
      case AiTodoActionType.createPomodoroTag:
      case AiTodoActionType.updatePomodoroTag:
        return '';
    }
  }

  Future<void> _saveHistorySilently() async {
    await ChatStorageService.saveHistory(_messages, _activeSessionId);
  }

  Future<void> _addTodosForMessage(ChatMessage msg) async {
    if (msg.todoActions == null) return;

    final existingCountdowns = widget.countdowns.isNotEmpty
        ? widget.countdowns
        : await StorageService.getCountdowns(widget.username);
    final existingTags = widget.pomodoroTags.isNotEmpty
        ? widget.pomodoroTags
        : await PomodoroService.getTags();

    final result = AiTodoActionExecutor.execute(
      actions: msg.todoActions!,
      existingTodos: widget.todos,
      existingTimeLogs: widget.timeLogs,
      existingCountdowns: existingCountdowns,
      existingTodoGroups: widget.todoGroups,
      existingPomodoroTags: existingTags,
      existingPlanBlocks: _planBlocks,
      categoryReminderDefaults: _categoryReminderDefaults,
    );

    if (result.hasChanges) {
      if (widget.onTodosBatchAction != null) {
        widget.onTodosBatchAction!(result.newTodos, result.updatedTodos);
      } else {
        // Fallback to separate calls
        if (result.newTodos.isNotEmpty) {
          if (widget.onTodosBatchInserted != null) {
            widget.onTodosBatchInserted!(result.newTodos);
          } else if (widget.onTodoInserted != null) {
            for (final t in result.newTodos) {
              widget.onTodoInserted!(t);
            }
          }
        }
        if (result.updatedTodos.isNotEmpty && widget.onTodosUpdated != null) {
          widget.onTodosUpdated!(result.updatedTodos);
        }
      }

      if (result.newTimeLogs.isNotEmpty || result.updatedTimeLogs.isNotEmpty) {
        final allLogs = await StorageService.getTimeLogs(widget.username);
        final merged = AiTodoActionExecutor.mergeTimeLogUpdates(
          allLogs,
          result.newTimeLogs,
          result.updatedTimeLogs,
        );
        await StorageService.saveTimeLogs(widget.username, merged, sync: true);
      }

      if (result.newCountdowns.isNotEmpty ||
          result.updatedCountdowns.isNotEmpty) {
        final allCountdowns =
            await StorageService.getCountdowns(widget.username);
        final merged = AiTodoActionExecutor.mergeCountdownUpdates(
          allCountdowns,
          result.newCountdowns,
          result.updatedCountdowns,
        );
        await StorageService.saveCountdowns(widget.username, merged,
            sync: true);
      }

      if (result.newTodoGroups.isNotEmpty ||
          result.updatedTodoGroups.isNotEmpty) {
        final allGroups = await StorageService.getTodoGroups(
          widget.username,
          includeDeleted: true,
        );
        final merged = AiTodoActionExecutor.mergeTodoGroupUpdates(
          allGroups,
          result.newTodoGroups,
          result.updatedTodoGroups,
        );
        await StorageService.saveTodoGroups(widget.username, merged,
            sync: true);
        widget.onTodoGroupsChanged?.call(merged);
      }

      if (result.newPomodoroTags.isNotEmpty ||
          result.updatedPomodoroTags.isNotEmpty) {
        final allTags = await PomodoroService.getTags();
        final merged = AiTodoActionExecutor.mergePomodoroTagUpdates(
          allTags,
          result.newPomodoroTags,
          result.updatedPomodoroTags,
        );
        await PomodoroService.saveTags(merged);
      }

      if (result.newPlanBlocks.isNotEmpty ||
          result.updatedPlanBlocks.isNotEmpty) {
        await StorageService.savePlanBlocks(
          widget.username,
          [...result.newPlanBlocks, ...result.updatedPlanBlocks],
          sync: true,
        );
        _planBlocks = [
          ..._planBlocks.where((existing) => !result.updatedPlanBlocks
              .any((updated) => updated.uuid == existing.uuid)),
          ...result.newPlanBlocks,
          ...result.updatedPlanBlocks,
        ];
      }

      for (final action in result.pomodoroActions) {
        await _executePomodoroAction(action);
      }

      if (!mounted) return;
      setState(() {});
      _saveHistorySilently();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '已执行所选操作 (新待办: ${result.newTodos.length}, 整理待办: ${result.updatedTodos.length}, 规划: ${result.newPlanBlocks.length + result.updatedPlanBlocks.length}, 专注记录: ${result.newTimeLogs.length + result.updatedTimeLogs.length}, 倒计时: ${result.newCountdowns.length + result.updatedCountdowns.length}, 分类: ${result.newTodoGroups.length + result.updatedTodoGroups.length}, 标签: ${result.newPomodoroTags.length + result.updatedPomodoroTags.length}, 番茄钟: ${result.pomodoroActions.length})')),
      );
    }
  }

  Future<void> _executePomodoroAction(AiTodoAction action) async {
    switch (action.type) {
      case AiTodoActionType.startPlanBlockPomodoro:
        final blockId = action.planBlockId;
        if (blockId == null || blockId.isEmpty) return;
        final blocks = _planBlocks.isNotEmpty
            ? _planBlocks
            : await StorageService.getPlanBlocks(widget.username);
        TodoPlanBlock? block;
        for (final item in blocks) {
          if (item.uuid == blockId && !item.isDeleted) {
            block = item;
            break;
          }
        }
        if (block == null) return;
        final existing = await PomodoroService.loadRunState();
        if (existing != null &&
            existing.phase != PomodoroPhase.idle &&
            existing.phase != PomodoroPhase.finished) {
          return;
        }
        final settings = await PomodoroService.getSettings();
        TodoItem? boundTodo;
        final match = widget.todos.where((t) => t['id'] == block!.todoId);
        if (match.isNotEmpty) {
          boundTodo = TodoItem(
            id: block.todoId,
            title: match.first['title']?.toString() ??
                block.titleSnapshot ??
                '规划任务',
          );
        }
        boundTodo ??= TodoItem(
          id: block.todoId,
          title: block.titleSnapshot ?? '规划任务',
        );
        block.status = TodoPlanStatus.focusing;
        block.markAsChanged();
        await StorageService.savePlanBlocks(widget.username, [block]);
        await PomodoroControlService.startFocus(
          settings: settings,
          boundTodo: boundTodo,
          durationMinutes: block.pomodoroRounds > 0
              ? block.pomodoroMinutes * block.pomodoroRounds
              : math.max(1, block.plannedMinutes),
          planBlockId: block.uuid,
          ensureSyncConnection: true,
        );
        break;
      case AiTodoActionType.startPomodoro:
        final existing = await PomodoroService.loadRunState();
        if (existing != null &&
            existing.phase != PomodoroPhase.idle &&
            existing.phase != PomodoroPhase.finished) {
          return;
        }
        final settings = await PomodoroService.getSettings();
        TodoItem? boundTodo;
        if (action.todoId != null) {
          final match = widget.todos.where((t) => t['id'] == action.todoId);
          if (match.isNotEmpty) {
            boundTodo = TodoItem(
              id: action.todoId,
              title: match.first['title']?.toString() ?? action.title ?? '专注',
              isDone: match.first['isDone'] == true,
              isDeleted: match.first['isDeleted'] == true,
            );
          }
        }
        boundTodo ??= action.title?.isNotEmpty == true
            ? TodoItem(id: '', title: action.title!)
            : null;
        await PomodoroControlService.startFocus(
          settings: settings,
          boundTodo: boundTodo,
          tagUuids: action.tagUuids,
          durationMinutes: action.durationMinutes,
          ensureSyncConnection: true,
        );
        break;
      case AiTodoActionType.stopPomodoro:
        await PomodoroControlService.stopCurrentFocus(
          username: widget.username,
          status: action.status == 'completed'
              ? PomodoroRecordStatus.completed
              : PomodoroRecordStatus.interrupted,
          markTodoComplete: action.status == 'completed',
          ensureSyncConnection: true,
        );
        break;
      case AiTodoActionType.createTodo:
      case AiTodoActionType.updateTodo:
      case AiTodoActionType.completeTodo:
      case AiTodoActionType.deleteTodo:
      case AiTodoActionType.rescheduleTodo:
      case AiTodoActionType.bulkRescheduleTodo:
      case AiTodoActionType.categorizeTodo:
      case AiTodoActionType.planTodos:
      case AiTodoActionType.createPlanBlock:
      case AiTodoActionType.updatePlanBlock:
      case AiTodoActionType.deletePlanBlock:
      case AiTodoActionType.reschedulePlanBlocks:
      case AiTodoActionType.skipPlanBlock:
      case AiTodoActionType.splitTodo:
      case AiTodoActionType.mergeTodos:
      case AiTodoActionType.createTimeLog:
      case AiTodoActionType.updateTimeLog:
      case AiTodoActionType.deleteTimeLog:
      case AiTodoActionType.createCountdown:
      case AiTodoActionType.updateCountdown:
      case AiTodoActionType.completeCountdown:
      case AiTodoActionType.deleteCountdown:
      case AiTodoActionType.createTodoGroup:
      case AiTodoActionType.updateTodoGroup:
      case AiTodoActionType.deleteTodoGroup:
      case AiTodoActionType.createPomodoroTag:
      case AiTodoActionType.updatePomodoroTag:
      case AiTodoActionType.deletePomodoroTag:
      case AiTodoActionType.unknown:
        break;
    }
  }

  Widget _buildQuickQuestion(
    String text, {
    bool compact = false,
    bool expand = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return _PressableScale(
      onTap: () {
        _inputCtrl.text = text;
        _sendMessage();
      },
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: expand ? double.infinity : null,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 14,
            vertical: compact ? 7 : 10,
          ),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            text,
            maxLines: expand ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 12 : 13,
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  String _buildRawReplyDebugText(ChatMessage msg) {
    final sections = <String>[];
    if (msg.rawContent.trim().isNotEmpty) {
      sections.add(msg.rawContent.trim());
    } else {
      sections.add('当前历史消息没有保存模型原始回复。');
      if (msg.content.trim().isNotEmpty) {
        sections.add('[CLEANED_CONTENT]\n${msg.content.trim()}');
      }
    }

    final actions = msg.todoActions;
    if (actions != null && actions.isNotEmpty) {
      const encoder = JsonEncoder.withIndent('  ');
      sections.add('[PARSED_ACTIONS]\n${encoder.convert(
        actions.map((action) => action.toJson()).toList(),
      )}');
    }

    if (msg.reasoningContent.trim().isNotEmpty) {
      sections.add('[REASONING]\n${msg.reasoningContent.trim()}');
    }

    if (msg.smartContext.trim().isNotEmpty) {
      sections.add('[SMART_CONTEXT]\n${msg.smartContext.trim()}');
    } else {
      sections.add(
          '[SMART_CONTEXT]\n本次回复未触发关键词注入额外上下文（课程/专注记录/冲突/团队）。\n注意：系统提示词中始终包含待办、分组、倒计时、番茄标签等基础上下文，因此模型仍可回答相关问题。');
    }

    return sections.join('\n\n');
  }

  Future<void> _showRawReplyDialog(ChatMessage msg) async {
    final colorScheme = Theme.of(context).colorScheme;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('模型原始回复'),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.82,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
            child: SingleChildScrollView(
              child: SelectableText(
                _buildRawReplyDebugText(msg),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: colorScheme.onSurface,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg, bool isDark) {
    final isUser = msg.role == ChatRole.user;
    final timeStr = DateFormat('HH:mm').format(msg.timestamp);
    final colorScheme = Theme.of(context).colorScheme;
    final maxBubbleWidth = MediaQuery.of(context).size.width >= 900
        ? 680.0
        : MediaQuery.of(context).size.width * 0.78;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
                child: Icon(
                  Icons.smart_toy_rounded,
                  size: 18,
                  color: colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxBubbleWidth),
              child: Column(
                crossAxisAlignment:
                    isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isUser && msg.reasoningContent.isNotEmpty)
                    _buildCollapsibleReasoning(
                      msg.reasoningContent,
                      isDark,
                      false,
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isUser
                          ? colorScheme.primary
                          : isDark
                              ? colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.55)
                              : colorScheme.surface,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isUser ? 16 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 16),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.035),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                      border: isUser
                          ? null
                          : Border.all(
                              color: colorScheme.outlineVariant
                                  .withValues(alpha: 0.55),
                              width: 0.5,
                            ),
                    ),
                    child: isUser
                        ? Text(
                            msg.content,
                            style: TextStyle(
                              color: colorScheme.onPrimary,
                              fontSize: 15,
                              height: 1.42,
                            ),
                          )
                        : MarkdownBody(
                            data: msg.content,
                            styleSheet: MarkdownStyleSheet(
                              p: TextStyle(
                                color: colorScheme.onSurface,
                                fontSize: 15,
                                height: 1.45,
                              ),
                              strong: TextStyle(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                              listBullet: TextStyle(
                                color: colorScheme.primary,
                                fontSize: 15,
                              ),
                              code: TextStyle(
                                color: colorScheme.secondary,
                                backgroundColor: colorScheme.secondaryContainer
                                    .withValues(alpha: 0.5),
                                fontSize: 14,
                                fontFamily: 'monospace',
                              ),
                              blockquote: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                              blockquoteDecoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    color: colorScheme.primary,
                                    width: 4,
                                  ),
                                ),
                                color: colorScheme.primaryContainer
                                    .withValues(alpha: 0.1),
                              ),
                            ),
                            selectable: true,
                          ),
                  ),
                  if (!_shouldDetachActions &&
                      msg.todoActions != null &&
                      msg.todoActions!.isNotEmpty)
                    _buildMessageTodoActions(msg, isDark),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          timeStr,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w300,
                            color: colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.75),
                          ),
                        ),
                        if (!isUser) ...[
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => _showRawReplyDialog(msg),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.data_object_rounded,
                                    size: 12,
                                    color: colorScheme.primary
                                        .withValues(alpha: 0.82),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    '原始回复',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      color: colorScheme.primary
                                          .withValues(alpha: 0.88),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: colorScheme.secondary.withValues(alpha: 0.1),
                child: Icon(
                  Icons.person_rounded,
                  size: 18,
                  color: colorScheme.secondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCollapsibleReasoning(
    String reasoning,
    bool isDark,
    bool isStreaming,
  ) {
    return _CollapsibleReasoningWidget(
      reasoning: reasoning,
      isDark: isDark,
      isStreaming: isStreaming,
    );
  }

  Widget _buildStreamingBubble(bool isDark) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _PulseAvatar(
            child: CircleAvatar(
              radius: 16,
              backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
              child: Icon(
                Icons.smart_toy_rounded,
                size: 18,
                color: colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_streamingReasoning.isNotEmpty)
                  _buildCollapsibleReasoning(_streamingReasoning, isDark, true),
                if (_streamingContent.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.4)
                          : Colors.white,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                        bottomLeft: Radius.circular(4),
                        bottomRight: Radius.circular(20),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                      border: Border.all(
                        color:
                            colorScheme.outlineVariant.withValues(alpha: 0.5),
                        width: 0.5,
                      ),
                    ),
                    child: MarkdownBody(
                      data: _streamingContent,
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 15,
                          height: 1.4,
                        ),
                        strong: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                        code: TextStyle(
                          color: colorScheme.secondary,
                          backgroundColor: colorScheme.secondaryContainer
                              .withValues(alpha: 0.5),
                          fontSize: 14,
                          fontFamily: 'monospace',
                        ),
                      ),
                      selectable: true,
                    ),
                  )
                else if (_streamingReasoning.isEmpty)
                  const _ThinkingLoader(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(ColorScheme colorScheme) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _buildModelSelector(),
                  ),
                ),
                if (!_isLoading && _inputHasText)
                  TextButton.icon(
                    icon: const Icon(Icons.content_copy_rounded, size: 16),
                    label: const Text('复制提示词'),
                    onPressed: _copyManualPromptFromInput,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (!_isLoading)
                  IconButton(
                    icon: Icon(
                      Icons.assignment_rounded,
                      size: 17,
                      color: colorScheme.onSurface.withValues(alpha: 0.58),
                    ),
                    onPressed: _pasteManualReplyFromClipboard,
                    tooltip: '粘贴AI回复识别',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(8),
                  ),
                IconButton(
                  icon: Icon(
                    Icons.delete_sweep_rounded,
                    size: 16,
                    color: colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  onPressed: _clearHistory,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(8),
                ),
              ],
            ),
            if (_inputHasText &&
                (_liveSmartContextPreview.isNotEmpty ||
                    _liveActionProtocolPreview.isNotEmpty)) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.22),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '发送预览',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _injectMoreContext = !_injectMoreContext;
                              if (_injectMoreContext) {
                                _useCustomInjectRange = false;
                              }
                              _liveSmartContextPreview =
                                  _buildSmartContextPreview(
                                      _inputCtrl.text.trim());
                              _liveActionProtocolPreview =
                                  _buildActionProtocolPreview(
                                      _inputCtrl.text.trim());
                              _liveEstimatedTokens =
                                  _estimateTokensForPendingInput(
                                      _inputCtrl.text.trim());
                            });
                          },
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 22),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                          ),
                          child: Text(
                            _injectMoreContext ? '注入更多: 开' : '注入更多',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _pickCustomInjectRange,
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 22),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                          ),
                          child: Text(
                            _useCustomInjectRange ? '自定义注入: 开' : '自定义注入',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_injectMoreContext)
                      Text(
                        '已扩大到未来30天范围',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    if (_useCustomInjectRange &&
                        _customInjectStart != null &&
                        _customInjectEnd != null)
                      Text(
                        '自定义范围: ${DateFormat('yyyy-MM-dd').format(_customInjectStart!)} 至 ${DateFormat('yyyy-MM-dd').format(_customInjectEnd!)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    const SizedBox(height: 6),
                    if (_liveSmartContextPreview.isNotEmpty)
                      SelectableText(
                        _liveSmartContextPreview,
                        maxLines: 2,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: colorScheme.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                    if (_liveSmartContextPreview.isEmpty)
                      Text(
                        '将注入：无（当前消息无需额外业务上下文）',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: colorScheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                    if (_liveActionProtocolPreview.isNotEmpty)
                      SelectableText(
                        _liveActionProtocolPreview,
                        maxLines: 3,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: colorScheme.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                    SelectableText(
                      '预计Token：~$_liveEstimatedTokens',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: colorScheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Container(
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(width: 4),
                  _buildIconButtonOption(
                    icon: Icons.psychology_rounded,
                    isSelected: _deepThinking,
                    tooltip: '深度思考',
                    onTap: (val) async {
                      setState(() => _deepThinking = val);
                      await ChatStorageService.setDeepThinkingEnabled(val);
                    },
                  ),
                  _buildIconButtonOption(
                    icon: Icons.auto_awesome_rounded,
                    isSelected: _smartContext,
                    tooltip: '智能上下文',
                    onTap: (val) => setState(() {
                      _smartContext = val;
                      _liveSmartContextPreview =
                          _buildSmartContextPreview(_inputCtrl.text.trim());
                      _liveActionProtocolPreview =
                          _buildActionProtocolPreview(_inputCtrl.text.trim());
                      _liveEstimatedTokens = _estimateTokensForPendingInput(
                          _inputCtrl.text.trim());
                    }),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    height: 20,
                    width: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      maxLines: 4,
                      minLines: 1,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: '问问助手...',
                        hintStyle: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.3),
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (!_isLoading &&
                      _messages.isNotEmpty &&
                      _messages.last.role == ChatRole.assistant)
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      tooltip: '重试',
                      onPressed: _retryLastMessage,
                      style: IconButton.styleFrom(
                        foregroundColor: colorScheme.onSurfaceVariant,
                        padding: const EdgeInsets.all(8),
                      ),
                    ),
                  IconButton(
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      switchInCurve: Curves.easeOutBack,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => ScaleTransition(
                        scale: animation,
                        child: FadeTransition(
                          opacity: animation,
                          child: child,
                        ),
                      ),
                      child: _isLoading
                          ? const Icon(
                              Icons.stop_rounded,
                              key: ValueKey('stop'),
                              size: 20,
                            )
                          : const Icon(
                              Icons.arrow_upward_rounded,
                              key: ValueKey('send'),
                              size: 20,
                            ),
                    ),
                    onPressed: _isLoading ? _stopGeneration : _sendMessage,
                    style: IconButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      padding: const EdgeInsets.all(8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconButtonOption({
    required IconData icon,
    required bool isSelected,
    required String tooltip,
    required Function(bool) onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => onTap(!isSelected),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primary.withValues(alpha: 0.1)
                : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutBack,
            scale: isSelected ? 1.08 : 1,
            child: Icon(
              icon,
              size: 18,
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

class _StaggeredFadeSlide extends StatelessWidget {
  final Widget child;
  final Duration delay;

  const _StaggeredFadeSlide({
    required this.child,
    this.delay = Duration.zero,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 360 + delay.inMilliseconds),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final delayedValue = delay.inMilliseconds == 0
            ? value
            : ((value * (360 + delay.inMilliseconds) - delay.inMilliseconds) /
                    360)
                .clamp(0.0, 1.0);
        return Opacity(
          opacity: delayedValue,
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - delayedValue)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final BorderRadius borderRadius;

  const _PressableScale({
    required this.child,
    required this.onTap,
    required this.borderRadius,
  });

  @override
  State<_PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<_PressableScale> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = _pressed ? 0.96 : (_hovered ? 1.03 : 1.0);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: Material(
            color: Colors.transparent,
            borderRadius: widget.borderRadius,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: widget.borderRadius,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class _IridescentActionPanel extends StatefulWidget {
  final Widget child;
  final bool isDark;

  const _IridescentActionPanel({
    required this.child,
    required this.isDark,
  });

  @override
  State<_IridescentActionPanel> createState() => _IridescentActionPanelState();
}

class _IridescentActionPanelState extends State<_IridescentActionPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            foregroundPainter: _IridescentBorderPainter(
              progress: _controller.value,
              isDark: widget.isDark,
            ),
            child: Padding(
              padding: const EdgeInsets.all(2.5),
              child: child,
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _IridescentBorderPainter extends CustomPainter {
  final double progress;
  final bool isDark;

  const _IridescentBorderPainter({
    required this.progress,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final rect = Offset.zero & size;
    final center = rect.center;
    final borderRect = rect.deflate(2.0);
    final radius = BorderRadius.circular(18).toRRect(borderRect);
    final colors = <Color>[
      const Color(0xFF5EFCE8).withValues(alpha: isDark ? 0.88 : 0.82),
      const Color(0xFF736EFE).withValues(alpha: isDark ? 0.82 : 0.74),
      const Color(0xFFFF7CE5).withValues(alpha: isDark ? 0.90 : 0.78),
      const Color(0xFFFFF275).withValues(alpha: isDark ? 0.86 : 0.72),
      const Color(0xFF7CFF8A).withValues(alpha: isDark ? 0.84 : 0.70),
      const Color(0xFF5EFCE8).withValues(alpha: isDark ? 0.88 : 0.82),
    ];
    final shader = SweepGradient(
      colors: colors,
      stops: const [0, 0.18, 0.38, 0.58, 0.78, 1],
      transform: GradientRotation(progress * math.pi * 2),
    ).createShader(rect);

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5.0
      ..shader = shader
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawRRect(radius, glowPaint);

    for (var i = 0; i < 3; i++) {
      final wave = math.sin((progress * math.pi * 2) + i * 1.7);
      final drift = Offset(
        math.cos(progress * math.pi * 2 + i) * 0.8,
        math.sin(progress * math.pi * 2 + i * 1.3) * 0.8,
      );
      final rippleRect = Rect.fromCenter(
        center: center + drift,
        width: borderRect.width - (i * 1.2) + wave,
        height: borderRect.height - (i * 1.2) - wave,
      );
      final ripple = BorderRadius.circular(18.0 - i).toRRect(rippleRect);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = i == 0 ? 2.1 : 1.1
        ..shader = shader
        ..blendMode = BlendMode.srcOver;
      canvas.drawRRect(ripple, paint);
    }

    final sheenPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: isDark ? 0.28 : 0.38);
    final highlightRect = borderRect.deflate(1.2).shift(
          Offset(
            math.cos(progress * math.pi * 2) * 0.7,
            math.sin(progress * math.pi * 2) * 0.7,
          ),
        );
    canvas.drawRRect(
        BorderRadius.circular(16).toRRect(highlightRect), sheenPaint);
  }

  @override
  bool shouldRepaint(covariant _IridescentBorderPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isDark != isDark;
  }
}

class _CollapsibleReasoningWidget extends StatefulWidget {
  final String reasoning;
  final bool isDark;
  final bool isStreaming;

  const _CollapsibleReasoningWidget({
    required this.reasoning,
    required this.isDark,
    required this.isStreaming,
  });

  @override
  State<_CollapsibleReasoningWidget> createState() =>
      _CollapsibleReasoningWidgetState();
}

class _CollapsibleReasoningWidgetState
    extends State<_CollapsibleReasoningWidget> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: widget.isDark
            ? Colors.grey[900]!.withValues(alpha: 0.5)
            : Colors.grey[100]!.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.psychology_outlined,
                    size: 16,
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '思考过程',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.7),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  if (widget.isStreaming)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.5),
                      ),
                    ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      size: 20,
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: MarkdownBody(
                data: widget.reasoning,
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                  code: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.3),
                    fontSize: 12,
                  ),
                ),
                selectable: true,
              ),
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
            firstCurve: Curves.easeInCubic,
            secondCurve: Curves.easeOutCubic,
            sizeCurve: Curves.easeOutCubic,
          ),
        ],
      ),
    );
  }
}

class _PulseAvatar extends StatefulWidget {
  final Widget child;
  const _PulseAvatar({required this.child});
  @override
  State<_PulseAvatar> createState() => _PulseAvatarState();
}

class _PulseAvatarState extends State<_PulseAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.95, end: 1.05).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: widget.child,
    );
  }
}

class _ThinkingLoader extends StatefulWidget {
  const _ThinkingLoader();
  @override
  State<_ThinkingLoader> createState() => _ThinkingLoaderState();
}

class _ThinkingLoaderState extends State<_ThinkingLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)
            : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(4),
          bottomRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...List.generate(3, (i) {
            return AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final offset = (i * 0.2);
                double value = (_controller.value + offset) % 1.0;
                return Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(
                      alpha: 0.2 + (0.8 * (1.0 - (value - 0.5).abs() * 2)),
                    ),
                    shape: BoxShape.circle,
                  ),
                );
              },
            );
          }),
          const SizedBox(width: 10),
          Text(
            '正在思考',
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _DanmakuSuggestions extends StatefulWidget {
  final List<String> suggestions;
  final Function(String) onTap;

  const _DanmakuSuggestions({
    required this.suggestions,
    required this.onTap,
  });

  @override
  State<_DanmakuSuggestions> createState() => _DanmakuSuggestionsState();
}

class _DanmakuSuggestionsState extends State<_DanmakuSuggestions> {
  late ScrollController _scrollCtrl1;
  late ScrollController _scrollCtrl2;
  late ScrollController _scrollCtrl3;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scrollCtrl1 = ScrollController();
    _scrollCtrl2 = ScrollController();
    _scrollCtrl3 = ScrollController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startScrolling();
    });
  }

  void _startScrolling() {
    _timer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (!mounted) return;
      _autoScroll(_scrollCtrl1, 0.35);
      _autoScroll(_scrollCtrl2, 0.55);
      _autoScroll(_scrollCtrl3, 0.45);
    });
  }

  void _autoScroll(ScrollController ctrl, double speed) {
    if (ctrl.hasClients) {
      final max = ctrl.position.maxScrollExtent;
      if (max > 0) {
        final next = ctrl.offset + speed;
        if (next >= max) {
          ctrl.jumpTo(0);
        } else {
          ctrl.jumpTo(next);
        }
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollCtrl1.dispose();
    _scrollCtrl2.dispose();
    _scrollCtrl3.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.suggestions.isEmpty) return const SizedBox.shrink();

    // 分成三行
    final row1 = <String>[];
    final row2 = <String>[];
    final row3 = <String>[];

    for (int i = 0; i < widget.suggestions.length; i++) {
      if (i % 3 == 0) {
        row1.add(widget.suggestions[i]);
      } else if (i % 3 == 1) {
        row2.add(widget.suggestions[i]);
      } else {
        row3.add(widget.suggestions[i]);
      }
    }

    // 为了实现无缝循环，每行内容加倍
    final items1 = [...row1, ...row1, ...row1];
    final items2 = [...row2, ...row2, ...row2];
    final items3 = [...row3, ...row3, ...row3];

    return Column(
      children: [
        if (row1.isNotEmpty) _buildRow(_scrollCtrl1, items1),
        if (row2.isNotEmpty) const SizedBox(height: 10),
        if (row2.isNotEmpty) _buildRow(_scrollCtrl2, items2),
        if (row3.isNotEmpty) const SizedBox(height: 10),
        if (row3.isNotEmpty) _buildRow(_scrollCtrl3, items3),
      ],
    );
  }

  Widget _buildRow(ScrollController ctrl, List<String> items) {
    return Expanded(
      child: ListView.builder(
        controller: ctrl,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: _DanmakuItem(
              text: items[index],
              onTap: () => widget.onTap(items[index]),
            ),
          );
        },
      ),
    );
  }
}

class _DanmakuItem extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _DanmakuItem({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isDark ? colorScheme.surfaceContainerHigh : colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
