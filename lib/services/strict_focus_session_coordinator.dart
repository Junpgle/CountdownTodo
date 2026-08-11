import 'dart:async';

import 'package:flutter/widgets.dart';

import '../utils/app_platform.dart';
import 'float_window_service.dart';
import 'notification_service.dart';
import 'pomodoro_service.dart';
import 'pomodoro_sync_service.dart';
import 'strict_focus_haptic_service.dart';
import 'strict_focus_sensor_service.dart';

/// Keeps strict-focus sensor control alive when the workbench route is gone.
///
/// The workbench owns the visual state, while this coordinator owns the
/// sensor subscription and persists pause/resume transitions. This is what
/// allows flipping the phone from the home page to continue the same session.
class StrictFocusSessionCoordinator with WidgetsBindingObserver {
  StrictFocusSessionCoordinator._() {
    WidgetsBinding.instance.addObserver(this);
    _runStateSub = PomodoroService.onRunStateChanged.listen((state) {
      if (!_isStrictFocusState(state)) {
        unawaited(stopMonitoring());
      }
    });
  }

  static final StrictFocusSessionCoordinator instance =
      StrictFocusSessionCoordinator._();

  final StrictFocusSensorService _sensorService = StrictFocusSensorService();
  final StreamController<StrictFocusSensorEvent> _sensorStateController =
      StreamController<StrictFocusSensorEvent>.broadcast();
  StreamSubscription<StrictFocusSensorEvent>? _sensorSub;
  StreamSubscription<PomodoroRunState?>? _runStateSub;
  Future<void>? _startFuture;
  Future<void>? _backgroundPauseFuture;
  Future<void> _mutationTail = Future<void>.value();
  Timer? _sensorRestartTimer;
  String? _monitoringSessionUuid;
  StrictFocusSensorEvent? _pendingSensorEvent;
  int _sensorRestartAttempts = 0;
  int _generation = 0;
  int _backgroundEpoch = 0;
  bool _monitoring = false;
  bool _handlingEvent = false;
  bool _isInBackground = false;

  bool get isMonitoring => _monitoring;

  /// UI can observe this stream without owning the sensor subscription.
  Stream<StrictFocusSensorEvent> get sensorEvents =>
      _sensorStateController.stream;

  Future<void> startMonitoring() async {
    if (!AppPlatform.isAndroid && !AppPlatform.isIOS) return;
    if (_isInBackground) return;

    final backgroundPause = _backgroundPauseFuture;
    if (backgroundPause != null) {
      await backgroundPause;
    }
    if (_isInBackground) return;

    final saved = await PomodoroService.loadRunState();
    if (!_isStrictFocusState(saved)) {
      await stopMonitoring();
      return;
    }
    if (_monitoring) return;

    if (_monitoringSessionUuid != saved!.sessionUuid) {
      _monitoringSessionUuid = saved.sessionUuid;
      _sensorRestartAttempts = 0;
    }

    final pending = _startFuture;
    if (pending != null) {
      await pending;
      return;
    }

    final future = _startMonitoring();
    _startFuture = future;
    try {
      await future;
    } finally {
      if (identical(_startFuture, future)) _startFuture = null;
    }
  }

  Future<void> _startMonitoring() async {
    final generation = ++_generation;
    _monitoring = true;
    _sensorSub = _sensorService.events.listen(_handleSensorEvent);
    final started = await _sensorService.start();
    if (generation != _generation) return;
    if (!started) {
      _monitoring = false;
      await _sensorSub?.cancel();
      _sensorSub = null;
    }
  }

  Future<void> stopMonitoring() async {
    ++_generation;
    _monitoring = false;
    _pendingSensorEvent = null;
    _sensorRestartTimer?.cancel();
    _sensorRestartTimer = null;
    final subscription = _sensorSub;
    _sensorSub = null;
    await subscription?.cancel();
    await _sensorService.stop();
  }

  Future<void> _handleSensorEvent(StrictFocusSensorEvent event) async {
    if (!_sensorStateController.isClosed) {
      _sensorStateController.add(event);
    }

    if (event.state == StrictFocusSensorState.waitingForFlip ||
        event.state == StrictFocusSensorState.faceDown ||
        event.state == StrictFocusSensorState.notFaceDown) {
      _sensorRestartAttempts = 0;
    }

    if (!_monitoring) return;
    if (event.state != StrictFocusSensorState.faceDown &&
        event.state != StrictFocusSensorState.notFaceDown &&
        event.state != StrictFocusSensorState.unavailable) {
      return;
    }

    // Keep the newest pose while a persistence/haptic operation is in flight.
    // The old implementation dropped it, which could leave the session stuck
    // until the user performed another complete flip.
    _pendingSensorEvent = event;
    if (_handlingEvent) return;

    _handlingEvent = true;
    try {
      while (_monitoring && _pendingSensorEvent != null) {
        final pending = _pendingSensorEvent!;
        _pendingSensorEvent = null;
        await _enqueueStateMutation(() => _processSensorEvent(pending));
      }
    } finally {
      _handlingEvent = false;
    }
  }

