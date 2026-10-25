import 'package:flutter/material.dart';

import '../models.dart';
import '../services/fixed_schedule_reschedule_impact_service.dart';
import '../services/schedule_conflict_service.dart';
import '../utils/time_utils.dart';

class FixedScheduleRescheduleImpactDialog extends StatefulWidget {
  const FixedScheduleRescheduleImpactDialog({
    super.key,
    required this.impact,
    required this.reload,
    required this.openTodo,
    required this.openPlan,
  });

  final FixedScheduleRescheduleImpact impact;
  final Future<FixedScheduleRescheduleImpact> Function() reload;
  final Future<void> Function(TodoItem todo) openTodo;
  final Future<void> Function(TodoPlanBlock plan) openPlan;

  @override
  State<FixedScheduleRescheduleImpactDialog> createState() =>
      _FixedScheduleRescheduleImpactDialogState();
}

class _FixedScheduleRescheduleImpactDialogState
    extends State<FixedScheduleRescheduleImpactDialog> {
  late FixedScheduleRescheduleImpact _impact = widget.impact;
  bool _showAllDeltas = false;
  bool _showAllPlans = false;
  bool _showAllReminders = false;
  bool _refreshing = false;
  bool _contextUnavailable = false;
  String? _refreshError;

  Future<void> _openTodo(TodoItem todo) async {
    try {
      await widget.openTodo(todo);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _contextUnavailable = true;
        _refreshError = '账号已切换或详情无法打开，请重新读取后再保存。';
      });
      return;
    }
    if (mounted) await _refreshImpact();
  }

  Future<void> _openPlan(TodoPlanBlock plan) async {
    try {
      await widget.openPlan(plan);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _contextUnavailable = true;
        _refreshError = '账号已切换或详情无法打开，请重新读取后再保存。';
      });
      return;
    }
    if (mounted) await _refreshImpact();
  }

  Future<void> _refreshImpact() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _contextUnavailable = true;
      _refreshError = null;
    });
    try {
      final refreshed = await widget.reload();
      if (!mounted) return;
      setState(() {
        _impact = refreshed;
        _refreshing = false;
        _contextUnavailable = false;
        _refreshError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _refreshing = false;
        _contextUnavailable = true;
        _refreshError = '关联事项读取失败，复核信息已过期；请重试后再保存。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final media = MediaQuery.sizeOf(context);
    final maxHeight = (media.height * 0.68).clamp(280.0, 620.0);
    final deltas = _impact.deltas;
    final displayedDeltas = _showAllDeltas
        ? deltas
        : deltas.take(4).toList(growable: false);
    final displayedPlans = _showAllPlans
        ? _impact.planBlocks
        : _impact.planBlocks.take(5).toList(growable: false);
    final displayedReminders = _showAllReminders
        ? _impact.reminders
        : _impact.reminders.take(5).toList(growable: false);

    return AlertDialog(
      key: const ValueKey('fixed-schedule-reschedule-impact-dialog'),
      title: const Row(
        children: [
          Icon(Icons.event_repeat_rounded),
          SizedBox(width: 10),
          Expanded(child: Text('复核改期影响')),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            child: _contextUnavailable
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_refreshing) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 12),
                      ],
                      Text(
                        _refreshError ?? '正在重新读取关联事项，请稍候。',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                      if (_refreshError != null)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _refreshImpact,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('重试复核'),
                          ),
                        ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '以下信息按当前编辑范围汇总。待办、规划和提醒配置都不会被自动修改。',
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 16),
                      _SectionTitle(
                        title: '日程变化',
                        count: deltas.length,
                        icon: Icons.event_available_outlined,
                      ),
                      if (deltas.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        _AffectedRangeSummary(deltas: deltas),
                      ],
                      const SizedBox(height: 6),
                      for (final delta in displayedDeltas)
                        _ScheduleDeltaTile(delta: delta),
                      if (deltas.length > displayedDeltas.length)
                        _ShowMoreButton(
                          label: _showAllDeltas
                              ? '收起场次'
                              : '查看其余 ${deltas.length - 4} 场',
                          onPressed: () =>
                              setState(() => _showAllDeltas = !_showAllDeltas),
                        ),
                      const SizedBox(height: 12),
                      _SectionTitle(
                        title: '关联待办',
                        count: _impact.visibleTodos.length,
                        icon: Icons.checklist_rounded,
                      ),
                      const SizedBox(height: 6),
                      if (_impact.relatedTodoIds.isEmpty)
                        const _EmptyHint('没有关联待办。')
                      else if (_impact.visibleTodos.isEmpty)
                        const _EmptyHint('关联待办已删除或当前不可见，已隐藏其内容。')
                      else
                        for (final todo in _impact.visibleTodos)
                          _TodoImpactTile(
                            todo: todo,
                            deadlineNeedsReview:
                                FixedScheduleRescheduleImpactService.todoDeadlineNeedsReview(
                                  todo,
                                  deltas,
                                ),
                            onTap: () => _openTodo(todo),
                          ),
                      const SizedBox(height: 12),
                      _SectionTitle(
                        title: '与新日程重叠的规划',
                        count: _impact.planBlocks.length,
                        icon: Icons.view_timeline_outlined,
                      ),
                      const SizedBox(height: 6),
                      if (_impact.planBlocks.isEmpty)
                        const _EmptyHint('没有发现有效规划重叠。')
                      else ...[
                        for (
                          var index = 0;
                          index < displayedPlans.length;
                          index++
                        )
                          _PlanImpactTile(
                            plan: displayedPlans[index],
                            conflict: _impact.planConflicts[index],
                            key: ValueKey(
                              'reschedule-impact-plan-${displayedPlans[index].id}-${_impact.planConflicts[index].startTime}',
                            ),
                            onTap: () => _openPlan(displayedPlans[index]),
                          ),
                        if (_impact.planBlocks.length > displayedPlans.length)
                          _ShowMoreButton(
                            label: _showAllPlans
                                ? '收起重叠规划'
                                : '查看其余 ${_impact.planBlocks.length - 5} 项',
                            onPressed: () =>
                                setState(() => _showAllPlans = !_showAllPlans),
                          ),
                      ],
                      const SizedBox(height: 12),
                      _SectionTitle(
                        title: '保存后提醒',
                        count: _impact.reminders.length,
                        icon: Icons.notifications_active_outlined,
                      ),
                      const SizedBox(height: 6),
                      if (_impact.reminders.isEmpty)
                        const _EmptyHint('没有尚未开始日程的有效提醒。')
                      else ...[
                        for (final reminder in displayedReminders)
                          _ReminderImpactTile(reminder: reminder),
                        if (_impact.reminders.length >
                            displayedReminders.length)
                          _ShowMoreButton(
                            label: _showAllReminders
                                ? '收起提醒'
                                : '查看其余 ${_impact.reminders.length - 5} 项',
                            onPressed: () => setState(
                              () => _showAllReminders = !_showAllReminders,
                            ),
                          ),
                      ],
                      if (_refreshing) ...[
                        const SizedBox(height: 12),
                        const LinearProgressIndicator(),
                      ],
                      if (_refreshError != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colors.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: colors.onErrorContainer,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _refreshError!,
                                  style: TextStyle(
                                    color: colors.onErrorContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _refreshImpact,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('重试复核'),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _refreshing ? null : () => Navigator.pop(context),
          child: const Text('返回修改'),
        ),
        FilledButton(
          key: const ValueKey('confirm-reschedule-impact'),
          onPressed: _refreshing || _contextUnavailable || _refreshError != null
              ? null
              : () => Navigator.pop(context, _impact),
          child: const Text('按此范围保存'),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.count,
    required this.icon,
  });

  final String title;
  final int count;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: colors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        Text('$count', style: Theme.of(context).textTheme.labelLarge),
      ],
    );
  }
}

