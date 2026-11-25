part of '../plan_block_editor_sheet.dart';

extension _PlanBlockEditorDrafts on _PlanBlockEditorSheetState {
  bool get _dirty =>
      _reuseNeedsRetention ||
      (_userTouched && _fields.fingerprint != _baseline);
  void _touch() => _userTouched = true;
  void _automaticBaseline() {
    if (!_userTouched) _baseline = _fields.fingerprint;
  }

  Future<void> _readDraftOffer() async {
    if (!_supportsDraft ||
        (widget.saver != null && widget.draftRepository == null)) {
      return;
    }
    final sequence = ++_draftReadSequence;
    final todoId = _selectedTodoId;
    if (_draftOffer != null || _draftLoadError != null) {
      _mutateState(() {
        _draftOffer = null;
        _draftLoadError = null;
      });
    }
    if (todoId == null || _localDraft != null) return;
    try {
      await _identityReady;
      if (_identityError != null) throw _identityError!;
      final offers = await _drafts.list(_saveIdentity!, todoId: todoId);
      if (!mounted ||
          sequence != _draftReadSequence ||
          todoId != _selectedTodoId) {
        return;
      }
      _mutateState(() {
        _draftOffer = offers.where((d) => d.id != _localDraft?.id).firstOrNull;
        _draftLoadError = null;
      });
    } catch (_) {
      if (mounted && sequence == _draftReadSequence) {
        _mutateState(() => _draftLoadError = '草稿读取失败，可重试；当前表单仍可编辑');
      }
    }
  }

  Future<void> _restoreDraft(PlanEditorDraft draft) async {
    if (_busy) return;
    _mutateState(() {
      _draftLoading = true;
      _draftRestoreFailed = false;
    });
    try {
      await _identityReady;
      if (_identityError != null) throw _identityError!;
      final prepared = await _drafts.prepare(
        _saveIdentity!,
        draft.id,
        draft.revision,
      );
      if (prepared.saved != null) {
        throw StateError('这份草稿已保存为规划，请从规划草稿查看已有规划');
      }
      if (!mounted) return;
      final f = prepared.draft.fields;
      PlanSplitSelection? restoredSplit;
      if (f.split != null) {
        final payload = PlanSplitDraft.fromJson(
          f.split!.toJson(),
          widget.username,
          f.todoId,
        );
        // Loading a draft must preserve times even when the current policy is
        // damaged. Defaults and the saved policy are checked at save/re-search.
        restoredSplit = PlanSplitSelection(
          payload.query,
          payload.slots,
          const PlanSplitSnapshot([]),
        );
      }
      if (!mounted) return;
      _mutateState(() {
        _estimateSequence++;
        _draftRevision++;
        _draftReadSequence++;
        _localDraft = prepared.draft;
        _targetPlanId = prepared.draft.targetId;
        _restoredTodo = prepared.todo;
        _selectedTodoId = f.todoId;
        _restoredBacklog = prepared.backlog;
        _preparationContext = widget.preparationContext ?? f.preparationContext;
        _approvedArrangements = prepared.backlog == null ? null : '[]';
        _start = DateTime.fromMillisecondsSinceEpoch(f.start);
        _end = DateTime.fromMillisecondsSinceEpoch(f.end);
        _remarkCtrl.text = f.remark;
        _reminderMinutes = f.reminder;
        _pomodoroMinutes = f.pomodoro;
        _pomodoroRounds = f.rounds;
        _split = restoredSplit;
        _splitIds = f.split?.ids.toList() ?? [];
        _singleStart = null;
        _singleEnd = null;
        _singleQuery = null;
        _splitAdjusted = false;
        _restored = true;
        _restoredScheduleOrigin = f.scheduleOrigin;
        _restoredWeeklyKey = f.weeklyKey;
        _restoredWeeklyIgnored = f.weeklyIgnored;
        _offsetChanged =
            f.offsetMinutes != _start.timeZoneOffset.inMinutes ||
            (f.split?.timeZoneChanged ?? false);
        _recommendation = null;
        _manualQuery = null;
        _estimatedMinutes = null;
        _estimateResult = null;
        _allowAutoRecommendation = false;
        _autoRecommendationPending = false;
        _initialEstimatePending = false;
        _recommendationStale = false;
        _draftOffer = null;
        _draftLoadError = null;
        _operationError = null;
        _userTouched = false;
        _reuseNeedsRetention = false;
        _rebuildTodoEntries();
        _baseline = _fields.fingerprint;
      });
    } catch (error) {
      if (widget.restoredDraft != null && mounted) {
        _mutateState(() => _draftRestoreFailed = true);
      }
      _reportError(error);
    } finally {
      if (mounted) _mutateState(() => _draftLoading = false);
    }
  }

