import '../widgets/floating_glass_control.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../services/api_service.dart';
import '../services/course_service.dart';
import '../services/fixed_schedule_recurrence_service.dart';
import '../services/reminder_schedule_service.dart';
import '../services/schedule_conflict_service.dart';
import '../storage_service.dart';

class FixedScheduleEditorScreen extends StatefulWidget {
  const FixedScheduleEditorScreen({
    super.key,
    required this.username,
    this.item,
    this.initialTeamUuid,
    this.onSave,
    this.onSaveAll,
    this.onSaved,
  });

  final String username;
  final FixedScheduleItem? item;
  final String? initialTeamUuid;
  final Future<void> Function(FixedScheduleItem)? onSave;
  final Future<void> Function(List<FixedScheduleItem>)? onSaveAll;
  final ValueChanged<FixedScheduleItem>? onSaved;

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
  late bool _cancelled;
  late RecurrenceType _recurrence;
  late DateTime _recurrenceEndDate;
  String? _selectedTeamUuid;
  List<Team> _teams = [];
  List<FixedScheduleItem> _seriesItems = [];
  bool _loadingContext = true;
  bool _saving = false;
  bool _canChangeTeam = true;
  int? _currentUserId;

  bool get _editing => widget.item != null;

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
    if (item == null && _reminderMinutes.isEmpty) {
      _reminderMinutes.add(15);
    }
    _cancelled = item?.status == FixedScheduleStatus.cancelled;
    _recurrence = item?.recurrence ?? RecurrenceType.none;
    _recurrenceEndDate = FixedScheduleRecurrenceService.defaultEndDate(
      startDate: _date,
      recurrence: _recurrence,
      customIntervalDays: item?.customIntervalDays ?? 1,
    );
    _selectedTeamUuid = item?.teamUuid ?? widget.initialTeamUuid;
    _seriesItems = item == null ? [] : [item];
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
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: _date,
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
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked != null && mounted) setState(() => _startTime = picked);
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (picked != null && mounted) setState(() => _endTime = picked);
  }

  Future<void> _pickRecurrenceEndDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: _date,
      lastDate: DateTime(_date.year + 5, 12, 31),
      initialDate:
          _recurrenceEndDate.isBefore(_date) ? _date : _recurrenceEndDate,
    );
    if (picked != null && mounted) {
      setState(() => _recurrenceEndDate = picked);
    }
  }

  Future<void> _loadEditorContext() async {
    final results = await Future.wait<dynamic>([
      ApiService.fetchTeams(),
      SharedPreferences.getInstance(),
      if (_editing)
        StorageService.getFixedSchedules(
          widget.username,
          includeDeleted: true,
        ),
    ]);
    if (!mounted) return;

    final teams = (results.first as List<dynamic>)
        .whereType<Map>()
        .map((raw) => Team.fromJson(Map<String, dynamic>.from(raw)))
        .where((team) => team.uuid.isNotEmpty)
        .toList();
    var seriesItems = _seriesItems;
    if (_editing && results.length > 2) {
      final allItems = results[2] as List<FixedScheduleItem>;
      final current = widget.item!;
      final seriesId = current.recurrenceSeriesId;
      seriesItems = allItems.where((item) {
        if (item.id == current.id) return true;
        return seriesId != null &&
            seriesId.isNotEmpty &&
            item.recurrenceSeriesId == seriesId;
      }).toList();
      final activeDates = seriesItems
          .where((item) => !item.isDeleted)
          .map((item) => DateTime.tryParse(item.date)?.toLocal())
          .whereType<DateTime>()
          .toList()
        ..sort();
      if (_recurrence != RecurrenceType.none && activeDates.isNotEmpty) {
        _date = activeDates.first;
        _recurrenceEndDate = activeDates.last;
      }
      if (_recurrence == RecurrenceType.customDays &&
          current.customIntervalDays == null &&
          activeDates.length > 1) {
        _customIntervalController.text = activeDates[1]
            .difference(activeDates.first)
            .inDays
            .clamp(1, 3650)
            .toString();
      }
    }

    setState(() {
      _teams = teams;
      _seriesItems = seriesItems;
      _currentUserId =
          (results[1] as SharedPreferences).getInt('current_user_id');
      final item = widget.item;
      _canChangeTeam = item == null || item.canChangeTeamFor(_currentUserId);
      _loadingContext = false;
    });
  }

  DateTime _atTime(TimeOfDay time) => DateTime(
        _date.year,
        _date.month,
        _date.day,
        time.hour,
        time.minute,
      );

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入固定日程名称')),
      );
      return;
    }

    final start = _timeTbd ? null : _atTime(_startTime);
    final end = _timeTbd || _endTimeTbd ? null : _atTime(_endTime);
    if (start != null && end != null && !end.isAfter(start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('结束时间必须晚于开始时间')),
      );
      return;
    }
    if (_recurrence != RecurrenceType.none &&
        _recurrenceEndDate.isBefore(_date)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('重复结束日期不能早于首次日期')),
      );
      return;
    }
    final customIntervalDays =
        int.tryParse(_customIntervalController.text.trim());
    if (_recurrence == RecurrenceType.customDays &&
        (customIntervalDays == null || customIntervalDays < 1)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入大于 0 的自定义重复天数')),
      );
      return;
    }

    setState(() => _saving = true);
    final existing = widget.item;
    final item = existing == null
        ? FixedScheduleItem(
            title: title,
            date: DateFormat('yyyy-MM-dd').format(_date),
          )
        : FixedScheduleItem.fromJson(existing.toJson());
    item
      ..title = title
      ..date = DateFormat('yyyy-MM-dd').format(_date)
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
      ..customIntervalDays =
          _recurrence == RecurrenceType.customDays ? customIntervalDays : null
      ..teamUuid = _selectedTeamUuid
      ..ownerUserId = existing?.ownerUserId ?? _currentUserId
      ..status = _cancelled
          ? FixedScheduleStatus.cancelled
          : existing?.status == FixedScheduleStatus.finished
              ? FixedScheduleStatus.finished
              : FixedScheduleStatus.scheduled;

    late final ({
      List<FixedScheduleItem> active,
      List<FixedScheduleItem> changes,
    }) series;
    try {
      series = FixedScheduleRecurrenceService.rebuildSeries(
        template: item,
        existingSeries: _seriesItems,
        recurrence: _recurrence,
        recurrenceEndDate:
            _recurrence == RecurrenceType.none ? _date : _recurrenceEndDate,
        customIntervalDays: customIntervalDays ?? 1,
      );
    } on FixedScheduleRecurrenceLimitException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
      return;
    }

    final conflicts = await _conflictsFor(series.active);
    if (!mounted) return;
    if (conflicts.isNotEmpty && !await _confirmConflicts(conflicts)) {
      if (mounted) setState(() => _saving = false);
      return;
    }

    await _saveItems(series.changes, refreshItem: series.active.first);
    widget.onSaved?.call(series.active.first);
    if (!mounted) return;
    Navigator.pop(context, series.active.first);
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
    final schedules = (results[0] as List<FixedScheduleItem>)
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
    return await showDialog<bool>(
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
                ...conflicts.take(3).map(
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
    final item = widget.item;
    if (item == null) return;
    final confirmed = await showDialog<bool>(
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
    final activeSeries =
        _seriesItems.where((entry) => !entry.isDeleted).toList();
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
    return Scaffold(
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: Text(
          _editing && _seriesItems.where((entry) => !entry.isDeleted).length > 1
              ? '编辑重复日程系列'
              : (_editing ? '编辑固定日程' : '新增固定日程'),
        ),
        actions: [
          if (_editing)
            IconButton(
              onPressed: _saving || _loadingContext ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: '删除固定日程',
            ),
          TextButton(
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: '日程名称',
              hintText: '例如：高等数学考试',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: colors.surfaceContainerLow,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.calendar_today_rounded),
                  title: Text(
                    _recurrence == RecurrenceType.none ? '日期' : '首次日期',
                  ),
                  subtitle: Text(DateFormat('yyyy-MM-dd').format(_date)),
                  onTap: _pickDate,
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
                    leading: const Icon(Icons.play_circle_outline_rounded),
                    title: const Text('开始时间'),
                    subtitle: Text(_startTime.format(context)),
                    onTap: _pickStartTime,
                  ),
                  LiquidGlassSwitchListTile(
                    secondary: const Icon(Icons.more_time_rounded),
                    title: const Text('结束时间待定'),
                    value: _endTimeTbd,
                    onChanged: (value) => setState(() => _endTimeTbd = value),
                  ),
                  if (!_endTimeTbd)
                    ListTile(
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
                  initialValue: _recurrence,
                  decoration: const InputDecoration(
                    labelText: '重复规则',
                    prefixIcon: Icon(Icons.repeat_rounded),
                    border: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  items: _supportedRecurrences
                      .map((type) => DropdownMenuItem(
                            value: type,
                            child: Text(_recurrenceLabel(type)),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _recurrence = value;
                      if (value != RecurrenceType.none &&
                          !_recurrenceEndDate.isAfter(_date)) {
                        _recurrenceEndDate =
                            FixedScheduleRecurrenceService.defaultEndDate(
                          startDate: _date,
                          recurrence: value,
                          customIntervalDays: int.tryParse(
                                _customIntervalController.text.trim(),
                              ) ??
                              1,
                        );
                      }
                    });
                  },
                ),
                if (_recurrence != RecurrenceType.none)
                  ListTile(
                    leading: const Icon(Icons.event_repeat_rounded),
                    title: const Text('重复结束日期'),
                    subtitle: Text(
                      DateFormat('yyyy-MM-dd').format(_recurrenceEndDate),
                    ),
                    onTap: _pickRecurrenceEndDate,
                  ),
                if (_recurrence == RecurrenceType.customDays)
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
            initialValue: _selectedTeamUuid ?? '',
            decoration: const InputDecoration(
              labelText: '团队归属',
              prefixIcon: Icon(Icons.groups_rounded),
              border: OutlineInputBorder(),
              helperText: '关联团队后，团队成员可同步看到该日程系列',
            ),
            items: [
              const DropdownMenuItem(
                value: '',
                child: Text('个人私有（仅自己可见）'),
              ),
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
                      _selectedTeamUuid =
                          value == null || value.isEmpty ? null : value;
                    })
                : null,
          ),
          if (!_canChangeTeam)
            const Padding(
              padding: EdgeInsets.only(top: 6, left: 12, right: 12),
              child: Text('只有日程创建者可以更改团队归属；其他内容仍可协作编辑。'),
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
              subtitle: const Text('取消后不再参与冲突、进行中状态和日历导出'),
              value: _cancelled,
              onChanged: (value) => setState(() => _cancelled = value),
            ),
          ],
        ],
      ),
    );
  }
}
