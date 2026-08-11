part of 'home_dashboard.dart';
// ignore_for_file: annotate_overrides

mixin _HomeDashboardPomodoroMixin on _HomeDashboardStateBase {
  Future<void> _initCrossDevicePomodoro() async {
    _deviceId = await StorageService.getDeviceId();
    final prefs = await SharedPreferences.getInstance();
    final userIdInt = prefs.getInt('current_user_id');
    if (userIdInt == null || _deviceId.isEmpty) return;

    _remotePomodoroSub?.cancel();
    _remotePomodoroSub =
        _syncService.onStateChanged.listen(_handleRemotePomodoroSignal);

    // 🍅 发起端重连后，服务端回推了历史专注状态
    // 若本地已无对应状态（说明已被用户关闭/完成），则通知云端清除残留
    _syncService.onStaleSyncFocus = (state) async {
      // debugPrint('[首页] 收到服务端回推的残留状态，校验本地...');
      final saved = await PomodoroService.loadRunState();
      if (saved == null ||
          (saved.phase != PomodoroPhase.focusing &&
              saved.phase != PomodoroPhase.breaking)) {
        // debugPrint('[首页] 本地无运行中的专注状态，发送 CLEAR_FOCUS 清除云端残留');
        _syncService.sendClearFocusSignal();
      } else {
        // debugPrint('[首页] 本地仍有运行中的专注，保留云端状态');
      }
    };

    // 监听网络重连，主动上报本地专注状态
    _connStateSub?.cancel();
    _connStateSub = _syncService.onConnectionChanged.listen((state) async {
      if (state == SyncConnectionState.connected) {
        final saved = await PomodoroService.loadRunState();
        if (saved == null) return;

        if (saved.phase == PomodoroPhase.focusing ||
            saved.phase == PomodoroPhase.breaking) {
          final isCountUp = saved.mode == TimerMode.countUp;
          final remaining = isCountUp
              ? 1
              : saved.targetEndMs - DateTime.now().millisecondsSinceEpoch;
          if (remaining > 0) {
            // debugPrint("🔗 [首页] WS已连上，主动向云端同步本地运行中的专注状态");

            final realTagNames = List<String>.from(saved.tagNames);
            if (realTagNames.isEmpty && saved.tagUuids.isNotEmpty) {
              final allTags = await PomodoroService.getTags();
              for (String uuid in saved.tagUuids) {
                final tag = allTags.where((t) => t.uuid == uuid).firstOrNull;
                if (tag != null) {
                  realTagNames.add(tag.name);
                }
              }
            }
            final sourceDeviceName =
                await StorageService.getDeviceFriendlyName();

            _syncService.sendReconnectSyncSignal(
              sessionUuid: saved.sessionUuid,
              todoUuid: saved.todoUuid,
              todoTitle: saved.todoTitle,
              planBlockId: saved.planBlockId,
              durationSeconds: saved.phase == PomodoroPhase.focusing
                  ? saved.plannedFocusSeconds
                  : saved.breakSeconds,
              targetEndMs: saved.targetEndMs,
              tagNames: realTagNames,
              sourceDeviceName: sourceDeviceName,
              mode: saved.mode.index,
              currentCycle: saved.currentCycle,
              totalCycles: saved.totalCycles,
              plannedFocusSeconds: saved.plannedFocusSeconds,
              note: saved.note,
              customTimestamp: saved.sessionStartMs, // 🚀 关键：使用真实的起点时间
            );
          }
        }
      }
    });

    // 🚀 显式获取版本号传给底层服务（双重保险）
    String appVersion = 'unknown';
    try {
      final info = await PackageInfo.fromPlatform();
      appVersion = info.version;
    } catch (_) {}

    // 🚀 获取 auth token 用于 WebSocket 鉴权
    final authToken = await StorageService.getAuthToken();

    await _syncService.ensureConnected(
        userIdInt.toString(), 'flutter_$_deviceId',
        authToken: authToken, appVersion: appVersion);
  }

  // FloatWindow channel is now handled by FloatWindowService

  // 🚀 修改：处理云端发来的 UPDATE_AVAILABLE 信号
  Future<void> _handleRemotePomodoroSignal(
      CrossDevicePomodoroState signal) async {
    if (!mounted || _deviceId.isEmpty) return;
    if (signal.sourceDevice == _deviceId ||
        signal.sourceDevice == 'flutter_$_deviceId') {
      return;
    }

    switch (signal.action) {
      // 🚀 新增：拦截云端的更新推送
      case 'UPDATE_AVAILABLE':
        if (!_hasShownUpdate && mounted && signal.manifestData != null) {
          _hasShownUpdate = true;
          final manifest = AppManifest.fromJson(signal.manifestData!);

          PackageInfo packageInfo = await PackageInfo.fromPlatform();
          if (!mounted) return;

          // 复用强大的 UpdateService 弹窗
          UpdateService.showUpdateDialog(context, manifest, packageInfo.version,
              hasUpdate: true);
        }
        break;
      case 'TEAM_REMOVED':
        // debugPrint('🚀 [协同] 收到强制移除信号，立即执行同步与本地清理...');
        await _handleManualSync(silent: true);
        break;

      case 'TEAM_UPDATE':
      case 'SYNC_DATA':
      case 'JOIN_REQUEST_APPROVED':
      case 'TEAM_MEMBER_JOINED':
      case 'NEW_INVITATION':
        // debugPrint('🚀 [协同信号] 收到 ${signal.action}, 触发静默同步');
        _debounceCollaborativeSync();
        break;

      case 'NEW_JOIN_REQUEST':
      case 'PENDING_COUNTS':
        _fetchTeamPendingCount();
        break;

      case 'NOTIFICATION_EVENT':
        _fetchTeamPendingCount();
        final eventId = signal.delta is Map
            ? int.tryParse(signal.delta['id']?.toString() ?? '')
            : null;
        if (eventId != null && eventId > 0) {
          unawaited(
            BackgroundNotificationService.markNotificationEventShown(
              eventId,
            ),
          );
          if (!_handledForegroundNotificationIds.add(eventId)) {
            break;
          }
        }
        final title =
            signal.delta is Map ? signal.delta['title']?.toString() : null;
        final body =
            signal.delta is Map ? signal.delta['body']?.toString() : null;
        if (title != null && title.isNotEmpty) {
          NotificationService.showGenericNotification(
            title: title,
            body: body ?? '',
          );
        }
        break;

      case 'NEW_ANNOUNCEMENT':
      case 'ANNOUNCEMENT_RECALLED':
        _fetchActiveAnnouncements();
        break;

      case 'START':
      case 'SYNC_FOCUS':
      case 'RECONNECT_SYNC':
        final isCountUp = signal.mode == 1;
        final endMs = signal.targetEndMs;
        if (endMs == null) return;

        int rem = 0;
        if (isCountUp) {
          final timestamp =
              signal.timestamp ?? DateTime.now().millisecondsSinceEpoch;
          rem = ((DateTime.now().millisecondsSinceEpoch - timestamp) / 1000)
              .floor();
        } else {
          rem = ((endMs - DateTime.now().millisecondsSinceEpoch) / 1000).ceil();
          if (rem <= 0) return;
        }

        setState(() {
          _remotePomodoro = signal;
          _remotePomodoroRemaining = rem;
        });
        _startRemotePomodoroTicker(endMs, isCountUp);

        if (AppPlatform.isWindows) {
          final prefs = await SharedPreferences.getInstance();
          if (prefs.getBool('float_window_enabled') ?? true) {
            await FloatWindowService.update(
              endMs: isCountUp ? signal.timestamp : endMs,
              title: signal.todoTitle ?? '',
              tags: signal.tags,
              isLocal: false,
              mode: isCountUp ? 1 : 0,
              note: signal.note ?? '',
            );
          }
        }
        break;

      case 'STOP':
      case 'INTERRUPT':
      case 'FOCUS_DISCONNECTED':
        _stopRemotePomodoroTicker();
        setState(() => _remotePomodoro = null);

        // 远端专注结束/断连后，将本地仍为 focusing 状态的规划块重置
        _resetStalePlanBlockFocus();

        if (AppPlatform.isWindows) {
          await FloatWindowService.update(endMs: 0, isLocal: false);
        }
        break;

      case 'SWITCH':
        if (_remotePomodoro == null) return;
        final isCountUp = _remotePomodoro!.mode == 1;
        setState(() {
          _remotePomodoro = CrossDevicePomodoroState(
            action: _remotePomodoro!.action,
            sessionUuid: signal.sessionUuid ?? _remotePomodoro!.sessionUuid,
            todoUuid: signal.todoUuid ?? _remotePomodoro!.todoUuid,
            todoTitle: signal.todoTitle ?? _remotePomodoro!.todoTitle,
            duration: _remotePomodoro!.duration,
            targetEndMs: _remotePomodoro!.targetEndMs,
            sourceDevice: _remotePomodoro!.sourceDevice,
            timestamp: signal.timestamp ?? _remotePomodoro!.timestamp,
            mode: _remotePomodoro!.mode,
            tags: _remotePomodoro!.tags,
            note: signal.note ?? _remotePomodoro!.note,
          );
          if (isCountUp) {
            _remotePomodoroRemaining = 0; // 🚀 关键：同步侧归零
          }
        });
        if (isCountUp) {
          _startRemotePomodoroTicker(_remotePomodoro!.targetEndMs ?? 0, true);
        }
        if (AppPlatform.isWindows) {
          await FloatWindowService.update(
            endMs: isCountUp
                ? (_remotePomodoro!.timestamp ??
                    DateTime.now().millisecondsSinceEpoch)
                : (_remotePomodoro!.targetEndMs ?? 0),
            title: _remotePomodoro!.todoTitle ?? '',
            tags: _remotePomodoro!.tags,
            isLocal: false,
            mode: isCountUp ? 1 : 0,
            note: _remotePomodoro!.note ?? '',
          );
        }
        break;

      case 'UPDATE_NOTE':
        if (_remotePomodoro == null) return;
        if (signal.sessionUuid != null &&
            signal.sessionUuid != _remotePomodoro!.sessionUuid) {
          return;
        }
        final isCountUp = _remotePomodoro!.mode == 1;
        setState(() {
          _remotePomodoro = CrossDevicePomodoroState(
            action: _remotePomodoro!.action,
            sessionUuid: _remotePomodoro!.sessionUuid,
            todoUuid: _remotePomodoro!.todoUuid,
            todoTitle: _remotePomodoro!.todoTitle,
            duration: _remotePomodoro!.duration,
            targetEndMs: _remotePomodoro!.targetEndMs,
            sourceDevice: _remotePomodoro!.sourceDevice,
            timestamp: _remotePomodoro!.timestamp,
            mode: _remotePomodoro!.mode,
            tags: _remotePomodoro!.tags,
            note: signal.note ?? '',
          );
        });
        if (AppPlatform.isWindows) {
          await FloatWindowService.update(
            endMs: isCountUp
                ? (_remotePomodoro!.timestamp ??
                    DateTime.now().millisecondsSinceEpoch)
                : (_remotePomodoro!.targetEndMs ?? 0),
            title: _remotePomodoro!.todoTitle ?? '',
            tags: _remotePomodoro!.tags,
            isLocal: false,
            mode: isCountUp ? 1 : 0,
            note: _remotePomodoro!.note ?? '',
          );
        }
        break;
    }
  }

  void _startRemotePomodoroTicker(int targetEndMs, bool isCountUp) {
    if (!_isDashboardInForeground) {
      _stopRemotePomodoroTicker();
      return;
    }
    _remotePomodoroTicker?.cancel();
    _remotePomodoroTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _remotePomodoroTicker?.cancel();
        return;
      }
      if (isCountUp) {
        final startedAt = _remotePomodoro?.timestamp;
        _remotePomodoroRemaining = startedAt == null
            ? _remotePomodoroRemaining + 1
            : ((DateTime.now().millisecondsSinceEpoch - startedAt) / 1000)
                .floor();
        _pomodoroTickNotifier.value++;
      } else {
        final rem =
            ((targetEndMs - DateTime.now().millisecondsSinceEpoch) / 1000)
                .ceil();
        if (rem <= 0) {
          _remotePomodoroTicker?.cancel();
          if (mounted) setState(() => _remotePomodoro = null);
        } else {
          _remotePomodoroRemaining = rem;
          _pomodoroTickNotifier.value++;
        }
      }
    });
  }

  void _stopRemotePomodoroTicker() {
    _remotePomodoroTicker?.cancel();
    _remotePomodoroTicker = null;
  }

  /// 🚀 重新实现：监测本地专注状态
  /// 不再使用 1 秒一次的轮询读取 Storage，改为监听 Stream
  void _initLocalPomodoroMonitoring() {
    _localPomodoroSub?.cancel();
    _localPomodoroSub = PomodoroService.onRunStateChanged.listen((saved) {
      if (!mounted) return;
      if (saved != null &&
          (saved.phase == PomodoroPhase.focusing ||
              saved.phase == PomodoroPhase.breaking)) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final isCountUp = saved.mode == TimerMode.countUp;
        final rem = isCountUp
            ? ((now - saved.sessionStartMs) / 1000).floor()
            : ((saved.targetEndMs - now) / 1000).ceil();

        setState(() {
          _localPomodoro = saved;
          _localPomodoroRemaining = rem;
        });
        _startLocalTicker(isCountUp);
      } else {
        _stopLocalTicker();
        setState(() {
          _localPomodoro = null;
          _localPomodoroRemaining = 0;
        });
      }
    });

    // 初始加载一次
    PomodoroService.loadRunState().then((saved) {
      if (!mounted || saved == null) return;
      if (saved.phase == PomodoroPhase.focusing ||
          saved.phase == PomodoroPhase.breaking) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final isCountUp = saved.mode == TimerMode.countUp;
        final rem = isCountUp
            ? ((now - saved.sessionStartMs) / 1000).floor()
            : ((saved.targetEndMs - now) / 1000).ceil();

        setState(() {
          _localPomodoro = saved;
          _localPomodoroRemaining = rem;
        });
        _startLocalTicker(isCountUp);
      }
    });
  }

  void _startLocalTicker(bool isCountUp) {
    if (!_isDashboardInForeground) {
      _stopLocalTicker();
      return;
    }
    _localPomodoroTicker?.cancel();
    _localPomodoroTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _localPomodoro == null) {
        timer.cancel();
        return;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final pomMode = _localPomodoro!.mode;
      final isActuallyCountUp = pomMode == TimerMode.countUp;

      final rem = isActuallyCountUp
          ? ((now - _localPomodoro!.sessionStartMs) / 1000).floor()
          : ((_localPomodoro!.targetEndMs - now) / 1000).ceil();

      _localPomodoroRemaining = rem;
      if (!isActuallyCountUp && _localPomodoroRemaining <= 0) {
        _localPomodoroRemaining = 0;
        _stopLocalTicker();
      }
      _pomodoroTickNotifier.value++;
    });
  }

  void _stopLocalTicker() {
    _localPomodoroTicker?.cancel();
    _localPomodoroTicker = null;
  }

  /// 待确认事项入口卡片（从图片识别来）

  bool _isPlanBlockStartable(TodoPlanStatus status) {
    return status == TodoPlanStatus.planned ||
        status == TodoPlanStatus.reminded ||
        status == TodoPlanStatus.delayed ||
        status == TodoPlanStatus.focusing;
  }

  /// 远端专注结束/断连后，将 focusing 状态但无对应本地/远端番茄钟的规划块重置为 delayed
  Future<void> _resetStalePlanBlockFocus() async {
    final hasLocal = _localPomodoro != null;
    final hasRemote = _remotePomodoro != null;
    if (hasLocal || hasRemote) return;

    final changed = <TodoPlanBlock>[];
    for (final b in _planBlocks) {
      if (b.isDeleted) continue;
      if (b.status == TodoPlanStatus.focusing) {
        b.status = TodoPlanStatus.delayed;
        b.markAsChanged();
        changed.add(b);
      }
    }
    if (changed.isNotEmpty) {
      await StorageService.savePlanBlocks(widget.username, changed);
      if (mounted) {
        setState(() {});
      }
    }
  }

  String _planBlockStartText(int startTimeMs, int nowMs) {
    final minutes = ((startTimeMs - nowMs) / 60000).ceil();
    return minutes <= 1 ? '马上开始' : '$minutes 分钟后开始';
  }

  Future<void> _startPlanBlockFocus(TodoPlanBlock block) async {
    try {
      final todos = await StorageService.getTodos(widget.username);
      TodoItem? boundTodo;
      for (final todo in todos) {
        if (todo.id == block.todoId && !todo.isDeleted) {
          boundTodo = todo;
          break;
        }
      }
      boundTodo ??= TodoItem(
        id: block.todoId,
        title: block.titleSnapshot?.isNotEmpty == true
            ? block.titleSnapshot!
            : '规划任务',
      );

      final configuredPomodoroMinutes = block.pomodoroRounds > 0
          ? block.pomodoroMinutes * block.pomodoroRounds
          : 0;
      final plannedMinutes = configuredPomodoroMinutes > 0
          ? configuredPomodoroMinutes
          : (block.plannedMinutes > 0
              ? block.plannedMinutes
              : ((block.endTime - block.startTime) / 60000).round());
      block.status = TodoPlanStatus.focusing;
      block.markAsChanged();
      await StorageService.savePlanBlocks(widget.username, [block]);
      final settings = await PomodoroService.getSettings();
      await PomodoroControlService.startFocus(
        settings: settings,
        boundTodo: boundTodo,
        durationMinutes: plannedMinutes < 1 ? 1 : plannedMinutes,
        planBlockId: block.uuid,
      );

      if (!mounted) return;
      await Navigator.push(
        context,
        PageTransitions.material(
          builder: (_) => PomodoroScreen(username: widget.username),
        ),
      );
      if (mounted) {
        _pomodoroRevision.value++;
        _scheduleRevision.value++;
        _timelineRevision.value++;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('启动专注失败: $e')),
      );
    }
  }

  Future<void> _stopPlanBlockPomodoro() async {
    try {
      await PomodoroControlService.stopCurrentFocus(
        username: widget.username,
        status: PomodoroRecordStatus.interrupted,
      );
      if (mounted) {
        _pomodoroRevision.value++;
        _scheduleRevision.value++;
        _timelineRevision.value++;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('停止专注失败: $e')),
      );
    }
  }
}
