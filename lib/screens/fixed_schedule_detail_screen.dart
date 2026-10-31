import 'dart:convert';

import 'package:flutter/material.dart';

import '../models.dart';
import '../models/todo_create_save_result.dart';
import '../storage_service.dart';
import '../services/pomodoro_service.dart';
import '../utils/page_transitions.dart';
import '../widgets/app_detail_widgets.dart';
import '../widgets/floating_glass_control.dart';
import 'add_todo_screen.dart';
import 'course_screens.dart';
import 'fixed_schedule_editor_screen.dart';
import 'plan_preparation_screen.dart';

class FixedScheduleDetailScreen extends StatefulWidget {
  const FixedScheduleDetailScreen({
    super.key,
    required this.username,
    required this.item,
    this.loadRelatedTodos,
    this.loadRelatedFixedSchedules,
    this.getCurrentUsername,
    this.loadTodoFocusRecords,
    this.onCreateRelatedTodo,
  });

  final String username;
  final FixedScheduleItem item;
  final Future<List<TodoItem>> Function(String username)? loadRelatedTodos;
  final Future<List<FixedScheduleItem>> Function(
    String username,
    String todoId,
  )?
  loadRelatedFixedSchedules;
  final Future<String?> Function()? getCurrentUsername;
  final Future<List<PomodoroRecord>> Function(String todoId)?
  loadTodoFocusRecords;
  final FixedScheduleTodoLinkSaver? onCreateRelatedTodo;

  @override
  State<FixedScheduleDetailScreen> createState() =>
      _FixedScheduleDetailScreenState();
}

class _FixedScheduleDetailScreenState extends State<FixedScheduleDetailScreen> {
  List<TodoItem> _todos = [];
  bool _loadingRelatedTodos = false;
  bool _relatedTodoLoadFailed = false;
  int _loadGeneration = 0;
  late FixedScheduleItem _activeItem;
  final Map<String, GlobalKey> _relatedTodoCardKeys = {};
  final GlobalKey _editButtonKey = GlobalKey();

  GlobalKey _getRelatedTodoCardKey(String id) =>
      _relatedTodoCardKeys.putIfAbsent(id, GlobalKey.new);

  FixedScheduleItem get item => _activeItem;
  String get username => widget.username;

  @override
  void initState() {
    super.initState();
    _activeItem = FixedScheduleItem.fromJson(widget.item.toJson());
    _loadRelatedTodos();
  }

  @override
  void didUpdateWidget(covariant FixedScheduleDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final scheduleChanged =
        jsonEncode(oldWidget.item.toJson()) != jsonEncode(widget.item.toJson());
    if (scheduleChanged) {
      _activeItem = FixedScheduleItem.fromJson(widget.item.toJson());
    }
    if (oldWidget.username != widget.username || scheduleChanged) {
      _loadRelatedTodos();
    }
  }

