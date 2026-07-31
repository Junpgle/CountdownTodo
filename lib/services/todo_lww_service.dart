/// 待办同步的严格 Last-Write-Wins 比较规则。
///
/// `updated_at` 是主顺序，只有时间戳完全相同时才使用版本号决胜。
/// 因此旧快照不能仅凭更高的本地版本号覆盖更新内容。
class TodoLwwService {
  TodoLwwService._();

  static int compare({
    required int incomingUpdatedAt,
    required int incomingVersion,
    required int currentUpdatedAt,
    required int currentVersion,
  }) {
    final timeOrder = incomingUpdatedAt.compareTo(currentUpdatedAt);
    if (timeOrder != 0) return timeOrder;
    return incomingVersion.compareTo(currentVersion);
  }

  static bool isIncomingWinner({
    required int incomingUpdatedAt,
    required int incomingVersion,
    required int currentUpdatedAt,
    required int currentVersion,
  }) =>
      compare(
        incomingUpdatedAt: incomingUpdatedAt,
        incomingVersion: incomingVersion,
        currentUpdatedAt: currentUpdatedAt,
        currentVersion: currentVersion,
      ) >
      0;

  static bool shouldReplaceRecurringSnapshot({
    required int incomingUpdatedAt,
    required int incomingVersion,
    required int currentUpdatedAt,
    required int currentVersion,
    bool incomingHasConflict = false,
  }) =>
      !incomingHasConflict &&
      isIncomingWinner(
        incomingUpdatedAt: incomingUpdatedAt,
        incomingVersion: incomingVersion,
        currentUpdatedAt: currentUpdatedAt,
        currentVersion: currentVersion,
      );
}
