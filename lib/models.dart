import 'dart:math'; // test
import 'package:flutter/cupertino.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';

import 'utils/analysis_image_cleanup.dart';
import 'utils/json_value_parser.dart';

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
  habitCheckIn,
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
    final typeIndex = JsonValueParser.toInt(map['type'])
        .clamp(0, TimelineEventType.values.length - 1)
        .toInt();
    return TimelineEvent(
      id: map['id']?.toString() ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        JsonValueParser.epochMillisOrNow(map['timestamp']),
      ),
      type: TimelineEventType.values[typeIndex],
      title: map['title']?.toString() ?? '',
      subtitle: map['subtitle']?.toString(),
      extraData: (map['extraData'] as Map?)?.cast<String, dynamic>(),
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
    final now = DateTime.now().millisecondsSinceEpoch;
    updatedAt = now > updatedAt ? now : updatedAt + 1;
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

    final recurrenceIndex = JsonValueParser.toInt(json['recurrence'])
        .clamp(0, RecurrenceType.values.length - 1)
        .toInt();

    return TodoItem(
      id: parsedId,
      title: json['content']?.toString() ?? json['title']?.toString() ?? '',
      isDone: json['is_completed'] == 1 ||
          json['is_completed'] == true ||
          json['isDone'] == true,
      isDeleted: json['is_deleted'] == 1 ||
          json['is_deleted'] == true ||
          json['isDeleted'] == true,
      version: JsonValueParser.toInt(json['version'], fallback: 1),
      updatedAt: _parseTimestamp(json['updated_at'] ?? json['lastUpdated']),
      createdAt: _parseTimestamp(json['created_at'] ?? json['createdAt']),

      // created_date = 任务开始时间（业务字段），与 created_at（物理创建时间）严格区分
      createdDate: (json['created_date'] != null)
          ? _parseTimestamp(json['created_date'])
          : ((json['createdDate'] != null)
              ? _parseTimestamp(json['createdDate'])
              : null),

      recurrence: RecurrenceType.values[recurrenceIndex],
      recurrenceSeriesId: _emptyStringToNull(
        (json['recurrence_series_id'] ?? json['recurrenceSeriesId'])
            ?.toString(),
      ),
      // 兼容两种字段名：后端列名 custom_interval_days 和本地存储名 customIntervalDays
      customIntervalDays: JsonValueParser.toNullableInt(
        json['customIntervalDays'] ?? json['custom_interval_days'],
      ),
      // 兼容两种字段名：后端列名 recurrence_end_date 和本地存储名 recurrenceEndDate
      recurrenceEndDate: _parseDateField(
          json['recurrenceEndDate'] ?? json['recurrence_end_date']),
      // due_date = 任务截止时间
      dueDate: _parseDateField(json['dueDate'] ?? json['due_date']),
      // 📝 备注
      remark: json['remark']?.toString(),
      // 📸 图片路径
      imagePath: (json['image_path'] ?? json['imagePath'])?.toString(),
      // 📄 原始分析文本
      originalText: (json['original_text'] ?? json['originalText'])?.toString(),
      // 📁 分组 ID
      groupId: (json['group_id'] ?? json['groupId'])?.toString(),
      // 🚀 提醒提前量
      reminderMinutes: JsonValueParser.toNullableInt(
        json['reminder_minutes'] ?? json['reminderMinutes'],
      ),
      // 👥 团队 ID
      teamUuid: (json['team_uuid'] ?? json['teamUuid'])?.toString(),
      creatorId: (json['creator_id'] ?? json['creatorId'])?.toString(),
      creatorName: (json['creator_name'] ?? json['creatorName'])?.toString(),
      teamName: (json['team_name'] ?? json['teamName'])?.toString(),
      collabType: JsonValueParser.toInt(
        json['collab_type'] ?? json['collabType'],
      ),
      isAllDay: json['is_all_day'] == 1 || json['isAllDay'] == true,
      categoryId:
          json['category_id']?.toString() ?? json['categoryId']?.toString(),
      hasConflict: json['has_conflict'] == 1 || json['has_conflict'] == true,
      serverVersionData: JsonValueParser.toMap(json['conflict_data']),
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
      title: json['title']?.toString() ?? '',
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
      version: JsonValueParser.toInt(json['version'], fallback: 1),
      updatedAt: _parseTimestamp(json['updated_at'] ?? json['lastUpdated']),
      createdAt: _parseTimestamp(json['created_at'] ?? json['createdAt']),
      teamUuid: (json['team_uuid'] ?? json['teamUuid'])?.toString(),
      teamName: (json['team_name'] ?? json['teamName'])?.toString(),
      creatorId: (json['creator_id'] ?? json['creatorId'])?.toString(),
      creatorName: (json['creator_name'] ?? json['creatorName'])?.toString(),
      hasConflict: json['has_conflict'] == 1 || json['has_conflict'] == true,
      conflictData: JsonValueParser.toMap(json['conflict_data']),
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
      version: JsonValueParser.toInt(json['version'], fallback: 1),
      updatedAt: _parseTimestamp(json['updated_at'] ?? json['updatedAt']),
      createdAt: _parseTimestamp(json['created_at'] ?? json['createdAt']),
      teamUuid: json['team_uuid']?.toString(),
      teamName: json['team_name']?.toString(),
      creatorId: json['creator_id']?.toString(),
      creatorName: json['creator_name']?.toString(),
      hasConflict: json['has_conflict'] == 1 || json['has_conflict'] == true,
      conflictData: JsonValueParser.toMap(json['conflict_data']),
    );
  }
}

