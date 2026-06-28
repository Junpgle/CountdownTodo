import 'package:flutter/material.dart';
import '../../../models.dart';

class WorkbenchTaskArea extends StatelessWidget {
  final bool isIdle;
  final bool isFocusing;
  final bool isRemoteWatching;
  final TodoItem? boundTodo;
  final Color contentColor;
  final VoidCallback onTap;
  final Key? bindKey;

  const WorkbenchTaskArea({
    super.key,
    required this.isIdle,
    required this.isFocusing,
    required this.isRemoteWatching,
    this.boundTodo,
    required this.contentColor,
    required this.onTap,
    this.bindKey,
  });

  @override
  Widget build(BuildContext context) {
    if (isRemoteWatching) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.track_changes_outlined,
                size: 15,
                color: const Color(0xFFFF6B6B).withValues(alpha: 0.7)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                boundTodo?.title ?? '自由专注',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight:
                      boundTodo != null ? FontWeight.w500 : FontWeight.normal,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (isFocusing) {
      return GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                boundTodo != null
                    ? Icons.track_changes_outlined
                    : Icons.add_task,
                size: 14,
                color: contentColor.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  boundTodo?.title ?? '无任务',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: contentColor.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
        key: bindKey,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.track_changes_outlined,
                  size: 15,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.6)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  boundTodo?.title ?? '自由专注',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ));
  }
}
