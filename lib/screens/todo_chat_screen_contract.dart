part of 'todo_chat_screen.dart';
// ignore_for_file: unused_element, unused_element_parameter, annotate_overrides

abstract class _TodoChatScreenStateBase extends State<TodoChatScreen> {
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
  final GlobalKey _historyKey = GlobalKey();
  final GlobalKey _newSessionKey = GlobalKey();
  final GlobalKey _settingsKey = GlobalKey();
  final GlobalKey _inputKey = GlobalKey();
  bool _showCoachMarks = false;

  List<TodoPlanBlock> _planBlocks = [];
  List<FixedScheduleItem> _fixedSchedules = [];
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
  void initState();
  void _checkCoachMarks();
  Future<void> _loadCategoryDefaults();
  Future<void> _loadPlanBlocks();
  void dispose();
  void _handleInputChanged();
  String _buildSmartContextPreview(String userText);
  String _buildContextQueryText(String userText);
  String _buildActionProtocolPreview(String userText);
  Future<void> _pickCustomInjectRange();
  int _estimateTokensForPendingInput(String text);
  int _estimateRequestTokens(List<Map<String, String>> messages);
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
  String _buildSystemPrompt();
  List<Map<String, String>> _buildApiMessages({
    String? pendingUserText,
    bool trackSmartContext = true,
  });
  String _latestUserTextFromHistory();
  String _injectContext(List<Map<String, String>> apiMessages);
  String _buildContextSummary();
  Future<void> _sendMessage();
  Future<void> _copyManualPromptFromInput();
  Future<void> _pasteManualReplyFromClipboard();
  Future<void> _importManualAiReply(String fullContent);
  String _lastUserContent();
  void _stopGeneration();
  void _retryLastMessage();
  Future<void> _generateSessionTitle();
  Future<void> _clearHistory();
  Future<void> _showPromptSettings();
  void _showPromptPreview(String prompt, bool enabled);
  Widget build(BuildContext context);
  PreferredSizeWidget _buildResponsiveAppBar(
      bool isDark, ColorScheme colorScheme);
  Widget _buildWideLayout(
    bool isDark,
    ColorScheme colorScheme,
  );
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
  Widget _buildHistorySidebarContent(BuildContext context,
      {required bool isWideMode});
  Future<void> _deleteAllSessions(BuildContext sidebarCtx);
  Widget _buildModelSelector();
  Future<void> _useGlobalModel();
  Future<void> _openLlmConfigPage();
  Future<void> _showModelConfig();
  List<String> _getSmartSuggestions();
  String _formatTodoTimeRange(
    String? startTime,
    String? dueDate,
    bool isAllDay,
  );
  String _formatScheduleActionTime(AiTodoAction action);
  String _getTodoCurrentFolderName(String? todoId);
  String _getRecurrenceText(String recurrence);
  Widget _buildMessageTodoActions(ChatMessage msg, bool isDark);
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
  String _idFieldLabel(AiTodoAction action);
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
  String _buildRawReplyDebugText(ChatMessage msg);
  Future<void> _showRawReplyDialog(ChatMessage msg);
  Widget _buildMessageBubble(ChatMessage msg, bool isDark);
  Widget _buildCollapsibleReasoning(
    String reasoning,
    bool isDark,
    bool isStreaming,
  );
  Widget _buildStreamingBubble(bool isDark);
  Widget _buildInputArea(ColorScheme colorScheme);
  Widget _buildIconButtonOption({
    required IconData icon,
    required bool isSelected,
    required String tooltip,
    required Function(bool) onTap,
  });
}