// ============================================================
// 🕐 统一时间规范（v3 - 最终版）
// ============================================================

int _parseTimestamp(dynamic val) {
  return JsonValueParser.epochMillisOrNow(val);
}

DateTime? _parseDateField(dynamic val) {
  return JsonValueParser.localDateTime(val);
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
      startTime: JsonValueParser.toInt(json['start_time']),
      endTime: JsonValueParser.toInt(json['end_time']),
      remark: json['remark']?.toString(),
      version: JsonValueParser.toInt(json['version'], fallback: 1),
      updatedAt: JsonValueParser.epochMillisOrNow(json['updated_at']),
      createdAt: JsonValueParser.epochMillisOrNow(json['created_at']),
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
        startTime: JsonValueParser.toInt(j['start_time']),
        endTime: JsonValueParser.toInt(j['end_time']),
        plannedMinutes: JsonValueParser.toInt(j['planned_minutes']),
        actualFocusSeconds: JsonValueParser.toInt(j['actual_focus_seconds']),
        status: TodoPlanStatus.values[JsonValueParser.toInt(j['status'])
            .clamp(0, TodoPlanStatus.values.length - 1)
            .toInt()],
        source: TodoPlanSource.values[JsonValueParser.toInt(j['source'])
            .clamp(0, TodoPlanSource.values.length - 1)
            .toInt()],
        remark: j['remark']?.toString(),
        reminderMinutes:
            JsonValueParser.toInt(j['reminder_minutes'], fallback: 5),
        pomodoroMinutes:
            JsonValueParser.toInt(j['pomodoro_minutes'], fallback: 25),
        pomodoroRounds: JsonValueParser.toInt(j['pomodoro_rounds']),
        calendarEventId: _emptyStringToNull(
            (j['calendar_event_id'] ?? j['calendarEventId'])?.toString()),
        pomodoroRecordIds: (j['pomodoro_record_ids'] as String?)
                ?.split(',')
                .where((s) => s.isNotEmpty)
                .toList() ??
            [],
        version: JsonValueParser.toInt(j['version'], fallback: 1),
        createdAt: JsonValueParser.toNullableInt(j['created_at']),
        updatedAt: JsonValueParser.toNullableInt(j['updated_at']),
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
  int? ownerUserId;
  String? deviceId;
  bool isDeleted;
  int version;
  int createdAt;
  int updatedAt;

  String get uuid => id;
  bool get isTimeTbd => startTime == null;
  bool get isEndTimeTbd => startTime != null && endTime == null;

  bool canChangeTeamFor(int? userId) =>
      teamUuid == null || (ownerUserId != null && ownerUserId == userId);

  /// “结束时间待定”只在日程所属日期内视为进行中，避免跨天后永久占用
  /// 进行中状态。这里的午夜边界仅用于展示，不会写回成虚构结束时间。
  int? get effectiveActivityEndTime {
    if (startTime == null) return null;
    if (endTime != null) return endTime;
    final parsedDate = DateTime.tryParse(date)?.toLocal();
    final start = DateTime.fromMillisecondsSinceEpoch(startTime!).toLocal();
    final day = parsedDate ?? start;
    return DateTime(day.year, day.month, day.day + 1).millisecondsSinceEpoch;
  }

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
    this.ownerUserId,
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
    final effectiveEnd = effectiveActivityEndTime;
    if (effectiveEnd != null && nowMs < effectiveEnd) {
      return FixedSchedulePhase.ongoing;
    }
    return FixedSchedulePhase.ended;
  }

  void markAsChanged() {
    version++;
    final now = DateTime.now().millisecondsSinceEpoch;
    updatedAt = now > updatedAt ? now : updatedAt + 1;
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
        'owner_user_id': ownerUserId,
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

    final rawStatus = JsonValueParser.toInt(json['status']);
    final rawSource = JsonValueParser.toInt(json['source']);
    final rawRecurrence = JsonValueParser.toInt(json['recurrence']);
    return FixedScheduleItem(
      id: (json['uuid'] ?? json['id'])?.toString(),
      title: json['title']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
      startTime: JsonValueParser.toNullableInt(json['start_time']),
      endTime: JsonValueParser.toNullableInt(json['end_time']),
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
      customIntervalDays: JsonValueParser.toNullableInt(
        json['custom_interval_days'] ?? json['customIntervalDays'],
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
      ownerUserId: int.tryParse(
        (json['owner_user_id'] ?? json['ownerUserId'] ?? json['user_id'] ?? '')
            .toString(),
      ),
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
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        startDate: JsonValueParser.localDateTime(json['start_date']) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        endDate: JsonValueParser.localDateTime(json['end_date']),
        isCurrent: json['is_current'] == true || json['is_current'] == 1,
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
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        startDate: DateTime.fromMillisecondsSinceEpoch(
            JsonValueParser.toInt(json['start_ms'])),
        endDate: json['end_ms'] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                JsonValueParser.toInt(json['end_ms']))
            : null,
        isCurrent: json['is_current'] == true || json['is_current'] == 1,
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
        uuid: (json['uuid'] ?? json['id'])?.toString(),
        courseName:
            (json['courseName'] ?? json['course_name'])?.toString() ?? '未知课程',
        teacherName:
            (json['teacherName'] ?? json['teacher_name'])?.toString() ?? '未知教师',
        date: json['date']?.toString() ?? '',
        weekday: JsonValueParser.toInt(json['weekday'], fallback: 1),
        startTime: JsonValueParser.toInt(
          json['startTime'] ?? json['start_time'],
        ),
        endTime: JsonValueParser.toInt(json['endTime'] ?? json['end_time']),
        weekIndex: JsonValueParser.toInt(
          json['weekIndex'] ?? json['week_index'],
          fallback: 1,
        ),
        roomName: (json['roomName'] ?? json['room_name'])?.toString() ?? '未知地点',
        lessonType: (json['lessonType'] ?? json['lesson_type'])?.toString(),
        semesterId: (json['semester_id'] ?? json['semesterId'])?.toString() ??
            'default',
        teamUuid: (json['team_uuid'] ?? json['teamUuid'])?.toString(),
        version: JsonValueParser.toInt(json['version'], fallback: 1),
        updatedAt: JsonValueParser.toNullableInt(json['updated_at']),
        createdAt: JsonValueParser.toNullableInt(json['created_at']),
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
        userId: JsonValueParser.toInt(json['user_id']),
        username: json['username']?.toString(),
        email: json['email']?.toString(),
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
      createdAt: JsonValueParser.epochMillisOrNow(json['created_at']),
      expiresAt: JsonValueParser.toNullableInt(json['expires_at']),
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
  final bool shareSchedules;
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
    this.shareSchedules = true,
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
        id: JsonValueParser.toInt(json['id']),
        shareCode: json['share_code']?.toString() ?? '',
        teamUuid: json['team_uuid']?.toString() ?? '',
        title: json['title']?.toString(),
        description: json['description']?.toString(),
        shareTodos: json['share_todos'] == 1 || json['share_todos'] == true,
        shareSchedules: json['share_schedules'] == null ||
            json['share_schedules'] == 1 ||
            json['share_schedules'] == true,
        shareCountdowns:
            json['share_countdowns'] == 1 || json['share_countdowns'] == true,
        shareAnnouncements: json['share_announcements'] == 1 ||
            json['share_announcements'] == true,
        hasPassword: json['has_password'] == true || json['has_password'] == 1,
        expiresAt: JsonValueParser.toNullableInt(json['expires_at']),
        viewCount: JsonValueParser.toInt(json['view_count']),
        createdAt: JsonValueParser.toInt(json['created_at']),
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
  habit,
  challenge,
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
