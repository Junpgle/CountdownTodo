import '../../models.dart';

/// Optional task context to prepare on the Pomodoro workbench before focus
/// starts. Supplying this intent never starts the timer by itself.
class PomodoroEntryIntent {
  const PomodoroEntryIntent({
    this.boundTodo,
    this.planBlockId,
    this.tagUuids,
    this.focusMinutes,
    this.habitUuid,
    this.challengeTaskId,
    this.targetLabel,
  });

  factory PomodoroEntryIntent.forPlanBlock({
    required TodoItem boundTodo,
    required TodoPlanBlock planBlock,
  }) {
    final configuredMinutes = planBlock.pomodoroRounds > 0
        ? planBlock.pomodoroMinutes * planBlock.pomodoroRounds
        : planBlock.plannedMinutes > 0
        ? planBlock.plannedMinutes
        : ((planBlock.endTime - planBlock.startTime) / 60000).round();
    return PomodoroEntryIntent(
      boundTodo: boundTodo,
      planBlockId: planBlock.uuid,
      focusMinutes: configuredMinutes.clamp(1, 120).toInt(),
    );
  }

  final TodoItem? boundTodo;
  final String? planBlockId;

  /// Explicit tags to preselect. When null, the workbench may recommend tags
  /// for [boundTodo]. An empty list explicitly clears the previous selection.
  final List<String>? tagUuids;

  /// One-time focus duration override for the next start.
  final int? focusMinutes;

  /// Optional bound habit UUID for automatic check-in upon focus completion.
  final String? habitUuid;

  /// Optional bound 30-day challenge task ID for automatic completion upon focus completion.
  final int? challengeTaskId;

  /// Optional display title when focusing on a habit or challenge without a TodoItem.
  final String? targetLabel;
}
