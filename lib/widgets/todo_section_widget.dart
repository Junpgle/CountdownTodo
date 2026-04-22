import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import '../services/api_service.dart';
import '../storage_service.dart';
import '../screens/historical_todos_screen.dart';
import '../services/todo_parser_service.dart';
import '../services/llm_service.dart';
import '../screens/home_settings_screen.dart';
import '../screens/add_todo_screen.dart';
import '../screens/todo_chat_screen.dart';
import 'home_sections.dart';
import 'todo_group_widget.dart';
import '../utils/page_transitions.dart';
import '../screens/folder_manage_screen.dart';
import '../services/pomodoro_sync_service.dart';

class TodoSectionWidget extends StatefulWidget {
  final List<TodoItem> todos;
  final String username;
  final bool isLight;
  final Function(List<TodoItem>) onTodosChanged;
  final VoidCallback onRefreshRequested;
  final List<TodoGroup> todoGroups;
  final Function(List<TodoGroup>) onGroupsChanged;

  /// 大模型识别成功后的回调，用于导航到确认页面
  final Function(List<Map<String, dynamic>>, String?, String?, String?, String?)?
      onLLMResultsParsed; // 🚀 参数：Results, imagePath, originalText, teamUuid, teamName

  final Function(String?, String?)? onTeamChanged; // 🚀 传参：ID, Name

  const TodoSectionWidget({
    super.key,
    required this.todos,
    required this.username,
    required this.isLight,
    required this.onTodosChanged,
    required this.onRefreshRequested,
    this.todoGroups = const [],
    this.onGroupsChanged = _defaultOnGroupsChanged,
    this.onLLMResultsParsed,
    this.onTeamChanged,
    this.initialSelectedTeamUuid,
  });

  final String? initialSelectedTeamUuid;

  static void _defaultOnGroupsChanged(List<TodoGroup> _) {}

  @override
  State<TodoSectionWidget> createState() => TodoSectionWidgetState();
}

