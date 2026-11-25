part of '../plan_block_editor_sheet.dart';

extension _PlanBlockEditorActions on _PlanBlockEditorSheetState {
  Future<TodoPlanBlock> _persist(
    TodoPlanBlock draft,
    PlanAvailabilitySelection? selection, {
    TodoPlanStatus? newStatus,
  }) async {
    final existing = _persistedBlock;
    if (_isReuse &&
        existing == null &&
        selection == null &&
        widget.saver == null) {
      selection = await _checkReuseTime();
    }
    if (widget.conflictEdit != null && widget.saver == null) {
      return (widget.conflictService ??
              PlanConflictReviewService(clock: widget.clock))
          .save(
            widget.conflictEdit!,
            draft,
            selection,
            expectedBlock: existing ?? widget.conflictEdit!.block,
            manualQuery: _manualQuery,
            newStatus: newStatus,
          );
    }
    if (widget.recovery != null && widget.saver == null) {
      return (widget.recoveryService ??
              MissedPlanRecoveryService(clock: widget.clock))
          .save(
            widget.recovery!,
            draft,
            selection,
            manualQuery: _manualQuery,
            expectedVersion: existing?.version,
            expectedUpdatedAt: existing?.updatedAt,
            newStatus: newStatus,
          );
    }
    if (widget.saver != null) {
      return widget.saver!(
        draft,
        selection,
        expectedVersion: existing?.version,
        expectedUpdatedAt: existing?.updatedAt,
        newStatus: newStatus,
      );
    }
    if (selection != null) {
      return PlanAvailabilityRepository(clock: widget.clock).save(
        selection,
        draft,
        expectedVersion: existing?.version,
        expectedUpdatedAt: existing?.updatedAt,
        beforeWrite: (executor) async {
          if (existing == null || existing.todoId != draft.todoId) {
            await _checkLinkedTodo(executor, draft);
          }
          await _checkPreparationSchedule(executor, draft.todoId);
        },
      );
    }
    return StorageService.savePlanBlockEdited(
      widget.username,
      draft,
      expectedVersion: existing?.version,
      expectedUpdatedAt: existing?.updatedAt,
      newStatus: newStatus,
      beforeWrite: (executor) async {
        if ((await StorageService.getLoginSession() ?? 'default') !=
            widget.username) {
          throw const PlanAvailabilityException('账号已切换，请重新打开编辑器');
        }
        if (existing == null || existing.todoId != draft.todoId) {
          await _checkLinkedTodo(executor, draft);
        }
        await _checkPreparationSchedule(executor, draft.todoId);
      },
    );
  }

