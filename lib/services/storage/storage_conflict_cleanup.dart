import 'package:flutter/foundation.dart';

class StorageConflictCleanup {
  const StorageConflictCleanup._();

  static const _allTables = <String>['todos', 'todo_groups', 'countdowns'];
  static const _supportedTables = <String>{
    'todos',
    'todo_groups',
    'countdowns',
  };

  static Future<void> clearGhostConflictFlags(
    dynamic db, {
    Iterable<String> tables = _allTables,
  }) async {
    const emptyConflictWhere =
        "has_conflict = 1 AND (conflict_data IS NULL OR TRIM(conflict_data) = '' OR conflict_data = 'null')";
    const staleConflictDataWhere =
        "has_conflict = 0 AND conflict_data IS NOT NULL AND TRIM(conflict_data) != '' AND conflict_data != 'null'";

    for (final table in tables) {
      if (!_supportedTables.contains(table)) continue;
      try {
        final updatedCount = await db.rawUpdate(
          'UPDATE $table '
          'SET has_conflict = CASE WHEN has_conflict = 1 THEN 0 ELSE has_conflict END, '
          'conflict_data = NULL '
          'WHERE ($emptyConflictWhere) OR ($staleConflictDataWhere)',
        );
        if (updatedCount > 0) {
          debugPrint('✅ 已清理 $table 的幽灵冲突: rows=$updatedCount');
        }
      } catch (e) {
        debugPrint('⚠️ 清理 $table 幽灵冲突失败: $e');
      }
    }
  }
}
