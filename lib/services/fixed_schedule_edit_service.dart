import '../models.dart';
import 'fixed_schedule_recurrence_service.dart';

/// Builds the exact set of fixed-schedule rows affected by an edit.
class FixedScheduleEditService {
  FixedScheduleEditService._();

  static ({
    List<FixedScheduleItem> affected,
    List<FixedScheduleItem> changes,
    FixedScheduleItem refreshItem,
  })
  buildChanges({
    required FixedScheduleEditScope scope,
    required FixedScheduleItem selectedOccurrence,
    required List<FixedScheduleItem> existingSeries,
    required FixedScheduleItem editedTemplate,
    required RecurrenceType recurrence,
    required DateTime recurrenceEndDate,
    int customIntervalDays = 1,
    bool applyTeamUuid = false,
    bool applyRelatedTodoIds = false,
  }) {
    return switch (scope) {
      FixedScheduleEditScope.occurrence => _editOccurrence(
        selectedOccurrence: selectedOccurrence,
        editedTemplate: editedTemplate,
        applyTeamUuid: applyTeamUuid,
        applyRelatedTodoIds: applyRelatedTodoIds,
      ),
      FixedScheduleEditScope.future => _editFuture(
        selectedOccurrence: selectedOccurrence,
        existingSeries: existingSeries,
        editedTemplate: editedTemplate,
        recurrence: recurrence,
        recurrenceEndDate: recurrenceEndDate,
        customIntervalDays: customIntervalDays,
        applyTeamUuid: applyTeamUuid,
        applyRelatedTodoIds: applyRelatedTodoIds,
      ),
      FixedScheduleEditScope.series => _editSeries(
        selectedOccurrence: selectedOccurrence,
        existingSeries: existingSeries,
        editedTemplate: editedTemplate,
        recurrence: recurrence,
        recurrenceEndDate: recurrenceEndDate,
        customIntervalDays: customIntervalDays,
        applyTeamUuid: applyTeamUuid,
        applyRelatedTodoIds: applyRelatedTodoIds,
      ),
    };
  }

  static ({
    List<FixedScheduleItem> affected,
    List<FixedScheduleItem> changes,
    FixedScheduleItem refreshItem,
  })
  _editOccurrence({
    required FixedScheduleItem selectedOccurrence,
    required FixedScheduleItem editedTemplate,
    required bool applyTeamUuid,
    required bool applyRelatedTodoIds,
  }) {
    if (editedTemplate.date == selectedOccurrence.date) {
      final updated = FixedScheduleItem.fromJson(selectedOccurrence.toJson());
      _copyEditableFields(
        updated,
        editedTemplate,
        applyTeamUuid: applyTeamUuid,
        applyRelatedTodoIds: applyRelatedTodoIds,
      );
      updated.markAsChanged();
      return (affected: [updated], changes: [updated], refreshItem: updated);
    }

    // A moved occurrence leaves a cancelled slot in its original series and
    // becomes a new standalone schedule. Keeping the original row preserves
    // the series anchor and avoids re-creating the old slot on later edits.
    final cancelledSlot = FixedScheduleItem.fromJson(
      selectedOccurrence.toJson(),
    );
    if (cancelledSlot.status != FixedScheduleStatus.cancelled) {
      cancelledSlot.status = FixedScheduleStatus.cancelled;
      cancelledSlot.markAsChanged();
    }
    final movedOccurrence = FixedScheduleItem(
      title: editedTemplate.title,
      date: editedTemplate.date,
      startTime: editedTemplate.startTime,
      endTime: editedTemplate.endTime,
      status: editedTemplate.status,
      source: selectedOccurrence.source,
      location: editedTemplate.location,
      remark: editedTemplate.remark,
      reminderMinutes: editedTemplate.reminderMinutes,
      timezone: editedTemplate.timezone,
      relatedTodoIds: applyRelatedTodoIds
          ? editedTemplate.relatedTodoIds
          : selectedOccurrence.relatedTodoIds,
      teamUuid: applyTeamUuid
          ? editedTemplate.teamUuid
          : selectedOccurrence.teamUuid,
      ownerUserId: selectedOccurrence.ownerUserId,
      deviceId: selectedOccurrence.deviceId,
    );
    movedOccurrence.markAsChanged();
    return (
      affected: [movedOccurrence],
      changes: [cancelledSlot, movedOccurrence],
      refreshItem: movedOccurrence,
    );
  }

