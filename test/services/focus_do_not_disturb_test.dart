import 'package:flutter_test/flutter_test.dart';

import 'package:countdown_todo/services/pomodoro_service.dart';
import 'package:countdown_todo/services/pomodoro_sync_service.dart';

void main() {
  test('persists the focus Do Not Disturb setting', () {
    final settings = PomodoroSettings(
      doNotDisturbDuringFocus: true,
    );

    final restored = PomodoroSettings.fromJson(settings.toJson());

    expect(restored.doNotDisturbDuringFocus, isTrue);
  });

  test('persists the focus Do Not Disturb run-state flag', () {
    final state = PomodoroRunState(
      phase: PomodoroPhase.focusing,
      doNotDisturbDuringFocus: true,
      sessionStartMs: 1000,
      targetEndMs: 2000,
    );

    final restored = PomodoroRunState.fromJson(state.toJson());

    expect(restored.doNotDisturbDuringFocus, isTrue);
    expect(restored.phase, PomodoroPhase.focusing);
  });

  test('accepts compatible cross-device Do Not Disturb values', () {
    final fromString = CrossDevicePomodoroState.fromJson({
      'action': 'START',
      'do_not_disturb': 'true',
    });
    final fromNumber = CrossDevicePomodoroState.fromJson({
      'action': 'START',
      'do_not_disturb': 1,
    });

    expect(fromString.doNotDisturb, isTrue);
    expect(fromNumber.doNotDisturb, isTrue);
    expect(fromString.toJson()['do_not_disturb'], isTrue);
  });
}
