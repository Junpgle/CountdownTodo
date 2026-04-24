import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../storage_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../services/llm_service.dart';
import '../services/notification_service.dart';

class ParsedTodoResult {
  final String title;
  final String? remark;
  final bool isAllDay;
  final DateTime? startTime;
  final DateTime? endTime;
  final RecurrenceType recurrence;
  final int? customIntervalDays;
  final String? originalText;
  final int? reminderMinutes;
  final String? groupId;
  final int collabType;

  final String? teamUuid;
  final String? teamName;
  final DateTime? recurrenceEndDate;

  ParsedTodoResult({
    required this.title,
    this.remark,
    this.isAllDay = false,
    this.startTime,
    this.endTime,
    this.recurrence = RecurrenceType.none,
    this.customIntervalDays,
    this.originalText,
    this.reminderMinutes,
    this.groupId,
    this.collabType = 0,
    this.teamUuid,
    this.teamName,
    this.recurrenceEndDate,
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'remark': remark,
      'isAllDay': isAllDay,
      'startTime': startTime?.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'recurrence': recurrence.name,
      'customIntervalDays': customIntervalDays,
      'originalText': originalText,
      'reminderMinutes': reminderMinutes,
      'groupId': groupId,
      'collab_type': collabType,
      'team_uuid': teamUuid,
      'team_name': teamName,
      'recurrence_end_date': recurrenceEndDate?.toIso8601String(),
    };
  }
}

class TodoConfirmScreen extends StatefulWidget {
  final List<Map<String, dynamic>> llmResults;
  final String? imagePath;
  final String? originalText;
  final Function(List<Map<String, dynamic>>)? onConfirm;

  final String? initialTeamUuid;
  final String? initialTeamName;

  const TodoConfirmScreen({
    super.key,
    required this.llmResults,
    this.imagePath,
    this.originalText,
    this.onConfirm,
    this.initialTeamUuid,
    this.initialTeamName,
  });

  @override
  State<TodoConfirmScreen> createState() => _TodoConfirmScreenState();
}

class _TodoConfirmScreenState extends State<TodoConfirmScreen> {
  late List<ParsedTodoResult> _allTodos;
  final List<Map<String, dynamic>> _confirmedTodos = [];
  int _currentIndex = 0;
  bool _isRetrying = false;
  String? _retryStatus;
  List<TodoGroup> _todoGroups = [];
  Map<String, int> _categoryReminderDefaults = {};
  String? _username;

  @override
  void initState() {
    super.initState();
    _allTodos = _parseResults(widget.llmResults);
    _loadTodoMetadata();
  }

  Future<void> _loadTodoMetadata() async {
    final username = await StorageService.getLoginSession();
    if (username != null) {
      final groups = await StorageService.getTodoGroups(username);
      final defaults =
          await StorageService.getCategoryReminderMinutes(username);
      setState(() {
        _username = username;
        _todoGroups = groups.where((g) => !g.isDeleted).toList();
        _categoryReminderDefaults = defaults;
      });
    }
  }

  List<ParsedTodoResult> _parseResults(List<Map<String, dynamic>> results) {
    return results.map((result) {
      return ParsedTodoResult(
        title: result['title'] ?? '',
        remark: result['remark'],
        isAllDay: result['isAllDay'] ?? false,
        startTime: result['startTime'] != null
            ? DateTime.tryParse(result['startTime'])
            : null,
        endTime: result['endTime'] != null
            ? DateTime.tryParse(result['endTime'])
            : null,
        recurrence: _parseRecurrenceType(result['recurrence']),
        customIntervalDays: result['customIntervalDays'],
        originalText: widget.originalText, // 📄 传入原始文本
        reminderMinutes: result['reminderMinutes'],
        groupId: result['groupId'],
        collabType: result['collab_type'] ?? 0,
        teamUuid: widget.initialTeamUuid,
        teamName: widget.initialTeamName,
        recurrenceEndDate: result['recurrence_end_date'] != null
            ? DateTime.tryParse(result['recurrence_end_date'])
            : null,
      );
    }).toList();
  }

