/// Removes obsolete todo instructions from saved AI prompts before appending
/// the current protocol. Recognition prompts also discard legacy all-day
/// fields; chat prompts retain lines that only mention those fields.
abstract final class LegacyAiPromptSanitizer {
  static final RegExp _legacyAction = RegExp(
    r'\bplan_todos\b|\[(?:PLAN_TODOS|CREATE_TODO|UPDATE_TODO|'
    r'COMPLETE_TODO|DELETE_TODO|RESCHEDULE_TODO)\]',
    caseSensitive: false,
  );

  static final RegExp _legacyTodoContainer = RegExp(
    r'["\x27\x60]?(?:todos|todo_list|updates|items)["\x27\x60]?[ \t]*:',
    caseSensitive: false,
  );

  static String sanitize(
    String prompt, {
    required String fallback,
    bool removeLegacyAllDayFields = false,
  }) {
    final sanitized = prompt
        .split('\n')
        .where((line) {
          if (_legacyAction.hasMatch(line)) return false;
          if (removeLegacyAllDayFields &&
              (line.contains('isAllDay') || line.contains('is_all_day'))) {
            return false;
          }

          final lower = line.toLowerCase();
          final mentionsTodo = lower.contains('todo') || line.contains('待办');
          final mentionsLegacyRange = lower.contains('starttime') ||
              lower.contains('endtime') ||
              lower.contains('start_time') ||
              lower.contains('end_time') ||
              line.contains('起止') ||
              (line.contains('00:00') && line.contains('23:59'));
          final mentionsLegacyTodoContainer =
              _legacyTodoContainer.hasMatch(line) && mentionsTodo;
          return !(mentionsTodo &&
              (mentionsLegacyRange || mentionsLegacyTodoContainer));
        })
        .join('\n')
        .trim();
    return sanitized.isEmpty ? fallback : sanitized;
  }
}
