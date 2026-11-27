part of 'todo_section_widget.dart';

class _TodoFixedScheduleReviewGuard {
  const _TodoFixedScheduleReviewGuard({
    required this.todoIds,
    required this.schedules,
  });

  final Set<String> todoIds;
  final List<FixedScheduleItem> schedules;
}

class TodoEditScreen extends StatefulWidget {
  final TodoItem todo;
  final List<TodoItem> todos;
  final FutureOr<void> Function(List<TodoItem>) onTodosChanged;
  final Future<TodoEditorSaveResult> Function(
    List<TodoItem>,
    Map<String, TodoItem>, {
    Map<String, Set<String>>? expectedSeriesMembership,
    Set<String>? expectedFixedScheduleTodoIds,
    List<FixedScheduleItem>? expectedFixedScheduleBaselines,
  })?
  onEditorSave;
  final FutureOr<void> Function(List<TodoGroup>, Map<String, TodoGroup>)?
  onEditorGroupsSave;
  final List<TodoGroup> todoGroups;
  final FutureOr<void> Function(List<TodoGroup>) onGroupsChanged;
  final String username;
  final TodoRecurrenceEditScope recurrenceEditScope;
  final void Function(String todoUuid)? onTodoCompletionCommitted;
  final DateTime Function() clock;

  const TodoEditScreen({
    required this.todo,
    required this.todos,
    required this.onTodosChanged,
    this.onEditorSave,
    this.onEditorGroupsSave,
    required this.todoGroups,
    required this.onGroupsChanged,
    required this.username,
    this.recurrenceEditScope = TodoRecurrenceEditScope.occurrence,
    this.onTodoCompletionCommitted,
    this.clock = DateTime.now,
    super.key,
  });
  @override
  State<TodoEditScreen> createState() => TodoEditScreenState();
}

class TodoEditScreenState extends State<TodoEditScreen> {
  DateTime get _now => widget.clock();
  final GlobalKey _planKey = GlobalKey();
  final GlobalKey _focusKey = GlobalKey();
  final GlobalKey _dataKey = GlobalKey();
  String? _verifiedEditingTodoImagePath;
  bool _showCoachMarks = false;
  bool _saving = false;
  bool _allowExit = false;
  bool _exitPromptOpen = false;
  bool _loadingEditorFields = false;
  bool _showSeriesOccurrenceDetails = false;
  late TodoItem _editingTodo;
  late List<TodoItem> _editorTodos;
  late List<TodoGroup> _editorGroups;

  TodoItem _copyTodo(TodoItem todo) => TodoItem.fromJson(todo.toJson());

  TodoGroup _copyGroup(TodoGroup group) => TodoGroup.fromJson(group.toJson());

  bool get _isWholeSeriesEdit =>
      widget.recurrenceEditScope == TodoRecurrenceEditScope.series;

  bool get _appliesToFutureOccurrences =>
      widget.recurrenceEditScope == TodoRecurrenceEditScope.future;

  int get _wholeSeriesMemberCount {
    final seriesId = TodoRecurrenceSeriesEditService.seriesIdFor(_editingTodo);
    if (seriesId == null) return 0;
    return TodoRecurrenceSeriesEditService.activeMembers(
      _editorTodos,
      seriesId,
    ).length;
  }

  String get _editorTitle => switch (widget.recurrenceEditScope) {
    TodoRecurrenceEditScope.occurrence => '编辑待办',
    TodoRecurrenceEditScope.future => '编辑后续周期',
    TodoRecurrenceEditScope.series => '编辑整个系列',
  };

  bool _hasEditingTodoImage() {
    final path = _editingTodo.imagePath;
    if (path == null || path.isEmpty) {
      _verifiedEditingTodoImagePath = null;
      return false;
    }
    if (_verifiedEditingTodoImagePath == path) return true;

    final exists = localImageExists(path);
    _verifiedEditingTodoImagePath = exists ? path : null;
    return exists;
  }

