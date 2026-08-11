part of 'todo_section_widget.dart';

class TodoEditScreen extends StatefulWidget {
  final TodoItem todo;
  final List<TodoItem> todos;
  final FutureOr<void> Function(List<TodoItem>) onTodosChanged;
  final List<TodoGroup> todoGroups;
  final FutureOr<void> Function(List<TodoGroup>) onGroupsChanged;
  final String username;
  final bool applyToFutureOccurrences;

  const TodoEditScreen(
      {required this.todo,
      required this.todos,
      required this.onTodosChanged,
      required this.todoGroups,
      required this.onGroupsChanged,
      required this.username,
      this.applyToFutureOccurrences = false,
      super.key});
  @override
  State<TodoEditScreen> createState() => TodoEditScreenState();
}

class TodoEditScreenState extends State<TodoEditScreen> {
  final GlobalKey _planKey = GlobalKey();
  final GlobalKey _focusKey = GlobalKey();
  final GlobalKey _dataKey = GlobalKey();
  bool _showCoachMarks = false;
  late TodoItem _editingTodo;

  Future<void> _checkCoachMarks() async {
    if (_showCoachMarks || !mounted) return;
    final hasSeenCoachMarks =
        await FeatureTipService.hasTipBeenShown('coach_edit_todo');
    if (hasSeenCoachMarks) return;
    if (mounted) {
      _showCoachMarks = true;
      CoachMarkOverlay.show(
        context: context,
        steps: [
          CoachMarkStep(
            targetKey: _planKey,
            title: '计划安排',
            description: '为待办事项规划具体的时间块，方便在时间轴上查看与管理。',
          ),
          CoachMarkStep(
            targetKey: _focusKey,
            title: '专注记录',
            description: '查看在此任务上的所有番茄钟或正计时专注历史。',
          ),
          CoachMarkStep(
            targetKey: _dataKey,
            title: '数据存证',
            description: '每次修改任务的时间、状态或内容，系统都会自动记录，方便随时追溯历史版本。',
          ),
        ],
        onFinish: _dismissCoachMarks,
        onSkip: _dismissCoachMarks,
      );
    }
  }

  Future<void> _dismissCoachMarks() async {
    if (!mounted) return;
    await FeatureTipService.markTipShown('coach_edit_todo');
    _showCoachMarks = false;
  }

  late TextEditingController _titleCtrl;
  late TextEditingController _remarkCtrl;
  late TextEditingController _customDaysCtrl;
  late bool _isDone;
  late DateTime _createdDate;
  late DateTime _originalCreatedDate;
  DateTime? _dueDate;
  late RecurrenceType _recurrence;
  int? _customDays;
  DateTime? _recurrenceEndDate;
  late bool _isAllDay;
  late bool _preserveLegacyTiming;
  String? _selectedGroupId;
  late int _reminderMinutes;
  Map<String, int> _categoryReminderDefaults = {};
  List<Team> _teams = [];
  String? _selectedTeamUuid;
  int _collabType = 0;
  bool _syncFolderToTeam = false;
  List<TodoPlanBlock> _relatedPlanBlocks = [];
  bool _isLoadingPlans = true;
  List<PomodoroRecord> _focusRecords = [];
  bool _isLoadingRecords = true;

