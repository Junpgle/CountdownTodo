part of 'todo_section_widget.dart';

extension _TodoEditScreenSections on TodoEditScreenState {
  Widget _buildRecurrenceScopeSummary(ColorScheme colorScheme) {
    if (_isWholeSeriesEdit) {
      return _buildWholeSeriesSummary(colorScheme);
    }
    final seriesId = TodoRecurrenceSeriesEditService.seriesIdFor(_editingTodo);
    final counts = seriesId == null
        ? null
        : TodoRecurrenceSeriesEditService.countMembers(
            _editorTodos,
            seriesId,
            now: _now,
          );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.event_repeat_rounded,
            size: 18,
            color: colorScheme.secondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              counts == null
                  ? '本次保存会修改本期及之后已经生成的周期。'
                  : '本次会修改本期及之后 ${counts.total - counts.historical} 期；未来周期也会沿用新规则。',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWholeSeriesSummary(ColorScheme colorScheme) {
    final seriesId = TodoRecurrenceSeriesEditService.seriesIdFor(_editingTodo);
    final occurrences = seriesId == null
        ? <TodoItem>[_editingTodo]
        : TodoRecurrenceSeriesEditService.activeMembers(_editorTodos, seriesId);
    final counts = seriesId == null
        ? null
        : TodoRecurrenceSeriesEditService.countMembers(
            _editorTodos,
            seriesId,
            now: _now,
          );
    final baseDateLabel = AppTimeFormats.dateFormatter(
      _isAllDay ? 'M月d日' : 'M月d日 HH:mm',
    ).format(_originalCreatedDate);

    return Container(
      key: const ValueKey('series_scope_summary'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '整个系列 · ${counts?.total ?? occurrences.length} 期',
                      key: const ValueKey('series_scope_title'),
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              TextButton(
                key: const ValueKey('series_occurrence_details_toggle'),
                onPressed: () => _mutateState(
                  () => _showSeriesOccurrenceDetails =
                      !_showSeriesOccurrenceDetails,
                ),
                child: Text(
                  _showSeriesOccurrenceDetails
                      ? '收起期次'
                      : '查看 ${occurrences.length} 期',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (counts != null) ...[
            Text(
              '历史 ${counts.historical} · 今天 ${counts.current} · 未来 ${counts.future}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 2),
            Text(
              '已完成 ${counts.completed} · 已跳过 ${counts.skipped} · 各期状态保留',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '日期变化以 $baseDateLabel 这期为基准',
            key: const ValueKey('series_date_shift_anchor'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (_showSeriesOccurrenceDetails) ...[
            const Divider(height: 20),
            for (final occurrence in occurrences)
              _buildSeriesOccurrenceRow(occurrence, colorScheme),
          ],
        ],
      ),
    );
  }

  Widget _buildSeriesOccurrenceRow(
    TodoItem occurrence,
    ColorScheme colorScheme,
  ) {
    final start = AppTimeFormats.localFromServerTimestamp(
      occurrence.createdDate ?? occurrence.createdAt,
    );
    final isCurrent = occurrence.id == _editingTodo.id;
    final status = _seriesOccurrenceStatus(occurrence, start);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppTimeFormats.dateFormatter('M月d日').format(start),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                Text(
                  status,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (isCurrent)
            Text(
              '当前基准',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            TextButton(
              key: ValueKey('series_set_anchor_${occurrence.id}'),
              onPressed: () => _switchToRelatedOccurrence(occurrence),
              child: const Text('设为基准'),
            ),
        ],
      ),
    );
  }

  String _seriesOccurrenceStatus(TodoItem occurrence, DateTime start) {
    if (occurrence.isDone) return '已完成';
    if (occurrence.isSkipped) return '已跳过';
    if (start.isAfter(_now)) return '未开始';
    final due =
        occurrence.dueDate?.toLocal() ??
        AppTimeFormats.localDayStartOffset(start, 1);
    return due.isBefore(_now) ? '已逾期' : '待完成';
  }

  Widget _buildRelatedRecurrenceSection(ColorScheme colorScheme) {
    final seriesId = TodoRecurrenceSeriesEditService.seriesIdFor(_editingTodo);
    final occurrences = seriesId == null
        ? <TodoItem>[_editingTodo]
        : TodoRecurrenceSeriesEditService.activeMembers(_editorTodos, seriesId);
    final isRecurrenceSeries =
        _editingTodo.recurrence != RecurrenceType.none ||
        _editingTodo.recurrenceSeriesId?.isNotEmpty == true;
    if (!isRecurrenceSeries || _isWholeSeriesEdit) {
      return const SizedBox.shrink();
    }

    return OptionalLiquidGlassCard(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      borderRadius: 16,
      highContrast: true,
      fallbackDecoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_tree_rounded,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '关联周期',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                '${occurrences.length} 期',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TodoRecurrenceCompletionOverview(
            occurrences: occurrences,
            currentTodoId: _editingTodo.id,
            currentIsDone: _isDone,
            currentIsSkipped: _editingTodo.isSkipped,
          ),
          if (occurrences.length > 1) ...[
            const SizedBox(height: 12),
            Text(
              '当前期已居中，点击其他期次可在本页切换编辑',
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            TodoRecurrenceOccurrencePicker(
              occurrences: occurrences,
              currentTodoId: _editingTodo.id,
              onSelected: _switchToRelatedOccurrence,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFocusRecordsSection() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isLoadingRecords) {
      return const AppSkeletonSheetList(
        itemCount: 2,
        itemHeight: 42,
        shrinkWrap: true,
        padding: EdgeInsets.symmetric(vertical: 8),
      );
    }

    if (_focusRecords.isEmpty) return const SizedBox.shrink();

    final totalFocusSeconds = _totalFocusSeconds;
    final focusedOccurrenceCount = _focusedPeriodCount;
    final isRecurrenceSeries =
        _editingTodo.recurrenceSeriesId?.isNotEmpty == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        KeyedSubtree(
          key: _focusKey,
          child: const Text(
            "专注记录",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(Icons.timer_rounded, color: colorScheme.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isRecurrenceSeries ? '循环累计专注' : '累计专注',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    Text(
                      PomodoroService.formatDuration(totalFocusSeconds),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                isRecurrenceSeries
                    ? '${_focusRecords.length} 次 · $focusedOccurrenceCount 期'
                    : '${_focusRecords.length} 次',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
        ..._focusRecords.take(20).map((r) {
          final startLocal = AppTimeFormats.localFromServerTimestamp(
            r.startTime,
          );
          final durationMin = r.effectiveDuration ~/ 60;
          final statusIcon = r.isCompleted
              ? Icons.check_circle_rounded
              : Icons.timer_off_rounded;
          final statusColor = r.isCompleted ? Colors.green : Colors.orange;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Navigator.push(
                  context,
                  PageTransitions.material(
                    builder: (_) => PomodoroDetailScreen(record: r, tags: []),
                  ),
                );
              },
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(statusIcon, size: 18, color: statusColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${AppTimeFormats.dateFormatter('MM-dd HH:mm').format(startLocal)} · $durationMin 分钟',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (r.note != null && r.note!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            r.note!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        if (_focusRecords.length > 20)
          Text(
            '仅显示最近 20 条',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        if (_focusRecords.isNotEmpty) const SizedBox(height: 8),
      ],
    );
  }

  Future<void> _createPlanBlock() async {
    final todo = _editingTodo;
    if (_isDone || todo.isDone || todo.isDeleted) return;
    final now = _now;
    final dayStart = DateTime(now.year, now.month, now.day, 8);
    final start = PlanAvailabilityService.minuteCeiling(
      now.isAfter(dayStart) ? now : dayStart,
    );
    await showPlanBlockEditorPage<void>(
      context: context,
      builder: (_) => PlanBlockEditorSheet(
        fullPage: true,
        username: widget.username,
        todos: [todo],
        todoGroups: _editorGroups,
        initialTodoId: todo.id,
        startTime: start,
        endTime: start.add(const Duration(minutes: 30)),
        autoFillEstimateOnTodoChange: false,
        autoRecommendTime: true,
        draftOrigin: 'todo',
        onManageDrafts: () => openPlanEditorDrafts(
          context,
          widget.username,
          onSaved: () {
            if (mounted) _loadRelatedPlans();
          },
        ),
        onSaved: () {
          if (mounted) _loadRelatedPlans();
        },
      ),
    );
  }

  Widget _buildPlanBlockSection() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KeyedSubtree(
          key: _planKey,
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                "计划安排",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                key: const ValueKey('todo-create-plan-block'),
                onPressed:
                    _isDone || _editingTodo.isDone || _editingTodo.isDeleted
                    ? null
                    : _createPlanBlock,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('新建规划块'),
              ),
              TextButton.icon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    PageTransitions.material(
                      builder: (_) => TodoPlanScreen(
                        username: widget.username,
                        initialDate: _now,
                        initialTodoId: widget.todo.id,
                      ),
                    ),
                  );
                  if (!mounted) return;
                  _loadRelatedPlans();
                },
                icon: const Icon(Icons.calendar_today, size: 16),
                label: const Text("今日计划"),
              ),
            ],
          ),
        ),
        if (_isDone || _editingTodo.isDone)
          PlanCleanupEntry(
            key: ValueKey('cleanup-entry-${_editingTodo.id}'),
            username: widget.username,
            todoId: _editingTodo.id,
            completionSaved: _isDone && _editingTodo.isDone,
            onReturn: _loadRelatedPlans,
          ),
        const SizedBox(height: 12),
        OptionalLiquidGlassCard(
          width: double.infinity,
          borderRadius: 16,
          highContrast: true,
          fallbackDecoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
          ),
          child: _isLoadingPlans
              ? const AppSkeletonSheetList(
                  itemCount: 2,
                  itemHeight: 42,
                  shrinkWrap: true,
                  padding: EdgeInsets.all(12),
                )
              : _relatedPlanBlocks.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      Icon(
                        Icons.event_note_outlined,
                        size: 40,
                        color: Colors.grey.withValues(alpha: 0.3),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        "暂无为此任务制定的时间计划",
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // ── 统计摘要 ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      child: _buildPlanBlockSummary(colorScheme),
                    ),
                    const Divider(height: 1),
                    // ── 规划块列表 ──
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      findItemIndexCallback: (Key key) {
                        if (key is ValueKey<String>) {
                          final id = key.value;
                          final idx = _relatedPlanBlocks.indexWhere(
                            (p) => p.id == id,
                          );
                          return idx != -1 ? idx : null;
                        }
                        return null;
                      },
                      itemCount: _relatedPlanBlocks.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final plan = _relatedPlanBlocks[index];
                        final start = DateTime.fromMillisecondsSinceEpoch(
                          plan.startTime,
                        );
                        final end = DateTime.fromMillisecondsSinceEpoch(
                          plan.endTime,
                        );
                        return RepaintBoundary(
                          key: ValueKey<String>(plan.id),
                          child: ListTile(
                            onTap: () async {
                              await Navigator.push(
                                context,
                                PageTransitions.material(
                                  builder: (_) => TodoPlanScreen(
                                    username: widget.username,
                                    initialDate: CalendarDateMath.dateOnly(
                                      start,
                                    ),
                                    initialTodoId: widget.todo.id,
                                  ),
                                ),
                              );
                              _loadRelatedPlans();
                            },
                            leading: Icon(
                              Icons.access_time_filled,
                              color: colorScheme.primary.withValues(alpha: 0.7),
                            ),
                            title: Text(
                              "${AppTimeFormats.dateFormatter('MM-dd').format(start)} ${AppTimeFormats.dateFormatter('HH:mm').format(start)} - ${AppTimeFormats.dateFormatter('HH:mm').format(end)}",
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Text("预计专注 ${plan.plannedMinutes} 分钟"),
                            trailing: const Icon(
                              Icons.chevron_right,
                              size: 20,
                              color: Colors.grey,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildPlanBlockSummary(ColorScheme colorScheme) {
    final blocks = _relatedPlanBlocks;
    final planned = blocks.fold<int>(0, (s, b) => s + b.plannedMinutes);
    final actual = blocks.fold<int>(
      0,
      (s, b) => s + b.actualFocusSeconds ~/ 60,
    );
    final done = blocks
        .where(
          (b) =>
              b.status == TodoPlanStatus.finished ||
              (b.plannedMinutes > 0 &&
                  b.actualFocusSeconds >= b.plannedMinutes * 60 * 0.9),
        )
        .length;
    final missed = blocks
        .where((b) => b.status == TodoPlanStatus.missed)
        .length;
    final rate = planned <= 0 ? 0.0 : (actual / planned).clamp(0.0, 999.0);

    Widget chip(String label, String value, Color color) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.20)),
          ),
          child: Column(
            children: [
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('计划', '${planned}m', Colors.deepPurple),
        const SizedBox(width: 6),
        chip('实际', '${actual}m', Colors.green),
        const SizedBox(width: 6),
        chip(
          '达成',
          '${(rate * 100).round()}%',
          Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 6),
        chip('完成', '$done', Colors.teal),
        const SizedBox(width: 6),
        chip('漏做', '$missed', Colors.redAccent),
      ],
    );
  }

  Widget _buildSquareTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(minHeight: 105),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.01),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPopupSquareTile<T>({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required T value,
    required List<PopupMenuEntry<T>> items,
    required ValueChanged<T> onSelected,
  }) {
    return PopupMenuButton<T>(
      initialValue: value,
      onOpened: () => FocusManager.instance.primaryFocus?.unfocus(),
      onSelected: onSelected,
      itemBuilder: (context) => items,
      offset: const Offset(0, 45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: _buildSquareTile(
        title: title,
        subtitle: subtitle,
        icon: icon,
        color: color,
        onTap: null, // Let PopupMenu handle it
      ),
    );
  }

  String _getReminderText(int minutes) {
    if (minutes == 0) return "准时提醒";
    if (minutes < 60) return "提前 $minutes 分钟";
    if (minutes < 1440) return "提前 ${minutes ~/ 60} 小时";
    return "提前 ${minutes ~/ 1440} 天";
  }

  String _getRecurrenceLabel(RecurrenceType type) {
    switch (type) {
      case RecurrenceType.none:
        return "不重复";
      case RecurrenceType.daily:
        return "每天";
      case RecurrenceType.weekly:
        return "每周";
      case RecurrenceType.monthly:
        return "每月";
      case RecurrenceType.yearly:
        return "每年";
      case RecurrenceType.weekdays:
        return "工作日";
      case RecurrenceType.customDays:
        return "自定义";
    }
  }

  Widget _buildCompactTeamSection() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "完成规则",
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(
            width: 140,
            child: _buildCustomSegmentedControl(
              labels: const ["全队同步", "各自独立"],
              selectedIndex: _collabType,
              onChanged: (idx) => _mutateState(() => _collabType = idx),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomSegmentedControl({
    required List<String> labels,
    required int selectedIndex,
    required ValueChanged<int> onChanged,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final isSelected = selectedIndex == index;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.all(2),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? colorScheme.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : [],
                ),
                child: Text(
                  labels[index],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  void _showFullImage(BuildContext context, String imagePath) {
    Navigator.of(context).push(
      PageTransitions.material(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: FloatingGlassAppBar(
            flexibleSpace: const FloatingGlassTopBarBackground(),
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text("图片预览"),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: localImageWidget(imagePath, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }
}
