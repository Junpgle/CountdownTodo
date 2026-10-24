import 'dart:convert';

import '../models.dart';
import 'schedule_conflict_service.dart';

class FixedScheduleRescheduleDelta {
  const FixedScheduleRescheduleDelta({this.before, this.after});

  final FixedScheduleItem? before;
  final FixedScheduleItem? after;

  String get id => after?.id ?? before!.id;

  String get title => after?.title ?? before!.title;

  DateTime? get start =>
      _localTime(after == null ? before?.startTime : after!.startTime);

  DateTime? get end =>
      _localTime(after == null ? before?.endTime : after!.endTime);
}

class FixedScheduleReminderPreview {
  const FixedScheduleReminderPreview({
    required this.scheduleId,
    required this.scheduleTitle,
    required this.advanceMinutes,
    required this.eventStart,
    required this.triggerAt,
  });

  final String scheduleId;
  final String scheduleTitle;
  final int advanceMinutes;
  final DateTime eventStart;
  final DateTime triggerAt;

  bool isPastAt(DateTime now) => triggerAt.isBefore(now);
}

class FixedScheduleRescheduleImpact {
  const FixedScheduleRescheduleImpact({
    required this.deltas,
    required this.relatedTodoIds,
    required this.sourceTodos,
    required this.visibleTodos,
    required this.planBlocks,
    required this.planBlockSnapshots,
    required this.planConflicts,
    required this.reminders,
  });

  final List<FixedScheduleRescheduleDelta> deltas;
  final Set<String> relatedTodoIds;
  final List<TodoItem> sourceTodos;
  final List<TodoItem> visibleTodos;
  final List<TodoPlanBlock> planBlocks;
  final List<TodoPlanBlock> planBlockSnapshots;
  final List<ScheduleConflict> planConflicts;
  final List<FixedScheduleReminderPreview> reminders;

  bool get shouldReview => deltas.isNotEmpty;

  bool get hasImpact =>
      relatedTodoIds.isNotEmpty ||
      planConflicts.isNotEmpty ||
      reminders.isNotEmpty;

  String get snapshotSignature {
    final todos = sourceTodos.map((item) => item.toJson()).toList()
      ..sort(
        (left, right) =>
            left['uuid'].toString().compareTo(right['uuid'].toString()),
      );
    final plans = planBlockSnapshots.map((item) => item.toJson()).toList()
      ..sort(
        (left, right) =>
            left['uuid'].toString().compareTo(right['uuid'].toString()),
      );
    final changedSchedules = deltas
        .map(
          (delta) => {
            'before': delta.before?.toJson(),
            'after': delta.after?.toJson(),
          },
        )
        .toList();
    return jsonEncode({
      'schedules': changedSchedules,
      'todos': todos,
      'plans': plans,
      'relatedTodoIds': relatedTodoIds.toList()..sort(),
    });
  }

  List<FixedScheduleItem> get newTimedSchedules => deltas
      .map((delta) => delta.after)
      .whereType<FixedScheduleItem>()
      .where(
        (item) =>
            !item.isDeleted &&
            item.status != FixedScheduleStatus.cancelled &&
            item.startTime != null &&
            item.endTime != null &&
            item.endTime! > item.startTime!,
      )
      .toList(growable: false);
}

/// Builds a read-only impact snapshot for a fixed-schedule reschedule.
class FixedScheduleRescheduleImpactService {
  FixedScheduleRescheduleImpactService._();