class TodoSectionWidgetState extends State<TodoSectionWidget>
    with TickerProviderStateMixin {
  bool _isWholeListExpanded = true;
  bool _isTodayExpanded = true;
  bool _isTodayManuallyExpanded = false;
  bool _isPastTodosExpanded = false;
  bool _isFutureExpanded = true;
  bool _hasInitializedExpansion = false;

  final Map<String, GlobalKey> _todoCardKeys = {};
  final Map<String, Key> _todoDismissKeys = {};
  final Map<String, AnimationController> _completingAnimations = {};
  final Map<String, bool> _isCompleting = {};
  bool _inlineFolders = true;
  final Set<String> _animatedTodoIds = {};

  String? _selectedSubTeamUuid; // 🚀 内部视口：当前选择的团队 UUID
  Map<String, String> _teamRoles = {}; // 🚀 缓存团队 ID -> 角色 (admin/member)

  @override
  void initState() {
    super.initState();
    _selectedSubTeamUuid = widget.initialSelectedTeamUuid;
    _loadSettings();
    _fetchTeamRoles(); // 🚀 获取角色
  }

  Future<void> _fetchTeamRoles() async {
    try {
      final teams = await ApiService.fetchTeams();
      if (mounted) {
        setState(() {
          for (var t in teams) {
            final uuid = t['uuid']?.toString();
            final role = (t['role'] == 0 || t['user_role'] == 0) ? 'admin' : 'member';
            if (uuid != null) _teamRoles[uuid] = role;
          }
        });
      }
    } catch (e) {
      debugPrint("获取团队角色失败: $e");
    }
  }

  Future<void> _loadSettings() async {
    final inline = await StorageService.getTodoFoldersInline();
    if (mounted) {
      setState(() {
        _inlineFolders = inline;
      });
    }
  }

  @override
  void dispose() {
    for (final controller in _completingAnimations.values) {
      controller.dispose();
    }
    super.dispose();
  }

  GlobalKey _getTodoCardKey(String todoId) {
    return _todoCardKeys.putIfAbsent(todoId, () => GlobalKey());
  }

  Key _getTodoDismissKey(String idPrefix, String todoId) {
    String mapKey = '${idPrefix}_$todoId';
    _todoDismissKeys.putIfAbsent(mapKey, () => UniqueKey());
    return _todoDismissKeys[mapKey]!;
  }

  @override
  void didUpdateWidget(TodoSectionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_hasInitializedExpansion && widget.todos.isNotEmpty) {
      _isTodayExpanded = !widget.todos
          .where((t) => !_isHistoricalTodo(t))
          .every((t) => t.isDone);
      _hasInitializedExpansion = true;
    }
  }

  bool _isHistoricalTodo(TodoItem t) {
    if (!t.isDone) return false;
    DateTime today = DateTime.now();
    today = DateTime(today.year, today.month, today.day);
    if (t.dueDate != null) {
      DateTime d = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
      return d.isBefore(today);
    } else {
      DateTime cDate = DateTime.fromMillisecondsSinceEpoch(
        t.createdDate ?? t.createdAt,
        isUtc: true,
      ).toLocal();
      DateTime c = DateTime(cDate.year, cDate.month, cDate.day);
      return c.isBefore(today);
    }
  }

  void showAddTodoDialog() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddTodoScreen(
          todoGroups: widget.todoGroups,
          initialTeamUuid: _selectedSubTeamUuid, // 🚀 关键：穿透视口上下文，自动标记团队
          onTodoAdded: (todo) {
            final updatedList = List<TodoItem>.from(widget.todos)..add(todo);
            widget.onTodosChanged(updatedList);
          },
          onLLMResultsParsed: widget.onLLMResultsParsed,
        ),
      ),
    );
  }

  /// 显示添加待办对话框并预填充大模型识别的数据
  /// [llmResults] 大模型识别结果列表
  /// [imagePath] 原始图片路径（用于显示缩略图）
  void showAddTodoDialogWithData(
    List<Map<String, dynamic>> llmResults, [
    String? imagePath,
    String? originalText,
  ]) {
    if (widget.onLLMResultsParsed != null) {
      final existingTeams = <String, String>{};
      for (var t in widget.todos) {
        if (t.teamUuid != null && t.teamName != null) {
          existingTeams[t.teamUuid!] = t.teamName!;
        }
      }
      final currentTeamName = _selectedSubTeamUuid != null ? existingTeams[_selectedSubTeamUuid] : null;
      widget.onLLMResultsParsed!(llmResults, imagePath, originalText, _selectedSubTeamUuid, currentTeamName);
    } else {
      // 如果没有回调，使用旧的对话框方式
      _showAddTodoDialogWithData(llmResults, imagePath);
    }
  }

  void _showAddTodoDialogWithData(
    List<Map<String, dynamic>>? llmResults,
    String? imagePath,
  ) {
    TextEditingController titleCtrl = TextEditingController();
    TextEditingController remarkCtrl = TextEditingController();
    DateTime createdAt = DateTime.now();
    DateTime? dueDate;
    RecurrenceType recurrence = RecurrenceType.none;
    TextEditingController customDaysCtrl = TextEditingController();
    int? customDays;
    DateTime? recurrenceEndDate;
    bool isAllDay = false;
    int reminderMinutes = 5; // 🚀 新增提醒设置
    Map<String, int> categoryReminderDefaults = {};
    String? currentUsername;

    int currentTab = 0;
    TextEditingController aiInputCtrl = TextEditingController();
    List<ParsedTodoResult> parsedResults = [];
    int currentParseIndex = 0;
    bool isParsing = false;
    String? llmRawResponse;
    String? sharedImagePath = imagePath; // 保存分享的图片路径

    int selectedTabIndex = 0;
    String? currentOriginalText; // 📄 保存原始文本内容

    // 如果有预填充的大模型数据，解析并设置
    if (llmResults != null && llmResults.isNotEmpty) {
      parsedResults = llmResults.map((result) {
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
          reminderMinutes: result['reminderMinutes'],
        );
      }).toList();

      llmRawResponse = const JsonEncoder.withIndent('  ').convert(llmResults);

      // 设置第一个待办的数据
      if (parsedResults.isNotEmpty) {
        final first = parsedResults[0];
        titleCtrl.text = first.title;
        remarkCtrl.text = first.remark ?? "";
        if (first.startTime != null) {
          createdAt = first.startTime!;
          if (first.isAllDay) {
            createdAt = DateTime(
              createdAt.year,
              createdAt.month,
              createdAt.day,
              0,
              0,
            );
          }
        }
        if (first.endTime != null) {
          dueDate = first.endTime;
        } else if (first.startTime != null && first.isAllDay) {
          dueDate = DateTime(
            createdAt.year,
            createdAt.month,
            createdAt.day,
            23,
            59,
          );
        }
        isAllDay = first.isAllDay;
        recurrence = first.recurrence;
        customDays = first.customIntervalDays;
        if (customDays != null) {
          customDaysCtrl.text = customDays.toString();
        }
        reminderMinutes = first.reminderMinutes ?? 5;
        currentOriginalText = first.originalText;
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          Widget manualInputTab() {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: InputDecoration(
                      labelText: "待办内容",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: remarkCtrl,
                    decoration: InputDecoration(
                      labelText: "备注 (可选)",
                      hintText: "添加备注...",
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
                    title: const Text(
                      "全天事件",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    value: isAllDay,
                    activeColor: Theme.of(context).colorScheme.primary,
                    onChanged: (val) {
                      setDialogState(() {
                        isAllDay = val;
                        if (isAllDay) {
                          createdAt = DateTime(
                            createdAt.year,
                            createdAt.month,
                            createdAt.day,
                            0,
                            0,
                          );
                          if (dueDate != null) {
                            dueDate = DateTime(
                              dueDate!.year,
                              dueDate!.month,
                              dueDate!.day,
                              23,
                              59,
                            );
                          } else {
                            dueDate = DateTime(
                              createdAt.year,
                              createdAt.month,
                              createdAt.day,
                              23,
                              59,
                            );
                          }
                        }
                      });
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      "开始时间: ${DateFormat(isAllDay ? 'yyyy-MM-dd' : 'yyyy-MM-dd HH:mm').format(createdAt)}",
                    ),
                    trailing: Icon(
                      Icons.edit_calendar,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
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
                          setDialogState(
                            () => createdAt = DateTime(
                              pickedDate.year,
                              pickedDate.month,
                              pickedDate.day,
                              0,
                              0,
                            ),
                          );
                        } else {
                          if (!context.mounted) return;
                          final pickedTime = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(createdAt),
                          );
                          if (pickedTime != null) {
                            setDialogState(
                              () => createdAt = DateTime(
                                pickedDate.year,
                                pickedDate.month,
                                pickedDate.day,
                                pickedTime.hour,
                                pickedTime.minute,
                              ),
                            );
                          }
                        }
                      }
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      dueDate == null
                          ? "设置截止时间 (可选)"
                          : "截止时间: ${DateFormat(isAllDay ? 'yyyy-MM-dd' : 'yyyy-MM-dd HH:mm').format(dueDate!)}",
                    ),
                    trailing: Icon(
                      Icons.event,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
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
                          setDialogState(
                            () => dueDate = DateTime(
                              pickedDate.year,
                              pickedDate.month,
                              pickedDate.day,
                              23,
                              59,
                            ),
                          );
                        } else {
                          if (!context.mounted) return;
                          final pickedTime = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(
                              dueDate ?? DateTime.now(),
                            ),
                          );
                          if (pickedTime != null) {
                            setDialogState(
                              () => dueDate = DateTime(
                                pickedDate.year,
                                pickedDate.month,
                                pickedDate.day,
                                pickedTime.hour,
                                pickedTime.minute,
                              ),
                            );
                          }
                        }
                      }
                    },
                  ),
                  const Divider(),
                  DropdownButtonFormField<RecurrenceType>(
                    value: recurrence,
                    decoration: InputDecoration(
                      labelText: "循环设置 (可选)",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: RecurrenceType.none,
                        child: Text("不重复"),
                      ),
                      DropdownMenuItem(
                        value: RecurrenceType.daily,
                        child: Text("每天重复"),
                      ),
                      DropdownMenuItem(
                        value: RecurrenceType.weekly,
                        child: Text("每周重复"),
                      ),
                      DropdownMenuItem(
                        value: RecurrenceType.monthly,
                        child: Text("每月重复"),
                      ),
                      DropdownMenuItem(
                        value: RecurrenceType.yearly,
                        child: Text("每年重复"),
                      ),
                      DropdownMenuItem(
                        value: RecurrenceType.weekdays,
                        child: Text("工作日"),
                      ),
                      DropdownMenuItem(
                        value: RecurrenceType.customDays,
                        child: Text("间隔几天"),
                      ),
                    ],
                    onChanged: (val) => setDialogState(() => recurrence = val!),
                  ),
                  if (recurrence == RecurrenceType.customDays)
                    Padding(
                      padding: const EdgeInsets.only(top: 12.0),
                      child: TextField(
                        controller: customDaysCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: "间隔天数",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onChanged: (val) => customDays = int.tryParse(val),
                      ),
                    ),
                  if (recurrence != RecurrenceType.none)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        recurrenceEndDate == null
                            ? "循环截止日期 (可选)"
                            : "循环结束: ${DateFormat('yyyy-MM-dd').format(recurrenceEndDate!)}",
                      ),
                      trailing: Icon(
                        Icons.event_busy,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2100),
                          initialDate: DateTime.now().add(
                            const Duration(days: 30),
                          ),
                        );
                        if (picked != null) {
                          setDialogState(() => recurrenceEndDate = picked);
                        }
                      },
                    ),
                  const Divider(),
                  DropdownButtonFormField<int>(
                    value: reminderMinutes,
                    decoration: InputDecoration(
                      labelText: "温馨提醒 (提前量)",
                      prefixIcon:
                          const Icon(Icons.notifications_active_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text("准时提醒")),
                      DropdownMenuItem(value: 5, child: Text("提前 5 分钟")),
                      DropdownMenuItem(value: 10, child: Text("提前 10 分钟")),
                      DropdownMenuItem(value: 15, child: Text("提前 15 分钟")),
                      DropdownMenuItem(value: 30, child: Text("提前 30 分钟")),
                      DropdownMenuItem(value: 45, child: Text("提前 45 分钟")),
                      DropdownMenuItem(value: 60, child: Text("提前 1 小时")),
                      DropdownMenuItem(value: 120, child: Text("提前 2 小时")),
                      DropdownMenuItem(value: 1440, child: Text("提前 1 天")),
                    ],
                    onChanged: (val) => setDialogState(() {
                      if (val != null) reminderMinutes = val;
                    }),
                  ),
                ],
              ),
            );
          }

          Widget aiRecognitionTab() {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 显示分享的图片缩略图（如果有）
                  if (sharedImagePath != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.secondaryContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.image,
                                size: 16,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                "识别的图片",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.secondary,
                                ),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: () =>
                                    _showFullImage(context, sharedImagePath!),
                                child: const Text("查看大图"),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () =>
                                _showFullImage(context, sharedImagePath!),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(sharedImagePath!),
                                height: 150,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    height: 100,
                                    color: Colors.grey[300],
                                    child: const Center(child: Text("图片加载失败")),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "支持的格式示例",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildExampleText("买牛奶明天5点"),
                        _buildExampleText("下周一在图书馆学习"),
                        _buildExampleText("三天后提醒我交水电费"),
                        _buildExampleText("每天跑步30分钟"),
                        _buildExampleText("上午9点到11点开会@会议室"),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: aiInputCtrl,
                    decoration: InputDecoration(
                      labelText: "输入待办内容",
                      hintText: "在此粘贴或输入文字...",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    maxLines: 4,
                    minLines: 2,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: isParsing
                              ? null
                              : () async {
                                  if (aiInputCtrl.text.trim().isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text("请输入待办内容")),
                                    );
                                    return;
                                  }
                                  setDialogState(() {
                                    isParsing = true;
                                  });

                                  // 给一个短暂延迟让UI刷新出 Loading 状态，避免同步卡顿
                                  await Future.delayed(
                                    const Duration(milliseconds: 150),
                                  );

                                  final results = TodoParserService.parseMulti(
                                    aiInputCtrl.text,
                                  );

                                  setDialogState(() {
                                    parsedResults = results;
                                    currentParseIndex = 0;
                                    isParsing = false;
                                    currentOriginalText = aiInputCtrl.text;
                                  });

                                  if (parsedResults.isNotEmpty) {
                                    final first = parsedResults[0];
                                    setDialogState(() {
                                      titleCtrl.text = first.title;
                                      remarkCtrl.text = first.remark ?? "";
                                      if (first.startTime != null) {
                                        createdAt = first.startTime!;
                                        if (first.isAllDay) {
                                          createdAt = DateTime(
                                            createdAt.year,
                                            createdAt.month,
                                            createdAt.day,
                                            0,
                                            0,
                                          );
                                        }
                                      }
                                      if (first.endTime != null) {
                                        dueDate = first.endTime;
                                      } else if (first.startTime != null &&
                                          first.isAllDay) {
                                        dueDate = DateTime(
                                          createdAt.year,
                                          createdAt.month,
                                          createdAt.day,
                                          23,
                                          59,
                                        );
                                      }
                                      isAllDay = first.isAllDay;
                                      recurrence = first.recurrence;
                                      customDays = first.customIntervalDays;
                                      if (customDays != null) {
                                        customDaysCtrl.text =
                                            customDays.toString();
                                      }

                                      // ★ 解析完成后自动切回"手动输入"标签页供用户检查或修改 ★
                                      selectedTabIndex = 0;
                                    });

                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            "解析成功，共${parsedResults.length}个待办",
                                          ),
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                  }
                                },
                          child: isParsing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text("智能解析"),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: isParsing
                              ? null
                              : () async {
                                  if (aiInputCtrl.text.trim().isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text("请输入待办内容")),
                                    );
                                    return;
                                  }

                                  final config = await LLMService.getConfig();
                                  if (config == null || !config.isConfigured) {
                                    if (!context.mounted) return;
                                    final goToSettings = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text("未配置大模型"),
                                        content: const Text(
                                          "使用大模型识别需要先配置API地址和密钥，是否前往设置？",
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: const Text("取消"),
                                          ),
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
                                            child: const Text("去配置"),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (goToSettings == true &&
                                        context.mounted) {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => const SettingsPage(),
                                        ),
                                      );
                                    }
                                    return;
                                  }

                                  setDialogState(() {
                                    isParsing = true;
                                  });

                                  try {
                                    final results =
                                        await LLMService.parseTodoWithLLM(
                                      aiInputCtrl.text,
                                    );

                                    final parsedResultsList = results.map((
                                      result,
                                    ) {
                                      return ParsedTodoResult(
                                        title:
                                            result['title'] ?? aiInputCtrl.text,
                                        remark: result['remark'],
                                        isAllDay: result['isAllDay'] ?? false,
                                        startTime: result['startTime'] != null
                                            ? DateTime.tryParse(
                                                result['startTime'],
                                              )
                                            : null,
                                        endTime: result['endTime'] != null
                                            ? DateTime.tryParse(
                                                result['endTime'],
                                              )
                                            : null,
                                        recurrence: _parseRecurrenceType(
                                          result['recurrence'],
                                        ),
                                        customIntervalDays:
                                            result['customIntervalDays'],
                                        originalText:
                                            aiInputCtrl.text, // 📄 保存原始输入文字
                                      );
                                    }).toList();

                                    setDialogState(() {
                                      parsedResults = parsedResultsList;
                                      currentParseIndex = 0;
                                      isParsing = false;
                                      llmRawResponse =
                                          const JsonEncoder.withIndent(
                                        '  ',
                                      ).convert(results);
                                    });

                                    if (parsedResults.isNotEmpty) {
                                      // 如果有回调，关闭对话框并导航到确认页面
                                      if (widget.onLLMResultsParsed != null) {
                                        Navigator.pop(ctx);
                                        final existingTeams = <String, String>{};
                                        for (var t in widget.todos) {
                                          if (t.teamUuid != null && t.teamName != null) {
                                            existingTeams[t.teamUuid!] = t.teamName!;
                                          }
                                        }
                                        final currentTeamName = _selectedSubTeamUuid != null ? existingTeams[_selectedSubTeamUuid] : null;

                                        widget.onLLMResultsParsed!(
                                            results, imagePath, aiInputCtrl.text, _selectedSubTeamUuid, currentTeamName);
                                        return;
                                      }

                                      final first = parsedResults[0];
                                      setDialogState(() {
                                        titleCtrl.text = first.title;
                                        remarkCtrl.text = first.remark ?? "";
                                        if (first.startTime != null) {
                                          createdAt = first.startTime!;
                                          if (first.isAllDay) {
                                            createdAt = DateTime(
                                              createdAt.year,
                                              createdAt.month,
                                              createdAt.day,
                                              0,
                                              0,
                                            );
                                          }
                                        }
                                        if (first.endTime != null) {
                                          dueDate = first.endTime;
                                        } else if (first.startTime != null &&
                                            first.isAllDay) {
                                          dueDate = DateTime(
                                            createdAt.year,
                                            createdAt.month,
                                            createdAt.day,
                                            23,
                                            59,
                                          );
                                        }
                                        isAllDay = first.isAllDay;
                                        recurrence = first.recurrence;
                                        customDays = first.customIntervalDays;
                                        if (customDays != null) {
                                          customDaysCtrl.text =
                                              customDays.toString();
                                        }
                                        currentOriginalText = aiInputCtrl.text;
                                        selectedTabIndex = 0;
                                      });

                                      if (mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              "大模型解析成功，共${parsedResults.length}个待办，请确认或修改后保存",
                                            ),
                                            duration: const Duration(
                                              seconds: 2,
                                            ),
                                          ),
                                        );
                                      }
                                    }
                                  } catch (e) {
                                    setDialogState(() {
                                      isParsing = false;
                                    });
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(content: Text("大模型解析失败: $e")),
                                      );
                                    }
                                  }
                                },
                          child: isParsing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text("大模型识别"),
                        ),
                      ),
                    ],
                  ),
                  if (parsedResults.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      "解析结果 (${currentParseIndex + 1}/${parsedResults.length})",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    _buildParseResultItem(
                      "待办内容",
                      parsedResults[currentParseIndex].title,
                    ),
                    _buildParseResultItem(
                      "开始时间",
                      parsedResults[currentParseIndex].startTime != null
                          ? DateFormat('yyyy-MM-dd HH:mm').format(
                              parsedResults[currentParseIndex].startTime!,
                            )
                          : "未识别",
                    ),
                    _buildParseResultItem(
                      "结束时间",
                      parsedResults[currentParseIndex].endTime != null
                          ? DateFormat(
                              'yyyy-MM-dd HH:mm',
                            ).format(parsedResults[currentParseIndex].endTime!)
                          : "未识别",
                    ),
                    _buildParseResultItem(
                      "全天事件",
                      parsedResults[currentParseIndex].isAllDay ? "是" : "否",
                    ),
                    _buildParseResultItem(
                      "重复",
                      _getRecurrenceText(
                        parsedResults[currentParseIndex].recurrence,
                      ),
                    ),
                    _buildParseResultItem(
                      "备注/地点",
                      parsedResults[currentParseIndex].remark ?? "-",
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        if (currentParseIndex > 0)
                          TextButton(
                            onPressed: () {
                              setDialogState(() => currentParseIndex--);
                              _applyParsedResult(
                                parsedResults[currentParseIndex],
                                setDialogState,
                                titleCtrl,
                                remarkCtrl,
                                (d) => createdAt = d,
                                (d) => dueDate = d,
                                (b) => isAllDay = b,
                                (r) => recurrence = r,
                                (i) => customDays = i,
                                customDaysCtrl,
                              );
                            },
                            child: const Text("上一个"),
                          ),
                        if (currentParseIndex < parsedResults.length - 1)
                          TextButton(
                            onPressed: () {
                              setDialogState(() => currentParseIndex++);
                              _applyParsedResult(
                                parsedResults[currentParseIndex],
                                setDialogState,
                                titleCtrl,
                                remarkCtrl,
                                (d) => createdAt = d,
                                (d) => dueDate = d,
                                (b) => isAllDay = b,
                                (r) => recurrence = r,
                                (i) => customDays = i,
                                customDaysCtrl,
                              );
                            },
                            child: const Text("下一个"),
                          ),
                      ],
                    ),
                    if (llmRawResponse != null) ...[
                      const SizedBox(height: 12),
                      ExpansionTile(
                        title: const Text(
                          "大模型原始返回",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: SelectableText(
                              llmRawResponse!,
                              style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            );
          }

          return AlertDialog(
            title: const Text("添加待办"),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.8,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text("手动输入")),
                      ButtonSegment(
                        value: 1,
                        icon: Icon(Icons.auto_awesome),
                        label: Text("AI识别"),
                      ),
                    ],
                    selected: {selectedTabIndex},
                    onSelectionChanged: (Set<int> selection) {
                      setDialogState(() {
                        selectedTabIndex = selection.first;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 400,
                    child: selectedTabIndex == 0
                        ? manualInputTab()
                        : aiRecognitionTab(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("取消"),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  if (titleCtrl.text.isNotEmpty) {
                    final newTodo = TodoItem(
                      title: titleCtrl.text,
                      recurrence: recurrence,
                      customIntervalDays: customDays,
                      recurrenceEndDate: recurrenceEndDate,
                      dueDate: dueDate,
                      createdDate: createdAt.millisecondsSinceEpoch,
                      remark: remarkCtrl.text.trim().isEmpty
                          ? null
                          : remarkCtrl.text.trim(),
                      imagePath: sharedImagePath,
                      originalText: currentOriginalText,
                      reminderMinutes: reminderMinutes,
                    );
                    List<TodoItem> updatedList = List.from(widget.todos)
                      ..add(newTodo);
                    widget.onTodosChanged(updatedList);
                    if (mounted) Navigator.pop(ctx);
                  }
                },
                child: const Text("添加"),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 显示全屏图片预览
  void _showFullImage(BuildContext context, String imagePath) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text("图片预览"),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.file(
                File(imagePath),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Text(
                      "图片加载失败",
                      style: TextStyle(color: Colors.white),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExampleText(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 4),
      child: Text(
        "• $text",
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      ),
    );
  }

  Widget _buildParseResultItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              "$label:",
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _getRecurrenceText(RecurrenceType type) {
    switch (type) {
      case RecurrenceType.none:
        return "不重复";
      case RecurrenceType.daily:
        return "每天重复";
      case RecurrenceType.weekly:
        return "每周重复";
      case RecurrenceType.monthly:
        return "每月重复";
      case RecurrenceType.yearly:
        return "每年重复";
      case RecurrenceType.weekdays:
        return "工作日重复";
      case RecurrenceType.customDays:
        return "自定义间隔";
    }
  }

  RecurrenceType _parseRecurrenceType(String? value) {
    switch (value) {
      case 'daily':
        return RecurrenceType.daily;
      case 'weekly':
        return RecurrenceType.weekly;
      case 'monthly':
        return RecurrenceType.monthly;
      case 'yearly':
        return RecurrenceType.yearly;
      case 'weekdays':
        return RecurrenceType.weekdays;
      case 'customDays':
        return RecurrenceType.customDays;
      default:
        return RecurrenceType.none;
    }
  }

  void _applyParsedResult(
    ParsedTodoResult result,
    void Function(void Function()) setDialogState,
    TextEditingController titleCtrl,
    TextEditingController remarkCtrl,
    Function(DateTime) setCreatedAt,
    Function(DateTime?) setDueDate,
    Function(bool) setIsAllDay,
    Function(RecurrenceType) setRecurrence,
    Function(int?) setCustomDays,
    TextEditingController customDaysCtrl,
  ) {
    setDialogState(() {
      titleCtrl.text = result.title;
      remarkCtrl.text = result.remark ?? "";
      if (result.startTime != null) {
        setCreatedAt(result.startTime!);
        if (result.isAllDay) {
          final d = result.startTime!;
          setCreatedAt(DateTime(d.year, d.month, d.day, 0, 0));
        }
      }
      if (result.endTime != null) {
        setDueDate(result.endTime);
      } else if (result.startTime != null && result.isAllDay) {
        final d = result.startTime!;
        setDueDate(DateTime(d.year, d.month, d.day, 23, 59));
      }
      setIsAllDay(result.isAllDay);
      setRecurrence(result.recurrence);
      if (result.customIntervalDays != null) {
        setCustomDays(result.customIntervalDays);
        customDaysCtrl.text = result.customIntervalDays.toString();
      }
    });
  }

  void _editTodo(TodoItem todo, BuildContext cardCtx) {
    final renderBox = cardCtx.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final rect = renderBox.localToGlobal(Offset.zero) & renderBox.size;
    final color = Theme.of(context).colorScheme.surface;

    Navigator.push(
      context,
      ContainerTransformRoute(
        page: _TodoEditScreen(
          todo: todo,
          todos: widget.todos,
          onTodosChanged: widget.onTodosChanged,
          todoGroups: widget.todoGroups,
          onGroupsChanged: widget.onGroupsChanged,
          username: widget.username,
        ),
        sourceRect: rect,
        sourceColor: color,
        sourceBorderRadius: const BorderRadius.all(Radius.circular(14)),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // 时间标签构建（单行，信息完整）
  // ─────────────────────────────────────────────
  String _buildTimeLabel(
    TodoItem todo,
    DateTime cDate,
    bool isPast,
    bool isFuture,
    DateTime now,
  ) {
    final bool isAllDay = todo.dueDate != null &&
        cDate.hour == 0 &&
        cDate.minute == 0 &&
        todo.dueDate!.hour == 23 &&
        todo.dueDate!.minute == 59;

    final String startStr = isAllDay
        ? DateFormat('MM/dd').format(cDate)
        : DateFormat('MM/dd HH:mm').format(cDate);

    if (todo.dueDate != null) {
      final String dueStr = isAllDay
          ? DateFormat('MM/dd').format(todo.dueDate!)
          : DateFormat('MM/dd HH:mm').format(todo.dueDate!);
      return "$startStr → $dueStr";
    } else {
      return "开始 $startStr";
    }
  }

  // ─────────────────────────────────────────────
  // Dynamic progress fill color system
  // ─────────────────────────────────────────────
  Color _getProgressFillColor(double progress, bool isPast) {
    if (isPast || progress >= 1.0) {
      // Overdue / at deadline: light red
      return const Color(0xFFE57373); // red 300
    } else if (progress >= 0.5) {
      // Mid stage: orange-yellow
      return const Color(0xFFFFB74D); // orange 300
    } else {
      // Early stage: emerald green
      return const Color(0xFF66BB6A); // green 400
    }
  }

  // ─────────────────────────────────────────────
  // Compact card: redesigned
  // ─────────────────────────────────────────────
  Widget _buildTodoItemCard(
    TodoItem todo, {
    required bool isPast,
    required bool isFuture,
    Key? key,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool isLight = widget.isLight;
    final bool isDark = !isLight;

    // ── 颜色层 ──
    final Color cardBg = todo.isDone
        ? colorScheme.surfaceContainerHighest.withOpacity(isLight ? 0.25 : 0.08)
        : colorScheme.surface.withOpacity(
            isPast
                ? (isLight ? 0.9 : 0.45)
                : isFuture
                    ? (isLight ? 0.85 : 0.35)
                    : (isLight ? 0.97 : 0.75),
          );

    final Color titleColor = todo.isDone
        ? colorScheme.onSurface.withOpacity(0.35)
        : (isPast || isFuture
            ? colorScheme.onSurface.withOpacity(0.65)
            : colorScheme.onSurface);

    // ── 进度计算 ──
    DateTime cDate = DateTime.fromMillisecondsSinceEpoch(
      todo.createdDate ?? todo.createdAt,
      isUtc: true,
    ).toLocal();
    final DateTime now = DateTime.now();
    double progress = 0.0;
    {
      DateTime start = cDate;
      DateTime end = todo.dueDate != null
          ? DateTime(
              todo.dueDate!.year,
              todo.dueDate!.month,
              todo.dueDate!.day,
              todo.dueDate!.hour,
              todo.dueDate!.minute,
              59,
            )
          : DateTime(cDate.year, cDate.month, cDate.day, 23, 59, 59);
      int totalMinutes = end.difference(start).inMinutes;
      if (totalMinutes <= 0) totalMinutes = 1;
      if (now.isAfter(start)) {
        progress = (now.difference(start).inMinutes / totalMinutes).clamp(
          0.0,
          1.0,
        );
      }
    }

    // ── 时间徽章文本 ──
    String badge = "";
    Color badgeColor = colorScheme.primary;
    Color badgeBg = colorScheme.primaryContainer.withOpacity(0.6);

    if (todo.dueDate != null) {
      final DateTime d = DateTime(
        todo.dueDate!.year,
        todo.dueDate!.month,
        todo.dueDate!.day,
      );
      final DateTime today = DateTime(now.year, now.month, now.day);
      if (isPast) {
        badge = "已逾期";
        badgeColor = Colors.redAccent.shade200;
        badgeBg = Colors.redAccent.withOpacity(0.12);
      } else if (isFuture) {
        int days = d.difference(today).inDays;
        badge = "$days天后";
        badgeColor = colorScheme.secondary;
        badgeBg = colorScheme.secondaryContainer.withOpacity(0.5);
      } else {
        badge = "今天截止";
        badgeColor = Colors.orange.shade700;
        badgeBg = Colors.orange.withOpacity(0.12);
      }
    } else {
      badge = DateFormat('MM/dd').format(cDate);
      badgeColor = colorScheme.onSurface.withOpacity(0.45);
      badgeBg = colorScheme.onSurface.withOpacity(0.06);
    }

    // ── 循环图标 ──
    Widget? recurrenceIcon;
    if (todo.recurrence != RecurrenceType.none) {
      recurrenceIcon = Icon(
        Icons.repeat_rounded,
        size: 11,
        color: colorScheme.primary.withOpacity(0.6),
      );
    }

    return LongPressDraggable<String>(
      data: todo.id,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.8,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(color: Colors.black26, blurRadius: 12, spreadRadius: 1)
            ],
          ),
          child: Text(todo.title,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 14)),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(todo.title,
              style: TextStyle(color: titleColor.withOpacity(0.95), fontSize: 14.5)),
        ),
      ),
      child: VisibilityDetector(
        key: Key('todo_item_vis_${todo.id}'),
        onVisibilityChanged: (info) {
          if (info.visibleFraction > 0.1 &&
              !_animatedTodoIds.contains(todo.id)) {
            if (mounted) {
              setState(() {
                _animatedTodoIds.add(todo.id);
              });
            }
          }
        },
        child: Dismissible(
            key: key ?? _getTodoDismissKey('dismiss', todo.id),
            direction: DismissDirection.endToStart,
            background: Container(
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: Colors.redAccent.shade400,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              child: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            onDismissed: (_) async {
              _todoDismissKeys.remove('drag_${todo.id}');
              _todoDismissKeys.remove('dismiss_${todo.id}');
              try {
                await StorageService.deleteTodoGlobally(
                    widget.username, todo.id);
                List<TodoItem> updatedList = List.from(widget.todos)
                  ..removeWhere((t) => t.id == todo.id);
                widget.onTodosChanged(updatedList);

                final prefs = await SharedPreferences.getInstance();
                final String cacheKey = 'deleted_todos_${widget.username}';
                List<TodoItem> deleted = [];
                String? str = prefs.getString(cacheKey);
                if (str != null) {
                  deleted = (jsonDecode(str) as Iterable)
                      .map((e) => TodoItem.fromJson(e))
                      .toList();
                }
                deleted.insert(0, todo);
                await prefs.setString(
                  cacheKey,
                  jsonEncode(deleted.map((e) => e.toJson()).toList()),
                );
              } catch (e) {
                debugPrint("删除失败: $e");
              }
            },
            child: Builder(
              builder: (cardCtx) => AnimatedBuilder(
                animation: _completingAnimations[todo.id] ??
                    AlwaysStoppedAnimation(0.0),
                builder: (context, child) {
                  final anim = _completingAnimations[todo.id];
                  final isAnimating = anim != null && anim.isAnimating;
                  final value = isAnimating ? anim.value : 0.0;
                  final scale = 1.0 - (value * 0.08);
                  final opacity = 1.0 - (value * 0.7);

                  return Transform.scale(
                    scale: scale,
                    child: Opacity(
                      opacity: opacity,
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(
                  key: _getTodoCardKey(todo.id),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: todo.teamUuid != null
                          ? (isLight
                              ? colorScheme.surface.withOpacity(0.92)
                              : colorScheme.surfaceContainerHighest.withOpacity(0.4))
                          : cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: todo.teamUuid != null
                            ? colorScheme.primary.withOpacity(0.2)
                            : (isPast && !todo.isDone
                                ? Colors.redAccent.withOpacity(0.25)
                                : colorScheme.outline
                                    .withOpacity(isLight ? 0.06 : 0.12)),
                        width: todo.teamUuid != null ? 1.2 : 1,
                      ),
                      boxShadow: (!todo.isDone && isLight)
                          ? [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.03),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : [],
                    ),
                    child: Stack(
                      children: [
                        if (!todo.isDone)
                          Positioned.fill(
                            child: TweenAnimationBuilder<double>(
                              duration: const Duration(milliseconds: 1200),
                              curve: Curves.easeOutQuart,
                              tween: Tween<double>(
                                  begin: 0.0,
                                  end: _animatedTodoIds.contains(todo.id)
                                      ? (progress < 0.08 ? 0.08 : progress.clamp(0.0, 1.0))
                                      : 0.0),
                              builder: (context, value, child) {
                                final fillColor = _getProgressFillColor(progress, isPast);
                                return FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: value,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          fillColor.withOpacity(isLight ? 0.32 : 0.18),
                                          fillColor.withOpacity(isLight ? 0.15 : 0.08),
                                        ],
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _editTodo(todo, cardCtx),
                            child: IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (todo.teamUuid != null)
                                    Container(
                                      width: 4,
                                      margin: const EdgeInsets.symmetric(vertical: 8),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary,
                                        borderRadius: const BorderRadius.horizontal(
                                          right: Radius.circular(3),
                                        ),
                                      ),
                                    ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: Checkbox(
                                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              visualDensity: VisualDensity.compact,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                              activeColor: colorScheme.primary,
                                              value: todo.isDone,
                                              onChanged: (val) {
                                                if (val == null) return;
                                                
                                                // 🚀 乐观 UI 更新：立即修改状态并通知父组件
                                                final bool wasDone = todo.isDone;
                                                setState(() {
                                                  todo.isDone = val;
                                                  if (val) {
                                                    _isCompleting[todo.id] = true;
                                                  } else {
                                                    _isCompleting.remove(todo.id);
                                                    _completingAnimations[todo.id]?.dispose();
                                                    _completingAnimations.remove(todo.id);
                                                  }
                                                });
                                                
                                                 if (val) {
                                                   PomodoroSyncService().sendStopSignal(todoUuid: todo.id);
                                                 }
                                                 todo.markAsChanged();
                                                List<TodoItem> updatedList = List.from(widget.todos);
                                                // 排序以将已完成移到底部
                                                updatedList.sort((a, b) => a.isDone == b.isDone ? 0 : (a.isDone ? 1 : -1));
                                                widget.onTodosChanged(updatedList);


                                                if (val && !wasDone) {
                                                  // 播放动画后清理
                                                  _completingAnimations[todo.id]?.dispose();
                                                  final controller = AnimationController(duration: const Duration(milliseconds: 400), vsync: this);
                                                  _completingAnimations[todo.id] = controller;
                                                  controller.forward().then((_) {
                                                    if (mounted) {
                                                      setState(() {
                                                        _isCompleting[todo.id] = false;
                                                      });
                                                    }
                                                  });
                                                }
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        todo.title,
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: TextStyle(
                                                          decoration: todo.isDone ? TextDecoration.lineThrough : null,
                                                          decorationColor: colorScheme.onSurface.withOpacity(0.3),
                                                          color: titleColor.withOpacity(0.95),
                                                          fontSize: 14.5,
                                                          fontWeight: todo.isDone || isPast || isFuture ? FontWeight.w500 : FontWeight.w600,
                                                          height: 1.2,
                                                        ),
                                                      ),
                                                    ),
                                                    if (recurrenceIcon != null) ...[
                                                      const SizedBox(width: 4),
                                                      recurrenceIcon,
                                                    ],
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: todo.isDone ? colorScheme.onSurface.withOpacity(0.06) : badgeBg,
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Text(
                                                        badge,
                                                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: todo.isDone ? colorScheme.onSurface.withOpacity(0.3) : badgeColor),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                if (todo.teamUuid != null) ...[
                                                  const SizedBox(height: 5),
                                                  Row(
                                                    children: [
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                            color: colorScheme.primary.withOpacity(0.18),
                                                          borderRadius: BorderRadius.circular(4),
                                                            border: Border.all(color: colorScheme.primary.withOpacity(0.4), width: 0.8),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Icon(_selectedSubTeamUuid == null ? Icons.groups_rounded : Icons.person_outline_rounded, size: 10, color: colorScheme.primary),
                                                            const SizedBox(width: 3),
                                                            Text(
                                                              _selectedSubTeamUuid == null 
                                                                ? "${todo.teamName ?? '团队'} · ${todo.creatorName ?? '成员'}"
                                                                : "创建者：${todo.creatorName ?? '成员'}", 
                                                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: colorScheme.primary)
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      if (todo.collabType == 1 && _teamRoles[todo.teamUuid] == 'admin') ...[
                                                         const SizedBox(width: 6),
                                                         GestureDetector(
                                                           onTap: () => _showIndependentTodoStatus(todo),
                                                           child: Container(
                                                             padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                             decoration: BoxDecoration(
                                                               color: Colors.green.withOpacity(0.15),
                                                               borderRadius: BorderRadius.circular(4),
                                                               border: Border.all(color: Colors.green.withOpacity(0.4), width: 0.8),
                                                             ),
                                                             child: Row(
                                                               children: [
                                                                 const Icon(Icons.assignment_turned_in_outlined, size: 10, color: Colors.green),
                                                                 const SizedBox(width: 3),
                                                                 const Text("独立任务进度", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
                                                               ],
                                                             ),
                                                           ),
                                                         ),
                                                      ],
                                                    ],
                                                  ),
                                                ],
                                                const SizedBox(height: 3),
                                                Row(
                                                  children: [
                                                    Icon(Icons.schedule_rounded, size: 11, color: colorScheme.onSurface.withOpacity(todo.isDone ? 0.65 : (isPast ? 0.75 : 0.65))),
                                                    const SizedBox(width: 3),
                                                    Expanded(child: Text(_buildTimeLabel(todo, cDate, isPast, isFuture, now), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: colorScheme.onSurface.withOpacity(todo.isDone ? 0.4 : isPast ? 0.75 : 0.65), height: 1.2))),
                                                  ],
                                                ),
                                                if (todo.remark != null && todo.remark!.isNotEmpty) ...[
                                                  const SizedBox(height: 2),
                                                  Text(todo.remark!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: colorScheme.onSurface.withOpacity(todo.isDone ? 0.22 : 0.4), height: 1.2)),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
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
              ),
            ),
          ),
        )
    );
  }
  Widget _buildAnimatedSection({required bool expanded, required Widget child}) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: animation,
            axisAlignment: -1,
            child: child,
          ),
        );
      },
      child: expanded
          ? Container(
              key: const ValueKey('expanded_content'),
              child: child,
            )
          : const SizedBox.shrink(key: ValueKey('collapsed_empty')),
    );
  }

  Widget _buildGroupLabel({
    required String text,
    required bool expanded,
    required VoidCallback onTap,
    Color? color,
    IconData? icon,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
            Icon(
              expanded ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
              size: 20,
              color: (color ?? Theme.of(context).colorScheme.onSurface).withOpacity(0.5),
            ),
            const SizedBox(width: 8),
            if (icon != null) ...[
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
            ],
            Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: (color ?? Theme.of(context).colorScheme.onSurface).withOpacity(0.8),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<TodoItem> _sortTodayTodos(List<TodoItem> list, DateTime now) {
    int startMs(TodoItem t) => t.createdDate ?? t.createdAt;
    final undone = list.where((t) => !t.isDone).toList()
      ..sort((a, b) => startMs(a).compareTo(startMs(b)));
    final done = list.where((t) => t.isDone).toList()
      ..sort((a, b) => startMs(a).compareTo(startMs(b)));
    return [...undone, ...done];
  }

  List<TodoItem> _sortFutureTodos(List<TodoItem> list, DateTime now) {
    int startMs(TodoItem t) => t.createdDate ?? t.createdAt;
    final undone = list.where((t) => !t.isDone).toList()
      ..sort((a, b) => startMs(a).compareTo(startMs(b)));
    final done = list.where((t) => t.isDone).toList()
      ..sort((a, b) => startMs(a).compareTo(startMs(b)));
    return [...undone, ...done];
  }

  Widget _buildTodoList() {
    final bool isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final bool useDarkUI = isDarkTheme || widget.isLight;

    final Iterable<TodoItem> activeTodos = widget.todos.where(
      (t) {
        if (t.isDeleted) return false;
        
        // 🧪 诊断打印：仅在调试模式下打印为何任务被隐藏
        final bool isHistorical = _isHistoricalTodo(t);
        final bool matchesTeam = _selectedSubTeamUuid == null || t.teamUuid == _selectedSubTeamUuid;
        
        if (isHistorical || !matchesTeam) {
            // debugPrint('👻 Todo [${t.title}] hidden: historical=$isHistorical, teamMatch=$matchesTeam');
        }

        if (isHistorical) return false;
        return matchesTeam;
      },
    );

    final Iterable<TodoGroup> activeGroups = widget.todoGroups.where(
      (g) {
        if (g.isDeleted) return false;
        if (_selectedSubTeamUuid != null) {
          return g.teamUuid == _selectedSubTeamUuid;
        }
        return true;
      },
    );

    if (activeTodos.isEmpty && activeGroups.isEmpty) {
      return EmptyState(text: "暂无待办，去添加一个吧", isLight: widget.isLight);
    }

    final int undoneCount = activeTodos.where((t) => !t.isDone).length;

    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);

    List<_SortedDisplayItem> pastItems = [];
    List<_SortedDisplayItem> todayItems = [];
    List<_SortedDisplayItem> futureItems = [];
    List<Widget> separateGroupWidgets = [];

    final groupTodosMap = <String, List<TodoItem>>{};
    final List<TodoItem> orphanedTodos = []; // 🚀 孤儿任务容器

    for (var t in widget.todos) {
      if (t.isDeleted || _isHistoricalTodo(t)) continue;
      
      final tid = (t.groupId == null || t.groupId!.isEmpty) ? null : t.groupId;
      if (tid != null) {
        // 检查这个组在当前视角下是否存在
        bool folderExists = widget.todoGroups.any((g) => g.id == tid);
        if (folderExists) {
            groupTodosMap.putIfAbsent(tid, () => []).add(t);
            continue;
        }
      }
      orphanedTodos.add(t);
    }

    void placeItem(_SortedDisplayItem item) {
      if (item.date == null) {
        todayItems.add(item);
      } else {
        final d = DateTime(item.date!.year, item.date!.month, item.date!.day);
        if (d.isBefore(today)) {
          pastItems.add(item);
        } else if (d.isAfter(today)) {
          futureItems.add(item);
        } else {
          todayItems.add(item);
        }
      }
    }

    // 1. Process Folders
    for (var g in widget.todoGroups) {
      if (g.isDeleted) continue;
      
      // 🚀 核心修正：视口过滤
      // 只有在选定特定团队时才进行截流；如果是“全部”(null)，则允许所有文件夹通过
      if (_selectedSubTeamUuid != null && g.teamUuid != _selectedSubTeamUuid) {
        continue;
      }
      final allGTodos = groupTodosMap[g.id] ?? [];
      // 🚀 核心过滤：如果选定了特定团队，则文件夹内的待办也要按团队过滤
      final gTodos = _selectedSubTeamUuid == null 
          ? allGTodos 
          : allGTodos.where((t) => t.teamUuid == _selectedSubTeamUuid).toList();

      if (gTodos.isEmpty && !g.isExpanded) continue;

      bool isAllDone = gTodos.isNotEmpty && gTodos.every((t) => t.isDone);
      DateTime? minDate;
      for (var t in gTodos) {
        if (!t.isDone && t.dueDate != null) {
          if (minDate == null || t.dueDate!.isBefore(minDate)) {
            minDate = t.dueDate;
          }
        }
      }
      if (minDate == null) {
        for (var t in gTodos) {
          if (t.dueDate != null) {
            if (minDate == null || t.dueDate!.isBefore(minDate)) {
              minDate = t.dueDate;
            }
          }
        }
      }

      final w = Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: TodoGroupWidget(
          group: g,
          groupTodos: gTodos,
          isLight: widget.isLight,
          onToggle: () {
            setState(() {
              g.isExpanded = !g.isExpanded;
              g.markAsChanged();
            });
            widget.onGroupsChanged(widget.todoGroups);
          },
          onTodoToggle: (todo) {
            if (!todo.isDone) {
               // 这里是取反前的判断，逻辑上是即将变为 Done
               PomodoroSyncService().sendStopSignal(todoUuid: todo.id);
            }
            todo.isDone = !todo.isDone;
            todo.markAsChanged();
            widget.onTodosChanged(widget.todos);
          },
          onTodoDropped: (todoId) {
            final idx = widget.todos.indexWhere((t) => t.id == todoId);
            if (idx != -1) {
              setState(() {
                widget.todos[idx].groupId = g.id;
                // 对于这种结构性调整，大幅提升版本号，确保覆盖另一端的自动重置（由于通常只+1）
                widget.todos[idx].version += 10;
                widget.todos[idx].updatedAt =
                    DateTime.now().millisecondsSinceEpoch;
              });
              widget.onTodosChanged(widget.todos);
            }
          },
          onTodoRemoved: (todoId) {
            final idx = widget.todos.indexWhere((t) => t.id == todoId);
            if (idx != -1 && widget.todos[idx].groupId != null) {
              setState(() {
                widget.todos[idx].groupId = null;
                // 对于这种结构性调整，大幅提升版本号，确保覆盖另一端的自动重置（由于通常只+1）
                widget.todos[idx].version += 10;
                widget.todos[idx].updatedAt =
                    DateTime.now().millisecondsSinceEpoch;
              });
              widget.onTodosChanged(widget.todos);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('自由了！已移出文件夹')),
              );
            }
          },
          onDelete: () async {
            final idx = widget.todoGroups.indexWhere((x) => x.id == g.id);
            if (idx != -1) {
              widget.todoGroups[idx].isDeleted = true;
              widget.todoGroups[idx].markAsChanged();
            }
            await StorageService.deleteTodoGroupGlobally(widget.username, g.id);
            widget.onGroupsChanged(widget.todoGroups);
            widget.onRefreshRequested();
          },
          onTodoTap: (todo) => _editTodo(todo, context),
          onTodoDelete: (todo) async {
            setState(() {
              // 🚀 跨端联动：删除任务即刻终止番茄钟
              PomodoroSyncService().sendStopSignal(todoUuid: todo.id);
              todo.isDeleted = true;
              todo.markAsChanged();
            });
            widget.onTodosChanged(List<TodoItem>.from(widget.todos));
            await StorageService.deleteTodoGlobally(widget.username, todo.id);
          },
        ),
      );

      // Calculate folder progress
      double groupProgress = 0.0;
      for (var t in gTodos) {
        if (t.isDone) continue;
        final cDate = DateTime.fromMillisecondsSinceEpoch(
                t.createdDate ?? t.createdAt,
                isUtc: true)
            .toLocal();
        final end = t.dueDate ??
            DateTime(cDate.year, cDate.month, cDate.day, 23, 59, 59);
        final totalMin = end.difference(cDate).inMinutes;
        if (totalMin > 0 && now.isAfter(cDate)) {
          final p =
              (now.difference(cDate).inMinutes / totalMin).clamp(0.0, 1.0);
          if (p > groupProgress) groupProgress = p;
        }
      }

      if (_inlineFolders) {
        placeItem(_SortedDisplayItem(
          todo: null,
          group: g,
          date: minDate,
          widget: w,
          isDone: isAllDone,
          startMs: 0,
          progress: groupProgress,
        ));
      } else {
        separateGroupWidgets.add(w);
      }
    }

    // 2. Process Standalone/Orphaned Todos
    for (final t in orphanedTodos) {
      // 🚀 核心修正：视口过滤
      // 只有在选定特定团队时才进行截流；如果是“全部”(null)，则允许所有散装待办通过
      if (_selectedSubTeamUuid != null && t.teamUuid != _selectedSubTeamUuid) {
        continue;
      }

      double todoProgress = 0.0;
      {
        final cDate = DateTime.fromMillisecondsSinceEpoch(
                t.createdDate ?? t.createdAt,
                isUtc: true)
            .toLocal();
        final end = t.dueDate ??
            DateTime(cDate.year, cDate.month, cDate.day, 23, 59, 59);
        final totalMin = end.difference(cDate).inMinutes;
        if (totalMin > 0 && now.isAfter(cDate)) {
          todoProgress =
              (now.difference(cDate).inMinutes / totalMin).clamp(0.0, 1.0);
        }
      }

      placeItem(_SortedDisplayItem(
        todo: t,
        group: null,
        date: t.dueDate,
        widget: const SizedBox.shrink(),
        isDone: t.isDone,
        startMs: t.createdDate ?? t.createdAt,
        progress: todoProgress,
      ));
    }

    void sortItems(List<_SortedDisplayItem> list) {
      list.sort((a, b) {
        if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
        final progressCmp = b.progress.compareTo(a.progress);
        if (progressCmp != 0) return progressCmp;
        if (a.date != null && b.date != null) return a.date!.compareTo(b.date!);
        if (a.date != null) return -1;
        if (b.date != null) return 1;
        return 0;
      });
    }

    sortItems(pastItems);
    sortItems(todayItems);
    sortItems(futureItems);

    final List<Widget> sections = [];

    if (!_inlineFolders && separateGroupWidgets.isNotEmpty) {
      sections.add(
        _buildGroupLabel(
          text: "📂 文件夹",
          expanded: true,
          color: Theme.of(context).colorScheme.primary,
          onTap: () {},
        ),
      );
      sections.add(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: separateGroupWidgets,
      ));
    }

    if (pastItems.isNotEmpty) {
      sections.add(
        _buildGroupLabel(
          text: "逾期 · ${pastItems.length}",
          expanded: _isPastTodosExpanded,
          color: Colors.redAccent.shade200,
          onTap: () =>
              setState(() => _isPastTodosExpanded = !_isPastTodosExpanded),
        ),
      );
      sections.add(
        _buildAnimatedSection(
          expanded: _isPastTodosExpanded,
          child: Column(
            children: pastItems.map((item) {
              final todo = item!.todo;
              if (todo != null) {
                return _buildTodoItemCard(todo,
                    isPast: true,
                    isFuture: false,
                    key: _getTodoDismissKey('dismiss', todo.id));
              }
              return item.widget;
            }).toList(),
          ),
        ),
      );
    }

    final bool allTodayDone =
        todayItems.isNotEmpty && todayItems.every((t) => t.isDone);
    final bool showTodayItems =
        _isTodayManuallyExpanded || (!allTodayDone && _isTodayExpanded);

    // ── 今日板块动画封装 ──
    sections.add(
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        transitionBuilder: (child, animation) {
          return FadeTransition(
              opacity: animation,
              child: SizeTransition(
                  sizeFactor: animation, axisAlignment: -1, child: child));
        },
        child: (!showTodayItems && todayItems.isNotEmpty)
            ? GestureDetector(
                key: const ValueKey('today_summary_card'),
                onTap: () => setState(() {
                  _isTodayManuallyExpanded = true;
                  _isTodayExpanded = true;
                }),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: widget.isLight
                        ? (isDarkTheme
                            ? Colors.grey[850]!.withOpacity(0.95)
                            : Colors.white.withOpacity(0.95))
                        : (allTodayDone
                            ? (isDarkTheme
                                ? Colors.green.withOpacity(0.15)
                                : Colors.green.withOpacity(0.08))
                            : (isDarkTheme
                                ? Colors.white.withValues(alpha: 0.08)
                                : Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.04))),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: allTodayDone
                          ? Colors.green.withOpacity(0.4)
                          : (widget.isLight
                              ? (isDarkTheme
                                  ? Colors.white.withOpacity(0.15)
                                  : Colors.black.withOpacity(0.1))
                              : (isDarkTheme
                                  ? Colors.white.withOpacity(0.22)
                                  : Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.25))),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black
                            .withOpacity(widget.isLight ? 0.15 : 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: allTodayDone
                                  ? Colors.green.withOpacity(0.1)
                                  : Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.1),
                              shape: BoxShape.circle),
                          child: Icon(
                              allTodayDone
                                  ? Icons.celebration_rounded
                                  : Icons.task_alt_rounded,
                              size: 20,
                              color: allTodayDone
                                  ? Colors.green
                                  : Theme.of(context).colorScheme.primary),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(allTodayDone ? "任务已全部达成！" : "今日事今日毕",
                                  style: TextStyle(
                                      color: allTodayDone
                                          ? (isDarkTheme
                                              ? Colors.green.shade200
                                              : Colors.green.shade900)
                                          : (widget.isLight
                                              ? (isDarkTheme
                                                  ? Colors.white
                                                  : Colors.black)
                                              : (isDarkTheme
                                                  ? Colors.white
                                                      .withOpacity(0.9)
                                                  : Colors.black
                                                      .withOpacity(0.85))),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      letterSpacing: 0.2)),
                              const SizedBox(height: 2),
                              Text(
                                  allTodayDone
                                      ? "今天也很努力呢，休息一下吧 ✨"
                                      : "今日还有 ${todayItems.where((t) => !t.isDone).length} 个待办等待完成",
                                  style: TextStyle(
                                      color: (allTodayDone
                                          ? (isDarkTheme
                                              ? Colors.green[200]
                                              : Colors.green[800])
                                          : (widget.isLight
                                              ? (isDarkTheme
                                                  ? Colors.white
                                                      .withOpacity(0.7)
                                                  : Colors.black
                                                      .withOpacity(0.6))
                                              : (isDarkTheme
                                                  ? Colors.white
                                                  : Colors.black))),
                                      fontSize: 12.5)),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios_rounded,
                            size: 14,
                            color: (allTodayDone ? Colors.green : Colors.grey)
                                .withOpacity(0.5)),
                      ],
                    ),
                  ),
                ),
              )
            : (showTodayItems && todayItems.isNotEmpty)
                ? Column(
                    key: const ValueKey('today_expanded_items'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildGroupLabel(
                        text:
                            "今日 · ${todayItems.where((t) => t.isDone).length}/${todayItems.length} 已完成",
                        expanded: true,
                        onTap: () => setState(() {
                          _isTodayExpanded = false;
                          _isTodayManuallyExpanded = false;
                        }),
                      ),
                      _buildAnimatedSection(
                        expanded: _isTodayExpanded,
                        child: ReorderableListView(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          buildDefaultDragHandles: false,
                          onReorder: (oldIndex, newIndex) {
                            if (newIndex > oldIndex) newIndex -= 1;
                            final List<int> todayIndices = [];
                            for (int i = 0; i < widget.todos.length; i++) {
                              final t = widget.todos[i];
                              if (_isHistoricalTodo(t) ||
                                  t.isDeleted ||
                                  t.groupId != null) continue;
                              if (t.dueDate == null ||
                                  (t.dueDate!.year == today.year &&
                                      t.dueDate!.month == today.month &&
                                      t.dueDate!.day == today.day))
                                todayIndices.add(i);
                            }
                            final reordered =
                                List<_SortedDisplayItem>.from(todayItems);
                            final item = reordered.removeAt(oldIndex);
                            reordered.insert(newIndex, item);
                            final updatedList =
                                List<TodoItem>.from(widget.todos);
                            final reorderedTodos = reordered
                                .where((e) => e.todo != null)
                                .map((e) => e.todo!)
                                .toList();
                            for (int i = 0;
                                i < todayIndices.length &&
                                    i < reorderedTodos.length;
                                i++)
                              updatedList[todayIndices[i]] = reorderedTodos[i];
                            widget.onTodosChanged(updatedList);
                          },
                          children: todayItems.asMap().entries.map((entry) {
                            final int index = entry.key;
                            final item = entry.value;
                            if (item.todo != null)
                              return ReorderableDelayedDragStartListener(
                                  key:
                                      _getTodoDismissKey('drag', item.todo!.id),
                                  index: index,
                                  child: _buildTodoItemCard(item.todo!,
                                      isPast: false,
                                      isFuture: false,
                                      key: _getTodoDismissKey(
                                          'dismiss', item.todo!.id)));
                            return Container(
                                key: ValueKey('group_${item.group!.id}'),
                                child: item.widget);
                          }).toList(),
                        ),
                      )
                    ],
                  )
                : const SizedBox.shrink(key: ValueKey('today_empty')),
      ),
    );

    if (futureItems.isNotEmpty) {
      sections.add(_buildGroupLabel(
          text: "将来 · ${futureItems.where((t) => !t.isDone).length} 未完成",
          expanded: _isFutureExpanded,
          icon: Icons.calendar_month_rounded,
          onTap: () => setState(() => _isFutureExpanded = !_isFutureExpanded)));
      sections.add(_buildAnimatedSection(
          expanded: _isFutureExpanded,
          child: Column(
               children: futureItems.map((item) {
                final todo = item!.todo;
                if (todo != null) {
                  return _buildTodoItemCard(todo,
                      isPast: false,
                      isFuture: true,
                      key: _getTodoDismissKey('dismiss', todo.id));
                }
                return item.widget;
              }).toList())));
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
            opacity: animation,
            child: SizeTransition(
                sizeFactor: animation, axisAlignment: -1, child: child));
      },
      child: !_isWholeListExpanded
          ? GestureDetector(
              key: const ValueKey('collapsed_card'),
              onTap: () => setState(() => _isWholeListExpanded = true),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: widget.isLight
                      ? (isDarkTheme
                          ? Colors.grey[850]!.withOpacity(0.95)
                          : Colors.white.withOpacity(0.95))
                      : null,
                  gradient: widget.isLight
                      ? null
                      : LinearGradient(
                          colors: useDarkUI
                              ? [
                                  Colors.white.withOpacity(0.12),
                                  Colors.white.withOpacity(0.04)
                                ]
                              : [
                                  Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.06),
                                  Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.01)
                                ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                      color: widget.isLight
                          ? (isDarkTheme
                              ? Colors.white.withOpacity(0.15)
                              : Colors.black.withOpacity(0.1))
                          : (useDarkUI
                              ? Colors.white.withOpacity(0.1)
                              : Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withOpacity(0.08)),
                      width: 1),
                ),
                child: Row(
                  children: [
                    Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10)),
                        child: Icon(Icons.checklist_rtl_rounded,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary)),
                    const SizedBox(width: 16),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(
                              undoneCount == 0
                                  ? "全部任务已完成"
                                  : "目前还有 $undoneCount 个待办",
                              style: TextStyle(
                                  color: widget.isLight
                                      ? (isDarkTheme
                                          ? Colors.white
                                          : Colors.black)
                                      : (useDarkUI ? Colors.white : null),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  letterSpacing: 0.2)),
                          const SizedBox(height: 2),
                          Text(
                              undoneCount == 0
                                  ? "今天做的不错！点击展开回顾"
                                  : "点击这里展开清单，继续加油吧 ✨",
                              style: TextStyle(
                                  color: widget.isLight
                                      ? (isDarkTheme
                                          ? Colors.white.withOpacity(0.6)
                                          : Colors.black.withOpacity(0.55))
                                      : (useDarkUI
                                              ? Colors.white
                                              : Colors.black)
                                          .withOpacity(0.5),
                                  fontSize: 12)),
                        ])),
                    Icon(Icons.unfold_more_rounded,
                        size: 18,
                        color: (useDarkUI ? Colors.white : Colors.grey)
                            .withOpacity(0.4)),
                  ],
                ),
              ),
            )
          : Column(
              key: const ValueKey('expanded_list'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTeamFilterTabs(), // 🚀 注入团队分类切换
                ...sections
              ],
            ),
    );
  }

  /// 🚀 Uni-Sync 4.0: 首页动态团队切换 Tab
  Widget _buildTeamFilterTabs() {
    // 1. 提取所有关联的团队信息 (同时扫描任务和文件夹)
    final Map<String, String> teamMap = {};
    for (var t in widget.todos) {
      if (t.teamUuid != null && t.teamName != null) {
        teamMap[t.teamUuid!] = t.teamName!;
      }
    }
    for (var g in widget.todoGroups) {
      if (g.teamUuid != null && g.teamName != null) {
        teamMap[g.teamUuid!] = g.teamName!;
      }
    }

    if (teamMap.isEmpty) return const SizedBox.shrink();

    final bool isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final bool useDarkUI = isDarkTheme || widget.isLight;

    return Container(
      height: 40,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // "全部" 按钮
            _buildFilterChip(
              label: "全部",
              isSelected: _selectedSubTeamUuid == null,
              onTap: () {
                setState(() => _selectedSubTeamUuid = null);
                widget.onTeamChanged?.call(null, null);
              },
              useDarkUI: useDarkUI,
            ),
            const SizedBox(width: 8),
            // 各个团队按钮
            ...teamMap.entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: _buildFilterChip(
                  label: entry.value,
                  isSelected: _selectedSubTeamUuid == entry.key,
                  onTap: () {
                    setState(() => _selectedSubTeamUuid = entry.key);
                    widget.onTeamChanged?.call(entry.key, entry.value);
                  },
                  useDarkUI: useDarkUI,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required bool useDarkUI,
  }) {
    final theme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.primary
              : (useDarkUI ? Colors.white10 : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(20),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: theme.primary.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected
                ? Colors.white
                : (useDarkUI ? Colors.white70 : Colors.black87),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final bool useDarkUI = isDarkTheme || widget.isLight;

    final int undoneCount = widget.todos
        .where((t) => !t.isDeleted && !_isHistoricalTodo(t) && !t.isDone)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: SectionHeader(
                title: "待办清单",
                icon: Icons.check_circle_outline,
                actionIcon: Icons.create_new_folder_outlined,
                actionTooltip: "管理文件夹",
                isLight: widget.isLight,
                onAction: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => FolderManageScreen(
                        username: widget.username,
                        todoGroups: widget.todoGroups,
                        onGroupsChanged: widget.onGroupsChanged,
                        allTodos: widget.todos,
                        onTodosChanged: widget.onTodosChanged,
                      ),
                    ),
                  );
                  _loadSettings();
                },
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.smart_toy_outlined,
                    size: 20,
                    color: useDarkUI ? Colors.white70 : Colors.grey,
                  ),
                  onPressed: () {
                    final todosForChat = widget.todos
                        .where((t) =>
                            !t.isDeleted && !t.isDone && !_isHistoricalTodo(t))
                        .map((t) {
                      return <String, dynamic>{
                        'id': t.id,
                        'title': t.title,
                        'remark': t.remark ?? '',
                        'startTime': t.createdDate != null
                            ? DateTime.fromMillisecondsSinceEpoch(
                                t.createdDate!,
                                isUtc: true,
                              ).toLocal().toIso8601String()
                            : '',
                        'endTime': t.dueDate != null
                            ? t.dueDate!.toIso8601String()
                            : '',
                        'isAllDay': t.dueDate != null &&
                            t.dueDate!.hour == 23 &&
                            t.dueDate!.minute == 59,
                        'recurrence': t.recurrence.name,
                        'groupId': t.groupId ?? '',
                      };
                    }).toList();

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TodoChatScreen(
                          username: widget.username,
                          todos: todosForChat,
                          todoGroups: widget.todoGroups,
                          onTodoInserted: (newTodo) {
                            final updatedList =
                                List<TodoItem>.from(widget.todos)..add(newTodo);
                            widget.onTodosChanged(updatedList);
                          },
                          onTodosBatchAction: (inserted, updated) {
                            final List<TodoItem> resultList =
                                List<TodoItem>.from(widget.todos);

                            // 1. 处理新增
                            resultList.addAll(inserted);

                            // 2. 处理更新
                            for (final update in updated) {
                              final idx = resultList
                                  .indexWhere((t) => t.id == update.id);
                              if (idx != -1) {
                                final existing = resultList[idx];
                                final gId = update.groupId;
                                resultList[idx] = TodoItem(
                                  id: existing.id,
                                  title: existing.title,
                                  isDone: existing.isDone,
                                  isDeleted: existing.isDeleted,
                                  version: existing.version,
                                  updatedAt:
                                      DateTime.now().millisecondsSinceEpoch,
                                  createdAt: existing.createdAt,
                                  createdDate: existing.createdDate,
                                  recurrence: existing.recurrence,
                                  customIntervalDays:
                                      existing.customIntervalDays,
                                  recurrenceEndDate: existing.recurrenceEndDate,
                                  dueDate: existing.dueDate,
                                  remark: existing.remark,
                                  groupId:
                                      (gId == null || gId.isEmpty) ? null : gId,
                                )..markAsChanged();
                              }
                            }

                            widget.onTodosChanged(resultList);
                          },
                        ),
                      ),
                    );
                  },
                  tooltip: 'AI待办助手',
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.history,
                    size: 20,
                    color: useDarkUI ? Colors.white70 : Colors.grey,
                  ),
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            HistoricalTodosScreen(username: widget.username),
                      ),
                    );
                    widget.onRefreshRequested();
                  },
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    _isWholeListExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 20,
                    color: useDarkUI ? Colors.white70 : Colors.grey,
                  ),
                  onPressed: () => setState(
                    () => _isWholeListExpanded = !_isWholeListExpanded,
                  ),
                ),
              ],
            ),
          ],
        ),
        _buildTodoList(),
      ],
    );
  }

  void _showCreateGroupDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("新建待办文件夹"),
        content: TextField(
          controller: titleCtrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: "文件夹名称"),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          FilledButton(
            onPressed: () async {
              if (titleCtrl.text.trim().isEmpty) return;
              final newGroup = TodoGroup(name: titleCtrl.text.trim());
              final currentGroups = List<TodoGroup>.from(widget.todoGroups)
                ..add(newGroup);
              await StorageService.saveTodoGroups(
                  widget.username, currentGroups);
              widget.onRefreshRequested();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text("创建"),
          ),
        ],
      ),
    );
  }

  void _showIndependentTodoStatus(TodoItem todo) async {
    // 🚀 不再使用全局阻塞 Dialog，改为弹窗内局部加载
    showDialog(
      context: context,
      builder: (ctx) => _IndependentStatusDialog(todo: todo),
    );
  }
}

