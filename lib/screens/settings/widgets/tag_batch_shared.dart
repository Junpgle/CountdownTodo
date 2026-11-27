import 'package:flutter/material.dart';

import '../../../models.dart';
import '../../../services/pomodoro_service.dart';
import '../../../utils/calendar_date_math.dart';

/// 按可选附加条件、包容日期范围与关键词筛选番茄钟记录，并按开始时间倒序返回。
List<PomodoroRecord> filterTagBatchPomodoros(
  List<PomodoroRecord> records, {
  DateTimeRange? dateRange,
  String searchQuery = '',
  bool Function(PomodoroRecord)? extraPredicate,
}) {
  Iterable<PomodoroRecord> filtered = records;
  if (extraPredicate != null) {
    filtered = filtered.where(extraPredicate);
  }
  if (dateRange != null) {
    final range = CalendarDateMath.inclusiveDateRange(
      dateRange.start,
      dateRange.end,
    );
    final startMs = range.start.millisecondsSinceEpoch;
    final endMs = range.endExclusive.millisecondsSinceEpoch;
    filtered = filtered.where(
      (p) => p.startTime >= startMs && p.startTime < endMs,
    );
  }
  if (searchQuery.isNotEmpty) {
    final query = searchQuery.toLowerCase();
    filtered = filtered.where((p) {
      final title = (p.todoTitle ?? '').toLowerCase();
      final note = (p.note ?? '').toLowerCase();
      return title.contains(query) || note.contains(query);
    });
  }
  final result = filtered.toList()
    ..sort((a, b) => b.startTime.compareTo(a.startTime));
  return result;
}

/// 按可选附加条件、包容日期范围与关键词筛选时间日志，并按开始时间倒序返回。
List<TimeLogItem> filterTagBatchTimeLogs(
  List<TimeLogItem> logs, {
  DateTimeRange? dateRange,
  String searchQuery = '',
  bool Function(TimeLogItem)? extraPredicate,
}) {
  Iterable<TimeLogItem> filtered = logs;
  if (extraPredicate != null) {
    filtered = filtered.where(extraPredicate);
  }
  if (dateRange != null) {
    final range = CalendarDateMath.inclusiveDateRange(
      dateRange.start,
      dateRange.end,
    );
    final startMs = range.start.millisecondsSinceEpoch;
    final endMs = range.endExclusive.millisecondsSinceEpoch;
    filtered = filtered.where(
      (l) => l.startTime >= startMs && l.startTime < endMs,
    );
  }
  if (searchQuery.isNotEmpty) {
    final query = searchQuery.toLowerCase();
    filtered = filtered.where((l) {
      final title = l.title.toLowerCase();
      final remark = (l.remark ?? '').toLowerCase();
      return title.contains(query) || remark.contains(query);
    });
  }
  final result = filtered.toList()
    ..sort((a, b) => b.startTime.compareTo(a.startTime));
  return result;
}

/// 在已选中集合与当前可见 ID 列表之间切换全选状态。
void toggleSelectAllRecordIds(
  Set<String> selectedIds,
  Iterable<String> visibleIds,
) {
  final ids = visibleIds.toList();
  if (selectedIds.length == ids.length) {
    selectedIds.clear();
  } else {
    selectedIds
      ..clear()
      ..addAll(ids);
  }
}

/// 从 [tagUuids] 中移除 [remove] 并追加未包含的 [add]，返回列表是否发生变化。
bool mutateRecordTagUuids(
  List<String> tagUuids, {
  Iterable<String> remove = const [],
  Iterable<String> add = const [],
}) {
  var changed = false;
  for (final uuid in remove) {
    if (tagUuids.contains(uuid)) {
      tagUuids.remove(uuid);
      changed = true;
    }
  }
  for (final uuid in add) {
    if (!tagUuids.contains(uuid)) {
      tagUuids.add(uuid);
      changed = true;
    }
  }
  return changed;
}

/// 批量标签页与重绑标签页共用的记录搜索输入框。
class TagBatchRecordSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String query;
  final String hintText;
  final double borderRadius;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const TagBatchRecordSearchField({
    super.key,
    required this.controller,
    required this.query,
    required this.hintText,
    required this.borderRadius,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hintText,
        isDense: true,
        prefixIcon: const Icon(Icons.search, size: 18),
        suffixIcon: query.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: onClear,
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }
}

/// 带全选头栏与复选框的多选记录列表。
class TagBatchRecordListView<T> extends StatelessWidget {
  final List<T> items;
  final String Function(T item) idOf;
  final Set<String> selectedIds;
  final void Function(String id, bool selected) onToggleItem;
  final Widget selectAllHeader;
  final Widget Function(T item) itemTitle;
  final Widget Function(T item) itemSubtitle;
  final Widget? Function(T item) itemTrailing;
  final EdgeInsetsGeometry? listPadding;

  const TagBatchRecordListView({
    super.key,
    required this.items,
    required this.idOf,
    required this.selectedIds,
    required this.onToggleItem,
    required this.selectAllHeader,
    required this.itemTitle,
    required this.itemSubtitle,
    required this.itemTrailing,
    this.listPadding,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        selectAllHeader,
        Expanded(
          child: ListView.builder(
            padding: listPadding,
            findChildIndexCallback: (Key key) {
              if (key is ValueKey<String>) {
                final id = key.value;
                final index = items.indexWhere((item) => idOf(item) == id);
                return index != -1 ? index : null;
              }
              return null;
            },
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final id = idOf(item);
              final isSelected = selectedIds.contains(id);
              return RepaintBoundary(
                key: ValueKey<String>(id),
                child: ListTile(
                  leading: Checkbox(
                    value: isSelected,
                    onChanged: (value) => onToggleItem(id, value == true),
                  ),
                  title: itemTitle(item),
                  subtitle: itemSubtitle(item),
                  trailing: itemTrailing(item),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
