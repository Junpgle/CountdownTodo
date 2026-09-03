part of 'home_dashboard.dart';
// ignore_for_file: annotate_overrides

mixin _HomeDashboardAiMixin on _HomeDashboardStateBase {
  Future<void> _openPendingRecognitionChat() async {
    final sessionId =
        _pendingTodoConfirm?['recognitionChatSessionId']?.toString().trim();
    if (sessionId != null && sessionId.isNotEmpty) {
      await ChatStorageService.setActiveSessionId(sessionId);
      if (!mounted) return;
      await _openAiAssistantFromAppBar();
      return;
    }

    final status = _pendingTodoConfirm?['status']?.toString();
    if (status == 'success') {
      await _openPendingTodoConfirm();
    } else if (status == 'failed') {
      await _retryPendingTodoRecognition();
    } else {
      await _openAiAssistantFromAppBar();
    }
  }

  Future<void> _openAiAssistantFromAppBar() async {
    final todoState = _todoSectionKey.currentState;
    if (todoState != null) {
      await todoState.openAiAssistant(sourceKey: _aiButtonKey);
      return;
    }

    try {
      final results = await Future.wait<dynamic>([
        CourseService.getAllCourses(widget.username),
        StorageService.getTimeLogs(widget.username),
        PomodoroService.getRecords(),
        ApiService.fetchTeams(),
      ]);
      final courses = (results[0] as List<CourseItem>)
          .where((course) => !course.isDeleted)
          .toList();
      final timeLogs = (results[1] as List<TimeLogItem>)
          .where((log) => !log.isDeleted)
          .toList();
      final pomodoroRecords = (results[2] as List<PomodoroRecord>)
          .where((record) => !record.isDeleted)
          .toList();
      final teams = (results[3] as List)
          .whereType<Map>()
          .map((t) => Team.fromJson(Map<String, dynamic>.from(t)))
          .toList();
      final categoryReminderDefaults =
          await StorageService.getCategoryReminderMinutes(widget.username);

      if (!mounted) return;
      await AiTodoChatLauncher.open(
        context,
        username: widget.username,
        sourceKey: _aiButtonKey,
        todos: _todos.where((t) => !t.isDone && !t.isDeleted).toList(),
        todoGroups: _todoGroups,
        courses: courses,
        timeLogs: timeLogs,
        pomodoroRecords: pomodoroRecords,
        conflicts: _latestSyncConflicts,
        teams: teams,
        fixedSchedules: _fixedSchedules,
        categoryReminderDefaults: categoryReminderDefaults,
        onTodoGroupsChanged: (groups) {
          unawaited(_handleAiTodoGroupsChanged(groups));
        },
        onTodosBatchAction: (inserted, updated) {
          unawaited(_handleAiTodosBatchAction(inserted, updated));
        },
        onFixedSchedulesChanged: (schedules) {
          if (!mounted) return;
          setState(() {
            _fixedSchedules =
                schedules.where((schedule) => !schedule.isDeleted).toList();
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开AI助手失败: $e')),
      );
    }
  }

  Future<void> _handleAiTodoGroupsChanged(List<TodoGroup> groups) async {
    if (!mounted) return;
    setState(() => _todoGroups = groups.where((g) => !g.isDeleted).toList());
    await StorageService.saveTodoGroups(widget.username, groups, sync: true);
  }

  Future<void> _handleAiTodosBatchAction(
    List<TodoItem> inserted,
    List<TodoItem> updated,
  ) async {
    final nextTodos = AiTodoActionExecutor.mergeTodoUpdates(
      _todos,
      inserted,
      updated,
    );
    if (!mounted) return;
    setState(() => _todos = nextTodos);
    await StorageService.saveTodos(widget.username, nextTodos);
    await _saveTodosToSharedFile(nextTodos);
    _timelineRevision.value++;
    _todoUpdateSignalNotifier.value++;
    FloatWindowService.triggerReminderCheck();
    FloatWindowService.invalidateSlotCache();
    FloatWindowService.update();
    _syncTodoNotification();
    _rescheduleAlarms();
    await WidgetService.updateTodoWidget(nextTodos);
  }

  // === 初始化与生命周期 ===
}
