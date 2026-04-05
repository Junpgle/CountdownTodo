import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import '../models/chat_message.dart';
import '../services/llm_service.dart';
import '../services/chat_storage_service.dart';
import '../screens/settings/llm_config_page.dart';

class TodoChatScreen extends StatefulWidget {
  final String username;
  final List<Map<String, dynamic>> todos;

  const TodoChatScreen({
    super.key,
    required this.username,
    required this.todos,
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
  List<String> _suggestions = [];
  String _customPrompt = '';
  bool _promptEnabled = true;
  String _chatModel = '';
  String _chatApiKey = '';
  String _chatApiUrl = '';

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadPromptSettings();
    _loadChatConfig();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final history = await ChatStorageService.loadHistory();
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
    if (mounted) {
      setState(() {
        if (config != null) {
          _chatModel = config['model'] ?? '';
          _chatApiKey = config['apiKey'] ?? '';
          _chatApiUrl = config['apiUrl'] ?? '';
        }
      });
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
    final todoList = widget.todos.map((t) {
      final title = t['title'] ?? '';
      final remark = t['remark'] ?? '';
      final startTime = t['startTime'] ?? '';
      final endTime = t['endTime'] ?? '';
      final isAllDay = t['isAllDay'] ?? false;
      final recurrence = t['recurrence'] ?? 'none';
      return '- 标题: $title${remark.isNotEmpty ? ' | 备注: $remark' : ''}${startTime.isNotEmpty ? ' | 开始: $startTime' : ''}${endTime.isNotEmpty ? ' | 结束: $endTime' : ''} | 全天: $isAllDay | 循环: $recurrence';
    }).join('\n');

    final now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    String prompt = _customPrompt;
    if (prompt.isEmpty) {
      prompt = ChatStorageService.defaultPrompt;
    }

    return prompt
        .replaceAll('{now}', now)
        .replaceAll('{todos}', todoList.isEmpty ? '暂无待办' : todoList);
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

    if (apiUrl.isEmpty) {
      apiUrl = 'https://open.bigmodel.cn/api/paas/v4/chat/completions';
    }

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
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      };

      final List<Map<String, String>> apiMessages = [
        {'role': 'system', 'content': _buildSystemPrompt()},
      ];

      for (final msg in _messages) {
        apiMessages.add({
          'role': msg.role == ChatRole.user ? 'user' : 'assistant',
          'content': msg.content,
        });
      }

      final body = jsonEncode({
        'model': model,
        'messages': apiMessages,
        'temperature': 0.7,
        'max_tokens': 2000,
        'stream': true,
      });

      final client = http.Client();
      final request = http.Request('POST', Uri.parse(apiUrl));
      request.headers.addAll(headers);
      request.body = body;

      final streamedResponse = await client.send(request).timeout(
            const Duration(seconds: 60),
          );

      if (streamedResponse.statusCode != 200) {
        throw Exception('请求失败: ${streamedResponse.statusCode}');
      }

      String fullContent = '';
      await for (final chunk in streamedResponse.stream.transform(
        utf8.decoder,
      )) {
        final lines = chunk.split('\n');
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || !trimmed.startsWith('data:')) continue;
          final data = trimmed.substring(5).trim();
          if (data == '[DONE]') continue;

          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final choices = json['choices'] as List?;
            if (choices != null && choices.isNotEmpty) {
              final delta = choices[0]['delta'] as Map<String, dynamic>?;
              final content = delta?['content'] as String?;
              if (content != null && content.isNotEmpty) {
                fullContent += content;
                if (mounted) {
                  setState(() {
                    _streamingContent = fullContent;
                  });
                  _scrollToBottom();
                }
              }
            }
          } catch (_) {}
        }
      }

      client.close();

      if (fullContent.isEmpty) {
        throw Exception('未收到有效回复');
      }

      final assistantMsg = ChatMessage(
        role: ChatRole.assistant,
        content: fullContent,
      );

      setState(() {
        _messages.add(assistantMsg);
        _streamingContent = '';
        _isLoading = false;
      });
      await ChatStorageService.addMessage(assistantMsg);
      _scrollToBottom();
      _generateSuggestions(assistantMsg.content);
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
                if (mounted) Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _showPromptPreview(String prompt, bool enabled) {
    final todoList = widget.todos.map((t) {
      final title = t['title'] ?? '';
      final remark = t['remark'] ?? '';
      final startTime = t['startTime'] ?? '';
      final endTime = t['endTime'] ?? '';
      final isAllDay = t['isAllDay'] ?? false;
      final recurrence = t['recurrence'] ?? 'none';
      return '- 标题: $title${remark.isNotEmpty ? ' | 备注: $remark' : ''}${startTime.isNotEmpty ? ' | 开始: $startTime' : ''}${endTime.isNotEmpty ? ' | 结束: $endTime' : ''} | 全天: $isAllDay | 循环: $recurrence';
    }).join('\n');

    final now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    String resolvedPrompt = prompt;
    if (resolvedPrompt.isEmpty) {
      resolvedPrompt = ChatStorageService.defaultPrompt;
    }
    resolvedPrompt = resolvedPrompt
        .replaceAll('{now}', now)
        .replaceAll('{todos}', todoList.isEmpty ? '暂无待办' : todoList);

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
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_toy_outlined),
            SizedBox(width: 8),
            Text('AI待办助手'),
          ],
        ),
        actions: [
          _buildModelSelector(),
          IconButton(
            icon: const Icon(Icons.tune_outlined),
            onPressed: _showPromptSettings,
            tooltip: '提示词设置',
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _clearHistory,
            tooltip: '清空聊天记录',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.smart_toy_outlined,
                          size: 64,
                          color: colorScheme.primary.withOpacity(0.5),
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
                            color: colorScheme.onSurface.withOpacity(0.6),
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
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: _messages.length + (_isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_isLoading && index == _messages.length) {
                        return _buildStreamingBubble(isDark);
                      }
                      final msg = _messages[index];
                      return _buildMessageBubble(msg, isDark);
                    },
                  ),
          ),
          if (_suggestions.isNotEmpty && !_isLoading)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
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
                      color: colorScheme.onSurface.withOpacity(0.5),
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
            ),
          _buildInputArea(colorScheme),
        ],
      ),
    );
  }

  Widget _buildModelSelector() {
    String displayName = _chatModel.isNotEmpty ? _chatModel : '默认模型';

    return PopupMenuButton<String>(
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.model_training_outlined,
            size: 20,
            color: _chatModel.isNotEmpty
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          ),
          const SizedBox(width: 2),
          Text(
            displayName,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _chatModel.isNotEmpty
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
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
                  if (mounted) Navigator.pop(ctx);
                },
                child: const Text('清除'),
              ),
            FilledButton(
              onPressed: useCustom
                  ? () async {
                      if (modelCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请输入模型名称')),
                        );
                        return;
                      }
                      if (apiKeyCtrl.text.trim().isEmpty) {
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
                      if (mounted) Navigator.pop(ctx);
                    }
                  : null,
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateSuggestions(String assistantResponse) async {
    setState(() => _suggestions = []);

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
          setState(() => _suggestions = []);
          return;
        }
      }

      if (apiUrl.isEmpty) {
        apiUrl = 'https://open.bigmodel.cn/api/paas/v4/chat/completions';
      }

      final now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
      final todoList = widget.todos.map((t) {
        return '- ${t['title'] ?? ''}';
      }).join('\n');

      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      };

      final body = jsonEncode({
        'model': model,
        'messages': [
          {
            'role': 'system',
            'content': '''你是一个智能待办助手。根据用户当前的待办清单和最近的对话内容，生成3-4个简短的后续问题或建议。

要求：
1. 只返回JSON数组，格式如：["建议1", "建议2", "建议3"]
2. 每个建议不超过15个字
3. 建议要具体、实用、与待办相关
4. 不要包含任何额外文字，只返回JSON数组''',
          },
          {
            'role': 'user',
            'content': '''当前时间：$now
当前待办：
$todoList

AI最近回复：
${assistantResponse.substring(0, assistantResponse.length > 500 ? 500 : assistantResponse.length)}

请生成4个后续建议问题。''',
          },
        ],
        'temperature': 0.8,
        'max_tokens': 200,
      });

      final response = await http
          .post(
            Uri.parse(apiUrl),
            headers: headers,
            body: body,
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final choices = data['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final content = choices[0]['message']['content'] as String;
          final suggestions = _extractSuggestions(content);
          if (mounted) {
            setState(() => _suggestions = suggestions);
          }
          return;
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _suggestions = _getDefaultSuggestions());
    }
  }

  List<String> _extractSuggestions(String content) {
    try {
      final trimmed = content.trim();
      int start = trimmed.indexOf('[');
      int end = trimmed.lastIndexOf(']');
      if (start != -1 && end != -1 && end > start) {
        final jsonStr = trimmed.substring(start, end + 1);
        final list = jsonDecode(jsonStr) as List;
        return list
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return _getDefaultSuggestions();
  }

  List<String> _getDefaultSuggestions() {
    return [
      '帮我排一下先后顺序',
      '哪些待办最紧急？',
      '今天应该先做什么？',
      '如何高效完成这些待办？',
    ];
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
                            .withOpacity(isDark ? 0.3 : 0.7),
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
                const SizedBox(height: 4),
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.4),
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withOpacity(isDark ? 0.3 : 0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _streamingContent.isNotEmpty
                      ? MarkdownBody(
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
                        )
                      : Text(
                          '思考中...',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.5),
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
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
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
      ),
    );
  }
}
