import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../models/ai_todo_action.dart';
import '../models/chat_message.dart';
import '../services/ai_action_parser.dart';
import '../services/ai_chat_service.dart';
import '../services/ai_todo_context_builder.dart';
import '../services/ai_todo_action_executor.dart';
import '../services/llm_service.dart';
import '../services/chat_storage_service.dart';
import '../screens/settings/llm_config_page.dart';
import '../storage_service.dart';

class TodoChatScreen extends StatefulWidget {
  final String username;
  final List<Map<String, dynamic>> todos;
  final List<TodoGroup> todoGroups;
  final List<CourseItem> courses;
  final List<TimeLogItem> timeLogs;
  final List<ConflictInfo> conflicts;
  final List<Team> teams;
  final Function(TodoItem)? onTodoInserted;
  final Function(List<TodoItem>)? onTodosBatchInserted;
  final Function(List<TodoItem>)? onTodosUpdated;
  final Function(List<TodoItem> inserted, List<TodoItem> updated)?
      onTodosBatchAction;

  const TodoChatScreen({
    super.key,
    required this.username,
    required this.todos,
    this.todoGroups = const [],
    this.courses = const [],
    this.timeLogs = const [],
    this.conflicts = const [],
    this.teams = const [],
    this.onTodoInserted,
    this.onTodosBatchInserted,
    this.onTodosUpdated,
    this.onTodosBatchAction,
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
  String _globalModelName = '';
  List<ChatSession> _sessions = [];
  bool _smartContext = true;
  String? _activeSessionId;
  Map<String, int> _categoryReminderDefaults = {};

  // 🚀 宽屏适配相关
  bool _sidebarVisible = true;
  bool get _isWide => MediaQuery.of(context).size.width >= 900;

  @override
  void initState() {
    super.initState();
    _initSessions();
    _loadPromptSettings();
    _loadChatConfig();
    _loadDeepThinking();
    _loadCategoryDefaults();
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

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
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
      _scrollToBottom();
    }
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
        }
        _globalModelName = globalConfig?.model ?? '';
      });
    }
  }

  Future<void> _loadDeepThinking() async {
    final enabled = await ChatStorageService.isDeepThinkingEnabled();
    if (mounted) {
      setState(() => _deepThinking = enabled);
    }
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
    return AiTodoContextBuilder.buildSystemPrompt(
      customPrompt: _customPrompt,
      promptEnabled: _promptEnabled,
      todos: widget.todos,
      todoGroups: widget.todoGroups,
    );
  }

  static const int _maxContextMessages = 15;

  List<Map<String, String>> _buildApiMessages() {
    final List<Map<String, String>> apiMessages = [
      {'role': 'system', 'content': _buildSystemPrompt()},
    ];

    if (_messages.length <= _maxContextMessages) {
      for (final msg in _messages) {
        apiMessages.add({
          'role': msg.role == ChatRole.user ? 'user' : 'assistant',
          'content': msg.content,
        });
      }
    } else {
      final firstUserMsg = _messages.firstWhere(
        (m) => m.role == ChatRole.user,
        orElse: () => _messages.first,
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
      final startIndex = _messages.length - recentCount;
      final recentMessages =
          _messages.sublist(startIndex > 0 ? startIndex : 0);
      for (final msg in recentMessages) {
        if (msg.content == firstUserMsg.content) continue;
        apiMessages.add({
          'role': msg.role == ChatRole.user ? 'user' : 'assistant',
          'content': msg.content,
        });
      }
    }

    _injectContext(apiMessages);
    return apiMessages;
  }

  /// 根据最后一条用户消息的关键词，按需注入课程/时间日志/冲突/团队上下文。
  void _injectContext(List<Map<String, String>> apiMessages) {
    if (!_smartContext) return;
    // 找到最后一条 user 消息
    int lastUserIdx = -1;
    for (int i = apiMessages.length - 1; i >= 0; i--) {
      if (apiMessages[i]['role'] == 'user') {
        lastUserIdx = i;
        break;
      }
    }
    if (lastUserIdx == -1) return;

    final userText = apiMessages[lastUserIdx]['content'] ?? '';
    final injection = AiTodoContextBuilder.buildContextInjection(
      userMessage: userText,
      courses: widget.courses,
      timeLogs: widget.timeLogs,
      conflicts: widget.conflicts,
      teams: widget.teams,
    );
    if (injection != null) {
      apiMessages[lastUserIdx] = {
        'role': 'user',
        'content': '$injection\n\n$userText',
      };
    }
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

    if (model.isEmpty || apiKey.isEmpty) {
      final globalConfig = await LLMService.getConfig();
      if (globalConfig != null && globalConfig.isConfigured) {
        model = globalConfig.model;
        apiKey = globalConfig.apiKey;
        apiUrl = globalConfig.apiUrl;
      } else {
        if (!mounted) return;
        final goToSettings = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('未配置大模型'),
            content: const Text('使用AI助手需要先配置API地址和密钥，是否前往设置？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('去配置'),
              ),
            ],
          ),
        );
        if (goToSettings == true && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LLMConfigPage()),
          );
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
          reasoningContent: reasoningContent,
          todoActions: todoActions.isNotEmpty ? todoActions : null,
        );

        _messages.add(assistantMsg);
        _streamingContent = '';
        _streamingReasoning = '';
        _isLoading = false;
        _suggestions = inlineSuggestions.isNotEmpty
            ? inlineSuggestions
            : _getDefaultSuggestions();
        ChatStorageService.addMessage(assistantMsg);
      });
      _scrollToBottom();
      _generateSessionTitle();
    } catch (e) {
      setState(() {
        _streamingContent = '';
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI回复失败: $e')),
        );
      }
    }
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
      appBar: _buildResponsiveAppBar(isDark, colorScheme),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 900) {
            return _buildWideLayout(isDark, colorScheme);
          }
          return _buildMobileLayout(isDark, colorScheme);
        },
      ),
    );
  }

  PreferredSizeWidget _buildResponsiveAppBar(bool isDark, ColorScheme colorScheme) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.pop(context),
        tooltip: '返回',
      ),
      title: Text(
        _getCurrentSessionTitle(),
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        if (_isWide)
          IconButton(
            icon: Icon(_sidebarVisible ? Icons.menu_open : Icons.menu),
            onPressed: () => setState(() => _sidebarVisible = !_sidebarVisible),
            tooltip: _sidebarVisible ? '隐藏侧边栏' : '显示侧边栏',
          ),
        IconButton(
          icon: const Icon(Icons.add_comment_outlined),
          onPressed: _newSession,
          tooltip: '新建对话',
        ),
        if (!_isWide)
          IconButton(
            icon: const Icon(Icons.history_outlined),
            onPressed: _showHistorySidebar,
            tooltip: '历史对话',
          ),
        IconButton(
          icon: const Icon(Icons.tune_outlined),
          onPressed: _showPromptSettings,
          tooltip: '提示词设置',
        ),
      ],
    );
  }

  Widget _buildWideLayout(bool isDark, ColorScheme colorScheme) {
    return Row(
      children: [
        if (_sidebarVisible)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 280,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: _buildHistorySidebarContent(context, isWideMode: true),
          ),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: _buildMessageList(isDark, colorScheme),
                  ),
                ),
              ),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    children: [
                      if (_suggestions.isNotEmpty && !_isLoading)
                        _buildSuggestionsArea(colorScheme),
                      _buildInputArea(colorScheme),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(bool isDark, ColorScheme colorScheme) {
    return Column(
      children: [
        Expanded(child: _buildMessageList(isDark, colorScheme)),
        if (_suggestions.isNotEmpty && !_isLoading)
          _buildSuggestionsArea(colorScheme),
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
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      itemCount: _messages.length + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (_isLoading && index == _messages.length) {
          return _buildStreamingBubble(isDark);
        }
        final msg = _messages[index];
        return _buildMessageBubble(msg, isDark);
      },
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.smart_toy_outlined,
            size: 64,
            color: colorScheme.primary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '你好！我是AI待办助手',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '你可以问我任何问题关于你的待办',
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _getDefaultSuggestions()
                .map(_buildQuickQuestion)
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionsArea(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '💡 你可以继续问我：',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _suggestions.map(_buildQuickQuestion).toList(),
          ),
        ],
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

  Widget _buildHistorySidebarContent(BuildContext context, {required bool isWideMode}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              const Text(
                '历史对话',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_sweep_outlined,
                    size: 20, color: Colors.grey),
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
        const Divider(height: 1),
        Expanded(
          child: _sessions.isEmpty
              ? const Center(child: Text('暂无历史对话'))
              : ListView.builder(
                  itemCount: _sessions.length,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemBuilder: (context, index) {
                    final session = _sessions[index];
                    final isActive = session.id == _activeSessionId;
                    return ListTile(
                      dense: isWideMode,
                      leading: Icon(
                        isActive ? Icons.chat_bubble : Icons.chat_bubble_outline,
                        size: 20,
                        color: isActive
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      title: Text(
                        session.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isActive ? FontWeight.bold : null,
                          color: isActive
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                      ),
                      subtitle: Text(
                        DateFormat('MM/dd HH:mm').format(
                          session.updatedAt,
                        ),
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () {
                          if (!isWideMode) Navigator.pop(context);
                          _deleteSession(session.id);
                        },
                        tooltip: '删除对话',
                      ),
                      selected: isActive,
                      selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                      onTap: () {
                        if (!isWideMode) Navigator.pop(context);
                        _switchSession(session.id);
                      },
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
        _suggestions = _getDefaultSuggestions();
      });
      // 关闭侧边栏
      Navigator.pop(sidebarCtx);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已清空所有历史对话')),
      );
    }
  }

  Widget _buildModelSelector() {
    String label = _chatModel.isNotEmpty
        ? _chatModel
        : '全局: ${_globalModelName.isNotEmpty ? _globalModelName : '未配置'}';

    return PopupMenuButton<String>(
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.model_training_outlined,
            size: 20,
            color: _chatModel.isNotEmpty
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
          ),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _chatModel.isNotEmpty
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
            ),
          ),
          const Icon(Icons.arrow_drop_down, size: 20),
        ],
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
              const Text('使用全局配置'),
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
        } else if (value == '__global__') {
          _useGlobalModel();
        }
      },
    );
  }

  Future<void> _useGlobalModel() async {
    await ChatStorageService.clearChatConfig();
    if (mounted) {
      setState(() {
        _chatModel = '';
        _chatApiKey = '';
        _chatApiUrl = '';
      });
    }
  }

  Future<void> _showModelConfig() async {
    final modelCtrl = TextEditingController(text: _chatModel);
    final apiKeyCtrl = TextEditingController(text: _chatApiKey);
    final apiUrlCtrl = TextEditingController(
      text: _chatApiUrl.isEmpty
          ? 'https://open.bigmodel.cn/api/paas/v4/chat/completions'
          : _chatApiUrl,
    );
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
                    subtitle: const Text('关闭后将使用全局大模型配置'),
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
                  if (mounted) {
                    setState(() {
                      _chatModel = '';
                      _chatApiKey = '';
                      _chatApiUrl = '';
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
                      );
                      if (mounted) {
                        setState(() {
                          _chatModel = modelCtrl.text.trim();
                          _chatApiKey = apiKeyCtrl.text.trim();
                          _chatApiUrl = apiUrlCtrl.text.trim();
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

  List<String> _getDefaultSuggestions() {
    return [
      '帮我规划今天的待办',
      '明天有什么课？',
      '我今天专注了多久？',
      '帮我整理一下待办分类',
      '哪些待办最紧急？',
    ];
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
    bool allAdded = msg.todoActions!.every((t) => t.isAdded);
    if (allAdded) return const SizedBox.shrink();
    final hasExistingMutations =
        msg.todoActions?.any((t) => t.mutatesExistingTodo) == true;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .primaryContainer
              .withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  Icon(
                    Icons.add_task_outlined,
                    color: Theme.of(context).colorScheme.primary,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    hasExistingMutations ? '建议整理待办' : '建议添加待办',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            ...msg.todoActions!.asMap().entries.map((entry) {
              final todo = entry.value;
              if (todo.isAdded) return const SizedBox.shrink();

              final isSelected = todo.isSelected;
              final currentGroupId = todo.groupId;
              final startTime = todo.startTime;
              final dueDate = todo.dueDate;
              final isAllDay = todo.isAllDay;
              final recurrence = todo.recurrence;
              final timeStr =
                  _formatTodoTimeRange(startTime, dueDate, isAllDay);

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[850] : Colors.white70,
                  borderRadius: BorderRadius.circular(8),
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
                                        color:
                                            Colors.grey.withValues(alpha: 0.8),
                                        fontStyle: FontStyle.italic),
                                  ),
                                ),
                            ],
                          ),
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
                                          style: const TextStyle(fontSize: 11),
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
                    (t) => t.isSelected && !t.isAdded,
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
                        '执行所选操作 (${msg.todoActions!.where((t) => t.isSelected && !t.isAdded).length})',
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
        color = Colors.blue;
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
      case AiTodoActionType.splitTodo:
        color = Colors.indigo;
        label = '拆分';
        break;
      case AiTodoActionType.mergeTodos:
        color = Colors.indigo;
        label = '合并';
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
      case AiTodoActionType.splitTodo:
        return action.sourceTodoIds.isEmpty
            ? '拆分为子任务'
            : '从 [${action.sourceTodoIds.join(', ')}] 拆分';
      case AiTodoActionType.mergeTodos:
        return action.sourceTodoIds.isEmpty
            ? '合并为新待办'
            : '合并 [${action.sourceTodoIds.join(', ')}]';
      case AiTodoActionType.createTodo:
      case AiTodoActionType.unknown:
        return '';
    }
  }

  Widget _buildChangeSummary(AiTodoAction action) {
    if (!action.mutatesExistingTodo) return const SizedBox.shrink();
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
      case AiTodoActionType.createTodo:
      case AiTodoActionType.updateTodo:
      case AiTodoActionType.completeTodo:
      case AiTodoActionType.rescheduleTodo:
      case AiTodoActionType.bulkRescheduleTodo:
      case AiTodoActionType.categorizeTodo:
      case AiTodoActionType.planTodos:
      case AiTodoActionType.unknown:
        return '';
    }
  }

  Future<void> _saveHistorySilently() async {
    await ChatStorageService.saveHistory(_messages, _activeSessionId);
  }

  void _addTodosForMessage(ChatMessage msg) {
    if (msg.todoActions == null) return;

    final result = AiTodoActionExecutor.execute(
      actions: msg.todoActions!,
      existingTodos: widget.todos,
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

      setState(() {});
      _saveHistorySilently();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '已执行所选操作 (新待办: ${result.newTodos.length}, 整理: ${result.updatedTodos.length})')),
      );
    }
  }

  Widget _buildQuickQuestion(String text) {
    return ActionChip(
      label: Text(text),
      onPressed: () {
        _inputCtrl.text = text;
        _sendMessage();
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage msg, bool isDark) {
    final isUser = msg.role == ChatRole.user;
    final timeStr = DateFormat('HH:mm').format(msg.timestamp);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.smart_toy_outlined,
                size: 18,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
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
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isUser
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: isDark ? 0.3 : 0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: isUser
                      ? Text(
                          msg.content,
                          style: TextStyle(
                            color: isUser
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.onSurface,
                            fontSize: 15,
                          ),
                        )
                      : MarkdownBody(
                          data: msg.content,
                          styleSheet: MarkdownStyleSheet(
                            p: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 15,
                            ),
                            strong: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                            ),
                            listBullet: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 15,
                            ),
                            code: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                              fontSize: 14,
                            ),
                          ),
                          selectable: true,
                        ),
                ),
                if (msg.todoActions != null && msg.todoActions!.isNotEmpty)
                  _buildMessageTodoActions(msg, isDark),
                const SizedBox(height: 4),
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 8),
          if (isUser)
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.person_outline,
                size: 18,
                color: Colors.white,
              ),
            ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
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
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: isDark ? 0.3 : 0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: MarkdownBody(
                      data: _streamingContent,
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 15,
                        ),
                        strong: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                        listBullet: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 15,
                        ),
                        code: TextStyle(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          backgroundColor:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                          fontSize: 14,
                        ),
                      ),
                      selectable: true,
                    ),
                  )
                else if (_streamingReasoning.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: isDark ? 0.3 : 0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '思考中...',
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5),
                        fontSize: 15,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputCtrl,
                    maxLines: 4,
                    minLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: '输入你的问题...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  onPressed: _isLoading ? null : _sendMessage,
                  style: IconButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    shape: const CircleBorder(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _buildModelSelector(),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                  onPressed: _clearHistory,
                  tooltip: '清空当前对话记录',
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 2),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  FilterChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.psychology_outlined,
                          size: 16,
                          color: _deepThinking
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '深度思考',
                          style: TextStyle(
                            fontSize: 12,
                            color: _deepThinking
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                    selected: _deepThinking,
                    onSelected: (val) async {
                      setState(() => _deepThinking = val);
                      await ChatStorageService.setDeepThinkingEnabled(val);
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _smartContext
                              ? Icons.auto_awesome
                              : Icons.auto_awesome_outlined,
                          size: 16,
                          color: _smartContext
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '智能上下文',
                          style: TextStyle(
                            fontSize: 12,
                            color: _smartContext
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                    selected: _smartContext,
                    onSelected: (val) {
                      setState(() => _smartContext = val);
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
    return Container(
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
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 20,
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
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
        ],
      ),
    );
  }
}
