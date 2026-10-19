part of 'todo_chat_screen.dart';

// ignore_for_file: unused_element, unused_element_parameter, annotate_overrides

abstract class _TodoChatScreenStateBase extends State<TodoChatScreen> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final ValueNotifier<int> _streamingBubbleRevision = ValueNotifier<int>(0);
  final ValueNotifier<int> _inputAreaRevision = ValueNotifier<int>(0);
  Timer? _inputPreviewTimer;
  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  String _streamingContent = '';
  String _streamingReasoning = '';
  List<ChatNativeToolCall> _streamingToolCalls = [];
  String? _streamingFinishReason;
  List<String> _suggestions = [];
  String _customPrompt = '';
  bool _promptEnabled = true;
  bool _deepThinking = true;
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
  AiContextMode _contextMode = AiContextMode.functionCalling;
  bool get _usesContextInjection =>
      _smartContext && _contextMode == AiContextMode.smartContextInjection;
  final Map<String, Map<String, dynamic>> _queryToolResults = {};
  AiQueryToolService _createQueryToolService();
  bool _showInjectedContextPreview = false;
  bool _injectMoreContext = false;
  bool _useCustomInjectRange = false;
  DateTime? _customInjectStart;
  DateTime? _customInjectEnd;
  bool _inputHasText = false;
  String _liveSmartContextPreview = '';
  String _liveActionProtocolPreview = '';
  int _liveEstimatedTokens = 0;
  ChatImageAttachment? _pendingAttachment;
  ChatUsageSummary? _pendingVoiceUsageSummary;
  bool _isPickingAttachment = false;
  String? _activeSessionId;
  Map<String, int> _categoryReminderDefaults = {};
  final GlobalKey _historyKey = GlobalKey();
  final GlobalKey _newSessionKey = GlobalKey();
  final GlobalKey _settingsKey = GlobalKey();
  final GlobalKey _inputKey = GlobalKey();
  final GlobalKey _tutorialButtonKey = GlobalKey();
  final Map<String, GlobalKey> _todoActionPanelKeys = {};
  bool _showCoachMarks = false;

  List<TodoPlanBlock> _planBlocks = [];
  PomodoroEntryIntent? _pendingPlanPomodoroEntry;
  GlobalKey _todoActionPanelKeyFor(ChatMessage message) =>
      _todoActionPanelKeys.putIfAbsent(message.id, GlobalKey.new);
  List<HabitGoal> _habitGoals = [];
  List<FixedScheduleItem> _fixedSchedules = [];
  Completer<void>? _cancelGeneration;
  bool _classificationSuggestionInjected = false;

  void _notifyStreamingBubbleChanged() {
    _streamingBubbleRevision.value++;
  }

  void _notifyInputAreaChanged() {
    _inputAreaRevision.value++;
  }

  FinanceDateRange? _financeContextDateRangeOverride() {
    final range = AiTodoContextBuilder.resolveCustomInjectionDateRange(
      customStart: _useCustomInjectRange ? _customInjectStart : null,
      customEnd: _useCustomInjectRange ? _customInjectEnd : null,
      injectMoreContext: _injectMoreContext,
    );
    if (range == null) return null;
    return FinanceDateRange(range.start, range.endExclusive);
  }

  // 🚀 宽屏适配相关
  bool _sidebarVisible = true;
  bool _actionRailCollapsed = false;
  bool get _isWide => MediaQuery.of(context).size.width >= 900;
  bool get _hasPendingActionMessages => _pendingActionMessages.isNotEmpty;
  int get _pendingActionCount {
    var count = 0;
    for (final msg in _messages) {
      final actions = msg.todoActions;
      if (actions == null) continue;
      for (final action in actions) {
        if (!action.isAdded && !action.isIgnored) count++;
      }
    }
    return count;
  }
  bool get _hasActionRailSpace {
    final width = MediaQuery.of(context).size.width;
    const actionRailWidth = 344.0;
    final historyWidth = _sidebarVisible ? 304.0 : 0.0;
    return width >= 900 && width - historyWidth - actionRailWidth >= 520;
  }

  bool get _shouldDetachActions =>
      _hasActionRailSpace && _hasPendingActionMessages;
  bool get _usesActionRail => _shouldDetachActions && !_actionRailCollapsed;

  List<String> _extractFreshSuggestions(
    String source, {
    Iterable<AiTodoAction> todoActions = const [],
    Iterable<FinanceEntryDraft> financeDrafts = const [],
    Iterable<FinanceAiAction> financeActions = const [],
    Iterable<String> settingsTargets = const [],
    Iterable<ChatNativeToolCall> nativeToolCalls = const [],
  }) {
    final actionContext = _suggestionCardContext(
      todoActions: todoActions,
      financeDrafts: financeDrafts,
      financeActions: financeActions,
      settingsTargets: settingsTargets,
      nativeToolCalls: nativeToolCalls,
    );
    return AiActionParser.extractSuggestions(
      source,
      previouslyShown: _recentAssistantSuggestions(_messages),
      contextText: _suggestionContext(
        _messages,
        extraText: source,
        actionContext: actionContext,
      ),
    );
  }

  String _suggestionContext(
    Iterable<ChatMessage> messages, {
    String extraText = '',
    String actionContext = '',
  }) {
    final messageList = messages.toList(growable: false);
    final latestUserRequest = messageList.reversed
        .firstWhere(
          (message) => message.role == ChatRole.user,
          orElse: () => ChatMessage(role: ChatRole.user, content: ''),
        )
        .content
        .trim();
    final cleanExtraText = AiActionParser.cleanActionContent(extraText);
    return [
      latestUserRequest,
      cleanExtraText,
      actionContext,
    ]
        .where((content) => content.trim().isNotEmpty)
        .join('\n');
  }

  String _suggestionCardContext({
    Iterable<AiTodoAction> todoActions = const [],
    Iterable<FinanceEntryDraft> financeDrafts = const [],
    Iterable<FinanceAiAction> financeActions = const [],
    Iterable<String> settingsTargets = const [],
    Iterable<ChatNativeToolCall> nativeToolCalls = const [],
  }) {
    final values = <String>[];

    void add(Object? value) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && text != 'null') values.add(text);
    }

    for (final action in todoActions.where(
      (action) => !action.isAdded && !action.isIgnored,
    )) {
      add(action.title);
      add(action.remark);
      add(action.location);
      add(action.date);
      add(action.startTime);
      add(action.dueDate);
      add(action.habitSourceType);
      add(action.habitPeriodType);
      add(action.unit);
      add(action.targetValue);
      add(action.durationMinutes);
      add(action.recurrence);
      add(action.metadata['groupName']);
      add(action.metadata['priorityLabel']);
      final tags = action.metadata['tags'];
      if (tags is Iterable) {
        for (final tag in tags) {
          add(tag);
        }
      }
    }
    for (final draft in financeDrafts.where(
      (draft) => !draft.isAdded && !draft.isIgnored,
    )) {
      add(draft.merchant);
      add(draft.categoryName);
      add(draft.paymentMethodName);
      add(draft.note);
      add(draft.transactionDate);
    }
    for (final action in financeActions.where(
      (action) => !action.isAdded && !action.isIgnored,
    )) {
      add(action.keyword);
      add(action.merchant);
      add(action.categoryName);
      add(action.paymentMethodName);
      add(action.note);
      add(action.reason);
      add(action.transactionDate);
      add(action.from);
      add(action.to);
    }
    for (final target in settingsTargets) {
      add(target);
    }
    const queryTextFields = {
      'items',
      'results',
      'records',
      'summary',
      'title',
      'name',
      'content',
      'remark',
      'note',
      'description',
      'merchant',
      'category',
      'category_name',
      'categoryName',
      'payment_method',
      'payment_method_name',
      'paymentMethodName',
      'tag',
      'tags',
      'location',
      'course',
      'course_name',
      'habit_name',
      'group_name',
      'groupName',
      'label',
      'display_name',
      'summary_text',
    };
    void addQueryText(Object? value) {
      if (value is Map) {
        for (final entry in value.entries) {
          if (queryTextFields.contains(entry.key.toString())) {
            addQueryText(entry.value);
          }
        }
      } else if (value is Iterable) {
        for (final item in value) {
          addQueryText(item);
        }
      } else {
        add(value);
      }
    }
    for (final call in nativeToolCalls) {
      if (call.name.startsWith('query_') && call.result != null) {
        addQueryText(call.result);
      }
    }
    return values.join('\n');
  }

  List<String> _recentAssistantSuggestions(
    Iterable<ChatMessage> messages,
  ) {
    final assistants = messages
        .where((message) => message.role == ChatRole.assistant)
        .toList(growable: false);
    return assistants.reversed
        .take(3)
        .expand((message) {
          final source = message.rawContent.trim().isNotEmpty
              ? message.rawContent
              : message.content;
          return AiActionParser.extractSuggestions(source);
        })
        .toSet()
        .toList(growable: false);
  }

  void initState();
  void _checkCoachMarks();
  Future<void> _loadCategoryDefaults();
  Future<void> _loadPlanBlocks();
  Future<void> _loadHabitGoals();
  void dispose();
  void _handleInputChanged();
  String _buildSmartContextPreview(String userText);
  String _recentConversationTextForContext({String? excludingMessageId});
  String _buildContextQueryText(String userText);
  String _buildActionProtocolPreview(String userText);
  Future<void> _pickCustomInjectRange();
  int _estimateTokensForPendingInput(String text);
  int _estimateRequestTokens(List<Map<String, dynamic>> messages);
  int _estimateTextTokens(String text);
  Future<void> _initSessions();
  Future<void> _switchSession(String sessionId);
  Future<void> _newSession();
  Future<void> _deleteSession(String sessionId);
  Future<void> _loadHistory();
  void _injectInitialCategorizationSuggestion();
  Future<void> _loadPromptSettings();
  Future<void> _loadChatConfig();
  Future<void> _loadDeepThinking();
  Future<void> _openTutorialPage();
  void _scrollToBottom();
  String _buildSystemPrompt({
    bool nativeToolCalls = false,
    bool? queryTools,
    bool settingsNavigation = true,
  });
  List<Map<String, dynamic>> _buildApiMessages({
    String? pendingUserText,
    bool trackSmartContext = true,
    String financeContext = '',
    String habitContext = '',
    bool nativeToolCalls = false,
    bool includeReasoningContent = false,
    bool? contextInjection,
    bool? queryTools,
  });
  String _latestUserTextFromHistory();
  String _latestAssistantMessageForActionRouting();
  String _injectContext(
    List<Map<String, dynamic>> apiMessages, {
    bool? enabled,
  });
  String _buildContextSummary();
  Future<void> _sendMessage();
  ChatUsageSummary? _takePendingVoiceUsageSummary();
  Future<void> _openVoiceInput();
  Future<void> _pickChatAttachment();
  Future<bool> _pasteChatImageFromClipboard();
  Future<List<Map<String, dynamic>>> _buildApiMessagesForRequest({
    required String financeContext,
    required String habitContext,
    required String provider,
    bool nativeToolCalls = false,
    bool includeReasoningContent = false,
    bool? contextInjection,
    bool? queryTools,
  });
  Future<void> _copyManualPromptFromInput();
  Future<void> _pasteManualReplyFromClipboard();
  Future<void> _importManualAiReply(String fullContent);
  String _lastUserContent();
  void _stopGeneration();
  void _retryLastMessage();
  Future<void> _generateSessionTitle({required String sessionId});
  Future<void> _clearHistory();
  Future<void> _showPromptSettings();
  Future<void> _showPromptSettingsFromSource(GlobalKey sourceKey);
  Widget build(BuildContext context);
  PreferredSizeWidget _buildResponsiveAppBar(
    bool isDark,
    ColorScheme colorScheme,
  );
  Widget _buildWideLayout(bool isDark, ColorScheme colorScheme);
  List<ChatMessage> get _pendingActionMessages;
  Widget _buildActionRail(bool isDark, ColorScheme colorScheme);
  Widget _buildCollapsedActionRailHandle(ColorScheme colorScheme);
  Widget _buildActionRailEmptyState(ColorScheme colorScheme);
  Widget _buildMobileLayout(bool isDark, ColorScheme colorScheme);
  Widget _buildMessageList(bool isDark, ColorScheme colorScheme);
  Widget _buildEmptyState(ColorScheme colorScheme);
  Widget _buildSuggestionsArea(ColorScheme colorScheme);
  String _getCurrentSessionTitle();
  void _showHistorySidebar();
  Widget _buildHistorySidebarContent(
    BuildContext context, {
    required bool isWideMode,
  });
  Future<void> _deleteAllSessions(BuildContext sidebarCtx);
  Widget _buildModelSelector();
  Future<void> _useGlobalModel();
  Future<void> _openLlmConfigPage();
  Future<void> _showModelConfig();
  String _formatTodoTimeRange(
    String? startTime,
    String? dueDate,
    bool isAllDay,
  );
  String _formatScheduleActionTime(AiTodoAction action);
  String _getTodoCurrentFolderName(String? todoId);
  String _getRecurrenceText(String recurrence);
  Widget _buildMessageTodoActions(ChatMessage msg, bool isDark);
  Widget _buildMessageFinanceDrafts(ChatMessage msg, bool isDark);
  Future<void> _editFinanceDraft(FinanceEntryDraft draft);
  Future<void> _ignoreFinanceDraft(FinanceEntryDraft draft);
  Widget _buildMessageFinanceActions(ChatMessage msg, bool isDark);
  Future<void> _editFinanceAction(FinanceAiAction action);
  Future<void> _deleteFinanceAction(FinanceAiAction action);
  Future<void> _ignoreFinanceAction(FinanceAiAction action);
  Widget _buildClassificationMetadata(AiTodoAction action);
  Widget _buildMiniMetaChip(IconData icon, String label, Color color);
  Widget _buildActionBadge(AiTodoAction action);
  void _ignoreAction(AiTodoAction action);
  void _recordIgnoreFeedback(AiTodoAction action);
  List<String> _extractActionKeywords(String text);
  Future<void> _editAction(AiTodoAction action);
  Widget _editField(
    TextEditingController controller,
    String label, {
    String? hint,
    TextInputType? keyboardType,
  });
  String? _nullIfBlank(String value);
  bool _usesTitle(AiTodoAction action);
  bool _usesRemark(AiTodoAction action);
  bool _usesStartTime(AiTodoAction action);
  bool _usesDueTime(AiTodoAction action);
  bool _usesDuration(AiTodoAction action);
  bool _usesReminder(AiTodoAction action);
  bool _usesColor(AiTodoAction action);
  bool _usesStatus(AiTodoAction action);
  bool _usesTags(AiTodoAction action);
  String _titleLabel(AiTodoAction action);
  String _startTimeLabel(AiTodoAction action);
  String _dueTimeLabel(AiTodoAction action);
  String _getMutationHint(AiTodoAction action);
  Widget _buildChangeSummary(AiTodoAction action);
  Widget _buildFixedScheduleChangeSummary(AiTodoAction action);
  Map<String, dynamic>? _findExistingTodo(String? todoId);
  String _getGroupName(String? groupId);
  bool _isDangerousAction(AiTodoAction action);
  String _getDangerHint(AiTodoAction action);
  Future<void> _saveHistorySilently();
  Future<void> _addTodosForMessage(ChatMessage msg);
  Future<void> _executePomodoroAction(AiTodoAction action);
  Widget _buildQuickQuestion(
    String text, {
    bool compact = false,
    bool expand = false,
  });
  String _buildRawReplyText(ChatMessage msg);
  Future<void> _showRawReplyDialog(ChatMessage msg);
  Widget _buildMessageBubble(ChatMessage msg, bool isDark);
  Widget _buildStreamingBubble(bool isDark);
  Widget _buildInputArea(ColorScheme colorScheme);
  Widget _buildChatAttachmentPreview(
    ChatImageAttachment attachment, {
    bool compact = false,
  });
}
