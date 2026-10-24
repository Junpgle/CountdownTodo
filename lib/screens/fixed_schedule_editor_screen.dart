import 'dart:async';

import '../widgets/floating_glass_control.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../services/api_service.dart';
import '../services/course_service.dart';
import '../services/fixed_schedule_edit_service.dart';
import '../services/fixed_schedule_recurrence_service.dart';
import '../services/fixed_schedule_reschedule_impact_service.dart';
import '../services/reminder_schedule_service.dart';
import '../services/schedule_conflict_service.dart';
import '../storage_service.dart';
import '../utils/app_dialogs.dart';
import '../utils/page_transitions.dart';
import '../utils/semester_week_context.dart';
import '../utils/time_utils.dart';
import '../widgets/fixed_schedule_reschedule_impact_dialog.dart';
import 'fixed_schedule_related_todo_picker_screen.dart';
import 'course_screens.dart';

class FixedScheduleEditorScreen extends StatefulWidget {
  const FixedScheduleEditorScreen({
    super.key,
    required this.username,
    this.item,
    this.initialTeamUuid,
    this.onSave,
    this.onSaveAll,
    this.onSaved,
    this.rescheduleReminders,
    this.syncOnSave = true,
    this.loadTeams,
  });

  final String username;
  final FixedScheduleItem? item;
  final String? initialTeamUuid;
  final Future<void> Function(FixedScheduleItem)? onSave;
  final Future<void> Function(List<FixedScheduleItem>)? onSaveAll;
  final ValueChanged<FixedScheduleItem>? onSaved;
  final Future<void> Function()? rescheduleReminders;
  final bool syncOnSave;
  final Future<List<dynamic>> Function()? loadTeams;

  @override
  State<FixedScheduleEditorScreen> createState() =>
      _FixedScheduleEditorScreenState();
}

class _FixedScheduleEditorScreenState extends State<FixedScheduleEditorScreen> {
  static const _supportedRecurrences = [
    RecurrenceType.none,
    RecurrenceType.daily,
    RecurrenceType.weekdays,
    RecurrenceType.weekly,
    RecurrenceType.monthly,
    RecurrenceType.yearly,
    RecurrenceType.customDays,
  ];

  late final TextEditingController _titleController;
  late final TextEditingController _locationController;
  late final TextEditingController _remarkController;
  late final TextEditingController _customIntervalController;
  late DateTime _date;
  late bool _timeTbd;
  late bool _endTimeTbd;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late Set<int> _reminderMinutes;
  late Set<String> _relatedTodoIds;
  Set<String> _baselineRelatedTodoIds = {};
  String? _baselineTeamUuid;
  late bool _cancelled;
  late RecurrenceType _recurrence;
  late DateTime _recurrenceEndDate;
  late FixedScheduleEditScope _editScope;
  DateTime? _seriesStartDate;
  DateTime? _seriesEndDate;
  String? _selectedTeamUuid;
  List<Team> _teams = [];
  List<FixedScheduleItem> _seriesItems = [];
  bool _loadingContext = true;
  bool _saving = false;
  bool _canChangeTeam = true;
  bool _supportsRangeEdit = false;
  int? _currentUserId;
  SemesterWeekContext? _semesterWeekContext;

  bool get _editing => widget.item != null;

  FixedScheduleItem? get _selectedOccurrence {
    final item = widget.item;
    if (item == null) return null;
    for (final loaded in _seriesItems) {
      if (loaded.id == item.id) return loaded;
    }
    return item;
  }

  DateTime get _selectedOccurrenceDate =>
      DateTime.tryParse(_selectedOccurrence?.date ?? '')?.toLocal() ?? _date;

  bool get _hasExternalScheduleIdentity {
    final item = _selectedOccurrence;
    return item != null &&
        (item.source == FixedScheduleSource.imported ||
            item.source == FixedScheduleSource.calendar ||
            item.externalSource?.trim().isNotEmpty == true ||
            item.externalId?.trim().isNotEmpty == true);
  }

  bool get _forcedOccurrenceEdit =>
      _editing &&
      _selectedOccurrence!.recurrence != RecurrenceType.none &&
      _hasExternalScheduleIdentity;

  FixedScheduleEditScope get _effectiveEditScope => _forcedOccurrenceEdit
      ? FixedScheduleEditScope.occurrence
      : (_supportsRangeEdit ? _editScope : FixedScheduleEditScope.series);

  bool get _isOccurrenceScope =>
      _effectiveEditScope == FixedScheduleEditScope.occurrence;

  bool get _canEditRecurrence => !_isOccurrenceScope;

  bool get _relatedTodoIdsChanged =>
      _relatedTodoIds.length != _baselineRelatedTodoIds.length ||
      !_relatedTodoIds.containsAll(_baselineRelatedTodoIds);

