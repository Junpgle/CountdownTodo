part of 'todo_section_widget.dart';

// ignore_for_file: annotate_overrides

mixin _TodoSectionLifecycleMixin on _TodoSectionStateBase {
  @override
  void initState() {
    super.initState();
    _selectedSubTeamUuid = widget.initialSelectedTeamUuid;
    _loadSettings();
    _loadHabitDisplaySettings();
    _fetchTeamRoles(); // 🚀 获取角色
  }

  Future<void> _loadHabitDisplaySettings() async {
    try {
      final goals = await HabitRepository.getActiveGoals();
      final seriesIds = <String>{};
      for (final goal in goals) {
        if (goal.sourceType != HabitSourceType.recurringTodo ||
            goal.displayMode != HabitDisplayMode.habitOnly) {
          continue;
        }
        seriesIds.addAll(goal.sourceIds.where((id) => id.isNotEmpty));
      }
      if (!mounted) return;
      setState(() {
        _habitOnlyRecurringSeriesIds = seriesIds;
        _cachedVm = null;
      });
    } catch (_) {
      // 习惯数据读取失败时保留待办列表，避免影响普通待办展示。
    }
  }

  Future<void> _fetchTeamRoles() async {
    try {
      final teams = await ApiService.fetchTeams();
      if (mounted) {
        setState(() {
          _teams = teams
              .whereType<Map>()
              .map((t) => Team.fromJson(Map<String, dynamic>.from(t)))
              .toList();
          for (var t in teams) {
            final uuid = t['uuid']?.toString();
            final role =
                (t['role'] == 0 || t['user_role'] == 0) ? 'admin' : 'member';
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
    final modeName = await StorageService.getTodoFolderDisplayMode();
    if (mounted) {
      setState(() {
        _inlineFolders = inline;
        _folderDisplayMode = _parseFolderDisplayMode(modeName);
        _cachedVm = null;
      });
    }
  }

  _TodoFolderDisplayMode _parseFolderDisplayMode(String modeName) {
    return _TodoFolderDisplayMode.values.firstWhere(
      (mode) => mode.name == modeName,
      orElse: () => _inlineFolders
          ? _TodoFolderDisplayMode.inline
          : _TodoFolderDisplayMode.separate,
    );
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
    if (oldWidget.todos != widget.todos ||
        oldWidget.todoGroups != widget.todoGroups) {
      _cachedVm = null;
      _loadHabitDisplaySettings();
    }
    if (!_hasInitializedExpansion && widget.todos.isNotEmpty) {
      _isTodayExpanded = !widget.todos
          .where((t) => !_isHistoricalTodo(t))
          .every((t) => t.isDone);
      _hasInitializedExpansion = true;
    }
  }

  Future<void> openAiAssistant({GlobalKey? sourceKey}) async {
    final aiContext = await _loadAiAssistantContext();
    if (!mounted) return;

    AiTodoChatLauncher.open(
      context,
      username: widget.username,
      sourceKey: sourceKey,
      todos: widget.todos
          .where((t) => !t.isDone && !_isHistoricalTodo(t))
          .toList(),
      todoGroups: widget.todoGroups,
      courses: aiContext.courses,
      timeLogs: aiContext.timeLogs,
      pomodoroRecords: aiContext.pomodoroRecords,
      conflicts: widget.conflicts,
      teams: aiContext.teams,
      onTodoGroupsChanged: widget.onGroupsChanged,
      onFixedSchedulesChanged: (_) => widget.onRefreshRequested(),
      onTodosBatchAction: (inserted, updated) {
        widget.onTodosChanged(
          AiTodoActionExecutor.mergeTodoUpdates(
            widget.todos,
            inserted,
            updated,
          ),
        );
      },
    );
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
      PageTransitions.material(
        builder: (_) => AddTodoScreen(
          todoGroups: widget.todoGroups,
          initialTeamUuid: _selectedSubTeamUuid, // 🚀 关键：穿透视口上下文，自动标记团队
          onTodoAdded: (todo) {
            final updatedList = List<TodoItem>.from(widget.todos)..add(todo);
            widget.onTodosChanged(updatedList);
          },
          onFixedScheduleAdded: (item) async {
            await StorageService.saveFixedSchedules(
              widget.username,
              [item],
            );
            widget.onRefreshRequested();
          },
          onLLMResultsParsed: widget.onLLMResultsParsed,
        ),
      ),
    );
  }

  /// 显示添加事项对话框并预填充大模型识别的数据
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
      final currentTeamName = _selectedSubTeamUuid != null
          ? existingTeams[_selectedSubTeamUuid]
          : null;
      widget.onLLMResultsParsed!(llmResults, imagePath, originalText,
          _selectedSubTeamUuid, currentTeamName);
    } else {
      // 如果没有回调，使用旧的对话框方式
      _showAddTodoDialogWithData(llmResults, imagePath, originalText);
    }
  }
}
