import 'dart:math';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';


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

  static int _parseMs(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool get isAllDayTask {
    if (isAllDay) return true;
    final data = toJson();
    final startMs = _parseMs(data['start_time'] ??
        data['startTime'] ??
        data['created_date'] ??
        data['createdDate']);
    final endMs = _parseMs(data['end_time'] ??
        data['endTime'] ??
        data['due_date'] ??
        data['dueDate']);
    if (startMs <= 0 || endMs <= startMs) return false;

    final start = DateTime.fromMillisecondsSinceEpoch(startMs);
    final end = DateTime.fromMillisecondsSinceEpoch(endMs);

    // 判定为全天任务：时间正好跨越 00:00 到 23:59 或次日 00:00
    if (start.hour == 0 && start.minute == 0) {
      if ((end.hour == 23 && end.minute == 59) ||
          (end.hour == 0 && end.minute == 0 && end.isAfter(start))) {
        return true;
      }
    }
    // 跨度超过 23.5 小时也视为全天
    if (end.difference(start).inMinutes >= 1410) return true;

    return false;
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
        'conflict_data': serverVersionData != null ? jsonEncode(serverVersionData) : null,
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

      recurrence: RecurrenceType.values[int.tryParse(json['recurrence']?.toString() ?? '0') ?? 0],
      // 兼容两种字段名：后端列名 custom_interval_days 和本地存储名 customIntervalDays
      customIntervalDays: int.tryParse(json['customIntervalDays']?.toString() ?? json['custom_interval_days']?.toString() ?? ''),
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
      categoryId: json['category_id']?.toString() ?? json['categoryId']?.toString(),
      hasConflict: json['has_conflict'] == 1 || json['has_conflict'] == true,
      serverVersionData: json['conflict_data'] != null ? (json['conflict_data'] is String ? jsonDecode(json['conflict_data']) : json['conflict_data']) : null,
    );
  }

  /// 🚀 静态方法：清理过期的图片分析文件（7天以上）
  static Future<void> cleanupAnalysisImages() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final imageDir = Directory('${appDir.path}/analysis_images');
      if (!await imageDir.exists()) return;

      final now = DateTime.now();
      final expiration = now.subtract(const Duration(days: 7));

      final files = imageDir.listSync();
      int deletedCount = 0;

      for (var file in files) {
        if (file is File) {
          final stat = await file.stat();
          if (stat.modified.isBefore(expiration)) {
            await file.delete();
            deletedCount++;
          }
        }
      }
      if (deletedCount > 0) {
        debugPrint('🧹 清理了 $deletedCount 个过期的识别图片');
      }
    } catch (e) {
      debugPrint('❌ 清理识别图片失败: $e');
    }
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

  factory CountdownItem.fromSql(Map<String, dynamic> map) => CountdownItem.fromJson(map);

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
      conflictData: json['conflict_data'] != null ? (json['conflict_data'] is String ? jsonDecode(json['conflict_data']) : json['conflict_data']) : null,
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

  factory TodoGroup.fromSql(Map<String, dynamic> map) => TodoGroup.fromJson(map);

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
      conflictData: json['conflict_data'] != null ? (json['conflict_data'] is String ? jsonDecode(json['conflict_data']) : json['conflict_data']) : null,
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
      id: json['id']?.toString() ?? json['uuid']?.toString() ?? const Uuid().v4(),
      title: json['title']?.toString() ?? '',
      tagUuids: (json['tag_uuids'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      startTime: (json['start_time'] as num?)?.toInt() ?? 0,
      endTime: (json['end_time'] as num?)?.toInt() ?? 0,
      remark: json['remark']?.toString(),
      version: (json['version'] as num?)?.toInt() ?? 1,
      updatedAt: (json['updated_at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      createdAt: (json['created_at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      isDeleted: json['is_deleted'] == 1 || json['is_deleted'] == true,
      deviceId: json['device_id']?.toString(),
      teamUuid: json['team_uuid']?.toString(),
    );
  }
}

// ==========================================
// 🚀 3. 课表相关
// ==========================================

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
    this.teamUuid,
    this.version = 1,
    int? updatedAt,
    int? createdAt,
    this.isDeleted = false,
  }) : uuid = uuid ?? generateDeterministicUuid(courseName, weekday, startTime, endTime, weekIndex, roomName),
       updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch,
       createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  static String generateDeterministicUuid(String name, int day, int start, int end, int week, String room) {
    const namespace = '6ba7b810-9dad-11d1-80b4-00c04fd430c8'; // Namespace URL as seed
    final input = "$name|$day|$start|$end|$week|$room";
    return const Uuid().v5(namespace, input);
  }

  String get formattedStartTime => '${(startTime ~/ 100).toString().padLeft(2, '0')}:${(startTime % 100).toString().padLeft(2, '0')}';
  String get formattedEndTime => '${(endTime ~/ 100).toString().padLeft(2, '0')}:${(endTime % 100).toString().padLeft(2, '0')}';

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
    userRole: (json['role'] == 0 || json['user_role'] == 0) ? TeamRole.admin : TeamRole.member,
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
    conflictWith: (json['conflict_with'] as Map?)?.cast<String, dynamic>() ?? {},
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

// ==========================================
// 🔍 5. 全局搜索模型 (Global Search)
// ==========================================

enum SearchResultType { todo, todoGroup, countdown, course, log, setting, action, tag, app, recommend, history }

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
