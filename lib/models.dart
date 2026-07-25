import 'dart:math'; // test
import 'package:flutter/cupertino.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';

import 'utils/analysis_image_cleanup.dart';

// ==========================================
// 0. 时间轴相关 (Timeline)
// ==========================================

enum TimelineEventType {
  pomodoroStart,
  pomodoroEnd,
  todoCreated,
  todoEdited,
  todoCompleted,
  countdownCreated,
  countdownEdited,
  countdownCompleted,
  courseStart,
  courseEnd,
  searchQuery,
  timeLog,
  planBlock,
}

class TimelineEvent {
  final String id;
  final DateTime timestamp;
  final TimelineEventType type;
  final String title;
  final String? subtitle;
  final Map<String, dynamic>? extraData;

  TimelineEvent({
    required this.id,
    required this.timestamp,
    required this.type,
    required this.title,
    this.subtitle,
    this.extraData,
  });

  factory TimelineEvent.fromMap(Map<String, dynamic> map) {
    return TimelineEvent(
      id: map['id'] ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
      type: TimelineEventType.values[map['type']],
      title: map['title'] ?? '',
      subtitle: map['subtitle'],
      extraData: map['extraData'],
    );
  }
}

// ==========================================
// 1. 测验相关 (完整保留原有逻辑)
// ==========================================

class Question {
  int num1;
  int num2;
  String operatorSymbol;
  int correctAnswer;
  int? userAnswer;
  bool isAnswered;

  Question({
    required this.num1,
    required this.num2,
    required this.operatorSymbol,
    required this.correctAnswer,
    this.userAnswer,
    this.isAnswered = false,
  });

  bool checkAnswer() {
    return isAnswered && userAnswer == correctAnswer;
  }

  @override
  String toString() {
    String opStr = operatorSymbol;
    if (opStr == '*') opStr = '×';
    if (opStr == '/') opStr = '÷';

    String result = "$num1 $opStr $num2 = ${userAnswer ?? '?'}";
    if (isAnswered) {
      result +=
          (userAnswer == correctAnswer) ? " (正确)" : " (错误, 正解: $correctAnswer)";
    } else {
      result += " (未作答)";
    }
    return result;
  }
}

class QuestionGenerator {
  static List<Question> generate(int count, Map<String, dynamic> settings) {
    List<Question> questions = [];
    Random rng = Random();

    // 从设置中读取参数
    List<String> operators = List<String>.from(settings['operators'] ?? ['+']);
    if (operators.isEmpty) operators = ['+']; // 防止为空

    int minN1 = settings['min_num1'] ?? 0;
    int maxN1 = settings['max_num1'] ?? 50;
    int minN2 = settings['min_num2'] ?? 0;
    int maxN2 = settings['max_num2'] ?? 50;
    int maxRes = settings['max_result'] ?? 100;

    int attempts = 0;
    while (questions.length < count && attempts < count * 100) {
      attempts++;
      String op = operators[rng.nextInt(operators.length)];
      int n1 = minN1 + rng.nextInt(maxN1 - minN1 + 1);
      int n2 = minN2 + rng.nextInt(maxN2 - minN2 + 1);
      int ans = 0;
      bool isValid = false;

      if (op == '+') {
        ans = n1 + n2;
        if (ans <= maxRes) isValid = true;
      } else if (op == '-') {
        if (n1 >= n2) {
          ans = n1 - n2;
          isValid = true;
        }
      } else if (op == '*') {
        ans = n1 * n2;
        if (ans <= maxRes) isValid = true;
      } else if (op == '/') {
        if (n2 != 0 && n1 % n2 == 0) {
          ans = n1 ~/ n2;
          isValid = true;
        }
      }

      if (isValid) {
        questions.add(Question(
            num1: n1, num2: n2, operatorSymbol: op, correctAnswer: ans));
      }
    }
    return questions;
  }
}

// ==========================================
// 🚀 2. 效率功能：支持 Delta Sync 的数据模型
// ==========================================

enum RecurrenceType {
  none,
  daily,
  customDays,
  weekly,
  monthly,
  yearly,
  weekdays
}

/// 用户可理解的待办时间语义。
///
/// [unscheduled] 没有完成日期；[dateOnly] 只要求在某天内完成；
/// [deadline] 有明确的截止时刻。实际执行时段由 [TodoPlanBlock] 表达，
/// 不属于待办本体的时间模式。
enum TodoTimeMode { unscheduled, dateOnly, deadline }

/// 文本解析阶段保留的时间含义，避免通过“00:00”反推用户输入类型。
enum ParsedTimeSemantics { unscheduled, dateOnly, deadline, range }

class TodoItem {
  String id; // 核心：全局唯一 UUID
  String title;
  bool isDone;
  bool isDeleted; // 核心：逻辑删除标记
  int version; // 核心：并发版本号
  int updatedAt; // 核心：最后修改时间戳 (毫秒)
  int createdAt; // 🚀 真正的创建时间戳 (物理生成时间，毫秒)
  int? createdDate; // 🚀 真正的开始时间戳 (业务逻辑设定的开始日期，毫秒)

  RecurrenceType recurrence;
  String? recurrenceSeriesId;
  int? customIntervalDays;
  DateTime? recurrenceEndDate;
  DateTime? dueDate;
  String? remark; // 📝 备注
  String? imagePath; // 📸 本地图片路径（仅本机，不参与多设备同步）
  String? originalText; // 📄 原始分析文本
  String? groupId; // 📁 所属分组 ID (null 表示未分组)
  int? reminderMinutes; // 🚀 新增：提前几分钟提醒
  String? creatorId;
  String? teamUuid;
  String? creatorName;
  String? teamName;
  int collabType; // 🚀 0: 所有人共同协作, 1: 每个人独立完成
  bool hasConflict;
  Map<String, dynamic>? serverVersionData;
  bool isAllDay;
  String? categoryId;

