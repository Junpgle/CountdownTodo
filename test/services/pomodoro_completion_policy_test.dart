import 'package:flutter_test/flutter_test.dart';
import 'package:countdown_todo/screens/pomodoro/views/workbench_view.dart';

void main() {
  group('Pomodoro completion policy', () {
    test('notification finish ends the whole session instead of starting break',
        () {
      expect(
        PomodoroWorkbenchState.shouldStartBreakAfterCompletion(
          isCountUp: false,
          currentCycle: 1,
          cycles: 4,
          continueWithBreak: false,
        ),
        isFalse,
      );
    });

    test('natural non-final countdown focus still starts its break', () {
      expect(
        PomodoroWorkbenchState.shouldStartBreakAfterCompletion(
          isCountUp: false,
          currentCycle: 1,
          cycles: 4,
          continueWithBreak: true,
        ),
        isTrue,
      );
    });

    test('final or count-up sessions do not start a break', () {
      expect(
        PomodoroWorkbenchState.shouldStartBreakAfterCompletion(
          isCountUp: false,
          currentCycle: 4,
          cycles: 4,
          continueWithBreak: true,
        ),
        isFalse,
      );
      expect(
        PomodoroWorkbenchState.shouldStartBreakAfterCompletion(
          isCountUp: true,
          currentCycle: 1,
          cycles: 4,
          continueWithBreak: true,
        ),
        isFalse,
      );
    });
  });
}
