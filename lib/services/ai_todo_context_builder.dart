import 'package:intl/intl.dart';

import '../models.dart';
import 'chat_storage_service.dart';
import 'pomodoro_service.dart';

class AiTodoContextBuilder {
  static String buildSystemPrompt({
    required String customPrompt,
    required bool promptEnabled,
    required List<Map<String, dynamic>> todos,
    required List<TodoGroup> todoGroups,
    List<CountdownItem> countdowns = const [],
    List<PomodoroTag> pomodoroTags = const [],
    List<TodoPlanBlock> planBlocks = const [],
    DateTime? now,
  }) {
    final nowValue = now ?? DateTime.now();
    final nowText =
        '${DateFormat('yyyy-MM-dd HH:mm').format(nowValue)} (${_formatTimeZone(nowValue)})';
    final todoList = _formatTodos(todos, todoGroups);
    final basePrompt = promptEnabled && customPrompt.trim().isNotEmpty
        ? customPrompt
        : ChatStorageService.defaultPrompt;

    final resolvedBasePrompt =
        basePrompt.replaceAll('{now}', nowText).replaceAll('{todos}', todoList);

    return '''$resolvedBasePrompt

【用户当前分类/文件夹】
${_formatGroups(todoGroups)}

【用户当前倒计时】
${_formatCountdowns(countdowns)}

【用户当前番茄标签】
${_formatPomodoroTags(pomodoroTags)}

【用户当前待办规划】
${_formatPlanBlocks(planBlocks, todos)}

【时间规则】
所有上下文时间均为本地时间，格式为yyyy-MM-dd HH:mm。判断今天、昨天、明天时必须以当前基准时间和括号中的时区为准，不要按UTC重新换算。

【待办管理功能 - 重要规则】
当用户明确要求创建/修改/完成/删除/延期/分类/规划/拆分/合并待办，或新增/修改/删除专注记录，或开始/停止番茄钟，或新增/修改/完成/删除倒计时，或新增/改名/改色/删除番茄标签时，必须在回复末尾附加JSON操作块。
操作已有待办必须使用待办ID；操作已有专注记录必须使用专注记录ID；操作已有倒计时必须使用倒计时ID；操作已有番茄标签必须使用标签ID。不确定时先追问。
JSON操作块必须且只能使用以下协议：
1. 必须用 [ACTION_START] 和 [ACTION_END] 包裹。
2. [ACTION_START] 内必须是合法 JSON 数组；即使只有一个操作，也必须放进数组。
3. 每个操作对象必须包含 "action" 字段。
4. 禁止使用 Markdown 代码块，例如 ```json。
5. 禁止使用 [PLAN_TODOS]、[CREATE_TODO]、[UPDATE_TODO] 等任何旧标记。
6. 禁止只输出 {"todos":[...]}、{"updates":[...]} 等缺少 "action" 字段的对象。
7. 如果同时输出操作块和建议块，顺序必须是：正文 -> [ACTION_START]...[ACTION_END] -> [SUGGEST_START]...[SUGGEST_END]。

唯一合法示例：
[ACTION_START]
[
  {"action":"plan_todos","todos":[{"title":"标题","remark":"备注","startTime":"YYYY-MM-DD HH:mm","dueDate":"YYYY-MM-DD HH:mm","isAllDay":false,"recurrence":"none","groupId":"","reminderMinutes":5}]}
]
[ACTION_END]

支持的动作：

- create_todo: {"action":"create_todo","todos":[{"title":"标题","remark":"备注","startTime":"YYYY-MM-DD HH:mm","dueDate":"YYYY-MM-DD HH:mm","isAllDay":false,"recurrence":"none","groupId":"","reminderMinutes":5}]}
- plan_todos: {"action":"plan_todos","todos":[{"title":"标题","remark":"备注","startTime":"YYYY-MM-DD HH:mm","dueDate":"YYYY-MM-DD HH:mm","isAllDay":false,"recurrence":"none","groupId":"","reminderMinutes":5}]}，用于生成新的计划待办
- create_plan_block: {“action”:”create_plan_block”,”blocks”:[{“todoId”:”已有待办ID”,”title”:”标题快照”,”startTime”:”YYYY-MM-DD HH:mm”,”dueDate”:”YYYY-MM-DD HH:mm”,”durationMinutes”:60,”remark”:”备注”,”reminderMinutes”:5}]}，用于把已有待办安排到具体时间块；用户说”规划今天/明天/本周时间””安排到几点到几点”时优先使用这个动作。重要：规划中提到的每一个已有待办都必须生成对应的plan block，不要只生成一个
- update_todo: {"action":"update_todo","updates":[{"todoId":"ID","title":"新标题","startTime":"...","dueDate":"...","groupId":"...","reminderMinutes":5}]}
- complete_todo: {"action":"complete_todo","updates":[{"todoId":"ID"}]}
- delete_todo: {"action":"delete_todo","updates":[{"todoId":"ID"}]}
- reschedule_todo: {"action":"reschedule_todo","updates":[{"todoId":"ID","startTime":"...","dueDate":"..."}]}
- bulk_reschedule: 同reschedule_todo，批量改期
- categorize_todo: {"action":"categorize_todo","updates":[{"todoId":"ID","groupId":"新分类ID"}]}
- split_todo: {"action":"split_todo","sourceTodoId":"原ID","deleteSource":false,"todos":[...]}
- merge_todos: {"action":"merge_todos","sourceTodoIds":["ID1","ID2"],"deleteSources":false,"todo":{...}}
- create_time_log: {"action":"create_time_log","logs":[{"title":"专注内容","startTime":"YYYY-MM-DD HH:mm","dueDate":"YYYY-MM-DD HH:mm","durationMinutes":60,"remark":"备注","tagUuids":[]}]}
- update_time_log: {"action":"update_time_log","updates":[{"logId":"ID","title":"新标题","startTime":"...","dueDate":"...","durationMinutes":60,"remark":"备注","tagUuids":[]}]}
- delete_time_log: {"action":"delete_time_log","updates":[{"logId":"ID"}]}
- start_pomodoro: {"action":"start_pomodoro","title":"专注内容","todoId":"可选待办ID","durationMinutes":25,"tagUuids":[]}
- stop_pomodoro: {"action":"stop_pomodoro","status":"completed"}
- create_countdown: {"action":"create_countdown","countdowns":[{"title":"事件","dueDate":"YYYY-MM-DD HH:mm"}]}
- update_countdown: {"action":"update_countdown","updates":[{"countdownId":"ID","title":"新标题","dueDate":"YYYY-MM-DD HH:mm"}]}
- complete_countdown: {"action":"complete_countdown","updates":[{"countdownId":"ID"}]}
- delete_countdown: {"action":"delete_countdown","updates":[{"countdownId":"ID"}]}
- create_todo_group: {"action":"create_todo_group","groups":[{"name":"分类名"}]}
- update_todo_group: {"action":"update_todo_group","updates":[{"groupId":"ID","name":"新分类名"}]}
- delete_todo_group: {"action":"delete_todo_group","updates":[{"groupId":"ID"}]}
- create_pomodoro_tag: {"action":"create_pomodoro_tag","tags":[{"name":"标签名","color":"#607D8B"}]}
- update_pomodoro_tag: {"action":"update_pomodoro_tag","updates":[{"tagId":"ID","name":"新名称","color":"#3B82F6"}]}
- delete_pomodoro_tag: {"action":"delete_pomodoro_tag","updates":[{"tagId":"ID"}]}

可组合多种操作：[ACTION_START][{"action":"create_plan_block","blocks":[...]},{"action":"start_pomodoro","title":"专注内容","durationMinutes":25}][ACTION_END]

【后续建议】
每次回复末尾附3-4个简短建议后续问题（≤15字），格式：[SUGGEST_START]["追问1","追问2","追问3"][SUGGEST_END]

【核心规则】
1. 意图判定：创建(提醒我/记一下)、规划(制定计划)、拆分(大任务拆小)、合并(多个合一)、修改(改标题/备注/时间)、完成(标记已做)、删除(移除)、改期(推迟/提前)、整理(分类/移动到文件夹)、新增/修改/删除待办分类或文件夹、记录专注、修改专注记录、删除专注记录、开始/停止番茄钟、管理倒计时、管理番茄标签
2. 文件夹归类：只在语义明显关联时分配groupId，不确定时留空，严禁乱分类
3. 危险操作(删除/完成/合并删源/拆分删源/停止番茄钟/删除专注记录/完成或删除倒计时/删除番茄标签)只在用户明确要求时输出
4. 禁止对已有分类任务重复categorize_todo
5. [ACTION_START]/[ACTION_END]标记和[SUGGEST_START]/[SUGGEST_END]标记必须完整
6. 规划完整性：当用户要求规划时间（今天/明天/本周等），文本中提到的每一个时间段如果对应已有待办，都必须在[ACTION_START]中生成create_plan_block，不能只生成部分。如果文本中规划了5个时间段对应5个已有待办，action中必须有5个blocks''';
  }

