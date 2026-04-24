import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../models.dart';
import '../../../storage_service.dart';
import '../../../services/api_service.dart';
import '../../../services/pomodoro_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/pomodoro_sync_service.dart';
import '../../../services/band_sync_service.dart';
import '../../../services/float_window_service.dart';
import '../../../update_service.dart';
import '../pomodoro_utils.dart';
import '../widgets/tag_manager_sheet.dart';
import '../widgets/immersive_timer.dart';
import '../widgets/workbench_actions.dart';
import '../widgets/workbench_task_area.dart';
import '../../../windows_island/island_channel.dart';
import 'package:window_manager/window_manager.dart';

class PomodoroWorkbench extends StatefulWidget {
  final String username;
  final ValueChanged<PomodoroPhase> onPhaseChanged;
  final VoidCallback? onReady;

  // New: allow the workbench to render in a compact mode (used by landscape side column)
  final bool isCompact;

  const PomodoroWorkbench({
    super.key,
    required this.username,
    required this.onPhaseChanged,
    this.onReady,
    this.isCompact = false,
  });

  @override
  State<PomodoroWorkbench> createState() => PomodoroWorkbenchState();
}

class PomodoroWorkbenchState extends State<PomodoroWorkbench> with WidgetsBindingObserver {
  // ── 设置 ──
  PomodoroSettings _settings = PomodoroSettings();

  // ── 运行状态 ──
  PomodoroPhase _phase = PomodoroPhase.idle;
  String _currentSessionUuid = '';
  bool _isHandlingEnd = false;

  int _targetEndMs = 0;
  int _remainingSeconds = 0;
  int _currentCycle = 1;
  int _sessionStartMs = 0;

  // 🚀 暂停状态
  bool _isPaused = false;
  int _pausedAtMs = 0;
  int _accumulatedMs = 0;
  int _pauseStartMs = 0;
  int _pauseElapsedSecs = 0;
  Timer? _pauseTicker;

  // ── 任务绑定 ──
  TodoItem? _boundTodo;
  List<PomodoroTag> _allTags = [];
  List<String> _selectedTagUuids = [];
  // Backwards-compatibility: older code referred to `_selectedUuids`.
  // Keep a getter/setter so any remaining call sites still work.
  List<String> get _selectedUuids => _selectedTagUuids;
  set _selectedUuids(List<String> v) => _selectedTagUuids = v;

  // ── Timer ──
  Timer? _ticker;
  int _notifyTickCount = 0;

  // ── Todos ──
  List<TodoItem> _todos = [];
  List<TodoGroup> _todoGroups = [];
  String _deviceId = '';
  String _userId = '';
  String _appVersion = 'unknown';

  // ── 跨端感知 ──
  final _syncService = PomodoroSyncService();
  StreamSubscription? _crossDeviceSub;
  StreamSubscription? _connSub; // 🚀 兼容性修复：改为通配订阅类型
  CrossDevicePomodoroState? _remoteState;
  Timer? _remoteTicker;
  List<String> _remoteTagNames = [];

  bool _wsConnected = false;
  SyncConnectionState _syncConnState = SyncConnectionState.disconnected; // 🚀 新增：跟踪连接状态
  bool _hasShownUpdate = false;
  bool _initializing = true;

  static const _keyBoundTodoUuid = 'pomodoro_idle_bound_todo_uuid';
  static const _keyBoundTodoTitle = 'pomodoro_idle_bound_todo_title';
  static const _keySelectedTagUuids = 'pomodoro_idle_selected_tag_uuids';

  @override
  void initState() {
    super.initState();
    FloatWindowService.isWorkbenchMounted = true;
    WidgetsBinding.instance.addObserver(this);
    _init();
    _listenToRunState();
    _listenToIslandActions();
  }

  StreamSubscription? _islandSub;
  StreamSubscription? _bandSub;
  void _listenToIslandActions() {
    _islandSub = IslandChannel.actionStream.listen((actionData) {
      if (!mounted) return;
      if (actionData.isNotEmpty) {
        final action = actionData['action']?.toString();
        if (action == 'finish') {
          windowManager.show();
          windowManager.focus();
          _onFocusEnd();
        } else if (action == 'abandon') {
          windowManager.show();
          windowManager.focus();
          _abandonFocus(true);
        }
      }
    });
    _bandSub = BandSyncService.onBandPomodoroAction.listen((actionData) {
      if (!mounted) return;
      final action = actionData['action']?.toString();
      if (action == 'finish') {
        if (!Platform.isWindows) {
          _finishEarly();
        } else {
          windowManager.show();
          windowManager.focus();
          _finishEarly();
        }
      } else if (action == 'abandon') {
        if (!Platform.isWindows) {
          _abandonFocus(true);
        } else {
          windowManager.show();
          windowManager.focus();
          _abandonFocus(true);
        }
      }
    });
  }

  StreamSubscription? _runStateSub;
  void _listenToRunState() {
    _runStateSub = PomodoroService.onRunStateChanged.listen((state) {
      if (state == null &&
          (_phase == PomodoroPhase.focusing ||
              _phase == PomodoroPhase.breaking)) {
        // Island action (finish/abandon) cleared the state, we must sync UI
        _ticker?.cancel();
        NotificationService.cancelNotification();
        if (mounted) {
          setState(() {
            _phase = PomodoroPhase.idle;
            _remainingSeconds = _settings.mode == TimerMode.countUp
                ? 0
                : _settings.focusMinutes * 60;
          });
          widget.onPhaseChanged(_phase);
          // Force full UI reload to reflect completed/abandoned session
          _init();
        }
      }
    });
  }

  @override
  void dispose() {
    FloatWindowService.isWorkbenchMounted = false;
    _ticker?.cancel();
    _remoteTicker?.cancel();
    _crossDeviceSub?.cancel();
    _connSub?.cancel();
    _runStateSub?.cancel();
    _islandSub?.cancel();
    _bandSub?.cancel();
    _wsConnected = false;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Public API: reload workbench data (used by parent when tab becomes visible)
  Future<void> reload() async {
    // Re-run the initialization sequence to refresh settings/tags/state
    await _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _notifyTickCount = 0;
      _recoverFromBackground();
      _syncService.resumeSync();
    }
  }

