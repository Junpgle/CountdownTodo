part of '../add_todo_screen.dart';

extension _AddTodoManualTabExt on _AddTodoScreenState {
  List<String> _extractKeywords() {
    final text = _titleCtrl.text.trim().toLowerCase();
    final tokens = <String>[];
    for (final m in _latinKeywordPattern.allMatches(text)) {
      if (m.group(0)!.length >= 2) tokens.add(m.group(0)!);
    }
    for (final m in _cjkKeywordPattern.allMatches(text)) {
      final seg = m.group(0)!;
      for (int i = 0; i < seg.length; i++) {
        tokens.add(seg[i]);
      }
      for (int i = 0; i < seg.length - 1; i++) {
        tokens.add(seg.substring(i, i + 2));
      }
    }
    return tokens;
  }

  void _applyClassificationSuggestion() {
    _unfocusActiveInput();
    final suggestion = _classificationSuggestion;
    if (suggestion == null) return;
    final kws = _extractKeywords();
    // Record positive feedback
    if (suggestion.hasGroup) {
      SuggestionFeedbackService.record(
        keywords: kws,
        suggestionType: 'group',
        suggestedValue: suggestion.groupId!,
        accepted: true,
      );
    }
    SuggestionFeedbackService.record(
      keywords: kws,
      suggestionType: 'priority',
      suggestedValue: '${suggestion.priority}',
      accepted: true,
    );
    for (final tag in suggestion.tags) {
      SuggestionFeedbackService.record(
        keywords: kws,
        suggestionType: 'tag',
        suggestedValue: tag,
        accepted: true,
      );
    }
    _mutateState(() {
      if (suggestion.hasGroup) {
        _selectedGroupId = suggestion.groupId;
      }
      if (suggestion.reminderMinutes != null) {
        _reminderMinutes = suggestion.reminderMinutes!;
      }
      _classificationSuggestion = null;
    });
    _onTitleChanged(force: true);
  }

  void _recordNegativeClassificationFeedback() {
    final suggestion = _classificationSuggestion;
    if (suggestion == null) return;
    final kws = _extractKeywords();
    if (suggestion.hasGroup) {
      SuggestionFeedbackService.record(
        keywords: kws,
        suggestionType: 'group',
        suggestedValue: suggestion.groupId!,
        accepted: false,
      );
    }
    SuggestionFeedbackService.record(
      keywords: kws,
      suggestionType: 'priority',
      suggestedValue: '${suggestion.priority}',
      accepted: false,
    );
    for (final tag in suggestion.tags) {
      SuggestionFeedbackService.record(
        keywords: kws,
        suggestionType: 'tag',
        suggestedValue: tag,
        accepted: false,
      );
    }
  }

  /// Record user's manual group selection as positive feedback,
  /// and negative feedback for the AI-suggested group if different.
  void _recordUserGroupChoice(String? chosenGroupId) {
    if (chosenGroupId == null) return;
    final kws = _extractKeywords();
    if (kws.isEmpty) return;

    // Positive feedback for user's choice
    SuggestionFeedbackService.record(
      keywords: kws,
      suggestionType: 'group',
      suggestedValue: chosenGroupId,
      accepted: true,
    );

    // Negative feedback for AI suggestion if user chose differently
    final suggestion = _classificationSuggestion;
    if (suggestion != null &&
        suggestion.hasGroup &&
        suggestion.groupId != chosenGroupId) {
      SuggestionFeedbackService.record(
        keywords: kws,
        suggestionType: 'group',
        suggestedValue: suggestion.groupId!,
        accepted: false,
      );
    }
  }