  TodoItem({
    String? id,
    required this.title,
    this.isDone = false,
    this.isDeleted = false,
    this.version = 1,
    int? updatedAt,
    int? createdAt,
    this.createdDate, // 🚀 新增入参
    this.recurrence = RecurrenceType.none,
    this.recurrenceSeriesId,
    this.customIntervalDays,
    this.recurrenceEndDate,
    this.dueDate,
    this.remark,
    this.imagePath,
    this.originalText,
    this.groupId,
    this.reminderMinutes,
    this.teamUuid,
    this.creatorId,
    this.creatorName,
    this.teamName,
    this.collabType = 0,
    this.hasConflict = false,
    this.serverVersionData,
    this.isAllDay = false,
    this.categoryId,
  })  : id = id ?? const Uuid().v4(),
        updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch,
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  // 🚀 核心方法：每次本地对任务的修改，都必须调用此方法！
  void markAsChanged() {
    version++;
    updatedAt = DateTime.now().millisecondsSinceEpoch;
  }

  DateTime get effectiveStartTime => DateTime.fromMillisecondsSinceEpoch(
        createdDate ?? createdAt,
        isUtc: true,
      ).toLocal();

  TodoTimeMode get timeMode {
    final end = dueDate?.toLocal();
    if (end == null) return TodoTimeMode.unscheduled;
    if (isAllDay || looksLikeLegacyDateOnlyRange(effectiveStartTime, end)) {
      return TodoTimeMode.dateOnly;
    }
    return TodoTimeMode.deadline;
  }

  bool get isDateOnly => timeMode == TodoTimeMode.dateOnly;

  /// 旧版客户端曾允许待办直接保存“开始—结束”执行时间段。
  ///
  /// 新版不再为新待办创建这种时间段，但编辑历史记录时必须识别并原样保留，
  /// 否则一次普通编辑就会把 [createdDate] 覆盖成 [dueDate]。
  bool get hasLegacyTimeRange {
    final end = dueDate?.toLocal();
    if (createdDate == null || end == null || isDateOnly) return false;
    return end.isAfter(effectiveStartTime);
  }

  /// 是否包含新版待办不再主动创建、但编辑时仍需保留的旧版时间信息。
  /// 包括“只有开始时间”和“开始—结束时间段”两种历史格式。
  bool get hasLegacyTiming =>
      createdDate != null &&
      !isDateOnly &&
      (dueDate == null || hasLegacyTimeRange);

  /// 兼容旧代码和旧插件命名；新业务代码优先使用 [isDateOnly]。
  bool get isAllDayTask => isDateOnly;

  /// 兼容早期未正确写入 `is_all_day`、只保存 00:00/23:59 的记录。
  ///
  /// 不再使用“持续超过 23.5 小时”作为判断条件，避免把真正的跨日
  /// 截止任务错误归为日期待办。
  static bool looksLikeLegacyDateOnlyRange(DateTime start, DateTime end) {
    if (!end.isAfter(start)) return false;
    final startsAtMidnight = start.hour == 0 &&
        start.minute == 0 &&
        start.second == 0 &&
        start.millisecond == 0;
    if (!startsAtMidnight) return false;

    final endsAtEndOfDay = end.hour == 23 && end.minute == 59;
    final endsAtLaterMidnight = end.hour == 0 &&
        end.minute == 0 &&
        end.second == 0 &&
        end.millisecond == 0;
    return endsAtEndOfDay || endsAtLaterMidnight;
  }

  /// 统一新建和重新编辑待办时的时间写入方式。
  ///
  /// - 未安排：不写业务开始时间和截止时间；
  /// - 日期待办：保存目标日 00:00 到 23:59，兼容旧客户端；
  /// - 截止待办：开始锚点与截止点相同，避免被旧逻辑当成执行时段。
  ///
  /// 旧数据不会在读取时调用此方法，因此历史时间段仍可按原值保留。
  static ({DateTime? start, DateTime? due}) normalizeTimeForWrite({
    DateTime? selectedDate,
    DateTime? dueDate,
    required bool isDateOnly,
  }) {
    if (isDateOnly) {
      final source = selectedDate ?? dueDate;
      if (source == null) return (start: null, due: null);
      return (
        start: DateTime(source.year, source.month, source.day),
        due: DateTime(source.year, source.month, source.day, 23, 59),
      );
    }
    if (dueDate == null) return (start: null, due: null);
    return (start: dueDate, due: dueDate);
  }