  RecurrenceType _parseRecurrenceType(String? type) {
    switch (type) {
      case 'daily':
        return RecurrenceType.daily;
      case 'weekly':
        return RecurrenceType.weekly;
      case 'monthly':
        return RecurrenceType.monthly;
      case 'yearly':
        return RecurrenceType.yearly;
      case 'customDays':
        return RecurrenceType.customDays;
      default:
        return RecurrenceType.none;
    }
  }

  Future<void> _retryRecognition() async {
    final imagePath = widget.imagePath;
    if (imagePath == null) return;

    setState(() {
      _isRetrying = true;
      _retryStatus = '正在重试...';
    });

    try {
      final maxRetries = await StorageService.getLLMRetryCount();
      final config = await LLMService.getConfig();

      if (config == null || !config.isConfigured) {
        setState(() {
          _isRetrying = false;
          _retryStatus = '需要配置大模型API';
        });
        return;
      }

      bool success = false;
      List<Map<String, dynamic>>? results;
      String? lastError;

      for (int attempt = 1; attempt <= maxRetries + 1; attempt++) {
        try {
          setState(() {
            _retryStatus = '第$attempt/${maxRetries + 1}次尝试...';
          });

          await NotificationService.showTodoRecognizeProgress(
            currentAttempt: attempt,
            maxAttempts: maxRetries + 1,
            status: '正在分析图片...',
          );

          results = await LLMService.parseTodoFromImage(imagePath)
              .timeout(const Duration(seconds: 90));

          success = true;
          break;
        } catch (e) {
          lastError = e.toString();
          debugPrint("重试第$attempt次失败: $e");

          if (attempt <= maxRetries) {
            await Future.delayed(Duration(seconds: 2 * attempt));
          }
        }
      }

      if (success && results != null && results.isNotEmpty) {
        setState(() {
          _allTodos = _parseResults(results!);
          _currentIndex = 0;
          _confirmedTodos.clear();
          _isRetrying = false;
          _retryStatus = null;
        });

        await NotificationService.showTodoRecognizeSuccess(
          todoCount: results.length,
        );
      } else {
        setState(() {
          _isRetrying = false;
          _retryStatus = '重试失败: ${lastError ?? "未知错误"}';
        });

        await NotificationService.showTodoRecognizeFailed(
          errorMsg: lastError ?? '未知错误',
        );
      }
    } catch (e) {
      setState(() {
        _isRetrying = false;
        _retryStatus = '重试失败: $e';
      });
    }
  }