  Future<void> _processSensorEvent(StrictFocusSensorEvent event) async {
    final state = await PomodoroService.loadRunState();
    if (state == null || !_isStrictFocusState(state)) {
      await stopMonitoring();
      return;
    }

    if (event.state == StrictFocusSensorState.unavailable) {
      if (!state.isPaused) {
        await _pauseRunState(state);
      }
      await stopMonitoring();
      _scheduleSensorRestart();
      return;
    }

    if (event.state == StrictFocusSensorState.faceDown && state.isPaused) {
      await _resumeRunState(state);
    } else if (event.state == StrictFocusSensorState.notFaceDown &&
        !state.isPaused) {
      await _pauseRunState(state);
    }
  }

  bool _isStrictFocusState(PomodoroRunState? state) {
    return state != null &&
        state.phase == PomodoroPhase.focusing &&
        state.mode == TimerMode.countUp &&
        state.strictFreeFocus;
  }

  /// Serializes all state transitions from sensor and lifecycle callbacks.
  /// SharedPreferences writes are asynchronous, so without this queue a
  /// background pause could read the previous state while a resume is saving.
  Future<void> _enqueueStateMutation(Future<void> Function() operation) async {
    final previous = _mutationTail;
    final completer = Completer<void>();
    _mutationTail = completer.future;

    unawaited(() async {
      try {
        await previous;
      } catch (_) {}
      try {
        await operation();
      } catch (_) {}
      if (!completer.isCompleted) completer.complete();
    }());

    await completer.future;
  }

  Future<void> _pauseRunState(PomodoroRunState state) async {
    if (state.isPaused) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final targetEndMs = state.mode == TimerMode.countUp
        ? state.sessionStartMs + state.accumulatedMs
        : state.targetEndMs;
    final intervals = List<PauseInterval>.from(state.pauseIntervals)
      ..add(PauseInterval(startMs: now));
    final paused = _copyState(
      state,
      targetEndMs: targetEndMs,
      isPaused: true,
      strictWaitingForFlip: false,
      pausedAtMs: now,
      pauseStartMs: now,
      accumulatedMs: state.accumulatedMs,
      pauseIntervals: intervals,
    );
    await PomodoroService.saveRunState(paused);
    // Persist the pause before invoking platform haptics so a background
    // transition cannot leave an unpaused state if the process is suspended.
    unawaited(StrictFocusHapticService.notifyFocusPaused());
    unawaited(_updateFloat(paused));
    PomodoroSyncService.instance.sendPauseSignal(
      sessionUuid: paused.sessionUuid,
      pausedAtMs: paused.pausedAtMs,
      accumulatedMs: paused.accumulatedMs,
      pauseStartMs: paused.pauseStartMs,
    );
  }

  Future<void> _resumeRunState(PomodoroRunState state) async {
    if (!state.isPaused || _isInBackground || !_monitoring) return;
    final resumeEpoch = _backgroundEpoch;
    final now = DateTime.now().millisecondsSinceEpoch;
    final pauseDuration =
        (now - state.pausedAtMs).clamp(0, 24 * 3600 * 1000).toInt();
    final intervals = List<PauseInterval>.from(state.pauseIntervals);
    if (intervals.isNotEmpty && intervals.last.isOngoing) {
      intervals.last.endMs = now;
    }

    final wasWaitingForFlip = state.strictWaitingForFlip;
    final resumed = _copyState(
      state,
      targetEndMs: state.mode == TimerMode.countdown
          ? state.targetEndMs + pauseDuration
          : state.targetEndMs,
      isPaused: false,
      strictWaitingForFlip: false,
      pausedAtMs: 0,
      pauseStartMs: 0,
      accumulatedMs: state.accumulatedMs + pauseDuration,
      pauseIntervals: intervals,
    );

    if (!_canResume(resumeEpoch)) return;
    await StrictFocusHapticService.notifyFocusStarted();
    if (!_canResume(resumeEpoch)) return;

    await PomodoroService.saveRunState(resumed);
    unawaited(_updateFloat(resumed));

    if (wasWaitingForFlip) {
      unawaited(NotificationService.updatePomodoroNotification(
        remainingSeconds: 0,
        phase: 'focusing',
        todoTitle: resumed.todoTitle,
        currentCycle: resumed.currentCycle,
        totalCycles: resumed.totalCycles,
        tagNames: resumed.tagNames,
        alertKey: 'pomo_start_${resumed.sessionStartMs}',
      ));
      PomodoroSyncService.instance.sendStartSignal(
        sessionUuid: resumed.sessionUuid,
        todoUuid: resumed.todoUuid,
        todoTitle: resumed.todoTitle,
        planBlockId: resumed.planBlockId,
        durationSeconds: resumed.focusSeconds,
        targetEndMs: resumed.targetEndMs,
        tagNames: resumed.tagNames,
        currentCycle: resumed.currentCycle,
        totalCycles: resumed.totalCycles,
        plannedFocusSeconds: resumed.plannedFocusSeconds,
        mode: resumed.mode.index,
        note: resumed.note,
        customTimestamp: resumed.sessionStartMs,
      );
    } else {
      PomodoroSyncService.instance.sendResumeSignal(
        sessionUuid: resumed.sessionUuid,
        pausedAtMs: 0,
        accumulatedMs: resumed.accumulatedMs,
        pauseStartMs: 0,
        targetEndMs: resumed.targetEndMs,
        mode: 1,
        todoUuid: resumed.todoUuid,
        todoTitle: resumed.todoTitle,
        note: resumed.note,
      );
    }
  }

