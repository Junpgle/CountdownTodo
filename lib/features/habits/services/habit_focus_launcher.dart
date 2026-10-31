import 'package:flutter/material.dart';

import '../../../screens/pomodoro_screen.dart';
import '../../../screens/pomodoro/pomodoro_entry_intent.dart';
import '../../../services/pomodoro_service.dart';
import '../../../utils/page_transitions.dart';
import '../../thirty_day_challenge/models/thirty_day_challenge.dart';
import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../repositories/habit_repository.dart';
import '../services/habit_rule_resolver.dart';
import '../../../utils/app_dialogs.dart';

/// Opens the Pomodoro workbench with the habit or 30-day challenge focus context prepared.
abstract final class HabitFocusLauncher {
  static Future<void> open({
    required BuildContext context,
    required String username,
    required HabitGoal goal,
    HabitGoalRuleRevision? rule,
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

      var effectiveRule = rule;
      if (effectiveRule == null &&
          goal.sourceType != HabitSourceType.pomodoroTag) {
        try {
          final rules = await HabitRepository.getRules(habitUuid: goal.uuid);
          effectiveRule = HabitRuleResolver.effectiveRule(
            rules,
            DateTime.now(),
          );
        } catch (_) {}
      }

      // A habit can cover several Pomodoro tags, but that list defines which
      // sessions count toward the habit. It does not mean every topic should
      // be selected for one focus session. Keep the convenience only when the
      // habit has exactly one linked tag; otherwise let the user choose.
      List<String> tagUuids;
      if (goal.sourceType == HabitSourceType.pomodoroTag) {
        final linkedTagUuids = goal.sourceIds
            .where((uuid) => uuid.trim().isNotEmpty)
            .toSet()
            .toList();
        tagUuids = linkedTagUuids.length == 1
            ? linkedTagUuids
            : const <String>[];
      } else {
        final configuredTags =
            (effectiveRule?.reminderPolicy.focusTagUuids ?? const <String>[])
                .where((uuid) => uuid.trim().isNotEmpty)
                .toSet()
                .toList();
        if (configuredTags.isNotEmpty) {
          tagUuids = configuredTags;
        } else {
          tagUuids = await _matchTagByName(goal.name);
        }
      }

      final focusMinutes =
          goal.defaultFocusMinutes ??
          effectiveRule?.reminderPolicy.plannedDurationMinutes;

      if (!context.mounted) return;
      await _openPomodoro(
        context,
        username,
        sourceKey: sourceKey,
        initialEntry: PomodoroEntryIntent(
          tagUuids: tagUuids,
          focusMinutes: focusMinutes,
          habitUuid: goal.uuid,
          targetLabel: '${goal.icon} ${goal.name}',
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

  static Future<void> openForChallenge({
    required BuildContext context,
    required String username,
    required ThirtyDayChallengeState challengeState,
    required ThirtyDayChallengeTask task,
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

      var tagUuids = challengeState.focusTagUuids
          .where((uuid) => uuid.trim().isNotEmpty)
          .toSet()
          .toList();
      if (tagUuids.isEmpty) {
        tagUuids = await _matchTagByName(challengeState.challengeTitle);
      }

      if (!context.mounted) return;
      await _openPomodoro(
        context,
        username,
        sourceKey: sourceKey,
        initialEntry: PomodoroEntryIntent(
          tagUuids: tagUuids,
          focusMinutes: challengeState.effectivePlannedMinutes,
          challengeTaskId: task.id,
          targetLabel: '🎯 ${task.title}',
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

  static Future<List<String>> _matchTagByName(String name) async {
    try {
      final normalized = name.trim();
      if (normalized.isEmpty) return const <String>[];
      final tags = await PomodoroService.getTags();
      for (final tag in tags) {
        if (!tag.isDeleted &&
            !tag.isArchived &&
            tag.name.trim() == normalized) {
          return [tag.uuid];
        }
      }
    } catch (_) {}
    return const <String>[];
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
