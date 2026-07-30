import 'package:flutter/material.dart';

import '../models.dart';

class TodoRecurrenceCompletionSummary {
  const TodoRecurrenceCompletionSummary({
    required this.completedCount,
    required this.pendingCount,
    required this.overdueCount,
    required this.futureCount,
    required this.elapsedCount,
    required this.totalCount,
  });

  final int completedCount;
  final int pendingCount;
  final int overdueCount;
  final int futureCount;
  final int elapsedCount;
  final int totalCount;

  double get completionRate =>
      elapsedCount == 0 ? 0 : completedCount / elapsedCount;
}

/// 循环待办编辑页中的完成情况总览。
///
/// 完成率只统计已经开始的期次，未来预生成实例单独展示，避免开放式循环
/// 因为提前生成了未来实例而长期显示一个偏低的完成率。
class TodoRecurrenceCompletionOverview extends StatelessWidget {
  const TodoRecurrenceCompletionOverview({
    super.key,
    required this.occurrences,
    this.currentTodoId,
    this.currentIsDone,
    this.now,
  });

  final List<TodoItem> occurrences;
  final String? currentTodoId;
  final bool? currentIsDone;
  final DateTime? now;

  static TodoRecurrenceCompletionSummary calculateSummary({
    required List<TodoItem> occurrences,
    required DateTime now,
    String? currentTodoId,
    bool? currentIsDone,
  }) {
    var completedCount = 0;
    var pendingCount = 0;
    var overdueCount = 0;
    var futureCount = 0;
    var elapsedCount = 0;

    for (final occurrence in occurrences.where((todo) => !todo.isDeleted)) {
      final start = DateTime.fromMillisecondsSinceEpoch(
        occurrence.createdDate ?? occurrence.createdAt,
        isUtc: true,
      ).toLocal();
      final isDone = occurrence.id == currentTodoId && currentIsDone != null
          ? currentIsDone
          : occurrence.isDone;

      if (isDone) {
        completedCount++;
        elapsedCount++;
        continue;
      }
      if (start.isAfter(now)) {
        futureCount++;
        continue;
      }

      elapsedCount++;
      final effectiveEnd = occurrence.dueDate?.toLocal() ??
          DateTime(start.year, start.month, start.day + 1);
      if (effectiveEnd.isBefore(now)) {
        overdueCount++;
      } else {
        pendingCount++;
      }
    }

    return TodoRecurrenceCompletionSummary(
      completedCount: completedCount,
      pendingCount: pendingCount,
      overdueCount: overdueCount,
      futureCount: futureCount,
      elapsedCount: elapsedCount,
      totalCount: completedCount + pendingCount + overdueCount + futureCount,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final summary = calculateSummary(
      occurrences: occurrences,
      now: now ?? DateTime.now(),
      currentTodoId: currentTodoId,
      currentIsDone: currentIsDone,
    );
    final percentage = (summary.completionRate * 100).round();

    return Semantics(
      label: '循环待办完成情况，完成率$percentage%，'
          '已完成${summary.completedCount}期，待完成${summary.pendingCount}期，'
          '已逾期${summary.overdueCount}期，未开始${summary.futureCount}期',
      child: Container(
        key: const ValueKey('recurrence_completion_overview'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.38),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.donut_large_rounded,
                  size: 17,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 7),
                const Expanded(
                  child: Text(
                    '完成情况总览',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '完成率 $percentage%',
                  key: const ValueKey('recurrence_completion_rate'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            LinearProgressIndicator(
              key: const ValueKey('recurrence_completion_progress'),
              value: summary.completionRate,
              minHeight: 7,
              borderRadius: BorderRadius.circular(99),
              backgroundColor: colorScheme.surfaceContainerHighest,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 5),
            Text(
              '已发生 ${summary.elapsedCount} 期 · 当前共 ${summary.totalCount} 期实例',
              style: TextStyle(
                fontSize: 10.5,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _Metric(
                  label: '已完成',
                  count: summary.completedCount,
                  color: colorScheme.primary,
                ),
                _Metric(
                  label: '待完成',
                  count: summary.pendingCount,
                  color: colorScheme.tertiary,
                ),
                _Metric(
                  label: '已逾期',
                  count: summary.overdueCount,
                  color: colorScheme.error,
                ),
                _Metric(
                  label: '未开始',
                  count: summary.futureCount,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$count',
            key: ValueKey('recurrence_metric_$label'),
            style: TextStyle(
              fontSize: 17,
              height: 1,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
