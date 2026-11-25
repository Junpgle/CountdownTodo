part of '../fixed_schedule_editor_screen.dart';

extension _FixedScheduleEditorSave on _FixedScheduleEditorScreenState {
  Future<void> _save() async {
    _unfocusActiveInput();
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('请输入固定日程名称')),
      );
      return;
    }

    final start = _timeTbd ? null : _atTime(_startTime);
    final end = _timeTbd || _endTimeTbd ? null : _atTime(_endTime);
    if (start != null && end != null && !end.isAfter(start)) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('结束时间必须晚于开始时间')),
      );
      return;
    }
    final existing = _selectedOccurrence;
    if (_forcedOccurrenceEdit &&
        existing != null &&
        AppTimeFormats.date(_date) != existing.date) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('该重复日程由外部日历管理，请在来源日历中移动场次')),
      );
      return;
    }
    final scope = existing == null
        ? FixedScheduleEditScope.series
        : _effectiveEditScope;
    final recurrence =
        scope == FixedScheduleEditScope.occurrence && existing != null
        ? existing.recurrence
        : _recurrence;
    if (scope != FixedScheduleEditScope.occurrence &&
        recurrence != RecurrenceType.none &&
        _recurrenceEndDate.isBefore(_date)) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('重复结束日期不能早于首次日期')),
      );
      return;
    }
    final customIntervalDays = int.tryParse(
      _customIntervalController.text.trim(),
    );
    if (scope != FixedScheduleEditScope.occurrence &&
        recurrence == RecurrenceType.customDays &&
        (customIntervalDays == null || customIntervalDays < 1)) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('请输入大于 0 的自定义重复天数')),
      );
      return;
    }

    _mutateState(() => _saving = true);
    final teamScopeChanged =
        _normalizeTeamUuid(_selectedTeamUuid) != _baselineTeamUuid;
    if (_relatedTodoIdsChanged || teamScopeChanged) {
      try {
        final invalidMessage = await _invalidRelatedTodoMessage();
        if (!mounted) return;
        if (invalidMessage != null) {
          _mutateState(() => _saving = false);
          AppSnackBars.showSnackBar(
            context,
            SnackBar(content: Text(invalidMessage)),
          );
          return;
        }
      } catch (_) {
        if (!mounted) return;
        _mutateState(() => _saving = false);
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('读取关联待办失败，关系改动未保存，请重试')),
        );
        return;
      }
    }
    final dateText = AppTimeFormats.date(_date);
    final item = existing == null
        ? FixedScheduleItem(title: title, date: dateText)
        : FixedScheduleItem.fromJson(existing.toJson());
    item
      ..title = title
      ..date = dateText
      ..startTime = start?.millisecondsSinceEpoch
      ..endTime = end?.millisecondsSinceEpoch
      ..location = _locationController.text.trim().isEmpty
          ? null
          : _locationController.text.trim()
      ..remark = _remarkController.text.trim().isEmpty
          ? null
          : _remarkController.text.trim()
      ..reminderMinutes = (_reminderMinutes.toList()
        ..sort((left, right) => right.compareTo(left)))
      ..timezone = DateTime.now().timeZoneName
      ..recurrence = recurrence
      ..customIntervalDays = recurrence == RecurrenceType.customDays
          ? customIntervalDays
          : null
      ..teamUuid = _selectedTeamUuid
      ..relatedTodoIds = _relatedTodoIds.toList()
      ..ownerUserId = existing?.ownerUserId ?? _currentUserId
      ..status = _cancelled
          ? FixedScheduleStatus.cancelled
          : existing?.status == FixedScheduleStatus.finished
          ? FixedScheduleStatus.finished
          : FixedScheduleStatus.scheduled;

    late final ({
      List<FixedScheduleItem> active,
      List<FixedScheduleItem> changes,
      FixedScheduleItem refreshItem,
    })
    plan;
    try {
      if (existing == null) {
        final created = FixedScheduleRecurrenceService.rebuildSeries(
          template: item,
          existingSeries: const [],
          recurrence: recurrence,
          recurrenceEndDate: recurrence == RecurrenceType.none
              ? _date
              : _recurrenceEndDate,
          customIntervalDays: customIntervalDays ?? 1,
          applyTeamUuid: true,
        );
        plan = (
          active: created.active,
          changes: created.changes,
          refreshItem: created.active.first,
        );
      } else {
        final edited = FixedScheduleEditService.buildChanges(
          scope: scope,
          selectedOccurrence: existing,
          existingSeries: _seriesItems,
          editedTemplate: item,
          recurrence: recurrence,
          recurrenceEndDate: scope == FixedScheduleEditScope.occurrence
              ? DateTime.tryParse(existing.date) ?? _date
              : _recurrenceEndDate,
          customIntervalDays: customIntervalDays ?? 1,
          applyTeamUuid: _selectedTeamUuid != existing.teamUuid,
          applyRelatedTodoIds: _relatedTodoIdsChanged,
        );
        plan = (
          active: edited.affected,
          changes: edited.changes,
          refreshItem: edited.refreshItem,
        );
      }
    } on FixedScheduleRecurrenceLimitException catch (error) {
      if (!mounted) return;
      _mutateState(() => _saving = false);
      AppSnackBars.showSnackBar(
        context,
        SnackBar(content: Text(error.toString())),
      );
      return;
    }

    if (existing != null &&
        _supportsRangeEdit &&
        !await _confirmEditScope(scope, plan, existing)) {
      if (mounted) _mutateState(() => _saving = false);
      return;
    }

    FixedScheduleRescheduleImpact? reviewedImpact;
    try {
      reviewedImpact = await _reviewRescheduleImpact(plan, scope, existing);
    } catch (_) {
      if (!mounted) return;
      _mutateState(() => _saving = false);
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('读取改期影响失败，未保存；请重试或返回修改')),
      );
      return;
    }
    if (reviewedImpact == null) {
      if (mounted) _mutateState(() => _saving = false);
      return;
    }

    final conflicts = await _conflictsFor(plan.changes);
    if (!mounted) return;
    final remainingConflicts = reviewedImpact.hasImpact
        ? conflicts
              .where(
                (conflict) =>
                    conflict.severity == ScheduleConflictSeverity.hard,
              )
              .toList(growable: false)
        : conflicts;
    if (remainingConflicts.isNotEmpty &&
        !await _confirmConflicts(remainingConflicts)) {
      if (mounted) _mutateState(() => _saving = false);
      return;
    }

    late final bool saved;
    try {
      saved = await _saveEditedItems(
        plan.changes,
        refreshItem: plan.refreshItem,
        reviewedImpact: reviewedImpact,
      );
    } catch (_) {
      if (!mounted) return;
      _mutateState(() => _saving = false);
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('保存失败，改期内容仍保留在编辑页，请重试')),
      );
      return;
    }
    if (!saved) {
      if (!mounted) return;
      _mutateState(() => _saving = false);
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('日程或关联内容已变化，请重新复核后再保存')),
      );
      return;
    }
    widget.onSaved?.call(plan.refreshItem);
    if (!mounted) return;
    Navigator.pop(context, plan.refreshItem);
  }

  Future<bool> _confirmEditScope(
    FixedScheduleEditScope scope,
    ({
      List<FixedScheduleItem> active,
      List<FixedScheduleItem> changes,
      FixedScheduleItem refreshItem,
    })
    plan,
    FixedScheduleItem selected,
  ) async {
    final activeSeries = _seriesItems.where((item) => !item.isDeleted).toList();
    final selectedDate = DateTime.tryParse(selected.date)?.toLocal();
    final keptEarlier =
        scope == FixedScheduleEditScope.future && selectedDate != null
        ? activeSeries.where((item) {
            final date = DateTime.tryParse(item.date)?.toLocal();
            return date != null && date.isBefore(selectedDate);
          }).length
        : 0;
    final removedCount = plan.changes.where((item) => item.isDeleted).length;
    final movedOccurrence =
        scope == FixedScheduleEditScope.occurrence &&
        plan.refreshItem.date != selected.date;
    final content = <Widget>[
      Text(_confirmedScopeSummary(scope, plan, selected)),
      if (keptEarlier > 0) Text('此前 $keptEarlier 场保持原样。'),
      if (_relatedTodoIdsChanged)
        Text(_relatedTodoReviewText(scope, plan, keptEarlier)),
      if (movedOccurrence) const Text('原日期场次将标记为已取消，并在新日期创建一条独立日程。'),
      if (removedCount > 0) Text('按新规则将有 $removedCount 场不再保留，写入逻辑删除。'),
      if (scope == FixedScheduleEditScope.occurrence)
        const Text('重复规则和其他场次不变；取消状态只作用于当前场次。'),
      if (scope != FixedScheduleEditScope.occurrence)
        Text(
          '本次保存会更新 ${plan.active.length} 场，重复规则从${scope == FixedScheduleEditScope.future ? '当前场次' : '系列首次日期'}起生效。',
        ),
    ];
    return await showAppDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('确认${_scopeLabel(scope)}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < content.length; index++) ...[
                  if (index > 0) const SizedBox(height: 8),
                  content[index],
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('返回修改'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text('应用到${_scopeLabel(scope)}'),
              ),
            ],
          ),
        ) ??
        false;
  }

  String _confirmedScopeSummary(
    FixedScheduleEditScope scope,
    ({
      List<FixedScheduleItem> active,
      List<FixedScheduleItem> changes,
      FixedScheduleItem refreshItem,
    })
    plan,
    FixedScheduleItem selected,
  ) {
    final actualDates =
        plan.active
            .map((item) => DateTime.tryParse(item.date))
            .whereType<DateTime>()
            .toList()
          ..sort();
    final resultRange = actualDates.isEmpty
        ? selected.date
        : (actualDates.first == actualDates.last
              ? AppTimeFormats.date(actualDates.first)
              : '${AppTimeFormats.date(actualDates.first)} – ${AppTimeFormats.date(actualDates.last)}');
    if (scope == FixedScheduleEditScope.occurrence) {
      return plan.refreshItem.date == selected.date
          ? '只修改当前场次 · ${selected.date}'
          : '只修改当前场次 · ${selected.date} → ${plan.refreshItem.date}';
    }

    final currentCount = _seriesItems.where((item) => !item.isDeleted).length;
    if (scope == FixedScheduleEditScope.future) {
      final selectedDate = DateTime.tryParse(selected.date);
      final previousCount = selectedDate == null
          ? 0
          : _seriesItems.where((item) {
              final date = DateTime.tryParse(item.date);
              return !item.isDeleted &&
                  date != null &&
                  date.isBefore(selectedDate);
            }).length;
      return '此前 $previousCount 场保持不变 · 本次及以后形成 ${plan.active.length} 场 · $resultRange';
    }

    final oldRange = _seriesStartDate == null || _seriesEndDate == null
        ? '当前 $currentCount 场'
        : '${AppTimeFormats.date(_seriesStartDate!)} – ${AppTimeFormats.date(_seriesEndDate!)}';
    final newEndDate = AppTimeFormats.date(_recurrenceEndDate);
    final oldEndDate = _seriesEndDate == null
        ? ''
        : AppTimeFormats.date(_seriesEndDate!);
    final endDateSummary =
        _recurrence != RecurrenceType.none &&
            oldEndDate.isNotEmpty &&
            oldEndDate != newEndDate
        ? ' · 结束日期 $oldEndDate → $newEndDate'
        : '';
    return '整个系列：$oldRange → ${plan.active.length} 场 · $resultRange$endDateSummary';
  }

  Future<bool> _saveEditedItems(
    List<FixedScheduleItem> items, {
    required FixedScheduleItem refreshItem,
    FixedScheduleRescheduleImpact? reviewedImpact,
  }) async {
    final saveAllHandler = widget.onSaveAll;
    if (saveAllHandler != null) {
      await saveAllHandler(items);
    } else {
      final saved = await StorageService.saveFixedSchedulesIfUnchanged(
        widget.username,
        baseline: _seriesItems,
        items: items,
        reviewedTodoIds: reviewedImpact?.shouldReview == true
            ? reviewedImpact!.relatedTodoIds.toList()
            : const [],
        reviewedTodos: reviewedImpact?.shouldReview == true
            ? reviewedImpact!.sourceTodos
            : const [],
        reviewedPlanBlocks: reviewedImpact?.shouldReview == true
            ? reviewedImpact!.planBlockSnapshots
            : null,
        sync: widget.syncOnSave,
      );
      if (!saved) return false;
      final saveHandler = widget.onSave;
      if (saveHandler != null) await saveHandler(refreshItem);
    }
    final reminderRefresh =
        widget.rescheduleReminders?.call() ??
        ReminderScheduleService.scheduleFromStorage(
          widget.username,
          force: true,
        );
    unawaited(
      reminderRefresh.catchError((Object error, StackTrace stackTrace) {
        debugPrint('Fixed schedule reminder refresh failed: $error');
      }),
    );
    return true;
  }

  Future<FixedScheduleRescheduleImpact?> _reviewRescheduleImpact(
    ({
      List<FixedScheduleItem> active,
      List<FixedScheduleItem> changes,
      FixedScheduleItem refreshItem,
    })
    plan,
    FixedScheduleEditScope scope,
    FixedScheduleItem? selected,
  ) async {
    if (selected == null) {
      return FixedScheduleRescheduleImpactService.build(
        baseline: const [],
        active: const [],
        changes: const [],
        scope: scope,
        selectedOccurrence: plan.refreshItem,
        refreshItem: plan.refreshItem,
        todos: const [],
        planBlocks: const [],
        now: DateTime.now(),
      );
    }
    final occurrence = selected;
    var impact = await _loadRescheduleImpact(plan, scope, occurrence);
    var hasPresentedReview = false;
    while (true) {
      if (impact.hasImpact || hasPresentedReview) {
        hasPresentedReview = true;
        if (!mounted) return null;
        final accepted = await showDialog<FixedScheduleRescheduleImpact>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => FixedScheduleRescheduleImpactDialog(
            impact: impact,
            reload: () => _loadRescheduleImpact(plan, scope, occurrence),
            openTodo: _openImpactTodo,
            openPlan: _openImpactPlan,
          ),
        );
        if (!mounted || accepted == null) return null;
        final latest = await _loadRescheduleImpact(plan, scope, occurrence);
        if (latest.snapshotSignature == accepted.snapshotSignature) {
          return latest;
        }
        impact = latest;
        continue;
      }

      // Even an empty review result is guarded at commit time. Re-read once
      // here so a plan or relationship added during the first query cannot
      // silently turn an empty result into an unreviewed impact.
      final latest = await _loadRescheduleImpact(plan, scope, occurrence);
      if (latest.snapshotSignature == impact.snapshotSignature) return latest;
      impact = latest;
    }
  }

  Future<FixedScheduleRescheduleImpact> _loadRescheduleImpact(
    ({
      List<FixedScheduleItem> active,
      List<FixedScheduleItem> changes,
      FixedScheduleItem refreshItem,
    })
    plan,
    FixedScheduleEditScope scope,
    FixedScheduleItem selected,
  ) async {
    Future<void> ensureSameAccount() async {
      if ((await StorageService.getLoginSession() ?? 'default') !=
          widget.username) {
        throw StateError('账户已切换，请重新打开固定日程');
      }
    }

    await ensureSameAccount();
    final empty = FixedScheduleRescheduleImpactService.build(
      baseline: _seriesItems,
      active: plan.active,
      changes: plan.changes,
      scope: scope,
      selectedOccurrence: selected,
      refreshItem: plan.refreshItem,
      todos: const [],
      planBlocks: const [],
      now: DateTime.now(),
    );
    final reads = await Future.wait<dynamic>([
      if (empty.relatedTodoIds.isNotEmpty)
        StorageService.getTodosForFixedScheduleRelationIds(
          widget.username,
          empty.relatedTodoIds,
        )
      else
        Future.value(const <TodoItem>[]),
      if (empty.newTimedSchedules.isNotEmpty)
        StorageService.getPlanBlocksOverlappingFixedSchedules(
          widget.username,
          empty.newTimedSchedules,
        )
      else
        Future.value(const <TodoPlanBlock>[]),
    ]);
    await ensureSameAccount();
    return FixedScheduleRescheduleImpactService.build(
      baseline: _seriesItems,
      active: plan.active,
      changes: plan.changes,
      scope: scope,
      selectedOccurrence: selected,
      refreshItem: plan.refreshItem,
      todos: reads[0] as List<TodoItem>,
      planBlocks: reads[1] as List<TodoPlanBlock>,
      now: DateTime.now(),
    );
  }

  Future<void> _openImpactTodo(TodoItem todo) async {
    if ((await StorageService.getLoginSession() ?? 'default') !=
        widget.username) {
      throw StateError('账户已切换，请返回后重新打开日程');
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      PageTransitions.material(builder: (_) => TodoDetailScreen(todo: todo)),
    );
  }

  Future<void> _openImpactPlan(TodoPlanBlock block) async {
    if ((await StorageService.getLoginSession() ?? 'default') !=
        widget.username) {
      throw StateError('账户已切换，请返回后重新打开日程');
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      PageTransitions.material(
        builder: (_) =>
            PlanBlockDetailScreen(block: block, username: widget.username),
      ),
    );
  }

  Future<List<ScheduleConflict>> _conflictsFor(
    List<FixedScheduleItem> candidates,
  ) async {
    final timedCandidates = candidates
        .where((item) => item.startTime != null && item.endTime != null)
        .toList();
    if (timedCandidates.isEmpty) {
      return const [];
    }
    final results = await Future.wait<dynamic>([
      StorageService.getFixedSchedules(widget.username),
      StorageService.getPlanBlocks(widget.username),
      CourseService.getAllCourses(widget.username),
    ]);
    final candidateIds = timedCandidates.map((item) => item.id).toSet();
    final schedules =
        (results[0] as List<FixedScheduleItem>)
            .where((item) => !candidateIds.contains(item.id))
            .toList()
          ..addAll(timedCandidates);
    return ScheduleConflictService.detect(
      fixedSchedules: schedules,
      planBlocks: results[1] as List<TodoPlanBlock>,
      courses: results[2] as List<CourseItem>,
    ).where((conflict) {
      return candidateIds.contains(conflict.leftId) ||
          candidateIds.contains(conflict.rightId);
    }).toList();
  }

  Future<void> _saveItems(
    List<FixedScheduleItem> items, {
    required FixedScheduleItem refreshItem,
  }) async {
    final saveAllHandler = widget.onSaveAll;
    if (saveAllHandler != null) {
      await saveAllHandler(items);
    } else {
      final saveHandler = widget.onSave;
      if (items.length == 1 && saveHandler != null) {
        await saveHandler(items.single);
      } else {
        await StorageService.saveFixedSchedules(widget.username, items);
        if (saveHandler != null) await saveHandler(refreshItem);
      }
    }
    await ReminderScheduleService.scheduleFromStorage(
      widget.username,
      force: true,
    );
  }

  Future<bool> _confirmConflicts(List<ScheduleConflict> conflicts) async {
    final hardCount = conflicts
        .where((item) => item.severity == ScheduleConflictSeverity.hard)
        .length;
    final softCount = conflicts.length - hardCount;
    return await showAppDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(hardCount > 0 ? '存在固定日程冲突' : '与规划块重叠'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hardCount > 0) Text('$hardCount 个硬冲突不会被系统自动移动。'),
                if (softCount > 0) Text('$softCount 个规划块可以稍后调整。'),
                const SizedBox(height: 12),
                ...conflicts
                    .take(3)
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('• ${item.message}'),
                      ),
                    ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('返回调整'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('仍然保存'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _delete() async {
    _unfocusActiveInput();
    final item = _selectedOccurrence;
    if (item == null) return;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除固定日程'),
        content: Text(
          _seriesItems.where((entry) => !entry.isDeleted).length > 1
              ? '将删除整个重复日程系列，历史数据仍可用于后续同步恢复。'
              : '该操作会进行逻辑删除，历史数据仍可用于后续同步恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final activeSeries = _seriesItems
        .where((entry) => !entry.isDeleted)
        .toList();
    final targets = activeSeries.isEmpty ? [item] : activeSeries;
    final tombstones = targets.map((entry) {
      final copy = FixedScheduleItem.fromJson(entry.toJson())..isDeleted = true;
      copy.markAsChanged();
      return copy;
    }).toList();
    await _saveItems(tombstones, refreshItem: tombstones.first);
    if (!mounted) return;
    Navigator.pop(context, item);
  }
}