  bool _isInitProcessing = false;
  Future<void> _init() async {
    if (_isInitProcessing) {
      debugPrint('[PomodoroWorkbench] _init already in progress, skipping redundant call');
      return;
    }
    _isInitProcessing = true;
    final initStart = DateTime.now();
    debugPrint(
        '[PomodoroWorkbench] _init start: ${initStart.toIso8601String()}');
    Timer? initWatchdog = Timer(const Duration(seconds: 6), () {});

    try {
      _settings = await PomodoroService.getSettings();
      _allTags = await PomodoroService.getTags();
      _deviceId = await StorageService.getDeviceId();
      try {
        final info = await PackageInfo.fromPlatform();
        _appVersion = info.version;
      } catch (e) {}

      //debugPrint('[PomodoroWorkbench] StorageService.getTodos() start');
      try {
        final todosRaw = await StorageService.getTodos(widget.username)
            .timeout(const Duration(seconds: 5), onTimeout: () {
          return <TodoItem>[];
        });
        _todos = (todosRaw).where((t) => !t.isDeleted && !t.isDone).toList();

        final groupsRaw = await StorageService.getTodoGroups(widget.username)
            .timeout(const Duration(seconds: 5), onTimeout: () => <TodoGroup>[]);
        _todoGroups = groupsRaw.where((g) => !g.isDeleted).toList();
      } catch (e) {
        _todos = [];
        _todoGroups = [];
      }

      PomodoroRunState? saved;
      try {
        saved = await PomodoroService.loadRunState()
            .timeout(const Duration(seconds: 5));
      } on TimeoutException catch (_) {
        saved = null;
      } catch (e) {
        saved = null;
      }

      if (saved != null && saved.phase != PomodoroPhase.idle) {
        try {
          try {
            await _recoverState(saved).timeout(const Duration(seconds: 5));
          } on TimeoutException catch (_) {}
        } catch (e) {}
      } else {
        try {
          SharedPreferences? prefs;
          try {
            prefs = await SharedPreferences.getInstance()
                .timeout(const Duration(seconds: 5));
          } catch (e) {
            prefs = null;
          }
          if (prefs != null) {
            final savedUuid = prefs.getString(_keyBoundTodoUuid);
            final savedTitle = prefs.getString(_keyBoundTodoTitle);
            final savedTagsRaw = prefs.getString(_keySelectedTagUuids);

            final restoredTagUuids = savedTagsRaw != null &&
                    savedTagsRaw.isNotEmpty
                ? savedTagsRaw.split(',').where((s) => s.isNotEmpty).toList()
                : <String>[];

            TodoItem? restoredTodo;
            if (savedUuid != null && savedUuid.isNotEmpty) {
              restoredTodo = _todos
                  .cast<TodoItem?>()
                  .firstWhere((t) => t?.id == savedUuid, orElse: () => null);
              if (restoredTodo == null &&
                  savedTitle != null &&
                  savedTitle.isNotEmpty) {
                restoredTodo = TodoItem(
                    id: savedUuid,
                    title: savedTitle,
                    isDone: false,
                    createdAt: 0);
              }
            }
            if (mounted) {
              setState(() {
                _remainingSeconds = _settings.mode == TimerMode.countUp
                    ? 0
                    : _settings.focusMinutes * 60;
                _boundTodo = restoredTodo;
                _selectedTagUuids = restoredTagUuids;
              });
              // 🚀 补擦除逻辑：初始状态为闲置
              _syncService.setLocalFocusing(false);
            }
          }
        } catch (e) {}
      }

      try {
        try {
          await _connectCrossDevice().timeout(const Duration(seconds: 5));
        } on TimeoutException catch (_) {}
      } catch (e) {}

      await Future.delayed(const Duration(milliseconds: 400));

      if (mounted) {
        setState(() => _initializing = false);
        widget.onReady?.call();
        _showLocalFloat();

        if (_userId.isNotEmpty && _deviceId.isNotEmpty) {
          debugPrint('[PomodoroWorkbench] _syncService.forceReconnect() start');
          try {
            try {
              await _syncService
                  .forceReconnect(_userId, 'flutter_$_deviceId')
                  .timeout(const Duration(seconds: 5));
            } on TimeoutException catch (_) {}
          } catch (e) {}
        }
      }
    } finally {
      _isInitProcessing = false;
      initWatchdog.cancel();
      final elapsed = DateTime.now().difference(initStart).inMilliseconds;
    }
  }

  Future<void> _connectCrossDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final userIdInt = prefs.getInt('current_user_id');
    if (userIdInt == null || _deviceId.isEmpty) return;
    _userId = userIdInt.toString();

    _crossDeviceSub?.cancel();
    _crossDeviceSub =
        _syncService.onStateChanged.listen(_handleCrossDeviceSignal);

    _connSub?.cancel();
    _connSub = _syncService.onConnectionChanged.listen((state) {
      if (!mounted) return;
      setState(() {
        _syncConnState = state;
        _wsConnected = state == SyncConnectionState.connected;
      });
      // debugPrint('[工作台] 同步通道连接状态变更: $state');
    });

    // 🍅 发起端重连后，服务端回推了历史专注状态
    // 若本地已无对应状态，则通知云端清除残留
    _syncService.onStaleSyncFocus = (state) async {
      // debugPrint('[工作台] 收到服务端回推的残留状态，校验本地...');
      final saved = await PomodoroService.loadRunState();
      if (saved == null ||
          (saved.phase != PomodoroPhase.focusing &&
              saved.phase != PomodoroPhase.breaking)) {
        // debugPrint('[工作台] 本地无运行中的专注，发送 CLEAR_FOCUS 清除云端残留');
        _syncService.sendClearFocusSignal();
      } else {
        // debugPrint('[工作台] 本地仍有运行中的专注，保留云端状态');
      }
    };

    // 🚀 获取 auth token 用于 WebSocket 鉴权
    String? authToken = ApiService.getToken();

    await _syncService.forceReconnect(_userId, 'flutter_$_deviceId',
        authToken: authToken, appVersion: _appVersion);

