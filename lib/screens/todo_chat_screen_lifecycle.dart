part of 'todo_chat_screen.dart';
// ignore_for_file: annotate_overrides, unused_element, unused_element_parameter

mixin _TodoChatLifecycle on _TodoChatScreenStateBase {
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
    _fixedSchedules = List<FixedScheduleItem>.from(widget.fixedSchedules);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkCoachMarks();
    });
  }

  void _checkCoachMarks() async {
    if (!mounted || _showCoachMarks) return;

    final hasShown = await FeatureTipService.hasTipBeenShown('todo_chat_guide');
    if (hasShown || !mounted) return;

    // 等待布局动画完成，避免获取的控件位置不准确
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    setState(() {
      _showCoachMarks = true;
    });

    CoachMarkOverlay.show(
      context: context,
      steps: [
        CoachMarkStep(
          targetKey: _historyKey,
          title: '历史对话',
          description: '点击这里可以展开或折叠历史对话列表，随时回顾之前的聊天记录。',
        ),
        CoachMarkStep(
          targetKey: _newSessionKey,
          title: '新建对话',
          description: '点击可以开启一轮全新的对话，不带历史记录的包袱。',
        ),
        CoachMarkStep(
          targetKey: _settingsKey,
          title: '助手设置',
          description: '如果你想调整大模型的系统提示词或自定义 API 设置，点这里进行个性化配置。',
        ),
        CoachMarkStep(
          targetKey: _inputKey,
          title: '智能输入区',
          description: '你可以用自然语言输入需求（比如“明天上午9点有个组会”），AI 助手会自动判断它应是日程、待办还是规划块。',
        ),
      ],
      onFinish: () {
        if (mounted) {
          setState(() {
            _showCoachMarks = false;
          });
        }
        FeatureTipService.markTipShown('todo_chat_guide');
      },
      onSkip: () {
        if (mounted) {
          setState(() {
            _showCoachMarks = false;
          });
        }
        FeatureTipService.markTipShown('todo_chat_guide');
      },
    );
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
          fixedSchedules: _fixedSchedules,
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
      prompt.contains('create_schedule') ||
          prompt.contains('update_schedule') ||
          prompt.contains('cancel_schedule') ||
          prompt.contains('delete_schedule'),
      '日程相关',
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
    String financeContext = '',
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
          'content': msg.toLLMMessage(),
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
          'content': msg.toLLMMessage(),
        });
      }
    }

    final smartContext = _injectContext(apiMessages);
    var combinedContext = smartContext;
    if (financeContext.trim().isNotEmpty) {
      int lastUserIndex = -1;
      for (int i = apiMessages.length - 1; i >= 0; i--) {
        if (apiMessages[i]['role'] == 'user') {
          lastUserIndex = i;
          break;
        }
      }
      if (lastUserIndex != -1) {
        final currentUserContent = apiMessages[lastUserIndex]['content'] ?? '';
        apiMessages[lastUserIndex] = {
          'role': 'user',
          'content': '${financeContext.trim()}\n\n$currentUserContent',
        };
        combinedContext = [
          smartContext,
          financeContext.trim(),
        ].where((item) => item.isNotEmpty).join('\n\n');
      }
    }
    if (trackSmartContext) {
      _lastRequestSmartContext = combinedContext;
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
      fixedSchedules: _fixedSchedules,
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

    return '[已省略 $omittedCount 条历史消息（用户 $userMsgCount 条，助手 $assistantMsgCount 条）。对话已围绕事项管理展开，继续当前话题即可。]';
  }
}
