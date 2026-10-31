import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../services/todo_deadline_fixed_schedule_review_service.dart';

Future<bool?> showTodoDeadlineFixedScheduleReviewDialog(
  BuildContext context,
  TodoDeadlineFixedScheduleReview review,
) {
  if (!review.needsReview) return Future.value(true);
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final colors = Theme.of(dialogContext).colorScheme;
      final screenHeight = MediaQuery.sizeOf(dialogContext).height;
      var showAllGroups = false;
      return AlertDialog(
        key: const ValueKey('todo-deadline-fixed-schedule-review-dialog'),
        title: const Text('关联固定日程复核'),
        content: SizedBox(
          width: 480,
          height: math.min(screenHeight * 0.62, 560),
          child: StatefulBuilder(
            builder: (context, setContentState) {
              final visibleGroups = showAllGroups
                  ? review.groups
                  : review.groups.take(5).toList(growable: false);
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '以下待办期限晚于关联日程开始，请核对是否仍要继续保存。',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    ...visibleGroups.map(
                      (group) => _ReviewGroupCard(group: group),
                    ),
                    if (review.groups.length > 5)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const ValueKey('todo-deadline-review-show-more'),
                          onPressed: () => setContentState(
                            () => showAllGroups = !showAllGroups,
                          ),
                          icon: Icon(
                            showAllGroups
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                          ),
                          label: Text(
                            showAllGroups
                                ? '收起'
                                : '查看其余 ${review.groups.length - 5} 项',
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.secondaryContainer.withValues(
                          alpha: 0.55,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          '这是期限核对提示，不代表时间冲突。确认后只保存待办修改，不会移动固定日程。',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSecondaryContainer),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('todo-deadline-review-return'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('返回修改'),
          ),
          FilledButton(
            key: const ValueKey('todo-deadline-review-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认保存'),
          ),
        ],
      );
    },
  );
}

class _ReviewGroupCard extends StatelessWidget {
  const _ReviewGroupCard({required this.group});

  final TodoDeadlineFixedScheduleReviewGroup group;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final shownEntries = group.entries.length <= 3
        ? group.entries
        : group.entries.take(2).toList(growable: false);
    final first = group.firstStart;
    final last = group.lastStart;
    final summary = group.isSeries
        ? '${group.entries.length} 场 · ${_formatDay(first)}—${_formatDay(last)}'
        : _formatTime(first);
    return Card(
      color: colors.surfaceContainerLow,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.event_note_rounded, color: colors.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.title.isEmpty ? '未命名固定日程' : group.title,
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        summary,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...shownEntries.map((entry) => _ReviewEntry(entry: entry)),
            if (group.entries.length > shownEntries.length)
              ExpansionTile(
                key: ValueKey('todo-deadline-series-${group.key}'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(top: 4),
                title: Text('查看全部 ${group.entries.length} 场'),
                children: group.entries
                    .skip(shownEntries.length)
                    .map((entry) => _ReviewEntry(entry: entry))
                    .toList(growable: false),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReviewEntry extends StatelessWidget {
  const _ReviewEntry({required this.entry});

  final TodoDeadlineFixedScheduleReviewEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final start = entry.schedule.startTime == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(entry.schedule.startTime!)
              .toLocal();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.afterTodo.title,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                '日程开始 · ${_formatTime(start)}',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              Text(
                '期限  ${_deadlineLabel(entry.beforeTodo)}  →  ${_deadlineLabel(entry.afterTodo)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                '期限晚于日程开始，请核对',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.tertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final DateFormat _reviewDayFormat = DateFormat('M月d日');
final DateFormat _reviewTimeFormat = DateFormat('M月d日 HH:mm');

String _deadlineLabel(TodoItem todo) {
  final due = todo.dueDate?.toLocal();
  if (due == null) return '未设置期限';
  return todo.isDateOnly
      ? '${_reviewDayFormat.format(due)} 内完成'
      : '${_reviewTimeFormat.format(due)} 前完成';
}

String _formatDay(DateTime? value) =>
    value == null ? '日期待定' : _reviewDayFormat.format(value);

String _formatTime(DateTime? value) =>
    value == null ? '时间待定' : _reviewTimeFormat.format(value);
