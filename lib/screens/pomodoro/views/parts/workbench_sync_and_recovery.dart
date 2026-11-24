part of '../workbench_view.dart';

extension _PomodoroWorkbenchSyncExt on PomodoroWorkbenchState {
  bool get _isStrictFreeFocus =>
      _settings.mode == TimerMode.countUp && _settings.strictFreeFocus;

  void _stopUiTickers() {
    _ticker?.cancel();
    _ticker = null;
    _pauseTicker?.cancel();
    _pauseTicker = null;
    _remoteTicker?.cancel();
    _remoteTicker = null;
  }

  Future<void> _resumeUiTickers() async {
    if (!_shouldRunUiTickers || _initializing) return;

    if (_phase == PomodoroPhase.remoteWatching) {
      final remote = _remoteState;
      if (remote != null) {
        _startRemoteTicker(
          remote.mode == 1 ? 0 : (remote.targetEndMs ?? _targetEndMs),
          remote.mode == 1,
        );
      }
      return;
    }

    await _recoverFromBackground();
    if (!_shouldRunUiTickers) return;
    if ((_phase == PomodoroPhase.focusing ||
            _phase == PomodoroPhase.breaking) &&
        _isPaused) {
      _pauseElapsedSecs =
          (DateTime.now().millisecondsSinceEpoch - _pauseStartMs) ~/ 1000;
      _timerTickNotifier.value++;
      _startPauseTicker();
    }
  }