class _AffectedRangeSummary extends StatelessWidget {
  const _AffectedRangeSummary({required this.deltas});

  final List<FixedScheduleRescheduleDelta> deltas;

  @override
  Widget build(BuildContext context) {
    final dates =
        deltas
            .expand((delta) => [delta.before?.date, delta.after?.date])
            .whereType<String>()
            .toList()
          ..sort();
    final first = dates.isEmpty ? null : DateTime.tryParse(dates.first);
    final last = dates.isEmpty ? null : DateTime.tryParse(dates.last);
    final range = first == null || last == null
        ? '日期范围待定'
        : first == last
        ? AppTimeFormats.format(first, 'yyyy年M月d日')
        : '${AppTimeFormats.format(first, 'yyyy年M月d日')} – ${AppTimeFormats.format(last, 'yyyy年M月d日')}';
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '受影响 ${deltas.length} 场 · $range',
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: colors.onSecondaryContainer),
      ),
    );
  }
}

class _ScheduleDeltaTile extends StatelessWidget {
  const _ScheduleDeltaTile({required this.delta});

  final FixedScheduleRescheduleDelta delta;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final before = delta.before;
    final after = delta.after;
    final detail = before == null
        ? '新增 · ${_scheduleDateAndTime(after!)}'
        : after == null
        ? '移除 · ${_scheduleDateAndTime(before)}'
        : '${_scheduleDateAndTime(before)}\n↓\n${_scheduleDateAndTime(after)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.schedule_rounded,
            size: 18,
            color: colors.onSurfaceVariant,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  delta.title,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TodoImpactTile extends StatelessWidget {
  const _TodoImpactTile({
    required this.todo,
    required this.deadlineNeedsReview,
    required this.onTap,
  });

  final TodoItem todo;
  final bool deadlineNeedsReview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final due = todo.dueDate?.toLocal();
    final dueText = due == null
        ? '未设置期限'
        : todo.isDateOnly
        ? '${AppTimeFormats.format(due, 'yyyy年M月d日')}内完成'
        : '截止 ${AppTimeFormats.format(due, 'yyyy年M月d日 HH:mm')}';
    final status = todo.isDone
        ? '已完成'
        : todo.isSkipped
        ? '已跳过'
        : todo.hasConflict
        ? '存在同步冲突'
        : '待完成';
    return ListTile(
      key: ValueKey('reschedule-impact-todo-${todo.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 2),
      dense: true,
      title: Text(todo.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$status · $dueText'),
          if (deadlineNeedsReview)
            Text(
              todo.isDateOnly ? '完成日期晚于其中一场日程，请核对' : '截止时间晚于其中一场日程开始，请核对',
              style: TextStyle(color: colors.tertiary),
            ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _PlanImpactTile extends StatelessWidget {
  const _PlanImpactTile({
    super.key,
    required this.plan,
    required this.conflict,
    required this.onTap,
  });

  final TodoPlanBlock plan;
  final ScheduleConflict conflict;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final start = DateTime.fromMillisecondsSinceEpoch(plan.startTime).toLocal();
    final end = DateTime.fromMillisecondsSinceEpoch(plan.endTime).toLocal();
    final overlapStart = DateTime.fromMillisecondsSinceEpoch(conflict.startTime)
        .toLocal();
    final overlapEnd = DateTime.fromMillisecondsSinceEpoch(conflict.endTime)
        .toLocal();
    final title = plan.titleSnapshot?.trim().isNotEmpty == true
        ? plan.titleSnapshot!.trim()
        : '未命名规划';
    final scheduleTitle = conflict.leftKind == ScheduleEntityKind.fixedSchedule
        ? conflict.leftTitle
        : conflict.rightTitle;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 2),
      dense: true,
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '$scheduleTitle · ${_formatTimeRange(start, end)} · 重叠 ${_formatTimeRange(overlapStart, overlapEnd)} · ${_planStatusLabel(plan.status)}',
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _ReminderImpactTile extends StatelessWidget {
  const _ReminderImpactTile({required this.reminder});

  final FixedScheduleReminderPreview reminder;

  @override
  Widget build(BuildContext context) {
    final triggerAt = AppTimeFormats.format(
      reminder.triggerAt,
      'yyyy年M月d日 HH:mm',
    );
    final advance = reminder.advanceMinutes == 0
        ? '准时'
        : reminder.advanceMinutes % 1440 == 0
        ? '提前${reminder.advanceMinutes ~/ 1440}天'
        : reminder.advanceMinutes % 60 == 0
        ? '提前${reminder.advanceMinutes ~/ 60}小时'
        : '提前${reminder.advanceMinutes}分钟';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.notifications_none_rounded, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '${reminder.scheduleTitle} · $advance：$triggerAt${reminder.isPastAt(DateTime.now()) ? '（提醒时点已过）' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text(
      label,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

class _ShowMoreButton extends StatelessWidget {
  const _ShowMoreButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: TextButton(onPressed: onPressed, child: Text(label)),
  );
}

String _scheduleDateAndTime(FixedScheduleItem? item) {
  if (item == null) return '';
  final date = DateTime.tryParse(item.date)?.toLocal();
  final dateLabel = date == null
      ? item.date
      : AppTimeFormats.format(date, 'yyyy年M月d日');
  if (item.startTime == null) return '$dateLabel · 时间待定';
  final start = DateTime.fromMillisecondsSinceEpoch(item.startTime!).toLocal();
  final startLabel = AppTimeFormats.format(start, 'HH:mm');
  if (item.endTime == null) return '$dateLabel · $startLabel开始 · 结束时间待定';
  final end = DateTime.fromMillisecondsSinceEpoch(item.endTime!).toLocal();
  return '$dateLabel · ${_formatTimeRange(start, end)}';
}

String _formatTimeRange(DateTime start, DateTime end) {
  final endPattern =
      start.year == end.year && start.month == end.month && start.day == end.day
      ? 'HH:mm'
      : 'yyyy年M月d日 HH:mm';
  return '${AppTimeFormats.format(start, 'yyyy年M月d日 HH:mm')} – ${AppTimeFormats.format(end, endPattern)}';
}

String _planStatusLabel(TodoPlanStatus status) => switch (status) {
  TodoPlanStatus.planned => '待执行',
  TodoPlanStatus.finished => '已完成',
  TodoPlanStatus.delayed => '已延后',
  TodoPlanStatus.cancelled => '已取消',
  TodoPlanStatus.reminded => '已提醒',
  TodoPlanStatus.focusing => '专注中',
  TodoPlanStatus.missed => '已漏做',
  TodoPlanStatus.skipped => '已跳过',
};