  static FixedScheduleRescheduleImpact build({
    required List<FixedScheduleItem> baseline,
    required List<FixedScheduleItem> active,
    required List<FixedScheduleItem> changes,
    required FixedScheduleEditScope scope,
    required FixedScheduleItem selectedOccurrence,
    required FixedScheduleItem refreshItem,
    required List<TodoItem> todos,
    required List<TodoPlanBlock> planBlocks,
    required DateTime now,
  }) {
    final deltas = _deltas(
      baseline: baseline,
      active: active,
      changes: changes,
      scope: scope,
      selectedOccurrence: selectedOccurrence,
      refreshItem: refreshItem,
    );
    final relatedTodoIds = <String>{};
    for (final delta in deltas) {
      relatedTodoIds.addAll(_normalizedTodoIds(delta.before?.relatedTodoIds));
      relatedTodoIds.addAll(_normalizedTodoIds(delta.after?.relatedTodoIds));
    }

    final sourceTodos = todos
        .where((todo) => relatedTodoIds.contains(todo.id))
        .toList(growable: false);
    final visibleTodos =
        sourceTodos
            .where((todo) {
              if (todo.isDeleted) return false;
              return deltas.any((delta) {
                final beforeIds = _normalizedTodoIds(
                  delta.before?.relatedTodoIds,
                );
                final afterIds = _normalizedTodoIds(
                  delta.after?.relatedTodoIds,
                );
                final isRelated =
                    beforeIds.contains(todo.id) || afterIds.contains(todo.id);
                final matchingSchedule = afterIds.contains(todo.id)
                    ? delta.after
                    : delta.before;
                return isRelated &&
                    matchingSchedule != null &&
                    _normalizeTeamUuid(matchingSchedule.teamUuid) ==
                        _normalizeTeamUuid(todo.teamUuid);
              });
            })
            .toList(growable: false)
          ..sort(
            (left, right) =>
                left.title.toLowerCase().compareTo(right.title.toLowerCase()),
          );

    final newTimedSchedules = deltas
        .map((delta) => delta.after)
        .whereType<FixedScheduleItem>()
        .where(
          (item) =>
              !item.isDeleted &&
              item.status != FixedScheduleStatus.cancelled &&
              item.startTime != null &&
              item.endTime != null &&
              item.endTime! > item.startTime!,
        )
        .toList(growable: false);
    final candidateIds = newTimedSchedules.map((item) => item.id).toSet();
    final conflicts =
        ScheduleConflictService.detect(
          fixedSchedules: newTimedSchedules,
          planBlocks: planBlocks,
        ).where(
          (conflict) =>
              conflict.severity == ScheduleConflictSeverity.soft &&
              (candidateIds.contains(conflict.leftId) ||
                  candidateIds.contains(conflict.rightId)),
        );
    final plansById = {for (final block in planBlocks) block.id: block};
    final sortedConflicts = conflicts.toList()
      ..sort((left, right) {
        final startCompare = left.startTime.compareTo(right.startTime);
        if (startCompare != 0) return startCompare;
        final leftPlanId = candidateIds.contains(left.leftId)
            ? left.rightId
            : left.leftId;
        final rightPlanId = candidateIds.contains(right.leftId)
            ? right.rightId
            : right.leftId;
        return (plansById[leftPlanId]?.startTime ?? 0).compareTo(
          plansById[rightPlanId]?.startTime ?? 0,
        );
      });
    final affectedPlans = sortedConflicts
        .map((conflict) {
          final planId = candidateIds.contains(conflict.leftId)
              ? conflict.rightId
              : conflict.leftId;
          return plansById[planId];
        })
        .whereType<TodoPlanBlock>()
        .toList(growable: false);

    final reminders = <FixedScheduleReminderPreview>[];
    for (final item
        in deltas.map((delta) => delta.after).whereType<FixedScheduleItem>()) {
      if (item.isDeleted ||
          item.status == FixedScheduleStatus.cancelled ||
          item.status == FixedScheduleStatus.finished ||
          item.startTime == null) {
        continue;
      }
      final eventStart = DateTime.fromMillisecondsSinceEpoch(item.startTime!)
          .toLocal();
      if (!eventStart.isAfter(now)) continue;
      final advances =
          item.reminderMinutes.where((value) => value >= 0).toSet().toList()
            ..sort((left, right) => right.compareTo(left));
      for (
        var reminderIndex = 0;
        reminderIndex < advances.length && reminderIndex < 8;
        reminderIndex++
      ) {
        final advance = advances[reminderIndex];
        reminders.add(
          FixedScheduleReminderPreview(
            scheduleId: item.id,
            scheduleTitle: item.title,
            advanceMinutes: advance,
            eventStart: eventStart,
            triggerAt: eventStart.subtract(Duration(minutes: advance)),
          ),
        );
      }
    }
    reminders.sort((left, right) {
      final timeCompare = left.triggerAt.compareTo(right.triggerAt);
      if (timeCompare != 0) return timeCompare;
      final titleCompare = left.scheduleTitle.compareTo(right.scheduleTitle);
      if (titleCompare != 0) return titleCompare;
      return left.advanceMinutes.compareTo(right.advanceMinutes);
    });

    return FixedScheduleRescheduleImpact(
      deltas: List.unmodifiable(deltas),
      relatedTodoIds: Set.unmodifiable(relatedTodoIds),
      sourceTodos: List.unmodifiable(sourceTodos),
      visibleTodos: List.unmodifiable(visibleTodos),
      planBlocks: List.unmodifiable(affectedPlans),
      planBlockSnapshots: List.unmodifiable(planBlocks),
      planConflicts: List.unmodifiable(sortedConflicts),
      reminders: List.unmodifiable(reminders),
    );
  }