  static ({
    List<FixedScheduleItem> affected,
    List<FixedScheduleItem> changes,
    FixedScheduleItem refreshItem,
  })
  _editFuture({
    required FixedScheduleItem selectedOccurrence,
    required List<FixedScheduleItem> existingSeries,
    required FixedScheduleItem editedTemplate,
    required RecurrenceType recurrence,
    required DateTime recurrenceEndDate,
    required int customIntervalDays,
    required bool applyTeamUuid,
    required bool applyRelatedTodoIds,
  }) {
    final selectedDate = DateTime.tryParse(selectedOccurrence.date);
    if (selectedDate == null) {
      return _editOccurrence(
        selectedOccurrence: selectedOccurrence,
        editedTemplate: editedTemplate,
        applyTeamUuid: applyTeamUuid,
        applyRelatedTodoIds: applyRelatedTodoIds,
      );
    }
    final affectedSeries = existingSeries.where((item) {
      final date = DateTime.tryParse(item.date);
      return date != null && !date.isBefore(selectedDate);
    }).toList();
    if (!affectedSeries.any((item) => item.id == selectedOccurrence.id)) {
      affectedSeries.add(selectedOccurrence);
    }

    final template = FixedScheduleItem.fromJson(editedTemplate.toJson())
      ..id = selectedOccurrence.id
      ..recurrenceSeriesId = recurrence == RecurrenceType.none
          ? null
          : selectedOccurrence.id;
    final rebuilt = FixedScheduleRecurrenceService.rebuildSeries(
      template: template,
      existingSeries: affectedSeries,
      recurrence: recurrence,
      recurrenceEndDate: recurrence == RecurrenceType.none
          ? DateTime.tryParse(template.date) ?? recurrenceEndDate
          : recurrenceEndDate,
      customIntervalDays: customIntervalDays,
      applyTeamUuid: applyTeamUuid,
      applyRelatedTodoIds: applyRelatedTodoIds,
    );
    final affected = _applySelectedStatus(
      rebuilt.active,
      rebuilt.changes,
      selectedOccurrence,
      editedTemplate.status,
    );
    return (
      affected: affected,
      changes: rebuilt.changes,
      refreshItem: _findById(affected, selectedOccurrence.id) ?? affected.first,
    );
  }

  static ({
    List<FixedScheduleItem> affected,
    List<FixedScheduleItem> changes,
    FixedScheduleItem refreshItem,
  })
  _editSeries({
    required FixedScheduleItem selectedOccurrence,
    required List<FixedScheduleItem> existingSeries,
    required FixedScheduleItem editedTemplate,
    required RecurrenceType recurrence,
    required DateTime recurrenceEndDate,
    required int customIntervalDays,
    required bool applyTeamUuid,
    required bool applyRelatedTodoIds,
  }) {
    final rootId = selectedOccurrence.recurrenceSeriesId?.trim();
    final template = FixedScheduleItem.fromJson(editedTemplate.toJson())
      ..id = rootId?.isNotEmpty == true
          ? rootId!
          : existingSeries
                .where((item) => !item.isDeleted)
                .map((item) => DateTime.tryParse(item.date))
                .whereType<DateTime>()
                .isEmpty
          ? selectedOccurrence.id
          : _earliestOccurrence(existingSeries).id
      ..recurrenceSeriesId = recurrence == RecurrenceType.none
          ? null
          : (rootId?.isNotEmpty == true ? rootId : null);
    final rebuilt = FixedScheduleRecurrenceService.rebuildSeries(
      template: template,
      existingSeries: existingSeries,
      recurrence: recurrence,
      recurrenceEndDate: recurrence == RecurrenceType.none
          ? DateTime.tryParse(template.date) ?? recurrenceEndDate
          : recurrenceEndDate,
      customIntervalDays: customIntervalDays,
      applyTeamUuid: applyTeamUuid,
      applyRelatedTodoIds: applyRelatedTodoIds,
    );
    final affected = _applySelectedStatus(
      rebuilt.active,
      rebuilt.changes,
      selectedOccurrence,
      editedTemplate.status,
    );
    return (
      affected: affected,
      changes: rebuilt.changes,
      refreshItem: _findById(affected, selectedOccurrence.id) ?? affected.first,
    );
  }

  static List<FixedScheduleItem> _applySelectedStatus(
    List<FixedScheduleItem> active,
    List<FixedScheduleItem> changes,
    FixedScheduleItem selected,
    FixedScheduleStatus status,
  ) {
    final target = _findById(active, selected.id);
    if (target == null || target.status == status) return active;
    target.status = status;
    if (!changes.any((item) => item.id == target.id)) {
      target.markAsChanged();
      changes.add(target);
    }
    return active;
  }

  static FixedScheduleItem? _findById(
    List<FixedScheduleItem> items,
    String id,
  ) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  static FixedScheduleItem _earliestOccurrence(List<FixedScheduleItem> items) {
    final active = items.where((item) => !item.isDeleted).toList()
      ..sort((left, right) => left.date.compareTo(right.date));
    return active.isEmpty ? items.first : active.first;
  }

  static void _copyEditableFields(
    FixedScheduleItem target,
    FixedScheduleItem template, {
    required bool applyTeamUuid,
    required bool applyRelatedTodoIds,
  }) {
    target
      ..title = template.title
      ..date = template.date
      ..startTime = template.startTime
      ..endTime = template.endTime
      ..location = template.location
      ..remark = template.remark
      ..reminderMinutes = List<int>.from(template.reminderMinutes)
      ..timezone = template.timezone;
    if (applyTeamUuid) target.teamUuid = template.teamUuid;
    if (applyRelatedTodoIds) {
      target.relatedTodoIds = List<String>.from(template.relatedTodoIds);
    }
    target.status = template.status;
  }
}
