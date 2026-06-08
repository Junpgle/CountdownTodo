import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'pomodoro_service.dart';
import 'pomodoro_sync_service.dart';

class MacPomodoroStatusBarService {
  static const MethodChannel _channel =
      MethodChannel('countdown_todo/macos_status_bar');

  static StreamSubscription<PomodoroRunState?>? _localSub;
  static StreamSubscription<CrossDevicePomodoroState>? _remoteSub;
  static bool _initialized = false;

  static Future<void> init() async {
    if (!Platform.isMacOS) return;
    if (_initialized) return;
    _initialized = true;

    // 监听本地专注状态
    try {
      final runState = await PomodoroService.loadRunState();
      if (runState != null &&
          (runState.phase == PomodoroPhase.focusing ||
           runState.phase == PomodoroPhase.breaking)) {
        _sendLocalState(runState);
      }
    } catch (e) {
      debugPrint('[MacPomodoroStatusBar] init error: $e');
    }

    _localSub = PomodoroService.onRunStateChanged.listen((state) {
      if (state == null) {
        _clearNative();
      } else if (state.phase == PomodoroPhase.focusing ||
                 state.phase == PomodoroPhase.breaking) {
        _sendLocalState(state);
      } else {
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

  static void _sendLocalState(PomodoroRunState state) {
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
    });
  }

  static void _sendRemoteState(CrossDevicePomodoroState remote) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final isCountUp = remote.mode == 1;
    final targetEndMs = remote.targetEndMs ?? 0;
    final timestamp = remote.timestamp ?? now;

    // 远端专注只做展示，不维护精确状态
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
    });
  }

  static void _checkAndClearIfNoLocal() async {
    // 延迟一点检查本地状态，避免竞态
    await Future.delayed(const Duration(milliseconds: 500));
    final local = await PomodoroService.loadRunState();
    if (local == null ||
        (local.phase != PomodoroPhase.focusing &&
         local.phase != PomodoroPhase.breaking)) {
      _clearNative();
    }
  }

  static void _clearNative() {
    _channel.invokeMethod('clearPomodoroStatus');
  }

  static void dispose() {
    _localSub?.cancel();
    _localSub = null;
    _remoteSub?.cancel();
    _remoteSub = null;
    _initialized = false;
  }
}