  void _editCurrentTodo() {
    if (_currentIndex >= _allTodos.length) return;
    final todo = _allTodos[_currentIndex];
    final titleCtrl = TextEditingController(text: todo.title);
    final remarkCtrl = TextEditingController(text: todo.remark ?? '');
    bool isAllDay = todo.isAllDay;
    DateTime createdAt = todo.startTime ?? DateTime.now();
    DateTime? dueDate = todo.endTime;
    String? selectedGroupId = todo.groupId;
    int reminderMinutes = todo.reminderMinutes ?? 5;
    int collabType = todo.collabType;
    RecurrenceType recurrence = todo.recurrence;
    int? customDays = todo.customIntervalDays;
    DateTime? recurrenceEndDate = todo.recurrenceEndDate;
    final customDaysCtrl = TextEditingController(text: customDays?.toString() ?? '');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('编辑待办'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: InputDecoration(
                      labelText: '待办内容',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: remarkCtrl,
                    decoration: InputDecoration(
                      labelText: '备注 (可选)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    maxLines: 3,
                    minLines: 1,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('全天事件'),
                    value: isAllDay,
                    onChanged: (val) {
                      setDialogState(() => isAllDay = val);
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '开始时间: ${DateFormat(isAllDay ? 'yyyy-MM-dd' : 'yyyy-MM-dd HH:mm').format(createdAt)}',
                    ),
                    onTap: () async {
                      final pickedDate = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDate: createdAt,
                      );
                      if (pickedDate != null) {
                        if (isAllDay) {
                          setDialogState(() => createdAt = DateTime(
                                pickedDate.year,
                                pickedDate.month,
                                pickedDate.day,
                                0,
                                0,
                              ));
                        } else {
                          if (!context.mounted) return;
                          final pickedTime = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(createdAt),
                          );
                          if (pickedTime != null) {
                            setDialogState(() => createdAt = DateTime(
                                  pickedDate.year,
                                  pickedDate.month,
                                  pickedDate.day,
                                  pickedTime.hour,
                                  pickedTime.minute,
                                ));
                          }
                        }
                      }
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      dueDate == null
                          ? '设置截止时间 (可选)'
                          : '截止时间: ${DateFormat(isAllDay ? 'yyyy-MM-dd' : 'yyyy-MM-dd HH:mm').format(dueDate!)}',
                    ),
                    onTap: () async {
                      final pickedDate = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDate: dueDate ?? createdAt,
                      );
                      if (pickedDate != null) {
                        if (isAllDay) {
                          setDialogState(() => dueDate = DateTime(
                                pickedDate.year,
                                pickedDate.month,
                                pickedDate.day,
                                23,
                                59,
                              ));
                        } else {
                          if (!context.mounted) return;
                          final pickedTime = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(dueDate ??
                                createdAt.add(const Duration(hours: 1))),
                          );
                          if (pickedTime != null) {
                            setDialogState(() => dueDate = DateTime(
                                  pickedDate.year,
                                  pickedDate.month,
                                  pickedDate.day,
                                  pickedTime.hour,
                                  pickedTime.minute,
                                ));
                          }
                        }
                      }
                    },
                  ),
                  const Divider(),
                  DropdownButtonFormField<String?>(
                    initialValue: selectedGroupId,
                    decoration: InputDecoration(
                      labelText: '归类到文件夹 (可选)',
                      prefixIcon: const Icon(Icons.folder_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('不归类 (独立待办)'),
                      ),
                      ..._todoGroups.map((g) => DropdownMenuItem<String?>(
                            value: g.id,
                            child: Text(g.name),
                          )),
                    ],
                    onChanged: (val) {
                      setDialogState(() {
                        selectedGroupId = val;
                        if (val != null &&
                            _categoryReminderDefaults.containsKey(val)) {
                          reminderMinutes = _categoryReminderDefaults[val]!;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: reminderMinutes,
                    decoration: InputDecoration(
                      labelText: '温馨提醒 (提前量)',
                      prefixIcon: const Icon(Icons.notifications_active_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('准时提醒')),
                      DropdownMenuItem(value: 5, child: Text('提前 5 分钟')),
                      DropdownMenuItem(value: 10, child: Text('提前 10 分钟')),
                      DropdownMenuItem(value: 15, child: Text('提前 15 分钟')),
                      DropdownMenuItem(value: 30, child: Text('提前 30 分钟')),
                      DropdownMenuItem(value: 45, child: Text('提前 45 分钟')),
                      DropdownMenuItem(value: 60, child: Text('提前 1 小时')),
                      DropdownMenuItem(value: 120, child: Text('提前 2 小时')),
                      DropdownMenuItem(value: 1440, child: Text('提前 1 天')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => reminderMinutes = val);
                      }
                    },
                  ),
                  if (todo.teamUuid != null) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: collabType,
                      decoration: InputDecoration(
                        labelText: "团队协作方式",
                        prefixIcon: const Icon(Icons.hub_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text("共同协作 (共享进度)")),
                        DropdownMenuItem(value: 1, child: Text("各自独立完成")),
                      ],
                      onChanged: (val) {
                        if (val != null) setDialogState(() => collabType = val);
                      },
                    ),
                  ],
                  const Divider(),
                  DropdownButtonFormField<RecurrenceType>(
                    initialValue: recurrence,
                    decoration: InputDecoration(
                      labelText: '循环设置 (可选)',
                      prefixIcon: const Icon(Icons.replay_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: RecurrenceType.none, child: Text('不重复')),
                      DropdownMenuItem(value: RecurrenceType.daily, child: Text('每天重复')),
                      DropdownMenuItem(value: RecurrenceType.weekly, child: Text('每周重复')),
                      DropdownMenuItem(value: RecurrenceType.monthly, child: Text('每月重复')),
                      DropdownMenuItem(value: RecurrenceType.yearly, child: Text('每年重复')),
                      DropdownMenuItem(value: RecurrenceType.weekdays, child: Text('工作日')),
                      DropdownMenuItem(value: RecurrenceType.customDays, child: Text('间隔几天')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => recurrence = val);
                    },
                  ),
                  if (recurrence == RecurrenceType.customDays) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: customDaysCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '间隔天数',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onChanged: (val) => customDays = int.tryParse(val),
                    ),
                  ],
                  if (recurrence != RecurrenceType.none) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        recurrenceEndDate == null
                            ? '循环截止日期 (可选)'
                            : '循环截止: ${DateFormat('yyyy-MM-dd').format(recurrenceEndDate!)}',
                      ),
                      trailing: const Icon(Icons.event_busy, size: 20),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: recurrenceEndDate ?? DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setDialogState(() => recurrenceEndDate = picked);
                        }
                      },
                    ),
                  ],
                ],
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
                    _allTodos[_currentIndex] = ParsedTodoResult(
                      title: titleCtrl.text,
                      remark: remarkCtrl.text.isEmpty ? null : remarkCtrl.text,
                      isAllDay: isAllDay,
                      startTime: createdAt,
                      endTime: dueDate,
                      recurrence: recurrence,
                      customIntervalDays: customDays,
                      recurrenceEndDate: recurrenceEndDate,
                      reminderMinutes: reminderMinutes,
                      groupId: selectedGroupId,
                      collabType: collabType,
                      teamUuid: todo.teamUuid,
                      teamName: todo.teamName,
                    );
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmCurrentTodo() {
    if (_currentIndex >= _allTodos.length) return;
    _confirmedTodos.add(_allTodos[_currentIndex].toMap());
    _moveToNext();
  }

  void _skipCurrentTodo() {
    _moveToNext();
  }

  void _moveToNext() {
    if (_currentIndex < _allTodos.length - 1) {
      setState(() {
        _currentIndex++;
      });
    } else {
      _finishConfirm();
    }
  }

  Future<void> _finishConfirm() async {
    if (_confirmedTodos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有添加任何待办')),
      );
      Navigator.pop(context);
      return;
    }

    // 🚀 核心：移动图片到持久化目录
    String? persistentImagePath;
    if (widget.imagePath != null) {
      try {
        final imageFile = File(widget.imagePath!);
        if (await imageFile.exists()) {
          final appDir = await getApplicationSupportDirectory();
          final imageDir = Directory('${appDir.path}/analysis_images');
          if (!await imageDir.exists()) {
            await imageDir.create(recursive: true);
          }

          final fileName = '${DateTime.now().millisecondsSinceEpoch}_${p.basename(widget.imagePath!)}';
          final newPath = '${imageDir.path}/$fileName';
          await imageFile.copy(newPath);
          persistentImagePath = newPath;
          debugPrint('📸 图片已持久化到: $persistentImagePath');
        }
      } catch (e) {
        debugPrint('❌ 持久化图片失败: $e');
      }
    }

    // 将路径注入到所有待办中
    if (persistentImagePath != null) {
      for (var todo in _confirmedTodos) {
        todo['imagePath'] = persistentImagePath;
      }
    }

    if (widget.onConfirm != null) {
      widget.onConfirm!(_confirmedTodos);
    }
    Navigator.pop(context, _confirmedTodos);
  }

  @override
  Widget build(BuildContext context) {
    final imagePath = widget.imagePath;
    final imageFile = imagePath != null ? File(imagePath) : null;
    final hasImage = imageFile?.existsSync() ?? false;
    final bool hasMoreTodos = _currentIndex < _allTodos.length;
    final currentTodo = hasMoreTodos ? _allTodos[_currentIndex] : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(hasMoreTodos
            ? '确认待办 (${_currentIndex + 1}/${_allTodos.length})'
            : '确认完成'),
        actions: [
          if (_isRetrying)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (hasMoreTodos)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '重新识别',
              onPressed: _retryRecognition,
            ),
        ],
      ),
      body: Column(
        children: [
          // 图片预览（可折叠）
          if (hasImage)
            Container(
              height: 120,
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: imageFile != null
                    ? Image.file(
                        imageFile,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Icon(Icons.broken_image,
                                size: 48, color: Colors.grey),
                          );
                        },
                      )
                    : const Center(
                        child: Icon(Icons.broken_image,
                            size: 48, color: Colors.grey),
                      ),
              ),
            ),

          // 重试状态提示
          if (_retryStatus != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isRetrying
                      ? Colors.blue.shade50
                      : (_retryStatus!.contains('失败')
                          ? Colors.red.shade50
                          : Colors.orange.shade50),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    if (_isRetrying)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(
                        _retryStatus!.contains('失败')
                            ? Icons.error_outline
                            : Icons.info_outline,
                        size: 16,
                        color: _retryStatus!.contains('失败')
                            ? Colors.red
                            : Colors.orange,
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _retryStatus!,
                        style: TextStyle(
                          fontSize: 13,
                          color: _retryStatus!.contains('失败')
                              ? Colors.red
                              : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 当前待办卡片 或 完成页面
          Expanded(
            child: _allTodos.isEmpty
                ? _buildEmptyState()
                : hasMoreTodos
                    ? AnimatedSwitcher(
                        duration: const Duration(milliseconds: 350),
                        transitionBuilder: (child, animation) {
                          final slideAnimation = Tween<Offset>(
                            begin: const Offset(0.3, 0.0),
                            end: Offset.zero,
                          ).animate(CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                          ));
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: slideAnimation,
                              child: child,
                            ),
                          );
                        },
                        child: _buildCurrentTodoCard(currentTodo!),
                      )
                    : _buildCompletedState(),
          ),

          // 底部按钮
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: hasMoreTodos ? _buildConfirmButtons() : _buildDoneButton(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            '没有待办事项',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _isRetrying ? null : _retryRecognition,
            icon: const Icon(Icons.refresh),
            label: const Text('重新识别'),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentTodoCard(ParsedTodoResult todo) {
    return SingleChildScrollView(
      key: ValueKey(_currentIndex),
      padding: const EdgeInsets.all(16),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部标签
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '待办 ${_currentIndex + 1}/${_allTodos.length}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: _editCurrentTodo,
                    tooltip: '编辑',
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 标题
              Text(
                todo.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              // 备注
              if (todo.remark != null && todo.remark!.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    todo.remark!,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // 时间信息
              _buildTimeInfo(todo),

              // 已确认数量提示
              if (_confirmedTodos.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle,
                          size: 16, color: Colors.green.shade700),
                      const SizedBox(width: 8),
                      Text(
                        '已添加 ${_confirmedTodos.length} 个待办',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeInfo(ParsedTodoResult todo) {
    String timeText;
    IconData timeIcon;

    if (todo.isAllDay) {
      timeIcon = Icons.today;
      if (todo.startTime != null) {
        timeText = '全天 | ${DateFormat('yyyy-MM-dd').format(todo.startTime!)}';
      } else {
        timeText = '全天';
      }
    } else if (todo.startTime != null && todo.endTime != null) {
      timeIcon = Icons.schedule;
      timeText =
          '${DateFormat('MM-dd HH:mm').format(todo.startTime!)} - ${DateFormat('HH:mm').format(todo.endTime!)}';
    } else if (todo.startTime != null) {
      timeIcon = Icons.play_circle_outline;
      timeText = '开始: ${DateFormat('MM-dd HH:mm').format(todo.startTime!)}';
    } else if (todo.endTime != null) {
      timeIcon = Icons.flag_outlined;
      timeText = '截止: ${DateFormat('MM-dd HH:mm').format(todo.endTime!)}';
    } else {
      timeIcon = Icons.access_time;
      timeText = '未设置时间';
    }

    return Row(
      children: [
        Icon(timeIcon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Text(
          timeText,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildCompletedState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline,
              size: 80, color: Colors.green.shade400),
          const SizedBox(height: 16),
          Text(
            '确认完成',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '已添加 ${_confirmedTodos.length} 个待办',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmButtons() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 添加按钮
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isRetrying ? null : _confirmCurrentTodo,
            icon: const Icon(Icons.add),
            label: const Text('添加这个待办'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // 跳过按钮
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isRetrying ? null : _skipCurrentTodo,
                icon: const Icon(Icons.skip_next),
                label: const Text('跳过'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isRetrying
                    ? null
                    : () {
                        // 添加剩余全部
                        for (int i = _currentIndex; i < _allTodos.length; i++) {
                          _confirmedTodos.add(_allTodos[i].toMap());
                        }
                        _finishConfirm();
                      },
                icon: const Icon(Icons.done_all),
                label: const Text('全部添加'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDoneButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.check),
        label: const Text('完成'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}
