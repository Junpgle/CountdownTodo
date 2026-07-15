import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../storage_service.dart';
import 'ongoing_activity_service.dart';
import 'pomodoro_service.dart';
import 'pomodoro_sync_service.dart';

/// macOS 状态栏番茄钟操作事件
enum MacPomodoroAction { togglePause, stopFocus }

enum MacIslandReminderActionType { acknowledged, snoozed }

class MacIslandReminderAction {
  const MacIslandReminderAction({
    required this.type,
    required this.reminder,
    this.snoozeMinutes = 10,
  });

  final MacIslandReminderActionType type;
  final Map<String, dynamic> reminder;
  final int snoozeMinutes;
}

class MacPomodoroStatusBarService {
  static const MethodChannel _channel =
      MethodChannel('countdown_todo/macos_status_bar');

  static StreamSubscription<PomodoroRunState?>? _localSub;
  static StreamSubscription<CrossDevicePomodoroState>? _remoteSub;
  static bool _initialized = false;
  static PomodoroRunState? _lastLocalActiveState;
  static Map<String, dynamic>? _lastRemotePayload;
  static final Map<int, Timer> _reminderTimers = {};
  static Timer? _activityTimer;
  static bool _activitySyncInProgress = false;
  static bool _activitySyncPending = false;
  static int _activitySyncGeneration = 0;
  static const Duration _restoreGracePeriod = Duration(minutes: 2);

  /// 状态栏操作事件流（暂停/继续/结束）
  static final StreamController<MacPomodoroAction> _actionController =
      StreamController<MacPomodoroAction>.broadcast();
  static Stream<MacPomodoroAction> get onAction => _actionController.stream;

  static final StreamController<MacIslandReminderAction>
      _reminderActionController =
      StreamController<MacIslandReminderAction>.broadcast();
  static Stream<MacIslandReminderAction> get onReminderAction =>
      _reminderActionController.stream;

  static Future<void> init() async {
    if (!Platform.isMacOS) return;
    if (_initialized) return;
    _initialized = true;
    _activitySyncGeneration++;
    debugPrint('[MacPomodoroStatusBar] init() called');

    // 设置 MethodCallHandler 接收 Swift 端消息
    _channel.setMethodCallHandler(_handleMethodCall);

    // 监听本地专注状态
    try {
      final runState = await PomodoroService.loadRunState();
      debugPrint('[MacPomodoroStatusBar] loadRunState: ${runState?.phase}');
      if (_isActiveLocalState(runState)) {
        _lastLocalActiveState = runState;
        _sendLocalState(runState!);
      }
    } catch (e) {
      debugPrint('[MacPomodoroStatusBar] init error: $e');
    }

    _localSub = PomodoroService.onRunStateChanged.listen((state) {
      debugPrint('[MacPomodoroStatusBar] onRunStateChanged: ${state?.phase}');
      if (state == null) {
        _lastLocalActiveState = null;
        _clearNative();
      } else if (_isActiveLocalState(state)) {
        _lastLocalActiveState = state;
        _sendLocalState(state);
      } else {
        _lastLocalActiveState = null;
        _clearNative();
      }
    });

    // 监听远端专注状态
    _remoteSub = PomodoroSyncService.instance.onStateChanged.listen((remote) {
      switch (remote.action) {
        case 'START':
        case 'SYNC_FOCUS':
        case 'RECONNECT_SYNC':
          _handleRemoteActiveState(remote);
        case 'STOP':
        case 'INTERRUPT':
        case 'FINISH':
        case 'CLEAR_FOCUS':
        case 'FOCUS_DISCONNECTED':
          _checkAndClearIfNoLocal();
        case 'SWITCH':
        case 'PAUSE':
        case 'RESUME':
          _handleRemoteActiveState(remote);
      }
    });

    StorageService.dataRefreshNotifier.addListener(_handleDataRefresh);
    await syncOngoingActivity();
  }