/// 🚀 新增：独立任务状态弹窗组件，带局部刷新逻辑，提升网络不佳时的体验
class _IndependentStatusDialog extends StatefulWidget {
  final TodoItem todo;
  const _IndependentStatusDialog({required this.todo});

  @override
  State<_IndependentStatusDialog> createState() => _IndependentStatusDialogState();
}

class _IndependentStatusDialogState extends State<_IndependentStatusDialog> {
  bool _isLoading = true;
  List<dynamic> _statusList = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final res = await ApiService.getTodoStatus(widget.todo.id);
      if (mounted) {
        setState(() {
          _statusList = res['data'] ?? res['status'] ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("任务进度: ${widget.todo.title}"),
      content: SizedBox(
        width: double.maxFinite,
        height: 350,
        child: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : (_error != null 
              ? Center(child: Text("加载失败: $_error"))
              : (_statusList.isEmpty 
                  ? const Center(child: Text("暂无成员进度数据"))
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _statusList.length,
                      itemBuilder: (context, index) {
                        final s = _statusList[index];
                        final isDone = s['is_completed'] == 1;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isDone ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                            child: Text(
                              (s['username'] as String?)?.isNotEmpty == true 
                                  ? s['username'][0].toUpperCase() 
                                  : '?',
                              style: TextStyle(color: isDone ? Colors.green : Colors.grey),
                            ),
                          ),
                          title: Text(s['username']?.toString() ?? '未知用户', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            isDone ? "已完成" : "进行中",
                            style: TextStyle(fontSize: 12, color: isDone ? Colors.green : Colors.grey),
                          ),
                          trailing: Icon(
                            isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                            color: isDone ? Colors.green : Colors.grey,
                          ),
                        );
                      },
                    ))),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("关闭")),
      ],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }
}

