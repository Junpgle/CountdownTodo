part of '../workbench_view.dart';

extension _PomodoroWorkbenchSessionExt on PomodoroWorkbenchState {
  Future<void> _recoverState(PomodoroRunState saved) async {
    if (!saved.strictWaitingForFlip) _strictWaitPlanStatusReceipt = null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final bool isCountUp = saved.mode == TimerMode.countUp;
    final bool isStrictFreeFocus =
        saved.strictFreeFocus && saved.mode == TimerMode.countUp;
    final bool forceStrictPause =
        isStrictFreeFocus &&
        !saved.isPaused &&
        !StrictFocusSessionCoordinator.instance.isMonitoringOrStarting;
    final int savedAccumulated = saved.accumulatedMs;
    int remaining;
    if (isCountUp) {
      if (saved.isPaused == true) {
        remaining =
            (((saved.pausedAtMs - saved.sessionStartMs) - savedAccumulated) /
                    1000)
                .floor();
      } else {
        remaining = (((now - saved.sessionStartMs) - savedAccumulated) / 1000)
            .floor();
      }
    } else {
      if (saved.isPaused == true) {
        remaining = ((saved.targetEndMs - saved.pausedAtMs) / 1000).ceil();
      } else {
        remaining = ((saved.targetEndMs - now) / 1000).ceil();
      }
    }
    _pauseStartMs = saved.pauseStartMs;

    if (saved.phase == PomodoroPhase.focusing ||
        saved.phase == PomodoroPhase.breaking) {
      if (!isCountUp && remaining <= 0 && saved.isPaused != true) {
        if (saved.phase == PomodoroPhase.focusing) {
          await _handleFocusEndFromBackground(saved);
        } else {
          await _handleBreakEndFromBackground(saved);
        }
        return;
      }
      TodoItem? boundTodo;
      if (saved.todoUuid != null) {
        boundTodo = _todos.cast<TodoItem?>().firstWhere(
          (t) => t?.id == saved.todoUuid,
          orElse: () => null,
        );
        if (boundTodo == null &&
            saved.todoTitle != null &&
            saved.todoTitle!.isNotEmpty) {
          boundTodo = TodoItem(
            id: saved.todoUuid!,
            title: saved.todoTitle!,
            isDone: false,
            createdAt: 0,
          );
        }
      }
      if (mounted) {
        _mutateState(() {
          _phase = saved.strictWaitingForFlip
              ? PomodoroPhase.idle
              : saved.phase;
          _currentSessionUuid = saved.sessionUuid;
          _targetEndMs = saved.targetEndMs;
          _remainingSeconds = remaining;
          _currentCycle = saved.currentCycle;
          _settings.focusMinutes = saved.focusSeconds ~/ 60;
          _settings.breakMinutes = saved.breakSeconds ~/ 60;
          _settings.cycles = saved.totalCycles;
          _settings.mode = saved.mode;
          _settings.strictFreeFocus = saved.strictFreeFocus;
          _settings.doNotDisturbDuringFocus = saved.doNotDisturbDuringFocus;
          _boundTodo = boundTodo;
          _selectedTagUuids = saved.tagUuids;
          _planBlockId = saved.planBlockId;
          _habitUuid = saved.habitUuid;
          _challengeTaskId = saved.challengeTaskId;
          _activeFocusSeconds = saved.focusSeconds;
          _preparedFocusMinutes = null;
          _sessionStartMs = saved.sessionStartMs;
          _strictWaitingForFlip =
              isStrictFreeFocus && saved.strictWaitingForFlip;
          _isPaused = saved.isPaused || forceStrictPause;
          _pausedAtMs = forceStrictPause ? now : saved.pausedAtMs;
          _accumulatedMs = saved.accumulatedMs;
          _pauseStartMs = forceStrictPause ? now : saved.pauseStartMs;
          _currentNote = saved.note ?? '';
          _pauseIntervals
            ..clear()
            ..addAll(saved.pauseIntervals);
          if (forceStrictPause) {
            _pauseIntervals.add(PauseInterval(startMs: now));
          }
        });
        if (!_initializing) widget.onPhaseChanged(_phase);
        await _setFocusDoNotDisturb(
          saved.phase == PomodoroPhase.focusing &&
              saved.doNotDisturbDuringFocus &&
              !saved.strictWaitingForFlip,
          sessionUuid: saved.sessionUuid,
          untilMs: saved.isPaused || isCountUp ? null : saved.targetEndMs,
        );
        if (forceStrictPause) {
          await PomodoroService.saveRunState(_buildCurrentRunState());
        }
        _syncService.setLocalFocusing(true);
        _pushPomodoroNotification(overrideRemaining: remaining);
        _showLocalFloat();
        if (isStrictFreeFocus) {
          await StrictFocusSessionCoordinator.instance.startMonitoring(
            requireInitialFaceUp: false,
          );
        }
        if (saved.isPaused == true || forceStrictPause) {
          _ticker?.cancel();
          _startPauseTicker();
        } else {
          _pauseTicker?.cancel();
          _pauseTicker = null;
          _startTicker();
        }
        if (!isCountUp && saved.isPaused != true && !forceStrictPause) {
          _scheduleReminders(
            saved.targetEndMs,
            saved.phase,
            saved.todoTitle,
            saved.currentCycle,
            saved.totalCycles,
            sessionUuid: saved.sessionUuid,
          );
        } else if (!isCountUp) {
          // A previously registered focus-end alarm is stale while paused.
          unawaited(
            NotificationService.cancelReminder(
              saved.phase == PomodoroPhase.focusing ? 40001 : 40002,
            ),
          );
        }
      }
    }
  }

