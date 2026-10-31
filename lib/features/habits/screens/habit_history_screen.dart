import '../../../widgets/floating_glass_control.dart';

import 'package:flutter/material.dart';

import '../../../models.dart';
import '../../../services/pomodoro_service.dart';
import '../models/habit_checkin.dart';
import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../repositories/habit_repository.dart';
import '../services/habit_adaptation_service.dart';
import '../services/habit_source_resolver.dart';
import '../services/habit_sleep_duration_service.dart';
import '../widgets/habit_checkin_editor.dart';
import '../widgets/habit_format.dart';
import '../../../utils/app_dialogs.dart';

/// 习惯历史：打卡记录 + 目标修改历史。
///
/// 对应设计文档第十五节独立的 `habit_history_screen.dart`，
/// 具体记录保留在详情页之外的历史页，避免主时间轴信息过多。
class HabitHistoryScreen extends StatefulWidget {
  final HabitGoal goal;
  final String username;

  const HabitHistoryScreen({super.key, required this.goal, this.username = ''});

  @override
  State<HabitHistoryScreen> createState() => _HabitHistoryScreenState();
}

class _HabitHistorySectionHeader {
  const _HabitHistorySectionHeader(this.title, {this.detail});

  final String title;
  final String? detail;
}

class _HabitHistoryDateHeader {
  const _HabitHistoryDateHeader(this.dateKey);

  final String dateKey;
}

class _HabitHistoryEmptyState {
  const _HabitHistoryEmptyState(this.text);

  final String text;
}

class _HabitHistoryGap {
  const _HabitHistoryGap(this.height);

  final double height;
}

class _HabitHistoryScreenState extends State<HabitHistoryScreen> {
  bool _loading = true;
  Map<String, HabitGoalRuleRevision> _rulesByUuid = const {};
  List<Object> _historyRows = const [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (HabitSleepDurationService.isSleepDurationGoal(widget.goal)) {
      await HabitSleepDurationService.syncAll();
    }
    final checkIns = await HabitRepository.getCheckIns(
      habitUuid: widget.goal.uuid,
    );
    final focusRecords = widget.goal.sourceType == HabitSourceType.pomodoroTag
        ? await HabitSourceResolver.recordsForTags(
            tagUuids: widget.goal.sourceIds,
            from: DateTime(1970),
            to: DateTime.now(),
          )
        : const <PomodoroRecord>[];
    final linkedTodos = widget.goal.sourceType == HabitSourceType.recurringTodo
        ? await HabitSourceResolver.todosForSeries(widget.goal.sourceIds)
        : const <TodoItem>[];
    final rules = await HabitRepository.getRules(habitUuid: widget.goal.uuid);
    final sortedCheckIns = checkIns.where((c) => !c.isDeleted).toList()
      ..sort((a, b) => b.logicalDate.compareTo(a.logicalDate));
    final sortedFocusRecords = focusRecords.toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
    final sortedLinkedTodos =
        linkedTodos.where((todo) => !todo.isDeleted).toList()
          ..sort((a, b) => _todoDate(b).compareTo(_todoDate(a)));
    final sortedRules = rules.where((r) => !r.isDeleted).toList()
      ..sort(
        (a, b) =>
            (b.effectiveFromDate ?? '').compareTo(a.effectiveFromDate ?? ''),
      );
    final rulesByUuid = {for (final rule in sortedRules) rule.uuid: rule};
    final historyRows = _buildHistoryRows(
      checkIns: sortedCheckIns,
      focusRecords: sortedFocusRecords,
      linkedTodos: sortedLinkedTodos,
      rules: sortedRules,
    );
    if (!mounted) return;
    setState(() {
      _rulesByUuid = rulesByUuid;
      _historyRows = historyRows;
      _loading = false;
    });
  }