    if (mounted) setState(() => _wsConnected = true);
  }

  void _handleCrossDeviceSignal(CrossDevicePomodoroState signal) async {
    if (!mounted || _initializing) return;

    final myDeviceId = 'flutter_$_deviceId';
    if (_deviceId.isEmpty ||
        (signal.sourceDevice != null && signal.sourceDevice == myDeviceId)) {
      return;
    }

    switch (signal.action) {
      case 'UPDATE_AVAILABLE':
        if (!_hasShownUpdate && mounted && signal.manifestData != null) {
          _hasShownUpdate = true;
          final manifest = AppManifest.fromJson(signal.manifestData!);
          PackageInfo packageInfo = await PackageInfo.fromPlatform();
          if (!mounted) return;
          UpdateService.showUpdateDialog(context, manifest, packageInfo.version,
              hasUpdate: true);
        }
        break;

      case 'START':
      case 'SYNC':
      case 'SYNC_FOCUS':
      case 'RECONNECT_SYNC':
        if (signal.sessionUuid != null &&
            signal.sessionUuid == _currentSessionUuid) {
          break;
        }
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
            final plannedSecs = signal.duration ?? (_settings.focusMinutes * 60);
            rem = plannedSecs - (signal.serverElapsedMs! ~/ 1000);
            if (rem < 0) rem = 0;
            localTargetEnd = nowMs + (rem * 1000);
          }
        } else {
          // 降级逻辑
          if (isCountUp) {
            final referenceMs = isPaused ? (signal.pausedAtMs ?? timestamp) : nowMs;
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
                createdAt: 0)
            : null;

        setState(() {
          _phase = PomodoroPhase.remoteWatching;
          _targetEndMs = isCountUp ? 0 : localTargetEnd; // 仅倒计时需要此标记
          _sessionStartMs = isCountUp ? localSessionStart : 0;
          _remainingSeconds = rem;
          _isPaused = isPaused;
          _pausedAtMs = signal.pausedAtMs ?? 0;
          _accumulatedMs = acc;
          _pauseStartMs = signal.pauseStartMs ?? _pausedAtMs;
          _boundTodo = remoteTodo;
          _remoteState = signal;
          _remoteTagNames = signal.tags;
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
        if (mounted) setState(() => _remoteTagNames = signal.tags);
        break;

      case 'PAUSE':
        if (_phase != PomodoroPhase.remoteWatching) break;
        if (mounted) {
          setState(() {
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
        if (_phase != PomodoroPhase.remoteWatching && _phase != PomodoroPhase.idle) break;
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
              final plannedSecs = signal.duration ?? (_settings.focusMinutes * 60);
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

          setState(() {
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

            if (signal.todoTitle != null && signal.todoTitle!.isNotEmpty) {
              _boundTodo = TodoItem(
                  id: signal.todoUuid ?? '',
                  title: signal.todoTitle!,
                  isDone: false,
                  createdAt: 0);
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
      case 'CLEAR_FOCUS':
      case 'FOCUS_DISCONNECTED':
        // 🚀 遵从“本地计时优先”原则：只有在远程观察模式下，才接受外部的停止信号
        if (_phase != PomodoroPhase.remoteWatching) break;

        // 🚀 精准匹配：如果信号中包含 ID，必须与当前观察的 ID 一致才停止
        if (signal.sessionUuid != null && _currentSessionUuid != signal.sessionUuid) break;
        if (signal.todoUuid != null && _boundTodo?.id != signal.todoUuid) break;

        if (_phase == PomodoroPhase.idle || _phase == PomodoroPhase.finished) break;
        _stopRemoteTicker();
        setState(() {
          _phase = PomodoroPhase.idle;
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

          setState(() {
            _boundTodo = (signal.todoTitle != null && signal.todoTitle!.isNotEmpty)
                ? TodoItem(
                    id: signal.todoUuid ?? '',
                    title: signal.todoTitle!,
                    isDone: false,
                    createdAt: 0,
                  )
                : null;
            _currentSessionUuid = signal.sessionUuid ?? _currentSessionUuid;
            if (isCountUp) {
              int elapsed = ((DateTime.now().millisecondsSinceEpoch - newTimestamp) / 1000).floor();
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
        setState(() => _remainingSeconds = elapsed);
      } else {
        final rem =
            ((targetEndMs - DateTime.now().millisecondsSinceEpoch) / 1000)
                .ceil();
        // 增加 2 秒容错缓冲，防止由于两端时钟微小偏差导致远端提前退出
        if (rem < -2) {
          _remoteTicker?.cancel();
          setState(() {
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
          setState(() => _remainingSeconds = rem < 0 ? 0 : rem);
        }
      }
    });
  }

  void _stopRemoteTicker() {
    _remoteTicker?.cancel();
    _remoteTicker = null;
  }

  Future<void> _persistIdleBoundTodo(TodoItem? todo,
      {List<String>? tagUuids}) async {
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

  Future<void> _recoverState(PomodoroRunState saved) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final bool isCountUp = saved.mode == TimerMode.countUp;
    final int savedAccumulated = saved.accumulatedMs;
    int remaining;
    if (isCountUp) {
      if (saved.isPaused == true) {
        remaining =
            (((saved.pausedAtMs - saved.sessionStartMs) - savedAccumulated) /
                    1000)
                .floor();
      } else {
        remaining =
            (((now - saved.sessionStartMs) - savedAccumulated) / 1000).floor();
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
              createdAt: 0);
        }
      }
      if (mounted) {
        setState(() {
          _phase = saved.phase;
          _currentSessionUuid = saved.sessionUuid ?? const Uuid().v4();
          _targetEndMs = saved.targetEndMs;
          _remainingSeconds = remaining;
          _currentCycle = saved.currentCycle;
          _settings.focusMinutes = saved.focusSeconds ~/ 60;
          _settings.breakMinutes = saved.breakSeconds ~/ 60;
          _settings.cycles = saved.totalCycles;
          _settings.mode = saved.mode;
          _boundTodo = boundTodo;
          _selectedTagUuids = saved.tagUuids;
          _sessionStartMs = saved.sessionStartMs;
          _isPaused = saved.isPaused ?? false;
          _pausedAtMs = saved.pausedAtMs ?? 0;
          _accumulatedMs = saved.accumulatedMs ?? 0;
          _pauseStartMs = saved.pauseStartMs;
        });
        _syncService.setLocalFocusing(true);
        widget.onPhaseChanged(_phase);
        _pushPomodoroNotification(overrideRemaining: remaining);
        _showLocalFloat();
        if (saved.isPaused == true) {
          _ticker?.cancel();
          _startPauseTicker();
        } else {
          _startTicker();
        }
        if (!isCountUp) {
          _scheduleReminders(saved.targetEndMs, saved.phase, saved.todoTitle,
              saved.currentCycle, saved.totalCycles);
        }
      }
    }
  }

  void _scheduleReminders(
      int endMs, PomodoroPhase phase, String? todoTitle, int cycle, int total) {
    final isFocusing = phase == PomodoroPhase.focusing;
    final alarmNotifId = isFocusing ? 40001 : 40002;
    final alarmTitle = isFocusing ? '🍅 专注时间到！' : '☕ 休息结束，继续出发！';
    final alarmText = isFocusing
        ? (todoTitle != null && todoTitle.isNotEmpty
            ? '"$todoTitle" 专注时段已结束'
            : '本轮专注已结束，做个总结吧')
        : '第 $cycle/$total 轮完成，下一轮专注准备好了';
    NotificationService.scheduleReminders([
      {
        'triggerAtMs': endMs,
        'title': alarmTitle,
        'text': alarmText,
        'notifId': alarmNotifId,
      }
    ]);
  }

  Future<void> _recoverFromBackground() async {
    if (_phase == PomodoroPhase.focusing || _phase == PomodoroPhase.breaking) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final bool isCountUp = _settings.mode == TimerMode.countUp;

      int remaining;
      if (isCountUp) {
        if (_isPaused) {
          remaining =
              ((_pausedAtMs - _sessionStartMs - _accumulatedMs) / 1000).floor();
        } else {
          remaining =
              (((now - _sessionStartMs) - _accumulatedMs) / 1000).floor();
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
        setState(() => _remainingSeconds = remaining);
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
        boundTodo = _todos
            .cast<TodoItem?>()
            .firstWhere((t) => t?.id == saved.todoUuid, orElse: () => null);
        if (boundTodo == null &&
            saved.todoTitle != null &&
            saved.todoTitle!.isNotEmpty) {
          boundTodo = TodoItem(
              id: saved.todoUuid!,
              title: saved.todoTitle!,
              isDone: false,
              createdAt: 0);
        }
      }
      setState(() {
        _phase = PomodoroPhase.idle;
        _currentCycle = saved.currentCycle;
        _boundTodo = boundTodo;
        _selectedTagUuids = saved.tagUuids;
        _remainingSeconds = _settings.focusMinutes * 60;
      });
      await PomodoroService.clearRunState();
      await _askCompletionAndRecord(
        sessionUuid: saved.sessionUuid ?? const Uuid().v4(),
        durationSeconds: saved.focusSeconds,
        startMs: saved.sessionStartMs,
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
        boundTodo = _todos
            .cast<TodoItem?>()
            .firstWhere((t) => t?.id == saved.todoUuid, orElse: () => null);
        if (boundTodo == null &&
            saved.todoTitle != null &&
            saved.todoTitle!.isNotEmpty) {
          boundTodo = TodoItem(
              id: saved.todoUuid!,
              title: saved.todoTitle!,
              isDone: false,
              createdAt: 0);
        }
      }
      await _persistIdleBoundTodo(boundTodo, tagUuids: saved.tagUuids);
      await PomodoroService.clearRunState();
      if (mounted) {
        setState(() {
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

  void _pushPomodoroNotification(
      {int? overrideRemaining, String alertKey = ''}) {
    final remaining = overrideRemaining ?? _remainingSeconds;
    final tagNames = _allTags
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
    );
  }

  void _startTicker() {
    _ticker?.cancel();
    _notifyTickCount = 0;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
      // debugPrint('[Ticker] Tick fired, _isPaused: $_isPaused, _phase: $_phase');
      if (!mounted) return;
      if (_phase != PomodoroPhase.focusing && _phase != PomodoroPhase.breaking) {
        return;
      }
      if (_isPaused) {
        // debugPrint('[Ticker] Skipping tick because _isPaused is true');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final bool isCountUp = _phase == PomodoroPhase.focusing &&
          _settings.mode == TimerMode.countUp;

      // debugPrint(
      //     '[Ticker] About to compute elapsed, _sessionStartMs: $_sessionStartMs, _accumulatedMs: $_accumulatedMs, now: $now');
      if (isCountUp) {
        final elapsed =
            (((now - _sessionStartMs) - _accumulatedMs) / 1000).floor();
        // debugPrint(
        //     '[Ticker] countUp elapsed: $elapsed, _remainingSeconds before setState: $_remainingSeconds');
        if (_isPaused) {
          // debugPrint('[Ticker] CRITICAL: Ticker tried to update while _isPaused=true. Skipping.');
        } else {
          setState(() {
            _remainingSeconds = elapsed;
            // debugPrint('[Ticker] Set _remainingSeconds to $elapsed');
          });
        }
        _notifyTickCount++;
        if (_notifyTickCount >= 60) {
          _notifyTickCount = 0;
          _pushPomodoroNotification(overrideRemaining: elapsed);
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
          setState(() => _remainingSeconds = remaining);
          _notifyTickCount++;
          final int interval = remaining <= 60 ? 1 : 60;
          if (_notifyTickCount >= interval) {
            _notifyTickCount = 0;
            _pushPomodoroNotification(overrideRemaining: remaining);
          }
        }
      }
    });
  }

  void _startPauseTicker() {
    _pauseTicker?.cancel();
    _pauseTicker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        _pauseElapsedSecs =
            (DateTime.now().millisecondsSinceEpoch - _pauseStartMs) ~/ 1000;
      });
    });
  }

  void _pauseFocus() {
    // debugPrint(
    //     '[Pause] _pauseFocus called, current _isPaused: $_isPaused, phase: $_phase');
    if (_phase != PomodoroPhase.focusing || _isPaused) {
      // debugPrint('[Pause] Early return, condition failed');
      return;
    }
    // debugPrint('[Pause] About to cancel ticker');
    _ticker?.cancel();
    // debugPrint(
    //     '[Pause] Ticker cancelled, setting _pausedAtMs and _pauseStartMs');
    _pausedAtMs = DateTime.now().millisecondsSinceEpoch;
    _pauseStartMs = DateTime.now().millisecondsSinceEpoch;

    if (_settings.mode == TimerMode.countUp) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final elapsed = ((now - _sessionStartMs) - _accumulatedMs);
      debugPrint('[Pause] countUp mode: elapsed=$elapsed');
      _targetEndMs = _sessionStartMs + elapsed;
    }

    debugPrint('[Pause] About to setState, _isPaused will be set to true');
    setState(() {
      _isPaused = true;
    });
    _startPauseTicker();
    debugPrint('[Pause] LOCKED. _pausedAtMs: $_pausedAtMs, _accumulatedMs: $_accumulatedMs');
    debugPrint('[Pause] After setState, calling notifications');
    _pushPomodoroNotification();
    _showLocalFloat();
    PomodoroService.saveRunState(PomodoroRunState(
      phase: _phase,
      sessionUuid: _currentSessionUuid,
      targetEndMs: _targetEndMs,
      currentCycle: _currentCycle,
      totalCycles: _settings.cycles,
      focusSeconds:
          _settings.mode == TimerMode.countUp ? 0 : _settings.focusMinutes * 60,
      breakSeconds: _settings.breakMinutes * 60,
      todoUuid: _boundTodo?.id,
      todoTitle: _boundTodo?.title,
      tagUuids: _selectedTagUuids,
      sessionStartMs: _sessionStartMs,
      plannedFocusSeconds:
          _settings.mode == TimerMode.countUp ? 0 : _settings.focusMinutes * 60,
      mode: _settings.mode,
      isPaused: true,
      pausedAtMs: _pausedAtMs,
      accumulatedMs: _accumulatedMs,
      pauseStartMs: _pauseStartMs,
    ));
    _syncService.sendPauseSignal(
      sessionUuid: _currentSessionUuid,
      pausedAtMs: _pausedAtMs,
      accumulatedMs: _accumulatedMs,
      pauseStartMs: _pauseStartMs,
    );
  }

  Future<void> _resumeFocus() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    debugPrint('[Resume] _resumeFocus called');
    if (_pausedAtMs > 0) {
      final pauseDuration = now - _pausedAtMs;
      _accumulatedMs += pauseDuration;
      debugPrint('[Resume] UPDATED. pauseDuration: $pauseDuration, new _accumulatedMs: $_accumulatedMs');

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
        );
      }
    }

    debugPrint('[Resume] Settings _isPaused=false and starting ticker');
    setState(() {
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
    );
    await PomodoroService.saveRunState(PomodoroRunState(
      phase: _phase,
      sessionUuid: _currentSessionUuid,
      targetEndMs: _targetEndMs,
      currentCycle: _currentCycle,
      totalCycles: _settings.cycles,
      focusSeconds:
          _settings.mode == TimerMode.countUp ? 0 : _settings.focusMinutes * 60,
      breakSeconds: _settings.breakMinutes * 60,
      todoUuid: _boundTodo?.id,
      todoTitle: _boundTodo?.title,
      tagUuids: _selectedTagUuids,
      sessionStartMs: _sessionStartMs,
      plannedFocusSeconds:
          _settings.mode == TimerMode.countUp ? 0 : _settings.focusMinutes * 60,
      mode: _settings.mode,
      isPaused: false,
      pausedAtMs: 0,
      accumulatedMs: _accumulatedMs,
    ));
  }

  void _showPauseDialog() {
    _pauseFocus();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          // 在对话框内部也启动一个定时器或者收听外部状态
          // 最简单的办法是使用 Timer.periodic 更新对话框内部状态
          return AlertDialog(
            title: const Text('⏸️ 已暂停'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_boundTodo != null
                    ? '正在专注: "${_boundTodo!.title}"'
                    : '自由专注中'),
                const SizedBox(height: 12),
                Text(_settings.mode == TimerMode.countUp
                    ? '已累计专注: ${_formatSeconds(_remainingSeconds)}'
                    : '还需持续专注: ${_formatSeconds(_remainingSeconds)}'),
                const SizedBox(height: 8),
                // 使用外部已经有的 _pauseElapsedSecs，
                // 但为了让弹窗自刷新，我们需要在弹窗建立时也跑一个微型 Timer
                _PauseTimerText(pauseStartMs: _pauseStartMs),
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
                style:
                    FilledButton.styleFrom(backgroundColor: Colors.red.shade400),
                onPressed: () {
                  Navigator.pop(ctx);
                  _abandonFocus();
                },
                child: const Text('结束专注'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatSeconds(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) return '$h小时${m > 0 ? "$m分" : ""}';
    if (m > 0) return '$m分${s > 0 ? "$s秒" : ""}';
    return '$s秒';
  }

  Future<void> _startFocus() async {
    final bool isCountUp = _settings.mode == TimerMode.countUp;
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
        localTodo = _todos
            .cast<TodoItem?>()
            .firstWhere((t) => t?.id == savedUuid, orElse: () => null);
        if (localTodo == null && savedTitle != null && savedTitle.isNotEmpty) {
          localTodo = TodoItem(
              id: savedUuid, title: savedTitle, isDone: false, createdAt: 0);
        }
      }
      _boundTodo = localTodo;
      _remoteState = null;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final durationMs = isCountUp ? 0 : _settings.focusMinutes * 60 * 1000;
    final end = isCountUp ? now : now + durationMs;
    _currentSessionUuid = const Uuid().v4();
    _isPaused = false;
    _pausedAtMs = 0;
    _accumulatedMs = 0;

    setState(() {
      _phase = PomodoroPhase.focusing;
      _targetEndMs = end;
      _remainingSeconds = 0;
      _sessionStartMs = now;
      _remoteState = null;
    });
    _stopRemoteTicker();
    _syncService.setLocalFocusing(true);
    widget.onPhaseChanged(_phase);
    _pushPomodoroNotification(alertKey: 'pomo_start_$end');
    _showLocalFloat();
    _startTicker();

    if (!isCountUp) {
      _scheduleReminders(end, PomodoroPhase.focusing, _boundTodo?.title,
          _currentCycle, _settings.cycles);
    }

    PomodoroService.saveRunState(PomodoroRunState(
      phase: PomodoroPhase.focusing,
      sessionUuid: _currentSessionUuid,
      targetEndMs: end,
      currentCycle: _currentCycle,
      totalCycles: _settings.cycles,
      focusSeconds: isCountUp ? 0 : _settings.focusMinutes * 60,
      breakSeconds: _settings.breakMinutes * 60,
      todoUuid: _boundTodo?.id,
      todoTitle: _boundTodo?.title,
      tagUuids: _selectedTagUuids,
      sessionStartMs: now,
      plannedFocusSeconds: isCountUp ? 0 : _settings.focusMinutes * 60,
      mode: _settings.mode,
      isPaused: false,
      pausedAtMs: 0,
      accumulatedMs: 0,
    ));

    _persistIdleBoundTodo(null);
    final allTags = await PomodoroService.getTags();
    final tagNames = _selectedTagUuids
        .map((uuid) =>
            allTags.where((t) => t.uuid == uuid).firstOrNull?.name ?? '')
        .where((n) => n.isNotEmpty)
        .toList();

    _syncService.sendStartSignal(
      sessionUuid: _currentSessionUuid,
      todoUuid: (_boundTodo?.id.isNotEmpty == true) ? _boundTodo!.id : null,
      todoTitle: _boundTodo?.title,
      durationSeconds: isCountUp ? 0 : _settings.focusMinutes * 60,
      targetEndMs: end,
      tagNames: tagNames,
      mode: _settings.mode.index,
      customTimestamp: _sessionStartMs,
    );

    // 同步到手环
    final pomodoroData = [
      {
        'sessionUuid': _currentSessionUuid,
        'phase': PomodoroPhase.focusing.index,
        'targetEndMs': end,
        'currentCycle': _currentCycle,
        'totalCycles': _settings.cycles,
        'focusSeconds': isCountUp ? 0 : _settings.focusMinutes * 60,
        'breakSeconds': _settings.breakMinutes * 60,
        'todoUuid': _boundTodo?.id,
        'todoTitle': _boundTodo?.title,
        'tagUuids': _selectedTagUuids,
        'tagNames': tagNames.map((n) => {'name': n}).toList(),
        'sessionStartMs': now,
        'plannedFocusSeconds': isCountUp ? 0 : _settings.focusMinutes * 60,
        'isCountUp': isCountUp,
        'mode': _settings.mode.index,
      }
    ];
    BandSyncService.syncPomodoro(pomodoroData);
  }

  Future<void> _switchTask(TodoItem? newTodo) async {
    if (_phase != PomodoroPhase.focusing) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final actualSeconds = ((now - _sessionStartMs) / 1000).round();

    final oldTodo = _boundTodo;

    setState(() {
      _boundTodo = newTodo;
      _sessionStartMs = now;
    });
    _pushPomodoroNotification();
    _showLocalFloat(); // 🚀 关键：切换任务后刷新悬浮窗标题

    if (actualSeconds > 5) {
      final isCountUp = _settings.mode == TimerMode.countUp;
      PomodoroService.addRecord(PomodoroRecord(
        uuid: _currentSessionUuid,
        todoUuid: oldTodo?.id,
        todoTitle: oldTodo?.title,
        tagUuids: List.from(_selectedTagUuids),
        startTime: now - actualSeconds * 1000,
        endTime: now,
        plannedDuration: isCountUp ? 0 : _settings.focusMinutes * 60,
        actualDuration: actualSeconds,
        status: PomodoroRecordStatus.switched,
        deviceId: _deviceId.isNotEmpty ? _deviceId : null,
      ));
    }

    _currentSessionUuid = const Uuid().v4();
    final isCountUpNow = _settings.mode == TimerMode.countUp;
    if (isCountUpNow) {
      setState(() => _remainingSeconds = 0); // 🚀 本端也显式清零
    }
    await _saveCurrentRunState();

    _syncService.sendSwitchSignal(
        todoUuid: newTodo?.id,
        todoTitle: newTodo?.title,
        sessionUuid: _currentSessionUuid);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(newTodo != null
              ? '已切换至: ${newTodo.title}'
              : '已切换为自由专注'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _finishEarly() async {
    if (_isHandlingEnd) return;
    _isHandlingEnd = true;
    try {
      _ticker?.cancel();
      _isPaused = false;
      _pausedAtMs = 0;
      _accumulatedMs = 0;
      NotificationService.cancelNotification();
      NotificationService.cancelReminder(40001);
      NotificationService.cancelReminder(40002);
      final now = DateTime.now().millisecondsSinceEpoch;
      final actualSeconds = ((now - _sessionStartMs) / 1000).round();
      final isCountUp = _settings.mode == TimerMode.countUp;

      await _persistIdleBoundTodo(_boundTodo);
      await PomodoroService.clearRunState();
      _syncService.sendStopSignal(todoUuid: _boundTodo?.id);
      // 🚀 Notify island to switch to idle immediately
      await FloatWindowService.update(endMs: 0, isLocal: true);

      await _askCompletionAndRecord(
        sessionUuid: _currentSessionUuid,
        durationSeconds: actualSeconds,
        startMs: _sessionStartMs,
        endMs: now,
        isCountUp: isCountUp,
      );
      NotificationService.sendPomodoroEndAlert(
          alertKey: 'pomo_end_$now',
          todoTitle: _boundTodo?.title,
          isBreak: false);
      await _proceedAfterRecord();
    } finally {
      _isHandlingEnd = false;
    }
  }

  Future<void> _onFocusEnd() async {
    if (_isHandlingEnd) return;
    _isHandlingEnd = true;
    try {
      NotificationService.cancelReminder(40001);
      final now = DateTime.now().millisecondsSinceEpoch;
      final isCountUp = _settings.mode == TimerMode.countUp;
      await _persistIdleBoundTodo(_boundTodo);
      await PomodoroService.clearRunState();
      _syncService.sendStopSignal(todoUuid: _boundTodo?.id);
      // 🚀 Notify island to switch to idle immediately
      await FloatWindowService.update(endMs: 0, isLocal: true);
      await _askCompletionAndRecord(
        sessionUuid: _currentSessionUuid,
        durationSeconds: isCountUp
            ? ((now - _sessionStartMs) / 1000).round()
            : _settings.focusMinutes * 60,
        startMs: _sessionStartMs,
        endMs: now,
        isCountUp: isCountUp,
      );
      NotificationService.sendPomodoroEndAlert(
          alertKey: 'pomo_end_$now',
          todoTitle: _boundTodo?.title,
          isBreak: false);
      await _proceedAfterRecord();
    } finally {
      _isHandlingEnd = false;
    }
  }

  Future<bool> _askCompletionAndRecord(
      {required String sessionUuid,
      required int durationSeconds,
      required int startMs,
      required int endMs,
      bool isCountUp = false}) async {
    if (!mounted) return false;

    int editedDuration = durationSeconds;
    final durationCtrl =
        TextEditingController(text: (durationSeconds ~/ 60).toString());

    final completed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(isCountUp ? '📈 记录专注' : '🍅 专注完成！'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_boundTodo != null
                ? '"${_boundTodo!.title}" 是否已完成？'
                : '专注时段已结束，该任务是否已完成？'),
            if (isCountUp) ...[
              const SizedBox(height: 20),
              const Text('修改计时时长 (分钟):',
                  style: TextStyle(fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 8),
              TextField(
                controller: durationCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () {
                if (isCountUp) {
                  final mins = int.tryParse(durationCtrl.text) ??
                      (durationSeconds ~/ 60);
                  editedDuration = mins * 60;
                }
                Navigator.pop(ctx, false);
              },
              child: const Text('未完成')),
          FilledButton(
              onPressed: () {
                if (isCountUp) {
                  final mins = int.tryParse(durationCtrl.text) ??
                      (durationSeconds ~/ 60);
                  editedDuration = mins * 60;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('已完成 ✓'))
        ],
      ),
    );
    final record = PomodoroRecord(
      uuid: sessionUuid,
      todoUuid: (_boundTodo?.id.isNotEmpty == true) ? _boundTodo!.id : null,
      todoTitle: _boundTodo?.title,
      tagUuids: List.from(_selectedTagUuids),
      startTime: startMs,
      endTime: isCountUp ? startMs + editedDuration * 1000 : endMs,
      plannedDuration: isCountUp ? 0 : _settings.focusMinutes * 60,
      actualDuration: editedDuration,
      status: (completed ?? false)
          ? PomodoroRecordStatus.completed
          : PomodoroRecordStatus.interrupted,
      deviceId: _deviceId.isNotEmpty ? _deviceId : null,
    );
    PomodoroService.addRecord(record);
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
        setState(() => _todos[localIdx].isDone = true);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('✅ "${_boundTodo!.title}" 已标记完成'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating));
      }
    }
    return completed ?? false;
  }

  Future<void> _proceedAfterRecord() async {
    if (!mounted) return;
    final isCountUp = _settings.mode == TimerMode.countUp;
    if (!isCountUp && _currentCycle < _settings.cycles) {
      await _startBreak();
    } else {
      setState(() {
        _phase = PomodoroPhase.finished;
        _currentCycle = 1;
        _remainingSeconds = isCountUp ? 0 : _settings.focusMinutes * 60;
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
    setState(() {
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
    _scheduleReminders(end, PomodoroPhase.breaking, _boundTodo?.title,
        _currentCycle, _settings.cycles);
    await _saveCurrentRunState();
  }

  Future<void> _onBreakEnd() async {
    if (_isHandlingEnd) return;
    _isHandlingEnd = true;
    try {
      NotificationService.cancelReminder(40002);
      NotificationService.sendPomodoroEndAlert(
          alertKey: 'pomo_end_$_targetEndMs',
          todoTitle: _boundTodo?.title,
          isBreak: true);
      setState(() {
        _phase = PomodoroPhase.idle;
        _currentCycle += 1;
        _remainingSeconds = _settings.mode == TimerMode.countUp
            ? 0
            : _settings.focusMinutes * 60;
      });
      _syncService.setLocalFocusing(false);
      widget.onPhaseChanged(_phase);
      PomodoroService.clearRunState();
      await _persistIdleBoundTodo(_boundTodo);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('☕ 休息结束，准备开始下一轮！'),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating));
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
      bool confirm = skipDialog;
      if (!skipDialog) {
        final res = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('放弃本次专注？'),
            content: const Text('本次专注记录将被丢弃。'),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('继续专注')),
              FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade400),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('放弃')),
            ],
          ),
        );
        confirm = res == true;
      }
      if (confirm) {
        NotificationService.cancelNotification();
        NotificationService.cancelReminder(40001);
        NotificationService.cancelReminder(40002);
        _syncService.sendStopSignal(todoUuid: _boundTodo?.id);
        // 🚀 Notify island to switch to idle immediately
        await FloatWindowService.update(endMs: 0, isLocal: true);
        final isCountUpMode = _settings.mode == TimerMode.countUp;
        setState(() {
          _phase = PomodoroPhase.idle;
          _currentCycle = 1;
          _remainingSeconds = isCountUpMode ? 0 : _settings.focusMinutes * 60;
        });
        _syncService.setLocalFocusing(false);
        widget.onPhaseChanged(_phase);
        _persistIdleBoundTodo(_boundTodo);
        PomodoroService.clearRunState();
      } else {
        _startTicker();
      }
    } finally {
      _isHandlingEnd = false;
    }
  }

  // 公开方法：供外部调用提前完成
  void handleFinishEarly() {
    _finishEarly();
  }

  // 公开方法：供外部调用放弃专注
  void handleAbandonFocus() {
    _abandonFocus();
  }

  void _showSettingsDialog() {
    final focusCtrl =
        TextEditingController(text: _settings.focusMinutes.toString());
    final breakCtrl =
        TextEditingController(text: _settings.breakMinutes.toString());
    final cyclesCtrl = TextEditingController(text: _settings.cycles.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⚙️ 番茄钟设置'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final f = int.tryParse(focusCtrl.text) ?? 25;
              final b = int.tryParse(breakCtrl.text) ?? 5;
              final c = int.tryParse(cyclesCtrl.text) ?? 4;
              final ns = PomodoroSettings(
                  focusMinutes: f.clamp(1, 120),
                  breakMinutes: b.clamp(1, 60),
                  cycles: c.clamp(1, 20));
              await PomodoroService.saveSettings(ns);
              setState(() {
                _settings = ns;
                if (_phase == PomodoroPhase.idle) {
                  _remainingSeconds =
                      ns.mode == TimerMode.countUp ? 0 : ns.focusMinutes * 60;
                }
              });
              if (ctx.mounted) Navigator.pop(ctx);
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
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12)));
  }

  void _showTagsDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => TagManagerSheet(
        allTags: _allTags,
        selectedUuids: _selectedTagUuids,
        onChanged: (tags, selected) async {
          await PomodoroService.saveTags(tags);
          PomodoroService.syncTagsToCloud().catchError((_) => null);
          setState(() {
            _allTags = tags;
            _selectedTagUuids = selected;
          });
          await _persistIdleBoundTodo(_boundTodo);
          await _saveCurrentRunState();
          _showLocalFloat();
          if (_phase == PomodoroPhase.focusing) {
            final tagNames = tags
                .where((t) => selected.contains(t.uuid))
                .map((t) => t.name)
                .toList();
            _syncService.sendUpdateTagsSignal(tagNames);
          }
        },
      ),
    );
  }

  void _showBindTodoDialog({bool isSwitching = false}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, controller) => Column(
          children: [
            Padding(
                padding: const EdgeInsets.all(20),
                child: Text(isSwitching ? '切换专注任务' : '选择专注任务',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold))),
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
                                : Theme.of(context).colorScheme.surfaceContainerHighest,
                            shape: BoxShape.circle),
                        child: Icon(
                          _boundTodo == null ? Icons.check : Icons.clear,
                          size: 20,
                          color: _boundTodo == null
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        )),
                    title: const Text('不绑定任务（自由专注）'),
                    selected: _boundTodo == null,
                    selectedTileColor: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withOpacity(0.3),
                    onTap: () async {
                      if (_phase == PomodoroPhase.focusing) {
                        await _switchTask(null);
                      } else {
                        setState(() => _boundTodo = null);
                        await _persistIdleBoundTodo(null);
                        await _saveCurrentRunState();
                      }
                      Navigator.pop(ctx);
                    },
                  ),
                  const Divider(height: 1),
                  ...(() {
                    final Map<String?, List<TodoItem>> grouped = {};
                    for (var t in _todos) {
                      grouped.putIfAbsent(t.groupId, () => []).add(t);
                    }

                    List<Widget> sections = [];
                    // Process named groups
                    for (var g in _todoGroups) {
                      final tasks = grouped[g.id];
                      if (tasks != null && tasks.isNotEmpty) {
                        sections.add(_buildSectionHeader(g.name));
                        sections.addAll(tasks.map((t) => _buildTodoTile(ctx, t, isSwitching)));
                        grouped.remove(g.id);
                      }
                    }

                    // Process unassigned tasks
                    if (grouped.containsKey(null)) {
                      final tasks = grouped[null]!;
                      if (tasks.isNotEmpty) {
                        sections.add(_buildSectionHeader('未分组'));
                        sections.addAll(tasks.map((t) => _buildTodoTile(ctx, t, isSwitching)));
                      }
                    }

                    // Safety for any other IDs
                    grouped.forEach((id, tasks) {
                      if (tasks.isNotEmpty) {
                        sections.add(_buildSectionHeader('其他'));
                        sections.addAll(tasks.map((t) => _buildTodoTile(ctx, t, isSwitching)));
                      }
                    });

                    return sections;
                  })(),
                  if (_todos.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(
                            child: Column(children: [
                          Icon(Icons.inbox_outlined,
                              size: 48, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('没有未完成的待办', style: TextStyle(color: Colors.grey))
                        ]))),
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
              shape: BoxShape.circle),
          child: Icon(Icons.check,
              size: 20, color: Theme.of(context).colorScheme.primary)),
      title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: t.remark != null && t.remark!.isNotEmpty
          ? Text(t.remark!, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      selected: t.id == _boundTodo?.id,
      selectedTileColor:
          Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
      onTap: () async {
        Navigator.pop(ctx);
        if (_phase == PomodoroPhase.focusing) {
          await _switchTask(t);
        } else {
          setState(() => _boundTodo = t);
          await _persistIdleBoundTodo(t);
          await _saveCurrentRunState();
        }
      },
    );
  }

  Future<void> _saveCurrentRunState() async {
    if (_phase == PomodoroPhase.idle ||
        _phase == PomodoroPhase.finished ||
        _phase == PomodoroPhase.remoteWatching) {
      return;
    }
    await PomodoroService.saveRunState(PomodoroRunState(
      phase: _phase,
      sessionUuid: _currentSessionUuid,
      targetEndMs: _targetEndMs,
      currentCycle: _currentCycle,
      totalCycles: _settings.cycles,
      focusSeconds:
          _settings.mode == TimerMode.countUp ? 0 : _settings.focusMinutes * 60,
      breakSeconds: _settings.breakMinutes * 60,
      todoUuid: _boundTodo?.id,
      todoTitle: _boundTodo?.title,
      tagUuids: _selectedTagUuids,
      sessionStartMs: _sessionStartMs,
      plannedFocusSeconds:
          _settings.mode == TimerMode.countUp ? 0 : _settings.focusMinutes * 60,
      mode: _settings.mode,
      isPaused: _isPaused,
      pausedAtMs: _pausedAtMs,
      accumulatedMs: _accumulatedMs,
      pauseStartMs: _pauseStartMs,
    ));
  }



  Future<void> _showLocalFloat() async {
    final bool isFocusing = _phase == PomodoroPhase.focusing;
    final bool isRemoteWatching = _phase == PomodoroPhase.remoteWatching;
    final bool isIdle =
        _phase == PomodoroPhase.idle || _phase == PomodoroPhase.finished;

    final tagNames = _allTags
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
      // 🚀 Fix: Forward explicitly to clear the island session state
      // when the local workbench enters idle/finished phase.
      await FloatWindowService.update(endMs: 0, isLocal: true);
    } else {
      await FloatWindowService.update(
        endMs: effectiveEndMs,
        title: displayTitle,
        tags: tagNames,
        isLocal: _phase != PomodoroPhase.remoteWatching,
        mode: mode,
        isPaused: _isPaused,
        accumulatedMs: _accumulatedMs,
        pauseStartMs: _pauseStartMs,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isIdle =
        _phase == PomodoroPhase.idle || _phase == PomodoroPhase.finished;
    final bool isFocusing = _phase == PomodoroPhase.focusing;
    final bool isRemoteWatching = _phase == PomodoroPhase.remoteWatching;
    final Color contentColor = Theme.of(context).colorScheme.onSurface;

    return SafeArea(
      bottom: false,
      child: AnimatedOpacity(
        opacity: _initializing ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
        child: OrientationBuilder(
          builder: (context, orientation) {
            final isLandscape = orientation == Orientation.landscape;

            return Padding(
              padding: EdgeInsets.symmetric(horizontal: isLandscape ? 32 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildHeader(isIdle, isFocusing, isRemoteWatching),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      transitionBuilder: (child, anim) =>
                          FadeTransition(opacity: anim, child: child),
                      child: isLandscape
                          ? _buildLandscapeLayout(isIdle, isFocusing,
                              isRemoteWatching, contentColor)
                          : _buildPortraitLayout(isIdle, isFocusing,
                              isRemoteWatching, contentColor),
                    ),
                  ),
                  if (!isLandscape)
                    const SafeArea(top: false, child: SizedBox(height: 8)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPortraitLayout(
      bool isIdle, bool isFocusing, bool isRemoteWatching, Color contentColor) {
    return Column(
      key: const ValueKey('portrait_layout'),
      children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: isIdle
                ? _buildIdleLayout(contentColor)
                : _buildActiveLayout(
                    isFocusing, isRemoteWatching, contentColor),
          ),
        ),
      ],
    );
  }

  Widget _buildLandscapeLayout(
      bool isIdle, bool isFocusing, bool isRemoteWatching, Color contentColor) {
    return Row(
      key: const ValueKey('landscape_layout'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left side: Timer + Mode Toggle
        Expanded(
          flex: 5,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildImmersiveTimerWidget(),
              // Move mode toggle below the timer in landscape when idle
              if (isIdle) ...[
                const SizedBox(height: 18),
                _buildModeToggle(),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
        const SizedBox(width: 24),
        // Right side: Info and Actions
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Right Actions
              if (isIdle)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.settings_outlined),
                          tooltip: '设置',
                          onPressed: _showSettingsDialog),
                      IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.label_outline),
                          tooltip: '标签',
                          onPressed: _showTagsDialog),
                      _buildSyncLinkButton(),
                    ],
                  ),
                ),

              if (isIdle) ...[
                const Spacer(),
                _buildIdleMiddle(),
                const Spacer(),
              ] else ...[
                const Spacer(),
                _buildTagsList(isRemoteWatching),
                const SizedBox(height: 16),
                WorkbenchTaskArea(
                  isIdle: false,
                  isFocusing: isFocusing,
                  isRemoteWatching: isRemoteWatching,
                  boundTodo: _boundTodo,
                  contentColor: contentColor,
                  onTap: () =>
                      _showBindTodoDialog(isSwitching: _boundTodo != null),
                ),
                const Spacer(flex: 2),
              ],
              _buildActions(isIdle, isFocusing, isRemoteWatching, contentColor),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(bool isIdle, bool isFocusing, bool isRemoteWatching) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return SizedBox(
      height: kToolbarHeight,
      child: Row(
        children: [
          AnimatedOpacity(
            opacity: (isFocusing || isRemoteWatching || isLandscape) ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: IgnorePointer(
              ignoring: !(isFocusing || isRemoteWatching || isLandscape),
              child: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context)),
            ),
          ),
          const Spacer(),
          if (!isLandscape) ...[
            AnimatedOpacity(
              opacity: isIdle ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: IgnorePointer(
                ignoring: !isIdle,
                child: Row(children: [
                  IconButton(
                      icon: const Icon(Icons.settings_outlined),
                      tooltip: '设置',
                      onPressed: _showSettingsDialog),
                  IconButton(
                      icon: const Icon(Icons.label_outline),
                      tooltip: '标签',
                      onPressed: _showTagsDialog),
                ]),
              ),
            ),
            _buildWSStatusIndicator(),
          ],
        ],
      ),
    );
  }

  Widget _buildWSStatusIndicator() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Mode toggle is intentionally moved below the timer; keep only the sync indicator here
        _buildSyncLinkButton(),
      ],
    );
  }

  Widget _buildModeToggle() {
    if (_phase != PomodoroPhase.idle) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SegmentedButton<TimerMode>(
        segments: const [
          ButtonSegment(
              value: TimerMode.countdown,
              label: Text('倒计时', style: TextStyle(fontSize: 12))),
          ButtonSegment(
              value: TimerMode.countUp,
              label: Text('正计时', style: TextStyle(fontSize: 12))),
        ],
        selected: {_settings.mode},
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
        ),
        onSelectionChanged: (s) async {
          setState(() {
            _settings.mode = s.first;
            _remainingSeconds = _settings.mode == TimerMode.countUp
                ? 0
                : _settings.focusMinutes * 60;
          });
          await PomodoroService.saveSettings(_settings);
        },
      ),
    );
  }

  Widget _buildSyncLinkButton() {
    IconData icon;
    Color color;
    String message;
    bool canRetry = false;

    switch (_syncConnState) {
      case SyncConnectionState.connected:
        icon = Icons.link_rounded;
        color = Colors.green;
        message = '跨端同步已连接';
        break;
      case SyncConnectionState.connecting:
        icon = Icons.sync;
        color = Colors.blueAccent;
        message = '正在连接同步通道...';
        break;
      case SyncConnectionState.error:
      case SyncConnectionState.disconnected:
      default:
        icon = Icons.link_off_rounded;
        color = Colors.redAccent.withOpacity(0.8);
        message = '同步连接已断开，点击重试';
        canRetry = true;
    }

    return Tooltip(
      message: message,
      child: InkWell(
        onTap: () {
          // 🚀 强制触发重连
          _syncService.manualReconnect();
          if (_syncConnState != SyncConnectionState.connected) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('正在尝试重新连接同步服务器...'),
                duration: Duration(seconds: 1),
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_syncConnState == SyncConnectionState.connecting)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.blueAccent,
                  ),
                )
              else
                Icon(icon, size: 18, color: color),
              if (canRetry) ...[
                const SizedBox(width: 6),
                Text(
                  '点击重连',
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIdleLayout(Color contentColor) {
    return Column(children: [
      const Spacer(flex: 2),
      _buildImmersiveTimerWidget(),
      // Place mode toggle under the timer in idle state (portrait)
      const SizedBox(height: 12),
      _buildModeToggle(),
      const SizedBox(height: 8),
      _buildIdleMiddle(),
      const Spacer(flex: 3),
      _buildActions(true, false, false, contentColor),
    ]);
  }

  Widget _buildActiveLayout(
      bool isFocusing, bool isRemoteWatching, Color contentColor) {
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      _buildImmersiveTimerWidget(),
      const SizedBox(height: 16),
      _buildTagsList(isRemoteWatching),
      const SizedBox(height: 16),
      WorkbenchTaskArea(
          isIdle: false,
          isFocusing: isFocusing,
          isRemoteWatching: isRemoteWatching,
          boundTodo: _boundTodo,
          contentColor: contentColor,
          onTap: () => _showBindTodoDialog(isSwitching: _boundTodo != null)),
      const SizedBox(height: 24),
      _buildActions(false, isFocusing, isRemoteWatching, contentColor),
    ]);
  }

  Widget _buildImmersiveTimerWidget() {
    final isCountUp = _settings.mode == TimerMode.countUp;
    final isRemoteCountUp = _remoteState?.duration == 0;
    return ImmersiveTimer(
      phase: _phase,
      remainingSeconds: _remainingSeconds,
      focusMinutes: _settings.focusMinutes,
      breakMinutes: _settings.breakMinutes,
      currentCycle: _currentCycle,
      totalCycles: _settings.cycles,
      isCountUp: isCountUp,
      isRemoteCountUp: isRemoteCountUp,
      remoteState: _remoteState,
      isCompact: widget.isCompact,
      isPaused: _isPaused,
      pauseSeconds: _pauseElapsedSecs,
    );
  }

  Widget _buildTagsList(bool isRemoteWatching) {
    if (isRemoteWatching) {
      if (_remoteTagNames.isEmpty) return const SizedBox.shrink();
      return Wrap(
          spacing: 6,
          runSpacing: 4,
          children: _remoteTagNames
              .map((n) => _SimpleTag(name: n, color: Colors.blueAccent))
              .toList());
    }
    final activeTags =
        _allTags.where((t) => _selectedTagUuids.contains(t.uuid)).toList();
    if (activeTags.isEmpty) return const SizedBox.shrink();
    return Wrap(
        spacing: 6,
        runSpacing: 4,
        children: activeTags
            .map((t) => _SimpleTag(name: t.name, color: hexToColor(t.color)))
            .toList());
  }

  Widget _buildIdleMiddle() {
    if (_allTags.isEmpty) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 148),
      child: SingleChildScrollView(
          child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: _allTags.map((tag) {
                final selected = _selectedTagUuids.contains(tag.uuid);
                final color = hexToColor(tag.color);
                return FilterChip(
                  label: Text(tag.name, style: const TextStyle(fontSize: 13)),
                  selected: selected,
                  showCheckmark: false,
                  selectedColor: color.withOpacity(0.2),
                  side: BorderSide(
                      color: selected ? color : Colors.grey.shade300),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  onSelected: (val) async {
                    setState(() {
                      if (val) {
                        _selectedTagUuids.add(tag.uuid);
                      } else {
                        _selectedTagUuids.remove(tag.uuid);
                      }
                    });
                    await _persistIdleBoundTodo(_boundTodo);
                    _showLocalFloat();
                    if (_phase == PomodoroPhase.focusing) {
                      _syncService.sendUpdateTagsSignal(_allTags
                          .where((t) => _selectedTagUuids.contains(t.uuid))
                          .map((t) => t.name)
                          .toList());
                    }
                  },
                );
              }).toList())),
    );
  }

  Widget _buildActions(
      bool isIdle, bool isFocusing, bool isRemoteWatching, Color contentColor) {
    final bool isPaused = _isPaused && _phase == PomodoroPhase.focusing;
    // debugPrint(
    //     '[BuildActions] _isPaused: $_isPaused, _phase: $_phase, isPaused: $isPaused, isFocusing: $isFocusing');
    return WorkbenchActions(
      isIdle: isIdle,
      isFocusing: isFocusing,
      isRemoteWatching: isRemoteWatching,
      phase: _phase,
      boundTodo: _boundTodo,
      onShowBindTodo: _showBindTodoDialog,
      onStartFocus: _startFocus,
      onFinishEarly: _finishEarly,
      onAbandonFocus: _abandonFocus,
      onPauseFocus: isPaused ? null : _pauseFocus,
      onShowPauseDialog: isPaused ? _resumeFocus : _showPauseDialog,
      onSkipBreak: () async {
        _ticker?.cancel();
        NotificationService.cancelNotification();
        NotificationService.cancelReminder(40002);
        await _persistIdleBoundTodo(_boundTodo);
        await PomodoroService.clearRunState();
        setState(() {
          _phase = PomodoroPhase.idle;
          _currentCycle += 1;
          _remainingSeconds = _settings.mode == TimerMode.countUp
              ? 0
              : _settings.focusMinutes * 60;
          _isPaused = false;
          _pausedAtMs = 0;
          _accumulatedMs = 0;
        });
        widget.onPhaseChanged(_phase);
      },
      isCompact: widget.isCompact,
    );
  }
}

class _SimpleTag extends StatelessWidget {
  final String name;
  final Color color;
  const _SimpleTag({required this.name, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.4))),
      child: Text(name,
          style: TextStyle(
              fontSize: 12,
              color: color.withOpacity(0.9),
              fontWeight: FontWeight.w500)),
    );
  }
}
class _PauseTimerText extends StatefulWidget {
  final int pauseStartMs;
  const _PauseTimerText({required this.pauseStartMs});

  @override
  State<_PauseTimerText> createState() => _PauseTimerTextState();
}

class _PauseTimerTextState extends State<_PauseTimerText> {
  Timer? _timer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _update();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) => _update());
  }

  void _update() {
    if (!mounted) return;
    setState(() {
      _seconds = (DateTime.now().millisecondsSinceEpoch - widget.pauseStartMs) ~/
          1000;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _format(int s) {
    if (s < 0) s = 0;
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    return Text('暂停时长: ${_format(_seconds)}');
  }
}
