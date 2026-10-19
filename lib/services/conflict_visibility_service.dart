import '../models.dart';
import '../features/habits/models/habit_goal.dart';
import '../features/habits/models/habit_goal_rule.dart';

enum TodoConflictKind { none, localSchedule, syncVersion, unresolved }

/// Todo 冲突的统一分类、可见性、自动清理和规划拦截规则。
///
/// 时间重叠是可重新安排的本地状态；同步版本冲突需要先核对；缺失快照
/// 的冲突保守地作为待核对状态处理。全天待办不产生本地时间冲突。
class ConflictVisibilityService {
  const ConflictVisibilityService._();

  static TodoConflictKind todoConflictKind(TodoItem todo) {
    if (todo.isDeleted || !todo.hasConflict) return TodoConflictKind.none;
    final data = todo.serverVersionData;
    if (data == null || data.isEmpty) return TodoConflictKind.unresolved;
    if (isVersionConflictData(data)) return TodoConflictKind.syncVersion;
    if (isLocalScheduleConflictData(data)) {
      return TodoConflictKind.localSchedule;
    }
    return TodoConflictKind.unresolved;
  }

  static bool blocksTodoPlanning(TodoItem todo) {
    final kind = todoConflictKind(todo);
    return kind == TodoConflictKind.syncVersion ||
        kind == TodoConflictKind.unresolved;
  }

  static bool clearImpossibleTodoScheduleConflict(TodoItem todo) {
    if (!shouldClearImpossibleTodoScheduleConflict(todo)) return false;
    todo.hasConflict = false;
    todo.serverVersionData = null;
    return true;
  }

  static bool isLocalScheduleConflictData(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return false;
    final conflictType = data['conflict_type']?.toString();
    if (conflictType == 'version_conflict' ||
        data['conflict_kind'] == 'version') {
      return false;
    }
    final source = data['source']?.toString();
    return conflictType == 'local_schedule_conflict' ||
        conflictType == 'schedule_conflict' ||
        source == 'local_detector' ||
        source == 'server_detector' ||
        data['type'] == 'schedule';
  }

  static Map<String, dynamic> scheduleConflictData({
    required TodoItem todo,
    required List<Map<String, dynamic>> peers,
    required String source,
  }) {
    final isTeamTodo = hasTeamUuid(todo.teamUuid);
    return {
      'uuid': todo.id,
      'id': todo.id,
      'content': todo.title,
      'team_uuid': todo.teamUuid,
      'schedule_scope': isTeamTodo ? 'team' : 'personal',
      'relation_type': classifyScheduleRelation(todo, peers),
      'conflict_kind': 'logic',
      'conflict_type': 'local_schedule_conflict',
      'source': source,
      'start_time': todo.createdDate ?? todo.createdAt,
      'end_time': todo.dueDate?.millisecondsSinceEpoch,
      'conflict_with': peers,
    };
  }

  static String classifyScheduleRelation(
    TodoItem todo,
    List<Map<String, dynamic>> peers,
  ) {
    final isTeamTodo = hasTeamUuid(todo.teamUuid);
    for (final peer in peers) {
      final peerIsTeam = hasTeamUuid(
        peer['team_uuid']?.toString() ?? peer['teamUuid']?.toString(),
      );
      if (peerIsTeam != isTeamTodo) return 'personal_team';
    }
    return isTeamTodo ? 'team_team' : 'personal_personal';
  }

  /// Unknown non-empty server snapshots retain the historical version-conflict
  /// behavior; empty snapshots are handled as unresolved instead.
  static bool isVersionConflictData(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return false;
    if (data['conflict_type'] == 'version_conflict' ||
        data['conflict_kind'] == 'version') {
      return true;
    }
    return !isLocalScheduleConflictData(data);
  }

  /// Clears schedule markers that cannot describe a real timed overlap.
  /// A missing peer list is retained for review because its source is unknown.
  static bool shouldClearImpossibleTodoScheduleConflict(TodoItem todo) {
    if (!todo.hasConflict ||
        isVersionConflictData(todo.serverVersionData) ||
        !isLocalScheduleConflictData(todo.serverVersionData)) {
      return false;
    }
    if (isAllDayTodo(todo)) return true;
    final peers = todo.serverVersionData?['conflict_with'];
    if (peers is! List) return false;
    return peers.isEmpty ||
        peers.every(
          (peer) =>
              peer is Map && isAllDayTodoData(Map<String, dynamic>.from(peer)),
        );
  }

  /// A Todo conflict belongs in the inbox when it is actionable or needs
  /// review. Date-only schedule conflicts are stale and are normalized away.
  static bool isVisibleTodoConflict(TodoItem todo) {
    switch (todoConflictKind(todo)) {
      case TodoConflictKind.none:
        return false;
      case TodoConflictKind.localSchedule:
        return !isAllDayTodo(todo) &&
            hasVisibleConflictPeer(todo.serverVersionData);
      case TodoConflictKind.syncVersion:
      case TodoConflictKind.unresolved:
        return true;
    }
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

    final startMs = _parseMillis(
      data['start_time'] ??
          data['startTime'] ??
          data['created_date'] ??
          data['createdDate'],
    );
    final endMs = _parseMillis(
      data['end_time'] ??
          data['endTime'] ??
          data['due_date'] ??
          data['dueDate'],
    );
    if (startMs <= 0 || endMs <= startMs) return false;

    final start = DateTime.fromMillisecondsSinceEpoch(startMs).toLocal();
    final end = DateTime.fromMillisecondsSinceEpoch(endMs).toLocal();
    return TodoItem.looksLikeLegacyDateOnlyRange(start, end);
  }

  /// 判断冲突快照是否至少包含一个非全天对等项。
  /// 缺少对等项列表时保留冲突以供核对。
  static bool hasVisibleConflictPeer(Map<String, dynamic>? data) {
    if (data == null || !isLocalScheduleConflictData(data)) return true;

    final peers = data['conflict_with'];
    if (peers is! List) return true;

    return peers.any((peer) {
      if (peer is! Map) return true;
      return !isAllDayTodoData(Map<String, dynamic>.from(peer));
    });
  }

  static int _parseMillis(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }
}