  List<Object> _buildHistoryRows({
    required List<HabitCheckIn> checkIns,
    required List<PomodoroRecord> focusRecords,
    required List<TodoItem> linkedTodos,
    required List<HabitGoalRuleRevision> rules,
  }) {
    final rows = <Object>[];
    switch (widget.goal.sourceType) {
      case HabitSourceType.pomodoroTag:
        rows.add(
          _HabitHistorySectionHeader(
            '专注记录',
            detail: '共 ${focusRecords.length} 条',
          ),
        );
        rows.add(const _HabitHistoryGap(10));
        if (focusRecords.isEmpty) {
          rows.add(const _HabitHistoryEmptyState('暂无专注记录'));
        } else {
          final grouped = _groupByHistoryDay(focusRecords, (record) {
            final local = DateTime.fromMillisecondsSinceEpoch(record.startTime)
                .toLocal();
            return _dateKey(local);
          });
          for (final entry in grouped.entries) {
            rows.add(_HabitHistoryDateHeader(entry.key));
            rows.addAll(entry.value);
          }
        }
      case HabitSourceType.recurringTodo:
        final completedTodos = linkedTodos
            .where((todo) => todo.isDone)
            .toList(growable: false);
        final hasRecords = checkIns.isNotEmpty || completedTodos.isNotEmpty;
        final totalCount = checkIns.length + completedTodos.length;
        rows.add(_HabitHistorySectionHeader('打卡记录', detail: '共 $totalCount 条'));
        rows.add(const _HabitHistoryGap(10));
        if (!hasRecords) {
          rows.add(const _HabitHistoryEmptyState('暂无打卡记录'));
        } else {
          final grouped = <String, List<Object>>{};
          for (final checkIn in checkIns) {
            grouped.putIfAbsent(checkIn.logicalDate, () => []).add(checkIn);
          }
          for (final todo in completedTodos) {
            final key = _todoDateKey(todo);
            if (!grouped.containsKey(key)) {
              grouped.putIfAbsent(key, () => []).add(todo);
            }
          }
          final sortedKeys = grouped.keys.toList()
            ..sort((a, b) => b.compareTo(a));
          for (final key in sortedKeys) {
            rows.add(_HabitHistoryDateHeader(key));
            rows.addAll(grouped[key]!);
          }
        }
      case HabitSourceType.quantityCheckIn:
      case HabitSourceType.durationCheckIn:
      case HabitSourceType.timeCheckIn:
        rows.add(
          _HabitHistorySectionHeader('打卡记录', detail: '共 ${checkIns.length} 条'),
        );
        rows.add(const _HabitHistoryGap(10));
        if (checkIns.isEmpty) {
          rows.add(const _HabitHistoryEmptyState('暂无打卡记录'));
        } else {
          final grouped = _groupByHistoryDay(checkIns, (checkIn) {
            return checkIn.logicalDate;
          });
          for (final entry in grouped.entries) {
            rows.add(_HabitHistoryDateHeader(entry.key));
            rows.addAll(entry.value);
          }
        }
    }

    rows.add(const _HabitHistoryGap(24));
    rows.add(const _HabitHistorySectionHeader('目标修改历史'));
    rows.add(const _HabitHistoryGap(10));
    if (rules.isEmpty) {
      rows.add(const _HabitHistoryEmptyState('暂无目标修改记录'));
    } else {
      rows.addAll(rules);
    }
    return rows;
  }