  @override
  void initState() {
    super.initState();
    _editingTodo = widget.todo;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final route = ModalRoute.of(context);
      if (route != null && route.animation != null) {
        if (route.animation!.isCompleted) {
          _checkCoachMarks();
        } else {
          void listener(AnimationStatus status) {
            if (status == AnimationStatus.completed) {
              _checkCoachMarks();
              route.animation!.removeStatusListener(listener);
            }
          }

          route.animation!.addStatusListener(listener);
        }
      } else {
        _checkCoachMarks();
      }
    });
    final t = _editingTodo;
    _titleCtrl = TextEditingController(text: t.title);
    _remarkCtrl = TextEditingController(text: t.remark ?? '');
    _isDone = t.isDone;
    _createdDate = DateTime.fromMillisecondsSinceEpoch(
            t.createdDate ?? t.createdAt,
            isUtc: true)
        .toLocal();
    _originalCreatedDate = _createdDate;
    _dueDate = t.dueDate;
    _recurrence = t.recurrence;
    _customDays = t.customIntervalDays;
    _customDaysCtrl =
        TextEditingController(text: _customDays?.toString() ?? '');
    _recurrenceEndDate = t.recurrenceEndDate;
    _isAllDay = t.isDateOnly;
    _preserveLegacyTiming = t.hasLegacyTiming;
    _selectedGroupId = t.groupId;
    _reminderMinutes = t.reminderMinutes ?? 5;
    _selectedTeamUuid = t.teamUuid;
    _collabType = t.collabType;
    _loadCategoryDefaults();
    _loadTeams();
    _loadRelatedPlans();
    _loadFocusRecords();
  }

  Future<void> _loadFocusRecords() async {
    if (!mounted) return;
    final editingTodoId = _editingTodo.id;
    final todoIds = _focusRecordTodoIds(_editingTodo, widget.todos);
    final records = await PomodoroService.getRecordsByTodoUuids(todoIds);
    if (!mounted || _editingTodo.id != editingTodoId) return;
    setState(() {
      _focusRecords = records;
      _isLoadingRecords = false;
    });
  }

  Future<void> _loadRelatedPlans() async {
    if (!mounted) return;
    final editingTodoId = _editingTodo.id;
    setState(() => _isLoadingPlans = true);
    final username = await StorageService.getLoginSession() ?? 'default';
    final plans =
        await StorageService.getPlanBlocksByTodo(username, editingTodoId);
    if (!mounted || _editingTodo.id != editingTodoId) return;
    setState(() {
      _relatedPlanBlocks = plans.where((p) => !p.isDeleted).toList();
      _isLoadingPlans = false;
    });
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
      if (!mounted) return;
      setState(() {
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

  Future<bool> _persistCurrentTodo({required bool closeAfterSave}) async {
    if (_titleCtrl.text.isEmpty) return false;
    final todo = _editingTodo;
    if (_preserveLegacyTiming &&
        _dueDate != null &&
        !_dueDate!.isAfter(_createdDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('结束时间必须晚于开始时间')),
      );
      return false;
    }
    final normalizedTime = TodoItem.normalizeTimeForEdit(
      selectedDate: _createdDate,
      dueDate: _dueDate,
      isDateOnly: _isAllDay,
      preserveExistingTiming: _preserveLegacyTiming,
    );
    if (_recurrence != RecurrenceType.none && normalizedTime.start == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('重复待办需要先设置首次完成日期')),
      );
      return false;
    }
    final normalizedStart = normalizedTime.start;
    final normalizedDue = normalizedTime.due;
    final seriesId = todo.recurrenceSeriesId;
    final startShift = normalizedStart == null
        ? Duration.zero
        : normalizedStart.difference(_originalCreatedDate);
    final editedDuration = normalizedStart == null || normalizedDue == null
        ? null
        : normalizedDue.difference(normalizedStart);
    final recurrenceEndDateChanged =
        _recurrenceEndDate?.millisecondsSinceEpoch !=
            todo.recurrenceEndDate?.millisecondsSinceEpoch;

    if (seriesId != null && seriesId.isNotEmpty) {
      final originalStartMs = _originalCreatedDate.millisecondsSinceEpoch;
      for (final occurrence in widget.todos) {
        if (occurrence.id == todo.id ||
            occurrence.isDeleted ||
            occurrence.recurrenceSeriesId != seriesId ||
            (occurrence.createdDate ?? occurrence.createdAt) <
                originalStartMs) {
          continue;
        }

        final occurrenceStart = DateTime.fromMillisecondsSinceEpoch(
          occurrence.createdDate ?? occurrence.createdAt,
          isUtc: true,
        ).toLocal();
        final shiftedStart = occurrenceStart.add(startShift);
        final recurrenceEndDay = _recurrenceEndDate == null
            ? null
            : DateTime(
                _recurrenceEndDate!.year,
                _recurrenceEndDate!.month,
                _recurrenceEndDate!.day,
              );
        final shiftedDay = DateTime(
          shiftedStart.year,
          shiftedStart.month,
          shiftedStart.day,
        );
        // 循环结束日期是系列规则的一部分，即使用户选择“只修改本期”，
        // 结束日期之后的已物化实例也必须删除；否则存储层下次滚动时仍
        // 会把它们视为系列成员。其它字段仍遵循“修改后续周期”开关。
        if (recurrenceEndDateChanged &&
            recurrenceEndDay != null &&
            shiftedDay.isAfter(recurrenceEndDay)) {
          occurrence.isDeleted = true;
          occurrence.recurrence = RecurrenceType.none;
          occurrence.markAsChanged();
          continue;
        }
        if (!widget.applyToFutureOccurrences) continue;
        if (_recurrence == RecurrenceType.none) {
          occurrence.isDeleted = true;
          occurrence.recurrence = RecurrenceType.none;
          occurrence.markAsChanged();
          continue;
        }
        occurrence.title = _titleCtrl.text;
        occurrence.createdDate = shiftedStart.millisecondsSinceEpoch;
        occurrence.dueDate =
            editedDuration == null ? null : shiftedStart.add(editedDuration);
        if (occurrence.recurrence != RecurrenceType.none) {
          occurrence.recurrence = _recurrence;
        }
        occurrence.customIntervalDays = _customDays;
        occurrence.recurrenceEndDate = _recurrenceEndDate;
        occurrence.remark =
            _remarkCtrl.text.trim().isEmpty ? null : _remarkCtrl.text.trim();
        occurrence.groupId = _selectedGroupId;
        occurrence.reminderMinutes = _reminderMinutes;
        occurrence.teamUuid = _selectedTeamUuid;
        occurrence.collabType = _collabType;
        occurrence.isAllDay = _isAllDay;
        occurrence.markAsChanged();
      }
    }

    todo.title = _titleCtrl.text;
    final wasDone = todo.isDone;
    todo.isDone = _isDone;
    if (!wasDone && _isDone) {
      PomodoroSyncService().sendStopSignal(todoUuid: todo.id);
    }
    todo.createdDate = normalizedStart?.millisecondsSinceEpoch;
    todo.dueDate = normalizedDue;
    todo.recurrence = _recurrence;
    if (_recurrence != RecurrenceType.none &&
        (todo.recurrenceSeriesId == null || todo.recurrenceSeriesId!.isEmpty)) {
      todo.recurrenceSeriesId = todo.id;
    }
    todo.customIntervalDays = _customDays;
    todo.recurrenceEndDate = _recurrenceEndDate;
    todo.remark =
        _remarkCtrl.text.trim().isEmpty ? null : _remarkCtrl.text.trim();
    todo.groupId = _selectedGroupId;
    todo.reminderMinutes = _reminderMinutes;
    todo.teamUuid = _selectedTeamUuid;
    todo.collabType = _collabType;
    todo.isAllDay = _isAllDay;
    todo.markAsChanged();

    if (_syncFolderToTeam &&
        _selectedGroupId != null &&
        _selectedTeamUuid != null) {
      final groups = List<TodoGroup>.from(widget.todoGroups);
      final idx = groups.indexWhere((g) => g.id == _selectedGroupId);
      if (idx != -1) {
        groups[idx].teamUuid = _selectedTeamUuid;
        final team =
            _teams.where((t) => t.uuid == _selectedTeamUuid).firstOrNull;
        if (team != null) groups[idx].teamName = team.name;
        groups[idx].markAsChanged();
        await StorageService.saveTodoGroups(widget.username, groups);
        await widget.onGroupsChanged(groups);
      }
    }

    await widget.onTodosChanged(List<TodoItem>.from(widget.todos));
    if (mounted && closeAfterSave) Navigator.pop(context, true);
    return true;
  }

  /// 设计文档 4.3：将当前循环待办加入习惯追踪。
  Future<void> _addToHabitTracking() async {
    final seriesId = _editingTodo.recurrenceSeriesId ?? _editingTodo.id;
    final already = await HabitRepository.getActiveGoals();
    if (!mounted) return;
    if (already.any((g) => g.sourceIds.contains(seriesId))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该循环待办已加入习惯追踪')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('加入习惯追踪'),
        content: Text(
          '将「${_editingTodo.title}」作为完成型习惯追踪？\n'
          '不会复制待办数据，完成后可在习惯中心查看进度与连续记录。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('加入'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final goal = await HabitRepository.createGoalFromSeries(
      todo: _editingTodo,
      username: widget.username,
    );
    if (!mounted) return;
    if (goal == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该循环待办已加入习惯追踪')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已加入习惯追踪：${goal.name}')),
    );
  }

  Future<void> _save() async {
    await _persistCurrentTodo(closeAfterSave: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bgColor = theme.brightness == Brightness.light
        ? const Color(0xFFF2F2F7)
        : theme.colorScheme.surface;

    final uniqueFolderMap = <String, TodoGroup>{};
    for (var g in widget.todoGroups) {
      if (g.id.isNotEmpty) uniqueFolderMap[g.id] = g;
    }
    final availableGroups = uniqueFolderMap.values.toList();
    final effectiveGroupId =
        (availableGroups.any((g) => g.id == _selectedGroupId))
            ? _selectedGroupId
            : null;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(widget.applyToFutureOccurrences ? '编辑后续周期' : '编辑待办'),
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
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消')),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('删除',
                            style: TextStyle(color: Colors.red))),
                  ],
                ),
              );
              if (confirm == true) {
                _editingTodo.isDeleted = true;
                _editingTodo.hasConflict = false;
                _editingTodo.serverVersionData = null;
                _editingTodo.markAsChanged();
                await widget.onTodosChanged(List<TodoItem>.from(widget.todos));
                if (!context.mounted) return;
                Navigator.pop(context, true);
              }
            },
            icon: const Icon(Icons.delete_outline_rounded,
                color: Colors.redAccent),
            tooltip: '删除待办',
          ),
          if (_editingTodo.recurrence != RecurrenceType.none) ...[
            IconButton(
              onPressed: _addToHabitTracking,
              icon: const Icon(Icons.repeat_rounded),
              tooltip: '加入习惯追踪',
            ),
          ],
          const SizedBox(width: 8),
          TextButton(
              onPressed: _save,
              child: const Text('保存',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.applyToFutureOccurrences) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.event_repeat_rounded,
                      size: 18, color: colorScheme.onSecondaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '本次保存会同步修改本期及之后已经生成的周期，未来周期也会沿用新规则。',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          _buildRelatedRecurrenceSection(colorScheme),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.01), blurRadius: 10)
              ],
            ),
            child: Column(
              children: [
                TextField(
                  controller: _titleCtrl,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(
                      hintText: "待办内容", border: InputBorder.none),
                ),
                const Divider(height: 1),
                TextField(
                  controller: _remarkCtrl,
                  maxLines: 3,
                  minLines: 1,
                  style: const TextStyle(fontSize: 15),
                  decoration: InputDecoration(
                    hintText: "备注 (可选)",
                    hintStyle:
                        TextStyle(color: Colors.grey.withValues(alpha: 0.8)),
                    border: InputBorder.none,
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  key: const ValueKey('todo_edit_completion_switch'),
                  contentPadding: EdgeInsets.zero,
                  value: _isDone,
                  onChanged: (value) => setState(() => _isDone = value),
                  secondary: Icon(
                    _isDone
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: _isDone
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                  title: const Text('完成状态'),
                  subtitle: Text(_isDone ? '本期已完成' : '本期待完成'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("时间与提醒",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  const Text("某天内完成",
                      style: TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(width: 6),
                  SizedBox(
                    height: 24,
                    child: Switch(
                      value: _isAllDay,
                      onChanged: (val) {
                        setState(() {
                          final wasDateOnlyRange = _dueDate != null &&
                              TodoItem.looksLikeLegacyDateOnlyRange(
                                _createdDate,
                                _dueDate!,
                              );
                          _isAllDay = val;
                          if (_isAllDay) {
                            _preserveLegacyTiming = false;
                            _createdDate = DateTime(_createdDate.year,
                                _createdDate.month, _createdDate.day, 0, 0);
                            _dueDate = _dueDate != null
                                ? DateTime(_dueDate!.year, _dueDate!.month,
                                    _dueDate!.day, 23, 59)
                                : DateTime(
                                    _createdDate.year,
                                    _createdDate.month,
                                    _createdDate.day,
                                    23,
                                    59);
                          } else if (wasDateOnlyRange) {
                            final now = DateTime.now();
                            _createdDate = DateTime(
                              _createdDate.year,
                              _createdDate.month,
                              _createdDate.day,
                              now.hour,
                              now.minute,
                            );
                            _dueDate = null;
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
          if (_preserveLegacyTiming && !_isAllDay) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '这是旧版时间待办，已有的开始/结束设置会继续保留。新的不可移动事项请使用“固定日程”。',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
          Row(
            children: [
              if (_isAllDay)
                Expanded(
                    child: _buildSquareTile(
                  title: "完成日期",
                  subtitle: DateFormat('MM-dd').format(_createdDate),
                  icon: Icons.event_available_rounded,
                  color: Theme.of(context).colorScheme.secondary,
                  onTap: () async {
                    final pickedDate = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDate: _createdDate);
                    if (!context.mounted || pickedDate == null) return;
                    if (_isAllDay) {
                      setState(() {
                        _createdDate = DateTime(
                          pickedDate.year,
                          pickedDate.month,
                          pickedDate.day,
                        );
                        _dueDate = DateTime(
                          pickedDate.year,
                          pickedDate.month,
                          pickedDate.day,
                          23,
                          59,
                        );
                      });
                    } else {
                      final pickedTime = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(_createdDate));
                      if (!mounted || pickedTime == null) return;
                      setState(() => _createdDate = DateTime(
                          pickedDate.year,
                          pickedDate.month,
                          pickedDate.day,
                          pickedTime.hour,
                          pickedTime.minute));
                    }
                  },
                )),
              if (_preserveLegacyTiming && !_isAllDay) ...[
                Expanded(
                    child: _buildSquareTile(
                  title: "开始时间",
                  subtitle: DateFormat('MM-dd HH:mm').format(_createdDate),
                  icon: Icons.play_circle_outline_rounded,
                  color: colorScheme.primary,
                  onTap: () async {
                    final pickedDate = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDate: _createdDate);
                    if (!context.mounted || pickedDate == null) return;
                    final pickedTime = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(_createdDate));
                    if (!mounted || pickedTime == null) return;
                    setState(() => _createdDate = DateTime(
                        pickedDate.year,
                        pickedDate.month,
                        pickedDate.day,
                        pickedTime.hour,
                        pickedTime.minute));
                  },
                )),
                const SizedBox(width: 12),
              ],
              if (!_isAllDay)
                Expanded(
                    child: _buildSquareTile(
                  title: _preserveLegacyTiming ? "结束时间" : "截止时间",
                  subtitle: _dueDate == null
                      ? (_preserveLegacyTiming ? "结束时间待定" : "未安排")
                      : _preserveLegacyTiming
                          ? DateFormat('MM-dd HH:mm').format(_dueDate!)
                          : "${DateFormat('MM-dd HH:mm').format(_dueDate!)} 前完成",
                  icon: _preserveLegacyTiming
                      ? Icons.stop_circle_outlined
                      : Icons.flag_rounded,
                  color: Colors.deepOrangeAccent,
                  onTap: () async {
                    final pickedDate = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDate: _dueDate ?? _createdDate);
                    if (!context.mounted || pickedDate == null) return;
                    if (_isAllDay) {
                      setState(() => _dueDate = DateTime(pickedDate.year,
                          pickedDate.month, pickedDate.day, 23, 59));
                    } else {
                      final pickedTime = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(
                              _dueDate ?? DateTime.now()));
                      if (!mounted || pickedTime == null) return;
                      setState(() => _dueDate = DateTime(
                          pickedDate.year,
                          pickedDate.month,
                          pickedDate.day,
                          pickedTime.hour,
                          pickedTime.minute));
                    }
                  },
                )),
            ],
          ),
          if (!_isAllDay && (_dueDate != null || _preserveLegacyTiming))
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _dueDate = null;
                  _preserveLegacyTiming = false;
                }),
                icon: const Icon(Icons.event_busy_outlined, size: 16),
                label: const Text('改为未安排'),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _buildPopupSquareTile<int>(
                title: "任务提醒",
                subtitle: _getReminderText(_reminderMinutes),
                icon: Icons.notifications_active_rounded,
                color: Colors.purpleAccent,
                value: _reminderMinutes,
                items: [0, 5, 10, 15, 30, 45, 60, 120, 1440]
                    .map((m) => PopupMenuItem(
                        value: m, child: Text(_getReminderText(m))))
                    .toList(),
                onSelected: (val) => setState(() => _reminderMinutes = val),
              )),
              const SizedBox(width: 12),
              Expanded(
                  child: _buildPopupSquareTile<RecurrenceType>(
                title: "重复",
                subtitle: _getRecurrenceLabel(_recurrence),
                icon: Icons.replay_rounded,
                color: Colors.teal,
                value: _recurrence,
                items: [
                  RecurrenceType.none,
                  RecurrenceType.daily,
                  RecurrenceType.weekly,
                  RecurrenceType.monthly,
                  RecurrenceType.yearly,
                  RecurrenceType.weekdays,
                  RecurrenceType.customDays
                ]
                    .map((r) => PopupMenuItem(
                        value: r, child: Text(_getRecurrenceLabel(r))))
                    .toList(),
                onSelected: (val) => setState(() => _recurrence = val),
              )),
            ],
          ),
          if (_recurrence != RecurrenceType.none)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: Colors.black.withValues(alpha: 0.04))),
              child: Column(
                children: [
                  if (_recurrence == RecurrenceType.customDays) ...[
                    Row(
                      children: [
                        const Text("每隔"),
                        const SizedBox(width: 12),
                        Expanded(
                            child: TextField(
                                controller: _customDaysCtrl,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(8))),
                                onChanged: (val) => setState(
                                    () => _customDays = int.tryParse(val)))),
                        const SizedBox(width: 12),
                        const Text("天重复"),
                      ],
                    ),
                    const Divider(height: 24),
                  ],
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                          context: context,
                          // 循环结束日期是系列规则，不是当前实例的截止时间；
                          // 允许把规则结束日期回调到今天之前。
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          initialDate: _recurrenceEndDate ??
                              DateTime.now().add(const Duration(days: 30)));
                      if (picked != null) {
                        setState(() => _recurrenceEndDate = picked);
                      }
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("重复结束日期"),
                        Row(children: [
                          Text(
                              _recurrenceEndDate == null
                                  ? "未指定"
                                  : DateFormat('yyyy-MM-dd')
                                      .format(_recurrenceEndDate!),
                              style: TextStyle(
                                  color: _recurrenceEndDate == null
                                      ? Colors.grey
                                      : colorScheme.primary)),
                          const Icon(Icons.chevron_right,
                              color: Colors.grey, size: 20)
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          if (availableGroups.isNotEmpty || _teams.isNotEmpty) ...[
            const Text("组织与协作",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                if (availableGroups.isNotEmpty)
                  Expanded(
                      child: _buildPopupSquareTile<String>(
                    title: "归属文件夹",
                    subtitle: effectiveGroupId == null
                        ? "未分类"
                        : (availableGroups
                                .where((g) => g.id == effectiveGroupId)
                                .firstOrNull
                                ?.name ??
                            '未知'),
                    icon: Icons.folder_rounded,
                    color: Colors.amber.shade600,
                    value: effectiveGroupId ?? "__none__",
                    items: [
                      const PopupMenuItem<String>(
                          value: "__none__", child: Text("未分类")),
                      ...availableGroups.map((g) =>
                          PopupMenuItem(value: g.id, child: Text(g.name)))
                    ],
                    onSelected: (v) => setState(() {
                      _selectedGroupId = v == "__none__" ? null : v;
                      if (_selectedGroupId != null &&
                          _categoryReminderDefaults
                              .containsKey(_selectedGroupId)) {
                        _reminderMinutes =
                            _categoryReminderDefaults[_selectedGroupId]!;
                      } else if (_selectedGroupId == null) {
                        _reminderMinutes = 5;
                      }
                    }),
                  )),
                if (availableGroups.isNotEmpty && _teams.isNotEmpty)
                  const SizedBox(width: 12),
                if (_teams.isNotEmpty)
                  Expanded(
                      child: _buildPopupSquareTile<String>(
                    title: "团队归属",
                    subtitle: _selectedTeamUuid == null
                        ? "个人私有"
                        : (_teams
                                .where((t) => t.uuid == _selectedTeamUuid)
                                .firstOrNull
                                ?.name ??
                            '未知'),
                    icon: Icons.groups_rounded,
                    color: Colors.indigoAccent,
                    value: _selectedTeamUuid ?? "__none__",
                    items: [
                      const PopupMenuItem<String>(
                          value: "__none__", child: Text("个人私有 (仅自己可见)")),
                      ..._teams.map((t) =>
                          PopupMenuItem(value: t.uuid, child: Text(t.name)))
                    ],
                    onSelected: (v) => setState(
                        () => _selectedTeamUuid = v == "__none__" ? null : v),
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
                        SizedBox(
                            height: 24,
                            width: 24,
                            child: Checkbox(
                                value: _syncFolderToTeam,
                                onChanged: (val) => setState(
                                    () => _syncFolderToTeam = val ?? false))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text("将文件夹 '${folder.name}' 也同步到团队，方便队友查看分类",
                                style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.primary,
                                    fontStyle: FontStyle.italic))),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              }),
            const SizedBox(height: 24),
          ],
          _buildPlanBlockSection(),
          _buildFocusRecordsSection(),
          if (_editingTodo.imagePath != null ||
              (_editingTodo.originalText != null &&
                  _editingTodo.originalText!.isNotEmpty)) ...[
            const Text("原始分析来源",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (localImageExists(_editingTodo.imagePath))
              GestureDetector(
                  onTap: () => _showFullImage(context, _editingTodo.imagePath!),
                  child: Container(
                      height: 160,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: localImageWidget(
                        _editingTodo.imagePath!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: 160,
                      ))),
            if (_editingTodo.originalText != null &&
                _editingTodo.originalText!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: Colors.black.withValues(alpha: 0.04))),
                  child: Text(_editingTodo.originalText!,
                      style:
                          const TextStyle(fontSize: 13, color: Colors.grey))),
            ],
            const SizedBox(height: 24),
          ],
          const SizedBox(height: 12),
          KeyedSubtree(
            key: _dataKey,
            child: const Text("数据存证",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => VersionHistorySheet.show(
                    context, _editingTodo.id, 'todos', _editingTodo.title),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Row(
                    children: [
                      Icon(Icons.history_rounded,
                          color: colorScheme.primary, size: 22),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("版本记录与回滚",
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14.5)),
                            Text("追踪修改历史，支持一键恢复至旧版本",
                                style: TextStyle(
                                    fontSize: 11.5, color: Colors.grey)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          color: Colors.grey.withValues(alpha: 0.5)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 60),
        ]),
      ),
    );
  }

  Widget _buildRelatedRecurrenceSection(ColorScheme colorScheme) {
    final occurrences = _relatedRecurrenceOccurrences(
      _editingTodo,
      widget.todos,
    );
    final isRecurrenceSeries = _editingTodo.recurrence != RecurrenceType.none ||
        _editingTodo.recurrenceSeriesId?.isNotEmpty == true;
    if (!isRecurrenceSeries) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_tree_rounded,
                  size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '关联周期',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                '${occurrences.length} 期',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TodoRecurrenceCompletionOverview(
            occurrences: occurrences,
            currentTodoId: _editingTodo.id,
            currentIsDone: _isDone,
          ),
          if (occurrences.length > 1) ...[
            const SizedBox(height: 12),
            Text(
              '当前期已居中，点击其他期次可在本页切换编辑',
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            TodoRecurrenceOccurrencePicker(
              occurrences: occurrences,
              currentTodoId: _editingTodo.id,
              onSelected: _switchToRelatedOccurrence,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _switchToRelatedOccurrence(TodoItem occurrence) async {
    if (occurrence.id == _editingTodo.id) return;
    FocusScope.of(context).unfocus();
    if (_hasUnsavedChanges) {
      final action = await showDialog<_OccurrenceSwitchAction>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('切换循环期次'),
          content: const Text('当前期有尚未保存的修改，要先保存再切换吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                _OccurrenceSwitchAction.cancel,
              ),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                _OccurrenceSwitchAction.discard,
              ),
              child: const Text('放弃修改'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                _OccurrenceSwitchAction.save,
              ),
              child: const Text('保存并切换'),
            ),
          ],
        ),
      );
      if (!mounted ||
          action == null ||
          action == _OccurrenceSwitchAction.cancel) {
        return;
      }
      if (action == _OccurrenceSwitchAction.save) {
        final saved = await _persistCurrentTodo(closeAfterSave: false);
        if (!mounted || !saved) return;
      }
    }

    setState(() {
      _editingTodo = occurrence;
      _loadEditorFields(occurrence);
      _syncFolderToTeam = false;
      _relatedPlanBlocks = [];
      _focusRecords = [];
      _isLoadingPlans = true;
      _isLoadingRecords = true;
    });
    _loadRelatedPlans();
    _loadFocusRecords();
  }

  void _loadEditorFields(TodoItem todo) {
    _titleCtrl.text = todo.title;
    _remarkCtrl.text = todo.remark ?? '';
    _isDone = todo.isDone;
    _createdDate = DateTime.fromMillisecondsSinceEpoch(
      todo.createdDate ?? todo.createdAt,
      isUtc: true,
    ).toLocal();
    _originalCreatedDate = _createdDate;
    _dueDate = todo.dueDate;
    _recurrence = todo.recurrence;
    _customDays = todo.customIntervalDays;
    _customDaysCtrl.text = _customDays?.toString() ?? '';
    _recurrenceEndDate = todo.recurrenceEndDate;
    _isAllDay = todo.isDateOnly;
    _preserveLegacyTiming = todo.hasLegacyTiming;
    _selectedGroupId = todo.groupId;
    _reminderMinutes = todo.reminderMinutes ?? 5;
    _selectedTeamUuid = todo.teamUuid;
    _collabType = todo.collabType;
  }

  bool get _hasUnsavedChanges {
    final normalizedTime = TodoItem.normalizeTimeForEdit(
      selectedDate: _createdDate,
      dueDate: _dueDate,
      isDateOnly: _isAllDay,
      preserveExistingTiming: _preserveLegacyTiming,
    );
    final todo = _editingTodo;
    final editedRemark =
        _remarkCtrl.text.trim().isEmpty ? null : _remarkCtrl.text.trim();
    final savedRemark =
        todo.remark?.trim().isEmpty ?? true ? null : todo.remark!.trim();
    return _titleCtrl.text != todo.title ||
        _isDone != todo.isDone ||
        normalizedTime.start?.millisecondsSinceEpoch != todo.createdDate ||
        normalizedTime.due?.millisecondsSinceEpoch !=
            todo.dueDate?.millisecondsSinceEpoch ||
        _recurrence != todo.recurrence ||
        _customDays != todo.customIntervalDays ||
        _recurrenceEndDate?.millisecondsSinceEpoch !=
            todo.recurrenceEndDate?.millisecondsSinceEpoch ||
        editedRemark != savedRemark ||
        _selectedGroupId != todo.groupId ||
        _reminderMinutes != (todo.reminderMinutes ?? 5) ||
        _selectedTeamUuid != todo.teamUuid ||
        _collabType != todo.collabType ||
        _syncFolderToTeam ||
        _isAllDay != todo.isDateOnly;
  }

  static List<TodoItem> _relatedRecurrenceOccurrences(
    TodoItem current,
    List<TodoItem> todos,
  ) {
    final seriesId = current.recurrenceSeriesId;
    if (seriesId == null || seriesId.isEmpty) return <TodoItem>[current];
    return todos
        .where((todo) => !todo.isDeleted && todo.recurrenceSeriesId == seriesId)
        .toList()
      ..sort((a, b) => (a.createdDate ?? a.createdAt)
          .compareTo(b.createdDate ?? b.createdAt));
  }

  static Set<String> _focusRecordTodoIds(
    TodoItem current,
    List<TodoItem> todos,
  ) {
    final seriesId = current.recurrenceSeriesId;
    if (seriesId == null || seriesId.isEmpty) return <String>{current.id};
    return <String>{
      current.id,
      ...todos
          .where((todo) => todo.recurrenceSeriesId == seriesId)
          .map((todo) => todo.id),
    };
  }

  static int _focusedRecurrencePeriodCount(
    TodoItem current,
    List<TodoItem> todos,
    List<PomodoroRecord> records,
  ) {
    final seriesId = current.recurrenceSeriesId;
    if (seriesId == null || seriesId.isEmpty) {
      return records.isEmpty ? 0 : 1;
    }

    final occurrences = <TodoItem>[
      current,
      ...todos.where((todo) =>
          todo.id != current.id && todo.recurrenceSeriesId == seriesId),
    ];
    final occurrenceById = <String, TodoItem>{
      for (final occurrence in occurrences) occurrence.id: occurrence,
    };
    final occurrenceByStartDay = <String, TodoItem>{};
    for (final occurrence in occurrences) {
      final dayKey = _localDayKey(
        occurrence.createdDate ?? occurrence.createdAt,
      );
      final existing = occurrenceByStartDay[dayKey];
      if (existing == null ||
          (occurrence.recurrence != RecurrenceType.none &&
              existing.recurrence == RecurrenceType.none)) {
        occurrenceByStartDay[dayKey] = occurrence;
      }
    }

    final periodKeys = <String>{};
    for (final record in records) {
      final boundOccurrence = occurrenceById[record.todoUuid];
      if (boundOccurrence != null &&
          _recordStartsInsideOccurrence(record, boundOccurrence)) {
        periodKeys.add(boundOccurrence.id);
        continue;
      }

      final datedOccurrence =
          occurrenceByStartDay[_localDayKey(record.startTime)];
      if (datedOccurrence != null) {
        periodKeys.add(datedOccurrence.id);
        continue;
      }

      periodKeys
          .add(boundOccurrence?.id ?? 'date:${_localDayKey(record.startTime)}');
    }
    return periodKeys.length;
  }

  static bool _recordStartsInsideOccurrence(
    PomodoroRecord record,
    TodoItem occurrence,
  ) {
    final occurrenceStart = occurrence.createdDate ?? occurrence.createdAt;
    final occurrenceEnd = occurrence.dueDate?.millisecondsSinceEpoch;
    if (occurrenceEnd == null) {
      return _localDayKey(record.startTime) == _localDayKey(occurrenceStart);
    }
    return record.startTime >= occurrenceStart &&
        record.startTime <= occurrenceEnd;
  }

  static String _localDayKey(int millisecondsSinceEpoch) {
    final local = DateTime.fromMillisecondsSinceEpoch(
      millisecondsSinceEpoch,
      isUtc: true,
    ).toLocal();
    return '${local.year}-${local.month}-${local.day}';
  }

  @visibleForTesting
  static List<TodoItem> relatedRecurrenceOccurrencesForTest(
    TodoItem current,
    List<TodoItem> todos,
  ) =>
      _relatedRecurrenceOccurrences(current, todos);

  @visibleForTesting
  static Set<String> focusRecordTodoIdsForTest(
    TodoItem current,
    List<TodoItem> todos,
  ) =>
      _focusRecordTodoIds(current, todos);

  @visibleForTesting
  static int focusedRecurrencePeriodCountForTest(
    TodoItem current,
    List<TodoItem> todos,
    List<PomodoroRecord> records,
  ) =>
      _focusedRecurrencePeriodCount(current, todos, records);

  Widget _buildFocusRecordsSection() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isLoadingRecords) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(
            child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    if (_focusRecords.isEmpty) return const SizedBox.shrink();

    final totalFocusSeconds = PomodoroService.totalFocusSeconds(_focusRecords);
    final focusedOccurrenceCount = _focusedRecurrencePeriodCount(
      _editingTodo,
      widget.todos,
      _focusRecords,
    );
    final isRecurrenceSeries =
        _editingTodo.recurrenceSeriesId?.isNotEmpty == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        KeyedSubtree(
          key: _focusKey,
          child: const Text("专注记录",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(Icons.timer_rounded, color: colorScheme.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isRecurrenceSeries ? '循环累计专注' : '累计专注',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    Text(
                      PomodoroService.formatDuration(totalFocusSeconds),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                isRecurrenceSeries
                    ? '${_focusRecords.length} 次 · $focusedOccurrenceCount 期'
                    : '${_focusRecords.length} 次',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
        ..._focusRecords.take(20).map((r) {
          final startLocal =
              DateTime.fromMillisecondsSinceEpoch(r.startTime, isUtc: true)
                  .toLocal();
          final durationMin = r.effectiveDuration ~/ 60;
          final statusIcon = r.isCompleted
              ? Icons.check_circle_rounded
              : Icons.timer_off_rounded;
          final statusColor = r.isCompleted ? Colors.green : Colors.orange;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Navigator.push(
                  context,
                  PageTransitions.material(
                    builder: (_) => PomodoroDetailScreen(
                      record: r,
                      tags: [],
                    ),
                  ),
                );
              },
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(statusIcon, size: 18, color: statusColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${DateFormat('MM-dd HH:mm').format(startLocal)} · $durationMin 分钟',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        if (r.note != null && r.note!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            r.note!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        if (_focusRecords.length > 20)
          Text(
            '仅显示最近 20 条',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        if (_focusRecords.isNotEmpty) const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildPlanBlockSection() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KeyedSubtree(
          key: _planKey,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("计划安排",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              TextButton.icon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    PageTransitions.material(
                      builder: (_) => TodoPlanScreen(
                        username: widget.username,
                        initialDate: DateTime.now(),
                        initialTodoId: widget.todo.id,
                      ),
                    ),
                  );
                  if (!mounted) return;
                  _loadRelatedPlans();
                },
                icon: const Icon(Icons.calendar_today, size: 16),
                label: const Text("今日计划"),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
          ),
          child: _isLoadingPlans
              ? const Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _relatedPlanBlocks.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        children: [
                          Icon(Icons.event_note_outlined,
                              size: 40,
                              color: Colors.grey.withValues(alpha: 0.3)),
                          const SizedBox(height: 12),
                          const Text("暂无为此任务制定的时间计划",
                              style:
                                  TextStyle(fontSize: 13, color: Colors.grey)),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        // ── 统计摘要 ──
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                          child: _buildPlanBlockSummary(colorScheme),
                        ),
                        const Divider(height: 1),
                        // ── 规划块列表 ──
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _relatedPlanBlocks.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final plan = _relatedPlanBlocks[index];
                            final start = DateTime.fromMillisecondsSinceEpoch(
                                plan.startTime);
                            final end = DateTime.fromMillisecondsSinceEpoch(
                                plan.endTime);
                            return ListTile(
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  PageTransitions.material(
                                    builder: (_) => TodoPlanScreen(
                                      username: widget.username,
                                      initialDate: DateTime(
                                          start.year, start.month, start.day),
                                      initialTodoId: widget.todo.id,
                                    ),
                                  ),
                                );
                                _loadRelatedPlans();
                              },
                              leading: Icon(Icons.access_time_filled,
                                  color: colorScheme.primary
                                      .withValues(alpha: 0.7)),
                              title: Text(
                                "${DateFormat('MM-dd').format(start)} ${DateFormat('HH:mm').format(start)} - ${DateFormat('HH:mm').format(end)}",
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w500),
                              ),
                              subtitle: Text("预计专注 ${plan.plannedMinutes} 分钟"),
                              trailing: const Icon(Icons.chevron_right,
                                  size: 20, color: Colors.grey),
                            );
                          },
                        ),
                      ],
                    ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildPlanBlockSummary(ColorScheme colorScheme) {
    final blocks = _relatedPlanBlocks;
    final planned = blocks.fold<int>(0, (s, b) => s + b.plannedMinutes);
    final actual =
        blocks.fold<int>(0, (s, b) => s + b.actualFocusSeconds ~/ 60);
    final done = blocks
        .where((b) =>
            b.status == TodoPlanStatus.finished ||
            (b.plannedMinutes > 0 &&
                b.actualFocusSeconds >= b.plannedMinutes * 60 * 0.9))
        .length;
    final missed =
        blocks.where((b) => b.status == TodoPlanStatus.missed).length;
    final rate = planned <= 0 ? 0.0 : (actual / planned).clamp(0.0, 999.0);

    Widget chip(String label, String value, Color color) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.20)),
          ),
          child: Column(
            children: [
              Text(value,
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.w800, fontSize: 14)),
              Text(label,
                  style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                      fontSize: 10)),
            ],
          ),
        ),
      );
    }

    return Row(children: [
      chip('计划', '${planned}m', Colors.deepPurple),
      const SizedBox(width: 6),
      chip('实际', '${actual}m', Colors.green),
      const SizedBox(width: 6),
      chip('达成', '${(rate * 100).round()}%',
          Theme.of(context).colorScheme.primary),
      const SizedBox(width: 6),
      chip('完成', '$done', Colors.teal),
      const SizedBox(width: 6),
      chip('漏做', '$missed', Colors.redAccent),
    ]);
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
            border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.01),
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
                  Text(title,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface),
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
      case RecurrenceType.none:
        return "不重复";
      case RecurrenceType.daily:
        return "每天";
      case RecurrenceType.weekly:
        return "每周";
      case RecurrenceType.monthly:
        return "每月";
      case RecurrenceType.yearly:
        return "每年";
      case RecurrenceType.weekdays:
        return "工作日";
      case RecurrenceType.customDays:
        return "自定义";
    }
  }

  Widget _buildCompactTeamSection() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("完成规则",
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500)),
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
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
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
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 1))
                        ]
                      : [],
                ),
                child: Text(
                  labels[index],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurface.withValues(alpha: 0.6),
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
      PageTransitions.material(
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
              child: localImageWidget(
                imagePath,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