  Future<void> _beginStrictWaiting() async {
    if (_strictWaitingForFlip || _strictStartInFlight) return;
    if (!AppPlatform.isAndroid && !AppPlatform.isIOS) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(
            content: Text('严格自由专注仅支持 Android 和 iOS 手机端'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    _mutateState(() {
      _strictWaitingForFlip = true;
      _strictSensorState = StrictFocusSensorState.waitingForFaceUp;
      _remainingSeconds = 0;
    });
    _strictUnavailableNoticeShown = false;
    _timerTickNotifier.value++;
    _strictStartInFlight = true;
    _suppressRunStateEvents = true;
    PomodoroStartResult? pending;
    (TodoPlanBlock, TodoPlanStatus)? planStatusReceipt;
    try {
      planStatusReceipt = await _markPlanBlockFocusing();
      pending = await PomodoroControlService.startFocus(
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
        notify: false,
        updateFloat: false,
        sync: false,
        syncBand: false,
        startPaused: true,
        strictWaitingForFlip: true,
      );
      _strictWaitPlanStatusReceipt = planStatusReceipt;
    } catch (_) {
      _strictWaitPlanStatusReceipt = null;
      await _rollbackPlanBlockStatus(planStatusReceipt);
      if (mounted) {
        _mutateState(() {
          _strictWaitingForFlip = false;
          _remainingSeconds = 0;
        });
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(
            content: Text('严格模式启动失败，请重试'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      await PomodoroService.clearRunState();
      PomodoroSyncService.instance.setLocalFocusing(false);
      return;
    } finally {
      _suppressRunStateEvents = false;
      _strictStartInFlight = false;
    }

    final waitingState = pending.state;
    _currentSessionUuid = waitingState.sessionUuid;
    _planBlockId = waitingState.planBlockId;
    _activeFocusSeconds = waitingState.focusSeconds;
    if (mounted) {
      _mutateState(() {
        // Keep the workbench in its idle layout while the persisted session is
        // only waiting for the first flip. The coordinator still owns a
        // focusing run state so the wait survives leaving this route.
        _phase = PomodoroPhase.idle;
        _targetEndMs = waitingState.targetEndMs;
        _remainingSeconds = 0;
        _sessionStartMs = waitingState.sessionStartMs;
        _isPaused = true;
        _pausedAtMs = waitingState.pausedAtMs;
        _pauseStartMs = waitingState.pauseStartMs;
        _accumulatedMs = waitingState.accumulatedMs;
        _pauseIntervals
          ..clear()
          ..addAll(waitingState.pauseIntervals);
      });
      _startPauseTicker();
      widget.onPhaseChanged(_phase);
    }

    // The coordinator owns this subscription, so the waiting state survives
    // popping the workbench route or switching back to the app home page.
    await StrictFocusSessionCoordinator.instance.startMonitoring(
      requireInitialFaceUp: true,
    );
  }

  Future<void> _cancelStrictWaiting() async {
    if (_strictStartInFlight) return;
    final saved = await PomodoroService.loadRunState();
    if (saved != null && !saved.strictWaitingForFlip) {
      _strictWaitPlanStatusReceipt = null;
      // A sensor event may have started the session while the cancel action
      // was waiting for SharedPreferences. Rehydrate the active state instead
      // of leaving this page in its idle waiting layout.
      await _recoverState(saved);
      return;
    }
    _strictWaitingForFlip = false;
    _strictStartInFlight = false;
    _pauseTicker?.cancel();
    _pauseTicker = null;
    await StrictFocusSessionCoordinator.instance.stopMonitoring();
    if (saved?.strictWaitingForFlip == true) {
      await _clearRunStateSilently();
      PomodoroSyncService.instance.setLocalFocusing(false);
      await NotificationService.cancelNotification();
      await FloatWindowService.update(endMs: 0, isLocal: true);
    }
    final planStatusReceipt = _strictWaitPlanStatusReceipt;
    _strictWaitPlanStatusReceipt = null;
    await _rollbackPlanBlockStatus(planStatusReceipt);
    if (!mounted) return;
    _mutateState(() {
      _phase = PomodoroPhase.idle;
      _isPaused = false;
      _pausedAtMs = 0;
      _pauseStartMs = 0;
      _accumulatedMs = 0;
      _activeFocusSeconds = null;
      _pauseIntervals.clear();
      _strictSensorState = StrictFocusSensorState.waitingForFaceUp;
      _remainingSeconds = 0;
    });
    widget.onPhaseChanged(_phase);
    _timerTickNotifier.value++;
  }

  Future<void> _stopStrictSensorMonitoring() async {
    _strictWaitingForFlip = false;
    _strictStartInFlight = false;
    await StrictFocusSessionCoordinator.instance.stopMonitoring();
  }

  void _handleStrictSensorEvent(StrictFocusSensorEvent event) {
    if (!mounted) return;
    final wasUnavailable =
        _strictSensorState == StrictFocusSensorState.unavailable;
    _strictSensorState = event.state;
    _timerTickNotifier.value++;

    if (event.state == StrictFocusSensorState.unavailable &&
        !wasUnavailable &&
        !_strictUnavailableNoticeShown &&
        (_strictWaitingForFlip ||
            (_isStrictFreeFocus &&
                _phase == PomodoroPhase.focusing &&
                _isPaused))) {
      _strictUnavailableNoticeShown = true;
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(
          content: Text('运动传感器不可用，正在自动重试'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (event.state == StrictFocusSensorState.waitingForFlip ||
        event.state == StrictFocusSensorState.faceDown ||
        event.state == StrictFocusSensorState.notFaceDown) {
      _strictUnavailableNoticeShown = false;
    }
  }

  Future<void> _init() async {
    if (_isInitProcessing) {
      // debugPrint(
      //     '[PomodoroWorkbench] _init already in progress, skipping redundant call');
      return;
    }
    _isInitProcessing = true;
    final preserveEntryBinding =
        _initialEntryApplied && widget.initialEntry != null;
    final preservedTodo = _boundTodo;
    final preservedTags = List<String>.from(_selectedTagUuids);
    final preservedPlanBlockId = _planBlockId;
    final preservedHabitUuid = _habitUuid;
    final preservedChallengeTaskId = _challengeTaskId;
    final preservedTargetLabel = _targetLabel;
    final preservedFocusMinutes = _preparedFocusMinutes;
    final initStart = DateTime.now();
    // debugPrint(
    //     '[PomodoroWorkbench] _init start: ${initStart.toIso8601String()}');
    Timer? initWatchdog = Timer(const Duration(seconds: 6), () {});

    try {
      final results = await Future.wait([
        PomodoroService.getSettings(),
        PomodoroService.getTags(),
        StorageService.getDeviceId(),
        StorageService.getTodos(widget.username)
            .timeout(const Duration(seconds: 5), onTimeout: () => <TodoItem>[]),
        StorageService.getTodoGroups(
          widget.username,
        ).timeout(const Duration(seconds: 5), onTimeout: () => <TodoGroup>[]),
        PomodoroService.loadRunState().timeout(
          const Duration(seconds: 5),
          onTimeout: () => null,
        ),
      ]);

      // 🚀 核心优化：若当前路由仍处于入场过渡动画中，等待动画完成再触发布局更新，
      // 若已在首页预挂载或懒加载占位已完成，则无需额外等待。
      final routeAnimation = mounted ? ModalRoute.of(context)?.animation : null;
      if (routeAnimation != null && routeAnimation.isAnimating) {
        await Future.delayed(const Duration(milliseconds: 160));
      }

      _settings = results[0] as PomodoroSettings;
      _allTags = results[1] as List<PomodoroTag>;
      _tags = _allTags.where((t) => !t.isArchived).toList();
      _deviceId = results[2] as String;
      unawaited(_refreshSystemDoNotDisturbAccess());

      final todosRaw = results[3] as List<TodoItem>;
      _todos = todosRaw
          .where((t) => !t.isDeleted && !t.isDone && !t.isSkipped)
          .toList();

      final groupsRaw = results[4] as List<TodoGroup>;
      _todoGroups = groupsRaw.where((g) => !g.isDeleted).toList();

      final saved = results[5] as PomodoroRunState?;
      final runIsActive =
          saved != null &&
          saved.phase != PomodoroPhase.idle &&
          saved.phase != PomodoroPhase.finished;

      try {
        final info = await PackageInfo.fromPlatform();
        _appVersion = info.version;
      } catch (e) {
        debugPrint('[PomodoroWorkbench] 读取应用版本失败: $e');
      }

      if (saved != null && saved.phase != PomodoroPhase.idle) {
        try {
          try {
            await _recoverState(saved).timeout(const Duration(seconds: 5));
          } on TimeoutException catch (e) {
            debugPrint('[PomodoroWorkbench] 恢复计时状态超时: $e');
          }
        } catch (e) {
          debugPrint('[PomodoroWorkbench] 恢复计时状态失败: $e');
        }
      } else {
        // A crash can leave the native DND marker behind even when no run
        // state was committed. Clear that stale ownership before restoring
        // the idle workbench.
        unawaited(_setFocusDoNotDisturb(false, force: true));
        try {
          SharedPreferences? prefs;
          try {
            prefs = await SharedPreferences.getInstance().timeout(
              const Duration(seconds: 5),
            );
          } catch (e) {
            debugPrint('[PomodoroWorkbench] 读取本地绑定状态失败: $e');
            prefs = null;
          }
          if (prefs != null) {
            final savedUuid = prefs.getString(_keyBoundTodoUuid);
            final savedTitle = prefs.getString(_keyBoundTodoTitle);
            final savedTagsRaw = prefs.getString(_keySelectedTagUuids);

            final restoredTagUuids =
                savedTagsRaw != null && savedTagsRaw.isNotEmpty
                ? savedTagsRaw.split(',').where((s) => s.isNotEmpty).toList()
                : <String>[];

            TodoItem? restoredTodo;
            if (savedUuid != null && savedUuid.isNotEmpty) {
              restoredTodo = _todos.cast<TodoItem?>().firstWhere(
                (t) => t?.id == savedUuid,
                orElse: () => null,
              );
              if (restoredTodo == null &&
                  savedTitle != null &&
                  savedTitle.isNotEmpty) {
                restoredTodo = TodoItem(
                  id: savedUuid,
                  title: savedTitle,
                  isDone: false,
                  createdAt: 0,
                );
              }
            }
            if (mounted) {
              _mutateState(() {
                _remainingSeconds = _settings.mode == TimerMode.countUp
                    ? 0
                    : _settings.focusMinutes * 60;
                _boundTodo = restoredTodo;
                _selectedTagUuids = restoredTagUuids;
                _planBlockId = null;
                _activeFocusSeconds = null;
                _preparedFocusMinutes = null;
              });
              // 🚀 补擦除逻辑：初始状态为闲置
              _syncService.setLocalFocusing(false);
            }
          }
        } catch (e) {
          debugPrint('[PomodoroWorkbench] 恢复本地绑定信息失败: $e');
        }
      }

      if (preserveEntryBinding && !runIsActive && mounted) {
        _mutateState(() {
          _boundTodo = preservedTodo;
          _selectedTagUuids = preservedTags;
          _planBlockId = preservedPlanBlockId;
          _habitUuid = preservedHabitUuid;
          _challengeTaskId = preservedChallengeTaskId;
          _targetLabel = preservedTargetLabel;
          _preparedFocusMinutes = preservedFocusMinutes;
          _remainingSeconds = _settings.mode == TimerMode.countUp
              ? 0
              : (preservedFocusMinutes ?? _settings.focusMinutes) * 60;
        });
        try {
          await _persistIdleBoundTodo(preservedTodo, tagUuids: preservedTags);
        } catch (_) {
          // Keep the in-memory entry binding if preferences are unavailable.
        }
      }

      if (!_initialEntryApplied) {
        _initialEntryApplied = true;
        if (!runIsActive) await _applyInitialEntry();
      }

      if (mounted) {
        _mutateState(() => _initializing = false);
        // Reveal the recovered phase and collapse the outer header together.
        widget.onPhaseChanged(_phase);
        widget.onReady?.call();
        _showLocalFloat();
      }

      try {
        try {
          await _connectCrossDevice().timeout(const Duration(seconds: 5));
        } on TimeoutException catch (e) {
          debugPrint('[PomodoroWorkbench] 连接跨设备服务超时: $e');
        }
      } catch (e) {
        debugPrint('[PomodoroWorkbench] 连接跨设备服务失败: $e');
      }
    } finally {
      _isInitProcessing = false;
      initWatchdog.cancel();
      final elapsed = DateTime.now().difference(initStart).inMilliseconds;
      debugPrint('[PomodoroWorkbench] 初始化耗时 ${elapsed}ms');
    }
  }

  Future<void> _connectCrossDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final userIdInt = prefs.getInt('current_user_id');
    if (userIdInt == null || _deviceId.isEmpty) return;
    _userId = userIdInt.toString();

    _crossDeviceSub?.cancel();
    _crossDeviceSub = _syncService.onStateChanged
        .asyncMap(_handleCrossDeviceSignal)
        .listen(
          (_) {},
          onError: (Object error) {
            debugPrint('[PomodoroWorkbench] 处理跨端消息失败: $error');
          },
        );

    _connSub?.cancel();
    _connSub = _syncService.onConnectionChanged.listen((state) async {
      if (!mounted) return;
      _mutateState(() {
        _syncConnState = state;
      });
      if (state == SyncConnectionState.connected &&
          (_phase == PomodoroPhase.focusing ||
              _phase == PomodoroPhase.breaking) &&
          _currentSessionUuid.isNotEmpty) {
        _syncService.setLocalFocusing(true);
        final sourceDeviceName = await StorageService.getDeviceFriendlyName();
        if (!mounted ||
            (_phase != PomodoroPhase.focusing &&
                _phase != PomodoroPhase.breaking) ||
            _currentSessionUuid.isEmpty) {
          return;
        }
        final isCountUp = _settings.mode == TimerMode.countUp;
        final plannedFocusSeconds = isCountUp
            ? 0
            : (_activeFocusSeconds ?? _settings.focusMinutes * 60);
        final durationSeconds = _phase == PomodoroPhase.focusing
            ? plannedFocusSeconds
            : _settings.breakMinutes * 60;
        final targetEndMs = isCountUp ? _sessionStartMs : _targetEndMs;
        final tagNames = _tags
            .where((t) => _selectedTagUuids.contains(t.uuid))
            .map((t) => t.name)
            .toList();
        _syncService.sendReconnectSyncSignal(
          sessionUuid: _currentSessionUuid,
          todoUuid: _boundTodo?.id.isNotEmpty == true ? _boundTodo!.id : null,
          todoTitle: _boundTodo?.title,
          planBlockId: _planBlockId,
          durationSeconds: durationSeconds,
          targetEndMs: targetEndMs,
          tagNames: tagNames,
          sourceDeviceName: sourceDeviceName,
          mode: _settings.mode.index,
          currentCycle: _currentCycle,
          totalCycles: _settings.cycles,
          plannedFocusSeconds: plannedFocusSeconds,
          note: _currentNote.isNotEmpty ? _currentNote : null,
          doNotDisturb:
              _phase == PomodoroPhase.focusing &&
              _settings.doNotDisturbDuringFocus &&
              !_strictWaitingForFlip,
          customTimestamp: _sessionStartMs > 0 ? _sessionStartMs : null,
        );
      }
      // debugPrint('[工作台] 同步通道连接状态变更: $state');
    });

    // 🍅 发起端重连后，服务端回推了历史专注状态
    // 若本地已无对应状态，则通知云端清除残留
    if (_staleSyncFocusHandler != null) {
      _syncService.unregisterStaleSyncFocusHandler(_staleSyncFocusHandler!);
    }
    _staleSyncFocusHandler = (state) async {
      // debugPrint('[工作台] 收到服务端回推的残留状态，校验本地...');
      final saved = await PomodoroService.loadRunState();
      if (saved == null ||
          (saved.phase != PomodoroPhase.focusing &&
              saved.phase != PomodoroPhase.breaking)) {
        // debugPrint('[工作台] 本地无运行中的专注，发送 CLEAR_FOCUS 清除云端残留');
        _syncService.sendClearFocusSignal(sessionUuid: state.sessionUuid);
      } else {
        // debugPrint('[工作台] 本地仍有运行中的专注，保留云端状态');
      }
    };
    _syncService.registerStaleSyncFocusHandler(_staleSyncFocusHandler!);

    // 🚀 获取 auth token 用于 WebSocket 鉴权
    final authToken = await StorageService.getAuthToken();

    await _syncService.forceReconnect(
      _userId,
      'flutter_$_deviceId',
      authToken: authToken,
      appVersion: _appVersion,
    );
  }

  Future<void> _handleCrossDeviceSignal(CrossDevicePomodoroState signal) async {
    if (!mounted || _initializing) return;

    final myDeviceId = 'flutter_$_deviceId';
    if (_deviceId.isEmpty ||
        (signal.sourceDevice != null &&
            (signal.sourceDevice == myDeviceId ||
                _syncService.isFromCurrentDevice(signal.sourceDevice)))) {
      return;
    }

    switch (signal.action) {
      case 'UPDATE_AVAILABLE':
        if (!_hasShownUpdate && mounted && signal.manifestData != null) {
          _hasShownUpdate = true;
          final manifest = AppManifest.fromJson(signal.manifestData!);
          PackageInfo packageInfo = await PackageInfo.fromPlatform();
          if (!mounted) return;
          UpdateService.showUpdateDialog(
            context,
            manifest,
            packageInfo.version,
            hasUpdate: true,
          );
        }
        break;

      case 'START':
      case 'SYNC':
      case 'SYNC_FOCUS':
      case 'RECONNECT_SYNC':
        if (_phase == PomodoroPhase.focusing ||
            _phase == PomodoroPhase.breaking ||
            _phase == PomodoroPhase.finished) {
          break;
        }

        final isCountUp = signal.mode == 1;
        final endMs = signal.targetEndMs ?? 0;
        final isPaused = signal.isPaused == true;
        final acc = signal.accumulatedMs ?? 0;
        final timestamp =
            signal.timestamp ?? DateTime.now().millisecondsSinceEpoch;
        int rem = 0;

        final nowMs = DateTime.now().millisecondsSinceEpoch;
        int localTargetEnd = 0;
        int localSessionStart = 0;

        if (signal.serverElapsedMs != null) {
          // 🚀 核心修复：彻底解决跨端时钟偏移。将服务端的“纯专注时长”转化为“本地结束/开始点”
          if (isCountUp) {
            localSessionStart = nowMs - signal.serverElapsedMs!;
            rem = signal.serverElapsedMs! ~/ 1000;
          } else {
            final plannedSecs =
                signal.duration ?? (_settings.focusMinutes * 60);
            rem = plannedSecs - (signal.serverElapsedMs! ~/ 1000);
            if (rem < 0) rem = 0;
            localTargetEnd = nowMs + (rem * 1000);
          }
        } else {
          // 降级逻辑
          if (isCountUp) {
            final referenceMs = isPaused
                ? (signal.pausedAtMs ?? timestamp)
                : nowMs;
            rem = ((referenceMs - timestamp - acc) / 1000).floor();
            localSessionStart = nowMs - (rem * 1000);
          } else {
            final referenceMs = isPaused ? (signal.pausedAtMs ?? endMs) : nowMs;
            rem = ((endMs - referenceMs) / 1000).ceil();
            localTargetEnd = nowMs + (rem * 1000);
          }
        }

        final todoTitle = signal.todoTitle;
        final remoteTodo = todoTitle != null && todoTitle.isNotEmpty
            ? TodoItem(
                id: signal.todoUuid ?? '',
                title: todoTitle,
                isDone: false,
                createdAt: 0,
              )
            : null;

        await _setFocusDoNotDisturb(
          signal.doNotDisturb == true,
          sessionUuid: signal.sessionUuid,
          untilMs: isPaused ? null : (isCountUp ? null : localTargetEnd),
        );
        if (!mounted) return;
        _mutateState(() {
          _phase = PomodoroPhase.remoteWatching;
          _targetEndMs = isCountUp ? 0 : localTargetEnd; // 仅倒计时需要此标记
          _sessionStartMs = isCountUp ? localSessionStart : 0;
          _currentSessionUuid = signal.sessionUuid ?? _currentSessionUuid;
          _remainingSeconds = rem;
          _isPaused = isPaused;
          _pausedAtMs = signal.pausedAtMs ?? 0;
          _accumulatedMs = acc;
          _pauseStartMs = signal.pauseStartMs ?? _pausedAtMs;
          _boundTodo = remoteTodo;
          _remoteState = signal;
          _remoteTagNames = signal.tags;
          _currentNote = signal.note ?? '';
        });
        widget.onPhaseChanged(_phase);

        if (isPaused) {
          _startPauseTicker();
        } else {
          _startRemoteTicker(_targetEndMs, isCountUp);
        }
        _showLocalFloat();
        break;

      case 'SYNC_TAGS':
      case 'UPDATE_TAGS':
        if (_phase != PomodoroPhase.remoteWatching) break;
        if (mounted) _mutateState(() => _remoteTagNames = signal.tags);
        break;

      case 'UPDATE_NOTE':
        if (signal.sessionUuid != null &&
            signal.sessionUuid != _currentSessionUuid &&
            signal.sessionUuid != _remoteState?.sessionUuid) {
          break;
        }
        if (_phase != PomodoroPhase.focusing &&
            _phase != PomodoroPhase.remoteWatching) {
          break;
        }
        if (mounted) {
          _mutateState(() {
            _currentNote = signal.note ?? '';
            if (_phase == PomodoroPhase.remoteWatching) {
              _remoteState = CrossDevicePomodoroState(
                action: _remoteState?.action ?? 'SYNC',
                sessionUuid: _remoteState?.sessionUuid,
                todoUuid: _remoteState?.todoUuid,
                todoTitle: _remoteState?.todoTitle,
                duration: _remoteState?.duration,
                targetEndMs: _remoteState?.targetEndMs,
                sourceDevice: _remoteState?.sourceDevice,
                timestamp: _remoteState?.timestamp,
                mode: _remoteState?.mode,
                tags: _remoteState?.tags ?? [],
                note: _currentNote,
                doNotDisturb: _remoteState?.doNotDisturb,
              );
            }
          });
          await _saveCurrentRunState();
          _showLocalFloat();
        }
        break;

      case 'PAUSE':
        if (_phase != PomodoroPhase.remoteWatching) break;
        await _setFocusDoNotDisturb(
          (signal.doNotDisturb ?? _remoteState?.doNotDisturb) == true,
          sessionUuid: signal.sessionUuid ?? _remoteState?.sessionUuid,
        );
        if (mounted) {
          _mutateState(() {
            _isPaused = true;
            _pausedAtMs =
                signal.pausedAtMs ?? DateTime.now().millisecondsSinceEpoch;
            _accumulatedMs = signal.accumulatedMs ?? 0;
            _pauseStartMs = signal.pauseStartMs ?? _pausedAtMs;
            _remoteState = signal;
          });
          _ticker?.cancel();
          _remoteTicker?.cancel();
          _startPauseTicker();
          _pushPomodoroNotification();
          _showLocalFloat();
        }
        break;

      case 'RESUME':
        if (_phase != PomodoroPhase.remoteWatching &&
            _phase != PomodoroPhase.idle) {
          break;
        }
        if (mounted) {
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          final isCountUp = signal.mode == 1;
          int rem = 0;

          int localTargetEnd = 0;
          int localSessionStart = 0;

          if (signal.serverElapsedMs != null) {
            if (isCountUp) {
              localSessionStart = nowMs - signal.serverElapsedMs!;
              rem = signal.serverElapsedMs! ~/ 1000;
            } else {
              final plannedSecs =
                  signal.duration ?? (_settings.focusMinutes * 60);
              rem = plannedSecs - (signal.serverElapsedMs! ~/ 1000);
              if (rem < 0) rem = 0;
              localTargetEnd = nowMs + (rem * 1000);
            }
          } else {
            // 降级使用本地校准逻辑
            final timestamp = signal.timestamp ?? nowMs;
            final endMs = signal.targetEndMs ?? 0;
            final acc = signal.accumulatedMs ?? 0;
            if (isCountUp) {
              rem = ((nowMs - timestamp - acc) / 1000).floor();
              localSessionStart = nowMs - (rem * 1000);
            } else {
              rem = ((endMs - nowMs) / 1000).ceil();
              localTargetEnd = nowMs + (rem * 1000);
            }
          }

          await _setFocusDoNotDisturb(
            (signal.doNotDisturb ?? _remoteState?.doNotDisturb) == true,
            sessionUuid: signal.sessionUuid ?? _remoteState?.sessionUuid,
            untilMs: isCountUp ? null : localTargetEnd,
          );

          _mutateState(() {
            _remoteState = signal;
            _isPaused = false;
            _phase = PomodoroPhase.remoteWatching;
            _pausedAtMs = 0;
            _pauseStartMs = 0;
            _pauseElapsedSecs = 0;
            _accumulatedMs = signal.accumulatedMs ?? _accumulatedMs;
            _remainingSeconds = rem;
            _targetEndMs = isCountUp ? 0 : localTargetEnd;
            _sessionStartMs = isCountUp ? localSessionStart : 0;
            _currentSessionUuid = signal.sessionUuid ?? _currentSessionUuid;
            if (signal.note != null) _currentNote = signal.note!;

            if (signal.todoTitle != null && signal.todoTitle!.isNotEmpty) {
              _boundTodo = TodoItem(
                id: signal.todoUuid ?? '',
                title: signal.todoTitle!,
                isDone: false,
                createdAt: 0,
              );
            }
          });
          _pauseTicker?.cancel();
          _startRemoteTicker(isCountUp ? 0 : _targetEndMs, isCountUp);
          _pushPomodoroNotification();
          _showLocalFloat();
          widget.onPhaseChanged(_phase);
        }
        break;

      case 'STOP':
      case 'INTERRUPT':
      case 'FINISH':
      case 'SYNC_RESET':
      case 'CLEAR_FOCUS':
      case 'FOCUS_DISCONNECTED':
        // 🚀 遵从“本地计时优先”原则：只有在远程观察模式下，才接受外部的停止信号
        if (_phase != PomodoroPhase.remoteWatching) break;

        // 🚀 精准匹配：如果信号中包含 ID，必须与当前观察的 ID 一致才停止
        if (signal.sessionUuid != null &&
            _currentSessionUuid != signal.sessionUuid) {
          break;
        }
        if (signal.sessionUuid == null &&
            signal.todoUuid != null &&
            _boundTodo?.id != signal.todoUuid) {
          break;
        }

        if (_phase == PomodoroPhase.idle || _phase == PomodoroPhase.finished) {
          break;
        }
        await _setFocusDoNotDisturb(
          false,
          sessionUuid: signal.sessionUuid ?? _remoteState?.sessionUuid,
        );
        _stopRemoteTicker();
        _mutateState(() {
          _phase = PomodoroPhase.idle;
          _currentSessionUuid = '';
          _remainingSeconds = _settings.mode == TimerMode.countUp
              ? 0
              : _settings.focusMinutes * 60;
          _remoteState = null;
          _boundTodo = null;
          _remoteTagNames = [];
        });
        widget.onPhaseChanged(_phase);
        break;

      case 'SWITCH':
        if (_phase != PomodoroPhase.remoteWatching) break;
        {
          final isCountUp = _remoteState?.mode == 1;
          final newTimestamp =
              signal.timestamp ?? DateTime.now().millisecondsSinceEpoch;

          await _setFocusDoNotDisturb(
            _remoteState?.doNotDisturb == true,
            sessionUuid: signal.sessionUuid ?? _remoteState?.sessionUuid,
            untilMs: isCountUp ? null : _targetEndMs,
          );

          _mutateState(() {
            _boundTodo =
                (signal.todoTitle != null && signal.todoTitle!.isNotEmpty)
                ? TodoItem(
                    id: signal.todoUuid ?? '',
                    title: signal.todoTitle!,
                    isDone: false,
                    createdAt: 0,
                  )
                : null;
            _currentSessionUuid = signal.sessionUuid ?? _currentSessionUuid;
            if (isCountUp) {
              int elapsed =
                  ((DateTime.now().millisecondsSinceEpoch - newTimestamp) /
                          1000)
                      .floor();
              _remainingSeconds = elapsed < 0 ? 0 : elapsed;
            }

            _remoteState = CrossDevicePomodoroState(
              action: _remoteState?.action ?? 'SYNC',
              sessionUuid: signal.sessionUuid ?? _remoteState?.sessionUuid,
              todoUuid: signal.todoUuid ?? _remoteState?.todoUuid,
              todoTitle: signal.todoTitle,
              duration: _remoteState?.duration,
              targetEndMs: _remoteState?.targetEndMs,
              sourceDevice: _remoteState?.sourceDevice,
              timestamp: signal.timestamp ?? _remoteState?.timestamp,
              mode: _remoteState?.mode,
              tags: _remoteState?.tags ?? [],
              note: signal.note ?? _remoteState?.note,
              doNotDisturb: _remoteState?.doNotDisturb,
            );
          });
          if (isCountUp) {
            _startRemoteTicker(_targetEndMs, true);
          }
        }
        break;
    }
  }

  void _startRemoteTicker(int targetEndMs, bool isCountUp) {
    _remoteTicker?.cancel();
    _remoteTicker = null;
    if (!_shouldRunUiTickers) return;
    _remoteTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _remoteTicker?.cancel();
        return;
      }
      if (_phase != PomodoroPhase.remoteWatching) {
        _remoteTicker?.cancel();
        return;
      }
      if (_isPaused) return;

      if (isCountUp) {
        final elapsed =
            ((DateTime.now().millisecondsSinceEpoch - _sessionStartMs) / 1000)
                .floor();
        _remainingSeconds = elapsed;
        _timerTickNotifier.value++;
      } else {
        final rem =
            ((targetEndMs - DateTime.now().millisecondsSinceEpoch) / 1000)
                .ceil();
        // 增加 2 秒容错缓冲，防止由于两端时钟微小偏差导致远端提前退出
        if (rem < -2) {
          unawaited(
            _setFocusDoNotDisturb(
              false,
              sessionUuid: _remoteState?.sessionUuid ?? _currentSessionUuid,
            ),
          );
          _remoteTicker?.cancel();
          _mutateState(() {
            _phase = PomodoroPhase.idle;
            _remainingSeconds = _settings.mode == TimerMode.countUp
                ? 0
                : _settings.focusMinutes * 60;
            _remoteState = null;
            _boundTodo = null;
            _remoteTagNames = [];
          });
          widget.onPhaseChanged(_phase);
        } else {
          // 即使内部允许负值缓冲，UI 上也要显示为 0
          _remainingSeconds = rem < 0 ? 0 : rem;
          _timerTickNotifier.value++;
        }
      }
    });
  }

  void _stopRemoteTicker() {
    _remoteTicker?.cancel();
    _remoteTicker = null;
  }

  Future<void> _persistIdleBoundTodo(
    TodoItem? todo, {
    List<String>? tagUuids,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (todo != null) {
      await prefs.setString(_keyBoundTodoUuid, todo.id);
      await prefs.setString(_keyBoundTodoTitle, todo.title);
    } else {
      await prefs.remove(_keyBoundTodoUuid);
      await prefs.remove(_keyBoundTodoTitle);
    }
    final tags = tagUuids ?? _selectedTagUuids;
    if (tags.isNotEmpty) {
      await prefs.setString(_keySelectedTagUuids, tags.join(','));
    } else {
      await prefs.remove(_keySelectedTagUuids);
    }
  }

  Future<List<String>> _recommendedTagUuidsForTodo(TodoItem todo) async {
    if (_tags.isEmpty) return const [];
    try {
      final records = await PomodoroService.getRecords().timeout(
        const Duration(seconds: 2),
        onTimeout: () => [],
      );
      return await TodoClassificationService.recommendPomodoroTagUuidsForTodo(
        todo: todo,
        tags: _tags,
        history: records,
        todoHistory: _todos,
        groups: _todoGroups,
      );
    } catch (e) {
      // debugPrint('[PomodoroWorkbench] recommend tags failed: $e');
      return const [];
    }
  }

  Future<void> _applyInitialEntry() async {
    final entry = widget.initialEntry;
    if (entry == null) return;

    TodoItem? boundTodo;
    final requestedTodo = entry.boundTodo;
    if (requestedTodo != null) {
      boundTodo = _todos.cast<TodoItem?>().firstWhere(
        (todo) => todo?.id == requestedTodo.id,
        orElse: () => requestedTodo,
      );
    }

    final List<String> tagUuids;
    if (entry.tagUuids != null) {
      tagUuids = List<String>.from(entry.tagUuids!);
    } else if (boundTodo != null) {
      tagUuids = await _recommendedTagUuidsForTodo(boundTodo);
    } else {
      tagUuids = List<String>.from(_selectedTagUuids);
    }
    if (!mounted) return;

    final focusMinutes = entry.focusMinutes?.clamp(1, 120).toInt();
    _mutateState(() {
      _boundTodo = boundTodo;
      _selectedTagUuids = tagUuids;
      _planBlockId = entry.planBlockId;
      _habitUuid = entry.habitUuid;
      _challengeTaskId = entry.challengeTaskId;
      _targetLabel = entry.targetLabel;
      _preparedFocusMinutes = focusMinutes;
      _activeFocusSeconds = null;
      _remainingSeconds = _settings.mode == TimerMode.countUp
          ? 0
          : (focusMinutes ?? _settings.focusMinutes) * 60;
    });
    try {
      await _persistIdleBoundTodo(boundTodo, tagUuids: tagUuids);
    } catch (error) {
      debugPrint('[PomodoroWorkbench] 保存入口绑定失败: $error');
    }
  }

  Future<(TodoPlanBlock, TodoPlanStatus)?> _markPlanBlockFocusing() async {
    final planBlockId = _planBlockId;
    if (planBlockId == null || planBlockId.isEmpty) return null;

    final blocks = await StorageService.getPlanBlocks(widget.username);
    TodoPlanBlock? block;
    for (final candidate in blocks) {
      if (candidate.uuid == planBlockId && !candidate.isDeleted) {
        block = candidate;
        break;
      }
    }
    if (block == null || _boundTodo?.id != block.todoId) {
      throw StateError('规划已变化，请重新从规划入口打开番茄钟');
    }
    if (block.status == TodoPlanStatus.focusing) return null;

    final previousStatus = block.status;
    final updated = await StorageService.savePlanBlockEdited(
      widget.username,
      block,
      expectedVersion: block.version,
      expectedUpdatedAt: block.updatedAt,
      newStatus: TodoPlanStatus.focusing,
    );
    return (updated, previousStatus);
  }

  Future<void> _rollbackPlanBlockStatus(
    (TodoPlanBlock, TodoPlanStatus)? receipt,
  ) async {
    if (receipt == null) return;
    try {
      await StorageService.savePlanBlockEdited(
        widget.username,
        receipt.$1,
        expectedVersion: receipt.$1.version,
        expectedUpdatedAt: receipt.$1.updatedAt,
        newStatus: receipt.$2,
      );
    } catch (error) {
      debugPrint('[PomodoroWorkbench] 恢复规划状态失败: $error');
    }
  }
}
