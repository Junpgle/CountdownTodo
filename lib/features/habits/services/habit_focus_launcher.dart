import 'package:flutter/material.dart';

import '../../../screens/pomodoro_screen.dart';
import '../../../screens/pomodoro/pomodoro_entry_intent.dart';
import '../../../services/pomodoro_service.dart';
import '../../../utils/page_transitions.dart';
import '../models/habit_goal.dart';
import '../../../utils/app_dialogs.dart';

/// Opens the Pomodoro workbench with the habit focus context prepared.
abstract final class HabitFocusLauncher {
  static Future<void> open({
    required BuildContext context,
    required String username,
    required HabitGoal goal,
    GlobalKey? sourceKey,
    VoidCallback? onReturned,
  }) async {
    try {
      final running = await PomodoroService.loadRunState();
      if (!context.mounted) return;

      if (running != null &&
          (running.phase == PomodoroPhase.focusing ||
              running.phase == PomodoroPhase.breaking)) {
        await _openPomodoro(context, username, sourceKey: sourceKey);
        return;
      }

      // A habit can cover several Pomodoro tags, but that list defines which
      // sessions count toward the habit. It does not mean every topic should
      // be selected for one focus session. Keep the convenience only when the
      // habit has exactly one linked tag; otherwise let the user choose.
      final linkedTagUuids = goal.sourceType == HabitSourceType.pomodoroTag
          ? goal.sourceIds
                .where((uuid) => uuid.trim().isNotEmpty)
                .toSet()
                .toList()
          : const <String>[];
      final tagUuids = linkedTagUuids.length == 1
          ? linkedTagUuids
          : const <String>[];
      if (!context.mounted) return;
      await _openPomodoro(
        context,
        username,
        sourceKey: sourceKey,
        initialEntry: PomodoroEntryIntent(
          tagUuids: tagUuids,
          focusMinutes: goal.defaultFocusMinutes,
        ),
      );
      if (context.mounted) onReturned?.call();
    } catch (error) {
      if (!context.mounted) return;
      AppSnackBars.showSnackBar(
        context,
        SnackBar(content: Text('打开番茄钟失败: $error')),
      );
    }
  }

  static Future<void> _openPomodoro(
    BuildContext context,
    String username, {
    GlobalKey? sourceKey,
    PomodoroEntryIntent? initialEntry,
  }) async {
    final page = PomodoroScreen(username: username, initialEntry: initialEntry);
    if (sourceKey == null) {
      await Navigator.of(context)
          .push(PageTransitions.material(builder: (_) => page));
      return;
    }
    await PageTransitions.pushFromRect<void>(
      context: context,
      sourceKey: sourceKey,
      placeholderIcon: Icons.timer_outlined,
      page: page,
    );
  }
}
