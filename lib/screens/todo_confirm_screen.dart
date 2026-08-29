import '../widgets/floating_glass_control.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../storage_service.dart';
import '../services/llm_service.dart';
import '../services/notification_service.dart';
import '../services/item_semantics_service.dart';
import '../services/fixed_schedule_recurrence_service.dart';
import '../services/reminder_schedule_service.dart';
import '../utils/local_image_provider.dart';
import '../utils/persistent_image_storage.dart';

enum _TodoConfirmationAction { addTodo, addFixedSchedule, cancel }

class ParsedTodoResult {
  final String title;
  final String? remark;
  final String? location;
  final bool isAllDay;
  final DateTime? startTime;
  final DateTime? endTime;
  final ParsedTimeSemantics timeSemantics;
  final RecurrenceType recurrence;
  final int? customIntervalDays;
  final String? originalText;
  final int? reminderMinutes;
  final String? groupId;
  final int collabType;
  final String? itemKind;

  final String? teamUuid;
  final String? teamName;
  final DateTime? recurrenceEndDate;

  ParsedTodoResult({
    required this.title,
    this.remark,
    this.location,
    this.isAllDay = false,
    this.startTime,
    this.endTime,
    this.timeSemantics = ParsedTimeSemantics.unscheduled,
    this.recurrence = RecurrenceType.none,
    this.customIntervalDays,
    this.originalText,
    this.reminderMinutes,
    this.groupId,
    this.collabType = 0,
    this.itemKind,
    this.teamUuid,
    this.teamName,
    this.recurrenceEndDate,
  });

