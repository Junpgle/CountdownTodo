import '../services/plan_todo_guard.dart';

/// A reviewed cancellation keeps the exact original rows and a stable result
/// timestamp. Retrying the same object can recognize its own committed result.
class PlanCleanupRequest {
  PlanCleanupRequest({
    required this.identity,
    required this.todoId,
    required this.fingerprint,
    required List<Map<String, Object?>> rows,
    required int cancelledAt,
  }) : rows = List.unmodifiable(
         rows.map((r) => Map<String, Object?>.unmodifiable(r)),
       ),
       cancelledAt = rows.fold<int>(
         cancelledAt,
         (value, row) => value > (row['updated_at'] as int? ?? 0)
             ? value
             : (row['updated_at'] as int? ?? 0) + 1,
       );

  final PlanTodoIdentity identity;
  final String todoId, fingerprint;
  final List<Map<String, Object?>> rows;
  final int cancelledAt;
  List<String> get ids => rows.map((r) => r['uuid'] as String).toList();
  Map<String, Object?> cancelledRow(Map<String, Object?> row) => {
    ...row,
    'status': 3,
    'version': (row['version'] as int) + 1,
    'updated_at': cancelledAt,
  };
  static bool sameRow(Map<String, Object?> a, Map<String, Object?> b) =>
      a.length == b.length &&
      a.keys.every((key) => b.containsKey(key) && a[key] == b[key]);

  int get unionMinutes {
    final intervals =
        rows.map((r) => (r['start_time'] as int, r['end_time'] as int)).toList()
          ..sort((a, b) => a.$1.compareTo(b.$1));
    int? start, end;
    var milliseconds = 0;
    for (final range in intervals) {
      if (end == null || range.$1 > end) {
        if (end != null) milliseconds += end - start!;
        start = range.$1;
        end = range.$2;
      } else if (range.$2 > end) {
        end = range.$2;
      }
    }
    if (end != null) milliseconds += end - start!;
    return milliseconds ~/ 60000;
  }

  bool get hasCalendarCopy => rows.any(
    (r) => (r['calendar_event_id']?.toString().trim() ?? '').isNotEmpty,
  );
}