class _TodoEditScreen extends StatefulWidget {
  final TodoItem todo;
  final List<TodoItem> todos;
  final Function(List<TodoItem>) onTodosChanged;
  final List<TodoGroup> todoGroups;
  final Function(List<TodoGroup>) onGroupsChanged;
  final String username;
  const _TodoEditScreen(
      {required this.todo,
      required this.todos,
      required this.onTodosChanged,
      required this.todoGroups,
      required this.onGroupsChanged,
      required this.username});
  @override
  State<_TodoEditScreen> createState() => _TodoEditScreenState();
}

class _TodoEditScreenState extends State<_TodoEditScreen> {
  late TextEditingController _titleCtrl;
  late TextEditingController _remarkCtrl;
  late TextEditingController _customDaysCtrl;
  late DateTime _createdDate;
  DateTime? _dueDate;
  late RecurrenceType _recurrence;
  int? _customDays;
  DateTime? _recurrenceEndDate;
  late bool _isAllDay;
  String? _selectedGroupId;
  late int _reminderMinutes;
  Map<String, int> _categoryReminderDefaults = {};
  String? _username;
  List<Team> _teams = [];
  String? _selectedTeamUuid;
  int _collabType = 0;
  bool _syncFolderToTeam = false;

  @override
  void initState() {
    super.initState();
    final t = widget.todo;
    _titleCtrl = TextEditingController(text: t.title);
    _remarkCtrl = TextEditingController(text: t.remark ?? '');
    _createdDate = DateTime.fromMillisecondsSinceEpoch(
            t.createdDate ?? t.createdAt,
            isUtc: true)
        .toLocal();
    _dueDate = t.dueDate;
    _recurrence = t.recurrence;
    _customDays = t.customIntervalDays;
    _customDaysCtrl =
        TextEditingController(text: _customDays?.toString() ?? '');
    _recurrenceEndDate = t.recurrenceEndDate;
    _isAllDay = _dueDate != null &&
        _createdDate.hour == 0 &&
        _createdDate.minute == 0 &&
        _dueDate!.hour == 23 &&
        _dueDate!.minute == 59;
    _selectedGroupId = t.groupId;
    _reminderMinutes = t.reminderMinutes ?? 5;
    _selectedTeamUuid = t.teamUuid;
    _collabType = t.collabType;
    _loadCategoryDefaults();
    _loadTeams();
  }