  Map<String, dynamic> toMap() {
    final normalizedTime = TodoItem.normalizeTimeForWrite(
      selectedDate: startTime,
      dueDate: endTime,
      isDateOnly: isAllDay,
    );
    return {
      'title': title,
      'remark': remark,
      'location': location,
      'isAllDay': isAllDay,
      'startTime': normalizedTime.start?.toIso8601String(),
      'endTime': normalizedTime.due?.toIso8601String(),
      'timeMode': timeSemantics.name,
      'recurrence': recurrence.name,
      'customIntervalDays': customIntervalDays,
      'originalText': originalText,
      'reminderMinutes': reminderMinutes,
      'groupId': groupId,
      'collab_type': collabType,
      'itemKind': itemKind,
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
  final Future<void> Function(FixedScheduleItem)? onFixedScheduleAdded;
  final VoidCallback? onSkip;

  final String? initialTeamUuid;
  final String? initialTeamName;

  const TodoConfirmScreen({
    super.key,
    required this.llmResults,
    this.imagePath,
    this.originalText,
    this.onConfirm,
    this.onFixedScheduleAdded,
    this.onSkip,
    this.initialTeamUuid,
    this.initialTeamName,
  });

  @override
  State<TodoConfirmScreen> createState() => _TodoConfirmScreenState();
}

class _TodoConfirmScreenState extends State<TodoConfirmScreen> {
  late List<ParsedTodoResult> _allTodos;
  final List<Map<String, dynamic>> _confirmedTodos = [];
  int _fixedScheduleCount = 0;
  int _currentIndex = 0;
  bool _isRetrying = false;
  String? _retryStatus;
  List<TodoGroup> _todoGroups = [];
  Map<String, int> _categoryReminderDefaults = {};

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
        _todoGroups = groups.where((g) => !g.isDeleted).toList();
        _categoryReminderDefaults = defaults;
      });
    }
  }

  List<ParsedTodoResult> _parseResults(List<Map<String, dynamic>> results) {
    return results.map((result) {
      final startTime = result['startTime'] != null
          ? DateTime.tryParse(result['startTime'])
          : null;
      final endTime = result['endTime'] != null
          ? DateTime.tryParse(result['endTime'])
          : null;
      final isAllDay = result['isAllDay'] ?? false;
      return ParsedTodoResult(
        title: result['title'] ?? '',
        remark: result['remark'],
        location: result['location']?.toString(),
        isAllDay: isAllDay,
        startTime: startTime,
        endTime: endTime,
        timeSemantics: _parseTimeSemantics(
          result['timeMode'],
          isAllDay: isAllDay,
          startTime: startTime,
          endTime: endTime,
        ),
        recurrence: _parseRecurrenceType(result['recurrence']),
        customIntervalDays: result['customIntervalDays'],
        originalText: widget.originalText, // 📄 传入原始文本
        reminderMinutes: result['reminderMinutes'],
        groupId: result['groupId'],
        collabType: result['collab_type'] ?? 0,
        itemKind: result['itemKind']?.toString(),
        teamUuid: widget.initialTeamUuid,
        teamName: widget.initialTeamName,
        recurrenceEndDate: DateTime.tryParse(
          (result['recurrenceEndDate'] ?? result['recurrence_end_date'] ?? '')
              .toString(),
        ),
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
      case 'weekdays':
        return RecurrenceType.weekdays;
      case 'customDays':
        return RecurrenceType.customDays;
      default:
        return RecurrenceType.none;
    }
  }

  ParsedTimeSemantics _parseTimeSemantics(
    dynamic raw, {
    required bool isAllDay,
    required DateTime? startTime,
    required DateTime? endTime,
  }) {
    if (isAllDay) return ParsedTimeSemantics.dateOnly;
    final name = raw?.toString();
    return ParsedTimeSemantics.values.firstWhere(
      (value) => value.name == name,
      orElse: () => startTime != null && endTime != null
          ? ParsedTimeSemantics.range
          : ParsedTimeSemantics.unscheduled,
    );
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
          // debugPrint("重试第$attempt次失败: $e");

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
    final customDaysCtrl =
        TextEditingController(text: customDays?.toString() ?? '');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('编辑事项'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: InputDecoration(
                      labelText: '事项内容',
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
                    title: const Text('某天内完成'),
                    value: isAllDay,
                    onChanged: (val) {
                      setDialogState(() {
                        final wasDateOnlyRange = dueDate != null &&
                            TodoItem.looksLikeLegacyDateOnlyRange(
                              createdAt,
                              dueDate!,
                            );
                        isAllDay = val;
                        if (isAllDay) {
                          createdAt = DateTime(
                            createdAt.year,
                            createdAt.month,
                            createdAt.day,
                          );
                          dueDate = DateTime(
                            dueDate?.year ?? createdAt.year,
                            dueDate?.month ?? createdAt.month,
                            dueDate?.day ?? createdAt.day,
                            23,
                            59,
                          );
                        } else if (wasDateOnlyRange) {
                          final now = DateTime.now();
                          createdAt = DateTime(
                            createdAt.year,
                            createdAt.month,
                            createdAt.day,
                            now.hour,
                            now.minute,
                          );
                          dueDate = null;
                        }
                      });
                    },
                  ),
                  if (isAllDay)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '完成日期: ${DateFormat('yyyy-MM-dd').format(createdAt)}',
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
                            setDialogState(() {
                              createdAt = DateTime(
                                pickedDate.year,
                                pickedDate.month,
                                pickedDate.day,
                              );
                              dueDate = DateTime(
                                pickedDate.year,
                                pickedDate.month,
                                pickedDate.day,
                                23,
                                59,
                              );
                            });
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
                  if (!isAllDay)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        dueDate == null
                            ? '设置截止时间（当前未安排）'
                            : '${DateFormat('yyyy-MM-dd HH:mm').format(dueDate!)} 前完成',
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
                      prefixIcon:
                          const Icon(Icons.notifications_active_outlined),
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
                      labelText: '重复 (可选)',
                      prefixIcon: const Icon(Icons.replay_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: RecurrenceType.none, child: Text('不重复')),
                      DropdownMenuItem(
                          value: RecurrenceType.daily, child: Text('每天重复')),
                      DropdownMenuItem(
                          value: RecurrenceType.weekly, child: Text('每周重复')),
                      DropdownMenuItem(
                          value: RecurrenceType.monthly, child: Text('每月重复')),
                      DropdownMenuItem(
                          value: RecurrenceType.yearly, child: Text('每年重复')),
                      DropdownMenuItem(
                          value: RecurrenceType.weekdays, child: Text('工作日')),
                      DropdownMenuItem(
                          value: RecurrenceType.customDays,
                          child: Text('间隔几天')),
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
                            ? '重复结束日期 (可选)'
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
                      location: todo.location,
                      isAllDay: isAllDay,
                      startTime: createdAt,
                      endTime: dueDate,
                      timeSemantics: isAllDay
                          ? ParsedTimeSemantics.dateOnly
                          : todo.timeSemantics,
                      recurrence: recurrence,
                      customIntervalDays: customDays,
                      recurrenceEndDate: recurrenceEndDate,
                      reminderMinutes: reminderMinutes,
                      groupId: selectedGroupId,
                      collabType: collabType,
                      itemKind: todo.itemKind,
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

  Future<void> _confirmCurrentTodo() async {
    if (_currentIndex >= _allTodos.length) return;
    final todo = _allTodos[_currentIndex];
    final action = await _confirmationAction(todo);
    if (action == _TodoConfirmationAction.cancel) return;
    if (action == _TodoConfirmationAction.addFixedSchedule) {
      if (!await _saveAsFixedSchedule(todo)) return;
    } else {
      _confirmedTodos.add(todo.toMap());
    }
    _moveToNext();
  }

  Future<_TodoConfirmationAction> _confirmationAction(
    ParsedTodoResult todo,
  ) async {
    final intent = _captureIntentFor(todo);
    if (todo.recurrence != RecurrenceType.none) {
      final normalizedTime = TodoItem.normalizeTimeForWrite(
        selectedDate: todo.startTime,
        dueDate: todo.endTime,
        isDateOnly: todo.isAllDay,
      );
      if (normalizedTime.start == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              intent == CaptureIntentKind.fixedSchedule
                  ? '“${todo.title}”是重复日程，请先设置首次发生日期'
                  : '“${todo.title}”是重复待办，请先设置首次完成日期',
            ),
          ),
        );
        return _TodoConfirmationAction.cancel;
      }
    }

    if (intent == CaptureIntentKind.todo || !mounted) {
      return _TodoConfirmationAction.addTodo;
    }
    final (title, message) = switch (intent) {
      CaptureIntentKind.fixedSchedule => (
          '识别为固定日程',
          widget.onFixedScheduleAdded == null
              ? '考试、会议或预约应保存为固定日程。当前入口尚未连接固定日程存储，继续会暂存为待办。'
              : '考试、会议或预约应保存为固定日程，可以直接按固定日程添加。',
        ),
      CaptureIntentKind.planBlock => (
          '识别为规划时段',
          '这个时间段更适合建立规划块。当前继续只保存待办，不会占用该时段。',
        ),
      CaptureIntentKind.needsConfirmation => (
          '需要确认时间性质',
          '无法确定这是固定日程还是可调整的规划时段。当前继续会暂存为待办。',
        ),
      CaptureIntentKind.todo => ('', ''),
    };
    return await showDialog<_TodoConfirmationAction>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  _TodoConfirmationAction.cancel,
                ),
                child: const Text('返回调整'),
              ),
              if (intent == CaptureIntentKind.fixedSchedule &&
                  widget.onFixedScheduleAdded != null)
                FilledButton.tonal(
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    _TodoConfirmationAction.addFixedSchedule,
                  ),
                  child: const Text('保存为固定日程'),
                ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  _TodoConfirmationAction.addTodo,
                ),
                child: const Text('暂存为待办'),
              ),
            ],
          ),
        ) ??
        _TodoConfirmationAction.cancel;
  }

  CaptureIntentKind _captureIntentFor(ParsedTodoResult todo) {
    return ItemSemanticsService.classifyCaptureIntent(
      todo.itemKind == null
          ? todo.originalText ?? todo.title
          : '${todo.title} ${todo.remark ?? ''}',
      declaredKind: todo.itemKind,
    );
  }

  Future<bool> _saveAsFixedSchedule(ParsedTodoResult todo) async {
    final callback = widget.onFixedScheduleAdded;
    if (callback == null) return false;
    final dateSource = todo.startTime ?? todo.endTime;
    if (dateSource == null) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('固定日程需要先确认日期')),
      );
      return false;
    }
    DateTime? start = todo.startTime;
    DateTime? end = todo.endTime;
    if (todo.isAllDay) {
      start = null;
      end = null;
    } else if (todo.timeSemantics == ParsedTimeSemantics.deadline &&
        end != null) {
      start = end;
      end = null;
    }
    final item = FixedScheduleItem(
      title: todo.title,
      date: DateFormat('yyyy-MM-dd').format(dateSource),
      startTime: start?.millisecondsSinceEpoch,
      endTime: end?.millisecondsSinceEpoch,
      source: FixedScheduleSource.ai,
      location: todo.location,
      remark: todo.remark,
      reminderMinutes: [todo.reminderMinutes ?? 15],
      timezone: DateTime.now().timeZoneName,
      recurrence: todo.recurrence,
      teamUuid: todo.teamUuid,
    );
    if (item.recurrence != RecurrenceType.none) {
      item.recurrenceSeriesId = item.id;
    }
    if (item.recurrence == RecurrenceType.none) {
      await callback(item);
      final username = await StorageService.getLoginSession();
      if (username != null) {
        await ReminderScheduleService.scheduleFromStorage(
          username,
          force: true,
        );
      }
      _fixedScheduleCount++;
      return true;
    }
    final recurrenceEnd = todo.recurrenceEndDate ??
        FixedScheduleRecurrenceService.defaultEndDate(
          startDate: dateSource,
          recurrence: item.recurrence,
          customIntervalDays: todo.customIntervalDays ?? 1,
        );
    late final ({
      List<FixedScheduleItem> active,
      List<FixedScheduleItem> changes,
    }) series;
    try {
      series = FixedScheduleRecurrenceService.rebuildSeries(
        template: item,
        existingSeries: const [],
        recurrence: item.recurrence,
        recurrenceEndDate: recurrenceEnd,
        customIntervalDays: todo.customIntervalDays ?? 1,
      );
    } on FixedScheduleRecurrenceLimitException catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
      return false;
    }
    final username = await StorageService.getLoginSession();
    if (username != null) {
      await StorageService.saveFixedSchedules(username, series.changes);
      await callback(series.active.first);
    } else {
      for (final occurrence in series.active) {
        await callback(occurrence);
      }
    }
    final reminderUsername = await StorageService.getLoginSession();
    if (reminderUsername != null) {
      await ReminderScheduleService.scheduleFromStorage(
        reminderUsername,
        force: true,
      );
    }
    _fixedScheduleCount += series.active.length;
    return true;
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
    if (_confirmedTodos.isEmpty && _fixedScheduleCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有添加任何内容')),
      );
      widget.onSkip?.call();
      Navigator.pop(context);
      return;
    }

    // 🚀 核心：移动图片到持久化目录
    String? persistentImagePath;
    if (_confirmedTodos.isNotEmpty && widget.imagePath != null) {
      try {
        persistentImagePath =
            await persistImagePath(widget.imagePath!, 'analysis_images');
        if (persistentImagePath != null) {
          // debugPrint('📸 图片已持久化到: $persistentImagePath');
        }
      } catch (e) {
        // debugPrint('❌ 持久化图片失败: $e');
      }
    }

    // 将路径注入到所有待办中
    if (persistentImagePath != null) {
      for (var todo in _confirmedTodos) {
        todo['imagePath'] = persistentImagePath;
      }
    }

    if (_confirmedTodos.isNotEmpty && widget.onConfirm != null) {
      widget.onConfirm!(_confirmedTodos);
    }
    if (!mounted) return;
    Navigator.pop(context, _confirmedTodos);
  }

  @override
  Widget build(BuildContext context) {
    final imagePath = widget.imagePath;
    final hasImage = localImageExists(imagePath);
    final bool hasMoreTodos = _currentIndex < _allTodos.length;
    final currentTodo = hasMoreTodos ? _allTodos[_currentIndex] : null;

    return Scaffold(
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: Text(hasMoreTodos
            ? '确认事项 (${_currentIndex + 1}/${_allTodos.length})'
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
      body: _isRetrying
          ? _buildSkeleton(Theme.of(context).brightness == Brightness.dark)
          : Column(
              children: [
                // 图片预览（可折叠）
                if (hasImage)
                  Container(
                    height: 120,
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: imagePath != null
                          ? localImageWidget(imagePath, fit: BoxFit.contain)
                          : const SizedBox.shrink(),
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
                            ? Theme.of(context).colorScheme.primary
                            : (_retryStatus!.contains('失败')
                                ? Colors.red
                                : Colors.orange),
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
                    child: hasMoreTodos
                        ? _buildConfirmButtons()
                        : _buildDoneButton(),
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
          Icon(Icons.inbox, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            '没有可确认事项',
            style: TextStyle(color: Colors.grey),
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
                      '${switch (_captureIntentFor(todo)) {
                        CaptureIntentKind.fixedSchedule => '日程',
                        CaptureIntentKind.planBlock => '规划块',
                        CaptureIntentKind.needsConfirmation => '待确认',
                        CaptureIntentKind.todo => '待办',
                      }} ${_currentIndex + 1}/${_allTodos.length}',
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
                    color: Colors.grey,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    todo.remark!,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
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
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, size: 16, color: Colors.green),
                      const SizedBox(width: 8),
                      Text(
                        '已添加 ${_confirmedTodos.length} 个待办',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.green,
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

    final intent = _captureIntentFor(todo);
    if (intent == CaptureIntentKind.fixedSchedule) {
      timeIcon = Icons.event;
      if (todo.isAllDay) {
        timeText = todo.startTime == null
            ? '日期待确认 · 时间待定'
            : '${DateFormat('yyyy-MM-dd').format(todo.startTime!)} · 时间待定';
      } else if (todo.startTime != null && todo.endTime != null) {
        timeText =
            '${DateFormat('MM-dd HH:mm').format(todo.startTime!)}–${DateFormat('HH:mm').format(todo.endTime!)}';
      } else if (todo.startTime != null) {
        timeText =
            '${DateFormat('MM-dd HH:mm').format(todo.startTime!)}开始 · 结束待定';
      } else {
        timeText = '日期和时间待确认';
      }
    } else if (intent == CaptureIntentKind.planBlock) {
      timeIcon = Icons.view_timeline_outlined;
      timeText = todo.startTime != null && todo.endTime != null
          ? '${DateFormat('MM-dd HH:mm').format(todo.startTime!)}–${DateFormat('HH:mm').format(todo.endTime!)}'
          : '规划时段待确认';
    } else if (todo.isAllDay) {
      timeIcon = Icons.today;
      if (todo.startTime != null) {
        timeText = '${DateFormat('yyyy-MM-dd').format(todo.startTime!)}内完成';
      } else {
        timeText = '某天内完成';
      }
    } else if (todo.endTime != null) {
      timeIcon = Icons.schedule;
      timeText = '${DateFormat('MM-dd HH:mm').format(todo.endTime!)}前完成';
    } else if (todo.startTime != null) {
      timeIcon = Icons.play_circle_outline;
      timeText = '时间待确认: ${DateFormat('MM-dd HH:mm').format(todo.startTime!)}';
    } else {
      timeIcon = Icons.access_time;
      timeText = '未安排';
    }

    return Row(
      children: [
        Icon(timeIcon, size: 18, color: Colors.grey),
        const SizedBox(width: 8),
        Text(
          timeText,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey,
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
          Icon(Icons.check_circle_outline, size: 80, color: Colors.green),
          const SizedBox(height: 16),
          Text(
            '确认完成',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            [
              if (_confirmedTodos.isNotEmpty) '${_confirmedTodos.length} 个待办',
              if (_fixedScheduleCount > 0) '$_fixedScheduleCount 个固定日程',
            ].join('、'),
            style: TextStyle(color: Colors.grey),
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
            label: const Text('确认并添加'),
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
                    : () async {
                        final remaining = _allTodos.sublist(_currentIndex);
                        for (final todo in remaining) {
                          final action = await _confirmationAction(todo);
                          if (action == _TodoConfirmationAction.cancel) return;
                          if (action ==
                              _TodoConfirmationAction.addFixedSchedule) {
                            if (!await _saveAsFixedSchedule(todo)) return;
                          } else {
                            _confirmedTodos.add(todo.toMap());
                          }
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
        onPressed: () {
          if (_confirmedTodos.isEmpty && _fixedScheduleCount == 0) {
            widget.onSkip?.call();
          }
          Navigator.pop(context);
        },
        icon: const Icon(Icons.check),
        label: const Text('完成'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _buildSkeleton(bool isDark) {
    final baseColor =
        isDark ? Colors.grey : Colors.white.withValues(alpha: 0.5);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
              height: 180,
              decoration: BoxDecoration(
                  color: baseColor, borderRadius: BorderRadius.circular(20))),
          const SizedBox(height: 20),
          Container(
              height: 80,
              decoration: BoxDecoration(
                  color: baseColor, borderRadius: BorderRadius.circular(16))),
          const SizedBox(height: 12),
          Container(
              height: 80,
              decoration: BoxDecoration(
                  color: baseColor, borderRadius: BorderRadius.circular(16))),
          const Spacer(),
          Container(
              height: 50,
              decoration: BoxDecoration(
                  color: baseColor, borderRadius: BorderRadius.circular(12))),
        ],
      ),
    );
  }
}