  Widget _buildResponsiveGrid(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isWide = constraints.maxWidth > 600;
        if (!isWide) {
          List<Widget> colChildren = [];
          for (int i = 0; i < children.length; i++) {
            colChildren.add(children[i]);
            if (i < children.length - 1) {
              colChildren.add(const Divider(height: 1));
            }
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: colChildren,
          );
        } else {
          return Wrap(
            children: children
                .map((c) => SizedBox(width: constraints.maxWidth / 2, child: c))
                .toList(),
          );
        }
      },
    );
  }

  Widget _buildRelatedFixedScheduleContext(FixedScheduleItem schedule) {
    final colors = Theme.of(context).colorScheme;
    final parsedDate = DateTime.tryParse(schedule.date)?.toLocal();
    final dateLabel = parsedDate == null
        ? schedule.date
        : _cachedDateFormat('yyyy年M月d日').format(parsedDate);
    final start = schedule.startTime == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(schedule.startTime!).toLocal();
    final end = schedule.endTime == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(schedule.endTime!).toLocal();
    final timeLabel = start == null
        ? '时间待定'
        : end == null
        ? '${_cachedDateFormat('HH:mm').format(start)} · 结束待定'
        : '${_cachedDateFormat('HH:mm').format(start)} - ${_cachedDateFormat('HH:mm').format(end)}';

    return Container(
      key: const ValueKey('related-fixed-schedule-context'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.event_available_rounded, color: colors.secondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  schedule.title.trim().isEmpty ? '固定日程' : schedule.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.onSecondaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$dateLabel · $timeLabel',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: colors.onSecondaryContainer),
                ),
                const SizedBox(height: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    child: Text(
                      '仅关联当前场次',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualInputTab({Key? key, double topPadding = 0}) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, _) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _unfocusActiveInput,
          child: SingleChildScrollView(
            key: key,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(16, topPadding + 8, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.relatedFixedScheduleContext case final schedule?)
                  _buildRelatedFixedScheduleContext(schedule),
                // Input Section
                OptionalLiquidGlassCard(
                  borderRadius: 24,
                  highContrast: true,
                  fallbackDecoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.fromBorderSide(
                      BorderSide(
                        color: colors.outlineVariant.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          key: const ValueKey('manual-todo-title'),
                          controller: _titleCtrl,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            hintText:
                                _manualCaptureKind == _ManualCaptureKind.todo
                                ? "准备做些什么？"
                                : "要记录什么日程？",
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            isDense: true,
                            isCollapsed: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 4,
                            ),
                          ),
                        ),
                        if (_manualCaptureKind == _ManualCaptureKind.todo &&
                            widget.relatedFixedScheduleContext == null)
                          _buildAISuggestionCard(),
                        if (_manualCaptureKind ==
                            _ManualCaptureKind.fixedSchedule) ...[
                          const Divider(height: 24),
                          TextField(
                            key: const ValueKey('manual-schedule-location'),
                            controller: _locationCtrl,
                            style: const TextStyle(fontSize: 15),
                            decoration: InputDecoration(
                              prefixIcon: Icon(
                                Icons.location_on_outlined,
                                size: 20,
                                color: colors.onSurfaceVariant,
                              ),
                              prefixIconConstraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 24,
                              ),
                              hintText: "地点 (可选)",
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              isDense: true,
                              isCollapsed: true,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 4,
                              ),
                              hintStyle: TextStyle(
                                color: Colors.grey.withValues(alpha: 0.8),
                              ),
                            ),
                          ),
                        ],
                        const Divider(height: 24),
                        TextField(
                          key: const ValueKey('manual-todo-remark'),
                          controller: _remarkCtrl,
                          style: const TextStyle(fontSize: 15),
                          maxLines: 4,
                          minLines: 1,
                          decoration: InputDecoration(
                            hintText: "补充细节或备注...",
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            isDense: true,
                            isCollapsed: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 4,
                            ),
                            hintStyle: TextStyle(
                              color: Colors.grey.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_manualCaptureKind == _ManualCaptureKind.todo &&
                            _selectedImagePath == null)
                          KeyedSubtree(
                            key: _attachmentKey,
                            child: TextButton.icon(
                              onPressed: _pickAttachmentImage,
                              icon: const Icon(
                                Icons.add_photo_alternate_outlined,
                                size: 20,
                              ),
                              label: const Text("添加图片"),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                visualDensity: VisualDensity.compact,
                                foregroundColor: colors.primary,
                              ),
                            ),
                          )
                        else if (_manualCaptureKind == _ManualCaptureKind.todo)
                          Stack(
                            children: [
                              InkWell(
                                onTap: _pickAttachmentImage,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: localImageWidget(
                                    _selectedImagePath!,
                                    height: 140,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: IconButton.filled(
                                  onPressed: () {
                                    _unfocusActiveInput();
                                    _mutateState(
                                      () => _selectedImagePath = null,
                                    );
                                  },
                                  icon: const Icon(Icons.close, size: 16),
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.black45,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.all(4),
                                    minimumSize: Size.zero,
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Properties
                ...[
                  // Todo Properties
                  OptionalLiquidGlassCard(
                    borderRadius: 16,
                    highContrast: true,
                    fallbackDecoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.fromBorderSide(
                        BorderSide(
                          color: colors.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: _buildResponsiveGrid([
                        if (_manualCaptureKind == _ManualCaptureKind.todo) ...[
                          LiquidGlassSwitchListTile(
                            title: const Text("某天内完成"),
                            subtitle: const Text("不指定具体时刻"),
                            value: _isAllDay,
                            secondary: KeyedSubtree(
                              key: _allDayKey,
                              child: const Icon(Icons.calendar_today),
                            ),
                            onChanged: (val) {
                              _unfocusActiveInput();
                              _mutateState(() {
                                final wasDateOnlyRange =
                                    _dueDate != null &&
                                    TodoItem.looksLikeLegacyDateOnlyRange(
                                      _createdAt,
                                      _dueDate!,
                                    );
                                // When changing a deadline into a date-only
                                // todo, the selected due date becomes the
                                // target date. Using _createdAt here would
                                // silently replace it with the creation day.
                                final targetDate = _dueDate ?? _createdAt;
                                _isAllDay = val;
                                if (_isAllDay) {
                                  _createdAt = DateTime(
                                    targetDate.year,
                                    targetDate.month,
                                    targetDate.day,
                                    0,
                                    0,
                                  );
                                  if (_dueDate != null) {
                                    _dueDate = DateTime(
                                      _dueDate!.year,
                                      _dueDate!.month,
                                      _dueDate!.day,
                                      23,
                                      59,
                                    );
                                  } else {
                                    _dueDate = DateTime(
                                      _createdAt.year,
                                      _createdAt.month,
                                      _createdAt.day,
                                      23,
                                      59,
                                    );
                                  }
                                } else if (wasDateOnlyRange) {
                                  final now = DateTime.now();
                                  _createdAt = DateTime(
                                    _createdAt.year,
                                    _createdAt.month,
                                    _createdAt.day,
                                    now.hour,
                                    now.minute,
                                  );
                                  _dueDate = null;
                                }
                              });
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.event),
                            title: Text(_isAllDay ? "完成日期" : "截止时间"),
                            subtitle: Text(
                              _isAllDay
                                  ? _dateWithSemesterWeek(
                                      _createdAt,
                                      _cachedDateFormat('MM-dd')
                                          .format(_createdAt),
                                    )
                                  : (_dueDate == null
                                        ? "未安排"
                                        : "${_dateWithSemesterWeek(_dueDate!, _cachedDateFormat('MM-dd HH:mm').format(_dueDate!))} 前完成"),
                            ),
                            trailing: _dueDate != null && !_isAllDay
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _unfocusActiveInput();
                                      _mutateState(() => _dueDate = null);
                                    },
                                  )
                                : const Icon(Icons.chevron_right),
                            onTap: _isAllDay ? _pickStartTime : _pickEndTime,
                          ),
                        ] else ...[
                          ListTile(
                            key: const ValueKey('fixed-schedule-date'),
                            leading: const Icon(Icons.calendar_today_rounded),
                            title: Text(
                              _recurrence == RecurrenceType.none
                                  ? '日期'
                                  : '首次日期',
                            ),
                            subtitle: Text(
                              _dateWithSemesterWeek(
                                _scheduleDate,
                                _cachedDateFormat('yyyy-MM-dd')
                                    .format(_scheduleDate),
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('时间待定'),
                                const SizedBox(width: 6),
                                LiquidGlassSwitch(
                                  key: const ValueKey(
                                    'fixed-schedule-time-tbd',
                                  ),
                                  value: _scheduleTimeTbd,
                                  onChanged: (value) {
                                    _unfocusActiveInput();
                                    _mutateState(
                                      () => _scheduleTimeTbd = value,
                                    );
                                  },
                                ),
                              ],
                            ),
                            onTap: _pickScheduleDate,
                          ),
                          if (!_scheduleTimeTbd) ...[
                            ListTile(
                              key: const ValueKey('fixed-schedule-start-time'),
                              leading: const Icon(
                                Icons.play_circle_outline_rounded,
                              ),
                              title: const Text('开始时间'),
                              subtitle: Text(
                                _scheduleStartTime.format(context),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: _pickScheduleStartTime,
                            ),
                            ListTile(
                              key: const ValueKey('fixed-schedule-end-time'),
                              leading: const Icon(Icons.stop_circle_outlined),
                              title: const Text('结束时间'),
                              subtitle: Text(
                                _scheduleEndTimeTbd
                                    ? '待定'
                                    : _scheduleEndTime.format(context),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('待定'),
                                  const SizedBox(width: 6),
                                  LiquidGlassSwitch(
                                    key: const ValueKey(
                                      'fixed-schedule-end-time-tbd',
                                    ),
                                    value: _scheduleEndTimeTbd,
                                    onChanged: (value) {
                                      _unfocusActiveInput();
                                      _mutateState(
                                        () => _scheduleEndTimeTbd = value,
                                      );
                                    },
                                  ),
                                ],
                              ),
                              onTap: _scheduleEndTimeTbd
                                  ? null
                                  : _pickScheduleEndTime,
                            ),
                          ],
                          KeyedSubtree(
                            key: const ValueKey('fixed-schedule-related-todos'),
                            child: Container(
                              key: _relatedTodosTileKey,
                              child: ListTile(
                                leading: const Icon(Icons.link_rounded),
                                title: Row(
                                  children: [
                                    Text(
                                      _selectedTeamUuid == null
                                          ? '关联个人待办'
                                          : '关联团队待办',
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            (_selectedTeamUuid == null
                                                    ? Theme.of(context)
                                                          .colorScheme
                                                          .surfaceContainerHighest
                                                    : Theme.of(context)
                                                          .colorScheme
                                                          .primaryContainer)
                                                .withValues(alpha: 0.6),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        _currentTeamScopeLabel,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: _selectedTeamUuid == null
                                              ? Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant
                                              : Theme.of(context)
                                                    .colorScheme
                                                    .onPrimaryContainer,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Text(
                                  _scheduleRelatedTodoIds.isEmpty
                                      ? (_selectedTeamUuid == null
                                            ? '未关联 · 当前只展示个人待办（如需团队待办请在下方切换归属）'
                                            : '未关联 · 当前只展示【$_currentTeamScopeLabel】待办')
                                      : '已关联 ${_scheduleRelatedTodoIds.length} 项（$_currentTeamScopeLabel）',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: _isSaving
                                    ? null
                                    : _chooseScheduleRelatedTodos,
                              ),
                            ),
                          ),
                        ],
                        ListTile(
                          leading: const Icon(Icons.notifications_outlined),
                          title: const Text("提醒"),
                          subtitle: Text(_getReminderText(_reminderMinutes)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            _unfocusActiveInput();
                            final val = await showMenu<int>(
                              context: context,
                              position: const RelativeRect.fromLTRB(
                                100,
                                400,
                                0,
                                0,
                              ),
                              items: [0, 5, 10, 15, 30, 45, 60, 120, 1440]
                                  .map(
                                    (m) => PopupMenuItem(
                                      value: m,
                                      child: Text(_getReminderText(m)),
                                    ),
                                  )
                                  .toList(),
                            );
                            if (val != null) {
                              _mutateState(() => _reminderMinutes = val);
                            }
                          },
                        ),
                        if (widget.relatedFixedScheduleContext == null)
                          ListTile(
                            leading: const Icon(Icons.repeat),
                            title: const Text("重复规则"),
                            subtitle: Text(_getRecurrenceLabel(_recurrence)),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () async {
                              _unfocusActiveInput();
                              final val = await showMenu<RecurrenceType>(
                                context: context,
                                position: const RelativeRect.fromLTRB(
                                  100,
                                  500,
                                  0,
                                  0,
                                ),
                                items:
                                    [
                                          RecurrenceType.none,
                                          RecurrenceType.daily,
                                          RecurrenceType.weekly,
                                          RecurrenceType.monthly,
                                          RecurrenceType.yearly,
                                          RecurrenceType.weekdays,
                                          RecurrenceType.customDays,
                                        ]
                                        .map(
                                          (r) => PopupMenuItem(
                                            value: r,
                                            child: Text(_getRecurrenceLabel(r)),
                                          ),
                                        )
                                        .toList(),
                              );
                              if (val != null) {
                                _mutateState(() => _recurrence = val);
                              }
                            },
                          ),
                        if (widget.relatedFixedScheduleContext == null &&
                            (_recurrence == RecurrenceType.customDays ||
                                _recurrence != RecurrenceType.none))
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_recurrence ==
                                    RecurrenceType.customDays) ...[
                                  Row(
                                    children: [
                                      const Text("每隔"),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: TextField(
                                          controller: _customDaysCtrl,
                                          keyboardType: TextInputType.number,
                                          textAlign: TextAlign.center,
                                          decoration: InputDecoration(
                                            isDense: true,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  vertical: 8,
                                                ),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                          onChanged: (val) => _mutateState(
                                            () =>
                                                _customDays = int.tryParse(val),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      const Text("天重复"),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                InkWell(
                                  onTap: () async {
                                    _unfocusActiveInput();
                                    final picked = await showAppDatePicker(
                                      context: context,
                                      initialDate:
                                          _recurrenceEndDate ?? DateTime.now(),
                                      firstDate: DateTime.now(),
                                      lastDate: DateTime(2100),
                                      semesterWeekContext: _semesterWeekContext,
                                    );
                                    if (picked != null) {
                                      _mutateState(
                                        () => _recurrenceEndDate = picked,
                                      );
                                    }
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text("重复结束日期"),
                                        Row(
                                          children: [
                                            Text(
                                              _recurrenceEndDate == null
                                                  ? "未指定"
                                                  : _dateWithSemesterWeek(
                                                      _recurrenceEndDate!,
                                                      _cachedDateFormat(
                                                        'yyyy-MM-dd',
                                                      ).format(
                                                        _recurrenceEndDate!,
                                                      ),
                                                    ),
                                              style: TextStyle(
                                                color:
                                                    _recurrenceEndDate == null
                                                    ? Colors.grey
                                                    : colors.primary,
                                              ),
                                            ),
                                            const Icon(
                                              Icons.chevron_right,
                                              color: Colors.grey,
                                              size: 20,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ]),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                // Group and Team
                if ((_manualCaptureKind == _ManualCaptureKind.todo &&
                        _localTodoGroups.isNotEmpty) ||
                    _teams.isNotEmpty ||
                    widget.relatedFixedScheduleContext != null) ...[
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      "组织与协作",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  OptionalLiquidGlassCard(
                    borderRadius: 16,
                    highContrast: true,
                    fallbackDecoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.fromBorderSide(
                        BorderSide(
                          color: colors.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: _buildResponsiveGrid([
                        if (_manualCaptureKind == _ManualCaptureKind.todo &&
                            _localTodoGroups.isNotEmpty)
                          ListTile(
                            leading: Icon(
                              Icons.folder_outlined,
                              color: colors.primary,
                            ),
                            title: const Text("归属文件夹"),
                            subtitle: Text(
                              _selectedGroupId == null
                                  ? "未分类"
                                  : (_localTodoGroups
                                            .where(
                                              (g) => g.id == _selectedGroupId,
                                            )
                                            .firstOrNull
                                            ?.name ??
                                        '未知'),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () async {
                              _unfocusActiveInput();
                              final result = await showTodoGroupPickerSheet(
                                context: context,
                                groups: _localTodoGroups,
                                selectedGroupId: _selectedGroupId,
                              );
                              if (!mounted || result == null) return;
                              final newGroupId = result.groupId;
                              _recordUserGroupChoice(newGroupId);
                              _mutateState(() {
                                _selectedGroupId = newGroupId;
                                if (_selectedGroupId != null &&
                                    _categoryReminderDefaults.containsKey(
                                      _selectedGroupId,
                                    )) {
                                  _reminderMinutes =
                                      _categoryReminderDefaults[_selectedGroupId]!;
                                } else if (_selectedGroupId == null) {
                                  _reminderMinutes = 5;
                                }
                              });
                              _onTitleChanged();
                            },
                          ),
                        if (widget.relatedFixedScheduleContext != null)
                          ListTile(
                            leading: Icon(
                              Icons.lock_outline_rounded,
                              color: colors.secondary,
                            ),
                            title: const Text("团队归属"),
                            subtitle: Text(
                              _relatedScheduleTeamUuid == null
                                  ? "个人私有 · 与固定日程保持一致"
                                  : (_teams
                                            .where(
                                              (team) =>
                                                  team.uuid ==
                                                  _relatedScheduleTeamUuid,
                                            )
                                            .firstOrNull
                                            ?.name ??
                                        "与固定日程保持一致"),
                            ),
                          )
                        else if (_teams.isNotEmpty)
                          ListTile(
                            leading: Icon(
                              Icons.groups_outlined,
                              color: colors.secondary,
                            ),
                            title: const Text("团队归属"),
                            subtitle: Text(
                              _selectedTeamUuid == null
                                  ? "个人私有"
                                  : (_teams
                                            .where(
                                              (t) =>
                                                  t.uuid == _selectedTeamUuid,
                                            )
                                            .firstOrNull
                                            ?.name ??
                                        '未知'),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () async {
                              _unfocusActiveInput();
                              final val = await showMenu<String>(
                                context: context,
                                position: const RelativeRect.fromLTRB(
                                  100,
                                  650,
                                  0,
                                  0,
                                ),
                                items: [
                                  const PopupMenuItem<String>(
                                    value: "__none__",
                                    child: Text("个人私有 (仅自己可见)"),
                                  ),
                                  ..._teams.map(
                                    (t) => PopupMenuItem(
                                      value: t.uuid,
                                      child: Text(t.name),
                                    ),
                                  ),
                                ],
                              );
                              if (val != null) {
                                _mutateState(
                                  () => _selectedTeamUuid = val == "__none__"
                                      ? null
                                      : val,
                                );
                              }
                            },
                          ),
                        if (_manualCaptureKind == _ManualCaptureKind.todo &&
                            _selectedTeamUuid != null)
                          ListTile(
                            leading: const Icon(Icons.sync_alt_rounded),
                            title: const Text("完成规则"),
                            trailing: SizedBox(
                              width: 140,
                              child: _buildCustomSegmentedControl(
                                labels: const ["全队同步", "各自独立"],
                                selectedIndex: _collabType,
                                onChanged: (idx) {
                                  _unfocusActiveInput();
                                  _mutateState(() => _collabType = idx);
                                },
                              ),
                            ),
                          ),
                      ]),
                    ),
                  ),
                ],
                SizedBox(
                  height: floatingBottomNavigationContentPaddingFor(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildManualKindBottomBar() {
    return FloatingBottomNavigationBar(
      mobilePortraitOnly: false,
      items: const [
        FloatingBottomNavigationItem(
          icon: Icons.check_circle_outline_rounded,
          label: '待办',
        ),
        FloatingBottomNavigationItem(
          icon: Icons.event_note_outlined,
          label: '日程',
        ),
      ],
      selectedIndex: _manualCaptureKind == _ManualCaptureKind.todo ? 0 : 1,
      onTabSelected: _selectManualCaptureKind,
    );
  }

  // ================= 待确认图片识别事项卡片 =================
  Widget _buildPendingTodoCard() {
    final imagePath = _pendingTodoConfirm!['imagePath'] as String?;
    final results = _pendingTodoConfirm!['results'] as List<dynamic>?;
    final todoCount = results?.length ?? 0;
    if (todoCount == 0) return const SizedBox.shrink();

    return Material(
      color: Theme.of(context).colorScheme.primaryContainer
          .withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (results == null || results.isEmpty) return;
          final typedResults = results
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _mutateState(() => _pendingTodoConfirm = null);
          StorageService.clearPendingTodoConfirm();
          if (widget.onLLMResultsParsed != null) {
            widget.onLLMResultsParsed!(
              typedResults,
              imagePath,
              null,
              null,
              null,
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (localImageExists(imagePath))
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: localImageWidget(
                    imagePath!,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                  ),
                )
              else
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.checklist_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 24,
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI识别完成',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '发现 $todoCount 个事项，点击查看',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
