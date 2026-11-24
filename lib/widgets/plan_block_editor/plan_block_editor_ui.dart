part of '../plan_block_editor_sheet.dart';

extension _PlanBlockEditorUi on _PlanBlockEditorSheetState {
  String _todoGroupLabel(TodoItem todo) {
    final groupId = todo.groupId;
    if (groupId == null || groupId.isEmpty) return '未分类';
    return widget.todoGroups
            .cast<TodoGroup?>()
            .firstWhere((group) => group?.id == groupId, orElse: () => null)
            ?.name ??
        '未知分类';
  }

  String _todoUrgencyLabel(TodoItem todo) {
    final target = todo.dueDate;
    if (target == null) return '无时间';
    return _planBlockEditorDateFormat('MM-dd HH:mm').format(target);
  }

  Widget _buildTodoDropdownRow(TodoItem todo) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 86),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            _todoGroupLabel(todo),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            todo.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              decoration: todo.isDone ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          todo.isDone ? '已完成' : _todoUrgencyLabel(todo),
          style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration(String label) {
    final colors = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: colors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: colors.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: colors.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    );
  }

  Future<void> _pickTime(bool start) async {
    final value = start ? _start : _end;
    final time = await showAppTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(value),
    );
    if (time == null || !mounted) return;
    _mutateState(() {
      _touch();
      _manualChange();
      final changed = DateTime(
        value.year,
        value.month,
        value.day,
        time.hour,
        time.minute,
      );
      if (start) {
        _start = changed;
      } else {
        _end = changed;
      }
    });
  }

  Widget _timeField(bool start) {
    final theme = Theme.of(context);
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: theme.colorScheme.onSurface,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: () => _pickTime(start),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            start ? '开始时间' : '结束时间',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _planBlockEditorDateFormat('HH:mm').format(start ? _start : _end),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(EdgeInsets padding, {required bool showIcon}) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showIcon) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.edit_calendar_outlined,
                color: theme.colorScheme.onPrimaryContainer,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.recovery != null
                      ? '重新安排'
                      : widget.block == null
                      ? '添加规划块'
                      : '编辑规划块',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '为待办留出专属时间',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (widget.block != null)
            PopupMenuButton<String>(
              tooltip: '更多操作',
              enabled: !_busy && !_draftLoading,
              onSelected: (value) {
                if (value == 'manual-complete') unawaited(_manualComplete());
                if (value == 'reuse') unawaited(_reusePlan());
                if (value == 'skip') _skip();
                if (value == 'delete') _delete();
              },
              itemBuilder: (_) => [
                if (_canManualComplete)
                  PopupMenuItem(
                    enabled: !_openingReuse,
                    value: 'manual-complete',
                    child: Text('确认规划已完成'),
                  ),
                if (_canReuse)
                  PopupMenuItem(
                    value: 'reuse',
                    enabled: !_busy && !_openingReuse && !_draftLoading,
                    child: Text(_openingReuse ? '正在读取设置…' : '照此新建'),
                  ),
                PopupMenuItem(
                  enabled: !_openingReuse,
                  value: 'skip',
                  child: const Text('跳过规划'),
                ),
                PopupMenuItem(
                  value: 'delete',
                  enabled: !_openingReuse,
                  child: Text(
                    '删除规划',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ),
          IconButton(
            tooltip: '关闭',
            onPressed: () => unawaited(_leave()),
            icon: const Icon(Icons.close, size: 22),
          ),
        ],
      ),
    );
  }

  Widget _formSection(IconData icon, String title) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildReuseNotice(ThemeData theme, ColorScheme colors) {
    final duration = _split?.query.total ?? _end.difference(_start).inMinutes;
    final unverified =
        _recommendation == null && _split == null && _persistedBlock == null;
    final corrections = _reuseSettingsAdjustments;
    if (corrections.isEmpty) {
      return Text(
        unverified
            ? '沿用已有规划设置 · $duration分钟\n时段尚未核实，请选择推荐或调整'
            : '沿用已有规划设置 · $duration分钟',
        key: const ValueKey('plan-reuse-notice'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      );
    }

    return Container(
      key: const ValueKey('plan-reuse-notice'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '沿用已有规划设置 · $duration分钟',
            style: theme.textTheme.titleSmall?.copyWith(
              color: colors.onSecondaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (unverified) ...[
            const SizedBox(height: 4),
            Text(
              '时段尚未核实，请选择推荐或调整',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSecondaryContainer,
              ),
            ),
          ],
          const SizedBox(height: 6),
          for (final correction in corrections)
            Text(
              correction,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSecondaryContainer,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            '调整仅应用于新规划，原规划保持不变。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  Widget _form(double width, double scale, EdgeInsets padding) {
    if (_draftRestoreFailed) {
      return Padding(padding: padding, child: _draftNotice());
    }
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final horizontalTimes = width >= 360 && scale < 1.7;
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _draftNotice(),
          if (_isReuse)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildReuseNotice(theme, colors),
            ),
          if (widget.recovery != null) ...[
            Text(
              '原安排：${_planBlockEditorDateFormat('MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(widget.recovery!.source.startTime))}–${_planBlockEditorDateFormat('MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(widget.recovery!.source.endTime))} · 漏做',
              key: const ValueKey('plan-recovery-origin'),
            ),
            for (final notice in widget.recovery!.notices)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colors.tertiaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 17,
                        color: colors.onTertiaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          notice,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onTertiaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
          ],
          _formSection(Icons.checklist_outlined, '规划内容'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('plan-todo-picker-$_selectedTodoId'),
            initialValue: _selectedTodoId,
            isExpanded: true,
            items: _todoEntries
                .map(
                  (entry) => DropdownMenuItem(
                    value: entry.value,
                    enabled: entry.todo != null && !entry.todo!.isDone,
                    child: entry.todo == null
                        ? Text(
                            entry.header!,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: colors.primary,
                            ),
                          )
                        : _buildTodoDropdownRow(entry.todo!),
                  ),
                )
                .toList(),
            selectedItemBuilder: (context) => _todoEntries
                .map(
                  (entry) => entry.todo == null
                      ? const SizedBox.shrink()
                      : Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            entry.todo!.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                )
                .toList(),
            onChanged:
                widget.recovery != null ||
                    widget.conflictEdit != null ||
                    !_hasSelectableTodos ||
                    _split != null
                ? null
                : (value) {
                    if (value == null || value.startsWith('__todo_header_')) {
                      return;
                    }
                    _mutateState(() {
                      _touch();
                      _selectedTodoId = value;
                      _approvedArrangements = null;
                      _selectedTodoMetadata = _currentTodoMetadata;
                      _estimatedMinutes = null;
                      _estimateResult = null;
                      _manualChange();
                    });
                    if (widget.autoFillEstimateOnTodoChange) {
                      _prefillEstimate(value);
                    }
                    unawaited(_readDraftOffer());
                  },
            decoration: _fieldDecoration('待办项目'),
          ),
          if (_selectedTodoId == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _hasSelectableTodos ? '原待办已完成或失效，请重新选择未完成待办' : '暂无可规划的未完成待办',
                key: const ValueKey('plan-no-unfinished-todos'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          if (_estimateResult != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TimeEstimationHint(result: _estimateResult!),
            ),
          const SizedBox(height: 20),
          if (_split != null)
            _splitPreview()
          else ...[
            _formSection(Icons.schedule_outlined, '安排时间'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${_planBlockEditorDateFormat('M月d日').format(_start)} 周${['一', '二', '三', '四', '五', '六', '日'][_start.weekday - 1]}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${_end.difference(_start).inMinutes} 分钟',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: colors.primaryContainer.withValues(alpha: 0.35),
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.15),
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: horizontalTimes
                  ? Row(
                      children: [
                        Expanded(child: _timeField(true)),
                        Icon(
                          Icons.arrow_forward,
                          size: 18,
                          color: colors.onSurfaceVariant,
                        ),
                        Expanded(child: _timeField(false)),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _timeField(true),
                        Divider(
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                          color: colors.outlineVariant,
                        ),
                        _timeField(false),
                      ],
                    ),
            ),
          ],
          const SizedBox(height: 16),
          if (_split == null && _initialEstimatePending)
            const Padding(
              key: ValueKey('plan-initial-estimate'),
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  LinearProgressIndicator(),
                  SizedBox(height: 8),
                  Text('正在预测完成时间…'),
                ],
              ),
            )
          else if (_split == null)
            PlanAvailabilityPanel(
              username: widget.username,
              resultsOnly: widget.fullPage,
              autoLookupResults:
                  _isReuse ||
                  !widget.autoRecommendTime ||
                  _estimatedMinutes != null,
              todo: _selectedTodo,
              initialDate: _start,
              initialMinutes: _end.difference(_start).inMinutes,
              editingBlock: _persistedBlock,
              estimatedMinutes: _estimatedMinutes,
              loader: widget.availabilityLoader,
              rangeLoader: widget.continuousRangeLoader,
              onSplitRequested: _canSplit
                  ? (q) => _chooseSplit(query: q)
                  : null,
              clock: widget.clock,
              initialExpanded:
                  widget.recovery != null || widget.autoRecommendTime,
              autoLookupAndSelect: _allowAutoRecommendation,
              autoSelectionRevision: _draftRevision,
              onAutoLookupPendingChanged: (pending) {
                if (mounted && _autoRecommendationPending != pending) {
                  _mutateState(() => _autoRecommendationPending = pending);
                }
              },
              dateShortcuts: widget.recovery != null,
              onQueryChanged: (query) => _manualQuery = query,
              onDateChanged: widget.recovery == null
                  ? null
                  : (date) => _mutateState(() {
                      final duration = _end.difference(_start);
                      _manualChange();
                      _start = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        _start.hour,
                        _start.minute,
                      );
                      _end = _start.add(duration);
                    }),
              onInvalidated: () {
                _estimateSequence++;
                if (_recommendation != null && mounted) {
                  _mutateState(() => _recommendationStale = true);
                }
              },
              onSelected: (selection) => _mutateState(() {
                final automatic = _autoRecommendationPending;
                if (!automatic) _touch();
                _estimateSequence++;
                _draftRevision++;
                _recommendation = selection;
                _restored = false;
                _recommendationStale = false;
                _start = selection.slot.start;
                _end = selection.slot.end;
                _operationError = null;
                _automaticBaseline();
              }),
            ),
          if (_canSplit && _split == null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('plan-open-split'),
                onPressed: _busy || _initialEstimatePending
                    ? null
                    : _chooseSplit,
                icon: const Icon(Icons.splitscreen_outlined),
                label: const Text('分段安排'),
              ),
            ),
          if (_restored && _restoredScheduleOrigin != 'manual')
            TextButton(
              key: const ValueKey('plan-draft-use-manual'),
              onPressed: _busy
                  ? null
                  : () => _mutateState(() {
                      _touch();
                      _manualChange();
                      if (_split != null) {
                        _split = PlanSplitSelection(
                          _split!.query.configure(
                            base: _split!.query.base.withWeekly(null),
                          ),
                          _split!.slots,
                          _split!.snapshot,
                        );
                        _splitAdjusted = true;
                      }
                    }),
              child: const Text('保留此时间，改为手动安排'),
            ),
          if (_recommendation != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _recommendationStale ? '推荐时段已失效，请重新查找' : '已填入推荐时段，保存前会再次检查。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _recommendationStale ? colors.error : colors.primary,
                ),
              ),
            ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: 0.6),
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _formSection(Icons.tune, '其他设置'),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('plan-remark'),
                  controller: _remarkCtrl,
                  readOnly: _splitPersisted,
                  onChanged: (_) => _mutateState(() {
                    _touch();
                    _draftRevision++;
                    _autoRecommendationPending = false;
                  }),
                  decoration: _fieldDecoration('备注（可选）'),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns =
                        ((constraints.maxWidth >= 300 && scale <= 1.15) ||
                            (constraints.maxWidth >= 460 && scale < 1.6))
                        ? 3
                        : (constraints.maxWidth >= 240 && scale < 1.6 ? 2 : 1);
                    final fieldWidth =
                        (constraints.maxWidth - 12 * (columns - 1)) / columns;
                    Widget option(
                      String label,
                      int value,
                      List<int> values,
                      String Function(int) title,
                      ValueChanged<int?> changed,
                    ) => SizedBox(
                      width: fieldWidth,
                      child: DropdownButtonFormField<int>(
                        key: ValueKey('plan-option-$label'),
                        initialValue: value,
                        isExpanded: true,
                        decoration: _fieldDecoration(label).copyWith(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 14,
                          ),
                        ),
                        style: theme.textTheme.bodySmall,
                        iconSize: 20,
                        items: values
                            .map(
                              (item) => DropdownMenuItem(
                                value: item,
                                child: Text(
                                  title(item) == '按规划时长' && fieldWidth < 120
                                      ? '按时长'
                                      : title(item),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _splitPersisted ? null : changed,
                      ),
                    );
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        option(
                          '单轮番茄',
                          _pomodoroMinutes,
                          [15, 20, 25, 30, 45, 60],
                          (m) => '$m 分钟',
                          (v) => _mutateState(() {
                            _touch();
                            _draftRevision++;
                            _pomodoroMinutes = v ?? 25;
                          }),
                        ),
                        option(
                          _split == null ? '番茄轮数' : '每段番茄轮数',
                          _pomodoroRounds,
                          [0, 1, 2, 3, 4, 5, 6],
                          (m) => m == 0 ? '按规划时长' : '$m 轮',
                          (v) => _mutateState(() {
                            _touch();
                            _draftRevision++;
                            _pomodoroRounds = v ?? 0;
                          }),
                        ),
                        option(
                          '提前提醒',
                          _reminderMinutes,
                          [0, 5, 10, 15, 30],
                          (m) => m == 0 ? '不提醒' : '$m 分钟前',
                          (v) => _mutateState(() {
                            _touch();
                            _draftRevision++;
                            _reminderMinutes = v ?? 5;
                          }),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer(double width, double scale, EdgeInsets padding) {
    final colors = Theme.of(context).colorScheme;
    final save = FilledButton(
      key: const ValueKey('plan-save'),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed:
          _busy ||
              _draftLoading ||
              _draftRestoreFailed ||
              _autoRecommendationPending ||
              (_selectedTodoId == null && !_focusStarted)
          ? null
          : _save,
      child: Text(
        _focusStarted
            ? '关闭'
            : _splitPersisted
            ? '完成'
            : _split != null
            ? '保存全部${_split!.slots.length}段'
            : '保存规划',
      ),
    );
    final focus = KeyedSubtree(
      key: _focusActionSourceKey,
      child: OutlinedButton.icon(
        key: const ValueKey('plan-save-focus'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed:
            _busy ||
                _draftLoading ||
                _draftRestoreFailed ||
                _autoRecommendationPending ||
                (_selectedTodoId == null && !_focusStarted)
            ? null
            : _saveAndStartFocus,
        icon: const Icon(Icons.play_arrow_rounded, size: 20),
        label: Text(
          _focusStarted
              ? '重试更新专注状态'
              : _splitPersisted
              ? _operationError?.startsWith('规划已保存，专注未启动') == true
                    ? '重试开始第1段'
                    : '进入第1段番茄钟'
              : _split != null
              ? '保存全部并进入番茄钟'
              : '保存并进入番茄钟',
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          top: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.block?.status == TodoPlanStatus.missed &&
              widget.onRecover != null)
            TextButton.icon(
              key: const ValueKey('plan-recover-from-editor'),
              onPressed: _busy
                  ? null
                  : () async {
                      final route = ModalRoute.of(context);
                      final recover = widget.onRecover!;
                      await _leave();
                      if (!_allowExit) return;
                      await route?.completed;
                      recover();
                    },
              icon: const Icon(Icons.event_repeat),
              label: const Text('重新安排'),
            ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(),
            ),
          if (_operationError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _operationError!,
                key: const ValueKey('plan-save-error'),
                style: TextStyle(color: colors.error),
              ),
            ),
          if (_operationError != null && widget.onManageDrafts != null)
            TextButton(
              onPressed: _busy ? null : widget.onManageDrafts,
              child: const Text('管理规划草稿'),
            ),
          if (_operationError != null &&
              widget.reviewRecovery != null &&
              !_focusStarted)
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      _mutateState(() => _busy = true);
                      try {
                        await widget.reviewRecovery!(context);
                      } catch (error) {
                        _reportError(error);
                      } finally {
                        if (mounted) _mutateState(() => _busy = false);
                      }
                    },
              child: const Text('查看最新安排'),
            ),
          if (width >= 440 && scale < 1.6)
            Row(
              children: [
                Expanded(child: focus),
                const SizedBox(width: 12),
                Expanded(child: save),
              ],
            )
          else ...[
            save,
            const SizedBox(height: 10),
            focus,
          ],
        ],
      ),
    );
  }

  Widget _page(double scale) => PopScope(
    canPop: _allowExit || (!_busy && !_draftLoading && !_dirty),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(_leave());
    },
    child: Scaffold(
      key: const ValueKey('plan-block-editor-page'),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        centerTitle: false,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
        leading: BackButton(onPressed: () => unawaited(_leave())),
        actions: [
          if (_supportsDraft)
            PopupMenuButton<String>(
              tooltip: '更多操作',
              onSelected: (value) {
                if (value == 'keep') unawaited(_keepDraft());
                if (value == 'manage') widget.onManageDrafts?.call();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'keep',
                  enabled:
                      !_busy &&
                      !_draftLoading &&
                      !_draftRestoreFailed &&
                      _persistedBlock == null,
                  child: const Text('保留草稿'),
                ),
                if (widget.onManageDrafts != null)
                  const PopupMenuItem(value: 'manage', child: Text('规划草稿')),
              ],
            ),
        ],
        title: Text(
          widget.conflictEdit != null
              ? '调整规划'
              : widget.recovery != null
              ? '重新安排'
              : '新建规划块',
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final inset = width >= 500 ? 24.0 : 16.0;
                final form = _form(
                  width,
                  scale,
                  EdgeInsets.fromLTRB(inset, 12, inset, 16),
                );
                final footer = _footer(
                  width,
                  scale,
                  EdgeInsets.fromLTRB(inset, 16, inset, 16),
                );
                final compact =
                    constraints.maxHeight < 320 ||
                    (constraints.maxHeight < 480 && scale > 1.3);
                return IgnorePointer(
                  ignoring: _busy || _draftLoading,
                  child: compact
                      ? SingleChildScrollView(
                          child: Column(children: [form, footer]),
                        )
                      : Column(
                          children: [
                            Expanded(child: SingleChildScrollView(child: form)),
                            footer,
                          ],
                        ),
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}