  Future<void> _loadTeams() async {
    final rawTeams = await ApiService.fetchTeams();
    if (mounted) {
      setState(() {
        _teams = rawTeams.map((t) => Team.fromJson(t)).toList();
      });
    }
  }

  Future<void> _loadCategoryDefaults() async {
    final username = await StorageService.getLoginSession();
    if (username != null) {
      final defaults =
          await StorageService.getCategoryReminderMinutes(username);
      setState(() {
        _username = username;
        _categoryReminderDefaults = defaults;
      });
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _remarkCtrl.dispose();
    _customDaysCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (_titleCtrl.text.isEmpty) return;
    final todo = widget.todo;
    todo.title = _titleCtrl.text;
    todo.createdDate = _createdDate.millisecondsSinceEpoch;
    todo.dueDate = _dueDate;
    todo.recurrence = _recurrence;
    todo.customIntervalDays = _customDays;
    todo.recurrenceEndDate = _recurrenceEndDate;
    todo.remark =
        _remarkCtrl.text.trim().isEmpty ? null : _remarkCtrl.text.trim();
    todo.groupId = _selectedGroupId;
    todo.reminderMinutes = _reminderMinutes;
    todo.teamUuid = _selectedTeamUuid;
    todo.collabType = _collabType;
    todo.markAsChanged();

    if (_syncFolderToTeam && _selectedGroupId != null && _selectedTeamUuid != null) {
      final groups = List<TodoGroup>.from(widget.todoGroups);
      final idx = groups.indexWhere((g) => g.id == _selectedGroupId);
      if (idx != -1) {
        groups[idx].teamUuid = _selectedTeamUuid;
        final team = _teams.where((t) => t.uuid == _selectedTeamUuid).firstOrNull;
        if (team != null) groups[idx].teamName = team.name;
        groups[idx].markAsChanged();
        StorageService.saveTodoGroups(widget.username, groups);
        widget.onGroupsChanged(groups);
      }
    }

    widget.onTodosChanged(List<TodoItem>.from(widget.todos));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bgColor = theme.brightness == Brightness.light ? const Color(0xFFF2F2F7) : theme.colorScheme.surface;

    final uniqueFolderMap = <String, TodoGroup>{};
    for (var g in widget.todoGroups) {
      if (g.id.isNotEmpty) uniqueFolderMap[g.id] = g;
    }
    final availableGroups = uniqueFolderMap.values.toList();
    final effectiveGroupId = (availableGroups.any((g) => g.id == _selectedGroupId))
        ? _selectedGroupId
        : null;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('编辑待办'),
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('删除待办'),
                  content: const Text('确定要删除这条待办吗？'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: Colors.red))),
                  ],
                ),
              );
              if (confirm == true) {
                widget.todo.isDeleted = true;
                widget.todo.markAsChanged();
                widget.onTodosChanged(List<TodoItem>.from(widget.todos));
                if (mounted) Navigator.pop(context);
              }
            },
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
            tooltip: '删除待办',
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: _save, child: const Text('保存', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10)],
            ),
            child: Column(
              children: [
                TextField(
                  controller: _titleCtrl,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(hintText: "待办内容", border: InputBorder.none),
                ),
                const Divider(height: 1),
                TextField(
                  controller: _remarkCtrl,
                  maxLines: 3,
                  minLines: 1,
                  style: const TextStyle(fontSize: 15),
                  decoration: InputDecoration(
                    hintText: "备注 (可选)",
                    hintStyle: TextStyle(color: Colors.grey.withOpacity(0.8)),
                    border: InputBorder.none,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("时间与提醒", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  const Text("全天事件", style: TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(width: 6),
                  SizedBox(
                    height: 24,
                    child: Switch(
                      value: _isAllDay,
                      onChanged: (val) {
                        setState(() {
                          _isAllDay = val;
                          if (_isAllDay) {
                            _createdDate = DateTime(_createdDate.year, _createdDate.month, _createdDate.day, 0, 0);
                            _dueDate = _dueDate != null
                                ? DateTime(_dueDate!.year, _dueDate!.month, _dueDate!.day, 23, 59)
                                : DateTime(_createdDate.year, _createdDate.month, _createdDate.day, 23, 59);
                          }
                        });
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildSquareTile(
                title: "开始时间",
                subtitle: DateFormat(_isAllDay ? 'MM-dd' : 'MM-dd HH:mm').format(_createdDate),
                icon: Icons.play_circle_fill,
                color: Colors.blueAccent,
                onTap: () async {
                  final pickedDate = await showDatePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime(2100), initialDate: _createdDate);
                  if (pickedDate != null) {
                    if (_isAllDay) setState(() => _createdDate = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, 0, 0));
                    else {
                      final pickedTime = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_createdDate));
                      if (pickedTime != null) setState(() => _createdDate = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute));
                    }
                  }
                },
              )),
              const SizedBox(width: 12),
              Expanded(child: _buildSquareTile(
                title: "截止时间",
                subtitle: _dueDate == null ? "未设置" : DateFormat(_isAllDay ? 'MM-dd' : 'MM-dd HH:mm').format(_dueDate!),
                icon: Icons.stop_circle_rounded,
                color: Colors.deepOrangeAccent,
                onTap: () async {
                  final pickedDate = await showDatePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime(2100), initialDate: _dueDate ?? _createdDate);
                  if (pickedDate != null) {
                    if (_isAllDay) setState(() => _dueDate = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, 23, 59));
                    else {
                      final pickedTime = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_dueDate ?? DateTime.now()));
                      if (pickedTime != null) setState(() => _dueDate = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute));
                    }
                  }
                },
              )),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildPopupSquareTile<int>(
                title: "任务提醒",
                subtitle: _getReminderText(_reminderMinutes),
                icon: Icons.notifications_active_rounded,
                color: Colors.purpleAccent,
                value: _reminderMinutes,
                items: [0, 5, 10, 15, 30, 45, 60, 120, 1440].map((m) => PopupMenuItem(value: m, child: Text(_getReminderText(m)))).toList(),
                onSelected: (val) => setState(() => _reminderMinutes = val),
              )),
              const SizedBox(width: 12),
              Expanded(child: _buildPopupSquareTile<RecurrenceType>(
                title: "循环规则",
                subtitle: _getRecurrenceLabel(_recurrence),
                icon: Icons.replay_rounded,
                color: Colors.teal,
                value: _recurrence,
                items: [RecurrenceType.none, RecurrenceType.daily, RecurrenceType.weekly, RecurrenceType.monthly, RecurrenceType.yearly, RecurrenceType.weekdays, RecurrenceType.customDays].map((r) => PopupMenuItem(value: r, child: Text(_getRecurrenceLabel(r)))).toList(),
                onSelected: (val) => setState(() => _recurrence = val),
              )),
            ],
          ),
          if (_recurrence != RecurrenceType.none)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: colorScheme.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.black.withOpacity(0.04))),
              child: Column(
                children: [
                  if (_recurrence == RecurrenceType.customDays) ...[
                    Row(
                      children: [
                        const Text("每隔"),
                        const SizedBox(width: 12),
                        Expanded(child: TextField(controller: _customDaysCtrl, keyboardType: TextInputType.number, textAlign: TextAlign.center, decoration: InputDecoration(isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 8), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onChanged: (val) => setState(() => _customDays = int.tryParse(val)))),
                        const SizedBox(width: 12),
                        const Text("天重复"),
                      ],
                    ),
                    const Divider(height: 24),
                  ],
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime(2100), initialDate: _recurrenceEndDate ?? DateTime.now().add(const Duration(days: 30)));
                      if (picked != null) setState(() => _recurrenceEndDate = picked);
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("循环截止日期"),
                        Row(children: [Text(_recurrenceEndDate == null ? "未指定" : DateFormat('yyyy-MM-dd').format(_recurrenceEndDate!), style: TextStyle(color: _recurrenceEndDate == null ? Colors.grey : colorScheme.primary)), const Icon(Icons.chevron_right, color: Colors.grey, size: 20)]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          if (availableGroups.isNotEmpty || _teams.isNotEmpty) ...[
            const Text("组织与协作", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                if (availableGroups.isNotEmpty)
                  Expanded(child: _buildPopupSquareTile<String>(
                    title: "归属文件夹",
                    subtitle: effectiveGroupId == null ? "未分类" : (availableGroups.where((g) => g.id == effectiveGroupId).firstOrNull?.name ?? '未知'),
                    icon: Icons.folder_rounded,
                    color: Colors.amber.shade600,
                    value: effectiveGroupId ?? "__none__",
                    items: [const PopupMenuItem<String>(value: "__none__", child: Text("未分类")), ...availableGroups.map((g) => PopupMenuItem(value: g.id, child: Text(g.name)))],
                    onSelected: (v) => setState(() {
                      _selectedGroupId = v == "__none__" ? null : v;
                      if (_selectedGroupId != null && _categoryReminderDefaults.containsKey(_selectedGroupId)) _reminderMinutes = _categoryReminderDefaults[_selectedGroupId]!;
                      else if (_selectedGroupId == null) _reminderMinutes = 5;
                    }),
                  )),
                if (availableGroups.isNotEmpty && _teams.isNotEmpty) const SizedBox(width: 12),
                if (_teams.isNotEmpty)
                  Expanded(child: _buildPopupSquareTile<String>(
                    title: "团队归属",
                    subtitle: _selectedTeamUuid == null ? "个人私有" : (_teams.where((t) => t.uuid == _selectedTeamUuid).firstOrNull?.name ?? '未知'),
                    icon: Icons.groups_rounded,
                    color: Colors.indigoAccent,
                    value: _selectedTeamUuid ?? "__none__",
                    items: [const PopupMenuItem<String>(value: "__none__", child: Text("个人私有 (仅自己可见)")), ..._teams.map((t) => PopupMenuItem(value: t.uuid, child: Text(t.name)))],
                    onSelected: (v) => setState(() => _selectedTeamUuid = v == "__none__" ? null : v),
                  )),
              ],
            ),
            if (_selectedTeamUuid != null) _buildCompactTeamSection(),
            const SizedBox(height: 12),
            if (_selectedTeamUuid != null && effectiveGroupId != null)
              Builder(builder: (context) {
                final folder = uniqueFolderMap[effectiveGroupId];
                if (folder != null && folder.teamUuid != _selectedTeamUuid) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0, left: 4.0),
                    child: Row(
                      children: [
                        SizedBox(height: 24, width: 24, child: Checkbox(value: _syncFolderToTeam, onChanged: (val) => setState(() => _syncFolderToTeam = val ?? false))),
                        const SizedBox(width: 8),
                        Expanded(child: Text("将文件夹 '${folder.name}' 也同步到团队，方便队友查看分类", style: TextStyle(fontSize: 12, color: colorScheme.primary, fontStyle: FontStyle.italic))),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              }),
            const SizedBox(height: 24),
          ],
          if (widget.todo.imagePath != null || (widget.todo.originalText != null && widget.todo.originalText!.isNotEmpty)) ...[
             const Text("原始分析来源", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
             const SizedBox(height: 12),
             if (widget.todo.imagePath != null) 
                GestureDetector(onTap: () => _showFullImage(context, widget.todo.imagePath!), child: Container(height: 160, width: double.infinity, decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), image: DecorationImage(image: FileImage(File(widget.todo.imagePath!)), fit: BoxFit.cover)))),
             if (widget.todo.originalText != null && widget.todo.originalText!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: colorScheme.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.black.withOpacity(0.04))), child: Text(widget.todo.originalText!, style: const TextStyle(fontSize: 13, color: Colors.grey))),
             ],
             const SizedBox(height: 24),
          ],
        ]),
      ),
    );
  }

  Widget _buildSquareTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 105,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withOpacity(0.04)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.01),
                blurRadius: 10,
                offset: const Offset(0, 2),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 26),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPopupSquareTile<T>({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required T value,
    required List<PopupMenuEntry<T>> items,
    required ValueChanged<T> onSelected,
  }) {
    return PopupMenuButton<T>(
      initialValue: value,
      onSelected: onSelected,
      itemBuilder: (context) => items,
      offset: const Offset(0, 45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: _buildSquareTile(
        title: title,
        subtitle: subtitle,
        icon: icon,
        color: color,
        onTap: null, // Let PopupMenu handle it
      ),
    );
  }

  String _getReminderText(int minutes) {
    if (minutes == 0) return "准时提醒";
    if (minutes < 60) return "提前 $minutes 分钟";
    if (minutes < 1440) return "提前 ${minutes ~/ 60} 小时";
    return "提前 ${minutes ~/ 1440} 天";
  }

  String _getRecurrenceLabel(RecurrenceType type) {
    switch (type) {
      case RecurrenceType.none: return "不重复";
      case RecurrenceType.daily: return "每天";
      case RecurrenceType.weekly: return "每周";
      case RecurrenceType.monthly: return "每月";
      case RecurrenceType.yearly: return "每年";
      case RecurrenceType.weekdays: return "工作日";
      case RecurrenceType.customDays: return "自定义";
    }
  }

  Widget _buildCompactTeamSection() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("完成规则", style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
          SizedBox(
            width: 140,
            child: _buildCustomSegmentedControl(
              labels: const ["全队同步", "各自独立"],
              selectedIndex: _collabType,
              onChanged: (idx) => setState(() => _collabType = idx),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomSegmentedControl({
    required List<String> labels,
    required int selectedIndex,
    required ValueChanged<int> onChanged,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final isSelected = selectedIndex == index;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.all(2),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? colorScheme.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: isSelected ? [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 1))
                  ] : [],
                ),
                child: Text(
                  labels[index],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? colorScheme.primary : colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  void _showFullImage(BuildContext context, String imagePath) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text("图片预览"),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.file(
                File(imagePath),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Text(
                      "图片加载失败",
                      style: TextStyle(color: Colors.white),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}






class _SortedDisplayItem {
  final TodoItem? todo;
  final TodoGroup? group;
  final DateTime? date;
  final Widget widget;
  final bool isDone;
  final int startMs;
  final double progress;

  _SortedDisplayItem({
    this.todo,
    this.group,
    this.date,
    required this.widget,
    required this.isDone,
    this.startMs = 0,
    this.progress = 0.0,
  });
}
