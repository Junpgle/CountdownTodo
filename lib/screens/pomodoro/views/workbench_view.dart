import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../models.dart';
import '../../../storage_service.dart';
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

class PomodoroWorkbenchState extends State<PomodoroWorkbench>
    with WidgetsBindingObserver {
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
  String _deviceId = '';
  String _userId = '';
  String _appVersion = 'unknown';

  // ── 跨端感知 ──
  final _syncService = PomodoroSyncService();
  StreamSubscription<CrossDevicePomodoroState>? _crossDeviceSub;
  CrossDevicePomodoroState? _remoteState;
  Timer? _remoteTicker;
  List<String> _remoteTagNames = [];

  bool _wsConnected = false;
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
    _runStateSub?.cancel();
    _islandSub?.cancel();
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

  Future<void> _init() async {
    final _initStart = DateTime.now();
    debugPrint(
        '[PomodoroWorkbench] _init start: ${_initStart.toIso8601String()}');
    Timer? _initWatchdog = Timer(const Duration(seconds: 6), () {
      debugPrint('[PomodoroWorkbench] WARNING: _init still running after 6s');
    });

    try {
      debugPrint('[PomodoroWorkbench] getSettings() start');
      _settings = await PomodoroService.getSettings();
      debugPrint('[PomodoroWorkbench] getSettings() done');

      debugPrint('[PomodoroWorkbench] getTags() start');
      _allTags = await PomodoroService.getTags();
      debugPrint(
          '[PomodoroWorkbench] getTags() done (count=${_allTags.length})');

      debugPrint('[PomodoroWorkbench] StorageService.getDeviceId() start');
      _deviceId = await StorageService.getDeviceId();
      debugPrint(
          '[PomodoroWorkbench] StorageService.getDeviceId() done: $_deviceId');

      debugPrint('[PomodoroWorkbench] PackageInfo.fromPlatform() start');
      try {
        final info = await PackageInfo.fromPlatform();
        _appVersion = info.version;
        debugPrint('[PomodoroWorkbench] PackageInfo done: $_appVersion');
      } catch (e, st) {
        debugPrint('[PomodoroWorkbench] PackageInfo failed: $e\n$st');
      }

      debugPrint('[PomodoroWorkbench] StorageService.getTodos() start');
      try {
        final todosRaw = await StorageService.getTodos(widget.username)
            .timeout(const Duration(seconds: 5), onTimeout: () {
          debugPrint(
              '[PomodoroWorkbench] WARNING: StorageService.getTodos() timed out');
          return <TodoItem>[];
        });
        _todos = (todosRaw).where((t) => !t.isDeleted && !t.isDone).toList();
        debugPrint(
            '[PomodoroWorkbench] StorageService.getTodos() done (count=${_todos.length})');
      } catch (e, st) {
        debugPrint('[PomodoroWorkbench] getTodos error: $e\n$st');
        _todos = [];
      }

      debugPrint('[PomodoroWorkbench] PomodoroService.loadRunState() start');
      PomodoroRunState? saved;
      try {
        saved = await PomodoroService.loadRunState()
            .timeout(const Duration(seconds: 5));
      } on TimeoutException catch (_) {
        debugPrint(
            '[PomodoroWorkbench] WARNING: PomodoroService.loadRunState() timed out');
        saved = null;
      } catch (e, st) {
        debugPrint(
            '[PomodoroWorkbench] PomodoroService.loadRunState() error: $e\n$st');
        saved = null;
      }
      debugPrint(
          '[PomodoroWorkbench] PomodoroService.loadRunState() done: ${saved != null}');

      if (saved != null && saved.phase != PomodoroPhase.idle) {
        debugPrint('[PomodoroWorkbench] _recoverState() start');
        try {
          try {
            await _recoverState(saved).timeout(const Duration(seconds: 5));
            debugPrint('[PomodoroWorkbench] _recoverState() done');
          } on TimeoutException catch (_) {
            debugPrint(
                '[PomodoroWorkbench] WARNING: _recoverState() timed out');
          }
        } catch (e, st) {
          debugPrint('[PomodoroWorkbench] _recoverState() error: $e\n$st');
        }
      } else {
        try {
          debugPrint(
              '[PomodoroWorkbench] reading persisted idle binding from SharedPreferences');
          SharedPreferences? prefs;
          try {
            prefs = await SharedPreferences.getInstance()
                .timeout(const Duration(seconds: 5));
          } catch (e, st) {
            debugPrint(
                '[PomodoroWorkbench] WARNING: SharedPreferences.getInstance() timed out or failed: $e\n$st');
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
            }
          }
        } catch (e, st) {
          debugPrint('[PomodoroWorkbench] error reading prefs: $e\n$st');
        }
      }

      debugPrint('[PomodoroWorkbench] _connectCrossDevice() start');
      try {
        try {
          await _connectCrossDevice().timeout(const Duration(seconds: 5));
          debugPrint('[PomodoroWorkbench] _connectCrossDevice() done');
        } on TimeoutException catch (_) {
          debugPrint(
              '[PomodoroWorkbench] WARNING: _connectCrossDevice() timed out');
        }
      } catch (e, st) {
        debugPrint('[PomodoroWorkbench] _connectCrossDevice() error: $e\n$st');
      }

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
              debugPrint(
                  '[PomodoroWorkbench] _syncService.forceReconnect() done');
            } on TimeoutException catch (_) {
              debugPrint(
                  '[PomodoroWorkbench] WARNING: _syncService.forceReconnect() timed out');
            }
          } catch (e, st) {
            debugPrint(
                '[PomodoroWorkbench] _syncService.forceReconnect() error: $e\n$st');
          }
        }
      }
    } catch (e, st) {
      debugPrint('[PomodoroWorkbench] _init error: $e\n$st');
    } finally {
      _initWatchdog?.cancel();
      final elapsed = DateTime.now().difference(_initStart).inMilliseconds;
      debugPrint('[PomodoroWorkbench] _init finished in ${elapsed}ms');
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
    await _syncService.forceReconnect(_userId, 'flutter_$_deviceId',
        appVersion: _appVersion);

    if (mounted) setState(() => _wsConnected = true);
  }

  void _handleCrossDeviceSignal(CrossDevicePomodoroState signal) async {
    if (!mounted || _initializing) return;

    final myDeviceId = 'flutter_$_deviceId';
    if (_deviceId.isEmpty ||
        (signal.sourceDevice != null && signal.sourceDevice == myDeviceId))
      return;

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
            signal.sessionUuid == _currentSessionUuid) break;
        if (_phase == PomodoroPhase.focusing ||
            _phase == PomodoroPhase.breaking ||
            _phase == PomodoroPhase.finished) break;

        final isCountUp = signal.mode == 1;
        final endMs = signal.targetEndMs ?? 0;

        int rem = 0;
        if (isCountUp) {
          final timestamp =
              signal.timestamp ?? DateTime.now().millisecondsSinceEpoch;
          rem = ((DateTime.now().millisecondsSinceEpoch - timestamp) / 1000)
              .floor();
          if (rem < 0) rem = 0; // 防止时间差导致的负数
        } else {
          rem = ((endMs - DateTime.now().millisecondsSinceEpoch) / 1000).ceil();
          if (rem <= 0) break;
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
          _targetEndMs = endMs;
          _remainingSeconds = rem;
          _boundTodo = remoteTodo;
          _remoteState = signal;
          _remoteTagNames = signal.tags;
        });
        widget.onPhaseChanged(_phase);
        _startRemoteTicker(endMs, isCountUp);
        _showLocalFloat(); // Update float window with correct style for remote sessions
        break;

      case 'SYNC_TAGS':
      case 'UPDATE_TAGS':
        if (_phase != PomodoroPhase.remoteWatching) break;
        if (mounted) setState(() => _remoteTagNames = signal.tags);
        break;

      case 'STOP':
      case 'INTERRUPT':
        if (_phase != PomodoroPhase.remoteWatching) break;
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
        if (signal.todoTitle != null && signal.todoTitle!.isNotEmpty) {
          final isCountUp = _remoteState?.mode == 1; // 🚀 识别是否为正计时
          final newTimestamp =
              signal.timestamp ?? DateTime.now().millisecondsSinceEpoch;

          setState(() {
            _boundTodo = TodoItem(
              id: signal.todoUuid ?? '',
              title: signal.todoTitle!,
              isDone: false,
              createdAt: 0,
            );
            _currentSessionUuid = signal.sessionUuid ?? _currentSessionUuid;
            if (isCountUp) {
              // 🚀 关键：同步侧也归零，且校准到这次 SWITCH 的起点
              _remainingSeconds =
                  ((DateTime.now().millisecondsSinceEpoch - newTimestamp) /
                          1000)
                      .floor();
              if (_remainingSeconds < 0) _remainingSeconds = 0;
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
          // 🚀 重新校准计时器起点 (仅针对正计时)
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

      if (isCountUp) {
        setState(() => _remainingSeconds++);
      } else {
        final rem =
            ((targetEndMs - DateTime.now().millisecondsSinceEpoch) / 1000)
                .ceil();
        if (rem <= 0) {
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
          setState(() => _remainingSeconds = rem);
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
    final remaining = isCountUp
        ? ((now - saved.sessionStartMs) / 1000).floor()
        : ((saved.targetEndMs - now) / 1000).ceil();

    if (saved.phase == PomodoroPhase.focusing ||
        saved.phase == PomodoroPhase.breaking) {
      if (!isCountUp && remaining <= 0) {
        if (saved.phase == PomodoroPhase.focusing) {
          await _handleFocusEndFromBackground(saved);
        } else {
          await _handleBreakEndFromBackground(saved);
        }
      } else {
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
          });
          widget.onPhaseChanged(_phase);
          _pushPomodoroNotification(overrideRemaining: remaining);
          _showLocalFloat();
          _startTicker();
          if (!isCountUp) {
            _scheduleReminders(saved.targetEndMs, saved.phase, saved.todoTitle,
                saved.currentCycle, saved.totalCycles);
          }
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
      final remaining = isCountUp
          ? ((now - _sessionStartMs) / 1000).floor()
          : ((_targetEndMs - now) / 1000).ceil();
      if (!isCountUp && remaining <= 0) {
        _ticker?.cancel();
        if (_phase == PomodoroPhase.focusing) {
          await _onFocusEnd();
        } else {
          await _onBreakEnd();
        }
      } else {
        setState(() => _remainingSeconds = remaining);
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
      if (!mounted) return;
      if (_phase != PomodoroPhase.focusing && _phase != PomodoroPhase.breaking)
        return;

      final now = DateTime.now().millisecondsSinceEpoch;
      final bool isCountUp = _phase == PomodoroPhase.focusing &&
          _settings.mode == TimerMode.countUp;

      if (isCountUp) {
        final elapsed = ((now - _sessionStartMs) / 1000).floor();
        setState(() => _remainingSeconds = elapsed);
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

    setState(() {
      _phase = PomodoroPhase.focusing;
      _targetEndMs = end;
      _remainingSeconds = 0;
      _sessionStartMs = now;
      _remoteState = null;
    });
    _stopRemoteTicker();
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

  Future<void> _switchTask(TodoItem newTodo) async {
    if (_phase != PomodoroPhase.focusing) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final actualSeconds = ((now - _sessionStartMs) / 1000).round();

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
        todoUuid: null, // 这里之前绑定的是旧任务
        todoTitle: null,
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
    PomodoroService.saveRunState(PomodoroRunState(
      phase: PomodoroPhase.focusing,
      sessionUuid: _currentSessionUuid,
      targetEndMs: _targetEndMs,
      currentCycle: _currentCycle,
      totalCycles: _settings.cycles,
      focusSeconds: isCountUpNow ? 0 : _settings.focusMinutes * 60,
      breakSeconds: _settings.breakMinutes * 60,
      todoUuid: newTodo.id,
      todoTitle: newTodo.title,
      tagUuids: _selectedTagUuids,
      sessionStartMs: now,
      plannedFocusSeconds: isCountUpNow ? 0 : _settings.focusMinutes * 60,
      mode: _settings.mode,
    ));

    _syncService.sendSwitchSignal(
        todoUuid: newTodo.id,
        todoTitle: newTodo.title,
        sessionUuid: _currentSessionUuid);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('已切换至: ${newTodo.title}'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _finishEarly() async {
    if (_isHandlingEnd) return;
    _isHandlingEnd = true;
    try {
      _ticker?.cancel();
      NotificationService.cancelNotification();
      NotificationService.cancelReminder(40001);
      NotificationService.cancelReminder(40002);
      final now = DateTime.now().millisecondsSinceEpoch;
      final actualSeconds = ((now - _sessionStartMs) / 1000).round();
      final isCountUp = _settings.mode == TimerMode.countUp;

      await _persistIdleBoundTodo(_boundTodo);
      await PomodoroService.clearRunState();
      _syncService.sendStopSignal();
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
      _syncService.sendStopSignal();
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
      if (localIdx != -1 && mounted)
        setState(() => _todos[localIdx].isDone = true);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('✅ "${_boundTodo!.title}" 已标记完成'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating));
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
    widget.onPhaseChanged(_phase);
    _pushPomodoroNotification();
    _showLocalFloat();
    _startTicker();
    NotificationService.cancelReminder(40001);
    _scheduleReminders(end, PomodoroPhase.breaking, _boundTodo?.title,
        _currentCycle, _settings.cycles);
    PomodoroService.saveRunState(PomodoroRunState(
      phase: PomodoroPhase.breaking,
      sessionUuid: _currentSessionUuid,
      targetEndMs: end,
      currentCycle: _currentCycle,
      totalCycles: _settings.cycles,
      focusSeconds: _settings.focusMinutes * 60,
      breakSeconds: _settings.breakMinutes * 60,
      todoUuid: _boundTodo?.id,
      todoTitle: _boundTodo?.title,
      tagUuids: _selectedTagUuids,
      sessionStartMs: now,
      plannedFocusSeconds: _settings.focusMinutes * 60,
    ));
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
      widget.onPhaseChanged(_phase);
      PomodoroService.clearRunState();
      await _persistIdleBoundTodo(_boundTodo);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('☕ 休息结束，准备开始下一轮！'),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating));
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
        _syncService.sendStopSignal();
        // 🚀 Notify island to switch to idle immediately
        await FloatWindowService.update(endMs: 0, isLocal: true);
        final isCountUpMode = _settings.mode == TimerMode.countUp;
        setState(() {
          _phase = PomodoroPhase.idle;
          _currentCycle = 1;
          _remainingSeconds = isCountUpMode ? 0 : _settings.focusMinutes * 60;
        });
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
                  if (!isSwitching)
                    ListTile(
                      leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              shape: BoxShape.circle),
                          child: const Icon(Icons.clear, size: 20)),
                      title: const Text('不绑定任务（自由专注）'),
                      onTap: () async {
                        setState(() => _boundTodo = null);
                        await _persistIdleBoundTodo(null);
                        Navigator.pop(ctx);
                      },
                    ),
                  ..._todos.map((t) => ListTile(
                        leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                shape: BoxShape.circle),
                            child: Icon(Icons.check,
                                size: 20,
                                color: Theme.of(context).colorScheme.primary)),
                        title: Text(t.title,
                            style:
                                const TextStyle(fontWeight: FontWeight.w500)),
                        subtitle: t.remark != null && t.remark!.isNotEmpty
                            ? Text(t.remark!,
                                maxLines: 1, overflow: TextOverflow.ellipsis)
                            : null,
                        selected: t.id == _boundTodo?.id,
                        selectedTileColor: Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withValues(alpha: 0.3),
                        onTap: () async {
                          Navigator.pop(ctx);
                          if (isSwitching) {
                            await _switchTask(t);
                          } else {
                            setState(() => _boundTodo = t);
                            await _persistIdleBoundTodo(t);
                          }
                        },
                      )),
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
          ? _sessionStartMs
          : (isRemoteCountUp ? (_remoteState?.timestamp ?? 0) : _targetEndMs);
      mode = (isCountUp || isRemoteCountUp) ? 1 : 0;
    }

    String displayTitle = _boundTodo?.title ?? '';
    if (displayTitle.isEmpty && !isIdle) {
      displayTitle = '自由专注';
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
            opacity: (isFocusing || isRemoteWatching) ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: IgnorePointer(
              ignoring: !(isFocusing || isRemoteWatching),
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
    return AnimatedOpacity(
      opacity: _wsConnected ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 600),
      child: const Tooltip(
          message: '跨端同步已连接',
          child: Center(
              child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.link_rounded, size: 20, color: Colors.grey),
          ))),
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
      phase: _phase, remainingSeconds: _remainingSeconds,
      focusMinutes: _settings.focusMinutes,
      breakMinutes: _settings.breakMinutes, currentCycle: _currentCycle,
      totalCycles: _settings.cycles,
      isCountUp: isCountUp, isRemoteCountUp: isRemoteCountUp,
      remoteState: _remoteState,
      // explicit compactness control from parent
      isCompact: widget.isCompact,
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
                  selectedColor: color.withValues(alpha: 0.2),
                  side: BorderSide(
                      color: selected ? color : Colors.grey.shade300),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  onSelected: (val) async {
                    setState(() {
                      if (val)
                        _selectedTagUuids.add(tag.uuid);
                      else
                        _selectedTagUuids.remove(tag.uuid);
                    });
                    await _persistIdleBoundTodo(_boundTodo);
                    _showLocalFloat();
                    if (_phase == PomodoroPhase.focusing)
                      _syncService.sendUpdateTagsSignal(_allTags
                          .where((t) => _selectedTagUuids.contains(t.uuid))
                          .map((t) => t.name)
                          .toList());
                  },
                );
              }).toList())),
    );
  }

  Widget _buildActions(
      bool isIdle, bool isFocusing, bool isRemoteWatching, Color contentColor) {
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
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4))),
      child: Text(name,
          style: TextStyle(
              fontSize: 12,
              color: color.withValues(alpha: 0.9),
              fontWeight: FontWeight.w500)),
    );
  }
}
