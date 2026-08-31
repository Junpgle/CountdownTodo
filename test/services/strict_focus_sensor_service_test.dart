import 'package:flutter_test/flutter_test.dart';

import 'package:countdown_todo/services/pomodoro_service.dart';
import 'package:countdown_todo/services/power_save_mode_service.dart';
import 'package:countdown_todo/services/strict_focus_sensor_service.dart';

void main() {
  group('StrictFocusPoseDetector', () {
    Map<String, dynamic> up(DateTime base) => {
          'x': 0.0,
          'y': 0.0,
          'z': 9.8,
          'timestamp': base,
        };

    Map<String, dynamic> down(DateTime base) => {
          'x': 0.0,
          'y': 0.0,
          'z': -9.8,
          'timestamp': base,
        };

    Map<String, dynamic> upright(DateTime base) => {
          'x': 0.0,
          'y': 9.8,
          'z': 0.0,
          'timestamp': base,
        };

    StrictFocusSensorEvent? sample(
      StrictFocusPoseDetector detector,
      Map<String, dynamic> value,
    ) {
      return detector.addSample(
        x: value['x'] as double,
        y: value['y'] as double,
        z: value['z'] as double,
        timestamp: value['timestamp'] as DateTime,
      );
    }

    test('requires a stable face-up pose before accepting a flip', () {
      final detector = StrictFocusPoseDetector();
      final base = DateTime(2026, 1, 1);

      expect(sample(detector, up(base)), isNull);
      expect(
        sample(detector, up(base.add(const Duration(milliseconds: 700))))
            ?.state,
        StrictFocusSensorState.waitingForFlip,
      );
      expect(
        sample(detector, down(base.add(const Duration(milliseconds: 701)))),
        isNull,
      );
      expect(
        sample(detector, down(base.add(const Duration(milliseconds: 1401))))
            ?.state,
        StrictFocusSensorState.faceDown,
      );
    });

    test('does not start when the phone is already face-down', () {
      final detector = StrictFocusPoseDetector();
      final base = DateTime(2026, 1, 1);

      expect(sample(detector, down(base)), isNull);
      expect(
        sample(detector, down(base.add(const Duration(milliseconds: 900)))),
        isNull,
      );
      expect(
        sample(detector, up(base.add(const Duration(milliseconds: 1000)))),
        isNull,
      );
      expect(
        sample(detector, up(base.add(const Duration(milliseconds: 1700))))
            ?.state,
        StrictFocusSensorState.waitingForFlip,
      );
    });

    test('emits notFaceDown after a stable return or upright pose', () {
      final detector = StrictFocusPoseDetector();
      final base = DateTime(2026, 1, 1);

      sample(detector, up(base));
      sample(detector, up(base.add(const Duration(milliseconds: 700))));
      sample(detector, down(base.add(const Duration(milliseconds: 701))));
      expect(
        sample(detector, down(base.add(const Duration(milliseconds: 1401))))
            ?.state,
        StrictFocusSensorState.faceDown,
      );

      expect(
        sample(detector, upright(base.add(const Duration(milliseconds: 1402)))),
        isNull,
      );
      expect(
        sample(detector, upright(base.add(const Duration(milliseconds: 2102))))
            ?.state,
        StrictFocusSensorState.notFaceDown,
      );
    });
  });

  test('strict mode survives settings and run-state serialization', () {
    final settings = PomodoroSettings(
      mode: TimerMode.countUp,
      strictFreeFocus: true,
    );
    final restoredSettings = PomodoroSettings.fromJson(settings.toJson());
    expect(restoredSettings.strictFreeFocus, isTrue);

    final state = PomodoroRunState(
      mode: TimerMode.countUp,
      strictFreeFocus: true,
      strictWaitingForFlip: true,
      isPaused: true,
      pausedAtMs: 2000,
      pauseStartMs: 2000,
      sessionStartMs: 1000,
    );
    final restoredState = PomodoroRunState.fromJson(state.toJson());
    expect(restoredState.strictFreeFocus, isTrue);
    expect(restoredState.strictWaitingForFlip, isTrue);
    expect(restoredState.isPaused, isTrue);
  });

  test('power saver platform events publish only real state changes', () {
    addTearDown(() {
      PowerSaveModeService.updateFromPlatformForTesting(false);
    });

    var notifications = 0;
    void listener() => notifications++;
    PowerSaveModeService.enabledListenable.addListener(listener);
    addTearDown(
      () => PowerSaveModeService.enabledListenable.removeListener(listener),
    );

    PowerSaveModeService.updateFromPlatformForTesting(true);
    expect(PowerSaveModeService.enabledListenable.value, isTrue);
    expect(notifications, 1);

    PowerSaveModeService.updateFromPlatformForTesting(true);
    expect(notifications, 1);

    PowerSaveModeService.updateFromPlatformForTesting(0);
    expect(PowerSaveModeService.enabledListenable.value, isFalse);
    expect(notifications, 2);
  });
}