  static bool todoDeadlineNeedsReview(
    TodoItem todo,
    Iterable<FixedScheduleRescheduleDelta> deltas,
  ) {
    final due = todo.dueDate?.toLocal();
    if (due == null || todo.isDeleted) return false;
    for (final delta in deltas) {
      final schedule = delta.after;
      if (schedule == null ||
          schedule.startTime == null ||
          !_normalizedTodoIds(schedule.relatedTodoIds).contains(todo.id)) {
        continue;
      }
      final start = DateTime.fromMillisecondsSinceEpoch(schedule.startTime!)
          .toLocal();
      if (todo.isDateOnly) {
        if (DateTime(
          due.year,
          due.month,
          due.day,
        ).isAfter(DateTime(start.year, start.month, start.day))) {
          return true;
        }
      } else if (due.isAfter(start)) {
        return true;
      }
    }
    return false;
  }

  static List<FixedScheduleRescheduleDelta> _deltas({
    required List<FixedScheduleItem> baseline,
    required List<FixedScheduleItem> active,
    required List<FixedScheduleItem> changes,
    required FixedScheduleEditScope scope,
    required FixedScheduleItem selectedOccurrence,
    required FixedScheduleItem refreshItem,
  }) {
    final previousById = {
      for (final item in baseline)
        if (!item.isDeleted) item.id: item,
    };
    final deltas = <FixedScheduleRescheduleDelta>[];
    final consumedBefore = <String>{};
    final consumedAfter = <String>{};

    if (scope == FixedScheduleEditScope.occurrence &&
        selectedOccurrence.date != refreshItem.date) {
      deltas.add(
        FixedScheduleRescheduleDelta(
          before: selectedOccurrence,
          after: refreshItem,
        ),
      );
      consumedBefore.add(selectedOccurrence.id);
      consumedAfter.add(refreshItem.id);
    }

    for (final item in active) {
      if (consumedAfter.contains(item.id) || item.isDeleted) continue;
      final previous = previousById[item.id];
      if (previous == null ||
          _changesScheduleTimingOrAvailability(previous, item)) {
        deltas.add(FixedScheduleRescheduleDelta(before: previous, after: item));
      }
      if (previous != null) consumedBefore.add(previous.id);
      consumedAfter.add(item.id);
    }

    for (final item in changes) {
      final previous = previousById[item.id];
      if (previous == null || consumedBefore.contains(item.id)) continue;
      if (item.isDeleted ||
          (item.status == FixedScheduleStatus.cancelled &&
              previous.status != FixedScheduleStatus.cancelled)) {
        deltas.add(FixedScheduleRescheduleDelta(before: previous, after: null));
        consumedBefore.add(item.id);
      }
    }

    deltas.sort((left, right) {
      final leftDate = left.after?.date ?? left.before?.date ?? '';
      final rightDate = right.after?.date ?? right.before?.date ?? '';
      final dateCompare = leftDate.compareTo(rightDate);
      if (dateCompare != 0) return dateCompare;
      final leftStart = left.after?.startTime ?? left.before?.startTime ?? 0;
      final rightStart = right.after?.startTime ?? right.before?.startTime ?? 0;
      return leftStart.compareTo(rightStart);
    });
    return deltas;
  }

  static bool _changesScheduleTimingOrAvailability(
    FixedScheduleItem before,
    FixedScheduleItem after,
  ) =>
      before.date != after.date ||
      before.startTime != after.startTime ||
      before.endTime != after.endTime ||
      (before.status == FixedScheduleStatus.cancelled) !=
          (after.status == FixedScheduleStatus.cancelled);

  static Set<String> _normalizedTodoIds(Iterable<String>? ids) =>
      (ids ?? const <String>[])
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toSet();

  static String? _normalizeTeamUuid(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}

DateTime? _localTime(int? milliseconds) => milliseconds == null
    ? null
    : DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