  Future<void> _loadRelatedTodos() async {
    final generation = ++_loadGeneration;
    final ids = item.relatedTodoIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (ids.isEmpty) {
      if (!mounted) return;
      setState(() {
        _todos = [];
        _loadingRelatedTodos = false;
        _relatedTodoLoadFailed = false;
      });
      return;
    }

    setState(() {
      _loadingRelatedTodos = true;
      _relatedTodoLoadFailed = false;
    });
    try {
      final todos = widget.loadRelatedTodos == null
          ? await StorageService.getTodosForFixedScheduleRelationIds(
              widget.username,
              ids,
            )
          : await widget.loadRelatedTodos!(widget.username);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _todos = todos;
        _loadingRelatedTodos = false;
        _relatedTodoLoadFailed = false;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _todos = [];
        _loadingRelatedTodos = false;
        _relatedTodoLoadFailed = true;
      });
    }
  }

  String? _normalizedTeamUuid(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  bool _hasSameVisibility(TodoItem todo) =>
      _normalizedTeamUuid(todo.teamUuid) == _normalizedTeamUuid(item.teamUuid);

  bool get _canCreateRelatedTodo =>
      widget.onCreateRelatedTodo != null &&
      item.phaseAt(DateTime.now()) != FixedSchedulePhase.cancelled;

  bool get _canRecommendPreparation =>
      item.startTime != null &&
      item.phaseAt(DateTime.now()) == FixedSchedulePhase.upcoming;

  String _todoStatusLabel(TodoItem todo) {
    if (todo.isDeleted) return '已删除';
    if (todo.isDone) return '已完成';
    if (todo.isSkipped) return '已跳过';
    if (todo.hasConflict) return '存在同步冲突';
    return '待完成';
  }

  String _todoSubtitle(TodoItem todo) {
    final status = _todoStatusLabel(todo);
    final due = todo.dueDate?.toLocal();
    if (due == null) return status;
    final date = todo.isDateOnly
        ? AppTimeFormats.format(due, 'yyyy年M月d日')
        : AppTimeFormats.format(due, 'yyyy年M月d日 HH:mm');
    return '$status · $date';
  }

  Future<void> _openRelatedTodo(TodoItem todo) async {
    await Navigator.of(context).push<void>(
      PageTransitions.material(
        builder: (_) => TodoDetailScreen(
          todo: todo,
          loadRelatedFixedSchedules: widget.loadRelatedFixedSchedules,
          getCurrentUsername: widget.getCurrentUsername,
          loadFocusRecords: widget.loadTodoFocusRecords,
          onCreateRelatedTodo: widget.onCreateRelatedTodo,
        ),
      ),
    );
    if (mounted) await _loadRelatedTodos();
  }

  Future<void> _openPreparation(TodoItem todo) async {
    if (!_canRecommendPreparation ||
        todo.isDone ||
        todo.isSkipped ||
        todo.isDeleted ||
        todo.hasConflict) {
      return;
    }
    await Navigator.of(context).push<void>(
      PageTransitions.material(
        builder: (_) => PlanPreparationScreen(
          username: username,
          schedule: item,
          todo: todo,
        ),
      ),
    );
    if (mounted) await _loadRelatedTodos();
  }

  Future<void> _openCreateRelatedTodo() async {
    final saveLinkedTodo = widget.onCreateRelatedTodo;
    if (saveLinkedTodo == null || !_canCreateRelatedTodo) return;
    await Navigator.of(context).push<void>(
      PageTransitions.material(
        builder: (_) => AddTodoScreen(
          username: username,
          initialTeamUuid: item.teamUuid,
          relatedFixedScheduleContext: item,
          onManualTodoSaved: (todo) async {
            final result = await saveLinkedTodo(todo, item);
            if (mounted) {
              setState(() => _activeItem = result.schedule);
              await _loadRelatedTodos();
            }
            return TodoCreateSaveResult(warnings: result.warnings);
          },
        ),
      ),
    );
  }

  Widget _buildRelatedTodosSection(BuildContext context) {
    final ids = item.relatedTodoIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList();
    final scheme = Theme.of(context).colorScheme;
    final todosById = {for (final todo in _todos) todo.id: todo};

    if (_loadingRelatedTodos) {
      return AppDetailSection(
        title: '关联待办',
        children: const [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          ),
        ],
      );
    }
    if (_relatedTodoLoadFailed) {
      return AppDetailSection(
        title: '关联待办',
        children: [
          Text(
            '关联待办读取失败，不能确认当前列表是否为空。',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _loadRelatedTodos,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ),
        ],
      );
    }

    if (ids.isEmpty) {
      return AppDetailSection(
        title: '关联待办',
        children: [
          Text(
            '暂无关联待办，可以关联已有待办。',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (_canCreateRelatedTodo)
                FilledButton.tonalIcon(
                  key: const ValueKey('fixed-schedule-create-related-todo'),
                  onPressed: _openCreateRelatedTodo,
                  icon: const Icon(Icons.add_task_rounded),
                  label: const Text('新建准备待办'),
                ),
              OutlinedButton.icon(
                onPressed: () => _openEditor(context),
                icon: const Icon(Icons.add_link_rounded),
                label: const Text('关联已有待办'),
              ),
            ],
          ),
        ],
      );
    }

    return AppDetailSection(
      title: '关联待办 · ${ids.length}',
      children: [
        if (_canCreateRelatedTodo)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('fixed-schedule-create-related-todo'),
              onPressed: _openCreateRelatedTodo,
              icon: const Icon(Icons.add_task_rounded),
              label: const Text('新建准备待办'),
            ),
          ),
        for (final id in ids)
          Builder(
            builder: (context) {
              final todo = todosById[id];
              final sameVisibility = todo != null && _hasSameVisibility(todo);
              final accessibleTodo =
                  todo != null && sameVisibility && !todo.isDeleted
                  ? todo
                  : null;
              final canOpen = accessibleTodo != null;
              final title = accessibleTodo == null
                  ? '关联待办不可用'
                  : (accessibleTodo.title.trim().isEmpty
                        ? '未命名待办'
                        : accessibleTodo.title.trim());
              final subtitle = accessibleTodo != null
                  ? _todoSubtitle(accessibleTodo)
                  : todo?.isDeleted == true && sameVisibility
                  ? '已删除'
                  : '已删除或当前日程不可见';
              final canPrepare =
                  accessibleTodo != null &&
                  _canRecommendPreparation &&
                  !accessibleTodo.isDone &&
                  !accessibleTodo.isSkipped &&
                  !accessibleTodo.hasConflict;
              final cardKey = _getRelatedTodoCardKey(id);
              return KeyedSubtree(
                key: ValueKey('fixed-schedule-related-todo-$id'),
                child: Card(
                  key: cardKey,
                  color: scheme.surfaceContainerLow,
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(
                          accessibleTodo?.isDone == true
                              ? Icons.task_alt_rounded
                              : accessibleTodo?.isSkipped == true
                              ? Icons.skip_next_rounded
                              : canOpen
                              ? Icons.checklist_rounded
                              : Icons.link_off_rounded,
                          color: canOpen
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                        title: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(subtitle),
                        trailing: canOpen
                            ? const Icon(Icons.open_in_new_rounded)
                            : null,
                        onTap: accessibleTodo == null
                            ? null
                            : () => _openRelatedTodo(accessibleTodo),
                      ),
                      if (canPrepare)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(
                              right: 12,
                              bottom: 8,
                            ),
                            child: TextButton.icon(
                              key: ValueKey(
                                'fixed-schedule-prepare-related-todo-$id',
                              ),
                              onPressed: () => _openPreparation(accessibleTodo),
                              icon: const Icon(Icons.schedule_rounded),
                              label: const Text('安排准备时间'),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  DateTime? get _start {
    final value = item.startTime;
    return value == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(value).toLocal();
  }

  DateTime? get _end {
    final value = item.endTime;
    return value == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(value).toLocal();
  }

  String _timeLabel(String? startLabel, String? endLabel) {
    if (startLabel == null) return '时间待定';
    if (endLabel == null) return '$startLabel · 结束待定';
    return '$startLabel - $endLabel';
  }

  String _phaseLabel(DateTime now) => switch (item.phaseAt(now)) {
    FixedSchedulePhase.timeTbd => '时间待定',
    FixedSchedulePhase.upcoming => '即将开始',
    FixedSchedulePhase.ongoing => '进行中',
    FixedSchedulePhase.ended => '已结束',
    FixedSchedulePhase.cancelled => '已取消',
  };

  String _recurrenceLabel() => switch (item.recurrence) {
    RecurrenceType.none => '不重复',
    RecurrenceType.daily => '每天重复',
    RecurrenceType.weekdays => '工作日重复',
    RecurrenceType.weekly => '每周重复',
    RecurrenceType.monthly => '每月重复',
    RecurrenceType.yearly => '每年重复',
    RecurrenceType.customDays => '每 ${item.customIntervalDays ?? 1} 天重复',
  };

  String _reminderLabel(int minutes) {
    if (minutes == 0) return '开始时';
    if (minutes % 1440 == 0) return '提前 ${minutes ~/ 1440} 天';
    if (minutes % 60 == 0) return '提前 ${minutes ~/ 60} 小时';
    return '提前 $minutes 分钟';
  }

  String get _reminderSummary {
    if (item.reminderMinutes.isEmpty) return '不提醒';
    final values = item.reminderMinutes
        .where((minutes) => minutes >= 0)
        .map(_reminderLabel)
        .toList();
    return values.isEmpty ? '不提醒' : values.join('、');
  }

  Future<void> _openEditor(BuildContext context, {GlobalKey? sourceKey}) async {
    final page = FixedScheduleEditorScreen(username: username, item: item);
    final result = sourceKey != null
        ? await PageTransitions.pushFromRect<FixedScheduleItem>(
            context: context,
            page: page,
            sourceKey: sourceKey,
          )
        : await Navigator.of(context).push<FixedScheduleItem>(
            PageTransitions.material(builder: (_) => page),
          );
    if (!context.mounted || result == null) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final phase = _phaseLabel(DateTime.now());
    final date = DateTime.tryParse(item.date)?.toLocal();
    final dateLabel = date == null
        ? item.date
        : AppTimeFormats.format(date, 'yyyy年M月d日');
    final start = _start;
    final end = _end;
    final startTimeLabel = start == null ? null : AppTimeFormats.clock(start);
    final endTimeLabel = end == null ? null : AppTimeFormats.clock(end);
    final timeLabel = _timeLabel(startTimeLabel, endTimeLabel);

    return AppDetailScreen(
      appBarTitle: '固定日程详情',
      backgroundColor: colors.surface,
      icon: Icons.event_available_rounded,
      iconSize: 64,
      titleSize: 22,
      title: item.title,
      headerSubtitle: '$dateLabel · $timeLabel',
      color: colors.primary,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      scrollPhysics: const BouncingScrollPhysics(),
      appBarActions: [
        IconButton(
          key: _editButtonKey,
          style: floatingGlassPlainIconButtonStyle(),
          onPressed: () => _openEditor(context, sourceKey: _editButtonKey),
          icon: const Icon(Icons.edit_outlined),
          tooltip: '编辑固定日程',
        ),
      ],
      sections: [
        AppDetailSection(
          title: '日程信息',
          children: [
            AppDetailWideCard(
              icon: Icons.calendar_today_rounded,
              title: '日期',
              value: dateLabel,
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: AppDetailInfoCard(
                      icon: Icons.play_arrow_rounded,
                      title: '开始时间',
                      value: startTimeLabel ?? '待定',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      color: colors.onSurfaceVariant,
                      size: 20,
                    ),
                  ),
                  Expanded(
                    child: AppDetailInfoCard(
                      icon: Icons.stop_rounded,
                      title: '结束时间',
                      value: endTimeLabel ?? '待定',
                    ),
                  ),
                ],
              ),
            ),
            if (item.location?.trim().isNotEmpty == true)
              AppDetailWideCard(
                icon: Icons.location_on_rounded,
                title: '地点',
                value: item.location!.trim(),
              ),
          ],
        ),
        AppDetailSection(
          title: '状态与提醒',
          children: [
            Row(
              children: [
                Expanded(
                  child: AppDetailInfoCard(
                    icon: Icons.flag_rounded,
                    title: '状态',
                    value: phase,
                    valueColor: phase == '进行中'
                        ? colors.primary
                        : colors.onSurface,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppDetailInfoCard(
                    icon: Icons.repeat_rounded,
                    title: '重复',
                    value: _recurrenceLabel(),
                  ),
                ),
              ],
            ),
            AppDetailWideCard(
              icon: Icons.notifications_active_rounded,
              title: '提醒',
              value: _reminderSummary,
            ),
          ],
        ),
        _buildRelatedTodosSection(context),
        if (item.teamUuid?.trim().isNotEmpty == true)
          AppDetailSection(
            title: '协作信息',
            children: [
              AppDetailWideCard(
                icon: Icons.group_rounded,
                title: '团队日程',
                value: item.teamUuid!.trim(),
              ),
            ],
          ),
        if (item.remark?.trim().isNotEmpty == true)
          AppDetailSection(
            title: '备注详情',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  item.remark!.trim(),
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.onSurface,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