  void _scheduleReminders(
    int endMs,
    PomodoroPhase phase,
    String? todoTitle,
    int cycle,
    int total, {
    String? sessionUuid,
  }) {
    final isFocusing = phase == PomodoroPhase.focusing;
    final alarmNotifId = isFocusing ? 40001 : 40002;
    final alarmTitle = isFocusing ? '🍅 专注时间到！' : '☕ 休息结束，继续出发！';
    final alarmText = isFocusing
        ? (todoTitle != null && todoTitle.isNotEmpty
              ? '"$todoTitle" 专注时段已结束'
              : '本轮专注已结束，做个总结吧')
        : '第 $cycle/$total 轮完成，下一轮专注准备好了';
    NotificationService.scheduleReminders(
      [
        {
          'triggerAtMs': endMs,
          'title': alarmTitle,
          'text': alarmText,
          'notifId': alarmNotifId,
          'type': 'pomodoro',
          'source': ScheduledReminderSources.pomodoro,
          'sessionUuid': ?sessionUuid,
        },
      ],
      clearFirst: false,
      replaceSource: ScheduledReminderSources.pomodoro,
    );
  }

  Future<void> _recoverFromBackground() async {
    if (_phase == PomodoroPhase.focusing || _phase == PomodoroPhase.breaking) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final bool isCountUp = _settings.mode == TimerMode.countUp;

      int remaining;
      if (isCountUp) {
        if (_isPaused) {
          remaining = ((_pausedAtMs - _sessionStartMs - _accumulatedMs) / 1000)
              .floor();
        } else {
          remaining = (((now - _sessionStartMs) - _accumulatedMs) / 1000)
              .floor();
        }
      } else {
        if (_isPaused) {
          remaining = ((_targetEndMs - _pausedAtMs) / 1000).ceil();
        } else {
          remaining = ((_targetEndMs - now) / 1000).ceil();
        }
      }

      if (!isCountUp && remaining <= 0 && !_isPaused) {
        _ticker?.cancel();
        if (_phase == PomodoroPhase.focusing) {
          await _onFocusEnd();
        } else {
          await _onBreakEnd();
        }
      } else {
        _mutateState(() => _remainingSeconds = remaining);
        if (!_isPaused && _ticker?.isActive != true) {
          _startTicker();
        }
      }
    }
  }

  Future<void> _handleFocusEndFromBackground(PomodoroRunState saved) async {
    if (_isHandlingEnd) return;
    _isHandlingEnd = true;
    try {
      NotificationService.cancelReminder(40001);
      TodoItem? boundTodo;
      if (saved.todoUuid != null) {
        boundTodo = _todos.cast<TodoItem?>().firstWhere(
          (t) => t?.id == saved.todoUuid,
          orElse: () => null,
        );
        if (boundTodo == null &&
            saved.todoTitle != null &&
            saved.todoTitle!.isNotEmpty) {
          boundTodo = TodoItem(
            id: saved.todoUuid!,
            title: saved.todoTitle!,
            isDone: false,
            createdAt: 0,
          );
        }
      }
      _mutateState(() {
        _phase = PomodoroPhase.idle;
        _currentCycle = saved.currentCycle;
        _boundTodo = boundTodo;
        _selectedTagUuids = saved.tagUuids;
        _planBlockId = saved.planBlockId;
        _habitUuid = saved.habitUuid;
        _challengeTaskId = saved.challengeTaskId;
        _activeFocusSeconds = saved.focusSeconds;
        _remainingSeconds = _settings.focusMinutes * 60;
      });
      await _clearRunStateSilently();
      await _askCompletionAndRecord(
        runState: saved,
        durationSeconds: saved.focusSeconds,
        endMs: saved.targetEndMs,
      );
      await _proceedAfterRecord();
    } finally {
      _isHandlingEnd = false;
    }
  }

  Future<void> _handleBreakEndFromBackground(PomodoroRunState saved) async {
    if (_isHandlingEnd) return;
    _isHandlingEnd = true;
    try {
      NotificationService.cancelReminder(40002);
      TodoItem? boundTodo;
      if (saved.todoUuid != null) {
        boundTodo = _todos.cast<TodoItem?>().firstWhere(
          (t) => t?.id == saved.todoUuid,
          orElse: () => null,
        );
        if (boundTodo == null &&
            saved.todoTitle != null &&
            saved.todoTitle!.isNotEmpty) {
          boundTodo = TodoItem(
            id: saved.todoUuid!,
            title: saved.todoTitle!,
            isDone: false,
            createdAt: 0,
          );
        }
      }
      await _persistIdleBoundTodo(boundTodo, tagUuids: saved.tagUuids);
      await _clearRunStateSilently();
      if (mounted) {
        _mutateState(() {
          _phase = PomodoroPhase.idle;
          _boundTodo = boundTodo;
          _selectedTagUuids = saved.tagUuids;
          _currentCycle = saved.currentCycle + 1;
          _remainingSeconds = saved.focusSeconds;
        });
        widget.onPhaseChanged(_phase);
      }
    } finally {
      _isHandlingEnd = false;
    }
  }

  void _pushPomodoroNotification({
    int? overrideRemaining,
    String alertKey = '',
  }) {
    final remaining = overrideRemaining ?? _remainingSeconds;
    final isRemoteWatching = _phase == PomodoroPhase.remoteWatching;
    final isCountUp = isRemoteWatching
        ? _remoteState?.mode == 1
        : _phase == PomodoroPhase.focusing &&
              _settings.mode == TimerMode.countUp;
    final timerAnchorMs = _isPaused
        ? null
        : isCountUp
        ? (isRemoteWatching
              ? _sessionStartMs
              : _sessionStartMs + _accumulatedMs)
        : _targetEndMs;
    final tagNames = _tags
        .where((t) => _selectedTagUuids.contains(t.uuid))
        .map((t) => t.name)
        .toList();
    NotificationService.updatePomodoroNotification(
      remainingSeconds: remaining,
      phase: _phase == PomodoroPhase.breaking ? 'breaking' : 'focusing',
      todoTitle: _boundTodo?.title,
      currentCycle: _currentCycle,
      totalCycles: _settings.cycles,
      tagNames: tagNames,
      alertKey: alertKey,
      timerMode: isCountUp ? 'countUp' : 'countdown',
      timerAnchorMs: timerAnchorMs,
      isPaused: _isPaused,
    );
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = null;
    if (!_shouldRunUiTickers) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
      // debugPrint('[Ticker] Tick fired, _isPaused: $_isPaused, _phase: $_phase');
      if (!mounted) return;
      if (_phase != PomodoroPhase.focusing &&
          _phase != PomodoroPhase.breaking) {
        return;
      }
      if (_isPaused) {
        // debugPrint('[Ticker] Skipping tick because _isPaused is true');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final bool isCountUp =
          _phase == PomodoroPhase.focusing &&
          _settings.mode == TimerMode.countUp;

      // debugPrint(
      //     '[Ticker] About to compute elapsed, _sessionStartMs: $_sessionStartMs, _accumulatedMs: $_accumulatedMs, now: $now');
      if (isCountUp) {
        final elapsed = (((now - _sessionStartMs) - _accumulatedMs) / 1000)
            .floor();
        // debugPrint(
        //     '[Ticker] countUp elapsed: $elapsed, _remainingSeconds before setState: $_remainingSeconds');
        if (_isPaused) {
          // debugPrint('[Ticker] CRITICAL: Ticker tried to update while _isPaused=true. Skipping.');
        } else {
          _remainingSeconds = elapsed;
          _timerTickNotifier.value++;
        }
      } else {
        final remaining = ((_targetEndMs - now) / 1000).ceil();
        if (remaining <= 0) {
          _ticker?.cancel();
          NotificationService.cancelNotification();
          if (_phase == PomodoroPhase.focusing) {
            await _onFocusEnd();
          } else {
            await _onBreakEnd();
          }
        } else {
          _remainingSeconds = remaining;
          _timerTickNotifier.value++;
        }
      }
    });
  }

  void _startPauseTicker() {
    _pauseTicker?.cancel();
    _pauseTicker = null;
    if (!_shouldRunUiTickers) return;
    _pauseTicker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      _pauseElapsedSecs =
          (DateTime.now().millisecondsSinceEpoch - _pauseStartMs) ~/ 1000;
      _timerTickNotifier.value++;
    });
  }

  void _pauseFocus() {
    // debugPrint(
    //     '[Pause] _pauseFocus called, current _isPaused: $_isPaused, phase: $_phase');
    if (_phase != PomodoroPhase.focusing || _isPaused) {
      // debugPrint('[Pause] Early return, condition failed');
      return;
    }
    // 暂停入口统一给出震动提示；不阻塞计时状态切换。
    unawaited(StrictFocusHapticService.notifyFocusPaused());
    // debugPrint('[Pause] About to cancel ticker');
    _ticker?.cancel();
    // debugPrint(
    //     '[Pause] Ticker cancelled, setting _pausedAtMs and _pauseStartMs');
    _pausedAtMs = DateTime.now().millisecondsSinceEpoch;
    _pauseStartMs = DateTime.now().millisecondsSinceEpoch;
    _pauseIntervals.add(PauseInterval(startMs: _pausedAtMs));

    if (_settings.mode == TimerMode.countUp) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final elapsed = ((now - _sessionStartMs) - _accumulatedMs);
      // debugPrint('[Pause] countUp mode: elapsed=$elapsed');
      _targetEndMs = _sessionStartMs + elapsed;
    }

    // debugPrint('[Pause] About to setState, _isPaused will be set to true');
    _mutateState(() {
      _isPaused = true;
    });
    // Do not leave the old countdown alarm armed while the focus is paused;
    // it could otherwise fire and end the DND rule for a still-running run.
    unawaited(NotificationService.cancelReminder(40001));
    unawaited(
      _setFocusDoNotDisturb(
        _settings.doNotDisturbDuringFocus,
        sessionUuid: _currentSessionUuid,
      ),
    );
    _startPauseTicker();
    // debugPrint(
    //     '[Pause] LOCKED. _pausedAtMs: $_pausedAtMs, _accumulatedMs: $_accumulatedMs');
    // debugPrint('[Pause] After setState, calling notifications');
    _pushPomodoroNotification();
    _showLocalFloat();
    PomodoroService.saveRunState(_buildCurrentRunState());
    _syncService.sendPauseSignal(
      sessionUuid: _currentSessionUuid,
      pausedAtMs: _pausedAtMs,
      accumulatedMs: _accumulatedMs,
      pauseStartMs: _pauseStartMs,
      doNotDisturb: _settings.doNotDisturbDuringFocus,
    );
  }

  Future<void> _resumeFocus() async {
    // 恢复计时也属于“开始计时”，使用开始提示。
    await StrictFocusHapticService.notifyFocusStarted();
    final now = DateTime.now().millisecondsSinceEpoch;
    // debugPrint('[Resume] _resumeFocus called');
    if (_pausedAtMs > 0) {
      final pauseDuration = now - _pausedAtMs;
      _accumulatedMs += pauseDuration;
      if (_pauseIntervals.isNotEmpty && _pauseIntervals.last.isOngoing) {
        _pauseIntervals.last.endMs = now;
      }
      // debugPrint(
      //     '[Resume] UPDATED. pauseDuration: $pauseDuration, new _accumulatedMs: $_accumulatedMs');

      // 如果是倒计时模式, 需要推后结束时间
      if (_settings.mode != TimerMode.countUp) {
        _targetEndMs += pauseDuration;
        // 重新调度通知
        _scheduleReminders(
          _targetEndMs,
          _phase,
          _boundTodo?.title,
          _currentCycle,
          _settings.cycles,
          sessionUuid: _currentSessionUuid,
        );
      }
    }

    await _setFocusDoNotDisturb(
      _settings.doNotDisturbDuringFocus,
      sessionUuid: _currentSessionUuid,
      untilMs: _settings.mode == TimerMode.countdown ? _targetEndMs : null,
    );

    // debugPrint('[Resume] Settings _isPaused=false and starting ticker');
    _mutateState(() {
      _isPaused = false;
      _pausedAtMs = 0;
      _pauseStartMs = 0;
      _pauseElapsedSecs = 0;
    });
    _pauseTicker?.cancel();
    _startTicker();
    _pushPomodoroNotification();
    _showLocalFloat();
    _syncService.sendResumeSignal(
      sessionUuid: _currentSessionUuid,
      pausedAtMs: 0,
      accumulatedMs: _accumulatedMs,
      pauseStartMs: 0,
      targetEndMs: _targetEndMs,
      mode: _settings.mode == TimerMode.countUp ? 1 : 0,
      todoUuid: _boundTodo?.id,
      todoTitle: _boundTodo?.title,
      note: _currentNote.isNotEmpty ? _currentNote : null,
      doNotDisturb: _settings.doNotDisturbDuringFocus,
    );
    await PomodoroService.saveRunState(_buildCurrentRunState());
  }

  void _finalizeOngoingPause(int endMs) {
    if (!_isPaused || _pausedAtMs <= 0) {
      if (_pauseIntervals.isNotEmpty && _pauseIntervals.last.isOngoing) {
        _pauseIntervals.last.endMs = endMs;
      }
      return;
    }

    final pauseDuration = endMs - _pausedAtMs;
    if (pauseDuration > 0) {
      _accumulatedMs += pauseDuration;
    }

    if (_pauseIntervals.isNotEmpty && _pauseIntervals.last.isOngoing) {
      _pauseIntervals.last.endMs = endMs;
    } else {
      _pauseIntervals.add(PauseInterval(startMs: _pausedAtMs, endMs: endMs));
    }

    _isPaused = false;
    _pausedAtMs = 0;
    _pauseStartMs = 0;
    _pauseElapsedSecs = 0;
  }

  void _showPauseDialog() {
    _pauseFocus();
    showAppDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('⏸️ 已暂停'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _boundTodo != null ? '正在专注: "${_boundTodo!.title}"' : '自由专注中',
                ),
                const SizedBox(height: 12),
                Text(
                  _settings.mode == TimerMode.countUp
                      ? '已累计专注: ${formatDurationChinese(_remainingSeconds)}'
                      : '还需持续专注: ${formatDurationChinese(_remainingSeconds)}',
                ),
                const SizedBox(height: 8),
                _PauseTimerText(
                  pauseStartMs: _pauseStartMs,
                  tickListenable: _timerTickNotifier,
                ),
                if (_pauseIntervals.length > 1) ...[
                  const SizedBox(height: 8),
                  Text(
                    '历史暂停 ${_pauseIntervals.length - 1} 次，累计 ${formatDurationChinese((_accumulatedMs / 1000).round())}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _resumeFocus();
                },
                child: const Text('继续'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade400,
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _showPauseEndChoiceDialog();
                },
                child: const Text('结束专注'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showPauseEndChoiceDialog() {
    showAppDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('结束专注'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_boundTodo != null ? '正在专注: "${_boundTodo!.title}"' : '自由专注中'),
            const SizedBox(height: 12),
            Text(
              '已累计专注: ${formatDurationChinese(PomodoroRunState.computeActualSeconds(_sessionStartMs, _accumulatedMs, endMs: _pausedAtMs > 0 ? _pausedAtMs : DateTime.now().millisecondsSinceEpoch))}',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            const Text('请选择结束方式：'),
          ],
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _abandonFocus(true);
            },
            child: const Text('放弃专注'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _finishEarly();
            },
            child: const Text('提前结束'),
          ),
        ],
      ),
    );
  }

  Future<void> _startFocus() async {
    if (_isStrictFreeFocus) {
      await _beginStrictWaiting();
      return;
    }
    if (_normalFocusStartInFlight) return;
    _normalFocusStartInFlight = true;
    try {
      await _startFocusNow();
    } finally {
      _normalFocusStartInFlight = false;
    }
  }

  Future<void> _startFocusNow() async {
    final startupStopwatch = Stopwatch()..start();
    unawaited(_notifyFocusStartHaptic());

    if (_phase == PomodoroPhase.remoteWatching) {
      _stopRemoteTicker();
      final prefs = await SharedPreferences.getInstance();
      final savedUuid = prefs.getString(_keyBoundTodoUuid);
      final savedTitle = prefs.getString(_keyBoundTodoTitle);
      final savedTagsRaw = prefs.getString(_keySelectedTagUuids);
      _selectedTagUuids = savedTagsRaw != null && savedTagsRaw.isNotEmpty
          ? savedTagsRaw.split(',').where((s) => s.isNotEmpty).toList()
          : [];
      TodoItem? localTodo;
      if (savedUuid != null && savedUuid.isNotEmpty) {
        localTodo = _todos.cast<TodoItem?>().firstWhere(
          (t) => t?.id == savedUuid,
          orElse: () => null,
        );
        if (localTodo == null && savedTitle != null && savedTitle.isNotEmpty) {
          localTodo = TodoItem(
            id: savedUuid,
            title: savedTitle,
            isDone: false,
            createdAt: 0,
          );
        }
      }
      _boundTodo = localTodo;
      _remoteState = null;
    }

    _isPaused = false;
    _pausedAtMs = 0;
    _accumulatedMs = 0;
    _pauseIntervals.clear();

    _suppressRunStateEvents = true;
    final PomodoroStartResult startResult;
    (TodoPlanBlock, TodoPlanStatus)? planStatusReceipt;
    try {
      planStatusReceipt = await _markPlanBlockFocusing();
      startResult = await PomodoroControlService.startFocus(
        settings: _settings,
        boundTodo: _boundTodo,
        tagUuids: _selectedTagUuids,
        currentCycle: _currentCycle,
        durationMinutes: _preparedFocusMinutes,
        planBlockId: _planBlockId,
        habitUuid: _habitUuid,
        challengeTaskId: _challengeTaskId,
        deviceId: _deviceId,
        note: _currentNote.isNotEmpty ? _currentNote : null,
        updateFloat: false,
        deferSideEffects: true,
      );
    } catch (error) {
      await _rollbackPlanBlockStatus(planStatusReceipt);
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text('启动专注失败: $error')),
        );
      }
      return;
    } finally {
      _suppressRunStateEvents = false;
    }
    if (!mounted) return;
    final started = startResult.state;
    _currentSessionUuid = started.sessionUuid;
    _planBlockId = started.planBlockId;
    _activeFocusSeconds = started.focusSeconds;
    _preparedFocusMinutes = null;
    _mutateState(() {
      _phase = PomodoroPhase.focusing;
      _targetEndMs = started.targetEndMs;
      _remainingSeconds = 0;
      _sessionStartMs = started.sessionStartMs;
      _remoteState = null;
    });
    startupStopwatch.stop();
    if (kDebugMode) {
      debugPrint(
        '[PomodoroStart] tap_to_active_state '
        '${startupStopwatch.elapsedMilliseconds}ms',
      );
    }
    _stopRemoteTicker();
    widget.onPhaseChanged(_phase);
    if (_isStrictFreeFocus) {
      // 工作台只负责展示，传感器监听交给跨页面协调器。
      await StrictFocusSessionCoordinator.instance.startMonitoring(
        requireInitialFaceUp: false,
      );
    }
    _startTicker();
    _showLocalFloat();

    _persistIdleBoundTodo(null);
  }

  Future<void> _notifyFocusStartHaptic() async {
    final stopwatch = Stopwatch()..start();
    await StrictFocusHapticService.notifyFocusStarted();
    stopwatch.stop();
    if (kDebugMode) {
      debugPrint('[PomodoroStart] haptic ${stopwatch.elapsedMilliseconds}ms');
    }
  }

  Future<void> _switchTask(TodoItem? newTodo) async {
    if (_phase != PomodoroPhase.focusing || _isHandlingEnd) return;
    final oldTodo = _boundTodo;
    final oldTagUuids = List<String>.from(_selectedTagUuids);
    final oldPlanBlockId = _planBlockId;
    final recommendedTagUuids = newTodo != null
        ? await _recommendedTagUuidsForTodo(newTodo)
        : <String>[];
    if (!mounted || _phase != PomodoroPhase.focusing || _isHandlingEnd) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final oldSessionStartMs = _sessionStartMs;
    final wasPaused = _isPaused;
    final pauseDurationMs = wasPaused && _pausedAtMs > 0
        ? now - _pausedAtMs
        : 0;
    if (wasPaused) {
      _finalizeOngoingPause(now);
      _pauseTicker?.cancel();
      _pauseTicker = null;
    }
    final actualSeconds = PomodoroRunState.computeActualSeconds(
      oldSessionStartMs,
      _accumulatedMs,
      endMs: now,
    );
    final isCountUp = _settings.mode == TimerMode.countUp;

    _mutateState(() {
      _boundTodo = newTodo;
      _planBlockId = null;
      _preparedFocusMinutes = null;
      if (wasPaused && !isCountUp && pauseDurationMs > 0) {
        _targetEndMs += pauseDurationMs;
      }
      if (recommendedTagUuids.isNotEmpty) {
        _selectedTagUuids = recommendedTagUuids;
      }
      _sessionStartMs = now;
    });
    _pushPomodoroNotification();
    _showLocalFloat(); // 🚀 关键：切换任务后刷新悬浮窗标题

    if (actualSeconds > 5) {
      final pauseSecs = (_accumulatedMs / 1000).round();
      final intervals = List<PauseInterval>.from(_pauseIntervals);
      await PomodoroService.addRecord(
        PomodoroRecord(
          uuid: _currentSessionUuid,
          todoUuid: oldTodo?.id,
          todoTitle: oldTodo?.title,
          tagUuids: oldTagUuids,
          startTime: oldSessionStartMs,
          endTime: now,
          plannedDuration: isCountUp
              ? 0
              : (_activeFocusSeconds ?? _settings.focusMinutes * 60),
          actualDuration: actualSeconds,
          status: PomodoroRecordStatus.switched,
          deviceId: _deviceId.isNotEmpty ? _deviceId : null,
          planBlockId: oldPlanBlockId,
          note: _currentNote.isNotEmpty ? _currentNote : null,
          totalPauseSeconds: pauseSecs,
          pauseIntervals: intervals,
        ),
      );
      widget.onRecordAdded?.call();
    }

    _currentNote = '';
    _currentSessionUuid = const Uuid().v4();
    _pauseIntervals.clear();
    _accumulatedMs = 0;
    _isPaused = false;
    _pausedAtMs = 0;
    _pauseStartMs = 0;
    final isCountUpNow = _settings.mode == TimerMode.countUp;
    if (isCountUpNow) {
      _mutateState(() => _remainingSeconds = 0); // 🚀 本端也显式清零
    }
    await _setFocusDoNotDisturb(
      _settings.doNotDisturbDuringFocus,
      sessionUuid: _currentSessionUuid,
      untilMs: isCountUpNow ? null : _targetEndMs,
    );
    await _saveCurrentRunState();
    if (!isCountUpNow) {
      _scheduleReminders(
        _targetEndMs,
        PomodoroPhase.focusing,
        _boundTodo?.title,
        _currentCycle,
        _settings.cycles,
        sessionUuid: _currentSessionUuid,
      );
    }
    _startTicker();

    _syncService.sendSwitchSignal(
      todoUuid: newTodo?.id,
      todoTitle: newTodo?.title,
      sessionUuid: _currentSessionUuid,
      note: _currentNote.isNotEmpty ? _currentNote : null,
    );
    if (recommendedTagUuids.isNotEmpty) {
      final tagNames = _tags
          .where((t) => _selectedTagUuids.contains(t.uuid))
          .map((t) => t.name)
          .toList();
      _syncService.sendUpdateTagsSignal(tagNames);
    }
    if (mounted) {
      AppSnackBars.showSnackBar(
        context,
        SnackBar(
          content: Text(
            newTodo != null ? '已切换至: ${newTodo.title}' : '已切换为自由专注',
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _finishEarly({bool finishWholeSession = false}) async {
    if (_isHandlingEnd) return;
    if (_phase != PomodoroPhase.focusing) return;
    _isHandlingEnd = true;
    try {
      await _stopStrictSensorMonitoring();
      _ticker?.cancel();
      _pauseTicker?.cancel();
      NotificationService.cancelNotification();
      NotificationService.cancelReminder(40001);
      NotificationService.cancelReminder(40002);
      final now = DateTime.now().millisecondsSinceEpoch;

      _finalizeOngoingPause(now);

      final actualSeconds = PomodoroRunState.computeActualSeconds(
        _sessionStartMs,
        _accumulatedMs,
        endMs: now,
      );
      _isPaused = false;
      _pausedAtMs = 0;
      _pauseStartMs = 0;
      final isCountUp = _settings.mode == TimerMode.countUp;

      await _persistIdleBoundTodo(_boundTodo);
      await _clearRunStateSilently();
      _syncService.sendStopSignal(
        todoUuid: _boundTodo?.id,
        sessionUuid: _currentSessionUuid,
      );
      // Notify island to switch to idle immediately.
      await _updateFloatSafely(
        FloatWindowService.update(endMs: 0, isLocal: true),
      );

      await _askCompletionAndRecord(
        runState: _buildCurrentRunState(),
        durationSeconds: actualSeconds,
        endMs: now,
        isCountUp: isCountUp,
      );
      _accumulatedMs = 0;
      _pauseIntervals.clear();
      NotificationService.sendPomodoroEndAlert(
        alertKey: 'pomo_end_$now',
        todoTitle: _boundTodo?.title,
        isBreak: false,
      );
      await _proceedAfterRecord(continueWithBreak: !finishWholeSession);
    } finally {
      _isHandlingEnd = false;
    }
  }

  Future<void> _onFocusEnd() async {
    if (_isHandlingEnd) return;
    _isHandlingEnd = true;
    try {
      await _stopStrictSensorMonitoring();
      _pauseTicker?.cancel();
      NotificationService.cancelReminder(40001);
      final now = DateTime.now().millisecondsSinceEpoch;
      final isCountUp = _settings.mode == TimerMode.countUp;

      _finalizeOngoingPause(now);

      await _persistIdleBoundTodo(_boundTodo);
      await _clearRunStateSilently();
      _syncService.sendStopSignal(
        todoUuid: _boundTodo?.id,
        sessionUuid: _currentSessionUuid,
      );
      // Notify island to switch to idle immediately.
      await _updateFloatSafely(
        FloatWindowService.update(endMs: 0, isLocal: true),
      );
      await _askCompletionAndRecord(
        runState: _buildCurrentRunState(),
        durationSeconds: isCountUp
            ? PomodoroRunState.computeActualSeconds(
                _sessionStartMs,
                _accumulatedMs,
                endMs: now,
              )
            : (_activeFocusSeconds ?? _settings.focusMinutes * 60),
        endMs: now,
        isCountUp: isCountUp,
      );
      NotificationService.sendPomodoroEndAlert(
        alertKey: 'pomo_end_$now',
        todoTitle: _boundTodo?.title,
        isBreak: false,
      );
      await _proceedAfterRecord();
    } finally {
      _isHandlingEnd = false;
    }
  }

  Future<bool> _askCompletionAndRecord({
    required PomodoroRunState runState,
    required int durationSeconds,
    required int endMs,
    bool isCountUp = false,
  }) async {
    if (!mounted) return false;

    int editedDuration = durationSeconds;
    final durationCtrl = TextEditingController(
      text: (durationSeconds ~/ 60).toString(),
    );

    final targetTitle =
        _boundTodo?.title ??
        (_targetLabel != null && _targetLabel!.trim().isNotEmpty
            ? _targetLabel!.trim()
            : null);

    final completed = await showAppDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(isCountUp ? '📈 记录专注' : '🍅 专注完成！'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              targetTitle != null
                  ? '"$targetTitle" 是否已完成？'
                  : '专注时段已结束，该任务是否已完成？',
            ),
            if (isCountUp) ...[
              const SizedBox(height: 20),
              const Text(
                '修改计时时长 (分钟):',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: durationCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (isCountUp) {
                final mins =
                    int.tryParse(durationCtrl.text) ?? (durationSeconds ~/ 60);
                editedDuration = mins * 60;
              }
              Navigator.pop(ctx, false);
            },
            child: const Text('未完成'),
          ),
          FilledButton(
            onPressed: () {
              if (isCountUp) {
                final mins =
                    int.tryParse(durationCtrl.text) ?? (durationSeconds ~/ 60);
                editedDuration = mins * 60;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('已完成 ✓'),
          ),
        ],
      ),
    );
    final record = PomodoroRecord.fromRunState(
      state: runState,
      status: PomodoroRecordStatus.completed,
      endMs: endMs,
      actualDuration: editedDuration,
      deviceId: _deviceId.isNotEmpty ? _deviceId : null,
    );
    await PomodoroService.addRecord(record);
    widget.onRecordAdded?.call();
    if (completed == true && _boundTodo != null && _boundTodo!.id.isNotEmpty) {
      StorageService.getTodos(widget.username).then((allTodos) async {
        final idx = allTodos.indexWhere((t) => t.id == _boundTodo!.id);
        if (idx != -1) {
          allTodos[idx].isDone = true;
          allTodos[idx].markAsChanged();
          await StorageService.saveTodos(widget.username, allTodos);
        }
      });
      final localIdx = _todos.indexWhere((t) => t.id == _boundTodo!.id);
      if (localIdx != -1 && mounted) {
        _mutateState(() => _todos[localIdx].isDone = true);
      }
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(
            content: Text('✅ "${_boundTodo!.title}" 已标记完成'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    final autoCheckInMessages =
        await HabitFocusCompletionService.onFocusRecorded(
          username: widget.username,
          record: record,
          explicitHabitUuid: runState.habitUuid ?? _habitUuid,
          explicitChallengeTaskId: runState.challengeTaskId ?? _challengeTaskId,
          userConfirmedCompleted: completed == true,
        );
    if (autoCheckInMessages.isNotEmpty && mounted) {
      AppSnackBars.showSnackBar(
        context,
        SnackBar(
          content: Text(autoCheckInMessages.join('\n')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return completed ?? false;
  }

  Future<void> _proceedAfterRecord({bool continueWithBreak = true}) async {
    if (!mounted) return;
    final isCountUp = _settings.mode == TimerMode.countUp;
    if (PomodoroWorkbenchState.shouldStartBreakAfterCompletion(
      isCountUp: isCountUp,
      currentCycle: _currentCycle,
      cycles: _settings.cycles,
      continueWithBreak: continueWithBreak,
    )) {
      await _startBreak();
    } else {
      _mutateState(() {
        _phase = PomodoroPhase.finished;
        _currentCycle = 1;
        _remainingSeconds = isCountUp ? 0 : _settings.focusMinutes * 60;
        _planBlockId = null;
        _activeFocusSeconds = null;
      });
      _syncService.setLocalFocusing(false);
      widget.onPhaseChanged(_phase);
      await _persistIdleBoundTodo(_boundTodo);
      _showLocalFloat();
    }
  }

  Future<void> _startBreak() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final end = now + _settings.breakMinutes * 60 * 1000;
    _mutateState(() {
      _phase = PomodoroPhase.breaking;
      _targetEndMs = end;
      _remainingSeconds = _settings.breakMinutes * 60;
    });
    _syncService.setLocalFocusing(true);
    widget.onPhaseChanged(_phase);
    _pushPomodoroNotification();
    _showLocalFloat();
    _startTicker();
    NotificationService.cancelReminder(40001);
    _scheduleReminders(
      end,
      PomodoroPhase.breaking,
      _boundTodo?.title,
      _currentCycle,
      _settings.cycles,
      sessionUuid: _currentSessionUuid,
    );
    await _saveCurrentRunState();
  }

  Future<void> _onBreakEnd() async {
    if (_isHandlingEnd) return;
    _isHandlingEnd = true;
    try {
      NotificationService.cancelReminder(40002);
      await _setFocusDoNotDisturb(false, sessionUuid: _currentSessionUuid);
      NotificationService.sendPomodoroEndAlert(
        alertKey: 'pomo_end_$_targetEndMs',
        todoTitle: _boundTodo?.title,
        isBreak: true,
      );
      _mutateState(() {
        _phase = PomodoroPhase.idle;
        _currentCycle += 1;
        _remainingSeconds = _settings.mode == TimerMode.countUp
            ? 0
            : _settings.focusMinutes * 60;
        _planBlockId = null;
        _activeFocusSeconds = null;
      });
      _syncService.setLocalFocusing(false);
      widget.onPhaseChanged(_phase);
      await _clearRunStateSilently();
      await _persistIdleBoundTodo(_boundTodo);
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(
            content: Text('☕ 休息结束，准备开始下一轮！'),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      _isHandlingEnd = false;
    }
  }

  Future<void> _abandonFocus([bool skipDialog = false]) async {
    if (_isHandlingEnd) return;
    _isHandlingEnd = true;
    try {
      _ticker?.cancel();
      _ticker = null;
      _pauseTicker?.cancel();
      bool confirm = skipDialog;
      if (!skipDialog) {
        final res = await showAppDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('放弃本次专注？'),
            content: const Text('本次专注会记录为放弃，用于统计中断率。'),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('继续专注'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade400,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('放弃'),
              ),
            ],
          ),
        );
        confirm = res == true;
      }
      if (confirm) {
        await _stopStrictSensorMonitoring();
        final now = DateTime.now().millisecondsSinceEpoch;

        _finalizeOngoingPause(now);

        final actualSeconds = PomodoroRunState.computeActualSeconds(
          _sessionStartMs,
          _accumulatedMs,
          endMs: now,
        );
        final isCountUpMode = _settings.mode == TimerMode.countUp;
        if (actualSeconds > 5) {
          await PomodoroService.addRecord(
            PomodoroRecord.fromRunState(
              state: _buildCurrentRunState(),
              status: PomodoroRecordStatus.interrupted,
              endMs: now,
              deviceId: _deviceId.isNotEmpty ? _deviceId : null,
            ),
          );
          widget.onRecordAdded?.call();
        }
        NotificationService.cancelNotification();
        NotificationService.cancelReminder(40001);
        NotificationService.cancelReminder(40002);
        _syncService.sendStopSignal(
          todoUuid: _boundTodo?.id,
          sessionUuid: _currentSessionUuid,
        );
        // Notify island to switch to idle immediately.
        await _updateFloatSafely(
          FloatWindowService.update(endMs: 0, isLocal: true),
        );
        _mutateState(() {
          _phase = PomodoroPhase.idle;
          _currentCycle = 1;
          _remainingSeconds = isCountUpMode ? 0 : _settings.focusMinutes * 60;
          _planBlockId = null;
          _activeFocusSeconds = null;
        });
        _syncService.setLocalFocusing(false);
        widget.onPhaseChanged(_phase);
        _persistIdleBoundTodo(_boundTodo);
        await _clearRunStateSilently();
      } else {
        _startTicker();
      }
    } finally {
      _isHandlingEnd = false;
    }
  }
}