  Map<String, List<T>> _groupByHistoryDay<T>(
    Iterable<T> items,
    String Function(T item) dateKeyFor,
  ) {
    final grouped = <String, List<T>>{};
    for (final item in items) {
      grouped.putIfAbsent(dateKeyFor(item), () => []).add(item);
    }
    return grouped;
  }

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Widget _buildHistoryRow(Object row, ColorScheme colorScheme) {
    if (row is _HabitHistorySectionHeader) {
      return _sectionHeader(colorScheme, row.title, detail: row.detail);
    }
    if (row is _HabitHistoryDateHeader) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(
          _dateLabel(row.dateKey),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colorScheme.primary,
          ),
        ),
      );
    }
    if (row is _HabitHistoryEmptyState) {
      return _emptyBox(colorScheme, row.text);
    }
    if (row is _HabitHistoryGap) return SizedBox(height: row.height);
    if (row is HabitCheckIn) return _checkInRow(colorScheme, row);
    if (row is PomodoroRecord) return _focusRecordRow(colorScheme, row);
    if (row is TodoItem) return _linkedTodoRow(colorScheme, row);
    if (row is HabitGoalRuleRevision) return _ruleRow(colorScheme, row);
    throw StateError('Unexpected habit history row: ${row.runtimeType}');
  }

  Widget _sectionHeader(
    ColorScheme colorScheme,
    String title, {
    String? detail,
  }) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        if (detail != null) ...[
          const SizedBox(width: 8),
          Text(
            detail,
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  Future<void> _deleteCheckIn(HabitCheckIn checkIn) async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除打卡'),
        content: const Text('确定删除这条打卡记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await HabitRepository.deleteCheckIn(checkIn);
    _loadData();
  }

  Future<void> _editCheckIn(HabitCheckIn checkIn) async {
    final rule = _ruleFor(checkIn.ruleRevisionUuid);
    if (rule == null) {
      if (!mounted) return;
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('找不到这条记录对应的目标规则')),
      );
      return;
    }
    final edited = await showHabitCheckInEditor(
      context: context,
      goal: widget.goal,
      rule: rule,
      checkIn: checkIn,
    );
    if (edited == null || !mounted) return;
    await HabitRepository.updateCheckIn(edited);
    _loadData();
  }

  HabitGoalRuleRevision? _ruleFor(String? uuid) {
    if (uuid == null) return null;
    return _rulesByUuid[uuid];
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final topBarHeight = floatingGlassTopBarHeight(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: Text('${widget.goal.name} · 历史'),
        centerTitle: false,
      ),
      body: FloatingGlassTopBarContentFade(
        topBarHeight: topBarHeight,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 840),
                  child: ListView.builder(
                    padding: EdgeInsets.fromLTRB(16, topBarHeight + 8, 16, 32),
                    itemCount: _historyRows.length,
                    itemBuilder: (context, index) =>
                        _buildHistoryRow(_historyRows[index], colorScheme),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _linkedTodoRow(ColorScheme colorScheme, TodoItem todo) {
    final local = _todoDate(todo);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 18,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  todo.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                if (todo.remark?.trim().isNotEmpty == true)
                  Text(
                    todo.remark!.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            HabitText.timeOfDay(local),
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  static DateTime _todoDate(TodoItem todo) {
    return DateTime.fromMillisecondsSinceEpoch(
      todo.createdDate ?? todo.createdAt,
      isUtc: true,
    ).toLocal();
  }

  static String _todoDateKey(TodoItem todo) {
    final local = _todoDate(todo);
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  Widget _focusRecordRow(ColorScheme colorScheme, PomodoroRecord record) {
    final local = DateTime.fromMillisecondsSinceEpoch(record.startTime)
        .toLocal();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.timer_rounded, size: 18, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  HabitText.formatDuration(
                    record.actualDuration ?? record.plannedDuration,
                  ),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                if (record.note?.isNotEmpty == true)
                  Text(
                    record.note!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            HabitText.timeOfDay(local),
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _checkInRow(ColorScheme colorScheme, HabitCheckIn checkIn) {
    final local = checkIn.localOccurredAt;
    final rule = _ruleFor(checkIn.ruleRevisionUuid);
    final unit = rule?.unit ?? '';
    final valueText = switch (widget.goal.sourceType) {
      HabitSourceType.quantityCheckIn =>
        '+${_trimNumber(checkIn.value)}${unit.isNotEmpty ? ' $unit' : ''}',
      HabitSourceType.durationCheckIn =>
        '${HabitAdaptationService.forHabit(widget.goal)?.kind == HabitAdaptationKind.sleepDuration ? '睡眠' : '时长'} '
            '${HabitText.formatDuration(checkIn.value.round())}',
      HabitSourceType.timeCheckIn => '打卡 ${HabitText.timeOfDay(local)}',
      HabitSourceType.recurringTodo => '完成打卡',
      HabitSourceType.pomodoroTag => HabitText.timeOfDay(local),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            HabitSourceType.timeCheckIn == widget.goal.sourceType
                ? Icons.schedule_rounded
                : Icons.add_circle_outline_rounded,
            size: 18,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  valueText,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                if (checkIn.note != null && checkIn.note!.isNotEmpty)
                  Text(
                    checkIn.note!,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            HabitText.timeOfDay(local),
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          if (checkIn.source != HabitCheckInSource.skip &&
              (widget.goal.sourceType == HabitSourceType.quantityCheckIn ||
                  widget.goal.sourceType == HabitSourceType.timeCheckIn ||
                  widget.goal.sourceType == HabitSourceType.durationCheckIn))
            IconButton(
              tooltip: '编辑',
              onPressed: () => _editCheckIn(checkIn),
              icon: const Icon(Icons.edit_outlined, size: 18),
            ),
          IconButton(
            tooltip: '删除',
            onPressed: () => _deleteCheckIn(checkIn),
            icon: Icon(
              Icons.delete_outline_rounded,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ruleRow(ColorScheme colorScheme, HabitGoalRuleRevision rule) {
    final from = rule.effectiveFromDate ?? '';
    final to = rule.effectiveToDate ?? '至今';
    final targetText = switch (widget.goal.sourceType) {
      HabitSourceType.quantityCheckIn =>
        '${_trimNumber(rule.targetValue)}'
            '${rule.unit.isNotEmpty ? ' ${rule.unit}' : ''}',
      HabitSourceType.pomodoroTag => HabitText.formatDuration(
        rule.targetValue.round(),
      ),
      HabitSourceType.durationCheckIn =>
        '${(rule.targetValue / 3600).toStringAsFixed(1)} 小时',
      HabitSourceType.timeCheckIn => HabitText.targetTime(
        rule.targetTimeMinute,
      ),
      HabitSourceType.recurringTodo => '完成一次',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.history_rounded, size: 18, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  targetText,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                Text(
                  '${HabitText.periodLabel(rule)} · $from 至 $to',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyBox(ColorScheme colorScheme, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
      ),
    );
  }

  String _dateLabel(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return key;
    final date = DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return '${date.month}月${date.day}日 ${weekdays[date.weekday - 1]}';
  }

  static String _trimNumber(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toStringAsFixed(1);
  }
}