  Future<void> _checkCoachMarks() async {
    if (_showCoachMarks || !mounted) return;
    final hasSeenCoachMarks = await FeatureTipService.hasTipBeenShown(
      'coach_edit_todo',
    );
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
  String _lastObservedTitle = '';
  String _lastObservedRemark = '';
  String _lastObservedCustomDays = '';
  bool? _lastCanPop;
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
  Map<String, Team> _teamsByUuid = const {};
  List<TodoGroup> _availableGroups = const [];
  Map<String, TodoGroup> _availableGroupsById = const {};
  String? _selectedTeamUuid;
  int _collabType = 0;
  bool _syncFolderToTeam = false;
  List<TodoPlanBlock> _relatedPlanBlocks = [];
  bool _isLoadingPlans = true;
  List<PomodoroRecord> _focusRecords = [];
  int _totalFocusSeconds = 0;
  int _focusedPeriodCount = 0;
  bool _isLoadingRecords = true;

  void _mutateState(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    _editorTodos = widget.todos.map(_copyTodo).toList();
    _editorGroups = widget.todoGroups.map(_copyGroup).toList();
    _rebuildAvailableGroupIndex();
    _editingTodo = _editorTodos.firstWhere(
      (todo) => todo.id == widget.todo.id,
      orElse: () => _copyTodo(widget.todo),
    );
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
    _createdDate = AppTimeFormats.localFromServerTimestamp(
      t.createdDate ?? t.createdAt,
    );
    _originalCreatedDate = _createdDate;
    _dueDate = t.dueDate;
    _recurrence = t.recurrence;
    _customDays = t.customIntervalDays;
    _customDaysCtrl = TextEditingController(
      text: _customDays?.toString() ?? '',
    );
    _lastObservedTitle = _titleCtrl.text;
    _lastObservedRemark = _remarkCtrl.text;
    _lastObservedCustomDays = _customDaysCtrl.text;
    _titleCtrl.addListener(_onEditorInputChanged);
    _remarkCtrl.addListener(_onEditorInputChanged);
    _customDaysCtrl.addListener(_onEditorInputChanged);
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

  @override
  void didUpdateWidget(covariant TodoEditScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.todoGroups, widget.todoGroups)) {
      _rebuildAvailableGroupIndex();
    }
  }

  void _rebuildAvailableGroupIndex() {
    final groupsById = <String, TodoGroup>{};
    for (final group in _editorGroups) {
      if (group.id.isNotEmpty) groupsById[group.id] = group;
    }
    _availableGroupsById = groupsById;
    _availableGroups = groupsById.values.toList(growable: false);
  }

  Future<void> _loadFocusRecords() async {
    if (!mounted) return;
    final editingTodoId = _editingTodo.id;
    final todoIds = _focusRecordTodoIds(_editingTodo, _editorTodos);
    final records = await PomodoroService.getRecordsByTodoUuids(todoIds);
    if (!mounted || _editingTodo.id != editingTodoId) return;
    final focusedPeriodCount = _focusedRecurrencePeriodCount(
      _editingTodo,
      _editorTodos,
      records,
    );
    final totalFocusSeconds = PomodoroService.totalFocusSeconds(records);
    setState(() {
      _focusRecords = records;
      _totalFocusSeconds = totalFocusSeconds;
      _focusedPeriodCount = focusedPeriodCount;
      _isLoadingRecords = false;
    });
  }

  Future<void> _loadRelatedPlans() async {
    if (!mounted) return;
    final editingTodoId = _editingTodo.id;
    setState(() => _isLoadingPlans = true);
    final username = await StorageService.getLoginSession() ?? 'default';
    final plans = await StorageService.getPlanBlocksByTodo(
      username,
      editingTodoId,
    );
    if (!mounted || _editingTodo.id != editingTodoId) return;
    setState(() {
      _relatedPlanBlocks = plans.where((p) => !p.isDeleted).toList();
      _isLoadingPlans = false;
    });
  }

  Future<void> _loadTeams() async {
    final rawTeams = await ApiService.fetchTeams();
    if (mounted) {
      final teams = rawTeams.map((t) => Team.fromJson(t)).toList();
      final teamsByUuid = <String, Team>{};
      for (final team in teams) {
        teamsByUuid.putIfAbsent(team.uuid, () => team);
      }
      setState(() {
        _teams = teams;
        _teamsByUuid = teamsByUuid;
      });
    }
  }

  Future<void> _loadCategoryDefaults() async {
    final username = await StorageService.getLoginSession();
    if (username != null) {
      final defaults = await StorageService.getCategoryReminderMinutes(
        username,
      );
      if (!mounted) return;
      setState(() {
        _categoryReminderDefaults = defaults;
      });
    }
  }

  @override
  void dispose() {
    _titleCtrl.removeListener(_onEditorInputChanged);
    _remarkCtrl.removeListener(_onEditorInputChanged);
    _customDaysCtrl.removeListener(_onEditorInputChanged);
    _titleCtrl.dispose();
    _remarkCtrl.dispose();
    _customDaysCtrl.dispose();
    super.dispose();
  }