  String? _normalizeTeamUuid(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  String _scopeLabel(FixedScheduleEditScope scope) => switch (scope) {
    FixedScheduleEditScope.occurrence => '仅本次',
    FixedScheduleEditScope.future => '本次及以后',
    FixedScheduleEditScope.series => '整个系列',
  };

  String _scopeDescription(FixedScheduleEditScope scope) {
    final selected = _selectedOccurrence;
    final selectedDate = selected == null
        ? _selectedOccurrenceDate
        : DateTime.tryParse(selected.date)?.toLocal() ??
              _selectedOccurrenceDate;
    final active = _seriesItems.where((item) => !item.isDeleted).toList()
      ..sort((left, right) => left.date.compareTo(right.date));
    final previousCount = active.where((item) {
      final date = DateTime.tryParse(item.date);
      return date != null && date.isBefore(selectedDate);
    }).length;
    final currentCount = switch (scope) {
      FixedScheduleEditScope.occurrence => 1,
      FixedScheduleEditScope.future => active.length - previousCount,
      FixedScheduleEditScope.series => active.length,
    };
    final start = scope == FixedScheduleEditScope.series
        ? (_seriesStartDate ?? selectedDate)
        : selectedDate;
    final end = scope == FixedScheduleEditScope.occurrence
        ? selectedDate
        : (_seriesEndDate ?? selectedDate);
    final dates = start == end
        ? AppTimeFormats.date(start)
        : '${AppTimeFormats.date(start)} – ${AppTimeFormats.date(end)}';
    if (scope == FixedScheduleEditScope.future) {
      return '此前 $previousCount 场保持不变 · 当前范围 $currentCount 场 · $dates';
    }
    if (scope == FixedScheduleEditScope.occurrence) {
      return '只修改当前场次 · $dates';
    }
    return '当前 $currentCount 场 · $dates';
  }

  Future<void> _chooseEditScope() async {
    final scope = await showAppDialog<FixedScheduleEditScope>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('修改范围'),
        content: RadioGroup<FixedScheduleEditScope>(
          groupValue: _editScope,
          onChanged: (value) => Navigator.pop(dialogContext, value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final scope in FixedScheduleEditScope.values)
                RadioListTile<FixedScheduleEditScope>(
                  value: scope,
                  title: Text(_scopeLabel(scope)),
                  subtitle: Text(_scopeDescription(scope)),
                  contentPadding: EdgeInsets.zero,
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (scope != null && mounted) _selectEditScope(scope);
  }

  void _selectEditScope(FixedScheduleEditScope? scope) {
    if (scope == null || scope == _editScope) return;
    setState(() {
      _editScope = scope;
      _date = scope == FixedScheduleEditScope.series
          ? (_seriesStartDate ?? _selectedOccurrenceDate)
          : _selectedOccurrenceDate;
      if (_recurrenceEndDate.isBefore(_date)) {
        _recurrenceEndDate = FixedScheduleRecurrenceService.defaultEndDate(
          startDate: _date,
          recurrence: _recurrence,
          customIntervalDays:
              int.tryParse(_customIntervalController.text.trim()) ?? 1,
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _titleController = TextEditingController(text: item?.title ?? '');
    _locationController = TextEditingController(text: item?.location ?? '');
    _remarkController = TextEditingController(text: item?.remark ?? '');
    _customIntervalController = TextEditingController(
      text: item?.customIntervalDays?.toString() ?? '2',
    );
    _date = DateTime.tryParse(item?.date ?? '')?.toLocal() ?? DateTime.now();
    final start = item?.startTime == null
        ? DateTime(_date.year, _date.month, _date.day, 9)
        : DateTime.fromMillisecondsSinceEpoch(item!.startTime!).toLocal();
    final end = item?.endTime == null
        ? start.add(const Duration(hours: 1))
        : DateTime.fromMillisecondsSinceEpoch(item!.endTime!).toLocal();
    _timeTbd = item?.isTimeTbd ?? false;
    _endTimeTbd = item?.isEndTimeTbd ?? false;
    _startTime = TimeOfDay.fromDateTime(start);
    _endTime = TimeOfDay.fromDateTime(end);
    _reminderMinutes = {
      ...?item?.reminderMinutes.where((minutes) => minutes >= 0),
    };
    _relatedTodoIds = {...?item?.relatedTodoIds};
    _baselineRelatedTodoIds = Set<String>.from(_relatedTodoIds);
    _baselineTeamUuid = _normalizeTeamUuid(
      item?.teamUuid ?? widget.initialTeamUuid,
    );
    if (item == null && _reminderMinutes.isEmpty) {
      _reminderMinutes.add(15);
    }
    _cancelled = item?.status == FixedScheduleStatus.cancelled;
    _recurrence = item?.recurrence ?? RecurrenceType.none;
    _editScope = FixedScheduleEditScope.series;
    _recurrenceEndDate = FixedScheduleRecurrenceService.defaultEndDate(
      startDate: _date,
      recurrence: _recurrence,
      customIntervalDays: item?.customIntervalDays ?? 1,
    );
    _selectedTeamUuid = item?.teamUuid ?? widget.initialTeamUuid;
    _seriesItems = item == null ? [] : [item];
    _loadSemesterWeekContext();
    _loadEditorContext();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _remarkController.dispose();
    _customIntervalController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showAppDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: _date,
      semesterWeekContext: _semesterWeekContext,
    );
    if (picked != null && mounted) {
      setState(() {
        _date = picked;
        if (_recurrence != RecurrenceType.none &&
            _recurrenceEndDate.isBefore(_date)) {
          _recurrenceEndDate = FixedScheduleRecurrenceService.defaultEndDate(
            startDate: _date,
            recurrence: _recurrence,
            customIntervalDays:
                int.tryParse(_customIntervalController.text.trim()) ?? 1,
          );
        }
      });
    }
  }

  Future<void> _pickStartTime() async {
    final picked = await showAppTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked != null && mounted) setState(() => _startTime = picked);
  }

  Future<void> _pickEndTime() async {
    final picked = await showAppTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (picked != null && mounted) setState(() => _endTime = picked);
  }

  Future<void> _pickRecurrenceEndDate() async {
    final picked = await showAppDatePicker(
      context: context,
      firstDate: _date,
      lastDate: DateTime(_date.year + 5, 12, 31),
      initialDate: _recurrenceEndDate.isBefore(_date)
          ? _date
          : _recurrenceEndDate,
      semesterWeekContext: _semesterWeekContext,
    );
    if (picked != null && mounted) {
      setState(() => _recurrenceEndDate = picked);
    }
  }

  Future<void> _loadSemesterWeekContext() async {
    final semesterWeekContext = await SemesterWeekContext.loadForToday();
    if (!mounted) return;
    setState(() => _semesterWeekContext = semesterWeekContext);
  }

  String _dateWithSemesterWeek(DateTime date, String formattedDate) =>
      _semesterWeekContext?.appendWeekLabel(date, formattedDate) ??
      formattedDate;

  Future<void> _loadEditorContext() async {
    final results = await Future.wait<dynamic>([
      widget.loadTeams?.call() ?? ApiService.fetchTeams(),
      SharedPreferences.getInstance(),
      if (_editing)
        StorageService.getFixedSchedules(widget.username, includeDeleted: true),
    ]);
    if (!mounted) return;

    final teams = (results.first as List<dynamic>)
        .whereType<Map>()
        .map((raw) => Team.fromJson(Map<String, dynamic>.from(raw)))
        .where((team) => team.uuid.isNotEmpty)
        .toList();
    var seriesItems = _seriesItems;
    DateTime? seriesStartDate;
    DateTime? seriesEndDate;
    var supportsRangeEdit = false;
    if (_editing && results.length > 2) {
      final allItems = results[2] as List<FixedScheduleItem>;
      final passedItem = widget.item!;
      final current = allItems.lastWhere(
        (item) => item.id == passedItem.id,
        orElse: () => passedItem,
      );
      final seriesId = current.recurrenceSeriesId;
      seriesItems = allItems.where((item) {
        if (item.id == current.id) return true;
        return seriesId != null &&
            seriesId.isNotEmpty &&
            item.recurrenceSeriesId == seriesId;
      }).toList();
      final activeDates =
          seriesItems
              .where((item) => !item.isDeleted)
              .map((item) => DateTime.tryParse(item.date)?.toLocal())
              .whereType<DateTime>()
              .toList()
            ..sort();
      if (activeDates.isNotEmpty) {
        seriesStartDate = activeDates.first;
        seriesEndDate = activeDates.last;
      }
      final sourceIsAppManaged =
          current.source == FixedScheduleSource.manual ||
          current.source == FixedScheduleSource.ai;
      supportsRangeEdit =
          current.recurrence != RecurrenceType.none &&
          activeDates.length > 1 &&
          sourceIsAppManaged &&
          current.externalSource?.trim().isNotEmpty != true &&
          current.externalId?.trim().isNotEmpty != true;
      _loadLatestEditorValues(
        current,
        seriesStartDate: seriesStartDate,
        seriesEndDate: seriesEndDate,
        activeDates: activeDates,
        supportsRangeEdit: supportsRangeEdit,
      );
    }

    setState(() {
      _teams = teams;
      _seriesItems = seriesItems;
      _seriesStartDate = seriesStartDate;
      _seriesEndDate = seriesEndDate;
      _supportsRangeEdit = supportsRangeEdit;
      _currentUserId = (results[1] as SharedPreferences).getInt(
        'current_user_id',
      );
      final item = _selectedOccurrence;
      _canChangeTeam = item == null || item.canChangeTeamFor(_currentUserId);
      _loadingContext = false;
    });
  }

  void _loadLatestEditorValues(
    FixedScheduleItem item, {
    required DateTime? seriesStartDate,
    required DateTime? seriesEndDate,
    required List<DateTime> activeDates,
    required bool supportsRangeEdit,
  }) {
    _titleController.text = item.title;
    _locationController.text = item.location ?? '';
    _remarkController.text = item.remark ?? '';
    final selectedDate = DateTime.tryParse(item.date)?.toLocal() ?? _date;
    _date = item.recurrence != RecurrenceType.none && supportsRangeEdit
        ? (seriesStartDate ?? selectedDate)
        : selectedDate;
    final start = item.startTime == null
        ? DateTime(_date.year, _date.month, _date.day, 9)
        : DateTime.fromMillisecondsSinceEpoch(item.startTime!).toLocal();
    final end = item.endTime == null
        ? DateTime(_date.year, _date.month, _date.day, 10)
        : DateTime.fromMillisecondsSinceEpoch(item.endTime!).toLocal();
    _timeTbd = item.startTime == null;
    _startTime = TimeOfDay(hour: start.hour, minute: start.minute);
    _endTimeTbd = item.startTime != null && item.endTime == null;
    _endTime = TimeOfDay(hour: end.hour, minute: end.minute);
    _reminderMinutes = item.reminderMinutes.toSet();
    if (_reminderMinutes.isEmpty) _reminderMinutes.add(15);
    _cancelled = item.status == FixedScheduleStatus.cancelled;
    _recurrence = item.recurrence;
    final inferredInterval = item.recurrence == RecurrenceType.customDays
        ? FixedScheduleRecurrenceService.inferCustomIntervalDays(activeDates)
        : null;
    final interval = item.customIntervalDays ?? inferredInterval ?? 2;
    _customIntervalController.text = interval.toString();
    _recurrenceEndDate =
        seriesEndDate ??
        FixedScheduleRecurrenceService.defaultEndDate(
          startDate: _date,
          recurrence: _recurrence,
          customIntervalDays: interval,
        );
    _selectedTeamUuid = item.teamUuid ?? widget.initialTeamUuid;
    _relatedTodoIds = item.relatedTodoIds.toSet();
    _baselineRelatedTodoIds = Set<String>.from(_relatedTodoIds);
    _baselineTeamUuid = _normalizeTeamUuid(item.teamUuid);
  }

  Future<void> _chooseRelatedTodos() async {
    final selected = await Navigator.of(context).push<Set<String>>(
      PageTransitions.material(
        builder: (_) => FixedScheduleRelatedTodoPickerScreen(
          username: widget.username,
          teamUuid: _selectedTeamUuid,
          initialSelectedIds: Set<String>.from(_relatedTodoIds),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _relatedTodoIds = Set<String>.from(selected));
  }

  Future<String?> _invalidRelatedTodoMessage() async {
    if (_relatedTodoIds.isEmpty) return null;
    final todos = await StorageService.getTodosForFixedScheduleRelations(
      widget.username,
    );
    final todosById = {for (final todo in todos) todo.id: todo};
    final targetTeamUuid = _normalizeTeamUuid(_selectedTeamUuid);
    final invalidIds = _relatedTodoIds.where((id) {
      final todo = todosById[id];
      return todo == null ||
          todo.isDeleted ||
          _normalizeTeamUuid(todo.teamUuid) != targetTeamUuid;
    });
    if (invalidIds.isEmpty) return null;
    return '请在“关联待办”中移除已删除或当前日程不可见的项目后再保存';
  }

  String _relatedTodoReviewText(
    FixedScheduleEditScope scope,
    ({
      List<FixedScheduleItem> active,
      List<FixedScheduleItem> changes,
      FixedScheduleItem refreshItem,
    })
    plan,
    int keptEarlier,
  ) {
    final added = _relatedTodoIds.difference(_baselineRelatedTodoIds).length;
    final removed = _baselineRelatedTodoIds.difference(_relatedTodoIds).length;
    final changes = [
      if (added > 0) '新增 $added 项',
      if (removed > 0) '移除 $removed 项',
    ].join('，');
    if (scope == FixedScheduleEditScope.occurrence) {
      return '关联待办：$changes，仅影响当前场次。';
    }
    if (scope == FixedScheduleEditScope.future) {
      return '关联待办：$changes，应用于本次及以后 ${plan.active.length} 场；此前 $keptEarlier 场不变。';
    }
    return '关联待办：$changes，应用于整个系列 ${plan.active.length} 场。';
  }

  DateTime _atTime(TimeOfDay time) =>
      DateTime(_date.year, _date.month, _date.day, time.hour, time.minute);

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('请输入固定日程名称')),
      );
      return;
    }

    final start = _timeTbd ? null : _atTime(_startTime);
    final end = _timeTbd || _endTimeTbd ? null : _atTime(_endTime);
    if (start != null && end != null && !end.isAfter(start)) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('结束时间必须晚于开始时间')),
      );
      return;
    }
    final existing = _selectedOccurrence;
    if (_forcedOccurrenceEdit &&
        existing != null &&
        AppTimeFormats.date(_date) != existing.date) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('该重复日程由外部日历管理，请在来源日历中移动场次')),
      );
      return;
    }
    final scope = existing == null
        ? FixedScheduleEditScope.series
        : _effectiveEditScope;
    final recurrence =
        scope == FixedScheduleEditScope.occurrence && existing != null
        ? existing.recurrence
        : _recurrence;
    if (scope != FixedScheduleEditScope.occurrence &&
        recurrence != RecurrenceType.none &&
        _recurrenceEndDate.isBefore(_date)) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('重复结束日期不能早于首次日期')),
      );
      return;
    }
    final customIntervalDays = int.tryParse(
      _customIntervalController.text.trim(),
    );
    if (scope != FixedScheduleEditScope.occurrence &&
        recurrence == RecurrenceType.customDays &&
        (customIntervalDays == null || customIntervalDays < 1)) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('请输入大于 0 的自定义重复天数')),
      );
      return;
    }

    setState(() => _saving = true);
    final teamScopeChanged =
        _normalizeTeamUuid(_selectedTeamUuid) != _baselineTeamUuid;
    if (_relatedTodoIdsChanged || teamScopeChanged) {
      try {
        final invalidMessage = await _invalidRelatedTodoMessage();
        if (!mounted) return;
        if (invalidMessage != null) {
          setState(() => _saving = false);
          AppSnackBars.showSnackBar(
            context,
            SnackBar(content: Text(invalidMessage)),
          );
          return;
        }
      } catch (_) {
        if (!mounted) return;
        setState(() => _saving = false);
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('读取关联待办失败，关系改动未保存，请重试')),
        );
        return;
      }
    }
    final dateText = AppTimeFormats.date(_date);
    final item = existing == null
        ? FixedScheduleItem(title: title, date: dateText)
        : FixedScheduleItem.fromJson(existing.toJson());
    item
      ..title = title
      ..date = dateText
      ..startTime = start?.millisecondsSinceEpoch
      ..endTime = end?.millisecondsSinceEpoch
      ..location = _locationController.text.trim().isEmpty
          ? null
          : _locationController.text.trim()
      ..remark = _remarkController.text.trim().isEmpty
          ? null
          : _remarkController.text.trim()
      ..reminderMinutes = (_reminderMinutes.toList()
        ..sort((left, right) => right.compareTo(left)))
      ..timezone = DateTime.now().timeZoneName
      ..recurrence = recurrence
      ..customIntervalDays = recurrence == RecurrenceType.customDays
          ? customIntervalDays
          : null
      ..teamUuid = _selectedTeamUuid
      ..relatedTodoIds = _relatedTodoIds.toList()
      ..ownerUserId = existing?.ownerUserId ?? _currentUserId
      ..status = _cancelled
          ? FixedScheduleStatus.cancelled
          : existing?.status == FixedScheduleStatus.finished
          ? FixedScheduleStatus.finished
          : FixedScheduleStatus.scheduled;

    late final ({
      List<FixedScheduleItem> active,
      List<FixedScheduleItem> changes,
      FixedScheduleItem refreshItem,
    })
    plan;
    try {
      if (existing == null) {
        final created = FixedScheduleRecurrenceService.rebuildSeries(
          template: item,
          existingSeries: const [],
          recurrence: recurrence,
          recurrenceEndDate: recurrence == RecurrenceType.none
              ? _date
              : _recurrenceEndDate,
          customIntervalDays: customIntervalDays ?? 1,
          applyTeamUuid: true,
        );
        plan = (
          active: created.active,
          changes: created.changes,
          refreshItem: created.active.first,
        );
      } else {
        final edited = FixedScheduleEditService.buildChanges(
          scope: scope,
          selectedOccurrence: existing,
          existingSeries: _seriesItems,
          editedTemplate: item,
          recurrence: recurrence,
          recurrenceEndDate: scope == FixedScheduleEditScope.occurrence
              ? DateTime.tryParse(existing.date) ?? _date
              : _recurrenceEndDate,
          customIntervalDays: customIntervalDays ?? 1,
          applyTeamUuid: _selectedTeamUuid != existing.teamUuid,
          applyRelatedTodoIds: _relatedTodoIdsChanged,
        );
        plan = (
          active: edited.affected,
          changes: edited.changes,
          refreshItem: edited.refreshItem,
        );
      }
    } on FixedScheduleRecurrenceLimitException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppSnackBars.showSnackBar(
        context,
        SnackBar(content: Text(error.toString())),
      );
      return;
    }

    if (existing != null &&
        _supportsRangeEdit &&
        !await _confirmEditScope(scope, plan, existing)) {
      if (mounted) setState(() => _saving = false);
      return;
    }

    FixedScheduleRescheduleImpact? reviewedImpact;
    try {
      reviewedImpact = await _reviewRescheduleImpact(plan, scope, existing);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('读取改期影响失败，未保存；请重试或返回修改')),
      );
      return;
    }
    if (reviewedImpact == null) {
      if (mounted) setState(() => _saving = false);
      return;
    }

    final conflicts = await _conflictsFor(plan.changes);
    if (!mounted) return;
    final remainingConflicts = reviewedImpact.hasImpact
        ? conflicts
              .where(
                (conflict) =>
                    conflict.severity == ScheduleConflictSeverity.hard,
              )
              .toList(growable: false)
        : conflicts;
    if (remainingConflicts.isNotEmpty &&
        !await _confirmConflicts(remainingConflicts)) {
      if (mounted) setState(() => _saving = false);
      return;
    }

    late final bool saved;
    try {
      saved = await _saveEditedItems(
        plan.changes,
        refreshItem: plan.refreshItem,
        reviewedImpact: reviewedImpact,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('保存失败，改期内容仍保留在编辑页，请重试')),
      );
      return;
    }
    if (!saved) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('日程或关联内容已变化，请重新复核后再保存')),
      );
      return;
    }
    widget.onSaved?.call(plan.refreshItem);
    if (!mounted) return;
    Navigator.pop(context, plan.refreshItem);
  }

  Future<bool> _confirmEditScope(
    FixedScheduleEditScope scope,
    ({
      List<FixedScheduleItem> active,
      List<FixedScheduleItem> changes,
      FixedScheduleItem refreshItem,
    })
    plan,
    FixedScheduleItem selected,
  ) async {
    final activeSeries = _seriesItems.where((item) => !item.isDeleted).toList();
    final selectedDate = DateTime.tryParse(selected.date)?.toLocal();
    final keptEarlier =
        scope == FixedScheduleEditScope.future && selectedDate != null
        ? activeSeries.where((item) {
            final date = DateTime.tryParse(item.date)?.toLocal();
            return date != null && date.isBefore(selectedDate);
          }).length
        : 0;
    final removedCount = plan.changes.where((item) => item.isDeleted).length;
    final movedOccurrence =
        scope == FixedScheduleEditScope.occurrence &&
        plan.refreshItem.date != selected.date;
    final content = <Widget>[
      Text(_confirmedScopeSummary(scope, plan, selected)),
      if (keptEarlier > 0) Text('此前 $keptEarlier 场保持原样。'),
      if (_relatedTodoIdsChanged)
        Text(_relatedTodoReviewText(scope, plan, keptEarlier)),
      if (movedOccurrence) const Text('原日期场次将标记为已取消，并在新日期创建一条独立日程。'),
      if (removedCount > 0) Text('按新规则将有 $removedCount 场不再保留，写入逻辑删除。'),
      if (scope == FixedScheduleEditScope.occurrence)
        const Text('重复规则和其他场次不变；取消状态只作用于当前场次。'),
      if (scope != FixedScheduleEditScope.occurrence)
        Text(
          '本次保存会更新 ${plan.active.length} 场，重复规则从${scope == FixedScheduleEditScope.future ? '当前场次' : '系列首次日期'}起生效。',
        ),
    ];
    return await showAppDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('确认${_scopeLabel(scope)}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < content.length; index++) ...[
                  if (index > 0) const SizedBox(height: 8),
                  content[index],
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('返回修改'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text('应用到${_scopeLabel(scope)}'),
              ),
            ],
          ),
        ) ??
        false;
  }

  String _confirmedScopeSummary(
    FixedScheduleEditScope scope,
    ({
      List<FixedScheduleItem> active,
      List<FixedScheduleItem> changes,
      FixedScheduleItem refreshItem,
    })
    plan,
    FixedScheduleItem selected,
  ) {
    final actualDates =
        plan.active
            .map((item) => DateTime.tryParse(item.date))
            .whereType<DateTime>()
            .toList()
          ..sort();
    final resultRange = actualDates.isEmpty
        ? selected.date
        : (actualDates.first == actualDates.last
              ? AppTimeFormats.date(actualDates.first)
              : '${AppTimeFormats.date(actualDates.first)} – ${AppTimeFormats.date(actualDates.last)}');
    if (scope == FixedScheduleEditScope.occurrence) {
      return plan.refreshItem.date == selected.date
          ? '只修改当前场次 · ${selected.date}'
          : '只修改当前场次 · ${selected.date} → ${plan.refreshItem.date}';
    }

    final currentCount = _seriesItems.where((item) => !item.isDeleted).length;
    if (scope == FixedScheduleEditScope.future) {
      final selectedDate = DateTime.tryParse(selected.date);
      final previousCount = selectedDate == null
          ? 0
          : _seriesItems.where((item) {
              final date = DateTime.tryParse(item.date);
              return !item.isDeleted &&
                  date != null &&
                  date.isBefore(selectedDate);
            }).length;
      return '此前 $previousCount 场保持不变 · 本次及以后形成 ${plan.active.length} 场 · $resultRange';
    }

    final oldRange = _seriesStartDate == null || _seriesEndDate == null
        ? '当前 $currentCount 场'
        : '${AppTimeFormats.date(_seriesStartDate!)} – ${AppTimeFormats.date(_seriesEndDate!)}';
    final newEndDate = AppTimeFormats.date(_recurrenceEndDate);
    final oldEndDate = _seriesEndDate == null
        ? ''
        : AppTimeFormats.date(_seriesEndDate!);
    final endDateSummary =
        _recurrence != RecurrenceType.none &&
            oldEndDate.isNotEmpty &&
            oldEndDate != newEndDate
        ? ' · 结束日期 $oldEndDate → $newEndDate'
        : '';
    return '整个系列：$oldRange → ${plan.active.length} 场 · $resultRange$endDateSummary';
  }

  Future<bool> _saveEditedItems(
    List<FixedScheduleItem> items, {
    required FixedScheduleItem refreshItem,
    FixedScheduleRescheduleImpact? reviewedImpact,
  }) async {
    final saveAllHandler = widget.onSaveAll;
    if (saveAllHandler != null) {
      await saveAllHandler(items);
    } else {
      final saved = await StorageService.saveFixedSchedulesIfUnchanged(
        widget.username,
        baseline: _seriesItems,
        items: items,
        reviewedTodoIds: reviewedImpact?.shouldReview == true
            ? reviewedImpact!.relatedTodoIds.toList()
            : const [],
        reviewedTodos: reviewedImpact?.shouldReview == true
            ? reviewedImpact!.sourceTodos
            : const [],
        reviewedPlanBlocks: reviewedImpact?.shouldReview == true
            ? reviewedImpact!.planBlockSnapshots
            : null,
        sync: widget.syncOnSave,
      );
      if (!saved) return false;
      final saveHandler = widget.onSave;
      if (saveHandler != null) await saveHandler(refreshItem);
    }
    final reminderRefresh =
        widget.rescheduleReminders?.call() ??
        ReminderScheduleService.scheduleFromStorage(
          widget.username,
          force: true,
        );
    unawaited(
      reminderRefresh.catchError((Object error, StackTrace stackTrace) {
        debugPrint('Fixed schedule reminder refresh failed: $error');
      }),
    );
    return true;
  }

  Future<FixedScheduleRescheduleImpact?> _reviewRescheduleImpact(
    ({
      List<FixedScheduleItem> active,
      List<FixedScheduleItem> changes,
      FixedScheduleItem refreshItem,
    })
    plan,
    FixedScheduleEditScope scope,
    FixedScheduleItem? selected,
  ) async {
    if (selected == null) {
      return FixedScheduleRescheduleImpactService.build(
        baseline: const [],
        active: const [],
        changes: const [],
        scope: scope,
        selectedOccurrence: plan.refreshItem,
        refreshItem: plan.refreshItem,
        todos: const [],
        planBlocks: const [],
        now: DateTime.now(),
      );
    }
    final occurrence = selected;
    var impact = await _loadRescheduleImpact(plan, scope, occurrence);
    var hasPresentedReview = false;
    while (true) {
      if (impact.hasImpact || hasPresentedReview) {
        hasPresentedReview = true;
        if (!mounted) return null;
        final accepted = await showDialog<FixedScheduleRescheduleImpact>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => FixedScheduleRescheduleImpactDialog(
            impact: impact,
            reload: () => _loadRescheduleImpact(plan, scope, occurrence),
            openTodo: _openImpactTodo,
            openPlan: _openImpactPlan,
          ),
        );
        if (!mounted || accepted == null) return null;
        final latest = await _loadRescheduleImpact(plan, scope, occurrence);
        if (latest.snapshotSignature == accepted.snapshotSignature) {
          return latest;
        }
        impact = latest;
        continue;
      }

      // Even an empty review result is guarded at commit time. Re-read once
      // here so a plan or relationship added during the first query cannot
      // silently turn an empty result into an unreviewed impact.
      final latest = await _loadRescheduleImpact(plan, scope, occurrence);
      if (latest.snapshotSignature == impact.snapshotSignature) return latest;
      impact = latest;
    }
  }

  Future<FixedScheduleRescheduleImpact> _loadRescheduleImpact(
    ({
      List<FixedScheduleItem> active,
      List<FixedScheduleItem> changes,
      FixedScheduleItem refreshItem,
    })
    plan,
    FixedScheduleEditScope scope,
    FixedScheduleItem selected,
  ) async {
    Future<void> ensureSameAccount() async {
      if ((await StorageService.getLoginSession() ?? 'default') !=
          widget.username) {
        throw StateError('账户已切换，请重新打开固定日程');
      }
    }

    await ensureSameAccount();
    final empty = FixedScheduleRescheduleImpactService.build(
      baseline: _seriesItems,
      active: plan.active,
      changes: plan.changes,
      scope: scope,
      selectedOccurrence: selected,
      refreshItem: plan.refreshItem,
      todos: const [],
      planBlocks: const [],
      now: DateTime.now(),
    );
    final reads = await Future.wait<dynamic>([
      if (empty.relatedTodoIds.isNotEmpty)
        StorageService.getTodosForFixedScheduleRelations(widget.username)
      else
        Future.value(const <TodoItem>[]),
      if (empty.newTimedSchedules.isNotEmpty)
        StorageService.getPlanBlocksOverlappingFixedSchedules(
          widget.username,
          empty.newTimedSchedules,
        )
      else
        Future.value(const <TodoPlanBlock>[]),
    ]);
    await ensureSameAccount();
    return FixedScheduleRescheduleImpactService.build(
      baseline: _seriesItems,
      active: plan.active,
      changes: plan.changes,
      scope: scope,
      selectedOccurrence: selected,
      refreshItem: plan.refreshItem,
      todos: reads[0] as List<TodoItem>,
      planBlocks: reads[1] as List<TodoPlanBlock>,
      now: DateTime.now(),
    );
  }

  Future<void> _openImpactTodo(TodoItem todo) async {
    if ((await StorageService.getLoginSession() ?? 'default') !=
        widget.username) {
      throw StateError('账户已切换，请返回后重新打开日程');
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      PageTransitions.material(builder: (_) => TodoDetailScreen(todo: todo)),
    );
  }

  Future<void> _openImpactPlan(TodoPlanBlock block) async {
    if ((await StorageService.getLoginSession() ?? 'default') !=
        widget.username) {
      throw StateError('账户已切换，请返回后重新打开日程');
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      PageTransitions.material(
        builder: (_) =>
            PlanBlockDetailScreen(block: block, username: widget.username),
      ),
    );
  }

  Future<List<ScheduleConflict>> _conflictsFor(
    List<FixedScheduleItem> candidates,
  ) async {
    final timedCandidates = candidates
        .where((item) => item.startTime != null && item.endTime != null)
        .toList();
    if (timedCandidates.isEmpty) {
      return const [];
    }
    final results = await Future.wait<dynamic>([
      StorageService.getFixedSchedules(widget.username),
      StorageService.getPlanBlocks(widget.username),
      CourseService.getAllCourses(widget.username),
    ]);
    final candidateIds = timedCandidates.map((item) => item.id).toSet();
    final schedules =
        (results[0] as List<FixedScheduleItem>)
            .where((item) => !candidateIds.contains(item.id))
            .toList()
          ..addAll(timedCandidates);
    return ScheduleConflictService.detect(
      fixedSchedules: schedules,
      planBlocks: results[1] as List<TodoPlanBlock>,
      courses: results[2] as List<CourseItem>,
    ).where((conflict) {
      return candidateIds.contains(conflict.leftId) ||
          candidateIds.contains(conflict.rightId);
    }).toList();
  }

  Future<void> _saveItems(
    List<FixedScheduleItem> items, {
    required FixedScheduleItem refreshItem,
  }) async {
    final saveAllHandler = widget.onSaveAll;
    if (saveAllHandler != null) {
      await saveAllHandler(items);
    } else {
      final saveHandler = widget.onSave;
      if (items.length == 1 && saveHandler != null) {
        await saveHandler(items.single);
      } else {
        await StorageService.saveFixedSchedules(widget.username, items);
        if (saveHandler != null) await saveHandler(refreshItem);
      }
    }
    await ReminderScheduleService.scheduleFromStorage(
      widget.username,
      force: true,
    );
  }

  Future<bool> _confirmConflicts(List<ScheduleConflict> conflicts) async {
    final hardCount = conflicts
        .where((item) => item.severity == ScheduleConflictSeverity.hard)
        .length;
    final softCount = conflicts.length - hardCount;
    return await showAppDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(hardCount > 0 ? '存在固定日程冲突' : '与规划块重叠'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hardCount > 0) Text('$hardCount 个硬冲突不会被系统自动移动。'),
                if (softCount > 0) Text('$softCount 个规划块可以稍后调整。'),
                const SizedBox(height: 12),
                ...conflicts
                    .take(3)
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('• ${item.message}'),
                      ),
                    ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('返回调整'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('仍然保存'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _delete() async {
    final item = _selectedOccurrence;
    if (item == null) return;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除固定日程'),
        content: Text(
          _seriesItems.where((entry) => !entry.isDeleted).length > 1
              ? '将删除整个重复日程系列，历史数据仍可用于后续同步恢复。'
              : '该操作会进行逻辑删除，历史数据仍可用于后续同步恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final activeSeries = _seriesItems
        .where((entry) => !entry.isDeleted)
        .toList();
    final targets = activeSeries.isEmpty ? [item] : activeSeries;
    final tombstones = targets.map((entry) {
      final copy = FixedScheduleItem.fromJson(entry.toJson())..isDeleted = true;
      copy.markAsChanged();
      return copy;
    }).toList();
    await _saveItems(tombstones, refreshItem: tombstones.first);
    if (!mounted) return;
    Navigator.pop(context, item);
  }

  String _reminderLabel(int minutes) {
    if (minutes == 0) return '开始时';
    if (minutes % 1440 == 0) return '提前 ${minutes ~/ 1440} 天';
    if (minutes % 60 == 0) return '提前 ${minutes ~/ 60} 小时';
    return '提前 $minutes 分钟';
  }

  String _recurrenceLabel(RecurrenceType type) => switch (type) {
    RecurrenceType.none => '不重复',
    RecurrenceType.daily => '每天',
    RecurrenceType.weekly => '每周',
    RecurrenceType.monthly => '每月',
    RecurrenceType.yearly => '每年',
    RecurrenceType.weekdays => '工作日',
    RecurrenceType.customDays => '自定义',
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final topBarHeight = floatingGlassTopBarHeight(context);
    final compactSaveAction =
        MediaQuery.sizeOf(context).width < 390 ||
        MediaQuery.textScalerOf(context).scale(14) > 16;
    final dateText = AppTimeFormats.date(_date);
    final recurrenceEndDateText = AppTimeFormats.date(_recurrenceEndDate);
    final appBarTitle = compactSaveAction
        ? _forcedOccurrenceEdit
              ? '编辑场次'
              : (_editing ? '编辑日程' : '新建日程')
        : _forcedOccurrenceEdit
        ? '编辑当前场次'
        : (_editing &&
                  _seriesItems.where((entry) => !entry.isDeleted).length > 1
              ? '编辑重复日程系列'
              : (_editing ? '编辑固定日程' : '新增固定日程'));
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: Text(appBarTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_editing)
            IconButton(
              onPressed: _saving || _loadingContext ? null : _delete,
              style: floatingGlassPlainIconButtonStyle(),
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: '删除固定日程',
            ),
          if (compactSaveAction)
            IconButton(
              key: const ValueKey('fixed-schedule-save'),
              onPressed: _saving || _loadingContext ? null : _save,
              style: floatingGlassPlainIconButtonStyle(),
              tooltip: '保存',
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
            )
          else
            TextButton(
              key: const ValueKey('fixed-schedule-save'),
              onPressed: _saving || _loadingContext ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
        ],
      ),
      body: FloatingGlassTopBarContentFade(
        topBarHeight: topBarHeight,
        child: AbsorbPointer(
          absorbing: _loadingContext,
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, topBarHeight + 16, 16, 16),
            children: [
              if (_loadingContext)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: '日程名称',
                  hintText: '例如：高等数学考试',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_supportsRangeEdit) ...[
                const SizedBox(height: 12),
                Card(
                  color: colors.surfaceContainerLow,
                  child: ListTile(
                    leading: const Icon(Icons.repeat_on_rounded),
                    title: const Text('修改范围'),
                    subtitle: Text(
                      '${_scopeLabel(_editScope)} · ${_scopeDescription(_editScope)}',
                    ),
                    trailing: const Icon(Icons.expand_more_rounded),
                    onTap: _saving ? null : _chooseEditScope,
                  ),
                ),
              ] else if (_forcedOccurrenceEdit) ...[
                const SizedBox(height: 12),
                Card(
                  color: colors.surfaceContainerLow,
                  child: const ListTile(
                    leading: Icon(Icons.info_outline_rounded),
                    title: Text('只编辑当前场次'),
                    subtitle: Text('重复范围由外部日历管理，请在来源日历中修改系列规则。'),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Card(
                color: colors.surfaceContainerLow,
                child: Column(
                  children: [
                    ListTile(
                      key: const ValueKey('fixed-schedule-date'),
                      leading: const Icon(Icons.calendar_today_rounded),
                      title: Text(
                        _recurrence == RecurrenceType.none
                            ? '日期'
                            : (_effectiveEditScope ==
                                      FixedScheduleEditScope.series
                                  ? '首次日期'
                                  : '本次日期'),
                      ),
                      subtitle: Text(_dateWithSemesterWeek(_date, dateText)),
                      onTap: _forcedOccurrenceEdit ? null : _pickDate,
                    ),
                    LiquidGlassSwitchListTile(
                      secondary: const Icon(Icons.schedule_rounded),
                      title: const Text('时间待定'),
                      subtitle: const Text('日期已确定，但主办方尚未公布具体时刻'),
                      value: _timeTbd,
                      onChanged: (value) => setState(() => _timeTbd = value),
                    ),
                    if (!_timeTbd) ...[
                      ListTile(
                        key: const ValueKey('fixed-schedule-start-time'),
                        leading: const Icon(Icons.play_circle_outline_rounded),
                        title: const Text('开始时间'),
                        subtitle: Text(_startTime.format(context)),
                        onTap: _pickStartTime,
                      ),
                      LiquidGlassSwitchListTile(
                        secondary: const Icon(Icons.more_time_rounded),
                        title: const Text('结束时间待定'),
                        value: _endTimeTbd,
                        onChanged: (value) =>
                            setState(() => _endTimeTbd = value),
                      ),
                      if (!_endTimeTbd)
                        ListTile(
                          key: const ValueKey('fixed-schedule-end-time'),
                          leading: const Icon(Icons.stop_circle_outlined),
                          title: const Text('结束时间'),
                          subtitle: Text(_endTime.format(context)),
                          onTap: _pickEndTime,
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Card(
                color: colors.surfaceContainerLow,
                child: Column(
                  children: [
                    DropdownButtonFormField<RecurrenceType>(
                      isExpanded: true,
                      initialValue: _recurrence,
                      decoration: const InputDecoration(
                        labelText: '重复规则',
                        prefixIcon: Icon(Icons.repeat_rounded),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      items: _supportedRecurrences
                          .map(
                            (type) => DropdownMenuItem(
                              value: type,
                              child: Text(_recurrenceLabel(type)),
                            ),
                          )
                          .toList(),
                      onChanged: !_canEditRecurrence
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() {
                                _recurrence = value;
                                if (value != RecurrenceType.none &&
                                    !_recurrenceEndDate.isAfter(_date)) {
                                  _recurrenceEndDate =
                                      FixedScheduleRecurrenceService.defaultEndDate(
                                        startDate: _date,
                                        recurrence: value,
                                        customIntervalDays:
                                            int.tryParse(
                                              _customIntervalController.text
                                                  .trim(),
                                            ) ??
                                            1,
                                      );
                                }
                              });
                            },
                    ),
                    if (!_canEditRecurrence)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('仅修改当前场次，重复规则和其他日期保持不变。'),
                        ),
                      ),
                    if (_recurrence != RecurrenceType.none &&
                        _canEditRecurrence)
                      ListTile(
                        leading: const Icon(Icons.event_repeat_rounded),
                        title: const Text('重复结束日期'),
                        subtitle: Text(
                          _dateWithSemesterWeek(
                            _recurrenceEndDate,
                            recurrenceEndDateText,
                          ),
                        ),
                        onTap: _pickRecurrenceEndDate,
                      ),
                    if (_recurrence == RecurrenceType.customDays &&
                        _canEditRecurrence)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: TextField(
                          controller: _customIntervalController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '每隔多少天',
                            suffixText: '天',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _selectedTeamUuid ?? '',
                decoration: const InputDecoration(
                  labelText: '团队归属',
                  prefixIcon: Icon(Icons.groups_rounded),
                  border: OutlineInputBorder(),
                  helperText: '关联团队后，团队成员可同步看到该日程系列',
                ),
                items: [
                  const DropdownMenuItem(value: '', child: Text('个人私有（仅自己可见）')),
                  if (_selectedTeamUuid != null &&
                      !_teams.any((team) => team.uuid == _selectedTeamUuid))
                    DropdownMenuItem(
                      value: _selectedTeamUuid,
                      child: const Text('当前团队'),
                    ),
                  ..._teams.map(
                    (team) => DropdownMenuItem(
                      value: team.uuid,
                      child: Text(team.name),
                    ),
                  ),
                ],
                onChanged: _canChangeTeam
                    ? (value) => setState(() {
                        _selectedTeamUuid = value == null || value.isEmpty
                            ? null
                            : value;
                      })
                    : null,
              ),
              if (!_canChangeTeam)
                const Padding(
                  padding: EdgeInsets.only(top: 6, left: 12, right: 12),
                  child: Text('只有日程创建者可以更改团队归属；其他内容仍可协作编辑。'),
                ),
              const SizedBox(height: 12),
              Card(
                color: colors.surfaceContainerLow,
                child: ListTile(
                  key: const ValueKey('fixed-schedule-related-todos'),
                  leading: const Icon(Icons.link_rounded),
                  title: const Text('关联待办'),
                  subtitle: Text(
                    _relatedTodoIds.isEmpty
                        ? '未关联 · 可添加复习、材料准备等待办'
                        : '已关联 ${_relatedTodoIds.length} 项 · 修改后按${_scopeLabel(_effectiveEditScope)}应用',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _saving || _loadingContext
                      ? null
                      : _chooseRelatedTodos,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _locationController,
                decoration: const InputDecoration(
                  labelText: '地点（可选）',
                  prefixIcon: Icon(Icons.location_on_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: InputDecoration(
                  labelText: '提醒（可多选）',
                  prefixIcon: const Icon(Icons.notifications_outlined),
                  border: const OutlineInputBorder(),
                  helperText: _timeTbd ? '时间确定后生效；全部取消即关闭提醒' : '全部取消即关闭提醒',
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children:
                      ({15, 30, 60, 1440, ..._reminderMinutes}.toList()..sort())
                          .map(
                            (minutes) => FilterChip(
                              label: Text(_reminderLabel(minutes)),
                              selected: _reminderMinutes.contains(minutes),
                              onSelected: (selected) => setState(() {
                                if (selected) {
                                  _reminderMinutes.add(minutes);
                                } else {
                                  _reminderMinutes.remove(minutes);
                                }
                              }),
                            ),
                          )
                          .toList(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _remarkController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '备注（可选）',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_editing) ...[
                const SizedBox(height: 8),
                LiquidGlassSwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('日程已取消'),
                  subtitle: const Text('取消状态只属于当前场次，不受上方修改范围影响'),
                  value: _cancelled,
                  onChanged: (value) => setState(() => _cancelled = value),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
