import '../models.dart';
import '../features/habits/models/habit_goal.dart';
import '../features/habits/models/habit_goal_rule.dart';

/// 统一同步冲突的可见性规则。
///
/// 冲突收件箱、首页角标和团队页计数必须使用同一套过滤口径，
/// 但是否要求团队归属由调用方通过 [isTeamVisibleConflict] 决定。
class ConflictVisibilityService {
  const ConflictVisibilityService._();

  /// 判断一个待办是否应该出现在冲突相关入口中。
  static bool isVisibleTodoConflict(TodoItem todo) {
    if (todo.isDeleted || !todo.hasConflict) return false;
    if (isAllDayTodo(todo)) return false;
    return hasVisibleConflictPeer(todo.serverVersionData);
  }

  static bool isVisibleTodoGroupConflict(TodoGroup group) =>
      !group.isDeleted && group.hasConflict;

  static bool isVisibleCountdownConflict(CountdownItem countdown) =>
      !countdown.isDeleted && countdown.hasConflict;

  static bool isVisibleHabitGoalConflict(HabitGoal goal) =>
      !goal.isDeleted && goal.hasConflict;

  static bool isVisibleHabitRuleConflict(HabitGoalRuleRevision rule) =>
      !rule.isDeleted && rule.hasConflict;

  /// 判断动态数据集合中的一项是否属于可见冲突。
  static bool isVisibleConflict(Object? item) {
    if (item is TodoItem) return isVisibleTodoConflict(item);
    if (item is TodoGroup) return isVisibleTodoGroupConflict(item);
    if (item is CountdownItem) return isVisibleCountdownConflict(item);
    if (item is HabitGoal) return isVisibleHabitGoalConflict(item);
    if (item is HabitGoalRuleRevision) return isVisibleHabitRuleConflict(item);
    return false;
  }

  /// 判断一个冲突是否属于团队冲突。
  static bool isTeamVisibleConflict(Object? item) {
    if (!isVisibleConflict(item)) return false;
    return hasTeamUuid(teamUuidOf(item));
  }

  /// 获取可见冲突项的团队 UUID；个人冲突返回 null。
  static String? teamUuidOf(Object? item) {
    if (item is TodoItem) return item.teamUuid;
    if (item is TodoGroup) return item.teamUuid;
    if (item is CountdownItem) return item.teamUuid;
    return null;
  }

  static bool hasTeamUuid(String? teamUuid) =>
      teamUuid != null && teamUuid.isNotEmpty;

  /// 计算首页是否需要显示团队冲突角标。
  static bool hasTeamConflict({
    required Iterable<TodoItem> todos,
    required Iterable<TodoGroup> groups,
    required Iterable<CountdownItem> countdowns,
  }) {
    return todos.any(isTeamVisibleConflict) ||
        groups.any(isTeamVisibleConflict) ||
        countdowns.any(isTeamVisibleConflict);
  }

  /// 判断 Todo 模型本身是否为全天任务。
  static bool isAllDayTodo(TodoItem todo) => todo.isAllDay || todo.isAllDayTask;

  /// 判断服务器冲突快照中的 Todo 数据是否为全天任务。
  ///
  /// 服务器历史数据同时存在 start_time/end_time、created_date/due_date
  /// 和 camelCase 字段，因此这里负责兼容字段名；日期语义仍交给
  /// [TodoItem.looksLikeLegacyDateOnlyRange]。
  static bool isAllDayTodoData(Map<String, dynamic> data) {
    if (data['is_all_day'] == 1 ||
        data['is_all_day'] == true ||
        data['isAllDay'] == true) {
      return true;
    }

    final startMs = _parseMillis(data['start_time'] ??
        data['startTime'] ??
        data['created_date'] ??
        data['createdDate']);
    final endMs = _parseMillis(data['end_time'] ??
        data['endTime'] ??
        data['due_date'] ??
        data['dueDate']);
    if (startMs <= 0 || endMs <= startMs) return false;

    final start = DateTime.fromMillisecondsSinceEpoch(startMs).toLocal();
    final end = DateTime.fromMillisecondsSinceEpoch(endMs).toLocal();
    return TodoItem.looksLikeLegacyDateOnlyRange(start, end);
  }

  /// 判断冲突快照是否至少包含一个非全天对等项。
  /// 非日程冲突或没有冲突列表时，沿用原有逻辑视为有效冲突。
  static bool hasVisibleConflictPeer(Map<String, dynamic>? data) {
    if (data == null ||
        (data['type'] != 'schedule' && data['conflict_with'] == null)) {
      return true;
    }

    final peers = data['conflict_with'];
    if (peers is! List) return true;

    return peers.any(
      (peer) =>
          peer is Map && !isAllDayTodoData(Map<String, dynamic>.from(peer)),
    );
  }

  static int _parseMillis(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }
}
