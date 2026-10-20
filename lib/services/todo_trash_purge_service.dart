import '../models.dart';

enum TodoTrashPurgeScope { item, series, recycleBin }

class TodoTrashPurgeEntry {
  const TodoTrashPurgeEntry({
    required this.uuid,
    required this.version,
    required this.updatedAt,
    required this.isDeleted,
  });

  final String uuid;
  final int version;
  final int updatedAt;
  final bool isDeleted;

  factory TodoTrashPurgeEntry.fromTodo(TodoItem todo) => TodoTrashPurgeEntry(
    uuid: todo.id,
    version: todo.version,
    updatedAt: todo.updatedAt,
    isDeleted: todo.isDeleted,
  );

  @override
  bool operator ==(Object other) =>
      other is TodoTrashPurgeEntry &&
      other.uuid == uuid &&
      other.version == version &&
      other.updatedAt == updatedAt &&
      other.isDeleted == isDeleted;

  @override
  int get hashCode => Object.hash(uuid, version, updatedAt, isDeleted);
}

class TodoTrashPurgePreview {
  const TodoTrashPurgePreview({
    required this.recordCount,
    required this.occurrenceCount,
    required this.completedCount,
    required this.skippedCount,
    required this.firstDate,
    required this.lastDate,
    required this.hasActiveSeriesMembers,
  });

  final int recordCount;
  final int occurrenceCount;
  final int completedCount;
  final int skippedCount;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool hasActiveSeriesMembers;
}

class TodoTrashPurgePlan {
  TodoTrashPurgePlan({
    required this.scope,
    required List<TodoTrashPurgeEntry> targetEntries,
    required List<TodoTrashPurgeEntry> guardEntries,
    required this.preview,
    this.seriesId,
  }) : targetEntries = List.unmodifiable(targetEntries),
       guardEntries = List.unmodifiable(guardEntries);

  final TodoTrashPurgeScope scope;
  final String? seriesId;
  final List<TodoTrashPurgeEntry> targetEntries;

  /// All rows whose membership and version must stay unchanged until commit.
  final List<TodoTrashPurgeEntry> guardEntries;
  final TodoTrashPurgePreview preview;

  Set<String> get targetIds => targetEntries.map((entry) => entry.uuid).toSet();
}

class TodoTrashPurgeResult {
  const TodoTrashPurgeResult({
    required this.deletedCount,
    required this.cacheCleared,
    required this.conflictsRefreshed,
  });

  final int deletedCount;
  final bool cacheCleared;
  final bool conflictsRefreshed;
}

class TodoTrashPurgeService {
  const TodoTrashPurgeService._();

  static TodoTrashPurgePlan forItem(TodoItem item) {
    if (!item.isDeleted) {
      throw StateError('该待办已不在回收站，请刷新后再试。');
    }
    final entry = TodoTrashPurgeEntry.fromTodo(item);
    return TodoTrashPurgePlan(
      scope: TodoTrashPurgeScope.item,
      targetEntries: [entry],
      guardEntries: [entry],
      preview: _preview([item], hasActiveSeriesMembers: false),
    );
  }

  static TodoTrashPurgePlan forSeries(List<TodoItem> members, String seriesId) {
    final normalizedId = seriesId.trim();
    if (normalizedId.isEmpty) {
      throw StateError('系列标识无效，无法批量清理。');
    }
    final seriesMembers = members.where((todo) {
      final memberSeriesId = todo.recurrenceSeriesId?.trim();
      return memberSeriesId == normalizedId ||
          (todo.id == normalizedId &&
              (memberSeriesId?.isNotEmpty ?? false) == false);
    }).toList();
    final deleted = seriesMembers.where((todo) => todo.isDeleted).toList();
    if (deleted.isEmpty) {
      throw StateError('该系列已没有回收站记录，请刷新后再试。');
    }
    return TodoTrashPurgePlan(
      scope: TodoTrashPurgeScope.series,
      seriesId: normalizedId,
      targetEntries: deleted.map(TodoTrashPurgeEntry.fromTodo).toList(),
      guardEntries: seriesMembers.map(TodoTrashPurgeEntry.fromTodo).toList(),
      preview: _preview(
        deleted,
        hasActiveSeriesMembers: seriesMembers.any((todo) => !todo.isDeleted),
      ),
    );
  }

  static TodoTrashPurgePlan forRecycleBin(List<TodoItem> deletedTodos) {
    final deleted = deletedTodos.where((todo) => todo.isDeleted).toList();
    if (deleted.isEmpty) {
      throw StateError('回收站已经为空，请刷新后再试。');
    }
    final entries = deleted.map(TodoTrashPurgeEntry.fromTodo).toList();
    return TodoTrashPurgePlan(
      scope: TodoTrashPurgeScope.recycleBin,
      targetEntries: entries,
      guardEntries: entries,
      preview: _preview(deleted, hasActiveSeriesMembers: false),
    );
  }

  static bool sameSnapshot(
    List<TodoTrashPurgeEntry> current,
    List<TodoTrashPurgeEntry> expected,
  ) {
    if (current.length != expected.length) return false;
    final byId = {for (final entry in expected) entry.uuid: entry};
    if (byId.length != expected.length) return false;
    return current.every((entry) => byId[entry.uuid] == entry);
  }

  static TodoTrashPurgePreview _preview(
    List<TodoItem> items, {
    required bool hasActiveSeriesMembers,
  }) {
    final byDay = <String, List<TodoItem>>{};
    final dates = <DateTime>[];
    for (final item in items) {
      final timestamp = item.createdDate ?? item.createdAt;
      final local = DateTime.fromMillisecondsSinceEpoch(
        timestamp,
        isUtc: true,
      ).toLocal();
      final day = DateTime(local.year, local.month, local.day);
      final key = '${day.year}-${day.month}-${day.day}';
      byDay.putIfAbsent(key, () => []).add(item);
      dates.add(day);
    }
    dates.sort();
    return TodoTrashPurgePreview(
      recordCount: items.length,
      occurrenceCount: byDay.length,
      completedCount: byDay.values
          .where((period) => period.any((item) => item.isDone))
          .length,
      skippedCount: byDay.values
          .where((period) => period.any((item) => item.isSkipped))
          .length,
      firstDate: dates.isEmpty ? null : dates.first,
      lastDate: dates.isEmpty ? null : dates.last,
      hasActiveSeriesMembers: hasActiveSeriesMembers,
    );
  }
}