  Future<PlanAvailabilitySelection> _checkReuseTime() async {
    final preferences = await PlanAvailabilityPreferences.load(widget.username);
    var appOnly = _manualQuery?.appOnly ?? false;
    while (true) {
      final query = PlanAvailabilityQuery(
        username: widget.username,
        todoId: _selectedTodoId!,
        date: _start,
        minutes: _end.difference(_start).inMinutes,
        windowStart: 0,
        windowEnd: 1440,
        appOnly: appOnly,
        bufferBefore: _manualQuery?.bufferBefore ?? preferences.bufferBefore,
        bufferAfter: _manualQuery?.bufferAfter ?? preferences.bufferAfter,
        bufferOverride: _manualQuery?.bufferOverride ?? false,
        bufferDefaultsKey:
            _manualQuery?.bufferDefaultsKey ?? preferences.bufferKey,
        avoidanceOverride: _manualQuery?.avoidanceOverride ?? false,
        avoidanceDefaultsKey:
            _manualQuery?.avoidanceDefaultsKey ?? preferences.avoidanceKey,
        avoidWindows:
            _manualQuery?.avoidWindows ??
            [
              for (final i in preferences.selectedIndices)
                preferences.options[i],
            ],
      );
      try {
        final repository = PlanAvailabilityRepository(clock: widget.clock);
        final fresh = await repository.read(query, forceRefresh: true);
        final candidate = PlanAvailabilitySelection(
          query,
          PlanTimeSlot(_start, _end),
          fresh,
        );
        if (!PlanAvailabilityService.accepts(
          candidate,
          fresh,
          now: widget.clock?.call() ?? DateTime.now(),
        )) {
          throw const PlanAvailabilityException('时段已过去、被占用或不符合避让，请重新选择');
        }
        return candidate;
      } on PlanAvailabilityException catch (error) {
        if (!error.canUseAppOnly || appOnly || !mounted) rethrow;
        final fallback = await showAppDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('手机日历读取失败'),
            content: Text(error.message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('仅检查应用内日程'),
              ),
            ],
          ),
        );
        if (fallback != true) rethrow;
        appOnly = true;
      }
    }
  }

  Future<void> _chooseSplit({PlanAvailabilityQuery? query}) async {
    if (_busy || !_canSplit || _splitPersisted) return;
    final initial =
        _split?.query ??
        PlanSplitQuery(
          query ??
              PlanAvailabilityQuery(
                username: widget.username,
                todoId: _selectedTodoId!,
                date: _manualQuery?.date ?? _start,
                minutes: _end.difference(_start).inMinutes,
                windowStart: _manualQuery?.windowStart ?? 480,
                windowEnd: _manualQuery?.windowEnd ?? 1320,
                avoidWindows: _manualQuery?.avoidWindows ?? const [],
                appOnly: _manualQuery?.appOnly ?? false,
                bufferBefore: _manualQuery?.bufferBefore ?? 0,
                bufferAfter: _manualQuery?.bufferAfter ?? 0,
                bufferOverride: _manualQuery?.bufferOverride ?? false,
                bufferDefaultsKey: _manualQuery?.bufferDefaultsKey,
                avoidanceOverride: _manualQuery?.avoidanceOverride ?? false,
                avoidanceDefaultsKey: _manualQuery?.avoidanceDefaultsKey,
                weekly: _manualQuery?.weekly,
              ),
        );
    final result = await Navigator.of(context).push<PlanSplitSelection>(
      MaterialPageRoute(
        builder: (_) => PlanSplitScreen(
          todo: _selectedTodo!,
          initialQuery: initial,
          clock: widget.clock,
          requireDurationConfirmation:
              _split == null &&
              widget.autoRecommendTime &&
              _estimatedMinutes == null &&
              _recommendation == null,
        ),
      ),
    );
    if (!mounted || result == null) return;
    _mutateState(() {
      if (_split == null) {
        _singleStart = _start;
        _singleEnd = _end;
        _singleQuery = _manualQuery;
      }
      _touch();
      _manualChange();
      _split = result;
      _restored = false;
      _splitAdjusted = false;
      _splitStale = false;
      _splitIds = [
        _targetPlanId,
        for (var i = 1; i < result.slots.length; i++) const Uuid().v4(),
      ];
      _start = result.slots.first.start;
      _end = result.slots.first.end;
    });
  }

  Future<void> _returnSingle() async {
    if (_busy || _splitPersisted) return;
    if (_splitAdjusted) {
      final yes = await showAppDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('放弃已调整的分段？'),
          content: const Text('备注、提醒和番茄设置会保留。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('返回单段'),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
    }
    _mutateState(() {
      _touch();
      _manualChange();
      _start = _singleStart ?? _start;
      _end = _singleEnd ?? _end;
      _manualQuery = _singleQuery;
      _split = null;
      _splitIds = [];
    });
  }

  Future<void> _adjustSplit(int index) async {
    if (_busy || _splitPersisted) return;
    final selection = _split!, old = selection.slots[index];
    final date = await showAppDatePicker(
      context: context,
      initialDate: old.start,
      firstDate: selection.query.base.dayStart,
      lastDate: CalendarDateMath.inclusiveEndDate(selection.query.endDate),
    );
    if (date == null || !mounted) return;
    final time = await showAppTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(old.start),
    );
    if (time == null || !mounted) return;
    _mutateState(() => _busy = true);
    try {
      final start = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      final replacement = PlanTimeSlot(
        start,
        start.add(Duration(minutes: old.minutes)),
      );
      // Reserve stable group-position UUIDs until the first atomic commit.
      // Reordering times must not replace the original draft's target anchor.
      final slots = [
        for (var i = 0; i < selection.slots.length; i++)
          i == index ? replacement : selection.slots[i],
      ]..sort((a, b) => a.start.compareTo(b.start));
      final manualSplit = selection.query.configure(
        base: selection.query.base.withWeekly(null),
      );
      final fresh = await PlanAvailabilityRepository(clock: widget.clock)
          .readSplit(
            manualSplit,
            forceRefresh: true,
            requireCalendar: selection.snapshot.includesCalendar,
          );
      if (!PlanSplitService.accepts(
        manualSplit,
        slots,
        fresh,
        now: widget.clock?.call() ?? DateTime.now(),
      )) {
        throw const PlanAvailabilityException('调整后的整组时段不可用，请避开其他分段和日程');
      }
      if (mounted) {
        _mutateState(() {
          _touch();
          _manualChange();
          _splitAdjusted = true;
          _splitStale = false;
          _split = PlanSplitSelection(manualSplit, slots, fresh);
          _start = slots.first.start;
          _end = slots.first.end;
        });
      }
    } catch (e) {
      _reportError(e);
    } finally {
      if (mounted) _mutateState(() => _busy = false);
    }
  }

  Widget _splitPreview() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        key: const ValueKey('plan-split-preview'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${_split!.slots.length}段 · 共${_split!.query.total}分钟',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (_splitStale)
            const Text(
              '安排或状态已变化，保存前将重新核对整组；也可重新选择整组。',
              key: ValueKey('plan-split-stale'),
            ),
          if (_splitPersisted)
            const Text(
              '分段已保存；这里只能重试启动第1段或关闭此页面。',
              key: ValueKey('plan-split-persisted'),
            ),
          for (var i = 0; i < _split!.slots.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('第${i + 1}段 · ${splitTimeLabel(_split!.slots[i])}'),
                  if (_pomodoroRounds > 0)
                    Text(
                      '本段专注${_pomodoroRounds * _pomodoroMinutes}分钟；固定轮数可能超出时段',
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _busy || _splitPersisted
                          ? null
                          : () => _adjustSplit(i),
                      child: const Text('调整本段'),
                    ),
                  ),
                ],
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: _busy || _splitPersisted ? null : _chooseSplit,
                child: const Text('重新选择整组'),
              ),
              TextButton(
                onPressed: _busy || _splitPersisted ? null : _returnSingle,
                child: const Text('返回单段'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Future<TodoPlanBlock> _saveDraft() async {
    if (_draftLoading) throw StateError('正在恢复草稿，请稍候');
    if (_draftRestoreFailed) throw StateError('草稿未能恢复，请先重试或返回列表');
    if (_selectedTodoId == null || !_end.isAfter(_start)) {
      throw const PlanAvailabilityException('请选择待办，并设置有效的开始和结束时间');
    }
    if (widget.block == null || widget.block!.todoId != _selectedTodoId) {
      final todo = _selectedTodo;
      if (todo == null || todo.isDone || todo.isDeleted || todo.isSkipped) {
        throw const PlanAvailabilityException('待办已完成、已跳过或失效，请选择未完成的待办');
      }
    }
    if (_persistedBlock != null && _savedDraftRevision == _draftRevision) {
      return _persistedBlock!;
    }
    if (_localDraft != null && _persistedBlock == null) {
      await _identityReady;
      if (_identityError != null) throw _identityError!;
      final latestDraft = await _drafts.read(_saveIdentity!, _localDraft!.id);
      if (latestDraft.revision != _localDraft!.revision) {
        throw StateError('草稿已更新，请重新读取后保存');
      }
      if (await _drafts.target(_saveIdentity!, _localDraft!) != null) {
        throw StateError('这份草稿已保存为规划，请从规划草稿查看，勿重复提交');
      }
    }
    final TodoPlanBlock saved;
    final preparationSelection = _preparationContext == null
        ? null
        : await _verifyPreparationTime();
    if (_split != null) {
      if (_restored) {
        final weekly = await _restoredWeeklyContext();
        final updated = await splitWithCurrentDefaults(
          _split!.query,
          useWeekly: _restoredScheduleOrigin != 'manual',
        );
        _split = PlanSplitSelection(
          updated.configure(base: updated.base.withWeekly(weekly)),
          _split!.slots,
          _split!.snapshot,
        );
      }
      if (_offsetChanged) throw StateError('时区已变化，请先确认当前显示的日期与时间');
      await _confirmNewArrangements(_selectedTodoId!);
      final blocks = [
        for (var i = 0; i < _split!.slots.length; i++)
          TodoPlanBlock(
              id: _splitIds[i],
              todoId: _selectedTodoId!,
              startTime: _split!.slots[i].start.millisecondsSinceEpoch,
              endTime: _split!.slots[i].end.millisecondsSinceEpoch,
            )
            ..titleSnapshot = _selectedTodo?.title
            ..plannedMinutes = _split!.slots[i].minutes
            ..remark = _remarkCtrl.text.isEmpty ? null : _remarkCtrl.text
            ..reminderMinutes = _reminderMinutes
            ..pomodoroMinutes = _pomodoroMinutes
            ..pomodoroRounds = _pomodoroRounds,
      ];
      final all = await PlanAvailabilityRepository(clock: widget.clock)
          .saveSplit(
            _split!,
            blocks,
            beforeWrite: (executor) => _checkLinkedTodo(executor, blocks.first),
          );
      _savedSplitBlocks = all;
      _splitStale = false;
      saved = all.first;
    } else {
      await _verifyRestoredTime();
      if (_recommendation != null && _recommendationStale) {
        throw const PlanAvailabilityException('推荐时段已失效，请重新查找或手动修改时间');
      }
      final draft = _persistedBlock == null
          ? TodoPlanBlock(
              id: _targetPlanId,
              todoId: _selectedTodoId!,
              startTime: _start.millisecondsSinceEpoch,
              endTime: _end.millisecondsSinceEpoch,
            )
          : TodoPlanBlock.fromJson(_persistedBlock!.toJson());
      draft
        ..todoId = _selectedTodoId!
        ..titleSnapshot = _selectedTodo?.title
        ..startTime = _start.millisecondsSinceEpoch
        ..endTime = _end.millisecondsSinceEpoch
        ..plannedMinutes = _end.difference(_start).inMinutes
        ..remark = _remarkCtrl.text.isEmpty ? null : _remarkCtrl.text
        ..reminderMinutes = _reminderMinutes
        ..pomodoroMinutes = _pomodoroMinutes
        ..pomodoroRounds = _pomodoroRounds;
      await _identityReady;
      if (_identityError != null && widget.saver == null) throw _identityError!;
      final committed =
          _isReuse && _persistedBlock == null && widget.saver == null
          ? await _reuseRepository.savedTarget(_saveIdentity!, draft)
          : null;
      if (committed != null) {
        saved = committed;
      } else {
        await _confirmNewArrangements(draft.todoId);
        saved = await _persist(
          draft,
          _preparationContext == null ? _recommendation : preparationSelection,
        );
      }
    }
    _persistedBlock = saved;
    _savedDraftRevision = _draftRevision;
    _baseline = _fields.fingerprint;
    _userTouched = false;
    _reuseNeedsRetention = false;
    if (_localDraft != null) {
      try {
        await _drafts.delete(
          _saveIdentity!,
          _localDraft!.id,
          _localDraft!.revision,
        );
        _localDraft = null;
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('规划已保存，但本机草稿清理失败；恢复时会识别已有规划')),
          );
        }
      }
    }
    widget.onSaved();
    if (widget.recovery != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已新建规划，原漏做记录已保留')));
    }
    return saved;
  }

  void _reportError(Object error, {bool focus = false}) {
    if (!mounted) return;
    final text = error is PlanAvailabilityException
        ? error.message
        : error is StateError
        ? error.message.toString()
        : '操作失败，请重试';
    _mutateState(
      () => _operationError = _focusStarted
          ? '专注已启动，后续操作失败：$text；可重试更新状态'
          : focus &&
                _savedDraftRevision == _draftRevision &&
                _persistedBlock != null
          ? '规划已保存，专注未启动：$text'
          : text,
    );
  }

  Future<void> _save() async {
    if (_busy || _openingReuse) return;
    _mutateState(() {
      _busy = true;
      _operationError = null;
    });
    try {
      if (!_focusStarted) await _saveDraft();
      await _popEditor();
    } catch (error) {
      _reportError(error);
    } finally {
      if (mounted) _mutateState(() => _busy = false);
    }
  }

  Future<void> _saveAndStartFocus() async {
    if (_busy || _openingReuse) return;
    _mutateState(() {
      _busy = true;
      _operationError = null;
    });
    try {
      final block = _focusStarted ? _persistedBlock! : await _saveDraft();
      var todo = _selectedTodo;
      if (todo == null) throw const PlanAvailabilityException('待办已失效，请重新打开编辑器');
      if (!_focusStarted && widget.saver == null) {
        if ((await StorageService.getLoginSession() ?? 'default') !=
            widget.username) {
          throw const PlanAvailabilityException('账号已切换，请重新打开编辑器');
        }
        final db = await DatabaseHelper.instance.databaseForUser(
          widget.username,
        );
        final blocks = await db.query(
          'todo_plan_blocks',
          where: 'uuid = ?',
          whereArgs: [block.id],
        );
        await _identityReady;
        if (_identityError != null) throw _identityError!;
        final freshTodo = await PlanTodoGuard.read(
          db,
          _saveIdentity!,
          block.todoId,
        );
        if (blocks.isEmpty ||
            blocks.single['version'] != block.version ||
            blocks.single['updated_at'] != block.updatedAt ||
            blocks.single['is_deleted'] == 1 ||
            freshTodo.isDone ||
            freshTodo.isDeleted ||
            freshTodo.isSkipped) {
          throw const PlanAvailabilityException('规划或待办已变化，请读取最新记录');
        }
        todo = freshTodo;
      }
      if (!_focusStarted && _split != null) {
        final db = await DatabaseHelper.instance.databaseForUser(
          widget.username,
        );
        await PlanTodoGuard.validate(db, _saveIdentity!, block.todoId);
        for (final saved in _savedSplitBlocks) {
          final rows = await db.query(
            'todo_plan_blocks',
            where: 'uuid=?',
            whereArgs: [saved.id],
          );
          if (rows.isEmpty ||
              rows.single['version'] != saved.version ||
              rows.single['updated_at'] != saved.updatedAt ||
              rows.single['is_deleted'] == 1 ||
              rows.single['has_conflict'] == 1) {
            throw const PlanAvailabilityException('分段规划已变化，请核对已有安排');
          }
        }
        final fresh = await PlanAvailabilityRepository(clock: widget.clock)
            .readSplit(
              _split!.query,
              forceRefresh: true,
              requireCalendar: _split!.snapshot.includesCalendar,
            );
        final clean = PlanSplitSnapshot([
          for (final day in fresh.days)
            PlanAvailabilitySnapshot(
              todo: day.todo,
              coverage: day.coverage,
              busy: day.busy
                  .where(
                    (b) =>
                        b.source != PlanBusySource.planBlock ||
                        !_splitIds.contains(b.id),
                  )
                  .toList(),
            ),
        ]);
        if (!PlanSplitService.accepts(
          _split!.query,
          _split!.slots,
          clean,
          now: widget.clock?.call() ?? DateTime.now(),
        )) {
          throw const PlanAvailabilityException('分段时段已变化，规划已保存；专注未启动');
        }
      }
      if (!_focusStarted && widget.saver == null && _recommendation != null) {
        final repository = PlanAvailabilityRepository(clock: widget.clock);
        final snapshot = await repository.read(
          _recommendation!.query,
          forceRefresh: true,
          requireCalendar: _recommendation!.snapshot.deviceCalendarIncluded,
        );
        final check = PlanAvailabilitySnapshot(
          todo: snapshot.todo,
          busy: snapshot.busy.where((item) => item.id != block.id).toList(),
          coverage: snapshot.coverage,
        );
        final db = await DatabaseHelper.instance.databaseForUser(
          widget.username,
        );
        final rows = await db.query(
          'todo_plan_blocks',
          where: 'uuid = ?',
          whereArgs: [block.id],
        );
        if (rows.isEmpty ||
            rows.single['version'] != block.version ||
            rows.single['updated_at'] != block.updatedAt ||
            !PlanAvailabilityService.accepts(
              _recommendation!,
              check,
              now: widget.clock?.call() ?? DateTime.now(),
            )) {
          throw const PlanAvailabilityException('规划或时段已变化，请读取最新记录');
        }
      }
      if (!_focusStarted && widget.saver == null && widget.recovery != null) {
        final service =
            widget.recoveryService ??
            MissedPlanRecoveryService(clock: widget.clock);
        await service.validate(widget.recovery!, ignoreBlockId: block.id);
        final start = DateTime.fromMillisecondsSinceEpoch(block.startTime);
        final end = DateTime.fromMillisecondsSinceEpoch(block.endTime);
        final query = PlanAvailabilityQuery(
          username: widget.username,
          todoId: block.todoId,
          date: start,
          minutes: block.plannedMinutes,
          windowStart: 0,
          windowEnd: 1440,
          excludeBlockId: block.id,
          appOnly: _manualQuery?.appOnly ?? false,
          bufferBefore: _manualQuery?.bufferBefore ?? 0,
          bufferAfter: _manualQuery?.bufferAfter ?? 0,
          bufferOverride: _manualQuery?.bufferOverride ?? false,
          bufferDefaultsKey: _manualQuery?.bufferDefaultsKey,
          avoidanceOverride: _manualQuery?.avoidanceOverride ?? false,
          avoidanceDefaultsKey: _manualQuery?.avoidanceDefaultsKey,
          avoidWindows: _manualQuery?.avoidWindows ?? const [],
        );
        final latest = await service.availability.read(
          query,
          forceRefresh: true,
          requireCalendar:
              _recommendation?.snapshot.deviceCalendarIncluded ?? false,
        );
        if (!PlanAvailabilityService.accepts(
          PlanAvailabilitySelection(query, PlanTimeSlot(start, end), latest),
          latest,
          now: service.now,
        )) {
          throw const MissedPlanRecoveryException('规划时段已失效或被占用，请读取最新安排');
        }
      }
      if (widget.navigateOnFocus) {
        widget.onSaved();
        if (!mounted) return;
        final navigator = Navigator.of(context);
        final sourceRect = PageTransitions.rectForKey(_focusActionSourceKey);
        final sourceColor = Theme.of(context).colorScheme.surface;
        await _popEditor();
        final openPomodoro = widget.openPomodoro;
        final page = PomodoroScreen(
          username: widget.username,
          initialEntry: PomodoroEntryIntent.forPlanBlock(
            boundTodo: todo,
            planBlock: block,
          ),
        );
        if (openPomodoro != null) {
          await openPomodoro(block, todo);
        } else if (sourceRect != null) {
          await PageTransitions.pushFromRectSnapshot<void>(
            navigator: navigator,
            page: page,
            sourceRect: sourceRect,
            sourceColor: sourceColor,
            placeholderIcon: Icons.timer_outlined,
          );
        } else {
          navigator.push(PageTransitions.material(builder: (_) => page));
        }
        return;
      }
      if (!_focusStarted) {
        if (widget.startFocus != null) {
          await widget.startFocus!(block, todo);
        } else {
          final settings = await PomodoroService.getSettings();
          final previousRun = await PomodoroService.loadRunState();
          try {
            await PomodoroControlService.startFocus(
              settings: settings,
              boundTodo: todo,
              durationMinutes: max(
                1,
                block.pomodoroRounds > 0
                    ? block.pomodoroMinutes * block.pomodoroRounds
                    : block.plannedMinutes,
              ),
              planBlockId: block.uuid,
            );
          } catch (_) {
            // Native notification/DND initialization may fail after the run
            // marker was saved. Retrying must not create another session.
            final run = await PomodoroService.loadRunState();
            if (run != null &&
                run.planBlockId == block.id &&
                run.phase == PomodoroPhase.focusing &&
                run.sessionUuid != previousRun?.sessionUuid) {
              _focusStarted = true;
            }
            rethrow;
          }
        }
        _focusStarted = true;
      }
      try {
        _persistedBlock = await _persist(
          block,
          null,
          newStatus: TodoPlanStatus.focusing,
        );
      } catch (_) {
        if (mounted) {
          _mutateState(() => _operationError = '专注已启动，但规划状态更新失败；可重试更新状态');
        }
        return;
      }
      widget.onSaved();
      if (!mounted) return;
      await _popEditor();
    } catch (error) {
      _reportError(error, focus: true);
    } finally {
      if (mounted) _mutateState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (widget.block == null || _busy || _openingReuse) return;
    await StorageService.deletePlanBlockGlobally(
      widget.username,
      widget.block!.id,
    );
    widget.onSaved();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _reusePlan() async {
    if (_busy || _openingReuse || _draftLoading || !_canReuse) return;
    if (_dirty) {
      _reportError(StateError('请先保存修改，或放弃修改后重新打开'));
      return;
    }
    _mutateState(() => _openingReuse = true);
    try {
      await _identityReady;
      if (_identityError != null) throw _identityError!;
      await _saveIdentity!.check();
      final seed = await _reuseRepository.read(
        widget.username,
        widget.block!.id,
      );
      if (!mounted) return;
      await seed.identity.check();
      await _saveIdentity!.check();
      if (!mounted) return;
      if (!await _confirmReuseSettingsCorrections(seed)) return;
      if (!mounted) return;
      await seed.identity.check();
      await _saveIdentity!.check();
      if (!mounted) return;
      if (_dirty) throw StateError('请先保存修改，或放弃修改后重新打开');
      final todos = [
        for (final t in widget.todos)
          if (t.id != widget.block!.todoId) t,
        if (seed.todo != null) seed.todo!,
      ];
      await showPlanBlockEditorPage<void>(
        context: context,
        builder: (_) => PlanBlockEditorSheet(
          fullPage: true,
          username: widget.username,
          reuse: seed,
          reuseRepository: widget.reuseRepository,
          startTime: seed.start,
          endTime: seed.end,
          todos: todos,
          todoGroups: widget.todoGroups,
          autoFillEstimateOnTodoChange: true,
          availabilityLoader: widget.availabilityLoader,
          continuousRangeLoader: widget.continuousRangeLoader,
          saver: widget.saver,
          startFocus: widget.startFocus,
          openPomodoro: widget.openPomodoro,
          estimate: widget.estimate,
          clock: widget.clock,
          navigateOnFocus: widget.navigateOnFocus,
          draftRepository: widget.draftRepository,
          onManageDrafts: widget.onManageDrafts,
          onSaved: widget.onSaved,
        ),
      );
    } catch (error) {
      if (mounted) _reportError(error);
    } finally {
      if (mounted) _mutateState(() => _openingReuse = false);
    }
  }

  Future<bool> _confirmReuseSettingsCorrections(PlanReuseSeed seed) async {
    final corrections = seed.settings.corrections;
    if (corrections.isEmpty) return true;

    final accepted = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: const Text('部分设置需要调整'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 360),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('这些设置不在当前可选范围内。继续后只调整新规划，原规划保持不变。'),
                  const SizedBox(height: 14),
                  for (final correction in corrections)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: colors.secondaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            correction.label,
                            style: Theme.of(dialogContext).textTheme.labelLarge
                                ?.copyWith(color: colors.onSecondaryContainer),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${correction.originalValue} → ${correction.replacementValue}',
                            style: Theme.of(dialogContext).textTheme.bodyMedium
                                ?.copyWith(color: colors.onSecondaryContainer),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('按建议继续'),
            ),
          ],
        );
      },
    );
    return accepted == true;
  }

  bool get _canManualComplete =>
      widget.block != null &&
      widget.onManualCompleted != null &&
      PlanManualCompletionService.supports(
        widget.block!,
        _manualCompletion.now,
      );

  Future<void> _manualComplete() async {
    if (!_canManualComplete || _busy || _openingReuse || _draftLoading) return;
    final route = ModalRoute.of(context);
    if (route?.isCurrent == false) return;
    if (_dirty) {
      _reportError(StateError('请先保存修改，或放弃修改后重新打开'));
      return;
    }
    _mutateState(() => _busy = true);
    try {
      await _identityReady;
      if (_identityError != null) throw _identityError!;
      await _saveIdentity!.check();
      final request = await _manualCompletion.prepare(
        widget.username,
        widget.block!.id,
        expected: widget.block,
      );
      if (!mounted || route?.isCurrent == false) return;
      if (_dirty) throw StateError('请先保存修改，或放弃修改后重新打开');
      final block = request.block;
      final format = AppTimeFormats.dateFormatter('M月d日 HH:mm');
      final confirmed = await showAppDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('确认这次规划已完成？'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  block.titleSnapshot?.trim().isNotEmpty == true
                      ? block.titleSnapshot!
                      : '这次规划',
                ),
                const SizedBox(height: 8),
                Text(
                  '${format.format(DateTime.fromMillisecondsSinceEpoch(block.startTime))} — ${format.format(DateTime.fromMillisecondsSinceEpoch(block.endTime))}',
                ),
                const SizedBox(height: 16),
                const Text('仅将这次规划标为已完成。不会改变待办完成状态，也不会新增专注记录。'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('返回核对'),
            ),
            FilledButton(
              key: const ValueKey('plan-manual-confirm'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('确认完成'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || route?.isCurrent == false) return;
      if (_dirty) throw StateError('请先保存修改，或放弃修改后重新打开');
      final receipt = await _manualCompletion.confirm(request);
      await receipt.identity.check();
      if (!mounted || route?.isCurrent == false) {
        receipt.invalidate();
        return;
      }
      _allowExit = true;
      widget.onSaved();
      Navigator.pop(context);
      widget.onManualCompleted!(receipt);
    } catch (error) {
      if (mounted) _reportError(error);
    } finally {
      if (mounted) _mutateState(() => _busy = false);
    }
  }

  Future<void> _skip() async {
    if (widget.block == null || _busy || _openingReuse) return;
    final block = widget.block!;
    block.status = TodoPlanStatus.skipped;
    block.markAsChanged();
    await StorageService.savePlanBlocks(widget.username, [block]);
    widget.onSaved();
    if (mounted) Navigator.pop(context);
  }
}
