part of '../workbench_view.dart';

extension _PomodoroWorkbenchDialogsExt on PomodoroWorkbenchState {
  void _showSettingsDialog({String? focusLabel}) {
    final focusCtrl = TextEditingController(
      text: (_preparedFocusMinutes ?? _settings.focusMinutes).toString(),
    );
    final breakCtrl = TextEditingController(
      text: _settings.breakMinutes.toString(),
    );
    final cyclesCtrl = TextEditingController(text: _settings.cycles.toString());
    showAppDialog(
      context: context,
      builder: (ctx) => SettingsFocusPage(
        labels: [?focusLabel],
        child: AlertDialog(
          title: const Text('⚙️ 番茄钟设置'),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _settingField('专注时长 (分钟)', focusCtrl),
              const SizedBox(height: 16),
              _settingField('休息时长 (分钟)', breakCtrl),
              const SizedBox(height: 16),
              _settingField('循环次数', cyclesCtrl),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final f = int.tryParse(focusCtrl.text) ?? 25;
                final b = int.tryParse(breakCtrl.text) ?? 5;
                final c = int.tryParse(cyclesCtrl.text) ?? 4;
                final ns = PomodoroSettings(
                  focusMinutes: f.clamp(1, 120),
                  breakMinutes: b.clamp(1, 60),
                  cycles: c.clamp(1, 20),
                  mode: _settings.mode,
                  strictFreeFocus: _settings.strictFreeFocus,
                  doNotDisturbDuringFocus: _settings.doNotDisturbDuringFocus,
                );
                await PomodoroService.saveSettings(ns);
                if (!mounted) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  return;
                }
                _mutateState(() {
                  _settings = ns;
                  _preparedFocusMinutes = null;
                  if (_phase == PomodoroPhase.idle) {
                    _remainingSeconds = ns.mode == TimerMode.countUp
                        ? 0
                        : ns.focusMinutes * 60;
                  }
                });
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _showNoteDialog() {
    final ctrl = TextEditingController(text: _currentNote);
    final isRemote = _phase == PomodoroPhase.remoteWatching;
    showAppDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('专注备注'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              maxLines: 5,
              minLines: 3,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '记录这次专注的感想、收获…',
                border: OutlineInputBorder(),
              ),
            ),
            if (isRemote) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Theme.of(ctx).colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '当前为远程观看，若发起端不在线，备注可能无法同步',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(ctx).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              if (!mounted) {
                if (ctx.mounted) Navigator.pop(ctx);
                return;
              }
              _mutateState(() => _currentNote = ctrl.text);
              if (ctx.mounted) Navigator.pop(ctx);
              await _saveCurrentRunState();
              if (!mounted) return;
              if (_phase == PomodoroPhase.focusing ||
                  _phase == PomodoroPhase.remoteWatching) {
                _syncService.sendUpdateNoteSignal(
                  sessionUuid: _currentSessionUuid,
                  note: _currentNote,
                );
                _showLocalFloat();
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Widget _settingField(String label, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
    );
  }

  void _showTagsDialog() async {
    await PageTransitions.pushFromRect<List<PomodoroTag>>(
      context: context,
      page: UnifiedTagManagerScreen(
        allTags: _allTags,
        selectedUuids: _selectedTagUuids,
        showSelection: true,
        showArchive: true,
        onChanged: (tags, selected) async {
          await PomodoroService.saveTags(tags);
          if (!mounted) return;
          PomodoroService.syncTagsToCloud().catchError((_) => null);
          _mutateState(() {
            _allTags = tags;
            _tags = tags.where((t) => !t.isArchived).toList();
            _selectedTagUuids = selected;
          });
          await _persistIdleBoundTodo(_boundTodo);
          await _saveCurrentRunState();
          _showLocalFloat();
          if (_phase == PomodoroPhase.focusing) {
            final tagNames = tags
                .where((t) => selected.contains(t.uuid) && !t.isArchived)
                .map((t) => t.name)
                .toList();
            _syncService.sendUpdateTagsSignal(tagNames);
          }
        },
      ),
      sourceKey: tagsManagerKey,
      sourceBorderRadius: BorderRadius.circular(24),
      placeholderIcon: Icons.label_outline,
    );
  }

  void _showBindTodoDialog({bool isSwitching = false}) {
    final pickerTodos = collapseRecurrenceSeriesForTodoPicker(_todos);
    showAppModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                isSwitching ? '切换专注任务' : '选择专注任务',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _boundTodo == null
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _boundTodo == null ? Icons.check : Icons.clear,
                        size: 20,
                        color: _boundTodo == null
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    title: const Text('不绑定任务（自由专注）'),
                    selected: _boundTodo == null,
                    selectedTileColor: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.3),
                    onTap: () async {
                      Navigator.pop(ctx);
                      if (_phase == PomodoroPhase.focusing) {
                        await _switchTask(null);
                      } else {
                        final clearPlanBinding = _planBlockId != null;
                        _mutateState(() {
                          _boundTodo = null;
                          _planBlockId = null;
                          if (clearPlanBinding) _preparedFocusMinutes = null;
                        });
                        await _persistIdleBoundTodo(null);
                        await _saveCurrentRunState();
                      }
                    },
                  ),
                  const Divider(height: 1),
                  ...(() {
                    final Map<String?, List<TodoItem>> grouped = {};
                    final groupIds = _todoGroups.map((g) => g.id).toSet();
                    for (var t in pickerTodos) {
                      final groupId = t.groupId;
                      final effectiveGroupId =
                          groupId != null &&
                              groupId.isNotEmpty &&
                              groupIds.contains(groupId)
                          ? groupId
                          : null;
                      grouped.putIfAbsent(effectiveGroupId, () => []).add(t);
                    }

                    List<Widget> sections = [];
                    // Process named groups
                    for (var g in _todoGroups) {
                      final tasks = grouped[g.id];
                      if (tasks != null && tasks.isNotEmpty) {
                        sections.add(_buildSectionHeader(g.name));
                        sections.addAll(
                          tasks.map((t) => _buildTodoTile(ctx, t, isSwitching)),
                        );
                        grouped.remove(g.id);
                      }
                    }

                    // Process unassigned tasks
                    if (grouped.containsKey(null)) {
                      final tasks = grouped[null]!;
                      if (tasks.isNotEmpty) {
                        sections.add(_buildSectionHeader('未分组'));
                        sections.addAll(
                          tasks.map((t) => _buildTodoTile(ctx, t, isSwitching)),
                        );
                      }
                    }

                    return sections;
                  })(),
                  if (pickerTodos.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.inbox_outlined,
                              size: 48,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 16),
                            Text(
                              '没有未完成的待办',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildTodoTile(BuildContext ctx, TodoItem t, bool isSwitching) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.check,
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: _buildTodoPickerSubtitle(t),
      selected: areSameTodoOrRecurrenceSeries(t, _boundTodo),
      selectedTileColor: Theme.of(context).colorScheme.primaryContainer
          .withValues(alpha: 0.3),
      onTap: () async {
        Navigator.pop(ctx);
        if (_phase == PomodoroPhase.focusing) {
          await _switchTask(t);
        } else {
          final recommended = await _recommendedTagUuidsForTodo(t);
          if (!mounted) return;
          _mutateState(() {
            if (_planBlockId != null && _boundTodo?.id != t.id) {
              _planBlockId = null;
              _preparedFocusMinutes = null;
            }
            _boundTodo = t;
            if (recommended.isNotEmpty) {
              _selectedTagUuids = recommended;
            }
          });
          await _persistIdleBoundTodo(t);
          await _saveCurrentRunState();
          _showLocalFloat();
        }
      },
    );
  }

  Widget? _buildTodoPickerSubtitle(TodoItem todo) {
    final labels = <String>[
      if (todo.recurrenceSeriesId?.isNotEmpty == true) '重复待办',
      if (todo.remark?.isNotEmpty == true) todo.remark!,
    ];
    if (labels.isEmpty) return null;
    return Text(
      labels.join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// 从当前 widget 状态构建 PomodoroRunState，统一各调用点
  PomodoroRunState _buildCurrentRunState() => PomodoroRunState(
    phase: _phase,
    sessionUuid: _currentSessionUuid,
    targetEndMs: _targetEndMs,
    currentCycle: _currentCycle,
    totalCycles: _settings.cycles,
    focusSeconds: _settings.mode == TimerMode.countUp
        ? 0
        : (_activeFocusSeconds ?? _settings.focusMinutes * 60),
    breakSeconds: _settings.breakMinutes * 60,
    todoUuid: _boundTodo?.id,
    todoTitle: _boundTodo?.title,
    tagUuids: _selectedTagUuids,
    tagNames: _tags
        .where((tag) => _selectedTagUuids.contains(tag.uuid))
        .map((tag) => tag.name)
        .toList(),
    sessionStartMs: _sessionStartMs,
    plannedFocusSeconds: _settings.mode == TimerMode.countUp
        ? 0
        : (_activeFocusSeconds ?? _settings.focusMinutes * 60),
    mode: _settings.mode,
    strictFreeFocus: _settings.strictFreeFocus,
    strictWaitingForFlip: _strictWaitingForFlip,
    doNotDisturbDuringFocus: _settings.doNotDisturbDuringFocus,
    isPaused: _isPaused,
    pausedAtMs: _pausedAtMs,
    accumulatedMs: _accumulatedMs,
    pauseStartMs: _pauseStartMs,
    pauseIntervals: _pauseIntervals,
    planBlockId: _planBlockId,
    habitUuid: _habitUuid,
    challengeTaskId: _challengeTaskId,
    note: _currentNote.isNotEmpty ? _currentNote : null,
  );

  Future<void> _saveCurrentRunState() async {
    if (_phase == PomodoroPhase.idle ||
        _phase == PomodoroPhase.finished ||
        _phase == PomodoroPhase.remoteWatching) {
      return;
    }
    await PomodoroService.saveRunState(_buildCurrentRunState());
  }

  Future<void> _showLocalFloat() async {
    final bool isFocusing = _phase == PomodoroPhase.focusing;
    final bool isRemoteWatching = _phase == PomodoroPhase.remoteWatching;
    final bool isIdle =
        _phase == PomodoroPhase.idle || _phase == PomodoroPhase.finished;

    final tagNames = _tags
        .where((t) => _selectedTagUuids.contains(t.uuid))
        .map((t) => t.name)
        .toList();

    int effectiveEndMs = 0;
    int mode = 0;

    if (!isIdle) {
      final isCountUp = isFocusing && _settings.mode == TimerMode.countUp;
      final isRemoteCountUp = isRemoteWatching && _remoteState?.mode == 1;
      effectiveEndMs = (isCountUp)
          ? _sessionStartMs + _accumulatedMs
          : (isRemoteCountUp ? (_remoteState?.timestamp ?? 0) : _targetEndMs);
      mode = (isCountUp || isRemoteCountUp) ? 1 : 0;
    }

    String displayTitle = _boundTodo?.title ?? '';
    if (displayTitle.isEmpty && !isIdle) {
      displayTitle = mode == 1 ? '自由专注' : '倒计时';
    }

    if (isIdle) {
      // Forward explicitly to clear the island session state when the local
      // workbench enters idle/finished phase.
      await _updateFloatSafely(
        FloatWindowService.update(endMs: 0, isLocal: true),
      );
    } else {
      await _updateFloatSafely(
        FloatWindowService.update(
          endMs: effectiveEndMs,
          title: displayTitle,
          tags: tagNames,
          isLocal: _phase != PomodoroPhase.remoteWatching,
          mode: mode,
          isPaused: _isPaused,
          accumulatedMs: _accumulatedMs,
          pauseStartMs: _pauseStartMs,
          note: _currentNote,
        ),
      );
    }
  }

  Future<void> _updateFloatSafely(Future<void> update) async {
    try {
      await update.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      // debugPrint('[PomodoroWorkbench] Float window update timed out');
    } catch (e) {
      // debugPrint('[PomodoroWorkbench] Float window update failed: $e');
    }
  }
}