  /// 根据用户消息关键词，返回需要注入的上下文片段。无匹配返回 null。
  static String? buildContextInjection({
    required String userMessage,
    required List<CourseItem> courses,
    required List<TimeLogItem> timeLogs,
    List<PomodoroRecord> pomodoroRecords = const [],
    List<TodoPlanBlock> planBlocks = const [],
    List<Map<String, dynamic>> todos = const [],
    required List<ConflictInfo> conflicts,
    required List<Team> teams,
    DateTime? now,
  }) {
    final nowValue = now ?? DateTime.now();
    final sections = <String>[];

    if (_matchesAny(userMessage, _courseKeywords) && courses.isNotEmpty) {
      sections.add(_formatCourses(courses, userMessage, nowValue));
    }
    if (_matchesAny(userMessage, _timeLogKeywords) &&
        (timeLogs.isNotEmpty ||
            pomodoroRecords.isNotEmpty ||
            planBlocks.isNotEmpty)) {
      sections.add(
        _formatFocusRecords(
          timeLogs,
          pomodoroRecords,
          userMessage,
          nowValue,
        ),
      );
      if (planBlocks.isNotEmpty) {
        sections.add(_formatPlanBlocks(planBlocks, todos));
      }
    }
    if (_matchesAny(userMessage, _conflictKeywords) && conflicts.isNotEmpty) {
      sections.add(_formatConflicts(conflicts));
    }
    if (_matchesAny(userMessage, _teamKeywords) && teams.isNotEmpty) {
      sections.add(_formatTeams(teams));
    }

    if (sections.isEmpty) return null;
    return '【相关上下文】\n${sections.join('\n')}';
  }

