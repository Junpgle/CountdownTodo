part of 'todo_section_widget.dart';

// ignore_for_file: annotate_overrides

mixin _TodoSectionLifecycleMixin on _TodoSectionStateBase {
  @override
  void initState() {
    super.initState();
    _selectedSubTeamUuid = widget.initialSelectedTeamUuid;
    StorageService.scopedDataRefreshNotifier.addListener(
      _onScopedDataRefreshForHabits,
    );
    _loadSettings();
    _loadHabitDisplaySettings();
    _fetchTeamRoles(); // 🚀 获取角色
  }

  void _onScopedDataRefreshForHabits() {
    if (!mounted) return;
    final domains = StorageService.scopedDataRefreshNotifier.value.domains;
    if (domains.contains(DataRefreshDomain.all) ||
        domains.contains(DataRefreshDomain.habits)) {
      _loadHabitDisplaySettings();
    }
  }

  Future<void> _loadHabitDisplaySettings() async {
    try {
      final seriesIds =
          await HabitRepository.getHabitOnlyRecurringTodoSeriesIds();
      if (!mounted) return;
      if (_habitOnlyRecurringSeriesIds.length == seriesIds.length &&
          _habitOnlyRecurringSeriesIds.containsAll(seriesIds)) {
        return;
      }
      setState(() {
        _habitOnlyRecurringSeriesIds = seriesIds;
        _invalidateTodoViewModel();
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
            final role = (t['role'] == 0 || t['user_role'] == 0)
                ? 'admin'
                : 'member';
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
        _invalidateTodoViewModel();
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
    StorageService.scopedDataRefreshNotifier.removeListener(
      _onScopedDataRefreshForHabits,
    );
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
    final now = DateTime.now();
    final today = CalendarDateMath.dateOnly(now);
    final nextSignature = _computeViewModelSignature(today);
    final inputListsChanged =
        oldWidget.todos != widget.todos ||
        oldWidget.todoGroups != widget.todoGroups;
    if (inputListsChanged ||
        _cachedVmSignature != nextSignature ||
        _cachedVmSignatureDate != today ||
        (_cachedVm != null && _cachedVm!.today != today)) {
      _cachedVm = null;
      _cachedTeamFilterMap = null;
      _cachedTeamFilterSignature = null;
      _recurrenceDateStructures.clear();
    }
    _cachedVmSignature = nextSignature;
    _cachedVmSignatureDate = today;

    if (oldWidget.username != widget.username) {
      _loadHabitDisplaySettings();
    }
    if (!_hasInitializedExpansion && widget.todos.isNotEmpty) {
      _isTodayExpanded = !widget.todos
          .where((t) => !_isHistoricalTodoAt(t, today))
          .every((t) => t.isDone);
      _hasInitializedExpansion = true;
    }
  }

  Future<void> openAiAssistant({
    GlobalKey? sourceKey,
    String? initialMessage,
    String? initialSessionId,
    bool sendInitialMessage = true,
    ChatUsageSummary? initialVoiceUsageSummary,
  }) async {
    final now = DateTime.now();
    final today = CalendarDateMath.dateOnly(now);

    await AiTodoChatLauncher.open(
      context,
      username: widget.username,
      sourceKey: sourceKey,
      initialMessage: initialMessage,
      initialSessionId: initialSessionId,
      sendInitialMessage: sendInitialMessage,
      initialVoiceUsageSummary: initialVoiceUsageSummary,
      todos: widget.todos
          .where(
            (t) => !t.isDone && !t.isSkipped && !_isHistoricalTodoAt(t, today),
          )
          .toList(),
      todoGroups: widget.todoGroups,
      conflicts: widget.conflicts,
      teams: _teams,
      loadCourses: () async {
        final list = await CourseService.getAllCourses(widget.username);
        return list.where((course) => !course.isDeleted).toList();
      },
      loadTimeLogs: () async {
        final list = await StorageService.getTimeLogs(widget.username);
        return list.where((log) => !log.isDeleted).toList();
      },
      loadPomodoroRecords: () async {
        final list = await PomodoroService.getRecords();
        return list.where((record) => !record.isDeleted).toList();
      },
      onTodoGroupsChanged: widget.onGroupsChanged,
      onFixedSchedulesChanged: (_) => widget.onRefreshRequested(),
      onTodosBatchAction:
          (
            inserted,
            updated, {
            expectedTodoBaselines,
            expectedSeriesMembership,
          }) async {
            final merged = AiTodoActionExecutor.mergeTodoUpdates(
              widget.todos,
              inserted,
              updated,
            );
            if (expectedSeriesMembership?.isNotEmpty == true) {
              final save = widget.onEditorSave;
              if (save == null || expectedTodoBaselines == null) {
                throw StateError('当前入口无法安全保存整个待办系列');
              }
              final result = await save(
                [...inserted, ...updated],
                expectedTodoBaselines,
                expectedSeriesMembership: expectedSeriesMembership,
              );
              if (result.warnings.isNotEmpty && mounted) {
                AppSnackBars.showSnackBar(
                  context,
                  SnackBar(content: Text(result.warnings.join('；'))),
                );
              }
            } else {
              await widget.onTodosChanged(merged);
            }
          },
    );
  }

  bool _isHistoricalTodoAt(TodoItem t, DateTime today) {
    if (!t.isDone) return false;
    final dueDate = t.dueDate;
    if (dueDate != null) {
      if (dueDate.year != today.year) return dueDate.year < today.year;
      if (dueDate.month != today.month) return dueDate.month < today.month;
      return dueDate.day < today.day;
    }

    // `today` is local midnight, so comparing epoch values preserves the
    // local-calendar boundary without allocating and converting a DateTime
    // for every completed todo.
    return (t.createdDate ?? t.createdAt) < today.millisecondsSinceEpoch;
  }

  void showAddTodoDialog() {
    Navigator.of(context).push(
      PageTransitions.material(
        builder: (_) => AddTodoScreen(
          todoGroups: widget.todoGroups,
          initialTeamUuid: _selectedSubTeamUuid, // 🚀 关键：穿透视口上下文，自动标记团队
          onTodoAdded: (todo) async {
            final updatedList = List<TodoItem>.from(widget.todos)..add(todo);
            await widget.onTodosChanged(updatedList);
          },
          onManualTodoSaved: widget.onManualTodoSaved,
          onFixedScheduleAdded: (item) async {
            await StorageService.saveFixedSchedules(widget.username, [item]);
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
      widget.onLLMResultsParsed!(
        llmResults,
        imagePath,
        originalText,
        _selectedSubTeamUuid,
        currentTeamName,
      );
    } else {
      // 如果没有回调，使用旧的对话框方式
      _showAddTodoDialogWithData(llmResults, imagePath, originalText);
    }
  }
}
