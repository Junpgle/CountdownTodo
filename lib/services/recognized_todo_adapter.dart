import '../models.dart';
import 'item_semantics_service.dart';

/// Normalizes vision results before they enter the current TodoItem protocol.
///
/// Vision providers and saved custom prompts can still return the older
/// startTime/endTime/isAllDay shape. The app's current todo protocol uses
/// timeMode and stores a todo as either an unscheduled item, a date-only item,
/// or a single deadline. Keeping this conversion in one place prevents the
/// confirmation page and the persistence callback from making different
/// decisions.
class RecognizedTodoAdapter {
  RecognizedTodoAdapter._();

  static List<Map<String, dynamic>> normalizeImageResults(
    Iterable<Map<String, dynamic>> results, {
    DateTime? now,
  }) {
    return results
        .map((result) => normalizeImageResult(result, now: now))
        .toList();
  }

  static Map<String, dynamic> normalizeImageResult(
    Map<String, dynamic> source, {
    DateTime? now,
  }) {
    final result = Map<String, dynamic>.from(source);
    final effectiveNow = now ?? DateTime.now();
    final title = _stringValue(result['title'] ?? result['content']) ?? '';
    final remark = _stringValue(
      result['remark'] ?? result['notes'] ?? result['note'],
    );
    final kind = _stringValue(result['itemKind'] ?? result['item_kind']);
    final start = parseDateTime(
      result['startTime'] ??
          result['start_time'] ??
          result['createdDate'] ??
          result['created_date'],
    );
    final due = parseDateTime(
      result['endTime'] ??
          result['end_time'] ??
          result['dueDate'] ??
          result['due_date'],
    );
    final declaredModeName = _stringValue(
      result['timeMode'] ?? result['time_mode'],
    );
    final declaredMode = parseTimeMode(declaredModeName);
    final declaredAllDay = parseBool(
      result['isAllDay'] ?? result['is_all_day'],
    );
    final legacyDateOnlyRange = start != null &&
        due != null &&
        TodoItem.looksLikeLegacyDateOnlyRange(start, due);
    final isTodo = kind == null || kind.toLowerCase() == 'todo';
    final isSpecial = _isSpecialTodo(title, remark);
    final hasExplicitTiming = start != null || due != null;

    // Keep the result map consumable by both the confirmation page and the
    // persistence callback, even when a custom vision prompt used `content`,
    // `notes`, or snake_case keys.
    if (result['title'] == null && title.isNotEmpty) {
      result['title'] = title;
    }
    if (result['remark'] == null && remark != null) {
      result['remark'] = remark;
    }
    if (kind != null) {
      result['itemKind'] = _canonicalItemKind(kind);
    }

    var isDateOnly = declaredAllDay ||
        declaredMode == TodoTimeMode.dateOnly ||
        legacyDateOnlyRange;

    // Image notifications for a ready order/package are actionable today.
    // Older image prompts represented these as an unscheduled todo, which
    // meant Android had no date window in which to put the item on the island.
    // Scope this compatibility promotion to image-recognized special todos;
    // normal text-created pickup todos keep the new unscheduled semantics.
    final shouldPromoteSpecial = isSpecial &&
        isTodo &&
        !isDateOnly &&
        !hasExplicitTiming &&
        declaredMode != TodoTimeMode.deadline &&
        declaredModeName?.toLowerCase() != 'range';
    if (shouldPromoteSpecial) isDateOnly = true;

    if (isDateOnly) {
      result['isAllDay'] = true;
      result['timeMode'] = TodoTimeMode.dateOnly.name;
      final sourceDate =
          start ?? due ?? (shouldPromoteSpecial ? effectiveNow : null);
      if (sourceDate != null) {
        final day = DateTime(
          sourceDate.year,
          sourceDate.month,
          sourceDate.day,
        );
        result['startTime'] = day.toIso8601String();
        result['endTime'] = DateTime(
          sourceDate.year,
          sourceDate.month,
          sourceDate.day,
          23,
          59,
        ).toIso8601String();
        result['dueDate'] = result['endTime'];
      }
    } else if (!isTodo) {
      // Fixed schedules and plan blocks still use an explicit range while
      // they are being confirmed. Only todo results should be collapsed to
      // the new single-deadline representation.
    } else if (declaredMode == TodoTimeMode.deadline ||
        (declaredMode == null && due != null)) {
      // The current TodoItem stores a deadline as one point, not the old
      // execution range. Preserve the end point as the actionable deadline.
      final deadline = due ?? start;
      result['timeMode'] = TodoTimeMode.deadline.name;
      result['isAllDay'] = false;
      if (deadline != null) {
        final deadlineText = deadline.toIso8601String();
        result['startTime'] = deadlineText;
        result['endTime'] = deadlineText;
        result['dueDate'] = deadlineText;
      } else {
        _clearTimeFields(result);
      }
    } else {
      // `unscheduled` is the source of truth for a new todo. Clear timing
      // aliases as well, otherwise the persistence callback could fall back
      // to an old snake_case or createdDate value and recreate a deadline.
      result['timeMode'] = TodoTimeMode.unscheduled.name;
      result['isAllDay'] = false;
      _clearTimeFields(result);
    }

    return result;
  }

  static TodoTimeMode? parseTimeMode(dynamic raw) {
    final value = _stringValue(raw);
    if (value == null) return null;
    for (final mode in TodoTimeMode.values) {
      if (mode.name.toLowerCase() == value.toLowerCase()) return mode;
    }
    return null;
  }

  static bool parseBool(dynamic raw) {
    if (raw == true || raw == 1) return true;
    final value = raw?.toString().trim().toLowerCase();
    return value == 'true' || value == 'yes' || value == '1';
  }

  static DateTime? parseDateTime(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw.toLocal();
    if (raw is num) return _fromEpoch(raw.toInt());

    final value = raw.toString().trim();
    if (value.isEmpty) return null;
    final epoch = int.tryParse(value);
    if (epoch != null) return _fromEpoch(epoch);
    return DateTime.tryParse(value)?.toLocal();
  }

  static DateTime _fromEpoch(int value) {
    final milliseconds = value.abs() < 100000000000 ? value * 1000 : value;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true)
        .toLocal();
  }

  static bool _isSpecialTodo(String title, String? remark) {
    final text = '$title ${remark ?? ''}';
    return ItemSemanticsService.specialTodoTypeForTitle(title) != 'default' ||
        ItemSemanticsService.domainKindForText(text) == TodoDomainKind.pickup;
  }

  static String _canonicalItemKind(String kind) {
    return switch (kind.trim().toLowerCase()) {
      'todo' => 'todo',
      'fixedschedule' || 'schedule' => 'fixedSchedule',
      'planblock' => 'planBlock',
      'needsconfirmation' => 'needsConfirmation',
      _ => kind,
    };
  }

  static void _clearTimeFields(Map<String, dynamic> result) {
    for (final key in const [
      'startTime',
      'endTime',
      'dueDate',
      'start_time',
      'end_time',
      'due_date',
      'createdDate',
      'created_date',
    ]) {
      result[key] = null;
    }
  }

  static String? _stringValue(dynamic raw) {
    final value = raw?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }
}