  static bool _matchesAny(String text, List<String> keywords) {
    return keywords.any((k) => text.contains(k));
  }

  static const _courseKeywords = [
    '课',
    '课程',
    '上课',
    '教室',
    '老师',
    '学期',
    '周几',
    '星期',
    '课表',
    '排课',
    '选课',
    '调课',
  ];
  static const _timeLogKeywords = [
    '专注',
    '番茄',
    '时间',
    '记录',
    '统计',
    '日志',
    '时长',
    '钟',
    '分钟',
    '效率',
    '集中',
  ];
  static const _conflictKeywords = [
    '冲突',
    '同步',
    '版本',
    '覆盖',
    '合并冲突',
    '冲突解决',
  ];
  static const _teamKeywords = [
    '团队',
    '协作',
    '成员',
    '管理员',
    '邀请',
    '队友',
    '小组',
  ];

  static String buildPromptPreview({
    required String customPrompt,
    required bool promptEnabled,
    required List<Map<String, dynamic>> todos,
    required List<TodoGroup> todoGroups,
    DateTime? now,
  }) {
    final nowValue = now ?? DateTime.now();
    final nowText =
        '${DateFormat('yyyy-MM-dd HH:mm').format(nowValue)} (${_formatTimeZone(nowValue)})';
    final basePrompt = promptEnabled && customPrompt.trim().isNotEmpty
        ? customPrompt
        : ChatStorageService.defaultPrompt;
    return basePrompt
        .replaceAll('{now}', nowText)
        .replaceAll('{todos}', _formatTodos(todos, todoGroups));
  }

