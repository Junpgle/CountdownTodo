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

part 'fixed_schedule_editor/fixed_schedule_editor_save.dart';
part 'fixed_schedule_editor/fixed_schedule_editor_view.dart';

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

  final GlobalKey _relatedTodosCardKey = GlobalKey();
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

  void _unfocusActiveInput() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _chooseEditScope() async {
    _unfocusActiveInput();
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
    _unfocusActiveInput();
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
    _unfocusActiveInput();
    final picked = await showAppTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked != null && mounted) {
      setState(() => _startTime = picked);
    }
  }

  Future<void> _pickEndTime() async {
    _unfocusActiveInput();
    final picked = await showAppTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (picked != null && mounted) {
      setState(() => _endTime = picked);
    }
  }

  Future<void> _pickRecurrenceEndDate() async {
    _unfocusActiveInput();
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
    _unfocusActiveInput();
    final page = FixedScheduleRelatedTodoPickerScreen(
      username: widget.username,
      teamUuid: _selectedTeamUuid,
      initialSelectedIds: Set<String>.from(_relatedTodoIds),
    );
    final selected = await PageTransitions.pushFromRect<Set<String>>(
      context: context,
      sourceKey: _relatedTodosCardKey,
      page: page,
    );
    if (selected == null || !mounted) return;
    setState(() => _relatedTodoIds = Set<String>.from(selected));
  }

  Future<String?> _invalidRelatedTodoMessage() async {
    if (_relatedTodoIds.isEmpty) return null;
    final todos = await StorageService.getTodosForFixedScheduleRelationIds(
      widget.username,
      _relatedTodoIds,
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

  void _mutateState(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) => _buildEditorScaffold(context);
}
