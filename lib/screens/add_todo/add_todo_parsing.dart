part of '../add_todo_screen.dart';

extension _AddTodoParsingExt on _AddTodoScreenState {
  void _onTitleChanged({bool force = false}) {
    final rawTitle = _titleCtrl.text;
    final remark = _remarkCtrl.text;
    final group = _selectedGroupId;
    final captureKind = _manualCaptureKind;
    if (!force &&
        rawTitle == _lastObservedTitleText &&
        remark == _lastObservedRemarkText &&
        group == _lastObservedGroupId &&
        captureKind == _lastObservedCaptureKind) {
      return;
    }
    _lastObservedTitleText = rawTitle;
    _lastObservedRemarkText = remark;
    _lastObservedGroupId = group;
    _lastObservedCaptureKind = captureKind;

    _estimationDebounce?.cancel();
    final sequence = ++_estimateSequence;
    if (mounted) {
      final hadSuggestions =
          _estimationResult != null ||
          _suggestedDueDate != null ||
          _classificationSuggestion != null;
      final canPop = _allowExit || (!_isSaving && !_hasUnsavedDraft);
      if (hadSuggestions || canPop != _lastCanPop) {
        _mutateState(() {
          _estimationResult = null;
          _suggestedDueDate = null;
          _classificationSuggestion = null;
        });
      }
    }
    if (_estimateAccountInvalid ||
        widget.relatedFixedScheduleContext != null ||
        _manualCaptureKind == _ManualCaptureKind.fixedSchedule) {
      return;
    }
    final text = rawTitle.trim();
    if (text.length < 2) return;
    _estimationDebounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final username = await _estimateAccount;
        await TimeEstimationRepository.checkAccount(username);
        if (!mounted || sequence != _estimateSequence) return;
        final result =
            await (widget.estimate?.call(text, group, username) ??
                TimeEstimationService.estimate(
                  text,
                  groupId: group,
                  username: username,
                ));
        if (!mounted || sequence != _estimateSequence) return;
        await TimeEstimationRepository.checkAccount(username);
        if (!mounted || sequence != _estimateSequence) return;
        final classification = await TodoClassificationService.recommendForText(
          title: text,
          remark: remark,
          groups: _localTodoGroups,
          categoryReminderDefaults: _categoryReminderDefaults,
          dueDate: _dueDate,
        );
        await TimeEstimationRepository.checkAccount(username);
        if (!mounted ||
            sequence != _estimateSequence ||
            group != _selectedGroupId ||
            text != _titleCtrl.text.trim() ||
            _manualCaptureKind != _ManualCaptureKind.todo) {
          return;
        }
        _mutateState(() {
          _estimationResult = result;
          _classificationSuggestion = classification;
          if (!_isAllDay) {
            _suggestedDueDate = _createdAt.add(
              Duration(minutes: result.estimatedMinutes),
            );
          }
        });
      } on TimeEstimationAccountChanged {
        _validateEstimateAccount();
      } catch (_) {
        // A suggestion failure must not discard the user's draft.
      }
    });
  }

  ParsedTimeSemantics _parseTimeSemantics(
    dynamic raw, {
    required bool isAllDay,
    required DateTime? startTime,
    required DateTime? endTime,
  }) {
    if (isAllDay) return ParsedTimeSemantics.dateOnly;
    final name = raw?.toString();
    return ParsedTimeSemantics.values.firstWhere(
      (value) => value.name == name,
      orElse: () => startTime != null && endTime != null
          ? ParsedTimeSemantics.range
          : ParsedTimeSemantics.unscheduled,
    );
  }

  String _getRecurrenceLabel(RecurrenceType r) {
    switch (r) {
      case RecurrenceType.none:
        return "不循环";
      case RecurrenceType.daily:
        return "每天重复";
      case RecurrenceType.weekly:
        return "每周重复";
      case RecurrenceType.monthly:
        return "每月重复";
      case RecurrenceType.yearly:
        return "每年重复";
      case RecurrenceType.weekdays:
        return "工作日";
      case RecurrenceType.customDays:
        return "间隔 ${_customDays ?? '?'} 天";
    }
  }

  CaptureIntentKind _captureIntentForParsed(ParsedTodoResult result) {
    return ItemSemanticsService.classifyCaptureIntent(
      result.itemKind == null
          ? result.originalText ?? result.title
          : '${result.title} ${result.remark ?? ''}',
      declaredKind: result.itemKind,
    );
  }

  String _parsedKindLabel(ParsedTodoResult result) {
    return switch (_captureIntentForParsed(result)) {
      CaptureIntentKind.todo => '待办',
      CaptureIntentKind.fixedSchedule => '固定日程',
      CaptureIntentKind.planBlock => '规划块',
      CaptureIntentKind.needsConfirmation => '待确认',
    };
  }

  String _parsedTimeLabel(ParsedTodoResult result) {
    final intent = _captureIntentForParsed(result);
    if (intent == CaptureIntentKind.fixedSchedule) {
      if (result.isAllDay) {
        return result.startTime == null
            ? '日期待确认 · 时间待定'
            : '${AppTimeFormats.dateFormatter('MM-dd').format(result.startTime!)} · 时间待定';
      }
      if (result.startTime != null && result.endTime != null) {
        return '${AppTimeFormats.dateFormatter('MM-dd HH:mm').format(result.startTime!)}–${AppTimeFormats.dateFormatter('HH:mm').format(result.endTime!)}';
      }
      if (result.startTime != null) {
        return '${AppTimeFormats.dateFormatter('MM-dd HH:mm').format(result.startTime!)}开始 · 结束待定';
      }
      return '日期和时间待确认';
    }
    if (intent == CaptureIntentKind.planBlock) {
      return result.startTime != null && result.endTime != null
          ? '${AppTimeFormats.dateFormatter('MM-dd HH:mm').format(result.startTime!)}–${AppTimeFormats.dateFormatter('HH:mm').format(result.endTime!)}'
          : '规划时段待确认';
    }
    if (result.isAllDay && result.startTime != null) {
      return '${AppTimeFormats.dateFormatter('MM-dd').format(result.startTime!)}内完成';
    }
    if (result.endTime != null) {
      return '${AppTimeFormats.dateFormatter('MM-dd HH:mm').format(result.endTime!)}前完成';
    }
    return '未安排';
  }

  String _getReminderText(int minutes) {
    switch (minutes) {
      case 0:
        return "不提醒";
      case 5:
        return "提前 5 分钟";
      case 10:
        return "提前 10 分钟";
      case 15:
        return "提前 15 分钟";
      case 30:
        return "提前 30 分钟";
      case 45:
        return "提前 45 分钟";
      case 60:
        return "提前 1 小时";
      case 120:
        return "提前 2 小时";
      case 1440:
        return "提前 1 天";
      default:
        return "提前 $minutes 分钟";
    }
  }

  void _applyParsedResult(ParsedTodoResult result) {
    final isScheduleResult =
        widget.relatedFixedScheduleContext == null &&
        widget.onFixedScheduleAdded != null &&
        _captureIntentForParsed(result) == CaptureIntentKind.fixedSchedule;
    _mutateState(() {
      if (isScheduleResult) {
        _manualCaptureKind = _ManualCaptureKind.fixedSchedule;
      }
      _titleCtrl.text = result.title;
      _locationCtrl.text = result.location ?? "";
      _remarkCtrl.text = _manualCaptureKind == _ManualCaptureKind.fixedSchedule
          ? (result.remark ?? "")
          : (result.effectiveTodoRemark ?? "");
      _dueDate = null;
      if (result.startTime != null) {
        _createdAt = result.startTime!;
        _scheduleDate = DateTime(
          result.startTime!.year,
          result.startTime!.month,
          result.startTime!.day,
        );
        if (result.isAllDay) {
          _createdAt = DateTime(
            _createdAt.year,
            _createdAt.month,
            _createdAt.day,
            0,
            0,
          );
          _scheduleTimeTbd = true;
        } else {
          _scheduleTimeTbd = false;
          _scheduleStartTime = TimeOfDay.fromDateTime(result.startTime!);
          if (result.endTime != null) {
            _scheduleEndTime = TimeOfDay.fromDateTime(result.endTime!);
            _scheduleEndTimeTbd = false;
          } else {
            _scheduleEndTimeTbd = true;
          }
        }
      }
      if (result.endTime != null) {
        _dueDate = result.endTime;
      } else if (result.startTime != null && result.isAllDay) {
        _dueDate = DateTime(
          _createdAt.year,
          _createdAt.month,
          _createdAt.day,
          23,
          59,
        );
      }
      _isAllDay = result.isAllDay;
      _recurrence = result.recurrence;
      _customDays = result.customIntervalDays;
      _recurrenceEndDate = result.recurrenceEndDate;
      if (_customDays != null) {
        _customDaysCtrl.text = _customDays.toString();
      } else {
        _customDaysCtrl.clear();
      }
      _reminderMinutes =
          result.reminderMinutes ??
          (result.itemKind == 'fixedSchedule' ? 15 : 5);
    });
  }

  Future<void> _doSmartParse() async {
    final input = _aiInputCtrl.text.trim();
    if (input.isEmpty) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text("请输入事项内容")),
      );
      return;
    }
    _mutateState(() => _isParsing = true);
    _startParsingAnimation();
    await Future.delayed(const Duration(milliseconds: 150));

    AiRecognitionHandle? recognitionHandle;
    try {
      recognitionHandle = await AiRecognitionChatBridge.startText(
        input,
        recognizer: '规则文本解析',
      );
    } catch (_) {}
    final results = TodoParserService.parseMulti(input);
    if (recognitionHandle != null) {
      await AiRecognitionChatBridge.complete(
        recognitionHandle,
        todoResults: results.map((result) => result.toMap()).toList(),
      );
    }
    _mutateState(() {
      _parsedResults = results;
      _parsedDraftIds = List.generate(results.length, (_) => const Uuid().v4());
      _parsedWithAi = false;
      _currentParseIndex = 0;
      _isParsing = false;
      _currentOriginalText = input;
    });
    _stopParsingAnimation();

    if (_parsedResults.isNotEmpty) {
      if (widget.onLLMResultsParsed != null && _parsedResults.length > 1) {
        final maps = _parsedResults.map((e) => e.toMap()).toList();
        final currentTeamName = _selectedTeamUuid != null
            ? _teams.where((t) => t.uuid == _selectedTeamUuid).firstOrNull?.name
            : null;
        widget.onLLMResultsParsed!(
          maps,
          null,
          _aiInputCtrl.text,
          _selectedTeamUuid,
          currentTeamName,
        );
        return;
      }

      _applyParsedResult(_parsedResults[0]);
      _mutateState(() => _selectedTabIndex = 0);
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(
            content: Text("解析成功，共${_parsedResults.length}个事项"),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _doLLMParse() async {
    final input = _aiInputCtrl.text.trim();
    if (input.isEmpty) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text("请输入事项内容")),
      );
      return;
    }

    final config = await LLMService.getConfig();
    if (config == null || !config.isConfigured) {
      if (!mounted) return;
      final goToSettings = await showAppDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("未配置大模型"),
          content: const Text("使用大模型识别需要先配置API地址和密钥，是否前往设置？"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("取消"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("去配置"),
            ),
          ],
        ),
      );
      if (goToSettings == true && mounted) {
        Navigator.of(context)
            .push(PageTransitions.slideHorizontal(const SettingsPage()));
      }
      return;
    }

    _mutateState(() => _isParsing = true);
    _startParsingAnimation();
    AiRecognitionHandle? recognitionHandle;
    ChatUsageSummary? recognitionUsage;
    try {
      recognitionHandle = await AiRecognitionChatBridge.startText(input);
    } catch (_) {}

    try {
      final rawResults = await LLMService.parseTodoWithLLM(
        input,
        onUsage: (usage) => recognitionUsage = usage,
      );
      final results = RecognizedTodoAdapter.normalizeResults(rawResults);

      if (widget.onLLMResultsParsed != null && results.length > 1) {
        if (recognitionHandle != null) {
          await AiRecognitionChatBridge.complete(
            recognitionHandle,
            todoResults: results,
            usageSummary: recognitionUsage,
          );
        }
        _mutateState(() {
          _isParsing = false;
          _currentOriginalText = input;
        });
        _stopParsingAnimation();
        final currentTeamName = _selectedTeamUuid != null
            ? _teams.where((t) => t.uuid == _selectedTeamUuid).firstOrNull?.name
            : null;
        widget.onLLMResultsParsed!(
          results,
          null,
          input,
          _selectedTeamUuid,
          currentTeamName,
        );
        return;
      }

      final parsedResultsList = results.map((rawResult) {
        final result = RecognizedTodoAdapter.normalizeResult(rawResult);
        final startTime = RecognizedTodoAdapter.parseDateTime(
          result['startTime'] ??
              result['start_time'] ??
              result['createdDate'] ??
              result['created_date'],
        );
        final endTime = RecognizedTodoAdapter.parseDateTime(
          result['endTime'] ??
              result['end_time'] ??
              result['dueDate'] ??
              result['due_date'],
        );
        final isAllDay = RecognizedTodoAdapter.parseBool(
          result['isAllDay'] ?? result['is_all_day'],
        );
        return ParsedTodoResult(
          title: result['title']?.toString() ?? input,
          remark: (result['remark'] ?? result['notes'] ?? result['note'])
              ?.toString(),
          location: result['location']?.toString(),
          isAllDay: isAllDay,
          startTime: startTime,
          endTime: endTime,
          timeSemantics: _parseTimeSemantics(
            result['timeMode'] ?? result['time_mode'],
            isAllDay: isAllDay,
            startTime: startTime,
            endTime: endTime,
          ),
          recurrence: parseRecurrenceType(result['recurrence']?.toString()),
          customIntervalDays:
              result['customIntervalDays'] ?? result['custom_interval_days'],
          recurrenceEndDate: RecognizedTodoAdapter.parseDateTime(
            result['recurrenceEndDate'] ?? result['recurrence_end_date'],
          ),
          reminderMinutes:
              result['reminderMinutes'] ?? result['reminder_minutes'],
          itemKind: (result['itemKind'] ?? result['item_kind'])?.toString(),
          originalText: input,
        );
      }).toList();

      _mutateState(() {
        _parsedResults = parsedResultsList;
        _parsedDraftIds = List.generate(
          parsedResultsList.length,
          (_) => const Uuid().v4(),
        );
        _parsedWithAi = true;
        _currentParseIndex = 0;
        _isParsing = false;
        _currentOriginalText = input;
      });
      _stopParsingAnimation();

      if (recognitionHandle != null) {
        await AiRecognitionChatBridge.complete(
          recognitionHandle,
          todoResults: results,
          usageSummary: recognitionUsage,
        );
      }

      if (_parsedResults.isNotEmpty) {
        _applyParsedResult(_parsedResults[0]);
        _mutateState(() => _selectedTabIndex = 0);
        if (mounted) {
          AppSnackBars.showSnackBar(
            context,
            SnackBar(
              content: Text("大模型解析成功，共${_parsedResults.length}个事项"),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (recognitionHandle != null) {
        await AiRecognitionChatBridge.fail(recognitionHandle, e);
      }
      _mutateState(() => _isParsing = false);
      _stopParsingAnimation();
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text("大模型解析失败: $e")),
        );
      }
    }
  }

  void _unfocusActiveInput() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _selectManualCaptureKind(int index) {
    _unfocusActiveInput();
    final next = index == 1
        ? _ManualCaptureKind.fixedSchedule
        : _ManualCaptureKind.todo;
    if (next == _ManualCaptureKind.fixedSchedule &&
        widget.onFixedScheduleAdded == null) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('当前入口暂不支持保存日程')),
      );
      return;
    }
    if (next == _ManualCaptureKind.todo &&
        widget.onManualTodoSaved == null &&
        widget.onTodoAdded == null) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('当前入口暂不支持新建待办')),
      );
      return;
    }
    _estimationDebounce?.cancel();
    ++_estimateSequence;
    _mutateState(() {
      _manualCaptureKind = next;
      if (next == _ManualCaptureKind.fixedSchedule) {
        _estimationResult = null;
        _suggestedDueDate = null;
        _classificationSuggestion = null;
        if (_locationCtrl.text.trim().isNotEmpty &&
            _remarkCtrl.text.trim() == _locationCtrl.text.trim()) {
          _remarkCtrl.clear();
        }
      } else if (_locationCtrl.text.trim().isNotEmpty &&
          _remarkCtrl.text.trim().isEmpty) {
        _remarkCtrl.text = _locationCtrl.text.trim();
      }
    });
    if (next == _ManualCaptureKind.todo) _onTitleChanged(force: true);
  }

  Future<void> _requestExit() async {
    if (_allowExit || _isSaving || _exitPromptOpen || !_hasUnsavedDraft) {
      return;
    }
    _exitPromptOpen = true;
    _unfocusActiveInput();
    FocusScope.of(context).unfocus();
    try {
      final action = await showAppDialog<_AddTodoExitAction>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('内容还没有保存'),
          content: const Text('离开后当前填写的待办或识别结果会丢失。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                _AddTodoExitAction.continueEditing,
              ),
              child: const Text('继续填写'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _AddTodoExitAction.discard),
              child: const Text('放弃草稿'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _AddTodoExitAction.save),
              child: const Text('保存并退出'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      switch (action) {
        case _AddTodoExitAction.discard:
          _allowExit = true;
          Navigator.pop(context);
          break;
        case _AddTodoExitAction.save:
          if (_selectedTabIndex == 0) {
            await _addTodo();
          } else {
            await _addBatchTodos();
          }
          break;
        case _AddTodoExitAction.continueEditing:
        case null:
          break;
      }
    } finally {
      _exitPromptOpen = false;
    }
  }

  DateTime _scheduleAt(TimeOfDay time) => DateTime(
    _scheduleDate.year,
    _scheduleDate.month,
    _scheduleDate.day,
    time.hour,
    time.minute,
  );

  Future<void> _pickScheduleDate() async {
    _unfocusActiveInput();
    final picked = await showAppDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: _scheduleDate,
      semesterWeekContext: _semesterWeekContext,
    );
    if (picked == null || !mounted) return;
    _mutateState(() {
      _scheduleDate = picked;
      if (_recurrenceEndDate != null &&
          _recurrenceEndDate!.isBefore(_scheduleDate)) {
        _recurrenceEndDate = _scheduleDate;
      }
    });
  }

  Future<void> _loadSemesterWeekContext() async {
    final semesterWeekContext = await SemesterWeekContext.loadForToday();
    if (!mounted) return;
    _mutateState(() => _semesterWeekContext = semesterWeekContext);
  }

  String _dateWithSemesterWeek(DateTime date, String formattedDate) =>
      _semesterWeekContext?.appendWeekLabel(date, formattedDate) ??
      formattedDate;

  Future<void> _pickScheduleStartTime() async {
    _unfocusActiveInput();
    final picked = await showAppTimePicker(
      context: context,
      initialTime: _scheduleStartTime,
    );
    if (picked != null && mounted) {
      _mutateState(() => _scheduleStartTime = picked);
    }
  }

  Future<void> _pickScheduleEndTime() async {
    _unfocusActiveInput();
    final picked = await showAppTimePicker(
      context: context,
      initialTime: _scheduleEndTime,
    );
    if (picked != null && mounted) {
      _mutateState(() => _scheduleEndTime = picked);
    }
  }

  Future<String?> _resolveUsername() async {
    if (widget.username?.trim().isNotEmpty == true) {
      return widget.username!.trim();
    }
    if (_username?.trim().isNotEmpty == true) {
      return _username!.trim();
    }
    final session = await StorageService.getLoginSession();
    if (session?.trim().isNotEmpty == true) {
      return session!.trim();
    }
    final active = await _estimateAccount;
    if (active.trim().isNotEmpty) {
      return active.trim();
    }
    return null;
  }

  String? _normalizeTeamUuid(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  String get _currentTeamScopeLabel {
    if (_selectedTeamUuid == null) return '个人私有';
    return _teams.where((t) => t.uuid == _selectedTeamUuid).firstOrNull?.name ??
        '团队';
  }

  Future<void> _chooseScheduleRelatedTodos() async {
    _unfocusActiveInput();
    final username = await _resolveUsername();
    if (username == null || !mounted) return;
    final page = FixedScheduleRelatedTodoPickerScreen(
      username: username,
      teamUuid: _selectedTeamUuid,
      initialSelectedIds: Set<String>.from(_scheduleRelatedTodoIds),
      loadTodoPage: widget.loadRelatedTodoPage,
      loadSelectedTodos: widget.loadSelectedRelatedTodos,
    );
    final selected = await PageTransitions.pushFromRect<Set<String>>(
      context: context,
      sourceKey: _relatedTodosTileKey,
      page: page,
    );
    if (selected == null || !mounted) return;
    _mutateState(() => _scheduleRelatedTodoIds = Set<String>.from(selected));
  }

  Future<String?> _invalidRelatedTodoMessage() async {
    if (_scheduleRelatedTodoIds.isEmpty) return null;
    final username = await _resolveUsername();
    if (username == null) return null;
    final todos =
        await (widget.loadSelectedRelatedTodos?.call(
              username,
              _scheduleRelatedTodoIds,
            ) ??
            StorageService.getTodosForFixedScheduleRelationIds(
              username,
              _scheduleRelatedTodoIds,
            ));
    final todosById = {for (final todo in todos) todo.id: todo};
    final targetTeamUuid = _normalizeTeamUuid(_selectedTeamUuid);
    final invalidIds = _scheduleRelatedTodoIds.where((id) {
      final todo = todosById[id];
      return todo == null ||
          todo.isDeleted ||
          _normalizeTeamUuid(todo.teamUuid) != targetTeamUuid;
    });
    if (invalidIds.isEmpty) return null;
    return '请在“关联待办”中移除已删除或当前日程不可见的项目后再保存';
  }
}
