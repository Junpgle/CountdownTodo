class SyncOplogEntry {
  const SyncOplogEntry({
    required this.id,
    required this.table,
    required this.uuid,
  });

  final int id;
  final String table;
  final String uuid;

  static SyncOplogEntry? fromRow(Map<String, dynamic> row) {
    final id = (row['id'] as num?)?.toInt();
    final table = row['target_table']?.toString() ?? '';
    final uuid = row['target_uuid']?.toString() ?? '';
    if (id == null || table.isEmpty || uuid.isEmpty) return null;
    return SyncOplogEntry(id: id, table: table, uuid: uuid);
  }
}

class SyncOplogResolution {
  const SyncOplogResolution({
    required this.acknowledgedIds,
    required this.blockedIds,
  });

  final Set<int> acknowledgedIds;
  final Set<int> blockedIds;
}

/// 同步请求与本地 oplog 之间的确认边界。
///
/// 只有请求发出前已经进入快照的操作才能被本次响应确认。
/// 请求进行期间新增的操作必须留待下一次同步，并保护对应待办
/// 不被本次响应中的旧快照覆盖。
class SyncOplogPolicy {
  SyncOplogPolicy._();

  static SyncOplogResolution resolveRequestSnapshot({
    required Iterable<SyncOplogEntry> requestSnapshot,
    required Set<String> blockingConflictUuids,
    required bool acknowledgeFixedScheduleOps,
  }) {
    final acknowledgedIds = <int>{};
    final blockedIds = <int>{};

    for (final entry in requestSnapshot) {
      if (entry.table == 'pomodoro_records' ||
          entry.table == 'pomodoro_tags' ||
          (!acknowledgeFixedScheduleOps && entry.table == 'fixed_schedules')) {
        continue;
      }
      if (blockingConflictUuids.contains(entry.uuid)) {
        blockedIds.add(entry.id);
      } else {
        acknowledgedIds.add(entry.id);
      }
    }

    return SyncOplogResolution(
      acknowledgedIds: acknowledgedIds,
      blockedIds: blockedIds,
    );
  }

  static Set<String> todoUuids(Iterable<SyncOplogEntry> entries) => entries
      .where((entry) => entry.table == 'todos')
      .map((entry) => entry.uuid)
      .toSet();

  static Set<String> todoUuidsCreatedAfterSnapshot({
    required Iterable<SyncOplogEntry> requestSnapshot,
    required Iterable<SyncOplogEntry> currentPending,
  }) {
    final requestIds = requestSnapshot.map((entry) => entry.id).toSet();
    return currentPending
        .where(
            (entry) => entry.table == 'todos' && !requestIds.contains(entry.id))
        .map((entry) => entry.uuid)
        .toSet();
  }

  static bool shouldProtectTodoMerge(
    String uuid, {
    required Set<String> forceFlushUuids,
    required Set<String> inFlightMutationUuids,
  }) =>
      forceFlushUuids.contains(uuid) || inFlightMutationUuids.contains(uuid);
}