  void _onEditorInputChanged() {
    if (!mounted || _loadingEditorFields) return;
    final titleText = _titleCtrl.text;
    final remarkText = _remarkCtrl.text;
    final customDaysText = _customDaysCtrl.text;
    if (titleText == _lastObservedTitle &&
        remarkText == _lastObservedRemark &&
        customDaysText == _lastObservedCustomDays) {
      return;
    }
    _lastObservedTitle = titleText;
    _lastObservedRemark = remarkText;
    _lastObservedCustomDays = customDaysText;
    final canPop = _allowExit || (!_saving && !_hasUnsavedChanges);
    if (canPop != _lastCanPop) {
      setState(() {});
    }
  }

  Widget _exitProtected(Widget child) {
    final canPop = _allowExit || (!_saving && !_hasUnsavedChanges);
    _lastCanPop = canPop;
    return PopScope<Object?>(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_requestExit());
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bgColor = theme.brightness == Brightness.light
        ? const Color(0xFFF2F2F7)
        : theme.colorScheme.surface;
    final topBarHeight = floatingGlassTopBarHeight(context);

    final availableGroups = _availableGroups;
    final selectedGroupId = _selectedGroupId;
    final effectiveGroupId =
        selectedGroupId != null &&
            _availableGroupsById.containsKey(selectedGroupId)
        ? selectedGroupId
        : null;

    return _exitProtected(
      Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: bgColor,
        appBar: FloatingGlassAppBar(
          flexibleSpace: const FloatingGlassTopBarBackground(),
          title: Text(_isWholeSeriesEdit ? '编辑系列' : _editorTitle),
          backgroundColor: bgColor,
          elevation: 0,
          scrolledUnderElevation: 0,
          actions: [
            IconButton(
              onPressed: _saving ? null : _deleteCurrentTodo,
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.redAccent,
              ),
              tooltip: _isWholeSeriesEdit ? '删除当前期' : '删除待办',
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
              onPressed: _saving ? null : _save,
              child: Text(
                _saving
                    ? '保存中…'
                    : _isWholeSeriesEdit
                    ? '应用到 $_wholeSeriesMemberCount 期'
                    : '保存',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: _isWholeSeriesEdit ? 720 : double.infinity,
            ),
            child: FloatingGlassTopBarContentFade(
              topBarHeight: topBarHeight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(16, topBarHeight + 8, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.recurrenceEditScope !=
                          TodoRecurrenceEditScope.occurrence) ...[
                        _buildRecurrenceScopeSummary(colorScheme),
                        const SizedBox(height: 12),
                      ],
                      if (!_isWholeSeriesEdit)
                        _buildRelatedRecurrenceSection(colorScheme),
                      OptionalLiquidGlassCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        borderRadius: 24,
                        highContrast: true,
                        fallbackDecoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.01),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            TextField(
                              controller: _titleCtrl,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: const InputDecoration(
                                hintText: "待办内容",
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                                isCollapsed: true,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                              ),
                            ),
                            Divider(
                              height: 1,
                              thickness: 0.8,
                              color: colorScheme.outlineVariant.withValues(
                                alpha: 0.35,
                              ),
                            ),
                            TextField(
                              controller: _remarkCtrl,
                              maxLines: 3,
                              minLines: 1,
                              style: const TextStyle(fontSize: 15),
                              decoration: InputDecoration(
                                hintText: "备注 (可选)",
                                hintStyle: TextStyle(
                                  color: Colors.grey.withValues(alpha: 0.8),
                                ),
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                                isCollapsed: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                              ),
                            ),
                            Divider(
                              height: 1,
                              thickness: 0.8,
                              color: colorScheme.outlineVariant.withValues(
                                alpha: 0.35,
                              ),
                            ),
                            if (!_isWholeSeriesEdit)
                              LiquidGlassSwitchListTile(
                                key: const ValueKey(
                                  'todo_edit_completion_switch',
                                ),
                                contentPadding: EdgeInsets.zero,
                                value: _isDone,
                                onChanged: (value) =>
                                    setState(() => _isDone = value),
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
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          const Text(
                            "时间与提醒",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Row(
                            children: [
                              const Text(
                                "某天内完成",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(width: 6),
                              SizedBox(
                                height: 24,
                                child: LiquidGlassSwitch(
                                  height: 24,
                                  value: _isAllDay,
                                  onChanged: (val) {
                                    setState(() {
                                      final wasDateOnlyRange =
                                          _dueDate != null &&
                                          TodoItem.looksLikeLegacyDateOnlyRange(
                                            _createdDate,
                                            _dueDate!,
                                          );
                                      _isAllDay = val;
                                      if (_isAllDay) {
                                        _preserveLegacyTiming = false;
                                        _createdDate = DateTime(
                                          _createdDate.year,
                                          _createdDate.month,
                                          _createdDate.day,
                                          0,
                                          0,
                                        );
                                        _dueDate = _dueDate != null
                                            ? DateTime(
                                                _dueDate!.year,
                                                _dueDate!.month,
                                                _dueDate!.day,
                                                23,
                                                59,
                                              )
                                            : DateTime(
                                                _createdDate.year,
                                                _createdDate.month,
                                                _createdDate.day,
                                                23,
                                                59,
                                              );
                                      } else if (wasDateOnlyRange) {
                                        final now = _now;
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
                            color: colorScheme.secondaryContainer.withValues(
                              alpha: 0.45,
                            ),
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
                                subtitle: AppTimeFormats.dateFormatter('MM-dd')
                                    .format(_createdDate),
                                icon: Icons.event_available_rounded,
                                color: Theme.of(context).colorScheme.secondary,
                                onTap: () async {
                                  final pickedDate = await showAppDatePicker(
                                    context: context,
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2100),
                                    initialDate: _createdDate,
                                  );
                                  if (!context.mounted || pickedDate == null) {
                                    return;
                                  }
                                  if (_isAllDay) {
                                    setState(() {
                                      _createdDate = CalendarDateMath.dateOnly(
                                        pickedDate,
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
                                    final pickedTime = await showAppTimePicker(
                                      context: context,
                                      initialTime: TimeOfDay.fromDateTime(
                                        _createdDate,
                                      ),
                                    );
                                    if (!mounted || pickedTime == null) return;
                                    setState(
                                      () => _createdDate = DateTime(
                                        pickedDate.year,
                                        pickedDate.month,
                                        pickedDate.day,
                                        pickedTime.hour,
                                        pickedTime.minute,
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                          if (_preserveLegacyTiming && !_isAllDay) ...[
                            Expanded(
                              child: _buildSquareTile(
                                title: "开始时间",
                                subtitle: AppTimeFormats.dateFormatter(
                                  'MM-dd HH:mm',
                                ).format(_createdDate),
                                icon: Icons.play_circle_outline_rounded,
                                color: colorScheme.primary,
                                onTap: () async {
                                  final pickedDate = await showAppDatePicker(
                                    context: context,
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2100),
                                    initialDate: _createdDate,
                                  );
                                  if (!context.mounted || pickedDate == null) {
                                    return;
                                  }
                                  final pickedTime = await showAppTimePicker(
                                    context: context,
                                    initialTime: TimeOfDay.fromDateTime(
                                      _createdDate,
                                    ),
                                  );
                                  if (!mounted || pickedTime == null) return;
                                  setState(
                                    () => _createdDate = DateTime(
                                      pickedDate.year,
                                      pickedDate.month,
                                      pickedDate.day,
                                      pickedTime.hour,
                                      pickedTime.minute,
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          if (!_isAllDay)
                            Expanded(
                              child: _buildSquareTile(
                                title: _preserveLegacyTiming ? "结束时间" : "截止时间",
                                subtitle: _dueDate == null
                                    ? (_preserveLegacyTiming ? "结束时间待定" : "未安排")
                                    : _preserveLegacyTiming
                                    ? AppTimeFormats.dateFormatter(
                                        'MM-dd HH:mm',
                                      ).format(_dueDate!)
                                    : "${AppTimeFormats.dateFormatter('MM-dd HH:mm').format(_dueDate!)} 前完成",
                                icon: _preserveLegacyTiming
                                    ? Icons.stop_circle_outlined
                                    : Icons.flag_rounded,
                                color: Colors.deepOrangeAccent,
                                onTap: () async {
                                  final pickedDate = await showAppDatePicker(
                                    context: context,
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2100),
                                    initialDate: _dueDate ?? _createdDate,
                                  );
                                  if (!context.mounted || pickedDate == null) {
                                    return;
                                  }
                                  if (_isAllDay) {
                                    setState(
                                      () => _dueDate = DateTime(
                                        pickedDate.year,
                                        pickedDate.month,
                                        pickedDate.day,
                                        23,
                                        59,
                                      ),
                                    );
                                  } else {
                                    final pickedTime = await showAppTimePicker(
                                      context: context,
                                      initialTime: TimeOfDay.fromDateTime(
                                        _dueDate ?? _now,
                                      ),
                                    );
                                    if (!mounted || pickedTime == null) return;
                                    setState(
                                      () => _dueDate = DateTime(
                                        pickedDate.year,
                                        pickedDate.month,
                                        pickedDate.day,
                                        pickedTime.hour,
                                        pickedTime.minute,
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                        ],
                      ),
                      if (!_isAllDay &&
                          (_dueDate != null || _preserveLegacyTiming))
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => setState(() {
                              _dueDate = null;
                              _preserveLegacyTiming = false;
                            }),
                            icon: const Icon(
                              Icons.event_busy_outlined,
                              size: 16,
                            ),
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
                                  .map(
                                    (m) => PopupMenuItem(
                                      value: m,
                                      child: Text(_getReminderText(m)),
                                    ),
                                  )
                                  .toList(),
                              onSelected: (val) =>
                                  setState(() => _reminderMinutes = val),
                            ),
                          ),
                          if (!_isWholeSeriesEdit) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildPopupSquareTile<RecurrenceType>(
                                title: '重复',
                                subtitle: _getRecurrenceLabel(_recurrence),
                                icon: Icons.replay_rounded,
                                color: colorScheme.tertiary,
                                value: _recurrence,
                                items:
                                    [
                                          RecurrenceType.none,
                                          RecurrenceType.daily,
                                          RecurrenceType.weekly,
                                          RecurrenceType.monthly,
                                          RecurrenceType.yearly,
                                          RecurrenceType.weekdays,
                                          RecurrenceType.customDays,
                                        ]
                                        .map(
                                          (recurrence) => PopupMenuItem(
                                            value: recurrence,
                                            child: Text(
                                              _getRecurrenceLabel(recurrence),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                onSelected: (value) =>
                                    setState(() => _recurrence = value),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (_isWholeSeriesEdit)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Row(
                            children: [
                              Icon(
                                Icons.repeat_rounded,
                                size: 18,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${_getRecurrenceLabel(_recurrence)} · 整个系列编辑不改重复规则，调整规则请选择“本期及以后”',
                                  key: const ValueKey(
                                    'series_locked_recurrence_rule',
                                  ),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_recurrence != RecurrenceType.none &&
                          !_isWholeSeriesEdit)
                        OptionalLiquidGlassCard(
                          margin: const EdgeInsets.only(top: 12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          borderRadius: 16,
                          highContrast: true,
                          fallbackDecoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.04),
                            ),
                          ),
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
                                              const EdgeInsets.symmetric(
                                                vertical: 8,
                                              ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                        ),
                                        onChanged: (val) => setState(
                                          () => _customDays = int.tryParse(val),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Text("天重复"),
                                  ],
                                ),
                                const Divider(height: 24),
                              ],
                              InkWell(
                                onTap: () async {
                                  final picked = await showAppDatePicker(
                                    context: context,
                                    // 循环结束日期是系列规则，不是当前实例的截止时间；
                                    // 允许把规则结束日期回调到今天之前。
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2100),
                                    initialDate:
                                        _recurrenceEndDate ??
                                        _now.add(const Duration(days: 30)),
                                  );
                                  if (picked != null) {
                                    setState(() => _recurrenceEndDate = picked);
                                  }
                                },
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text("重复结束日期"),
                                    Row(
                                      children: [
                                        Text(
                                          _recurrenceEndDate == null
                                              ? "未指定"
                                              : AppTimeFormats.dateFormatter(
                                                  'yyyy-MM-dd',
                                                ).format(_recurrenceEndDate!),
                                          style: TextStyle(
                                            color: _recurrenceEndDate == null
                                                ? Colors.grey
                                                : colorScheme.primary,
                                          ),
                                        ),
                                        const Icon(
                                          Icons.chevron_right,
                                          color: Colors.grey,
                                          size: 20,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 24),
                      if (availableGroups.isNotEmpty || _teams.isNotEmpty) ...[
                        const Text(
                          "组织与协作",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            if (availableGroups.isNotEmpty)
                              Expanded(
                                child: _buildSquareTile(
                                  title: "归属文件夹",
                                  subtitle: effectiveGroupId == null
                                      ? "未分类"
                                      : (_availableGroupsById[effectiveGroupId]
                                                ?.name ??
                                            '未知'),
                                  icon: Icons.folder_rounded,
                                  color: Colors.amber.shade600,
                                  onTap: () async {
                                    FocusManager.instance.primaryFocus
                                        ?.unfocus();
                                    final result =
                                        await showTodoGroupPickerSheet(
                                          context: context,
                                          groups: availableGroups,
                                          selectedGroupId: effectiveGroupId,
                                        );
                                    if (!mounted || result == null) return;
                                    setState(() {
                                      _selectedGroupId = result.groupId;
                                      if (_selectedGroupId != null &&
                                          _categoryReminderDefaults.containsKey(
                                            _selectedGroupId,
                                          )) {
                                        _reminderMinutes =
                                            _categoryReminderDefaults[_selectedGroupId]!;
                                      } else if (_selectedGroupId == null) {
                                        _reminderMinutes = 5;
                                      }
                                    });
                                  },
                                ),
                              ),
                            if (availableGroups.isNotEmpty && _teams.isNotEmpty)
                              const SizedBox(width: 12),
                            if (_teams.isNotEmpty)
                              Expanded(
                                child: _buildPopupSquareTile<String>(
                                  title: "团队归属",
                                  subtitle: _selectedTeamUuid == null
                                      ? "个人私有"
                                      : (_teamsByUuid[_selectedTeamUuid]
                                                ?.name ??
                                            '未知'),
                                  icon: Icons.groups_rounded,
                                  color: Colors.indigoAccent,
                                  value: _selectedTeamUuid ?? "__none__",
                                  items: [
                                    const PopupMenuItem<String>(
                                      value: "__none__",
                                      child: Text("个人私有 (仅自己可见)"),
                                    ),
                                    ..._teams.map(
                                      (t) => PopupMenuItem(
                                        value: t.uuid,
                                        child: Text(t.name),
                                      ),
                                    ),
                                  ],
                                  onSelected: (v) => setState(
                                    () => _selectedTeamUuid = v == "__none__"
                                        ? null
                                        : v,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (_selectedTeamUuid != null)
                          _buildCompactTeamSection(),
                        const SizedBox(height: 12),
                        if (_selectedTeamUuid != null &&
                            effectiveGroupId != null)
                          Builder(
                            builder: (context) {
                              final folder =
                                  _availableGroupsById[effectiveGroupId];
                              if (folder != null &&
                                  folder.teamUuid != _selectedTeamUuid) {
                                return Padding(
                                  padding: const EdgeInsets.only(
                                    top: 8.0,
                                    left: 4.0,
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: Checkbox(
                                          value: _syncFolderToTeam,
                                          onChanged: (val) => setState(
                                            () => _syncFolderToTeam =
                                                val ?? false,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          "将文件夹 '${folder.name}' 也同步到团队，方便队友查看分类",
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: colorScheme.primary,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        const SizedBox(height: 24),
                      ],
                      _buildPlanBlockSection(),
                      _buildFocusRecordsSection(),
                      if (_editingTodo.imagePath != null ||
                          (_editingTodo.originalText != null &&
                              _editingTodo.originalText!.isNotEmpty)) ...[
                        const Text(
                          "原始分析来源",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_hasEditingTodoImage())
                          GestureDetector(
                            onTap: () => _showFullImage(
                              context,
                              _editingTodo.imagePath!,
                            ),
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
                              ),
                            ),
                          ),
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
                                color: Colors.black.withValues(alpha: 0.04),
                              ),
                            ),
                            child: Text(
                              _editingTodo.originalText!,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                      ],
                      const SizedBox(height: 12),
                      KeyedSubtree(
                        key: _dataKey,
                        child: const Text(
                          "数据存证",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.04),
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => VersionHistorySheet.show(
                              context,
                              _editingTodo.id,
                              'todos',
                              _editingTodo.title,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.history_rounded,
                                    color: colorScheme.primary,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "版本记录与回滚",
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14.5,
                                          ),
                                        ),
                                        Text(
                                          "追踪修改历史，支持一键恢复至旧版本",
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    color: Colors.grey.withValues(alpha: 0.5),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 60),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @visibleForTesting
  static List<TodoItem> relatedRecurrenceOccurrencesForTest(
    TodoItem current,
    List<TodoItem> todos,
  ) => _relatedRecurrenceOccurrences(current, todos);

  @visibleForTesting
  static Set<String> focusRecordTodoIdsForTest(
    TodoItem current,
    List<TodoItem> todos,
  ) => _focusRecordTodoIds(current, todos);

  @visibleForTesting
  static int focusedRecurrencePeriodCountForTest(
    TodoItem current,
    List<TodoItem> todos,
    List<PomodoroRecord> records,
  ) => _focusedRecurrencePeriodCount(current, todos, records);
}
