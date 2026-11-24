part of 'todo_chat_screen.dart';

// ignore_for_file: annotate_overrides, unused_element, unused_element_parameter

mixin _TodoChatActionExecution on _TodoChatScreenStateBase {
  Future<void> _saveHistorySilently() async {
    await ChatStorageService.saveHistory(_messages, _activeSessionId);
  }

  Future<void> _updateTodoActionDraft(
    AiTodoAction source,
    void Function(AiTodoAction draft) update,
  ) async {
    final draft = source.copy();
    update(draft);
    await _commitTodoActionDraft(source, draft);
  }

  Future<void> _commitTodoActionDraft(
    AiTodoAction source,
    AiTodoAction draft,
  ) async {
    final messageIndex = _messages.indexWhere(
      (message) =>
          message.todoActions?.any((action) => identical(action, source)) ??
          false,
    );
    if (messageIndex < 0) {
      throw StateError('找不到待更新的操作草稿');
    }
    final message = _messages[messageIndex];
    final actions = List<AiTodoAction>.from(message.todoActions!);
    final actionIndex = actions.indexWhere(
      (action) => identical(action, source),
    );
    if (actionIndex < 0) throw StateError('操作草稿已变化，请重新打开后再试');
    actions[actionIndex] = draft;

    final stagedMessages = List<ChatMessage>.from(_messages);
    stagedMessages[messageIndex] = message.copyWith(todoActions: actions);
    await ChatStorageService.saveHistory(stagedMessages, _activeSessionId);
    if (!mounted) return;
    _messages = stagedMessages;
    setState(() {});
  }

  Future<void> _addTodosForMessage(ChatMessage msg) async {
    if (!_executingMessageIds.add(msg.id)) return;
    try {
      await _executeMessageActions(msg);
    } catch (error) {
      if (!mounted) return;
      setState(() {});
      try {
        await _saveHistorySilently();
      } catch (historyError) {
        debugPrint(
          'AI action recovery state could not be saved: $historyError',
        );
      }
      if (!mounted) return;
      AppSnackBars.error(context, '操作执行中断；已成功保存的操作已完成，未完成的操作仍保留在确认卡中：$error');
    } finally {
      _executingMessageIds.remove(msg.id);
    }
  }

  final Set<String> _executingMessageIds = {};

  Future<void> _executeMessageActions(ChatMessage msg) async {
    if (msg.todoActions == null) return;
    final pendingActions = msg.todoActions!
        .where(
          (action) => action.isSelected && !action.isAdded && !action.isIgnored,
        )
        .toList();
    final hasUntitledCreation = pendingActions.any(
      (action) =>
          (action.type == AiTodoActionType.createTodo ||
              action.type == AiTodoActionType.splitTodo ||
              action.type == AiTodoActionType.mergeTodos) &&
          action.title?.trim().isNotEmpty != true,
    );
    if (hasUntitledCreation) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('待办标题为空，请先编辑确认卡再执行')),
      );
      return;
    }
    final hasUnresolvedCountdownTeam = pendingActions.any((action) {
      if (action.type != AiTodoActionType.createCountdown) return false;
      final name = action.teamName?.trim() ?? '';
      final uuid = action.teamUuid?.trim() ?? '';
      if (name.isEmpty && uuid.isEmpty) return false;

      final team = AiTeamBindingResolver.resolveReference(
        name: name,
        uuid: uuid,
        teams: _teams,
      );
      if (team == null) return true;

      // Keep a resolved local binding canonical so the executor persists the
      // same team that the confirmation card displays, including name aliases.
      action
        ..teamName = team.name
        ..teamUuid = team.uuid
        ..hasTeamUuid = true;
      return false;
    });
    if (hasUnresolvedCountdownTeam) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('目标团队未匹配，请编辑确认卡选择团队或改为仅自己可见')),
      );
      return;
    }
    final hasUnspecifiedCategory = pendingActions.any(
      (action) =>
          action.type == AiTodoActionType.categorizeTodo && !action.hasGroupId,
    );
    final hasUnknownCategory = pendingActions.any((action) {
      final groupId = action.groupId?.trim();
      return action.isTodoAction &&
          action.mutatesExistingItem &&
          action.hasGroupId &&
          groupId?.isNotEmpty == true &&
          !widget.todoGroups.any(
            (group) => group.id == groupId && !group.isDeleted,
          );
    });
    if (hasUnspecifiedCategory || hasUnknownCategory) {
      AppSnackBars.showSnackBar(
        context,
        SnackBar(
          content: Text(
            hasUnspecifiedCategory
                ? '请先在确认卡中选择目标分类；移入默认分类时也请明确选择“默认分类”'
                : '目标分类已不存在，请在确认卡中重新选择',
          ),
        ),
      );
      return;
    }
    final hasPlanningActions = msg.todoActions!.any(
      (action) => action.isPlanBlockAction,
    );
    final needsCurrentTodoCatalog =
        hasPlanningActions ||
        pendingActions.any(
          (action) =>
              (action.isTodoAction && action.mutatesExistingItem) ||
              action.type == AiTodoActionType.splitTodo ||
              action.type == AiTodoActionType.mergeTodos,
        );
    final existingTodos = needsCurrentTodoCatalog
        ? [
            for (final todo in await StorageService.getTodos(widget.username))
              {...todo.toJson(), 'title': todo.title},
          ]
        : widget.todos;
    final wholeSeriesActions = pendingActions
        .where(
          (action) =>
              action.type == AiTodoActionType.updateTodo &&
              action.recurrenceScope == 'series',
        )
        .toList(growable: false);
    final wholeSeriesTodos = existingTodos
        .map((todo) => TodoItem.fromJson(Map<String, dynamic>.from(todo)))
        .toList(growable: false);
    final expectedTodoBaselines = <String, TodoItem>{};
    final expectedSeriesMembership = <String, Set<String>>{};
    for (final action in wholeSeriesActions) {
      final target = wholeSeriesTodos
          .where((todo) => todo.id == action.todoId)
          .firstOrNull;
      final seriesId = target == null
          ? null
          : TodoRecurrenceSeriesEditService.seriesIdFor(target);
      if (target == null ||
          seriesId == null ||
          (action.recurrenceSeriesId?.trim().isNotEmpty == true &&
              action.recurrenceSeriesId!.trim() != seriesId)) {
        if (mounted) {
          AppSnackBars.showSnackBar(
            context,
            const SnackBar(content: Text('待办系列已不存在或范围不匹配，请重新查询后再操作')),
          );
        }
        return;
      }
      final members = TodoRecurrenceSeriesEditService.activeMembers(
        wholeSeriesTodos,
        seriesId,
      );
      expectedSeriesMembership[seriesId] = members
          .map((todo) => todo.id)
          .toSet();
      expectedTodoBaselines.addEntries(
        members.map(
          (todo) => MapEntry(todo.id, TodoItem.fromJson(todo.toJson())),
        ),
      );
    }
    if (wholeSeriesActions.isNotEmpty &&
        !await _confirmWholeSeriesAiUpdates(
          wholeSeriesActions,
          wholeSeriesTodos,
        )) {
      return;
    }
    final needsCurrentTimeLogCatalog = pendingActions.any(
      (action) => action.isTimeLogAction && action.mutatesExistingItem,
    );
    final existingTimeLogs = needsCurrentTimeLogCatalog
        ? await StorageService.getTimeLogs(widget.username)
        : _timeLogs;

    final existingCountdowns = widget.countdowns.isNotEmpty
        ? widget.countdowns
        : await StorageService.getCountdowns(widget.username);
    final existingTags = widget.pomodoroTags.isNotEmpty
        ? widget.pomodoroTags
        : await PomodoroService.getTags();

    final result = AiTodoActionExecutor.execute(
      actions: msg.todoActions!,
      existingTodos: existingTodos,
      existingTimeLogs: existingTimeLogs,
      existingCountdowns: existingCountdowns,
      existingTodoGroups: widget.todoGroups,
      existingPomodoroTags: existingTags,
      existingPlanBlocks: _planBlocks,
      existingFixedSchedules: _fixedSchedules,
      categoryReminderDefaults: _categoryReminderDefaults,
    );

    try {
      await _validateTodoSkipActions(pendingActions);
    } catch (error) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', '')),
          ),
        );
      }
      return;
    }

    if (result.hasChanges) {
      final plannedNewTodos = result.newTodos
          .where(
            (todo) =>
                result.newPlanBlocks.any((block) => block.todoId == todo.id),
          )
          .toList();
      if (plannedNewTodos.isNotEmpty) {
        try {
          await AiPlanDraftRepository.save(
            username: widget.username,
            newTodos: plannedNewTodos,
            blocks: result.newPlanBlocks,
          );
        } catch (error) {
          for (final action in result.actionsForWriteGroup(
            AiTodoActionWriteGroup.newPlanBlocks,
          )) {
            if (action.newTodoTitle != null &&
                plannedNewTodos.any((todo) => todo.id == action.todoId)) {
              action.todoId = null;
            }
          }
          if (mounted) {
            setState(() {});
            AppSnackBars.error(context, '规划保存失败，待办与规划均未写入：$error');
          }
          return;
        }
        result.markWriteGroupAdded(AiTodoActionWriteGroup.newPlanBlocks);
        await _saveHistorySilently();
      }
      final changedHabits = await AiTodoActionExecutor.saveHabitActions(
        username: widget.username,
        actions: result.newHabitActions,
        onActionSaved: _saveHistorySilently,
      );
      if (widget.onTodosBatchAction != null) {
        if (result.newTodos.isNotEmpty || result.updatedTodos.isNotEmpty) {
          await widget.onTodosBatchAction!(
            result.newTodos,
            result.updatedTodos,
            expectedTodoBaselines: expectedTodoBaselines.isEmpty
                ? null
                : expectedTodoBaselines,
            expectedSeriesMembership: expectedSeriesMembership.isEmpty
                ? null
                : expectedSeriesMembership,
          );
          result.markWriteGroupAdded(AiTodoActionWriteGroup.newTodos);
          result.markWriteGroupAdded(AiTodoActionWriteGroup.updatedTodos);
          await _saveHistorySilently();
        }
      } else {
        // Fallback to separate calls
        final standaloneNewTodos = result.newTodos
            .where(
              (todo) =>
                  !plannedNewTodos.any((planned) => planned.id == todo.id),
            )
            .toList();
        if (standaloneNewTodos.isNotEmpty) {
          if (widget.onTodosBatchInserted != null) {
            await widget.onTodosBatchInserted!(standaloneNewTodos);
          } else if (widget.onTodoInserted != null) {
            for (final t in standaloneNewTodos) {
              await widget.onTodoInserted!(t);
            }
          } else {
            throw StateError('当前页面没有待办保存回调');
          }
          result.markWriteGroupAdded(AiTodoActionWriteGroup.newTodos);
          await _saveHistorySilently();
        }
        if (result.updatedTodos.isNotEmpty) {
          if (expectedSeriesMembership.isNotEmpty) {
            throw StateError('当前入口不能对整个系列进行安全保存，请从待办列表打开 AI 助手');
          }
          if (widget.onTodosUpdated == null) {
            throw StateError('当前页面没有待办更新回调');
          }
          await widget.onTodosUpdated!(result.updatedTodos);
          result.markWriteGroupAdded(AiTodoActionWriteGroup.updatedTodos);
          await _saveHistorySilently();
        }
      }

      if (result.newTimeLogs.isNotEmpty || result.updatedTimeLogs.isNotEmpty) {
        final allLogs = await StorageService.getTimeLogs(widget.username);
        final merged = AiTodoActionExecutor.mergeTimeLogUpdates(
          allLogs,
          result.newTimeLogs,
          result.updatedTimeLogs,
        );
        await StorageService.saveTimeLogs(widget.username, merged, sync: true);
        result.markWriteGroupAdded(AiTodoActionWriteGroup.timeLogs);
        await _saveHistorySilently();
      }

      if (result.newCountdowns.isNotEmpty ||
          result.updatedCountdowns.isNotEmpty) {
        final allCountdowns = await StorageService.getCountdowns(
          widget.username,
        );
        final merged = AiTodoActionExecutor.mergeCountdownUpdates(
          allCountdowns,
          result.newCountdowns,
          result.updatedCountdowns,
        );
        await StorageService.saveCountdowns(
          widget.username,
          merged,
          sync: true,
        );
        result.markWriteGroupAdded(AiTodoActionWriteGroup.countdowns);
        await _saveHistorySilently();
      }

      if (result.newTodoGroups.isNotEmpty ||
          result.updatedTodoGroups.isNotEmpty) {
        final allGroups = await StorageService.getTodoGroups(
          widget.username,
          includeDeleted: true,
        );
        final merged = AiTodoActionExecutor.mergeTodoGroupUpdates(
          allGroups,
          result.newTodoGroups,
          result.updatedTodoGroups,
        );
        await StorageService.saveTodoGroups(
          widget.username,
          merged,
          sync: true,
        );
        result.markWriteGroupAdded(AiTodoActionWriteGroup.todoGroups);
        await _saveHistorySilently();
        try {
          widget.onTodoGroupsChanged?.call(merged);
        } catch (error) {
          debugPrint('AI todo-group UI refresh failed after save: $error');
        }
      }

      if (result.newPomodoroTags.isNotEmpty ||
          result.updatedPomodoroTags.isNotEmpty) {
        final allTags = await PomodoroService.getTags();
        final merged = AiTodoActionExecutor.mergePomodoroTagUpdates(
          allTags,
          result.newPomodoroTags,
          result.updatedPomodoroTags,
        );
        await PomodoroService.saveTags(merged);
        result.markWriteGroupAdded(AiTodoActionWriteGroup.pomodoroTags);
        await _saveHistorySilently();
      }

      if (result.newPlanBlocks.isNotEmpty ||
          result.updatedPlanBlocks.isNotEmpty) {
        await StorageService.savePlanBlocks(widget.username, [
          if (plannedNewTodos.isEmpty) ...result.newPlanBlocks,
          ...result.updatedPlanBlocks,
        ], sync: true);
        _planBlocks = [
          ..._planBlocks.where(
            (existing) => !result.updatedPlanBlocks.any(
              (updated) => updated.uuid == existing.uuid,
            ),
          ),
          ...result.newPlanBlocks,
          ...result.updatedPlanBlocks,
        ];
        if (plannedNewTodos.isEmpty) {
          result.markWriteGroupAdded(AiTodoActionWriteGroup.newPlanBlocks);
        }
        result.markWriteGroupAdded(AiTodoActionWriteGroup.updatedPlanBlocks);
        await _saveHistorySilently();
      }

      if (result.newFixedSchedules.isNotEmpty ||
          result.updatedFixedSchedules.isNotEmpty) {
        await StorageService.saveFixedSchedules(widget.username, [
          ...result.newFixedSchedules,
          ...result.updatedFixedSchedules,
        ], sync: true);
        result.markWriteGroupAdded(AiTodoActionWriteGroup.fixedSchedules);
        await _saveHistorySilently();
        _fixedSchedules = AiTodoActionExecutor.mergeFixedScheduleUpdates(
          _fixedSchedules,
          result.newFixedSchedules,
          result.updatedFixedSchedules,
        );
        try {
          widget.onFixedSchedulesChanged?.call(_fixedSchedules);
          await ReminderScheduleService.scheduleFromStorage(
            widget.username,
            force: true,
          );
        } catch (error) {
          debugPrint('AI fixed-schedule refresh failed after save: $error');
        }
      }

      var executedPomodoroActions = 0;
      var skippedPomodoroActions = 0;
      _pendingPlanPomodoroEntry = null;
      for (final action in result.pomodoroActions) {
        bool executed;
        try {
          executed = await _executePomodoroAction(action);
        } catch (_) {
          executed = false;
        }
        action.isAdded = executed;
        if (executed) {
          executedPomodoroActions++;
          try {
            await _saveHistorySilently();
          } catch (error) {
            debugPrint('AI Pomodoro action history could not be saved: $error');
          }
        } else {
          skippedPomodoroActions++;
        }
      }

      if (skippedPomodoroActions > 0 &&
          executedPomodoroActions == 0 &&
          !result.hasNonPomodoroChanges) {
        if (mounted) {
          AppSnackBars.showSnackBar(
            context,
            const SnackBar(
              content: Text('番茄钟操作未执行（目标不可用或运行状态冲突），操作卡已保留，可检查后重试。'),
            ),
          );
        }
        return;
      }

      if (!mounted) return;
      final pendingPlanPomodoroEntry = _pendingPlanPomodoroEntry;
      try {
        await _saveHistorySilently();
      } catch (error) {
        debugPrint('AI action history could not be saved: $error');
      }
      if (!mounted) return;

      AppSnackBars.showSnackBar(
        context,
        SnackBar(
          content: Text(
            '已执行所选操作 (新待办: ${result.newTodos.length}, 习惯操作: ${changedHabits.length}, 整理待办: ${result.updatedTodos.length}, 日程: ${result.newFixedSchedules.length + result.updatedFixedSchedules.length}, 规划: ${result.newPlanBlocks.length + result.updatedPlanBlocks.length}, 专注记录: ${result.newTimeLogs.length + result.updatedTimeLogs.length}, 倒计时: ${result.newCountdowns.length + result.updatedCountdowns.length}, 分类: ${result.newTodoGroups.length + result.updatedTodoGroups.length}, 标签: ${result.newPomodoroTags.length + result.updatedPomodoroTags.length}, 番茄钟: $executedPomodoroActions)${pendingPlanPomodoroEntry != null ? '；规划番茄钟已准备，未开始计时' : ''}${skippedPomodoroActions > 0 ? '；$skippedPomodoroActions 项番茄钟操作未执行，确认卡仍保留。' : ''}',
          ),
        ),
      );
      if (pendingPlanPomodoroEntry != null && mounted) {
        try {
          await PageTransitions.pushFromRect<void>(
            context: context,
            sourceKey: _todoActionPanelKeyFor(msg),
            placeholderIcon: Icons.timer_outlined,
            page: PomodoroScreen(
              username: widget.username,
              initialEntry: pendingPlanPomodoroEntry,
            ),
          );
        } finally {
          _pendingPlanPomodoroEntry = null;
          if (mounted) setState(() {});
        }
      } else {
        _pendingPlanPomodoroEntry = null;
        setState(() {});
      }
    }
  }

  Future<bool> _confirmWholeSeriesAiUpdates(
    List<AiTodoAction> actions,
    List<TodoItem> todos,
  ) async {
    final seriesTargets = <String, TodoItem>{};
    for (final action in actions) {
      final target = todos
          .where((todo) => todo.id == action.todoId && !todo.isDeleted)
          .firstOrNull;
      final seriesId = target == null
          ? null
          : TodoRecurrenceSeriesEditService.seriesIdFor(target);
      if (target == null ||
          seriesId == null ||
          (action.recurrenceSeriesId?.trim().isNotEmpty == true &&
              action.recurrenceSeriesId!.trim() != seriesId)) {
        return false;
      }
      seriesTargets.putIfAbsent(seriesId, () => target);
    }
    final summaries = <String>[];
    for (final entry in seriesTargets.entries) {
      final counts = TodoRecurrenceSeriesEditService.countMembers(
        todos,
        entry.key,
        now: DateTime.now(),
      );
      if (counts.total == 0) return false;
      summaries.add(
        '“${entry.value.title}”：${counts.total} 期（历史 ${counts.historical}、今天 ${counts.current}、未来 ${counts.future}）；已完成 ${counts.completed}、已跳过 ${counts.skipped}。',
      );
    }
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认修改整个待办系列'),
        content: Text(
          '${summaries.join('\n\n')}\n\n只修改待办内容与时间；每期完成和跳过状态会保留。重复规则不变，已有规划块、时间日志和专注记录保留原时间。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('返回检查'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认修改'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _validateTodoSkipActions(Iterable<AiTodoAction> actions) async {
    for (final action in actions.where(
      (action) =>
          action.type == AiTodoActionType.skipTodo &&
          action.isSelected &&
          !action.isAdded &&
          !action.isIgnored,
    )) {
      if (action.recurrenceScope != 'occurrence') {
        throw StateError('跳过操作只能针对一个具体期次');
      }
      final todoId = action.todoId?.trim();
      if (todoId == null || todoId.isEmpty) {
        throw StateError('跳过操作缺少具体待办ID，请重新查询');
      }
      final latest = await StorageService.getTodoByUuid(
        widget.username,
        todoId,
      );
      if (latest == null ||
          latest.isDeleted ||
          latest.isDone ||
          latest.isSkipped ||
          (latest.recurrenceSeriesId?.isNotEmpty != true &&
              latest.recurrence == RecurrenceType.none)) {
        throw StateError('这期待办状态已变化或已不存在，请重新查询后再操作');
      }
      final linkedPlans = await StorageService.getPlanBlocksByTodo(
        widget.username,
        todoId,
      );
      final run = await PomodoroService.loadRunState();
      final runFocusesTodo =
          run != null &&
          {
            PomodoroPhase.focusing,
            PomodoroPhase.breaking,
            PomodoroPhase.remoteWatching,
          }.contains(run.phase) &&
          (run.todoUuid == todoId ||
              (run.planBlockId?.isNotEmpty == true &&
                  linkedPlans.any((block) => block.id == run.planBlockId)));
      if (runFocusesTodo) {
        throw StateError('这期待办正在专注，请先结束当前专注再跳过');
      }
    }
  }

  Future<bool> _executePomodoroAction(AiTodoAction action) async {
    switch (action.type) {
      case AiTodoActionType.startPlanBlockPomodoro:
        if (_pendingPlanPomodoroEntry != null) return false;
        final blockId = action.planBlockId;
        if (blockId == null || blockId.isEmpty) return false;
        final blocks = await StorageService.getPlanBlocks(widget.username);
        TodoPlanBlock? block;
        for (final item in blocks) {
          if (item.uuid == blockId && !item.isDeleted) {
            block = item;
            break;
          }
        }
        if (block == null) return false;
        final existing = await PomodoroService.loadRunState();
        if (existing != null &&
            existing.phase != PomodoroPhase.idle &&
            existing.phase != PomodoroPhase.finished) {
          return false;
        }
        final todos = await StorageService.getTodos(widget.username);
        TodoItem? boundTodo;
        for (final todo in todos) {
          if (todo.id == block.todoId && !todo.isDeleted && !todo.isDone) {
            boundTodo = todo;
            break;
          }
        }
        if (boundTodo == null) return false;
        _pendingPlanPomodoroEntry = PomodoroEntryIntent.forPlanBlock(
          boundTodo: boundTodo,
          planBlock: block,
        );
        return true;
      case AiTodoActionType.startPomodoro:
        if (_pendingPlanPomodoroEntry != null) return false;
        final existing = await PomodoroService.loadRunState();
        if (existing != null &&
            existing.phase != PomodoroPhase.idle &&
            existing.phase != PomodoroPhase.finished) {
          return false;
        }
        final settings = await PomodoroService.getSettings();
        TodoItem? boundTodo;
        if (action.todoId != null) {
          final match = widget.todos.where((t) => t['id'] == action.todoId);
          if (match.isNotEmpty) {
            boundTodo = TodoItem(
              id: action.todoId,
              title: match.first['title']?.toString() ?? action.title ?? '专注',
              isDone: match.first['isDone'] == true,
              isDeleted: match.first['isDeleted'] == true,
            );
          }
        }
        boundTodo ??= action.title?.isNotEmpty == true
            ? TodoItem(id: '', title: action.title!)
            : null;
        await PomodoroControlService.startFocus(
          settings: settings,
          boundTodo: boundTodo,
          tagUuids: action.tagUuids,
          durationMinutes: action.durationMinutes,
          ensureSyncConnection: true,
          deferSideEffects: true,
        );
        return true;
      case AiTodoActionType.stopPomodoro:
        return PomodoroControlService.stopCurrentFocus(
          username: widget.username,
          status: action.status == 'completed'
              ? PomodoroRecordStatus.completed
              : PomodoroRecordStatus.interrupted,
          markTodoComplete: action.status == 'completed',
          ensureSyncConnection: true,
        );
      case AiTodoActionType.createTodo:
      case AiTodoActionType.updateTodo:
      case AiTodoActionType.completeTodo:
      case AiTodoActionType.skipTodo:
      case AiTodoActionType.deleteTodo:
      case AiTodoActionType.createFixedSchedule:
      case AiTodoActionType.updateFixedSchedule:
      case AiTodoActionType.cancelFixedSchedule:
      case AiTodoActionType.deleteFixedSchedule:
      case AiTodoActionType.rescheduleTodo:
      case AiTodoActionType.bulkRescheduleTodo:
      case AiTodoActionType.categorizeTodo:
      case AiTodoActionType.planTodos:
      case AiTodoActionType.createPlanBlock:
      case AiTodoActionType.updatePlanBlock:
      case AiTodoActionType.deletePlanBlock:
      case AiTodoActionType.reschedulePlanBlocks:
      case AiTodoActionType.skipPlanBlock:
      case AiTodoActionType.splitTodo:
      case AiTodoActionType.mergeTodos:
      case AiTodoActionType.createTimeLog:
      case AiTodoActionType.updateTimeLog:
      case AiTodoActionType.deleteTimeLog:
      case AiTodoActionType.createCountdown:
      case AiTodoActionType.updateCountdown:
      case AiTodoActionType.completeCountdown:
      case AiTodoActionType.deleteCountdown:
      case AiTodoActionType.createTodoGroup:
      case AiTodoActionType.updateTodoGroup:
      case AiTodoActionType.deleteTodoGroup:
      case AiTodoActionType.createPomodoroTag:
      case AiTodoActionType.updatePomodoroTag:
      case AiTodoActionType.deletePomodoroTag:
      case AiTodoActionType.createHabit:
      case AiTodoActionType.updateHabit:
      case AiTodoActionType.deleteHabit:
      case AiTodoActionType.unknown:
        return false;
    }
  }

  Widget _buildQuickQuestion(
    String text, {
    bool compact = false,
    bool expand = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return _PressableScale(
      onTap: () {
        _inputCtrl.text = text;
        _sendMessage();
      },
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: expand ? double.infinity : null,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 14,
            vertical: compact ? 7 : 10,
          ),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            text,
            maxLines: expand ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 12 : 13,
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  String _buildRawReplyText(ChatMessage msg) {
    final rawReply = msg.rawContent;
    if (rawReply.isEmpty) return '当前消息没有保存模型原始回复。';
    if (rawReply == msg.content &&
        (rawReply.startsWith('模型未返回可执行的操作调用；') ||
            rawReply.startsWith('模型没有返回可执行的规划草案，'))) {
      return '这条历史消息只保存了应用提示，模型原始回复当时未留存，无法恢复。';
    }
    return rawReply;
  }

  Future<void> _showRawReplyDialog(ChatMessage msg) async {
    final colorScheme = Theme.of(context).colorScheme;
    await showAppDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('模型原始回复'),
        content: SizedBox(
          width: MediaQuery.sizeOf(ctx).width * 0.82,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
            child: SingleChildScrollView(
              child: SelectableText(
                _buildRawReplyText(msg),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: colorScheme.onSurface,
                  fontFamily: 'monospace',
                ),
              ),
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
}