  Future<bool> _keepDraft() async {
    if (_busy ||
        _draftRestoreFailed ||
        !_supportsDraft ||
        _persistedBlock != null) {
      return false;
    }
    if (_offsetChanged) {
      _reportError(StateError('时区已变化，请先确认当前显示的日期与时间'));
      return false;
    }
    _mutateState(() => _busy = true);
    try {
      await _identityReady;
      if (_identityError != null) throw _identityError!;
      final saved = await _drafts.keep(
        _saveIdentity!,
        _fields,
        previous: _localDraft,
        targetId: _targetPlanId,
      );
      if (!mounted) return false;
      _mutateState(() {
        _localDraft = saved;
        _baseline = _fields.fingerprint;
        _userTouched = false;
        _reuseNeedsRetention = false;
        _operationError = null;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已保留到本机规划草稿')));
      return true;
    } catch (error) {
      _reportError(error);
      return false;
    } finally {
      if (mounted) _mutateState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    if (_busy || _openingReuse || _draftLoading || _exitPrompt) return;
    if (!_dirty) {
      await _popEditor();
      return;
    }
    _exitPrompt = true;
    final action = await showAppDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(_supportsDraft ? '保留这次规划？' : '放弃未保存的修改？'),
        content: Text(
          _localDraft != null
              ? '放弃修改也会删除这份本机草稿。保留后可稍后继续。'
              : '时段、备注、番茄和提醒设置还没有保存为规划。',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(c),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, 'discard'),
            child: const Text('放弃修改'),
          ),
          if (_supportsDraft && _persistedBlock == null)
            FilledButton(
              onPressed: () => Navigator.pop(c, 'keep'),
              child: const Text('保留草稿并离开'),
            ),
        ],
      ),
    );
    _exitPrompt = false;
    if (!mounted || action == null) return;
    if (action == 'keep') {
      if (!await _keepDraft()) return;
    } else if (_localDraft != null) {
      _mutateState(() => _busy = true);
      try {
        await _drafts.delete(
          _saveIdentity!,
          _localDraft!.id,
          _localDraft!.revision,
        );
        _localDraft = null;
      } catch (error) {
        _reportError(error);
        return;
      } finally {
        if (mounted) _mutateState(() => _busy = false);
      }
    }
    await _popEditor();
  }

  Future<void> _popEditor() async {
    if (!mounted) return;
    _mutateState(() => _allowExit = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickDraftDate() async {
    final now = widget.clock?.call() ?? DateTime.now();
    final date = await showAppDatePicker(
      context: context,
      initialDate: _start.isBefore(now) ? now : _start,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 10),
    );
    if (date == null || !mounted) return;
    _mutateState(() {
      _touch();
      _manualChange();
      final duration = _end.difference(_start);
      _start = DateTime(
        date.year,
        date.month,
        date.day,
        _start.hour,
        _start.minute,
      );
      _end = _start.add(duration);
    });
  }

  Future<void> _openDraftOffer() async {
    final offer = _draftOffer;
    if (offer == null || _busy || _draftLoading) return;
    if (_dirty) {
      final replace = await showAppDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('继续上次草稿？'),
          content: const Text('这会替换当前尚未保留的输入。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('继续当前编辑'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('继续上次草稿'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }
    try {
      _mutateState(() => _draftLoading = true);
      final draft = await _drafts.read(_saveIdentity!, offer.id);
      if (mounted) await _restoreDraft(draft);
    } catch (error) {
      _reportError(error);
    } finally {
      if (mounted) _mutateState(() => _draftLoading = false);
    }
  }

  Widget _draftNotice() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_draftLoading) const LinearProgressIndicator(),
      if (_draftRestoreFailed) ...[
        const Text('草稿未能恢复，当前不能保存。可重试或返回草稿列表查看保留内容。'),
        TextButton(
          onPressed: () => _restoreDraft(widget.restoredDraft!),
          child: const Text('重试恢复'),
        ),
      ],
      if (_draftLoadError != null)
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(_draftLoadError!),
            TextButton(onPressed: _readDraftOffer, child: const Text('重试读取草稿')),
          ],
        ),
      if (_draftOffer != null)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.drafts_outlined),
          title: const Text('此待办有未完成的本机草稿'),
          subtitle: Text(
            AppTimeFormats.dateFormatter('M月d日 HH:mm').format(
              DateTime.fromMillisecondsSinceEpoch(_draftOffer!.updatedAt),
            ),
          ),
          onTap: _openDraftOffer,
          trailing: const Icon(Icons.chevron_right),
        ),
      if (_restored) ...[
        Text(
          _offsetChanged ? '时区已变化，请确认当前显示的日期与时间' : '草稿已恢复，请重新核对时段；保存前会检查最新安排。',
          key: const ValueKey('plan-draft-restored'),
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              key: const ValueKey('plan-draft-date'),
              onPressed: _busy
                  ? null
                  : _split == null
                  ? _pickDraftDate
                  : _chooseSplit,
              icon: const Icon(Icons.edit_calendar_outlined),
              label: Text(_split == null ? '修改日期' : '修改分段条件'),
            ),
            if (_offsetChanged)
              TextButton(
                onPressed: () => _mutateState(() {
                  _touch();
                  _offsetChanged = false;
                }),
                child: const Text('确认当前时区时间'),
              ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    ],
  );

  Future<PlanWeeklyContext?> _restoredWeeklyContext() async {
    if (!_restored || _restoredScheduleOrigin == 'manual') return null;
    if (_restoredWeeklyIgnored) {
      throw const PlanAvailabilityException(
        '草稿的本次不使用每周规则已失效，请重新查找并明确选择，或改为手动安排',
      );
    }
    final saved = await PlanWeeklyAvailabilityPreferences.load(widget.username);
    if (saved.error != null) throw PlanAvailabilityException(saved.error!);
    if (_restoredWeeklyKey != null && _restoredWeeklyKey != saved.key) {
      throw const PlanAvailabilityException('草稿的每周可安排时间已变化，请重新查找或改为手动安排');
    }
    return PlanWeeklyContext(saved.rules);
  }

  Future<void> _verifyRestoredTime() async {
    if (!_restored) return;
    if (_offsetChanged) throw StateError('时区已变化，请先确认当前显示的日期与时间');
    final weekly = await _restoredWeeklyContext();
    final preferences = await PlanAvailabilityPreferences.load(widget.username);
    if (preferences.bufferError != null &&
        !(_manualQuery?.bufferOverride ?? false)) {
      throw PlanAvailabilityException(preferences.bufferError!);
    }
    var appOnly =
        _manualQuery?.appOnly ?? _recommendation?.query.appOnly ?? false;
    while (true) {
      final query = PlanAvailabilityQuery(
        username: widget.username,
        weekly: weekly,
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
        final latest =
            await (widget.availabilityLoader?.call(query) ??
                PlanAvailabilityRepository(clock: widget.clock)
                    .read(query, forceRefresh: true));
        final selection = PlanAvailabilitySelection(
          query,
          PlanTimeSlot(_start, _end),
          latest,
        );
        if (!PlanAvailabilityService.accepts(
          selection,
          latest,
          now: widget.clock?.call() ?? DateTime.now(),
        )) {
          throw const PlanAvailabilityException('草稿时段已过期、被占用或不符合避让，请重新选择时段');
        }
        _recommendation = selection;
        _recommendationStale = false;
        return;
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

  Future<void> _captureSaveIdentity() async {
    try {
      _saveIdentity =
          widget.reuse?.identity ??
          _backlog?.identity ??
          await PlanTodoIdentity.capture(widget.username);
      await _saveIdentity!.check();
    } catch (error) {
      _identityError = error;
    }
  }

  Future<void> _checkLinkedTodo(
    DatabaseExecutor executor,
    TodoPlanBlock draft,
  ) async {
    await _identityReady;
    if (_identityError != null) throw _identityError!;
    final identity = _saveIdentity!;
    if (_localDraft != null) {
      await _drafts.validateRevision(executor, identity, _localDraft!);
    }
    await PlanTodoGuard.validate(executor, identity, draft.todoId);
    if (_backlog != null) {
      if (draft.todoId != _backlog!.todoId) {
        throw const PlanAvailabilityException('待办已变化，请重新打开清单');
      }
      await PlanTodoGuard.validateBacklog(
        executor,
        _backlog!,
        _approvedArrangements ?? _backlog!.arrangements,
        DateTime.fromMillisecondsSinceEpoch(draft.startTime),
        DateTime.fromMillisecondsSinceEpoch(draft.endTime),
        widget.clock?.call() ?? DateTime.now(),
      );
    }
    if (_isReuse && _backlog == null) {
      await PlanTodoGuard.validateBacklog(
        executor,
        PlanBacklogSaveContext(
          identity,
          draft.todoId,
          _approvedArrangements ?? '[]',
        ),
        _approvedArrangements ?? '[]',
        DateTime.fromMillisecondsSinceEpoch(draft.startTime),
        DateTime.fromMillisecondsSinceEpoch(draft.endTime),
        widget.clock?.call() ?? DateTime.now(),
      );
    }
    if (_split != null && _backlog == null && !_isReuse) {
      final latest = await PlanTodoGuard.arrangements(
        executor,
        draft.todoId,
        widget.clock?.call() ?? DateTime.now(),
      );
      if (latest != (_approvedArrangements ?? '[]')) {
        throw const PlanAvailabilityException('待办安排已变化，请重新确认追加整组');
      }
    }
    await identity.check();
  }

  Future<void> _confirmNewArrangements(String todoId) async {
    if ((_backlog == null && _split == null && !_isReuse) ||
        widget.saver != null) {
      return;
    }
    await _identityReady;
    if (_identityError != null) throw _identityError!;
    final db = await DatabaseHelper.instance.databaseForUser(widget.username);
    await PlanTodoGuard.validate(db, _saveIdentity!, todoId);
    final latest = await PlanTodoGuard.arrangements(
      db,
      todoId,
      widget.clock?.call() ?? DateTime.now(),
    );
    if (latest == (_approvedArrangements ?? _backlog?.arrangements ?? '[]')) {
      return;
    }
    if (latest == '[]') {
      _approvedArrangements = latest;
      return;
    }
    if (!mounted) throw const PlanAvailabilityException('页面已关闭');
    final append = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_isReuse ? '此待办已有安排' : '此待办已有新的安排'),
        content: Text(
          _isReuse
              ? '本次会新增独立规划，原安排保留。可先查看已有安排，再决定是否追加。'
              : '编辑期间安排已变化。查看已有安排，或确认仍追加这次规划。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('查看已有安排'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('仍追加这次规划'),
          ),
        ],
      ),
    );
    if (append != true) {
      if (append == false) await widget.onViewExisting?.call();
      if (append == false &&
          _isReuse &&
          widget.onViewExisting == null &&
          mounted) {
        final rows = await db.query(
          'todo_plan_blocks',
          columns: ['start_time', 'end_time', 'status'],
          where: 'todo_uuid=? AND COALESCE(is_deleted,0)=0 AND status IN (0,2,4,5) AND end_time>?',
          whereArgs: [
            todoId,
            (widget.clock?.call() ?? DateTime.now()).millisecondsSinceEpoch,
          ],
          orderBy: 'start_time',
          limit: 20,
        );
        await _saveIdentity!.check();
        if (mounted) {
          await showAppDialog<void>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('已有安排'),
              content: SingleChildScrollView(
                child: Text(
                  rows
                      .map(
                        (r) =>
                            '${AppTimeFormats.dateFormatter('MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(r['start_time'] as int))}–${AppTimeFormats.dateFormatter('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(r['end_time'] as int))}',
                      )
                      .join('\n'),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('返回编辑'),
                ),
              ],
            ),
          );
        }
      }
      throw const PlanAvailabilityException('尚未追加，草稿已保留');
    }
    _approvedArrangements = latest;
  }

  void _manualChange() {
    _autoRecommendationPending = false;
    _draftRevision++;
    _estimateSequence++;
    _recommendation = null;
    _recommendationStale = false;
    _operationError = null;
    _restoredScheduleOrigin = 'manual';
    _restoredWeeklyKey = null;
    _restoredWeeklyIgnored = false;
  }

  Future<void> _checkPreparationSchedule(
    DatabaseExecutor executor,
    String todoId,
  ) async {
    final context = _preparationContext ?? widget.preparationContext;
    if (context == null) return;
    await FixedSchedulePreparationGuard.validate(
      executor,
      context,
      todoId,
      now: widget.clock?.call() ?? DateTime.now(),
    );
  }

  Future<PlanAvailabilitySelection> _verifyPreparationTime() async {
    final context = _preparationContext ?? widget.preparationContext;
    final todo = _selectedTodo;
    if (context == null || todo == null || _selectedTodoId == null) {
      throw const PlanAvailabilityException('准备安排上下文已失效，请重新打开固定日程');
    }
    final preferences = await PlanAvailabilityPreferences.load(widget.username);
    if (preferences.bufferError != null) {
      throw PlanAvailabilityException(preferences.bufferError!);
    }
    final weekly = await PlanWeeklyAvailabilityPreferences.load(
      widget.username,
    );
    if (weekly.error != null || weekly.rules == null) {
      throw PlanAvailabilityException(weekly.error ?? '每周可安排时间无法读取，请修复规则后重试');
    }
    final query = PlanAvailabilityQuery(
      username: widget.username,
      todoId: todo.id,
      date: _start,
      minutes: _end.difference(_start).inMinutes,
      windowStart: 0,
      windowEnd: 1440,
      appOnly: context.appOnly,
      bufferBefore: preferences.bufferBefore,
      bufferAfter: preferences.bufferAfter,
      bufferDefaultsKey: preferences.bufferKey,
      avoidanceDefaultsKey: preferences.avoidanceKey,
      avoidWindows: [
        for (final index in preferences.selectedIndices)
          preferences.options[index],
      ],
      preparationEnd: DateTime.fromMillisecondsSinceEpoch(context.startTime)
          .toLocal(),
      weekly: PlanWeeklyContext(weekly.rules),
    );
    final repository = PlanAvailabilityRepository(clock: widget.clock);
    await PlanAvailabilityPreferences.validateQueryDefaults(query);
    final fresh = await repository.read(query, forceRefresh: true);
    final selection = PlanAvailabilitySelection(
      query,
      PlanTimeSlot(_start, _end),
      fresh,
    );
    if (!PlanAvailabilityService.accepts(
      selection,
      fresh,
      now: widget.clock?.call() ?? DateTime.now(),
    )) {
      throw const PlanAvailabilityException('准备时段已过期、被占用或越过固定日程开始时间，请重新查找');
    }
    return selection;
  }
}