  /// 编辑待办时的时间写入方式。
  ///
  /// 只有已经存在的旧版时间信息可以走 [preserveExistingTiming]；新建待办
  /// 仍应使用 [normalizeTimeForWrite]，将时间表达为未安排、日期或截止时刻。
  static ({DateTime? start, DateTime? due}) normalizeTimeForEdit({
    required DateTime selectedDate,
    DateTime? dueDate,
    required bool isDateOnly,
    required bool preserveExistingTiming,
  }) {
    if (preserveExistingTiming && !isDateOnly) {
      return (start: selectedDate, due: dueDate);
    }
    return normalizeTimeForWrite(
      selectedDate: selectedDate,
      dueDate: dueDate,
      isDateOnly: isDateOnly,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'uuid': id,
        'content': title,
        'is_completed': isDone ? 1 : 0,
        'is_deleted': isDeleted ? 1 : 0,
        'version': version,
        'updated_at': updatedAt, // UTC 毫秒时间戳
        'created_at': createdAt, // UTC 毫秒时间戳（物理创建时间，不可变）
        'created_date': createdDate, // UTC 毫秒时间戳（任务开始时间，可为 null）
        'due_date': dueDate
            ?.toUtc()
            .millisecondsSinceEpoch, // UTC 毫秒时间戳（任务截止时间，可为 null）
        'recurrence': recurrence.index,
        'recurrence_series_id': recurrenceSeriesId,
        'recurrenceSeriesId': recurrenceSeriesId,
        // 循环间隔：同时输出两种键名兼容后端列名(custom_interval_days)和本地存储名(customIntervalDays)
        'customIntervalDays': customIntervalDays,
        'custom_interval_days': customIntervalDays,
        // 循环结束日：同时输出两种键名
        'recurrenceEndDate': recurrenceEndDate?.toUtc().millisecondsSinceEpoch,
        'recurrence_end_date':
            recurrenceEndDate?.toUtc().millisecondsSinceEpoch,
        'remark': remark, // 📝 备注（可为 null）
        'image_path': imagePath, // 📸 图片路径
        'original_text': originalText, // 📄 原始分析文本
        'group_id': groupId, // 📁 分组 ID
        'reminder_minutes': reminderMinutes, // 🚀 提醒提前量
        'team_uuid': teamUuid, // 👥 团队 ID
        'creator_id': creatorId,
        'creator_name': creatorName,
        'team_name': teamName,
        'collab_type': collabType,
        'is_all_day': isAllDay ? 1 : 0,
        'category_id': categoryId,
        'has_conflict': hasConflict ? 1 : 0,
        'conflict_data':
            serverVersionData != null ? jsonEncode(serverVersionData) : null,
      };

  factory TodoItem.fromSql(Map<String, dynamic> map) => TodoItem.fromJson(map);

  factory TodoItem.fromJson(Map<String, dynamic> json) {
    // 优先读取后端的 uuid 字段，如果没有再尝试 id 字段，最后才兜底生成
    String parsedId =
        json['uuid']?.toString() ?? json['id']?.toString() ?? const Uuid().v4();
    if (!parsedId.contains('-')) {
      parsedId = const Uuid().v4(); // 如果旧数据是自增ID，强制转UUID
    }

    return TodoItem(
      id: parsedId,
      title: json['content'] ?? json['title'] ?? '',
      isDone: json['is_completed'] == 1 ||
          json['is_completed'] == true ||
          json['isDone'] == true,
      isDeleted: json['is_deleted'] == 1 ||
          json['is_deleted'] == true ||
          json['isDeleted'] == true,
      version: json['version'] ?? 1,
      updatedAt: _parseTimestamp(json['updated_at'] ?? json['lastUpdated']),
      createdAt: _parseTimestamp(json['created_at'] ?? json['createdAt']),

      // created_date = 任务开始时间（业务字段），与 created_at（物理创建时间）严格区分
      createdDate: (json['created_date'] != null)
          ? _parseTimestamp(json['created_date'])
          : ((json['createdDate'] != null)
              ? _parseTimestamp(json['createdDate'])
              : null),

      recurrence: RecurrenceType
          .values[int.tryParse(json['recurrence']?.toString() ?? '0') ?? 0],
      recurrenceSeriesId: _emptyStringToNull(
        (json['recurrence_series_id'] ?? json['recurrenceSeriesId'])
            ?.toString(),
      ),
      // 兼容两种字段名：后端列名 custom_interval_days 和本地存储名 customIntervalDays
      customIntervalDays: int.tryParse(json['customIntervalDays']?.toString() ??
          json['custom_interval_days']?.toString() ??
          ''),
      // 兼容两种字段名：后端列名 recurrence_end_date 和本地存储名 recurrenceEndDate
      recurrenceEndDate: _parseDateField(
          json['recurrenceEndDate'] ?? json['recurrence_end_date']),
      // due_date = 任务截止时间
      dueDate: _parseDateField(json['due_date']),
      // 📝 备注
      remark: json['remark'] as String?,
      // 📸 图片路径
      imagePath: (json['image_path'] ?? json['imagePath']) as String?,
      // 📄 原始分析文本
      originalText: (json['original_text'] ?? json['originalText']) as String?,
      // 📁 分组 ID
      groupId: (json['group_id'] ?? json['groupId']) as String?,
      // 🚀 提醒提前量
      reminderMinutes:
          json['reminder_minutes'] as int? ?? json['reminderMinutes'] as int?,
      // 👥 团队 ID
      teamUuid: json['team_uuid'] ?? json['teamUuid'],
      creatorId: json['creator_id'] ?? json['creatorId'],
      creatorName: json['creator_name'] ?? json['creatorName'],
      teamName: json['team_name'] ?? json['teamName'],
      collabType: json['collab_type'] ?? json['collabType'] ?? 0,
      isAllDay: json['is_all_day'] == 1 || json['isAllDay'] == true,
      categoryId:
          json['category_id']?.toString() ?? json['categoryId']?.toString(),
      hasConflict: json['has_conflict'] == 1 || json['has_conflict'] == true,
      serverVersionData: json['conflict_data'] != null
          ? (json['conflict_data'] is String
              ? jsonDecode(json['conflict_data'])
              : json['conflict_data'])
          : null,
    );
  }

  /// 🚀 静态方法：清理过期的图片分析文件（7天以上）
  static Future<void> cleanupAnalysisImages() async {
    await cleanupAnalysisImagesImpl();
  }
}

class CountdownItem {
  String id;
  String title;
  DateTime targetDate;
  bool isDeleted;
  bool isCompleted;
  int version;
  int updatedAt;
  int createdAt;
  String? teamUuid;
  String? teamName;
  String? creatorId;
  String? creatorName;
  bool hasConflict;
  Map<String, dynamic>? conflictData;

  CountdownItem({
    String? id,
    required this.title,
    required this.targetDate,
    this.isDeleted = false,
    this.isCompleted = false,
    this.version = 1,
    int? updatedAt,
    int? createdAt,
    this.teamUuid,
    this.teamName,
    this.creatorId,
    this.creatorName,
    this.hasConflict = false,
    this.conflictData,
  })  : id = id ?? const Uuid().v4(),
        updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch,
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  // 🚀 核心方法：每次本地对倒计时的修改，都必须调用此方法！
  void markAsChanged() {
    version++;
    updatedAt = DateTime.now().millisecondsSinceEpoch;
  }

  Map<String, dynamic> toJson() => {
        'id': id, // 兼容本地读取
        'uuid': id, // 对齐后端数据库主键
        'title': title,
        'target_time': targetDate.millisecondsSinceEpoch, // UTC 毫秒时间戳
        'is_deleted': isDeleted ? 1 : 0,
        'is_completed': isCompleted ? 1 : 0,
        'version': version,
        'updated_at': updatedAt, // UTC 毫秒时间戳
        'created_at': createdAt, // UTC 毫秒时间戳
        'team_uuid': teamUuid,
        'team_name': teamName,
        'creator_id': creatorId,
        'creator_name': creatorName,
        'has_conflict': hasConflict ? 1 : 0,
        'conflict_data': conflictData != null ? jsonEncode(conflictData) : null,
      };

