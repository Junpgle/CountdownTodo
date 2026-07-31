import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';

/// 循环待办编辑页顶部的期次选择器。
///
/// 当前期始终位于可视区域中央；父组件切换 [currentTodoId] 时只更新当前
/// 页面，不负责创建新的路由。
class TodoRecurrenceOccurrencePicker extends StatefulWidget {
  const TodoRecurrenceOccurrencePicker({
    super.key,
    required this.occurrences,
    required this.currentTodoId,
    required this.onSelected,
  });

  final List<TodoItem> occurrences;
  final String currentTodoId;
  final ValueChanged<TodoItem> onSelected;

  @override
  State<TodoRecurrenceOccurrencePicker> createState() =>
      _TodoRecurrenceOccurrencePickerState();
}

class _TodoRecurrenceOccurrencePickerState
    extends State<TodoRecurrenceOccurrencePicker> {
  static const double _cardWidth = 86;
  static const double _spacing = 8;

  final ScrollController _scrollController = ScrollController();
  bool _needsCenter = true;
  bool _animateNextCenter = false;

  @override
  void didUpdateWidget(covariant TodoRecurrenceOccurrencePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentTodoId != widget.currentTodoId ||
        !_hasSameOccurrenceOrder(oldWidget.occurrences, widget.occurrences)) {
      _needsCenter = true;
      _animateNextCenter = oldWidget.currentTodoId != widget.currentTodoId;
    }
  }

  bool _hasSameOccurrenceOrder(List<TodoItem> before, List<TodoItem> after) {
    if (before.length != after.length) return false;
    for (var index = 0; index < before.length; index++) {
      if (before[index].id != after[index].id) return false;
    }
    return true;
  }

  void _scheduleCenter(int currentIndex) {
    if (!_needsCenter || currentIndex < 0) return;
    _needsCenter = false;
    final animate = _animateNextCenter;
    _animateNextCenter = false;
    final target = currentIndex * (_cardWidth + _spacing);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      final offset = target.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (animate) {
        _scrollController.animateTo(
          offset,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollController.jumpTo(offset);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentIndex = widget.occurrences.indexWhere(
      (occurrence) => occurrence.id == widget.currentTodoId,
    );
    _scheduleCenter(currentIndex);

    return LayoutBuilder(
      builder: (context, constraints) {
        final sidePadding = constraints.maxWidth > _cardWidth
            ? (constraints.maxWidth - _cardWidth) / 2
            : 0.0;
        return SingleChildScrollView(
          key: const ValueKey('related_recurrence_scroll'),
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: sidePadding),
            child: Row(
              children: [
                for (var index = 0; index < widget.occurrences.length; index++)
                  Padding(
                    padding: EdgeInsets.only(
                      right:
                          index == widget.occurrences.length - 1 ? 0 : _spacing,
                    ),
                    child: _buildOccurrenceCard(
                      context,
                      widget.occurrences[index],
                      colorScheme,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOccurrenceCard(
    BuildContext context,
    TodoItem occurrence,
    ColorScheme colorScheme,
  ) {
    final isCurrent = occurrence.id == widget.currentTodoId;
    final start = DateTime.fromMillisecondsSinceEpoch(
      occurrence.createdDate ?? occurrence.createdAt,
      isUtc: true,
    ).toLocal();

    return Semantics(
      selected: isCurrent,
      button: !isCurrent,
      label: '${DateFormat('M月d日').format(start)}，'
          '${isCurrent ? '正在编辑' : occurrence.isDone ? '已完成' : '待完成'}',
      child: InkWell(
        key: ValueKey('related_recurrence_${occurrence.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: isCurrent ? null : () => widget.onSelected(occurrence),
        child: Container(
          width: _cardWidth,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: isCurrent
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isCurrent
                  ? colorScheme.primary.withValues(alpha: 0.45)
                  : colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            children: [
              Icon(
                occurrence.isDone
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 18,
                color: occurrence.isDone
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat('M月d日').format(start),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                isCurrent
                    ? '正在编辑'
                    : occurrence.isDone
                        ? '已完成'
                        : '待完成',
                style: TextStyle(
                  fontSize: 10,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
