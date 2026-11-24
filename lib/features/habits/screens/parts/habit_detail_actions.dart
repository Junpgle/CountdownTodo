part of '../habit_detail_screen.dart';

extension _HabitDetailActions on _HabitDetailScreenState {
  Future<void> _enableSleepCoaching() async {
    try {
      final username = await _accountUsername();
      final snapshot = await HabitSleepCoachingService.enable(
        username: username,
      );
      if (mounted) _mutateState(() => _sleepCoachingSnapshot = snapshot);
    } catch (_) {
      if (!mounted) return;
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('训练计划开启失败，请稍后重试')),
      );
    }
  }

  Future<void> _setSleepCoachingPaused(bool paused) async {
    final snapshot = _sleepCoachingSnapshot;
    if (snapshot == null) return;
    try {
      final username = await _accountUsername();
      final plan = await HabitSleepCoachingService.setPaused(
        username: username,
        plan: snapshot.plan,
        paused: paused,
      );
      final refreshed = await HabitSleepCoachingService.load(username);
      if (mounted) {
        _mutateState(
          () => _sleepCoachingSnapshot =
              refreshed ??
              HabitSleepCoachingSnapshot(
                plan: plan,
                stageIndex: 0,
                stageProgressDays: 0,
                metrics: snapshot.metrics,
              ),
        );
      }
    } catch (_) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('训练状态更新失败，请稍后重试')),
        );
      }
    }
  }

  Future<void> _setSleepCoachingEnabled(bool enabled) async {
    final snapshot = _sleepCoachingSnapshot;
    if (snapshot == null) return;
    try {
      final username = await _accountUsername();
      final plan = await HabitSleepCoachingService.setEnabled(
        username: username,
        plan: snapshot.plan,
        enabled: enabled,
      );
      final refreshed = await HabitSleepCoachingService.load(username);
      if (mounted) {
        _mutateState(
          () => _sleepCoachingSnapshot =
              refreshed ??
              HabitSleepCoachingSnapshot(
                plan: plan,
                stageIndex: 0,
                stageProgressDays: 0,
                metrics: snapshot.metrics,
              ),
        );
      }
    } catch (_) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('训练开关更新失败，请稍后重试')),
        );
      }
    }
  }

  Future<void> _updateSleepCoachingSettings(
    int stepMinutes,
    int stageDays,
  ) async {
    final snapshot = _sleepCoachingSnapshot;
    if (snapshot == null) return;
    try {
      final username = await _accountUsername();
      final plan = await HabitSleepCoachingService.updateSettings(
        username: username,
        plan: snapshot.plan,
        stepMinutes: stepMinutes,
        stageDays: stageDays,
      );
      final refreshed = await HabitSleepCoachingService.load(username);
      if (mounted) {
        _mutateState(
          () => _sleepCoachingSnapshot =
              refreshed ??
              HabitSleepCoachingSnapshot(
                plan: plan,
                stageIndex: 0,
                stageProgressDays: 0,
                metrics: snapshot.metrics,
              ),
        );
      }
    } catch (_) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('训练节奏更新失败，请稍后重试')),
        );
      }
    }
  }

  Future<void> _loadTimeLogImportPreview() async {
    final adaptation = HabitAdaptationService.forHabit(_goal);
    final part = switch (adaptation?.kind) {
      HabitAdaptationKind.earlySleep => HabitTimeLogImportPart.bedtime,
      HabitAdaptationKind.earlyWake => HabitTimeLogImportPart.wakeTime,
      _ => null,
    };
    if (part == null) {
      if (mounted) {
        _mutateState(() {
          _timeLogImportPreview = null;
          _timeLogImportPart = null;
        });
      }
      return;
    }
    try {
      final results = await Future.wait<dynamic>([
        StorageService.getTimeLogs(widget.username),
        PomodoroService.getTags(),
      ]);
      final tags = results[1] as List<PomodoroTag>;
      final preview = await HabitSleepLogMigrationService.buildImportPreview(
        goal: _goal,
        logs: results[0] as List<TimeLogItem>,
        tagNames: {for (final tag in tags) tag.uuid: tag.name},
        part: part,
      );
      if (!mounted) return;
      _mutateState(() {
        _timeLogImportPreview = preview;
        _timeLogImportPart = part;
      });
    } catch (_) {
      // 导入入口属于增强体验，读取失败不影响习惯详情的正常展示。
    }
  }

  HabitGoalRuleRevision get _rule {
    final rule = HabitRuleResolver.effectiveRule(
      _rules,
      HabitSleepDurationService.displayLogicalDateFor(_goal, DateTime.now()),
    );
    return rule ??
        HabitGoalRuleRevision(
          habitUuid: _goal.uuid,
          effectiveFromDate: '',
          periodType: HabitPeriodType.daily,
        );
  }

  Future<void> _editHabit() async {
    final changed = await PageTransitions.pushFromRect(
      context: context,
      page: HabitEditScreen(goal: _goal),
      sourceKey: _menuActionKey,
      sourceBorderRadius: BorderRadius.circular(20),
    );
    if (changed == true && mounted) {
      _loadData();
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _openHistory({GlobalKey? sourceKey}) async {
    await PageTransitions.pushFromRect(
      context: context,
      page: HabitHistoryScreen(goal: _goal, username: widget.username),
      sourceKey: sourceKey ?? _menuActionKey,
      sourceBorderRadius: BorderRadius.circular(16),
    );
    if (mounted) _loadData();
  }

  Future<void> _toggleArchive() async {
    await HabitRepository.setArchived(_goal, !_goal.isArchived);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _deleteHabit() async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除习惯'),
        content: Text('确定删除「${_goal.name}」吗？历史记录将保留但不再展示。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await HabitRepository.deleteGoal(_goal);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _openTimeLogImport() async {
    final preview = _timeLogImportPreview;
    final part = _timeLogImportPart;
    if (preview == null || part == null || !preview.hasPendingLogs) return;
    final isBedtime = part == HabitTimeLogImportPart.bedtime;
    final habitLabel = isBedtime ? '早睡' : '早起';
    final colorScheme = Theme.of(context).colorScheme;
    var timeSelection = HabitSleepLogTimeSelection.startTime;
    var sleepKind = HabitSleepLogKind.fullSleep;
    final options = await showAppDialog<HabitSleepLogMigrationOptions>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final selectedPending =
              isBedtime && sleepKind == HabitSleepLogKind.nap
              ? preview.pendingLogs
                    .where((log) => !preview.gridOnlyLogIds.contains(log.id))
                    .toList(growable: false)
              : preview.pendingLogs;
          final previewLogs = selectedPending.take(6).toList(growable: false);
          final selectedOptions = HabitSleepLogMigrationOptions(
            timeSelection: timeSelection,
            kind: sleepKind,
          );
          return AlertDialog(
            title: Text('导入$habitLabel时间日志'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '将把 ${selectedPending.length} 条记录作为“$habitLabel”的历史打卡导入。原时间日志不会修改，历史记录中会保留原来的日期和${isBedtime ? '入睡' : '起床'}时间。',
                  ),
                  if (isBedtime && preview.gridOnlyLogIds.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      '记录类型',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('整段睡眠'),
                          selected: sleepKind == HabitSleepLogKind.fullSleep,
                          onSelected: (_) => setDialogState(
                            () => sleepKind = HabitSleepLogKind.fullSleep,
                          ),
                        ),
                        ChoiceChip(
                          label: const Text('小睡'),
                          selected: sleepKind == HabitSleepLogKind.nap,
                          onSelected: (_) => setDialogState(
                            () => sleepKind = HabitSleepLogKind.nap,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      sleepKind == HabitSleepLogKind.fullSleep
                          ? '短时间格仅作为入睡时间标记。'
                          : '短时间格会被视为小睡，不导入早睡。',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '时间点取法',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('取开始时间'),
                          selected:
                              timeSelection ==
                              HabitSleepLogTimeSelection.startTime,
                          onSelected: (_) => setDialogState(
                            () => timeSelection =
                                HabitSleepLogTimeSelection.startTime,
                          ),
                        ),
                        ChoiceChip(
                          label: const Text('取平均时间'),
                          selected:
                              timeSelection ==
                              HabitSleepLogTimeSelection.midpoint,
                          onSelected: (_) => setDialogState(
                            () => timeSelection =
                                HabitSleepLogTimeSelection.midpoint,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  ...previewLogs.map((log) {
                    final eventTime = DateTime.fromMillisecondsSinceEpoch(
                      isBedtime ? log.startTime : log.endTime,
                    ).toLocal();
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Icon(
                            isBedtime
                                ? Icons.nightlight_round
                                : Icons.wb_twilight_rounded,
                            size: 16,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            '${eventTime.year}-${eventTime.month.toString().padLeft(2, '0')}-'
                            '${eventTime.day.toString().padLeft(2, '0')}',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                          const Spacer(),
                          Text(
                            HabitText.timeOfDay(eventTime),
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (selectedPending.length > previewLogs.length) ...[
                    const SizedBox(height: 4),
                    Text(
                      '还有 ${selectedPending.length - previewLogs.length} 条记录未展开',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    '这些记录会标记为“导入”，不会伪造新的连续打卡。历史页会展示它们；既有目标规则和历史统计不会被自动改写。',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton.icon(
                onPressed: selectedPending.isEmpty
                    ? null
                    : () => Navigator.of(dialogContext).pop(selectedOptions),
                icon: const Icon(Icons.file_download_outlined),
                label: Text('导入 ${selectedPending.length} 条'),
              ),
            ],
          );
        },
      ),
    );
    if (options == null || !mounted) return;

    final selectedPending = isBedtime && options.kind == HabitSleepLogKind.nap
        ? preview.pendingLogs
              .where((log) => !preview.gridOnlyLogIds.contains(log.id))
              .toList(growable: false)
        : preview.pendingLogs;
    if (selectedPending.isEmpty) return;
    final effectivePreview = HabitTimeLogImportPreview(
      candidateLogs: preview.candidateLogs,
      pendingLogs: selectedPending,
      alreadyImportedCount:
          preview.candidateLogs.length - selectedPending.length,
      gridOnlyLogIds: preview.gridOnlyLogIds,
    );

    try {
      final imported = await HabitSleepLogMigrationService.importTimeLogs(
        goal: _goal,
        rule: _rule,
        preview: effectivePreview,
        part: part,
        options: options,
      );
      await HabitSleepDurationService.syncAll();
      if (!mounted) return;
      AppSnackBars.showSnackBar(
        context,
        SnackBar(content: Text('已导入 $imported 条$habitLabel历史打卡')),
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      AppSnackBars.showSnackBar(context, SnackBar(content: Text('导入失败：$e')));
    }
  }

  Future<void> _editRecord(HabitCheckIn? checkIn) async {
    if (checkIn == null) {
      AppSnackBars.showSnackBar(
        context,
        SnackBar(content: Text('$_displayPeriodLabel还没有记录')),
      );
      return;
    }
    final rule = _rules.firstWhere(
      (candidate) => candidate.uuid == checkIn.ruleRevisionUuid,
      orElse: () => _rule,
    );
    final edited = await showHabitCheckInEditor(
      context: context,
      goal: _goal,
      rule: rule,
      checkIn: checkIn,
    );
    if (edited == null || !mounted) return;
    await HabitRepository.updateCheckIn(edited);
    _loadData();
  }

  Future<void> _deleteRecord(HabitCheckIn checkIn) async {
    if (checkIn.source == HabitCheckInSource.freeze) {
      await HabitFreezeService.revokeFreeze(
        goal: _goal,
        freezeCheckIn: checkIn,
      );
    } else {
      await HabitRepository.deleteCheckIn(checkIn);
    }
    if (mounted) _loadData();
  }

  /// 补录：选择任意日期时间新增一条打卡。
  Future<void> _addBackfill() async {
    final now = DateTime.now();
    var date = now;
    var time = TimeOfDay.fromDateTime(now);
    // 局部 controller：对话框每次打开都是空值，避免残留上一次输入。
    final valueController = TextEditingController();

    final ok = await showAppDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('补录打卡'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_rounded),
                title: Text(
                  '${date.year}-${date.month.toString().padLeft(2, '0')}-'
                  '${date.day.toString().padLeft(2, '0')}',
                ),
                onTap: () async {
                  final picked = await showAppDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: now.subtract(const Duration(days: 90)),
                    lastDate: now,
                  );
                  if (picked != null) {
                    setDialogState(() {
                      date = DateTime(
                        picked.year,
                        picked.month,
                        picked.day,
                        time.hour,
                        time.minute,
                      );
                    });
                  }
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule_rounded),
                title: Text(
                  '时间：${time.hour.toString().padLeft(2, '0')}:'
                  '${time.minute.toString().padLeft(2, '0')}',
                ),
                onTap: () async {
                  final picked = await showAppTimePicker(
                    context: context,
                    initialTime: time,
                  );
                  if (picked != null) {
                    setDialogState(() {
                      time = picked;
                      date = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        picked.hour,
                        picked.minute,
                      );
                    });
                  }
                },
              ),
              if (_goal.sourceType == HabitSourceType.quantityCheckIn ||
                  _goal.sourceType == HabitSourceType.durationCheckIn) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: valueController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText:
                        _goal.sourceType == HabitSourceType.durationCheckIn
                        ? '睡眠时长（小时）'
                        : '数量${_rule.unit.isNotEmpty ? '（${_rule.unit}）' : ''}',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('补录'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) {
      valueController.dispose();
      return;
    }

    double value = 0;
    if (_goal.sourceType == HabitSourceType.quantityCheckIn ||
        _goal.sourceType == HabitSourceType.durationCheckIn) {
      final parsed = double.tryParse(valueController.text.trim());
      valueController.dispose();
      if (parsed == null || parsed <= 0) {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('请输入有效的数量')),
        );
        return;
      }
      value = _goal.sourceType == HabitSourceType.durationCheckIn
          ? parsed * 3600
          : parsed;
    } else {
      valueController.dispose();
    }
    await HabitRepository.addCheckIn(
      goal: _goal,
      rule: _rule,
      localOccurredAt: date,
      value: value,
    );
    _loadData();
  }

  /// 时长型：启动专注并跳转番茄钟，默认时长为习惯设置的默认时长。
  Future<void> _startFocus() => HabitFocusLauncher.open(
    context: context,
    username: widget.username,
    goal: _goal,
    sourceKey: _detailCardKey,
    onReturned: () {
      _loadData();
    },
  );
}
