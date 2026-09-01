part of 'home_dashboard.dart';
// ignore_for_file: annotate_overrides

mixin _HomeDashboardNavigationMixin on _HomeDashboardStateBase {
  Future<void> _checkExactAlarmPermission() async {
    final granted = await NotificationService.checkExactAlarmPermission();
    if (granted) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('⏰ 需要「精确闹钟」权限才能在 App 被杀后准时发送提醒'),
        action: SnackBarAction(
          label: '去授权',
          onPressed: () async {
            await _permissionCoordinator.request(
              AppPermissionKind.exactAlarm,
            );
          },
        ),
        duration: const Duration(seconds: 8),
      ),
    );
  }

  /// 导航到待办确认页面
  Future<dynamic> _navigateToTodoConfirm(List<Map<String, dynamic>> results,
      String? imagePath, String? originalText,
      [String? teamUuid, String? teamName]) async {
    if (!mounted || results.isEmpty) return null;

    return Navigator.push(
      context,
      PageTransitions.slideHorizontal(TodoConfirmScreen(
        llmResults: results,
        imagePath: imagePath,
        originalText: originalText,
        initialTeamUuid: teamUuid,
        initialTeamName: teamName,
        onFixedScheduleAdded: (item) async {
          await StorageService.saveFixedSchedules(
            widget.username,
            [item],
          );
          if (!mounted) return;
          _scheduleRevision.value++;
          _timelineRevision.value++;
          await _loadAllData(
            deferred: true,
            domains: const {DataRefreshDomain.fixedSchedules},
          );
          if (_pendingTodoConfirm != null) {
            setState(() => _pendingTodoConfirm = null);
            ExternalShareHandler.clearPendingTodoConfirm();
          }
        },
        onConfirm: (confirmedResults) {
          // 用户确认后，直接批量添加待办
          _batchAddTodos(confirmedResults, teamUuid, teamName);
          // 清除待确认数据（如果有）
          if (_pendingTodoConfirm != null) {
            setState(() => _pendingTodoConfirm = null);
            ExternalShareHandler.clearPendingTodoConfirm();
          }
        },
        onSkip: () {
          // 用户跳过全部待办，清除待确认数据
          if (_pendingTodoConfirm != null) {
            setState(() => _pendingTodoConfirm = null);
            ExternalShareHandler.clearPendingTodoConfirm();
          }
        },
      )),
    );
  }

  Future<void> _openRecognizedFinanceDrafts(
    List<FinanceEntryDraft> drafts,
  ) async {
    if (drafts.isEmpty) return;
    var savedCount = 0;
    for (final draft in drafts) {
      if (!mounted) return;
      final saved = await Navigator.of(context).push<FinanceTransaction>(
        PageTransitions.slideHorizontal(
          FinanceEntryScreen(initialDraft: draft),
        ),
      );
      if (saved != null) {
        draft.isAdded = true;
        savedCount++;
      } else {
        draft.isIgnored = true;
      }
    }
    await ExternalShareHandler.clearPendingFinanceRecognized();
    if (mounted && savedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存 $savedCount 笔识别账单')),
      );
    }
  }

  /// 批量添加待办 (支持团队上下文关联)
  Future<void> _batchAddTodos(List<Map<String, dynamic>> todosData,
      [String? teamUuid, String? teamName]) async {
    if (todosData.isEmpty) return;

    RecurrenceType parseRecurrence(dynamic value) {
      final index =
          value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
      if (index != null && index >= 0 && index < RecurrenceType.values.length) {
        return RecurrenceType.values[index];
      }
      final name = value?.toString();
      return RecurrenceType.values.firstWhere(
        (type) => type.name == name,
        orElse: () => RecurrenceType.none,
      );
    }

    int? parseInt(dynamic value) {
      return JsonValueParser.toNullableInt(value);
    }

    final newTodos = todosData.map((data) {
      final selectedDate = RecognizedTodoAdapter.parseDateTime(
        data['startTime'] ??
            data['start_time'] ??
            data['createdDate'] ??
            data['created_date'],
      );
      final parsedDueDate = RecognizedTodoAdapter.parseDateTime(
        data['endTime'] ??
            data['end_time'] ??
            data['dueDate'] ??
            data['due_date'],
      );
      final timeMode = RecognizedTodoAdapter.parseTimeMode(
        data['timeMode'] ?? data['time_mode'],
      );
      final isDateOnly = RecognizedTodoAdapter.parseBool(
            data['isAllDay'] ?? data['is_all_day'],
          ) ||
          timeMode == TodoTimeMode.dateOnly ||
          (selectedDate != null &&
              parsedDueDate != null &&
              TodoItem.looksLikeLegacyDateOnlyRange(
                selectedDate,
                parsedDueDate,
              ));
      final dueDate = parsedDueDate ??
          (timeMode == TodoTimeMode.deadline ? selectedDate : null);

      final normalizedTime = TodoItem.normalizeTimeForWrite(
        selectedDate: selectedDate,
        dueDate: dueDate,
        isDateOnly: isDateOnly,
      );

      return TodoItem(
        title: data['title']?.toString() ?? data['content']?.toString() ?? '',
        remark: (data['remark'] ?? data['notes'] ?? data['note'])?.toString(),
        dueDate: normalizedTime.due,
        createdDate: normalizedTime.start?.toUtc().millisecondsSinceEpoch,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        recurrence: parseRecurrence(data['recurrence']),
        customIntervalDays: parseInt(
            data['customIntervalDays'] ?? data['custom_interval_days']),
        recurrenceEndDate: RecognizedTodoAdapter.parseDateTime(
          data['recurrence_end_date'] ?? data['recurrenceEndDate'],
        ),
        // 📸 关联图片路径（兼容确认页与存储层两种字段名）
        imagePath: (data['imagePath'] ?? data['image_path'])?.toString(),
        // 📄 原始分析文本
        originalText:
            (data['originalText'] ?? data['original_text'])?.toString(),
        teamUuid: (data['team_uuid'] ?? data['teamUuid'] ?? teamUuid)
            ?.toString(), // 🚀 关联团队
        teamName: (data['team_name'] ?? data['teamName'] ?? teamName)
            ?.toString(), // 🚀 团队名称
        groupId: (data['groupId'] ?? data['group_id'])?.toString(),
        reminderMinutes:
            parseInt(data['reminderMinutes'] ?? data['reminder_minutes']),
        collabType: parseInt(data['collab_type'] ?? data['collabType']) ?? 0,
        isAllDay: isDateOnly,
      );
    }).toList();

    // 更新局部卡片，避免为批量添加待办重建整个首页。
    _todos = [...newTodos, ..._todos];
    _todosNotifier.value = List<TodoItem>.from(_todos);
    _todoUpdateSignalNotifier.value++;
    _timelineRevision.value++;
    _pomodoroTickNotifier.value++;

    // 保存到数据库
    final allTodos = await StorageService.getTodos(widget.username);
    for (var newT in newTodos) {
      int idx = allTodos.indexWhere((x) => x.id == newT.id);
      if (idx != -1) {
        allTodos[idx] = newT;
      } else {
        allTodos.add(newT);
      }
    }
    await StorageService.saveTodos(widget.username, allTodos);

    // 将待办数据写入共享文件供 Island 读取
    await _saveTodosToSharedFile(allTodos);

    // 通知 Island 检查提醒并刷新槽位缓存
    FloatWindowService.triggerReminderCheck();
    FloatWindowService.invalidateSlotCache();
    _syncTodoNotification();
    await WidgetService.updateTodoWidget(_todos);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已添加 ${newTodos.length} 个待办'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// 检查是否有待确认的事项数据（从通知点击进入）
  Future<void> _checkPendingTodoConfirm() async {
    // App 进程重启后没有任务实例可以继续处理旧的 processing 状态，
    // 先把这类中断任务收口为失败，避免首页永久显示加载圈。
    await ExternalShareHandler.recoverInterruptedTodoRecognition();
    var pendingData = await ExternalShareHandler.getPendingTodoConfirm();
    if (!mounted) return;

    if (pendingData != null) {
      final rawFinanceResults = pendingData['financeResults'];
      final financeDrafts = rawFinanceResults is List
          ? rawFinanceResults
              .whereType<Map>()
              .map((item) =>
                  FinanceEntryDraft.fromJson(Map<String, dynamic>.from(item)))
              .where((draft) => !draft.isAdded && !draft.isIgnored)
              .toList()
          : const <FinanceEntryDraft>[];
      if (financeDrafts.isNotEmpty && !_isOpeningPendingFinance) {
        _isOpeningPendingFinance = true;
        try {
          await _openRecognizedFinanceDrafts(financeDrafts);
        } finally {
          _isOpeningPendingFinance = false;
        }
        pendingData = await ExternalShareHandler.getPendingTodoConfirm();
        if (!mounted) return;
        if (pendingData == null) return;
      }

      final imagePath = pendingData['imagePath'] as String?;
      final status = pendingData['status'] as String? ?? 'success';
      final results = pendingData['results'] as List<dynamic>?;
      // 只要有 imagePath 就显示卡片（支持 processing/retrying/failed/success 状态）
      if (imagePath != null &&
          (status != 'success' || (results?.isNotEmpty ?? false))) {
        // 保存待确认数据，显示入口卡片
        setState(() {
          _pendingTodoConfirm = pendingData;
        });
        return;
      }
    }

    // 没有待确认数据，清除状态
    setState(() {
      _pendingTodoConfirm = null;
    });
  }

  /// 显示全屏图片预览（针对分析产生的图片）
  void _showAnalysisImage(String imagePath) {
    Navigator.of(context).push(
      PageTransitions.material(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: FloatingGlassAppBar(
            flexibleSpace: const FloatingGlassTopBarBackground(),
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text("原本分析图片"),
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

  /// 显示原始分析文本对话框
  void _showOriginalText(String text) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("分析原始文字"),
        content: SingleChildScrollView(
          child: SelectableText(
            text,
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("确定"),
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  /// 将已有的 PomodoroScreen 带到前台，或 push 新的。
  /// 用 remove + push 代替 popUntil，避免破坏栈中其他路由。
  void _navigateToPomodoro() {
    if (!mounted || _navigatingToPomodoro) return;
    // 🚀 去重：如果已在番茄钟页，直接返回
    if (_pomodoroRoute != null && _pomodoroRoute!.isCurrent) return;
    // 🚀 时间戳防抖：500ms 内不重复导航
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastPomodoroNavigateMs < 500) return;
    _lastPomodoroNavigateMs = now;

    final nav = Navigator.of(context);

    if (_pomodoroRoute != null) {
      // 已有番茄钟页但被其他页面盖住：remove 后重新 push 到顶部
      try {
        nav.removeRoute(_pomodoroRoute!);
      } catch (_) {
        // route 已被 pop（如用户手动返回），清除引用
      }
      _pomodoroRoute = null;
    }

    // push 新的番茄钟页
    _navigatingToPomodoro = true;
    final route = PageTransitions.material(
      builder: (_) => PomodoroScreen(username: widget.username),
      settings: const RouteSettings(name: 'pomodoro'),
    );
    _pomodoroRoute = route;
    nav.push(route).whenComplete(() {
      _navigatingToPomodoro = false;
      // 如果是被用户手动 pop 的（不是 removeRoute），清除引用
      if (_pomodoroRoute == route) _pomodoroRoute = null;
    });
  }

  Future<void> _handleMacIslandCommand(MacIslandCommand command) async {
    if (!mounted) return;
    switch (command.type) {
      case MacIslandCommandType.openEntity:
        await _openIslandEntity(command.entityKind, command.entityId);
      case MacIslandCommandType.startFocus:
        await _startIslandEntityFocus(command.entityKind, command.entityId);
      case MacIslandCommandType.completeTodo:
        await _completeIslandTodo(command.entityId);
    }
  }

  Future<void> _openIslandEntity(String kind, String id) async {
    if (kind == 'todo') {
      final todo = await _findIslandTodo(id);
      if (todo == null || !mounted) return;
      await Navigator.of(context).push(
        PageTransitions.slideHorizontal(TodoDetailScreen(todo: todo)),
      );
      return;
    }

    if (kind == 'plan_block') {
      final block = await _findIslandPlanBlock(id);
      if (!mounted) return;
      await Navigator.of(context).push(
        PageTransitions.material(
          builder: (_) => TodoPlanScreen(
            username: widget.username,
            initialDate: block == null
                ? DateTime.now()
                : DateTime.fromMillisecondsSinceEpoch(block.startTime),
            initialTodoId: block?.todoId,
          ),
        ),
      );
      return;
    }

    if (kind == 'course') {
      final course = await _findIslandCourse(id);
      if (course == null || !mounted) return;
      await Navigator.of(context).push(
        PageTransitions.slideHorizontal(CourseDetailScreen(course: course)),
      );
      return;
    }

    if (kind == 'fixed_schedule') {
      final item = await _findIslandFixedSchedule(id);
      if (item == null || !mounted) return;
      await Navigator.of(context).push(
        PageTransitions.material(
          builder: (_) => FixedScheduleEditorScreen(
            username: widget.username,
            item: item,
          ),
        ),
      );
      if (!mounted) return;
      _scheduleRevision.value++;
      _timelineRevision.value++;
      return;
    }

    _navigateToPomodoro();
  }

  Future<void> _startIslandEntityFocus(String kind, String id) async {
    final running = await PomodoroService.loadRunState();
    if (running != null &&
        (running.phase == PomodoroPhase.focusing ||
            running.phase == PomodoroPhase.breaking)) {
      _navigateToPomodoro();
      return;
    }

    if (kind == 'plan_block') {
      final block = await _findIslandPlanBlock(id);
      if (block != null) await _startPlanBlockFocus(block);
      return;
    }
    if (kind != 'todo') return;

    final todo = await _findIslandTodo(id);
    if (todo == null || todo.isDone || todo.isDeleted) return;
    try {
      final settings = await PomodoroService.getSettings();
      await PomodoroControlService.startFocus(
        settings: settings,
        boundTodo: todo,
      );
      if (!mounted) return;
      _pomodoroRevision.value++;
      _navigateToPomodoro();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('启动专注失败: $e')),
      );
    }
  }

  Future<void> _completeIslandTodo(String id) async {
    final todo = await _findIslandTodo(id);
    if (todo == null || todo.isDone || todo.isDeleted) return;

    final running = await PomodoroService.loadRunState();
    if (running != null &&
        running.todoUuid == id &&
        (running.phase == PomodoroPhase.focusing ||
            running.phase == PomodoroPhase.breaking)) {
      await PomodoroControlService.stopCurrentFocus(
        username: widget.username,
        status: PomodoroRecordStatus.completed,
        markTodoComplete: true,
      );
    } else {
      todo.isDone = true;
      todo.markAsChanged();
      await StorageService.updateSingleTodo(widget.username, todo);
    }

    if (!mounted) return;
    todo.isDone = true;
    _todos.sort((a, b) => a.isDone == b.isDone ? 0 : (a.isDone ? 1 : -1));
    _todosNotifier.value = List<TodoItem>.from(_todos);
    _todoUpdateSignalNotifier.value++;
    _timelineRevision.value++;
    _pomodoroRevision.value++;
    _pomodoroTickNotifier.value++;
    unawaited(_loadAllData(domains: const {DataRefreshDomain.todos}));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已完成：${todo.title}')),
    );
  }

  Future<TodoItem?> _findIslandTodo(String id) async {
    for (final todo in _todos) {
      if (todo.id == id && !todo.isDeleted) return todo;
    }
    final todos = await StorageService.getTodos(widget.username);
    for (final todo in todos) {
      if (todo.id == id && !todo.isDeleted) return todo;
    }
    return null;
  }

  Future<TodoPlanBlock?> _findIslandPlanBlock(String id) async {
    for (final block in _planBlocks) {
      if (block.id == id && !block.isDeleted) return block;
    }
    final blocks = await StorageService.getPlanBlocks(widget.username);
    for (final block in blocks) {
      if (block.id == id && !block.isDeleted) return block;
    }
    return null;
  }

  Future<CourseItem?> _findIslandCourse(String id) async {
    final dashboardCourses =
        _safeListResult<CourseItem>(_dashboardCourseData['courses']);
    for (final course in dashboardCourses) {
      if (course.uuid == id && !course.isDeleted) return course;
    }
    final courses = await CourseService.getAllCourses(widget.username);
    for (final course in courses) {
      if (course.uuid == id && !course.isDeleted) return course;
    }
    return null;
  }

  Future<FixedScheduleItem?> _findIslandFixedSchedule(String id) async {
    final items = await StorageService.getFixedSchedules(widget.username);
    for (final item in items) {
      if (item.id == id && !item.isDeleted) return item;
    }
    return null;
  }

  /// 处理 App Shortcut 导航
  Future<void> _handleShortcut(String shortcutType) async {
    if (!mounted) return;
    // debugPrint("⚡ 处理 Shortcut: $shortcutType");
    switch (shortcutType) {
      case 'settings':
        await Navigator.of(context).push(
          PageTransitions.slideHorizontal(const SettingsPage()),
        );
        _loadSectionPreferences();
        _loadSemesterSettings();
        await _loadHomeTextConfig();
        _loadAllData(deferred: true);
        break;
      case 'schedule':
        PageTransitions.pushFromRect(
          context: context,
          page: WeeklyCourseScreen(username: widget.username),
          sourceKey: _courseButtonKey,
        );
        break;
      case 'band':
        Navigator.of(context).push(
          PageTransitions.slideHorizontal(const BandSyncScreen()),
        );
        break;
    }
  }

  /// 处理规划块通知点击，导航到规划页面
  Future<void> _handleOpenPlanBlock(dynamic arguments) async {
    // notifId 33001-33999，减去 33001 得到 plan block 在调度列表中的 index
    int? notifId;
    String? planBlockId;
    if (arguments is Map) {
      notifId = arguments['notifId'] as int?;
      planBlockId =
          (arguments['planBlockId'] ?? arguments['plan_block_id'])?.toString();
    }
    // debugPrint("📅 打开规划提醒, notifId=$notifId, planBlockId=$planBlockId");
    TodoPlanBlock? target;
    final blocks = await StorageService.getPlanBlocks(widget.username);
    if (planBlockId != null && planBlockId.isNotEmpty) {
      for (final block in blocks) {
        if (block.uuid == planBlockId && !block.isDeleted) {
          target = block;
          break;
        }
      }
    }
    if (target == null && notifId != null) {
      const baseId = 33001;
      final idx = notifId - baseId;
      if (idx >= 0 && idx < blocks.length) target = blocks[idx];
    }
    if (target != null) {
      if (target.status == TodoPlanStatus.planned ||
          target.status == TodoPlanStatus.reminded) {
        target.status = TodoPlanStatus.reminded;
        target.markAsChanged();
        await StorageService.savePlanBlocks(widget.username, [target],
            sync: true);
      }
      // 导航到规划页面，由用户手动决定是否开始专注
      if (!mounted) return;
      Navigator.of(context).push(
        PageTransitions.material(
          builder: (_) => TodoPlanScreen(
            username: widget.username,
            initialDate: DateTime.now(),
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      PageTransitions.material(
        builder: (_) => TodoPlanScreen(
          username: widget.username,
          initialDate: DateTime.now(),
        ),
      ),
    );
  }

  /// 打开待确认事项页面
  Future<void> _openPendingTodoConfirm() async {
    if (_pendingTodoConfirm == null) return;

    final imagePath = _pendingTodoConfirm!['imagePath'] as String?;
    final results = _pendingTodoConfirm!['results'] as List<dynamic>?;

    if (imagePath == null || results == null || results.isEmpty) return;

    final List<Map<String, dynamic>> typedResults =
        results.map((e) => Map<String, dynamic>.from(e as Map)).toList();

    final confirmedResults =
        await _navigateToTodoConfirm(typedResults, imagePath, null);

    // 只有用户实际确认了待办才清除，直接返回则保留
    if (confirmedResults != null && (confirmedResults as List).isNotEmpty) {
      setState(() {
        _pendingTodoConfirm = null;
      });
      ExternalShareHandler.clearPendingTodoConfirm();
    }
  }
}
