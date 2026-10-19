import '../../models.dart';

/// Optional task context to prepare on the Pomodoro workbench before focus
/// starts. Supplying this intent never starts the timer by itself.
class PomodoroEntryIntent {
  const PomodoroEntryIntent({
    this.boundTodo,
    this.planBlockId,
    this.tagUuids,
    this.focusMinutes,
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
}