  static String _formatTodos(
    List<Map<String, dynamic>> todos,
    List<TodoGroup> todoGroups,
  ) {
    if (todos.isEmpty) return '暂无待办';
    return todos.take(80).map((t) {
      final id = t['id'] ?? 'unknown';
      final title = t['title'] ?? '';
      final remark = t['remark'] ?? '';
      final startTime = t['startTime'] ?? '';
      final endTime = t['endTime'] ?? '';
      final isAllDay = t['isAllDay'] ?? false;
      final recurrence = t['recurrence'] ?? 'none';
      final reminderMinutes = t['reminderMinutes'] ?? 5;
      final gid = t['groupId'] ?? '';
      var folderName = '';
      if (gid.toString().isNotEmpty) {
        folderName = todoGroups
            .firstWhere((g) => g.id == gid, orElse: () => TodoGroup(name: ''))
            .name;
      }

      return '- [ID: $id] 标题: $title${remark.toString().isNotEmpty ? ' | 备注: $remark' : ''}${folderName.isNotEmpty ? ' | 分类: $folderName' : ''}${startTime.toString().isNotEmpty ? ' | 开始: $startTime' : ''}${endTime.toString().isNotEmpty ? ' | 结束: $endTime' : ''} | 全天: $isAllDay | 循环: $recurrence | 提醒: 提前$reminderMinutes分钟';
    }).join('\n');
  }

  static String _formatGroups(List<TodoGroup> todoGroups) {
    if (todoGroups.isEmpty) return '暂无分类';
    return todoGroups.map((g) => '- 名称: ${g.name} | ID: ${g.id}').join('\n');
  }

  static String _formatCountdowns(List<CountdownItem> countdowns) {
    final active = countdowns.where((c) => !c.isDeleted).take(40).toList();
    if (active.isEmpty) return '暂无倒计时';
    return active.map((c) {
      final target = DateFormat('yyyy-MM-dd HH:mm').format(c.targetDate);
      final status = c.isCompleted ? '已达成' : '进行中';
      return '- [ID: ${c.id}] 标题: ${c.title} | 目标: $target | 状态: $status';
    }).join('\n');
  }

  static String _formatPomodoroTags(List<PomodoroTag> tags) {
    final active = tags.where((t) => !t.isDeleted).take(40).toList();
    if (active.isEmpty) return '暂无番茄标签';
    return active
        .map((t) => '- [ID: ${t.uuid}] 名称: ${t.name} | 颜色: ${t.color}')
        .join('\n');
  }

  static String _formatPlanBlocks(
    List<TodoPlanBlock> blocks,
    List<Map<String, dynamic>> todos,
  ) {
    final active = blocks.where((b) => !b.isDeleted).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    if (active.isEmpty) return '暂无规划';

    String todoTitle(String id) {
      final match = todos.where((t) => t['id']?.toString() == id).toList();
      if (match.isEmpty) return id;
      final title = match.first['title']?.toString();
      return title == null || title.isEmpty ? id : title;
    }

    return active.take(60).map((b) {
      final start = DateFormat('yyyy-MM-dd HH:mm')
          .format(DateTime.fromMillisecondsSinceEpoch(b.startTime));
      final end = DateFormat('yyyy-MM-dd HH:mm')
          .format(DateTime.fromMillisecondsSinceEpoch(b.endTime));
      final actualMinutes = b.actualFocusSeconds ~/ 60;
      return '- [ID: ${b.id}] 待办ID: ${b.todoId} | 标题: ${b.titleSnapshot ?? todoTitle(b.todoId)} | 时间: $start-$end | 计划: ${b.plannedMinutes}分钟 | 实际专注: $actualMinutes分钟 | 状态: ${b.status.name} | 提醒: 提前${b.reminderMinutes}分钟';
    }).join('\n');
  }