  bool _canResume(int resumeEpoch) {
    return !_isInBackground && _monitoring && resumeEpoch == _backgroundEpoch;
  }

  Future<void> _updateFloat(PomodoroRunState state) {
    final countUpAnchor = state.sessionStartMs + state.accumulatedMs;
    return FloatWindowService.update(
      endMs:
          state.mode == TimerMode.countUp ? countUpAnchor : state.targetEndMs,
      title: state.todoTitle ?? '自由专注',
      tags: state.tagNames,
      isLocal: true,
      mode: 1,
      isPaused: state.isPaused,
      accumulatedMs: state.accumulatedMs,
      pauseStartMs: state.pauseStartMs,
      note: state.note ?? '',
    );
  }

  PomodoroRunState _copyState(
    PomodoroRunState state, {
    required int targetEndMs,
    required bool isPaused,
    required bool strictWaitingForFlip,
    required int pausedAtMs,
    required int pauseStartMs,
    required int accumulatedMs,
    required List<PauseInterval> pauseIntervals,
  }) {
    return PomodoroRunState(
      phase: state.phase,
      sessionUuid: state.sessionUuid,
      targetEndMs: targetEndMs,
      currentCycle: state.currentCycle,
      totalCycles: state.totalCycles,
      focusSeconds: state.focusSeconds,
      breakSeconds: state.breakSeconds,
      todoUuid: state.todoUuid,
      todoTitle: state.todoTitle,
      tagUuids: List<String>.from(state.tagUuids),
      tagNames: List<String>.from(state.tagNames),
      sessionStartMs: state.sessionStartMs,
      plannedFocusSeconds: state.plannedFocusSeconds,
      mode: state.mode,
      strictFreeFocus: state.strictFreeFocus,
      strictWaitingForFlip: strictWaitingForFlip,
      isPaused: isPaused,
      pausedAtMs: pausedAtMs,
      accumulatedMs: accumulatedMs,
      pauseStartMs: pauseStartMs,
      pauseIntervals: pauseIntervals,
      planBlockId: state.planBlockId,
      note: state.note,
    );
  }

  void _scheduleSensorRestart() {
    if (_isInBackground || _sensorRestartTimer != null) return;
    if (_sensorRestartAttempts >= 3) return;
    final delaySeconds = 1 << _sensorRestartAttempts;
    _sensorRestartAttempts += 1;
    _sensorRestartTimer = Timer(Duration(seconds: delaySeconds), () {
      _sensorRestartTimer = null;
      unawaited(startMonitoring());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      pauseForBackground();
    } else if (state == AppLifecycleState.resumed) {
      _isInBackground = false;
      _sensorRestartAttempts = 0;
      unawaited(startMonitoring());
    }
  }

  void pauseForBackground() {
    // Stop reacting to sensor events before the asynchronous state write.
    // This closes the small window in which the app is already in the
    // background but a late sensor event could still resume the session.
    _isInBackground = true;
    _backgroundEpoch += 1;
    _monitoring = false;
    _pendingSensorEvent = null;
    _scheduleBackgroundPause();
  }

  void _scheduleBackgroundPause() {
    if (_backgroundPauseFuture != null) return;
    final future = _pauseForBackground();
    _backgroundPauseFuture = future;
    unawaited(_clearBackgroundPauseFuture(future));
  }

  Future<void> _clearBackgroundPauseFuture(Future<void> future) async {
    try {
      await future;
    } catch (_) {
      // The app may be closing while persistence or the platform haptic call
      // is in flight. Monitoring is already stopped, so leave the future
      // cleared and allow the next foreground transition to recover state.
    } finally {
      if (identical(_backgroundPauseFuture, future)) {
        _backgroundPauseFuture = null;
      }
    }
  }

  Future<void> _pauseForBackground() async {
    await stopMonitoring();
    await _enqueueStateMutation(() async {
      final saved = await PomodoroService.loadRunState();
      if (_isStrictFocusState(saved) && !saved!.isPaused) {
        await _pauseRunState(saved);
      }
    });
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    _sensorRestartTimer?.cancel();
    _sensorRestartTimer = null;
    await _runStateSub?.cancel();
    await stopMonitoring();
    await _sensorStateController.close();
  }
}