  factory CountdownItem.fromSql(Map<String, dynamic> map) =>
      CountdownItem.fromJson(map);

  factory CountdownItem.fromJson(Map<String, dynamic> json) {
    // 优先读取后端的 uuid 字段
    String parsedId =
        json['uuid']?.toString() ?? json['id']?.toString() ?? const Uuid().v4();
    if (!parsedId.contains('-')) parsedId = const Uuid().v4();

    return CountdownItem(
      id: parsedId,
      title: json['title'] ?? '',
      // 🚀 修复：正确解析 targetDate（可能是毫秒时间戳或 ISO 字符串）
      // 兼容所有字段名：target_time(客户端), target_date(新服务器DB列名), targetDate(旧格式)
      targetDate: _parseDateField(json['target_time'] ??
              json['target_date'] ??
              json['targetDate']) ??
          DateTime.now().add(const Duration(days: 1)),
      isDeleted: json['is_deleted'] == 1 ||
          json['is_deleted'] == true ||
          json['isDeleted'] == true,
      isCompleted: json['is_completed'] == 1 ||
          json['is_completed'] == true ||
          json['isCompleted'] == true,
      version: json['version'] ?? 1,
      updatedAt: _parseTimestamp(json['updated_at'] ?? json['lastUpdated']),
      createdAt: _parseTimestamp(json['created_at'] ?? json['createdAt']),
      teamUuid: json['team_uuid'] ?? json['teamUuid'],
      teamName: json['team_name'] ?? json['teamName'],
      creatorId: json['creator_id'] ?? json['creatorId'],
      creatorName: json['creator_name'] ?? json['creatorName'],
      hasConflict: json['has_conflict'] == 1 || json['has_conflict'] == true,
      conflictData: json['conflict_data'] != null
          ? (json['conflict_data'] is String
              ? jsonDecode(json['conflict_data'])
              : json['conflict_data'])
          : null,
    );
  }
}

// ==========================================
// Todo Group Model
// ==========================================

class TodoGroup {
  String id;
  String name;
  bool isExpanded;
  bool isDeleted;
  int version;
  int updatedAt;
  int createdAt;
  String? teamUuid;
  String? teamName;
  String? creatorId;
  String? creatorName;
  bool hasConflict;
  Map<String, dynamic>? conflictData;

  TodoGroup({
    String? id,
    required this.name,
    this.isExpanded = false,
    this.isDeleted = false,
    this.version = 1,
    int? updatedAt,
    int? createdAt,
    this.teamUuid,
    this.teamName,
    this.creatorId,
    this.creatorName,
    this.hasConflict = false,
    this.conflictData,
  })  : id = id ?? const Uuid().v4(),
        updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch,
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  void markAsChanged() {
    version++;
    updatedAt = DateTime.now().millisecondsSinceEpoch;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'uuid': id,
        'name': name,
        'is_expanded': isExpanded ? 1 : 0,
        'is_deleted': isDeleted ? 1 : 0,
        'version': version,
        'updated_at': updatedAt,
        'created_at': createdAt,
        'team_uuid': teamUuid,
        'team_name': teamName,
        'creator_id': creatorId,
        'creator_name': creatorName,
        'has_conflict': hasConflict ? 1 : 0,
        'conflict_data': conflictData != null ? jsonEncode(conflictData) : null,
      };

  factory TodoGroup.fromSql(Map<String, dynamic> map) =>
      TodoGroup.fromJson(map);

