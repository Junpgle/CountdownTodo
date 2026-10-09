import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/plan_availability.dart';
import '../screens/course_screens.dart';
import '../screens/pomodoro_screen.dart';
import '../screens/todo_plan_screen.dart';
import '../services/missed_plan_recovery_service.dart';
import '../services/plan_availability_service.dart';
import '../utils/app_dialogs.dart';
import '../utils/page_transitions.dart';
import 'plan_block_editor_sheet.dart';

final _openingRecovery = <String>{};

String _period(int start, int end) =>
    '${DateFormat('MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(start))}–${DateFormat('MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(end))}';

Future<int?> _recoveryDialog(
  BuildContext context,
  WidgetBuilder builder,
) async {
  ModalRoute<dynamic>? route;
  final result = await showAppDialog<int>(
    context: context,
    builder: (context) {
      route = ModalRoute.of(context);
      return builder(context);
    },
  );
  await route?.completed;
  return result;
}

Future<bool> _reviewFollowups(
  BuildContext context,
  MissedPlanRecoveryContext state,
) async {
  if (!state.hasCurrentFocus && state.followups.isEmpty) return true;
  final result = await _recoveryDialog(
    context,
    (dialogContext) => AlertDialog(
      scrollable: true,
      title: Text(state.hasCurrentFocus ? '该待办正在专注' : '已有后续规划'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(state.todo.title),
          if (state.hasCurrentFocus) const Text('请先查看当前专注，本次暂不新建。'),
          for (final block in state.followups)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_period(block.startTime, block.endTime)),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('取消'),
        ),
        TextButton(
          key: const ValueKey('plan-recovery-view-existing'),
          onPressed: () => Navigator.pop(dialogContext, 2),
          child: Text(state.hasCurrentFocus ? '查看当前专注' : '查看已有规划'),
        ),
        if (!state.hasCurrentFocus)
          FilledButton(
            key: const ValueKey('plan-recovery-add-again'),
            onPressed: () => Navigator.pop(dialogContext, 1),
            child: const Text('仍新建一次'),
          ),
      ],
    ),
  );
  if (!context.mounted) return false;
  if (result == 2) {
    await Navigator.of(context).push(
      PageTransitions.material(
        builder: (_) => state.hasCurrentFocus
            ? PomodoroScreen(username: state.username)
            : TodoPlanScreen(
                username: state.username,
                initialDate: DateTime.fromMillisecondsSinceEpoch(
                  state.followups.first.startTime,
                ),
              ),
      ),
    );
    return false;
  }
  if (result != 1) return false;
  state.acknowledgeFollowups();
  return true;
}

/// Three formal entries use this same read/confirmation/new-draft route.
Future<void> showMissedPlanRecovery({
  required BuildContext context,
  required String username,
  required String sourceId,
  required VoidCallback onSaved,
  MissedPlanRecoveryService service = const MissedPlanRecoveryService(),
}) async {
  final key = '$username/$sourceId';
  if (!_openingRecovery.add(key)) return;
  try {
    final state = await service.read(username, sourceId);
    if (!context.mounted ||
        !await _reviewFollowups(context, state) ||
        !context.mounted) {
      return;
    }
    final today = service.now;
    final lower = DateTime(today.year, today.month, today.day, 8);
    final start = PlanAvailabilityService.minuteCeiling(
      today.isAfter(lower) ? today : lower,
    );
    final draft = state.draft(start);
    await showPlanBlockEditorPage<void>(
      context: context,
      builder: (_) => PlanBlockEditorSheet(
        fullPage: true,
        recovery: state,
        recoveryService: service,
        username: username,
        todos: [state.todo],
        todoGroups: const [],
        initialTodoId: state.todo.id,
        autoFillEstimateOnTodoChange: false,
        startTime: start,
        endTime: DateTime.fromMillisecondsSinceEpoch(draft.endTime),
        clock: service.clock,
        onSaved: onSaved,
        availabilityLoader: (query, {bool forceRefresh = false}) =>
            service.availability.read(query, forceRefresh: forceRefresh),
        reviewRecovery: (editorContext) async {
          final latest = await service.read(username, sourceId);
          if (latest.sourceFingerprint != state.sourceFingerprint) {
            throw const MissedPlanRecoveryException('原漏做规划已变化，请重新打开；当前输入已保留');
          }
          if (!editorContext.mounted) return;
          if (await _reviewFollowups(editorContext, latest)) {
            state.acknowledgedFollowups.addAll(latest.acknowledgedFollowups);
          }
        },
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    final todo = error is MissedPlanRecoveryException ? error.todo : null;
    final result = await _recoveryDialog(
      context,
      (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('暂时无法重新安排'),
        content: Text(
          error is PlanAvailabilityException ? error.message : '读取失败，请重试',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
          if (todo != null)
            TextButton(
              key: const ValueKey('plan-recovery-view-todo'),
              onPressed: () => Navigator.pop(dialogContext, 1),
              child: const Text('查看待办'),
            ),
        ],
      ),
    );
    if (result == 1 && context.mounted && todo != null) {
      await Navigator.of(context).push(
        PageTransitions.material(builder: (_) => TodoDetailScreen(todo: todo)),
      );
    }
  } finally {
    _openingRecovery.remove(key);
  }
}