  static String _formatCourses(
    List<CourseItem> courses,
    String userMessage,
    DateTime now,
  ) {
    if (courses.isEmpty) return '课程表: 暂无';
    final activeCourses = courses.where((c) => !c.isDeleted).toList()
      ..sort((a, b) {
        final dateCompare = a.date.compareTo(b.date);
        if (dateCompare != 0) return dateCompare;
        return a.startTime.compareTo(b.startTime);
      });
    if (activeCourses.isEmpty) return '课程表: 暂无';

    final allDates = activeCourses
        .map((c) => DateTime.tryParse(c.date))
        .whereType<DateTime>()
        .toList();
    final availableRange = allDates.isEmpty
        ? null
        : _DateRange(
            label: '全部可用课程日期',
            start: allDates.first,
            end: allDates.last.add(const Duration(days: 1)),
          );
    final period = _resolveCoursePeriod(userMessage, now);
    final scopedCourses = _selectCoursesForPeriod(activeCourses, period, now);
    final lines = scopedCourses
        .take(30)
        .map((c) =>
            '- ${c.date} ${c.formattedStartTime}-${c.formattedEndTime} ${c.courseName} | ${c.roomName} | ${c.teacherName}')
        .join('\n');
    final header = period == null
        ? '课程表（当前时间: ${_formatDateTime(now)}，今日起最近30节）'
        : '课程表（当前时间: ${_formatDateTime(now)}，${period.label}范围: ${_formatDate(period.start)} 至 ${_formatDate(period.end.subtract(const Duration(days: 1)))})';
    final rangeLine = availableRange == null
        ? ''
        : '\n${availableRange.label}: ${_formatDate(availableRange.start)} 至 ${_formatDate(availableRange.end.subtract(const Duration(days: 1)))}';
    return '$header$rangeLine\n${lines.isEmpty ? '暂无匹配课程' : lines}';
  }

  static List<CourseItem> _selectCoursesForPeriod(
    List<CourseItem> courses,
    _DateRange? period,
    DateTime now,
  ) {
    if (period != null) {
      return courses.where((c) {
        final date = DateTime.tryParse(c.date);
        if (date == null) return false;
        final day = DateTime(date.year, date.month, date.day);
        return !day.isBefore(period.start) && day.isBefore(period.end);
      }).toList();
    }

    final today = DateTime(now.year, now.month, now.day);
    return courses.where((c) {
      final date = DateTime.tryParse(c.date);
      if (date == null) return false;
      final day = DateTime(date.year, date.month, date.day);
      return !day.isBefore(today);
    }).toList();
  }

  static _DateRange? _resolveCoursePeriod(String text, DateTime now) {
    final todayStart = DateTime(now.year, now.month, now.day);
    if (text.contains('今天') || text.contains('今日')) {
      return _DateRange(
        label: '今日',
        start: todayStart,
        end: todayStart.add(const Duration(days: 1)),
      );
    }
    if (text.contains('明天') || text.contains('明日')) {
      final start = todayStart.add(const Duration(days: 1));
      return _DateRange(
        label: '明日',
        start: start,
        end: start.add(const Duration(days: 1)),
      );
    }
    if (text.contains('后天') || text.contains('后日')) {
      final start = todayStart.add(const Duration(days: 2));
      return _DateRange(
        label: '后日',
        start: start,
        end: start.add(const Duration(days: 1)),
      );
    }
    if (text.contains('下周')) {
      final thisWeekStart =
          todayStart.subtract(Duration(days: now.weekday - 1));
      final start = thisWeekStart.add(const Duration(days: 7));
      return _DateRange(
        label: '下周',
        start: start,
        end: start.add(const Duration(days: 7)),
      );
    }
    if (text.contains('本周') || text.contains('这周')) {
      final start = todayStart.subtract(Duration(days: now.weekday - 1));
      return _DateRange(
        label: '本周',
        start: start,
        end: start.add(const Duration(days: 7)),
      );
    }
    if (text.contains('本月') || text.contains('这个月')) {
      return _DateRange(
        label: '本月',
        start: DateTime(now.year, now.month),
        end: DateTime(now.year, now.month + 1),
      );
    }
    return null;
  }

