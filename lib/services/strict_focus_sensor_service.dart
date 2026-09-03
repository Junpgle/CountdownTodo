import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

import '../utils/android_energy_policy.dart';
import '../utils/app_platform.dart';
import 'power_save_mode_service.dart';

/// The sensor states used by strict free focus.
enum StrictFocusSensorState {
  unavailable,
  waitingForFaceUp,
  waitingForFlip,
  faceDown,
  notFaceDown,
}

class StrictFocusSensorEvent {
  const StrictFocusSensorEvent(this.state, {this.error});

  final StrictFocusSensorState state;
  final Object? error;
}

/// Converts accelerometer samples into stable screen-up/screen-down changes.
///
/// The detector deliberately requires the phone to be face-up at least once
/// after monitoring starts. This prevents a session from starting immediately
/// when the user taps start while the phone is already face-down.
class StrictFocusPoseDetector {
  StrictFocusSensorState _state = StrictFocusSensorState.waitingForFaceUp;
  StrictFocusSensorState? _candidate;
  DateTime? _candidateSince;
  bool _hasSeenFaceUp = false;

  StrictFocusSensorState get state => _state;

  StrictFocusSensorEvent? addSample({
    required double x,
    required double y,
    required double z,
    DateTime? timestamp,
  }) {
    final now = timestamp ?? DateTime.now();
    final magnitude = math.sqrt(x * x + y * y + z * z);
    if (!magnitude.isFinite || magnitude < 6.0) {
      _clearCandidate();
      return null;
    }

    final normalizedZ = z / magnitude;
    final rawUp = normalizedZ >= 0.72;
    final rawDown = normalizedZ <= -0.72;

    if (!_hasSeenFaceUp) {
      if (!rawUp) {
        _clearCandidate();
        return null;
      }
      if (!_stableFor(StrictFocusSensorState.waitingForFlip, now)) {
        return null;
      }
      _hasSeenFaceUp = true;
      _state = StrictFocusSensorState.waitingForFlip;
      _clearCandidate();
      return const StrictFocusSensorEvent(
        StrictFocusSensorState.waitingForFlip,
      );
    }

    final target = rawDown
        ? StrictFocusSensorState.faceDown
        : StrictFocusSensorState.notFaceDown;
    if (!_stableFor(target, now)) return null;
    if (_state == target) return null;

    _state = target;
    _clearCandidate();
    return StrictFocusSensorEvent(target);
  }

  bool _stableFor(StrictFocusSensorState target, DateTime now) {
    if (_candidate != target) {
      _candidate = target;
      _candidateSince = now;
      return false;
    }
    final since = _candidateSince;
    return since != null &&
        now.difference(since) >= const Duration(milliseconds: 700);
  }

  void _clearCandidate() {
    _candidate = null;
    _candidateSince = null;
  }
}

/// Owns the mobile accelerometer subscription used by strict free focus.
class StrictFocusSensorService {
  final _eventController = StreamController<StrictFocusSensorEvent>.broadcast();
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  Timer? _noSampleTimer;
  bool _running = false;
  bool _powerSaveListenerRegistered = false;
  int _samplingRevision = 0;
  DateTime? _lastSampleAt;
  StrictFocusPoseDetector _detector = StrictFocusPoseDetector();

  Stream<StrictFocusSensorEvent> get events => _eventController.stream;

  Future<bool> start() async {
    await stop();
    if (!AppPlatform.isAndroid && !AppPlatform.isIOS) {
      _emit(const StrictFocusSensorEvent(StrictFocusSensorState.unavailable));
      return false;
    }

    _running = true;
    _registerPowerSaveListener();
    _detector = StrictFocusPoseDetector();
    _lastSampleAt = null;
    _emit(const StrictFocusSensorEvent(
      StrictFocusSensorState.waitingForFaceUp,
    ));

    try {
      _listenToAccelerometer();
      _noSampleTimer = Timer(const Duration(seconds: 3), () {
        if (_running && _lastSampleAt == null) {
          _emit(const StrictFocusSensorEvent(
            StrictFocusSensorState.unavailable,
          ));
        }
      });
      return true;
    } catch (error) {
      _emit(StrictFocusSensorEvent(
        StrictFocusSensorState.unavailable,
        error: error,
      ));
      await stop();
      return false;
    }
  }

  Future<void> stop() async {
    _running = false;
    _samplingRevision++;
    _unregisterPowerSaveListener();
    _noSampleTimer?.cancel();
    _noSampleTimer = null;
    await _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;
    _lastSampleAt = null;
  }

  void _listenToAccelerometer() {
    _accelerometerSubscription = accelerometerEventStream(
      samplingPeriod: AndroidEnergyPolicy.strictFocusSensorPeriod,
    ).listen(
      (event) {
        if (!_running) return;
        _lastSampleAt = DateTime.now();
        final next = _detector.addSample(
          x: event.x,
          y: event.y,
          z: event.z,
          timestamp: _lastSampleAt,
        );
        if (next != null) _emit(next);
      },
      onError: (Object error) {
        _emit(StrictFocusSensorEvent(
          StrictFocusSensorState.unavailable,
          error: error,
        ));
      },
      cancelOnError: true,
    );
  }

  void _registerPowerSaveListener() {
    if (_powerSaveListenerRegistered || !AppPlatform.isAndroid) return;
    PowerSaveModeService.enabledListenable.addListener(_onPowerSaveModeChanged);
    _powerSaveListenerRegistered = true;
  }

  void _unregisterPowerSaveListener() {
    if (!_powerSaveListenerRegistered) return;
    PowerSaveModeService.enabledListenable
        .removeListener(_onPowerSaveModeChanged);
    _powerSaveListenerRegistered = false;
  }

  void _onPowerSaveModeChanged() {
    if (_running) unawaited(_restartAccelerometerSampling());
  }

  Future<void> _restartAccelerometerSampling() async {
    final revision = ++_samplingRevision;
    final previous = _accelerometerSubscription;
    _accelerometerSubscription = null;
    try {
      await previous?.cancel();
    } catch (error) {
      _emit(StrictFocusSensorEvent(
        StrictFocusSensorState.unavailable,
        error: error,
      ));
    }
    if (!_running || revision != _samplingRevision) return;

    try {
      _listenToAccelerometer();
    } catch (error) {
      _emit(StrictFocusSensorEvent(
        StrictFocusSensorState.unavailable,
        error: error,
      ));
    }
  }

  void _emit(StrictFocusSensorEvent event) {
    if (!_eventController.isClosed) _eventController.add(event);
  }

  Future<void> dispose() async {
    await stop();
    await _eventController.close();
  }
}
