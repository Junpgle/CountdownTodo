import 'package:flutter/material.dart';

import '../models.dart';
import '../services/todo_recurrence_delete_service.dart';
import '../utils/app_dialogs.dart';

Future<TodoRecurrenceDeleteScope?> showTodoRecurrenceDeleteDialog({
  required BuildContext context,
  required TodoItem todo,
  required List<TodoItem> todos,
}) async {
  var selectedScope = TodoRecurrenceDeleteScope.occurrence;
  final scope = await showAppModalBottomSheet<TodoRecurrenceDeleteScope>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setModalState) {
        final scheme = Theme.of(context).colorScheme;
        final titleStyle = Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w700);
        final options = [
          TodoRecurrenceDeleteScope.occurrence,
          TodoRecurrenceDeleteScope.future,
          TodoRecurrenceDeleteScope.series,
        ];
        return Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                6,
                20,
                16 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.delete_outline_rounded, color: scheme.error),
                        const SizedBox(width: 10),
                        Expanded(child: Text('移至回收站', style: titleStyle)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '选择「${todo.title}」的删除范围',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 14),
                    for (final option in options)
                      _TodoRecurrenceDeleteOption(
                        key: ValueKey('recurrence_delete_${option.name}'),
                        todos: todos,
                        todo: todo,
                        scope: option,
                        selected: selectedScope == option,
                        onTap: () => setModalState(() {
                          selectedScope = option;
                        }),
                      ),
                    if (selectedScope == TodoRecurrenceDeleteScope.series) ...[
                      const SizedBox(height: 4),
                      Text(
                        '已完成和已跳过期次也会移入回收站。记录可在回收站逐期恢复。',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            child: const Text('取消'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            key: const ValueKey('confirm_recurrence_delete'),
                            onPressed: () =>
                                Navigator.pop(sheetContext, selectedScope),
                            style: FilledButton.styleFrom(
                              backgroundColor: scheme.error,
                              foregroundColor: scheme.onError,
                            ),
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: Text(
                              selectedScope == TodoRecurrenceDeleteScope.series
                                  ? '继续'
                                  : '移入回收站',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
  if (scope == null ||
      scope != TodoRecurrenceDeleteScope.series ||
      !context.mounted) {
    return scope;
  }

  final preview = TodoRecurrenceDeleteService.preview(
    todos: todos,
    todoId: todo.id,
    scope: scope,
  );
  final accepted = await showAppDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(
        Icons.delete_forever_outlined,
        color: Theme.of(dialogContext).colorScheme.error,
      ),
      title: const Text('移入整个重复系列？'),
      content: Text(
        '这会将 ${preview.occurrenceCount} 期（${preview.completedCount} 期已完成，${preview.skippedCount} 期已跳过）移入回收站。重复生成将停止，关联规划、专注和时间日志会保留。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('返回'),
        ),
        FilledButton(
          key: const ValueKey('confirm_delete_recurrence_series'),
          onPressed: () => Navigator.pop(dialogContext, true),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
            foregroundColor: Theme.of(dialogContext).colorScheme.onError,
          ),
          child: const Text('移入整个系列'),
        ),
      ],
    ),
  );
  return accepted == true ? scope : null;
}

class _TodoRecurrenceDeleteOption extends StatelessWidget {
  const _TodoRecurrenceDeleteOption({
    super.key,
    required this.todos,
    required this.todo,
    required this.scope,
    required this.selected,
    required this.onTap,
  });

  final List<TodoItem> todos;
  final TodoItem todo;
  final TodoRecurrenceDeleteScope scope;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preview = TodoRecurrenceDeleteService.preview(
      todos: todos,
      todoId: todo.id,
      scope: scope,
    );
    final title = switch (scope) {
      TodoRecurrenceDeleteScope.occurrence => '仅本期',
      TodoRecurrenceDeleteScope.future => '本期及以后',
      TodoRecurrenceDeleteScope.series => '整个系列',
    };
    final description = switch (scope) {
      TodoRecurrenceDeleteScope.occurrence => '后续期次照常保留',
      TodoRecurrenceDeleteScope.future => '此前期次保留，停止后续生成',
      TodoRecurrenceDeleteScope.series => '移除所有已生成期次，停止重复生成',
    };
    final status = [
      if (preview.completedCount > 0) '${preview.completedCount}期已完成',
      if (preview.skippedCount > 0) '${preview.skippedCount}期已跳过',
    ];
    final countLabel = preview.occurrenceCount == 1
        ? '1期'
        : '${preview.occurrenceCount}期';

    return Semantics(
      button: true,
      selected: selected,
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        color: selected ? scheme.errorContainer.withValues(alpha: 0.42) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? scheme.error : scheme.outlineVariant,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? scheme.error : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$title · $countLabel',
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      if (status.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          status.join(' · '),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                      if (preview.recordCount > preview.occurrenceCount)
                        Text(
                          '包含 ${preview.recordCount} 条记录（含重复数据）',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