  static String _formatFocusRecords(
    List<TimeLogItem> timeLogs,
    List<PomodoroRecord> pomodoroRecords,
    String userMessage,
    DateTime now,
  ) {
    final activeLogs = timeLogs.where((t) => !t.isDeleted).toList();
    final activePomodoros = pomodoroRecords.where((p) => !p.isDeleted).toList();
    if (activeLogs.isEmpty && activePomodoros.isEmpty) return '专注记录: 暂无';
    final period = _resolveTimeLogPeriod(userMessage, now);
    final records = <_FocusRecord>[
      ...activeLogs.map(_FocusRecord.fromTimeLog),
      ...activePomodoros.map(_FocusRecord.fromPomodoro),
    ]..sort((a, b) => b.startMs.compareTo(a.startMs));
    final scopedRecords = period == null
        ? records.take(30).toList()
        : records.where((r) => _focusOverlapsPeriod(r, period)).toList();

    if (period != null) {
      final totalMinutes = scopedRecords
          .map((r) => _focusOverlapMinutes(r, period))
          .fold<int>(0, (sum, minutes) => sum + minutes);
      final timeLogMinutes = scopedRecords
          .where((r) => r.source == '补录')
          .map((r) => _focusOverlapMinutes(r, period))
          .fold<int>(0, (sum, minutes) => sum + minutes);
      final pomodoroMinutes = scopedRecords
          .where((r) => r.source == '番茄钟')
          .map((r) => _focusOverlapMinutes(r, period))
          .fold<int>(0, (sum, minutes) => sum + minutes);
      final lines = scopedRecords.take(30).map((r) {
        final start = _formatEpochMillis(r.startMs);
        final end = _formatEpochMillis(r.endMs);
        final minutes = _focusOverlapMinutes(r, period);
        return '- [${r.source} ID: ${r.id}] $start-$end ${r.title} | 本时段计入${_formatDuration(minutes)}${r.status != null ? ' | 状态: ${r.status}' : ''}';
      }).join('\n');
      return '''专注记录:
${period.label}范围: ${_formatDateTime(period.start)} 至 ${_formatDateTime(period.end)}
${period.label}合计: ${_formatDuration(totalMinutes)}
其中补录: ${_formatDuration(timeLogMinutes)}，番茄钟: ${_formatDuration(pomodoroMinutes)}
${period.label}记录:
${lines.isEmpty ? '暂无' : lines}''';
    }

    final lines = scopedRecords.map((r) {
      final start = _formatEpochMillis(r.startMs);
      final end = _formatEpochMillis(r.endMs);
      return '- [${r.source} ID: ${r.id}] $start-$end ${r.title} | ${_formatDuration(r.minutes)}${r.status != null ? ' | 状态: ${r.status}' : ''}';
    }).join('\n');
    return '专注记录（最近30条，按开始时间倒序）:\n$lines';
  }

  static String _formatConflicts(List<ConflictInfo> conflicts) {
    if (conflicts.isEmpty) return '冲突信息: 暂无';
    final lines = conflicts.take(20).map((c) {
      final title = c.item['title'] ?? c.item['content'] ?? c.item['id'] ?? '';
      final other = c.conflictWith['title'] ??
          c.conflictWith['content'] ??
          c.conflictWith['id'] ??
          '';
      return '- ${c.type}: $title <-> $other';
    }).join('\n');
    return '冲突信息:\n$lines';
  }

  static String _formatTeams(List<Team> teams) {
    if (teams.isEmpty) return '团队协作: 暂无';
    final lines = teams
        .take(20)
        .map((t) => '- ${t.name} | ID: ${t.uuid} | 成员: ${t.memberCount}')
        .join('\n');
    return '团队协作:\n$lines';
  }

  static String _formatTimeZone(DateTime value) {
    final offset = value.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final absOffset = offset.abs();
    final hours = absOffset.inHours.toString().padLeft(2, '0');
    final minutes = (absOffset.inMinutes % 60).toString().padLeft(2, '0');
    return 'UTC$sign$hours:$minutes ${value.timeZoneName}';
  }

