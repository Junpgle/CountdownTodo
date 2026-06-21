import 'package:flutter/foundation.dart';

class StorageConflictCleanup {
  const StorageConflictCleanup._();

  static Future<void> clearGhostConflictFlags(dynamic db) async {
    const emptyConflictWhere =
        "has_conflict = 1 AND (conflict_data IS NULL OR TRIM(conflict_data) = '' OR conflict_data = 'null')";
    const staleConflictDataWhere =
        "has_conflict = 0 AND conflict_data IS NOT NULL AND TRIM(conflict_data) != '' AND conflict_data != 'null'";

    for (final table in const ['todos', 'todo_groups', 'countdowns']) {
      try {
        final emptySnapshotCount = await db.update(
          table,
          {'has_conflict': 0, 'conflict_data': null},
          where: emptyConflictWhere,
        );
        final staleSnapshotCount = await db.update(
          table,
          {'conflict_data': null},
          where: staleConflictDataWhere,
        );
        if (emptySnapshotCount > 0 || staleSnapshotCount > 0) {
          debugPrint(
              '✅ 已清理 $table 的幽灵冲突: empty=$emptySnapshotCount stale=$staleSnapshotCount');
        }
      } catch (e) {
        debugPrint('⚠️ 清理 $table 幽灵冲突失败: $e');
      }
    }
  }
}