  factory TodoGroup.fromJson(Map<String, dynamic> json) {
    String parsedId =
        json['uuid']?.toString() ?? json['id']?.toString() ?? const Uuid().v4();
    return TodoGroup(
      id: parsedId,
      name: json['name']?.toString() ?? '未命名分组',
      isExpanded: json['is_expanded'] == 1 || json['is_expanded'] == true,
      isDeleted: json['is_deleted'] == 1 || json['is_deleted'] == true,
      version: json['version'] as int? ?? 1,
      updatedAt: _parseTimestamp(json['updated_at'] ?? json['updatedAt']),
      createdAt: _parseTimestamp(json['created_at'] ?? json['createdAt']),
      teamUuid: json['team_uuid']?.toString(),
      teamName: json['team_name']?.toString(),
      creatorId: json['creator_id']?.toString(),
      creatorName: json['creator_name']?.toString(),
      hasConflict: json['has_conflict'] == 1 || json['has_conflict'] == true,
      conflictData: json['conflict_data'] != null
          ? (json['conflict_data'] is String
              ? jsonDecode(json['conflict_data'])
              : json['conflict_data'])
          : null,
    );
  }
}

// ============================================================
// 🕐 统一时间规范（v3 - 最终版）
// ============================================================

int _parseTimestamp(dynamic val) {
  if (val == null) return DateTime.now().millisecondsSinceEpoch;
  if (val is int) return val;
  if (val is double) return val.toInt();
  if (val is String) {
    final trimmed = val.trim();
    final n = int.tryParse(trimmed);
    if (n != null) return n;
    final dt = DateTime.tryParse(trimmed);
    if (dt != null) return dt.toUtc().millisecondsSinceEpoch;
  }
  return DateTime.now().millisecondsSinceEpoch;
}

DateTime? _parseDateField(dynamic val) {
  if (val == null) return null;
  int ms;
  if (val is int) {
    ms = val;
  } else if (val is double) {
    ms = val.toInt();
  } else if (val is String) {
    final trimmed = val.trim();
    final n = int.tryParse(trimmed);
    if (n != null) {
      ms = n;
    } else {
      final dt = DateTime.tryParse(trimmed);
      if (dt != null) {
        return dt.toUtc().millisecondsSinceEpoch > 0 ? dt.toLocal() : null;
      }
      return null;
    }
  } else {
    return null;
  }
  if (ms <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
}

String? _emptyStringToNull(String? value) {
  if (value == null || value.isEmpty || value == 'null') return null;
  return value;
}

class TimeLogItem {
  String id;
  String title;
  List<String> tagUuids;
  int startTime;
  int endTime;
  String? remark;
  int version;
  int updatedAt;
  int createdAt;
  bool isDeleted;
  String? deviceId;
  String? teamUuid;

  TimeLogItem({
    String? id,
    required this.title,
    this.tagUuids = const [],
    required this.startTime,
    required this.endTime,
    this.remark,
    this.version = 1,
    int? updatedAt,
    int? createdAt,
    this.isDeleted = false,
    this.deviceId,
    this.teamUuid,
  })  : id = id ?? const Uuid().v4(),
        updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch,
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  void markAsChanged() {
    version++;
    updatedAt = DateTime.now().millisecondsSinceEpoch;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'tag_uuids': tagUuids,
        'start_time': startTime,
        'end_time': endTime,
        'remark': remark,
        'version': version,
        'updated_at': updatedAt,
        'created_at': createdAt,
        'is_deleted': isDeleted ? 1 : 0,
        'device_id': deviceId,
        'team_uuid': teamUuid,
      };

  factory TimeLogItem.fromJson(Map<String, dynamic> json) {
    return TimeLogItem(
      id: json['id']?.toString() ??
          json['uuid']?.toString() ??
          const Uuid().v4(),
      title: json['title']?.toString() ?? '',
      tagUuids: (json['tag_uuids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      startTime: (json['start_time'] as num?)?.toInt() ?? 0,
      endTime: (json['end_time'] as num?)?.toInt() ?? 0,
      remark: json['remark']?.toString(),
      version: (json['version'] as num?)?.toInt() ?? 1,
      updatedAt: (json['updated_at'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      createdAt: (json['created_at'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      isDeleted: json['is_deleted'] == 1 || json['is_deleted'] == true,
      deviceId: json['device_id']?.toString(),
      teamUuid: json['team_uuid']?.toString(),
    );
  }
}

// ==========================================
// 🚀 2.5 待办规划区块 (Todo Plan Blocks)
// ==========================================

enum TodoPlanStatus {
  planned,
  finished,
  delayed,
  cancelled,
  reminded,
  focusing,
  missed,
  skipped,
}

enum TodoPlanSource { manual, ai, calendar }

class TodoPlanBlock {
  String id; // Global unique ID
  String todoId;
  String? titleSnapshot;
  int startTime; // UTC ms
  int endTime; // UTC ms
  int plannedMinutes;
  int actualFocusSeconds;
  TodoPlanStatus status;
  TodoPlanSource source;
  String? remark;
  int reminderMinutes;
  int pomodoroMinutes;
  int pomodoroRounds;
  String? calendarEventId;
  List<String> pomodoroRecordIds;
  int version;
  int createdAt;
  int updatedAt;
  bool isDeleted;
  bool isChangedLocally;
  String? deviceId;

  String get uuid => id; // Alias for database compatibility

  TodoPlanBlock({
    String? id,
    required this.todoId,
    this.titleSnapshot,
    required this.startTime,
    required this.endTime,
    this.plannedMinutes = 0,
    this.actualFocusSeconds = 0,
    this.status = TodoPlanStatus.planned,
    this.source = TodoPlanSource.manual,
    this.remark,
    this.reminderMinutes = 5,
    this.pomodoroMinutes = 25,
    this.pomodoroRounds = 0,
    this.calendarEventId,
    List<String>? pomodoroRecordIds,
    this.version = 1,
    int? createdAt,
    int? updatedAt,
    this.isDeleted = false,
    this.isChangedLocally = false,
    this.deviceId,
  })  : id = id ?? const Uuid().v4(),
        pomodoroRecordIds = pomodoroRecordIds ?? [],
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  void markAsChanged() {
    version++;
    isChangedLocally = true;
    updatedAt = DateTime.now().millisecondsSinceEpoch;
  }

  Map<String, dynamic> toJson() => {
        'uuid': id,
        'todo_uuid': todoId,
        'title_snapshot': titleSnapshot,
        'start_time': startTime,
        'end_time': endTime,
        'planned_minutes': plannedMinutes,
        'actual_focus_seconds': actualFocusSeconds,
        'status': status.index,
        'source': source.index,
        'remark': remark,
        'reminder_minutes': reminderMinutes,
        'pomodoro_minutes': pomodoroMinutes,
        'pomodoro_rounds': pomodoroRounds,
        'calendar_event_id': calendarEventId,
        'pomodoro_record_ids': pomodoroRecordIds.join(','),
        'version': version,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'is_deleted': isDeleted ? 1 : 0,
        'device_id': deviceId,
      };

  Map<String, dynamic> toDbJson() {
    final data = toJson();
    // Older local databases created calendar_event_id as TEXT NOT NULL.
    // Keep the cloud JSON nullable, but use an empty string for SQLite writes.
    data['calendar_event_id'] = calendarEventId ?? '';
    return data;
  }

  factory TodoPlanBlock.fromJson(Map<String, dynamic> j) => TodoPlanBlock(
        id: (j['uuid'] ?? j['id'])?.toString(),
        todoId:
            (j['todo_uuid'] ?? j['todo_id'] ?? j['todoId'])?.toString() ?? '',
        titleSnapshot: (j['title_snapshot'] ?? j['titleSnapshot'])?.toString(),
        startTime: (j['start_time'] as num?)?.toInt() ?? 0,
        endTime: (j['end_time'] as num?)?.toInt() ?? 0,
        plannedMinutes: (j['planned_minutes'] as num?)?.toInt() ?? 0,
        actualFocusSeconds: (j['actual_focus_seconds'] as num?)?.toInt() ?? 0,
        status: TodoPlanStatus.values[(j['status'] as int? ?? 0)
            .clamp(0, TodoPlanStatus.values.length - 1)],
        source: TodoPlanSource.values[(j['source'] as int? ?? 0)
            .clamp(0, TodoPlanSource.values.length - 1)],
        remark: j['remark']?.toString(),
        reminderMinutes: (j['reminder_minutes'] as num?)?.toInt() ?? 5,
        pomodoroMinutes: (j['pomodoro_minutes'] as num?)?.toInt() ?? 25,
        pomodoroRounds: (j['pomodoro_rounds'] as num?)?.toInt() ?? 0,
        calendarEventId: _emptyStringToNull(
            (j['calendar_event_id'] ?? j['calendarEventId'])?.toString()),
        pomodoroRecordIds: (j['pomodoro_record_ids'] as String?)
                ?.split(',')
                .where((s) => s.isNotEmpty)
                .toList() ??
            [],
        version: (j['version'] as num?)?.toInt() ?? 1,
        createdAt: (j['created_at'] as num?)?.toInt(),
        updatedAt: (j['updated_at'] as num?)?.toInt(),
        isDeleted: j['is_deleted'] == 1 || j['is_deleted'] == true,
        deviceId: j['device_id']?.toString(),
      );
}

// ==========================================
// 📌 2.6 固定日程 (Fixed Schedules)
// ==========================================

enum FixedScheduleStatus { scheduled, finished, cancelled }

enum FixedScheduleSource { manual, ai, imported, calendar }

enum FixedSchedulePhase { timeTbd, upcoming, ongoing, ended, cancelled }

/// 由学校、组织、预约方等外部来源决定时间的硬约束日程。
///
/// 该模型独立于 [TodoItem] 和 [TodoPlanBlock]：不使用完成勾选表达日程
/// 状态，也不会被待办的截止时间和规划块的可移动语义污染。
class FixedScheduleItem {
  String id;
  String title;
  String date;
  int? startTime;
  int? endTime;
  FixedScheduleStatus status;
  FixedScheduleSource source;
  String? location;
  String? remark;
  List<int> reminderMinutes;
  String? timezone;
  RecurrenceType recurrence;
  int? customIntervalDays;
  String? recurrenceSeriesId;
  List<String> relatedTodoIds;
  String? externalSource;
  String? externalId;
  String? teamUuid;
  String? deviceId;
  bool isDeleted;
  int version;
  int createdAt;
  int updatedAt;

  String get uuid => id;
  bool get isTimeTbd => startTime == null;
  bool get isEndTimeTbd => startTime != null && endTime == null;

  FixedScheduleItem({
    String? id,
    required this.title,
    required this.date,
    this.startTime,
    this.endTime,
    this.status = FixedScheduleStatus.scheduled,
    this.source = FixedScheduleSource.manual,
    this.location,
    this.remark,
    List<int>? reminderMinutes,
    this.timezone,
    this.recurrence = RecurrenceType.none,
    this.customIntervalDays,
    this.recurrenceSeriesId,
    List<String>? relatedTodoIds,
    this.externalSource,
    this.externalId,
    this.teamUuid,
    this.deviceId,
    this.isDeleted = false,
    this.version = 1,
    int? createdAt,
    int? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        reminderMinutes = List<int>.from(reminderMinutes ?? const [15]),
        relatedTodoIds = List<String>.from(relatedTodoIds ?? const []),
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  FixedSchedulePhase phaseAt(DateTime now) {
    if (status == FixedScheduleStatus.cancelled || isDeleted) {
      return FixedSchedulePhase.cancelled;
    }
    if (startTime == null) return FixedSchedulePhase.timeTbd;
    if (status == FixedScheduleStatus.finished) {
      return FixedSchedulePhase.ended;
    }
    final nowMs = now.millisecondsSinceEpoch;
    if (nowMs < startTime!) return FixedSchedulePhase.upcoming;
    if (endTime == null || nowMs < endTime!) {
      return FixedSchedulePhase.ongoing;
    }
    return FixedSchedulePhase.ended;
  }

  void markAsChanged() {
    version++;
    updatedAt = DateTime.now().millisecondsSinceEpoch;
  }

  Map<String, dynamic> toJson() => {
        'uuid': id,
        'title': title,
        'date': date,
        'start_time': startTime,
        'end_time': endTime,
        'status': status.index,
        'source': source.index,
        'location': location,
        'remark': remark,
        'reminder_minutes': jsonEncode(reminderMinutes),
        'timezone': timezone,
        'recurrence': recurrence.index,
        'custom_interval_days': customIntervalDays,
        'recurrence_series_id': recurrenceSeriesId,
        'related_todo_ids': jsonEncode(relatedTodoIds),
        'external_source': externalSource,
        'external_id': externalId,
        'team_uuid': teamUuid,
        'device_id': deviceId,
        'is_deleted': isDeleted ? 1 : 0,
        'version': version,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory FixedScheduleItem.fromJson(Map<String, dynamic> json) {
    List<T> parseList<T>(dynamic raw, T Function(dynamic) convert) {
      if (raw == null) return <T>[];
      dynamic decoded = raw;
      if (raw is String) {
        if (raw.trim().isEmpty) return <T>[];
        try {
          decoded = jsonDecode(raw);
        } catch (_) {
          decoded = raw.split(',');
        }
      }
      if (decoded is! List) return <T>[];
      return decoded.map(convert).toList();
    }

    final rawStatus = (json['status'] as num?)?.toInt() ?? 0;
    final rawSource = (json['source'] as num?)?.toInt() ?? 0;
    final rawRecurrence = (json['recurrence'] as num?)?.toInt() ?? 0;
    return FixedScheduleItem(
      id: (json['uuid'] ?? json['id'])?.toString(),
      title: json['title']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
      startTime: (json['start_time'] as num?)?.toInt(),
      endTime: (json['end_time'] as num?)?.toInt(),
      status: FixedScheduleStatus
          .values[rawStatus.clamp(0, FixedScheduleStatus.values.length - 1)],
      source: FixedScheduleSource
          .values[rawSource.clamp(0, FixedScheduleSource.values.length - 1)],
      location: _emptyStringToNull(json['location']?.toString()),
      remark: _emptyStringToNull(json['remark']?.toString()),
      reminderMinutes: parseList<int>(
        json['reminder_minutes'] ?? json['reminderMinutes'],
        (value) =>
            value is num ? value.toInt() : int.tryParse(value.toString()) ?? 0,
      ),
      timezone: _emptyStringToNull(json['timezone']?.toString()),
      recurrence: RecurrenceType
          .values[rawRecurrence.clamp(0, RecurrenceType.values.length - 1)],
      customIntervalDays: int.tryParse(
        (json['custom_interval_days'] ?? json['customIntervalDays'] ?? '')
            .toString(),
      ),
      recurrenceSeriesId: _emptyStringToNull(
          (json['recurrence_series_id'] ?? json['recurrenceSeriesId'])
              ?.toString()),
      relatedTodoIds: parseList<String>(
        json['related_todo_ids'] ?? json['relatedTodoIds'],
        (value) => value.toString(),
      ),
      externalSource: _emptyStringToNull(json['external_source']?.toString()),
      externalId: _emptyStringToNull(json['external_id']?.toString()),
      teamUuid: _emptyStringToNull(json['team_uuid']?.toString()),
      deviceId: _emptyStringToNull(json['device_id']?.toString()),
      isDeleted: json['is_deleted'] == 1 || json['is_deleted'] == true,
      version: (json['version'] as num?)?.toInt() ?? 1,
      createdAt: (json['created_at'] as num?)?.toInt(),
      updatedAt: (json['updated_at'] as num?)?.toInt(),
    );
  }
}
// ==========================================
// 🚀 3. 课表相关
// ==========================================

/// 学期信息模型
class SemesterInfo {
  final String id; // 学期标识，如 "2025-fall", "2026-spring"
  final String name; // 学期名称，如 "2025秋季学期"
  final DateTime startDate; // 开学日期
  final DateTime? endDate; // 放假日期（可选）
  final bool isCurrent; // 是否为当前学期

  SemesterInfo({
    required this.id,
    required this.name,
    required this.startDate,
    this.endDate,
    this.isCurrent = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'start_date': startDate.toIso8601String(),
        'end_date': endDate?.toIso8601String(),
        'is_current': isCurrent,
      };

  factory SemesterInfo.fromJson(Map<String, dynamic> json) => SemesterInfo(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
        startDate: DateTime.parse(json['start_date']),
        endDate:
            json['end_date'] != null ? DateTime.parse(json['end_date']) : null,
        isCurrent: json['is_current'] ?? false,
      );

  /// 转换为毫秒时间戳（用于云端同步）
  Map<String, dynamic> toCloudJson() => {
        'id': id,
        'name': name,
        'start_ms': startDate.millisecondsSinceEpoch,
        'end_ms': endDate?.millisecondsSinceEpoch,
        'is_current': isCurrent,
      };

  factory SemesterInfo.fromCloudJson(Map<String, dynamic> json) => SemesterInfo(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
        startDate: DateTime.fromMillisecondsSinceEpoch(json['start_ms'] as int),
        endDate: json['end_ms'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['end_ms'] as int)
            : null,
        isCurrent: json['is_current'] ?? false,
      );
}

class CourseItem {
  final String uuid;
  final String courseName;
  final String teacherName;
  final String date; // yyyy-MM-dd
  final int weekday;
  final int startTime;
  final int endTime;
  final int weekIndex;
  final String roomName;
  final String? lessonType;
  final String semesterId; // 所属学期标识
  String? teamUuid;
  int version;
  int updatedAt;
  int createdAt;
  bool isDeleted;

  CourseItem({
    String? uuid,
    required this.courseName,
    required this.teacherName,
    required this.date,
    required this.weekday,
    required this.startTime,
    required this.endTime,
    required this.weekIndex,
    required this.roomName,
    this.lessonType,
    this.semesterId = 'default',
    this.teamUuid,
    this.version = 1,
    int? updatedAt,
    int? createdAt,
    this.isDeleted = false,
  })  : uuid = uuid ??
            generateDeterministicUuid(
                courseName, weekday, startTime, endTime, weekIndex, roomName,
                semesterId: semesterId),
        updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch,
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  static String generateDeterministicUuid(
      String name, int day, int start, int end, int week, String room,
      {String semesterId = 'default'}) {
    const namespace =
        '6ba7b810-9dad-11d1-80b4-00c04fd430c8'; // Namespace URL as seed
    final input = "$semesterId|$name|$day|$start|$end|$week|$room";
    return const Uuid().v5(namespace, input);
  }

  String get formattedStartTime =>
      '${(startTime ~/ 100).toString().padLeft(2, '0')}:${(startTime % 100).toString().padLeft(2, '0')}';
  String get formattedEndTime =>
      '${(endTime ~/ 100).toString().padLeft(2, '0')}:${(endTime % 100).toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'courseName': courseName,
        'teacherName': teacherName,
        'date': date,
        'weekday': weekday,
        'startTime': startTime,
        'endTime': endTime,
        'weekIndex': weekIndex,
        'roomName': roomName,
        'lessonType': lessonType,
        'semester_id': semesterId,
        'team_uuid': teamUuid,
        'version': version,
        'updated_at': updatedAt,
        'created_at': createdAt,
        'is_deleted': isDeleted ? 1 : 0,
      };

  factory CourseItem.fromJson(Map<String, dynamic> json) => CourseItem(
        uuid: json['uuid'] ?? json['id'],
        courseName: json['courseName'] ?? json['course_name'] ?? '未知课程',
        teacherName: json['teacherName'] ?? json['teacher_name'] ?? '未知教师',
        date: json['date'] ?? '',
        weekday: json['weekday'] ?? 1,
        startTime: json['startTime'] ?? json['start_time'] ?? 0,
        endTime: json['endTime'] ?? json['end_time'] ?? 0,
        weekIndex: json['weekIndex'] ?? json['week_index'] ?? 1,
        roomName: json['roomName'] ?? json['room_name'] ?? '未知地点',
        lessonType: json['lessonType'] ?? json['lesson_type'],
        semesterId: json['semester_id'] ?? json['semesterId'] ?? 'default',
        teamUuid: json['team_uuid'] ?? json['teamUuid'],
        version: (json['version'] as num?)?.toInt() ?? 1,
        updatedAt: (json['updated_at'] as num?)?.toInt(),
        createdAt: (json['created_at'] as num?)?.toInt(),
        isDeleted: json['is_deleted'] == 1 || json['is_deleted'] == true,
      );
}

// ==========================================
// 👥 4. 团队与协作模型 (Team Collaboration)
// ==========================================

enum TeamRole { admin, member }

class TeamMember {
  final int userId;
  final String? username;
  final String? email;
  final TeamRole role;
  final int joinedAt;

  TeamMember({
    required this.userId,
    this.username,
    this.email,
    required this.role,
    required this.joinedAt,
  });

  factory TeamMember.fromJson(Map<String, dynamic> json) => TeamMember(
        userId: (json['user_id'] as num).toInt(),
        username: json['username'] as String?,
        email: json['email'] as String?,
        role: (json['role'] == 0) ? TeamRole.admin : TeamRole.member,
        joinedAt: _parseTimestamp(json['joined_at']),
      );
}

class Team {
  final String uuid;
  final String name;
  final int creatorId;
  final int createdAt;
  final TeamRole userRole;
  final int memberCount;
  final String? inviteCode;

  Team({
    required this.uuid,
    required this.name,
    required this.creatorId,
    required this.createdAt,
    required this.userRole,
    this.memberCount = 1,
    this.inviteCode,
  });

  factory Team.fromJson(Map<String, dynamic> json) => Team(
        uuid: json['uuid']?.toString() ?? '',
        name: json['name']?.toString() ?? '未命名团队',
        creatorId: int.tryParse(json['creator_id']?.toString() ?? '0') ?? 0,
        createdAt: _parseTimestamp(json['created_at']),
        userRole: (json['role'] == 0 || json['user_role'] == 0)
            ? TeamRole.admin
            : TeamRole.member,
        memberCount: int.tryParse(json['member_count']?.toString() ?? '1') ?? 1,
        inviteCode: json['invite_code']?.toString(),
      );
}

class TeamInvitation {
  final String code;
  final String teamUuid;
  final int expiresAt;

  TeamInvitation({
    required this.code,
    required this.teamUuid,
    required this.expiresAt,
  });
}

class ConflictInfo {
  final String type;
  final Map<String, dynamic> item;
  final Map<String, dynamic> conflictWith;

  ConflictInfo({
    required this.type,
    required this.item,
    required this.conflictWith,
  });

  factory ConflictInfo.fromJson(Map<String, dynamic> json) => ConflictInfo(
        type: json['type']?.toString() ?? 'unknown',
        item: (json['item'] as Map?)?.cast<String, dynamic>() ?? {},
        conflictWith:
            (json['conflict_with'] as Map?)?.cast<String, dynamic>() ?? {},
      );
}

class TeamAnnouncement {
  final String uuid;
  final String teamUuid;
  final String title;
  final String content;
  final String? creatorName;
  final int createdAt;
  final int? expiresAt; // 🚀 过期时间戳
  final bool isPriority; // 是否强制置顶且需确认
  bool isRead; // 本地状态：当前用户是否已读

  TeamAnnouncement({
    required this.uuid,
    required this.teamUuid,
    required this.title,
    required this.content,
    this.creatorName,
    required this.createdAt,
    this.expiresAt,
    this.isPriority = false,
    this.isRead = false,
  });

  // 兼容旧代码使用的 timestamp 字段
  int get timestamp => createdAt;

  factory TeamAnnouncement.fromJson(Map<String, dynamic> json) {
    return TeamAnnouncement(
      uuid: json['uuid']?.toString() ?? '',
      teamUuid: json['team_uuid']?.toString() ?? '',
      title: json['title']?.toString() ?? '无标题',
      content: json['content']?.toString() ?? '',
      creatorName: json['creator_name'],
      createdAt: json['created_at'] ?? DateTime.now().millisecondsSinceEpoch,
      expiresAt: json['expires_at'],
      isPriority: json['is_priority'] == 1 || json['is_priority'] == true,
      isRead: json['is_read'] == 1 || json['is_read'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'team_uuid': teamUuid,
        'title': title,
        'content': content,
        'creator_name': creatorName,
        'created_at': createdAt,
        'expires_at': expiresAt,
        'is_priority': isPriority ? 1 : 0,
        'is_read': isRead ? 1 : 0,
      };
}

class TeamShare {
  final int id;
  final String shareCode;
  final String teamUuid;
  final String? title;
  final String? description;
  final bool shareTodos;
  final bool shareCountdowns;
  final bool shareAnnouncements;
  final bool hasPassword;
  final int? expiresAt;
  final int viewCount;
  final int createdAt;
  final bool isActive;
  final String? shareUrl;

  TeamShare({
    required this.id,
    required this.shareCode,
    required this.teamUuid,
    this.title,
    this.description,
    this.shareTodos = true,
    this.shareCountdowns = true,
    this.shareAnnouncements = true,
    this.hasPassword = false,
    this.expiresAt,
    this.viewCount = 0,
    required this.createdAt,
    this.isActive = true,
    this.shareUrl,
  });

  bool get isExpired =>
      expiresAt != null && expiresAt! < DateTime.now().millisecondsSinceEpoch;

  factory TeamShare.fromJson(Map<String, dynamic> json) => TeamShare(
        id: (json['id'] as num?)?.toInt() ?? 0,
        shareCode: json['share_code']?.toString() ?? '',
        teamUuid: json['team_uuid']?.toString() ?? '',
        title: json['title']?.toString(),
        description: json['description']?.toString(),
        shareTodos: json['share_todos'] == 1 || json['share_todos'] == true,
        shareCountdowns:
            json['share_countdowns'] == 1 || json['share_countdowns'] == true,
        shareAnnouncements: json['share_announcements'] == 1 ||
            json['share_announcements'] == true,
        hasPassword: json['has_password'] == true || json['has_password'] == 1,
        expiresAt: (json['expires_at'] as num?)?.toInt(),
        viewCount: (json['view_count'] as num?)?.toInt() ?? 0,
        createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
        isActive: json['is_active'] == 1 || json['is_active'] == true,
        shareUrl: json['share_url']?.toString(),
      );
}

// ==========================================
// 🔍 5. 全局搜索模型 (Global Search)
// ==========================================

enum SearchResultType {
  todo,
  todoGroup,
  countdown,
  course,
  log,
  setting,
  action,
  tag,
  app,
  recommend,
  history
}

class SearchResult {
  final String id;
  final String title;
  final String? subtitle;
  final IconData icon;
  final SearchResultType type;
  final Map<String, dynamic>? extraData; // 用于存储跳转参数
  final String? breadcrumb; // 仅设置项使用，显示路径如 "设置 > 视觉"

  SearchResult({
    required this.id,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.type,
    this.extraData,
    this.breadcrumb,
  });
}