  static _TimeLogPeriod? _resolveTimeLogPeriod(String text, DateTime now) {
    final todayStart = DateTime(now.year, now.month, now.day);
    if (text.contains('今天') || text.contains('今日')) {
      return _TimeLogPeriod(
        label: '今日',
        start: todayStart,
        end: todayStart.add(const Duration(days: 1)),
      );
    }
    if (text.contains('昨天') || text.contains('昨日')) {
      final start = todayStart.subtract(const Duration(days: 1));
      return _TimeLogPeriod(
        label: '昨日',
        start: start,
        end: todayStart,
      );
    }
    if (text.contains('本周') || text.contains('这周')) {
      final start = todayStart.subtract(Duration(days: now.weekday - 1));
      return _TimeLogPeriod(
        label: '本周',
        start: start,
        end: start.add(const Duration(days: 7)),
      );
    }
    if (text.contains('本月') || text.contains('这个月')) {
      final start = DateTime(now.year, now.month);
      return _TimeLogPeriod(
        label: '本月',
        start: start,
        end: DateTime(now.year, now.month + 1),
      );
    }
    return null;
  }

  static bool _focusOverlapsPeriod(_FocusRecord record, _TimeLogPeriod period) {
    return record.endMs > period.start.millisecondsSinceEpoch &&
        record.startMs < period.end.millisecondsSinceEpoch;
  }

  static int _focusOverlapMinutes(_FocusRecord record, _TimeLogPeriod period) {
    final start = record.startMs > period.start.millisecondsSinceEpoch
        ? record.startMs
        : period.start.millisecondsSinceEpoch;
    final end = record.endMs < period.end.millisecondsSinceEpoch
        ? record.endMs
        : period.end.millisecondsSinceEpoch;
    if (end <= start) return 0;
    return ((end - start) / 60000).round();
  }

  static String _formatEpochMillis(int value) {
    return _formatDateTime(DateTime.fromMillisecondsSinceEpoch(value));
  }

  static String _formatDateTime(DateTime value) {
    return DateFormat('yyyy-MM-dd HH:mm').format(value.toLocal());
  }

  static String _formatDate(DateTime value) {
    return DateFormat('yyyy-MM-dd').format(value.toLocal());
  }

  static String _formatDuration(int minutes) {
    if (minutes <= 0) return '0分钟';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (hours == 0) return '$minutes分钟';
    if (rest == 0) return '$hours小时';
    return '$hours小时$rest分钟';
  }
}

class _TimeLogPeriod {
  const _TimeLogPeriod({
    required this.label,
    required this.start,
    required this.end,
  });

  final String label;
  final DateTime start;
  final DateTime end;
}

class _FocusRecord {
  const _FocusRecord({
    required this.id,
    required this.title,
    required this.source,
    required this.startMs,
    required this.endMs,
    this.status,
  });

  factory _FocusRecord.fromTimeLog(TimeLogItem log) {
    return _FocusRecord(
      id: log.id,
      title: log.title,
      source: '补录',
      startMs: log.startTime,
      endMs: log.endTime,
    );
  }

  factory _FocusRecord.fromPomodoro(PomodoroRecord record) {
    final endMs =
        record.endTime ?? record.startTime + record.effectiveDuration * 1000;
    return _FocusRecord(
      id: record.uuid,
      title: record.todoTitle?.isNotEmpty == true ? record.todoTitle! : '番茄钟',
      source: '番茄钟',
      startMs: record.startTime,
      endMs: endMs,
      status: record.isCompleted ? '已完成' : '已中断',
    );
  }

  final String id;
  final String title;
  final String source;
  final int startMs;
  final int endMs;
  final String? status;

  int get minutes => ((endMs - startMs) / 60000).round();
}

class _DateRange {
  const _DateRange({
    required this.label,
    required this.start,
    required this.end,
  });

  final String label;
  final DateTime start;
  final DateTime end;
}
