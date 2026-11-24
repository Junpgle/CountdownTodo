part of '../add_todo_screen.dart';

extension _AddTodoSavingSuggestionsExt on _AddTodoScreenState {
  Future<bool> _saveManualFixedSchedule() async {
    final start = _scheduleTimeTbd ? null : _scheduleAt(_scheduleStartTime);
    final end = _scheduleTimeTbd || _scheduleEndTimeTbd
        ? null
        : _scheduleAt(_scheduleEndTime);
    if (start != null && end != null && !end.isAfter(start)) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('结束时间必须晚于开始时间')),
      );
      return false;
    }

    final invalidMessage = await _invalidRelatedTodoMessage();
    if (invalidMessage != null) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text(invalidMessage)),
        );
      }
      return false;
    }

    final parsed = ParsedTodoResult(
      title: _titleCtrl.text.trim(),
      location: _locationCtrl.text.trim().isEmpty
          ? null
          : _locationCtrl.text.trim(),
      remark: _remarkCtrl.text.trim().isEmpty ? null : _remarkCtrl.text.trim(),
      isAllDay: _scheduleTimeTbd,
      startTime: _scheduleTimeTbd ? _scheduleDate : start,
      endTime: end,
      timeSemantics: _scheduleTimeTbd
          ? ParsedTimeSemantics.dateOnly
          : ParsedTimeSemantics.range,
      recurrence: _recurrence,
      customIntervalDays: _customDays,
      recurrenceEndDate: _recurrenceEndDate,
      reminderMinutes: _reminderMinutes,
      originalText: _currentOriginalText,
    );
    return _saveFixedScheduleFromText(
      _currentOriginalText ?? _titleCtrl.text,
      parsedResult: parsed,
      source: FixedScheduleSource.manual,
      relatedTodoIds: _scheduleRelatedTodoIds.toList(),
    );
  }

  Future<void> _addTodo() async {
    if (_isSaving) return;
    if (_titleCtrl.text.trim().isEmpty) {
      AppSnackBars.showSnackBar(
        context,
        SnackBar(
          content: Text(
            _manualCaptureKind == _ManualCaptureKind.fixedSchedule
                ? '请输入日程名称'
                : '请输入待办内容',
          ),
        ),
      );
      return;
    }
    _mutateState(() => _isSaving = true);
    try {
      if (_manualCaptureKind == _ManualCaptureKind.fixedSchedule) {
        final saved = await _saveManualFixedSchedule();
        if (saved && mounted) Navigator.pop(context);
        return;
      }
      final sourceText = _currentOriginalText ?? _titleCtrl.text;
      final currentParsed = _parsedResults.isEmpty
          ? null
          : _parsedResults[_currentParseIndex];
      final saveTarget = widget.relatedFixedScheduleContext == null
          ? await _confirmCaptureIntent(
              sourceText,
              declaredKind: currentParsed?.itemKind,
              semanticText: '${_titleCtrl.text} ${_remarkCtrl.text}',
            )
          : _CaptureSaveTarget.todo;
      if (saveTarget == _CaptureSaveTarget.cancel) return;
      if (saveTarget == _CaptureSaveTarget.fixedSchedule) {
        final hasParsedDate =
            currentParsed?.startTime != null ||
            currentParsed?.endTime != null ||
            _isAllDay ||
            _dueDate != null;
        final manualLocation = _locationCtrl.text.trim().isEmpty
            ? null
            : _locationCtrl.text.trim();
        final resolvedLocation = manualLocation ?? currentParsed?.location;
        final manualRemark = _remarkCtrl.text.trim();
        final resolvedRemark = manualRemark.isEmpty
            ? null
            : (resolvedLocation != null &&
                      manualRemark == resolvedLocation.trim()
                  ? currentParsed?.remark
                  : manualRemark);
        final editedParsed = currentParsed == null
            ? null
            : ParsedTodoResult(
                title: _titleCtrl.text.trim(),
                remark: resolvedRemark,
                location: resolvedLocation,
                isAllDay: _isAllDay,
                startTime: hasParsedDate ? _createdAt : null,
                endTime: _dueDate,
                timeSemantics: currentParsed.timeSemantics,
                recurrence: _recurrence,
                customIntervalDays: _customDays,
                recurrenceEndDate: _recurrenceEndDate,
                reminderMinutes: _reminderMinutes,
                itemKind: currentParsed.itemKind,
                originalText: sourceText,
              );
        final saved = await _saveFixedScheduleFromText(
          sourceText,
          parsedResult: editedParsed,
        );
        if (saved && mounted) Navigator.pop(context);
        return;
      }

      final normalizedTime = TodoItem.normalizeTimeForWrite(
        selectedDate: _createdAt,
        dueDate: _dueDate,
        isDateOnly: _isAllDay,
      );
      if (_recurrence != RecurrenceType.none && normalizedTime.start == null) {
        if (!mounted) return;
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('重复待办需要先设置首次完成日期')),
        );
        return;
      }

      final persistentImagePath = await _persistAttachmentImageIfNeeded();
      final selectedTeam = _selectedTeamUuid != null
          ? _teams.where((t) => t.uuid == _selectedTeamUuid).firstOrNull
          : null;

      final todo = TodoItem(
        id: _pendingManualTodoId ??= const Uuid().v4(),
        title: _titleCtrl.text,
        recurrence: widget.relatedFixedScheduleContext == null
            ? _recurrence
            : RecurrenceType.none,
        customIntervalDays: widget.relatedFixedScheduleContext == null
            ? _customDays
            : null,
        recurrenceEndDate: widget.relatedFixedScheduleContext == null
            ? _recurrenceEndDate
            : null,
        dueDate: normalizedTime.due,
        createdDate: normalizedTime.start?.millisecondsSinceEpoch,
        remark: _remarkCtrl.text.trim().isEmpty
            ? null
            : _remarkCtrl.text.trim(),
        originalText: _currentOriginalText,
        imagePath: persistentImagePath,
        groupId: _selectedGroupId,
        reminderMinutes: _reminderMinutes,
        teamUuid: widget.relatedFixedScheduleContext == null
            ? _selectedTeamUuid
            : _relatedScheduleTeamUuid,
        teamName: selectedTeam?.name,
        creatorName: _username,
        collabType: _collabType,
        isAllDay: _isAllDay,
      );

      final saveResult = widget.onManualTodoSaved != null
          ? await widget.onManualTodoSaved!(todo)
          : await _saveManualTodoWithLegacyCallback(todo);
      if (!mounted) return;
      if (saveResult.warnings.isNotEmpty) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text('待办已保存；${saveResult.warnings.join('；')}')),
        );
      }
      Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text('保存失败，请重试：$error')),
        );
      }
    } finally {
      if (mounted) _mutateState(() => _isSaving = false);
    }
  }

  Future<TodoCreateSaveResult> _saveManualTodoWithLegacyCallback(
    TodoItem todo,
  ) async {
    final callback = widget.onTodoAdded;
    if (callback == null) throw StateError('当前入口未连接待办保存');
    await callback(todo);
    return const TodoCreateSaveResult();
  }

  Future<_CaptureSaveTarget> _confirmCaptureIntent(
    String sourceText, {
    String? declaredKind,
    String? semanticText,
  }) async {
    final intent = ItemSemanticsService.classifyCaptureIntent(
      declaredKind == null ? sourceText : semanticText ?? sourceText,
      declaredKind: declaredKind,
    );
    if (intent == CaptureIntentKind.todo || !mounted) {
      return _CaptureSaveTarget.todo;
    }

    final (title, message) = switch (intent) {
      CaptureIntentKind.fixedSchedule => (
        '识别为固定日程',
        widget.onFixedScheduleAdded == null
            ? '考试、会议或预约属于不可自由移动的固定日程。当前入口尚未连接固定日程存储，继续会暂存为待办。'
            : '考试、会议或预约属于不可自由移动的固定日程，可以直接按固定日程保存。',
      ),
      CaptureIntentKind.planBlock => (
        '识别为规划时段',
        '这个时间段更适合关联到待办的规划块。现在继续只会保存待办，不会占用规划日历。',
      ),
      CaptureIntentKind.needsConfirmation => (
        '需要确认时间性质',
        '无法确定这是外部固定日程，还是你可以调整的规划时段。现在继续会暂存为待办。',
      ),
      CaptureIntentKind.todo => ('', ''),
    };

    return await showAppDialog<_CaptureSaveTarget>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(dialogContext, _CaptureSaveTarget.cancel),
                child: const Text('返回调整'),
              ),
              if (intent == CaptureIntentKind.fixedSchedule &&
                  widget.onFixedScheduleAdded != null)
                FilledButton.tonal(
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    _CaptureSaveTarget.fixedSchedule,
                  ),
                  child: const Text('保存为固定日程'),
                ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(dialogContext, _CaptureSaveTarget.todo),
                child: const Text('暂存为待办'),
              ),
            ],
          ),
        ) ??
        _CaptureSaveTarget.cancel;
  }

  Future<bool> _saveFixedScheduleFromText(
    String sourceText, {
    ParsedTodoResult? parsedResult,
    FixedScheduleSource? source,
    List<String>? relatedTodoIds,
  }) async {
    final callback = widget.onFixedScheduleAdded;
    if (callback == null) return false;
    final parsed = parsedResult ?? TodoParserService.parse(sourceText);
    final dateSource = parsed.startTime ?? parsed.endTime ?? _dueDate;
    if (dateSource == null) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('固定日程需要先确认日期')),
        );
      }
      return false;
    }
    DateTime? start = parsed.startTime;
    DateTime? end = parsed.endTime;
    if (parsed.isAllDay) {
      start = null;
      end = null;
    } else if (parsed.timeSemantics == ParsedTimeSemantics.deadline &&
        end != null) {
      // 单一时刻在待办解析中表示截止点；对固定日程则表示开始时刻，
      // 结束时间保持待定，不能静默补出一小时。
      start = end;
      end = null;
    } else if (start == null && _dueDate != null) {
      start = _dueDate;
    }

    final reminderMinutes = parsed.reminderMinutes ?? _reminderMinutes;
    final resolvedSource =
        source ??
        (parsedResult == null
            ? FixedScheduleSource.manual
            : FixedScheduleSource.ai);
    final resolvedLocation = _locationCtrl.text.trim().isNotEmpty
        ? _locationCtrl.text.trim()
        : (parsed.location?.trim().isNotEmpty == true
              ? parsed.location!.trim()
              : null);
    final manualRemark = _remarkCtrl.text.trim();
    final resolvedRemark =
        manualRemark.isNotEmpty && manualRemark != resolvedLocation
        ? manualRemark
        : (parsed.remark?.trim().isNotEmpty == true
              ? parsed.remark!.trim()
              : null);
    final item = FixedScheduleItem(
      title: parsed.title.trim().isEmpty ? _titleCtrl.text : parsed.title,
      date: _cachedDateFormat('yyyy-MM-dd').format(dateSource),
      startTime: start?.millisecondsSinceEpoch,
      endTime: end?.millisecondsSinceEpoch,
      source: resolvedSource,
      location: resolvedLocation,
      remark: resolvedRemark,
      reminderMinutes:
          reminderMinutes < 0 ||
              (resolvedSource == FixedScheduleSource.manual &&
                  reminderMinutes == 0)
          ? const []
          : [reminderMinutes],
      timezone: DateTime.now().timeZoneName,
      recurrence: parsed.recurrence,
      recurrenceSeriesId: null,
      teamUuid: _selectedTeamUuid,
      relatedTodoIds:
          relatedTodoIds ??
          (_manualCaptureKind == _ManualCaptureKind.fixedSchedule
              ? _scheduleRelatedTodoIds.toList()
              : const []),
    );
    if (item.recurrence != RecurrenceType.none) {
      item.recurrenceSeriesId = item.id;
    }
    if (item.recurrence == RecurrenceType.none) {
      await callback(item);
      final username = _username ?? await StorageService.getLoginSession();
      if (username != null) {
        await ReminderScheduleService.scheduleFromStorage(
          username,
          force: true,
        );
      }
      return true;
    }
    final recurrenceEnd =
        parsed.recurrenceEndDate ??
        FixedScheduleRecurrenceService.defaultEndDate(
          startDate: dateSource,
          recurrence: item.recurrence,
          customIntervalDays: parsed.customIntervalDays ?? 1,
        );
    late final ({
      List<FixedScheduleItem> active,
      List<FixedScheduleItem> changes,
    })
    series;
    try {
      series = FixedScheduleRecurrenceService.rebuildSeries(
        template: item,
        existingSeries: const [],
        recurrence: item.recurrence,
        recurrenceEndDate: recurrenceEnd,
        customIntervalDays: parsed.customIntervalDays ?? 1,
      );
    } on FixedScheduleRecurrenceLimitException catch (error) {
      if (!mounted) return false;
      AppSnackBars.showSnackBar(
        context,
        SnackBar(content: Text(error.toString())),
      );
      return false;
    }
    final username = _username ?? await StorageService.getLoginSession();
    if (username != null) {
      await StorageService.saveFixedSchedules(username, series.changes);
      await callback(series.active.first);
    } else {
      for (final occurrence in series.active) {
        await callback(occurrence);
      }
    }
    final reminderUsername =
        _username ?? await StorageService.getLoginSession();
    if (reminderUsername != null) {
      await ReminderScheduleService.scheduleFromStorage(
        reminderUsername,
        force: true,
      );
    }
    return true;
  }

  Future<void> _addBatchTodos() async {
    if (_isSaving || _parsedResults.isEmpty) return;
    if (widget.onTodosBatchAdded == null && widget.onTodoAdded == null) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('当前入口未连接待办保存')),
      );
      return;
    }

    _mutateState(() => _isSaving = true);
    try {
      final todoResults = <ParsedTodoResult>[];
      for (final result in _parsedResults) {
        final sourceText = result.originalText ?? result.title;
        final saveTarget = await _confirmCaptureIntent(
          sourceText,
          declaredKind: result.itemKind,
          semanticText: '${result.title} ${result.remark ?? ''}',
        );
        if (saveTarget == _CaptureSaveTarget.cancel) return;
        if (saveTarget == _CaptureSaveTarget.fixedSchedule) {
          await _saveFixedScheduleFromText(sourceText, parsedResult: result);
        } else {
          todoResults.add(result);
        }
      }

      final persistentImagePath = await _persistAttachmentImageIfNeeded();
      final selectedTeam = _selectedTeamUuid != null
          ? _teams.where((t) => t.uuid == _selectedTeamUuid).firstOrNull
          : null;

      final List<TodoItem> todos = [];
      for (final r in todoResults) {
        final parsedDueDate =
            r.endTime ??
            (r.isAllDay && r.startTime != null
                ? DateTime(
                    r.startTime!.year,
                    r.startTime!.month,
                    r.startTime!.day,
                    23,
                    59,
                  )
                : null);
        final normalizedTime = TodoItem.normalizeTimeForWrite(
          selectedDate: r.startTime,
          dueDate: parsedDueDate,
          isDateOnly: r.isAllDay,
        );
        if (r.recurrence != RecurrenceType.none &&
            normalizedTime.start == null) {
          if (!mounted) return;
          AppSnackBars.showSnackBar(
            context,
            SnackBar(content: Text('“${r.title}”是重复待办，请先设置首次完成日期')),
          );
          return;
        }
        final classification = await TodoClassificationService.recommendForText(
          title: r.title,
          remark: r.effectiveTodoRemark ?? '',
          groups: _localTodoGroups,
          categoryReminderDefaults: _categoryReminderDefaults,
          dueDate: parsedDueDate,
        );
        final suggestedGroupId = classification.confidence >= 0.20
            ? classification.groupId
            : null;
        todos.add(
          TodoItem(
            id: _parsedDraftIdFor(r),
            title: r.title,
            recurrence: r.recurrence,
            customIntervalDays: r.customIntervalDays,
            recurrenceEndDate: r.recurrenceEndDate,
            dueDate: normalizedTime.due,
            createdDate: normalizedTime.start?.millisecondsSinceEpoch,
            remark: r.effectiveTodoRemark,
            originalText: _currentOriginalText,
            imagePath: persistentImagePath,
            groupId: suggestedGroupId,
            reminderMinutes:
                r.reminderMinutes ??
                (suggestedGroupId != null
                    ? classification.reminderMinutes
                    : _reminderMinutes),
            teamUuid: _selectedTeamUuid,
            teamName: selectedTeam?.name,
            creatorName: _username,
            collabType: _collabType,
            isAllDay: r.isAllDay,
          ),
        );
      }

      if (todos.isNotEmpty) {
        if (widget.onTodosBatchAdded != null) {
          await widget.onTodosBatchAdded!(todos);
        } else {
          final onTodoAdded = widget.onTodoAdded!;
          for (var t in todos) {
            await onTodoAdded(t);
          }
        }
      }
      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text('保存失败，请重试：$error')),
        );
      }
    } finally {
      if (mounted) _mutateState(() => _isSaving = false);
    }
  }

  String _parsedDraftIdFor(ParsedTodoResult result) {
    final index = _parsedResults.indexOf(result);
    if (index < 0) return const Uuid().v4();
    while (_parsedDraftIds.length <= index) {
      _parsedDraftIds.add(const Uuid().v4());
    }
    return _parsedDraftIds[index];
  }

  // ================= 自定义统一分段控制器 (替代容易崩溃的原生 SegmentedButton) =================
  Widget _buildCustomSegmentedControl({
    required List<String> labels,
    required int selectedIndex,
    required ValueChanged<int> onChanged,
    bool floating = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: floating
            ? colorScheme.surface.withValues(alpha: 0)
            : colorScheme.onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(labels.length, (index) {
          final isSelected = selectedIndex == index;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(index),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? (floating
                            ? colorScheme.surfaceContainerHighest.withValues(
                                alpha: 0.72,
                              )
                            : colorScheme.surface)
                      : colorScheme.surface.withValues(alpha: 0),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: isSelected && !floating
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
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
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

  // ================= 网格化组件 (N*N Array UI Helpers) =================

  // 时间选择助手
  Future<void> _pickStartTime() async {
    _unfocusActiveInput();
    final pickedDate = await showAppDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: _createdAt,
      semesterWeekContext: _semesterWeekContext,
    );
    if (pickedDate != null) {
      if (_isAllDay) {
        _mutateState(() {
          _createdAt = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            0,
            0,
          );
          _dueDate = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            23,
            59,
          );
        });
      } else {
        if (!mounted) return;
        final pickedTime = await showAppTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(_createdAt),
        );
        if (pickedTime != null) {
          _mutateState(() {
            _createdAt = DateTime(
              pickedDate.year,
              pickedDate.month,
              pickedDate.day,
              pickedTime.hour,
              pickedTime.minute,
            );
            _updateSuggestedDueDate();
          });
        }
      }
    }
  }

  Future<void> _pickEndTime() async {
    _unfocusActiveInput();
    final pickedDate = await showAppDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: _dueDate ?? _createdAt,
      semesterWeekContext: _semesterWeekContext,
    );
    if (pickedDate != null) {
      if (_isAllDay) {
        _mutateState(() {
          _dueDate = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            23,
            59,
          );
          _suggestedDueDate = null;
        });
      } else {
        if (!mounted) return;
        final pickedTime = await showAppTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(_dueDate ?? DateTime.now()),
        );
        if (pickedTime != null) {
          _mutateState(() {
            _dueDate = DateTime(
              pickedDate.year,
              pickedDate.month,
              pickedDate.day,
              pickedTime.hour,
              pickedTime.minute,
            );
            _suggestedDueDate = null;
          });
        }
      }
    }
  }

  /// Re-compute suggested due date when start time changes
  void _updateSuggestedDueDate() {
    if (_estimationResult != null && !_isAllDay) {
      _suggestedDueDate = _createdAt.add(
        Duration(minutes: _estimationResult!.estimatedMinutes),
      );
    }
  }

  bool get _hasAISuggestions =>
      _estimationResult != null || _classificationSuggestion != null;

  void _acceptDueDateSuggestion() {
    _unfocusActiveInput();
    if (_suggestedDueDate != null) {
      _mutateState(() {
        _dueDate = _suggestedDueDate;
        _suggestedDueDate = null;
      });
    }
  }

  Widget _buildAISuggestionCard() {
    if (!_hasAISuggestions) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    final est = _estimationResult;
    final clsSug = _classificationSuggestion;
    final hasDueDate = _suggestedDueDate != null && !_isAllDay;

    // Check if classification suggestion is meaningful
    final hasNewGroup =
        clsSug != null && clsSug.hasGroup && clsSug.groupId != _selectedGroupId;
    final hasClassification =
        hasNewGroup || (clsSug != null && clsSug.tags.isNotEmpty);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.only(top: 10, bottom: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primaryContainer.withValues(alpha: 0.4),
            cs.primaryContainer.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with a "Pro" feel
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [cs.primary, cs.secondary]),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 12, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'AI INSIGHT',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '智能建议',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface.withValues(alpha: 0.8),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  _unfocusActiveInput();
                  _recordNegativeClassificationFeedback();
                  _estimationDebounce?.cancel();
                  ++_estimateSequence;
                  _mutateState(() {
                    _estimationResult = null;
                    _suggestedDueDate = null;
                    _classificationSuggestion = null;
                  });
                },
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  '忽略',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Duration suggestion
          if (est != null) TimeEstimationHint(result: est),

          // Due date suggestion
          if (hasDueDate)
            _buildSuggestionItem(
              icon: Icons.calendar_today_rounded,
              label:
                  "建议截止: ${_cachedDateFormat('MM-dd HH:mm').format(_suggestedDueDate!)}",
              showAccept: true,
              onAccept: _acceptDueDateSuggestion,
              accentColor: Colors.deepOrangeAccent,
            ),

          // Classification suggestion
          if (hasClassification) ...[
            _buildSuggestionItem(
              icon: Icons.auto_graph_rounded,
              label: '分类与标签建议',
              showAccept: true,
              onAccept: _applyClassificationSuggestion,
              accentColor: cs.primary,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (hasNewGroup)
                    _buildMiniChip(
                      Icons.folder_special_rounded,
                      clsSug.groupName ?? '未分类',
                      Colors.amber.shade700,
                    ),
                  _buildMiniChip(
                    Icons.priority_high_rounded,
                    clsSug.priorityLabel,
                    clsSug.priority >= 4 ? Colors.redAccent : Colors.blueGrey,
                  ),
                  ...clsSug.tags.map(
                    (tag) => _buildMiniChip(Icons.tag_rounded, tag, cs.primary),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSuggestionItem({
    required IconData icon,
    required String label,
    String? sub,
    Color? subColor,
    required bool showAccept,
    VoidCallback? onAccept,
    Color? accentColor,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: (accentColor ?? cs.primary).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 14, color: accentColor ?? cs.primary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface.withValues(alpha: 0.9),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (sub != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        sub,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color:
                              subColor?.withValues(alpha: 0.7) ?? Colors.grey,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (showAccept)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onAccept,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: (accentColor ?? cs.primary).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: (accentColor ?? cs.primary).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '采纳',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: accentColor ?? cs.primary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMiniChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}