  /// 处理 Swift 端发来的消息
  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    debugPrint('[MacPomodoroStatusBar] _handleMethodCall: ${call.method}');
    switch (call.method) {
      case 'togglePomodoroPause':
        _actionController.add(MacPomodoroAction.togglePause);
      case 'stopPomodoroFocus':
        _actionController.add(MacPomodoroAction.stopFocus);
      case 'acknowledgeIslandReminder':
        final reminder = _methodArguments(call.arguments);
        _reminderActionController.add(MacIslandReminderAction(
          type: MacIslandReminderActionType.acknowledged,
          reminder: reminder,
        ));
      case 'snoozeIslandReminder':
        final args = _methodArguments(call.arguments);
        final reminder = args['reminder'] is Map
            ? Map<String, dynamic>.from(args['reminder'] as Map)
            : args;
        final minutes = (args['minutes'] as num?)?.toInt() ?? 10;
        _reminderActionController.add(MacIslandReminderAction(
          type: MacIslandReminderActionType.snoozed,
          reminder: reminder,
          snoozeMinutes: minutes,
        ));
    }
  }

  static Map<String, dynamic> _methodArguments(dynamic arguments) {
    if (arguments is Map) {
      return Map<String, dynamic>.from(arguments);
    }
    return <String, dynamic>{};
  }

  /// 为应用运行期间注册灵动岛提醒；系统通知仍由 NotificationService 负责。
  static Future<void> scheduleIslandReminders(
    List<Map<String, dynamic>> reminders, {
    bool clearFirst = true,
    bool restoring = false,
  }) async {
    if (!Platform.isMacOS) return;
    final prefs = await SharedPreferences.getInstance();
    final islandEnabled = prefs.getBool('macos_island_enabled') ??
        prefs.getBool('macos_status_bar_enabled') ??
        true;
    final remindersEnabled =
        prefs.getBool('macos_island_reminders_enabled') ?? true;
    if (!islandEnabled || !remindersEnabled) {
      if (clearFirst) clearIslandReminders();
      return;
    }

    if (clearFirst) {
      for (final timer in _reminderTimers.values) {
        timer.cancel();
      }
      _reminderTimers.clear();
      // 重建未来定时器时保留已经展开或已确认的提醒，避免数据刷新造成重复弹出。
      if (reminders.isEmpty) {
        await _channel.invokeMethod('clearIslandReminders');
      }
    }

    final now = DateTime.now();
    for (final source in reminders) {
      final reminder = Map<String, dynamic>.from(source);
      final notifId = (reminder['notifId'] as num?)?.toInt();
      final triggerAtMs = (reminder['triggerAtMs'] as num?)?.toInt();
      if (notifId == null || triggerAtMs == null) continue;

      _reminderTimers.remove(notifId)?.cancel();
      final triggerAt = DateTime.fromMillisecondsSinceEpoch(triggerAtMs);
      final delay = triggerAt.difference(now);
      if (delay.isNegative) {
        if (!_shouldDeliverLateReminder(
          reminder,
          now: now,
          triggerAt: triggerAt,
          restoring: restoring,
        )) {
          continue;
        }
        await _showIslandReminder(reminder);
        continue;
      }

      _reminderTimers[notifId] = Timer(delay, () {
        _reminderTimers.remove(notifId);
        final firedAt = DateTime.now();
        if (!_shouldDeliverLateReminder(
          reminder,
          now: firedAt,
          triggerAt: triggerAt,
          restoring: true,
        )) {
          return;
        }
        _showIslandReminder(reminder);
      });
    }
  }

  static bool _shouldDeliverLateReminder(
    Map<String, dynamic> reminder, {
    required DateTime now,
    required DateTime triggerAt,
    required bool restoring,
  }) {
    final startAtMs = (reminder['startAtMs'] as num?)?.toInt() ??
        (reminder['courseStartMs'] as num?)?.toInt();
    if (startAtMs != null) {
      final startAt = DateTime.fromMillisecondsSinceEpoch(startAtMs);
      return now.isBefore(startAt);
    }
    return restoring && now.difference(triggerAt) <= _restoreGracePeriod;
  }

  static Future<void> _showIslandReminder(Map<String, dynamic> reminder) async {
    try {
      await _channel.invokeMethod('showIslandReminder', reminder);
    } catch (e) {
      debugPrint('[MacIsland] show reminder failed: $e');
    }
  }

  static void clearIslandReminders() {
    for (final timer in _reminderTimers.values) {
      timer.cancel();
    }
    _reminderTimers.clear();
    _channel.invokeMethod('clearIslandReminders');
  }

  static Future<void> showTestReminder() async {
    if (!Platform.isMacOS) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _showIslandReminder({
      'notifId': 39999,
      'triggerAtMs': now,
      'title': '灵动岛提醒测试',
      'text': '位置和内容显示正常，点击“好的”即可关闭',
      'type': 'upcoming_todo',
    });
  }

  static void _sendLocalState(PomodoroRunState state) async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('macos_island_enabled') ??
        prefs.getBool('macos_status_bar_enabled') ??
        true;
    if (!enabled) return;
    _lastRemotePayload = null;
    debugPrint(
        '[MacPomodoroStatusBar] _sendLocalState: phase=${state.phase}, targetEndMs=${state.targetEndMs}');
    _channel.invokeMethod('updatePomodoroStatus', {
      'phase': state.phase.name,
      'targetEndMs': state.targetEndMs,
      'sessionStartMs': state.sessionStartMs,
      'mode': state.mode.name,
      'isPaused': state.isPaused,
      'pausedAtMs': state.pausedAtMs,
      'accumulatedMs': state.accumulatedMs,
      'pauseStartMs': state.pauseStartMs,
      'todoTitle': state.todoTitle ?? '',
      'isRemote': false,
    });
  }

  static bool _isActiveLocalState(PomodoroRunState? state) {
    return isUsableLocalState(state);
  }

  @visibleForTesting
  static bool isUsableLocalState(
    PomodoroRunState? state, {
    int? nowMs,
  }) {
    if (state == null ||
        (state.phase != PomodoroPhase.focusing &&
            state.phase != PomodoroPhase.breaking)) {
      return false;
    }
    if (state.isPaused || state.mode == TimerMode.countUp) return true;
    return state.targetEndMs > (nowMs ?? DateTime.now().millisecondsSinceEpoch);
  }

  /// 本机专注优先于 WebSocket 状态，且忽略服务端回推的本机专注事件。
  static Future<void> _handleRemoteActiveState(
      CrossDevicePomodoroState remote) async {
    final cached = _lastLocalActiveState;
    if (_isActiveLocalState(cached)) {
      debugPrint(
          '[MacIsland] keep local focus over ${remote.action}: ${cached!.sessionUuid}');
      _sendLocalState(cached);
      return;
    }

    final local = await PomodoroService.loadRunState();
    if (_isActiveLocalState(local)) {
      _lastLocalActiveState = local;
      debugPrint(
          '[MacIsland] restore local focus over ${remote.action}: ${local!.sessionUuid}');
      _sendLocalState(local);
      return;
    }

    if (PomodoroSyncService.instance.isFromCurrentDevice(remote.sourceDevice)) {
      debugPrint(
          '[MacIsland] ignore local WebSocket echo: ${remote.action}, source=${remote.sourceDevice}');
      return;
    }

    _sendRemoteState(remote);
  }

  static void _sendRemoteState(CrossDevicePomodoroState remote) async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('macos_island_enabled') ??
        prefs.getBool('macos_status_bar_enabled') ??
        true;
    if (!enabled) return;

    final payload = mergeRemotePayload(remote, _lastRemotePayload);
    if (payload == null) return;
    _lastRemotePayload = payload;
    _channel.invokeMethod('updatePomodoroStatus', payload);
  }

  @visibleForTesting
  static Map<String, dynamic>? mergeRemotePayload(
    CrossDevicePomodoroState remote,
    Map<String, dynamic>? previous, {
    int? nowMs,
  }) {
    final isIncremental = remote.action == 'SWITCH' ||
        remote.action == 'PAUSE' ||
        remote.action == 'RESUME';
    if (isIncremental && previous == null) return null;
    final previousSession = previous?['sessionUuid']?.toString();
    final requiresSameSession =
        remote.action == 'PAUSE' || remote.action == 'RESUME';
    if (requiresSameSession &&
        remote.sessionUuid != null &&
        previousSession != null &&
        remote.sessionUuid != previousSession) {
      return null;
    }

    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final remoteMode = remote.mode;
    final previousMode = previous?['mode']?.toString();
    final mode = remoteMode == null
        ? (previousMode ?? 'countdown')
        : (remoteMode == 1 ? 'countUp' : 'countdown');
    final isPaused = switch (remote.action) {
      'PAUSE' => true,
      'RESUME' => false,
      _ => remote.isPaused ?? (previous?['isPaused'] as bool?) ?? false,
    };
    return <String, dynamic>{
      'phase': 'focusing',
      'sessionUuid': remote.sessionUuid ?? previous?['sessionUuid'] ?? '',
      'targetEndMs': remote.targetEndMs ?? previous?['targetEndMs'] ?? 0,
      'sessionStartMs': remote.timestamp ?? previous?['sessionStartMs'] ?? now,
      'mode': mode,
      'isPaused': isPaused,
      'pausedAtMs': remote.pausedAtMs ?? previous?['pausedAtMs'] ?? 0,
      'accumulatedMs': remote.accumulatedMs ?? previous?['accumulatedMs'] ?? 0,
      'pauseStartMs': remote.pauseStartMs ?? previous?['pauseStartMs'] ?? 0,
      'todoTitle': remote.todoTitle ?? previous?['todoTitle'] ?? '',
      'isRemote': true,
    };
  }

  static void _checkAndClearIfNoLocal() async {
    final cached = _lastLocalActiveState;
    if (_isActiveLocalState(cached)) {
      debugPrint(
          '[MacPomodoroStatusBar] skip remote clear, cached local active: ${cached!.phase}');
      _sendLocalState(cached);
      return;
    }

    // 延迟一点检查本地状态，避免竞态
    await Future.delayed(const Duration(milliseconds: 500));
    final local = await PomodoroService.loadRunState();
    if (_isActiveLocalState(local)) {
      _lastLocalActiveState = local;
      debugPrint(
          '[MacPomodoroStatusBar] skip remote clear, loaded local active: ${local!.phase}');
      _sendLocalState(local);
      return;
    }

    _clearNative();
    _lastRemotePayload = null;
  }

  static void _clearNative() {
    debugPrint('[MacPomodoroStatusBar] _clearNative called');
    _channel.invokeMethod('clearPomodoroStatus');
  }

  static void _handleDataRefresh() {
    unawaited(syncOngoingActivity());
  }

  /// 同步当前课程、计划块或明确时段待办，并在下一处起止边界自动重算。
  static Future<void> syncOngoingActivity() async {
    if (!Platform.isMacOS || !_initialized) return;
    if (_activitySyncInProgress) {
      _activitySyncPending = true;
      return;
    }
    _activitySyncInProgress = true;
    _activitySyncPending = false;
    final generation = _activitySyncGeneration;
    _activityTimer?.cancel();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!_isActivitySyncCurrent(generation)) return;
      final enabled = prefs.getBool('macos_island_enabled') ??
          prefs.getBool('macos_status_bar_enabled') ??
          true;
      if (!enabled) {
        await _channel.invokeMethod('clearOngoingActivity');
        return;
      }

      final username = prefs.getString(StorageService.KEY_CURRENT_USER) ?? '';
      if (username.trim().isEmpty) {
        await _channel.invokeMethod('clearOngoingActivity');
        if (_isActivitySyncCurrent(generation)) {
          _scheduleActivitySync(const Duration(minutes: 2));
        }
        return;
      }
      final resolution =
          await OngoingActivityService.resolveFromStorage(username);
      if (!_isActivitySyncCurrent(generation)) return;
      final activity = resolution.activity;
      if (activity == null) {
        await _channel.invokeMethod('clearOngoingActivity');
      } else {
        await _channel.invokeMethod('updateOngoingActivity', activity.toMap());
      }

      final now = DateTime.now();
      final boundaryDelay = resolution.nextBoundary?.difference(now);
      final delay = boundaryDelay != null && !boundaryDelay.isNegative
          ? boundaryDelay + const Duration(milliseconds: 250)
          : const Duration(minutes: 15);
      if (!_isActivitySyncCurrent(generation)) return;
      _scheduleActivitySync(
        delay > const Duration(minutes: 15)
            ? const Duration(minutes: 15)
            : delay,
      );
    } catch (e) {
      if (_isActivitySyncCurrent(generation)) {
        debugPrint('[MacIsland] ongoing activity sync failed: $e');
        _scheduleActivitySync(const Duration(minutes: 2));
      }
    } finally {
      _activitySyncInProgress = false;
      if (_activitySyncPending && _initialized) {
        _activitySyncPending = false;
        unawaited(syncOngoingActivity());
      }
    }
  }

  static bool _isActivitySyncCurrent(int generation) =>
      _initialized && generation == _activitySyncGeneration;

  static void _scheduleActivitySync(Duration delay) {
    _activityTimer?.cancel();
    _activityTimer = Timer(
      delay,
      () => unawaited(syncOngoingActivity()),
    );
  }

  /// 供外部（设置页）主动清除状态栏显示
  static void clearNative() {
    _clearNative();
  }

  /// 设置变更后立即把当前专注状态同步到灵动岛。
  static Future<void> syncCurrentStatus() async {
    if (!Platform.isMacOS) return;
    final state = await PomodoroService.loadRunState();
    if (_isActiveLocalState(state)) {
      _lastLocalActiveState = state;
      _sendLocalState(state!);
    } else if (_lastRemotePayload != null) {
      await _channel.invokeMethod(
        'updatePomodoroStatus',
        _lastRemotePayload,
      );
    } else {
      _clearNative();
    }
    await syncOngoingActivity();
  }

  static void dispose() {
    _initialized = false;
    _activitySyncGeneration++;
    _activitySyncPending = false;
    _localSub?.cancel();
    _localSub = null;
    _remoteSub?.cancel();
    _remoteSub = null;
    StorageService.dataRefreshNotifier.removeListener(_handleDataRefresh);
    _activityTimer?.cancel();
    _activityTimer = null;
    _lastLocalActiveState = null;
    _lastRemotePayload = null;
  }
}
