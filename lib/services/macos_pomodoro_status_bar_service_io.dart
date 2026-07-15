import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  static final Map<int, Timer> _reminderTimers = {};
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
          _sendRemoteState(remote);
        case 'STOP':
        case 'INTERRUPT':
        case 'FOCUS_DISCONNECTED':
          _checkAndClearIfNoLocal();
        case 'SWITCH':
          _sendRemoteState(remote);
      }
    });
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
      await _channel.invokeMethod('clearIslandReminders');
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
        if (!restoring || delay.abs() > _restoreGracePeriod) continue;
        await _showIslandReminder(reminder);
        continue;
      }

      _reminderTimers[notifId] = Timer(delay, () {
        _reminderTimers.remove(notifId);
        final lateness = DateTime.now().difference(triggerAt);
        if (lateness > _restoreGracePeriod) return;
        _showIslandReminder(reminder);
      });
    }
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
    return state != null &&
        (state.phase == PomodoroPhase.focusing ||
            state.phase == PomodoroPhase.breaking);
  }

  static void _sendRemoteState(CrossDevicePomodoroState remote) async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('macos_island_enabled') ??
        prefs.getBool('macos_status_bar_enabled') ??
        true;
    if (!enabled) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final isCountUp = remote.mode == 1;
    final targetEndMs = remote.targetEndMs ?? 0;
    final timestamp = remote.timestamp ?? now;

    _channel.invokeMethod('updatePomodoroStatus', {
      'phase': 'focusing',
      'targetEndMs': targetEndMs,
      'sessionStartMs': timestamp,
      'mode': isCountUp ? 'countUp' : 'countdown',
      'isPaused': false,
      'pausedAtMs': 0,
      'accumulatedMs': 0,
      'pauseStartMs': 0,
      'todoTitle': remote.todoTitle ?? '',
      'isRemote': true,
    });
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
  }

  static void _clearNative() {
    debugPrint('[MacPomodoroStatusBar] _clearNative called');
    _channel.invokeMethod('clearPomodoroStatus');
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
    } else {
      _clearNative();
    }
  }

  static void dispose() {
    _localSub?.cancel();
    _localSub = null;
    _remoteSub?.cancel();
    _remoteSub = null;
    _lastLocalActiveState = null;
    _initialized = false;
  }
}
