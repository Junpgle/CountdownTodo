import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'pomodoro_service.dart';

class MacPomodoroStatusBarService {
  static const MethodChannel _channel =
      MethodChannel('countdown_todo/macos_status_bar');

  static StreamSubscription<PomodoroRunState?>? _subscription;
  static bool _initialized = false;
  static Timer? _timer;
  static PomodoroRunState? _currentState;

  static Future<void> init() async {
    if (!Platform.isMacOS) return;
    if (_initialized) return;
    _initialized = true;

    try {
      _currentState = await PomodoroService.loadRunState();
      if (_currentState != null) {
        _sendToNative(_currentState!);
      }
    } catch (e) {
      debugPrint('[MacPomodoroStatusBar] init error: $e');
    }

    _subscription = PomodoroService.onRunStateChanged.listen((state) {
      _currentState = state;
      if (state == null) {
        _clearNative();
      } else {
        _sendToNative(state);
      }
    });
  }

  static void _sendToNative(PomodoroRunState state) {
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

  static void _clearNative() {
    _channel.invokeMethod('clearPomodoroStatus');
  }

  static void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _timer?.cancel();
    _timer = null;
    _initialized = false;
  }
}
