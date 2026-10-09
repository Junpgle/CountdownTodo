import 'package:flutter/material.dart';

import '../../../screens/pomodoro_screen.dart';
import '../../../services/pomodoro_control_service.dart';
import '../../../services/pomodoro_service.dart';
import '../../../utils/page_transitions.dart';
import '../models/habit_goal.dart';
import '../../../utils/app_dialogs.dart';

/// Starts focus for a habit and opens the shared Pomodoro screen.
abstract final class HabitFocusLauncher {
  static Future<void> open({
    required BuildContext context,
    required String username,
    required HabitGoal goal,
    VoidCallback? onReturned,
  }) async {
    try {
      final running = await PomodoroService.loadRunState();
      if (!context.mounted) return;

      if (running != null &&
          (running.phase == PomodoroPhase.focusing ||
              running.phase == PomodoroPhase.breaking)) {
        await _openPomodoro(context, username);
        return;
      }

      final settings = await PomodoroService.getSettings();
      if (!context.mounted) return;
      final tagUuids = goal.sourceType == HabitSourceType.pomodoroTag
          ? goal.sourceIds
          : const <String>[];
      await PomodoroControlService.startFocus(
        settings: settings,
        tagUuids: tagUuids,
        durationMinutes: goal.defaultFocusMinutes,
      );
      if (!context.mounted) return;
      await _openPomodoro(context, username);
      if (context.mounted) onReturned?.call();
    } catch (error) {
      if (!context.mounted) return;
      AppSnackBars.showSnackBar(
        context,
        SnackBar(content: Text('启动专注失败: $error')),
      );
    }
  }

  static Future<void> _openPomodoro(
    BuildContext context,
    String username,
  ) async {
    await Navigator.of(context).push(
      PageTransitions.material(
        builder: (_) => PomodoroScreen(username: username),
      ),
    );
  }
}
