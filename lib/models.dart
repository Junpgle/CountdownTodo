import 'dart:math';
import 'package:uuid/uuid.dart';

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
      result += (userAnswer == correctAnswer) ? " (正确)" : " (错误, 正解: $correctAnswer)";
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
        questions.add(Question(num1: n1, num2: n2, operatorSymbol: op, correctAnswer: ans));
      }
    }
    return questions;
  }
}

// ==========================================
// 🚀 2. 效率功能：支持 Delta Sync 的数据模型
// ==========================================

enum RecurrenceType { none, daily, customDays }

class TodoItem {
  String id; // 核心：全局唯一 UUID
  String title;
  bool isDone;
  bool isDeleted; // 核心：逻辑删除标记
  int version;    // 核心：并发版本号
  int updatedAt;  // 核心：最后修改时间戳 (毫秒)
  int createdAt;  // 🚀 真正的创建时间戳 (物理生成时间，毫秒)
  int? createdDate; // 🚀 真正的开始时间戳 (业务逻辑设定的开始日期，毫秒)

  RecurrenceType recurrence;
  int? customIntervalDays;
  DateTime? recurrenceEndDate;
  DateTime? dueDate;
  String? remark; // 📝 备注

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
  }) :
        this.id = id ?? const Uuid().v4(),
        this.updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch,
        this.createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  // 🚀 核心方法：每次本地对任务的修改，都必须调用此方法！
  void markAsChanged() {
    version++;
    updatedAt = DateTime.now().millisecondsSinceEpoch;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'uuid': id,
    'content': title,
    'is_completed': isDone ? 1 : 0,
    'is_deleted': isDeleted ? 1 : 0,
    'version': version,
    'updated_at': updatedAt,          // UTC 毫秒时间戳
    'created_at': createdAt,          // UTC 毫秒时间戳（物理创建时间，不可变）
    'created_date': createdDate,      // UTC 毫秒时间戳（任务开始时间，可为 null）
    'due_date': dueDate?.millisecondsSinceEpoch,  // UTC 毫秒时间戳（任务截止时间，可为 null）
    'recurrence': recurrence.index,
    // 循环间隔：同时输出两种键名兼容后端列名(custom_interval_days)和本地存储名(customIntervalDays)
    'customIntervalDays': customIntervalDays,
    'custom_interval_days': customIntervalDays,
    // 循环结束日：同时输出两种键名
    'recurrenceEndDate': recurrenceEndDate?.millisecondsSinceEpoch,
    'recurrence_end_date': recurrenceEndDate?.millisecondsSinceEpoch,
    'remark': remark,                 // 📝 备注（可为 null）
  };

  factory TodoItem.fromJson(Map<String, dynamic> json) {
    // 优先读取后端的 uuid 字段，如果没有再尝试 id 字段，最后才兜底生成
    String parsedId = json['uuid']?.toString() ?? json['id']?.toString() ?? const Uuid().v4();
    if (!parsedId.contains('-')) parsedId = const Uuid().v4(); // 如果旧数据是自增ID，强制转UUID

    return TodoItem(
      id: parsedId,
      title: json['content'] ?? json['title'] ?? '',
      isDone: json['is_completed'] == 1 || json['is_completed'] == true || json['isDone'] == true,
      isDeleted: json['is_deleted'] == 1 || json['is_deleted'] == true || json['isDeleted'] == true,
      version: json['version'] ?? 1,
      updatedAt: _parseTimestamp(json['updated_at'] ?? json['lastUpdated']),
      createdAt: _parseTimestamp(json['created_at'] ?? json['createdAt']),

      // created_date = 任务开始时间（业务字段），与 created_at（物理创建时间）严格区分
      createdDate: (json['created_date'] != null)
          ? _parseTimestamp(json['created_date'])
          : ((json['createdDate'] != null) ? _parseTimestamp(json['createdDate']) : null),

      recurrence: RecurrenceType.values[json['recurrence'] as int? ?? 0],
      // 兼容两种字段名：后端列名 custom_interval_days 和本地存储名 customIntervalDays
      customIntervalDays: json['customIntervalDays'] as int?
          ?? json['custom_interval_days'] as int?,
      // 兼容两种字段名：后端列名 recurrence_end_date 和本地存储名 recurrenceEndDate
      recurrenceEndDate: _parseDateField(
          json['recurrenceEndDate'] ?? json['recurrence_end_date']),
      // due_date = 任务截止时间
      dueDate: _parseDateField(json['due_date']),
      // 📝 备注
      remark: json['remark'] as String?,
    );
  }
}

class CountdownItem {
  String id;
  String title;
  DateTime targetDate;
  bool isDeleted;
  int version;
  int updatedAt;
  int createdAt;

  CountdownItem({
    String? id,
    required this.title,
    required this.targetDate,
    this.isDeleted = false,
    this.version = 1,
    int? updatedAt,
    int? createdAt,
  }) :
        this.id = id ?? const Uuid().v4(),
        this.updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch,
        this.createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  // 🚀 核心方法：每次本地对倒计时的修改，都必须调用此方法！
  void markAsChanged() {
    version++;
    updatedAt = DateTime.now().millisecondsSinceEpoch;
  }

  Map<String, dynamic> toJson() => {
    'id': id,           // 兼容本地读取
    'uuid': id,         // 对齐后端数据库主键
    'title': title,
    'target_time': targetDate.millisecondsSinceEpoch, // UTC 毫秒时间戳
    'is_deleted': isDeleted ? 1 : 0,
    'version': version,
    'updated_at': updatedAt,   // UTC 毫秒时间戳
    'created_at': createdAt,   // UTC 毫秒时间戳
  };

  factory CountdownItem.fromJson(Map<String, dynamic> json) {
    // 优先读取后端的 uuid 字段
    String parsedId = json['uuid']?.toString() ?? json['id']?.toString() ?? const Uuid().v4();
    if (!parsedId.contains('-')) parsedId = const Uuid().v4();

    return CountdownItem(
      id: parsedId,
      title: json['title'] ?? '',
      // 🚀 修复：正确解析 targetDate（可能是毫秒时间戳或 ISO 字符串）
      // null/0 均视为无效，fallback 到明天（避免把 target_time=0 的旧脏数据当成今日倒计时）
      targetDate: _parseDateField(json['target_time'] ?? json['targetDate']) ??
          DateTime.now().add(const Duration(days: 1)),
      isDeleted: json['is_deleted'] == 1 || json['is_deleted'] == true || json['isDeleted'] == true,
      version: json['version'] ?? 1,
      updatedAt: _parseTimestamp(json['updated_at'] ?? json['lastUpdated']),
      createdAt: _parseTimestamp(json['created_at'] ?? json['createdAt']),
    );
  }
}

// ============================================================
// 🕐 统一时间规范（v3 - 最终版）
//
// 【规范】
//   - 所有时间字段在存储、传输中统一使用 UTC 毫秒时间戳 (int)
//   - DateTime.now().millisecondsSinceEpoch 与 JS Date.now()
//     均为 UTC epoch，天然一致，无需任何 +8/-8 偏移
//   - 显示给用户时：DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal()
//
// 【历史数据兼容】新数据统一 int ms；历史数据库中可能存有 ISO 字符串，兼容解析不再写入。
// ============================================================

/// 解析 UTC 毫秒时间戳，必填字段专用（null 返回当前时间）。
/// 同时兼容 ISO 8601 字符串（历史数据库遗留格式）。
int _parseTimestamp(dynamic val) {
  if (val == null) return DateTime.now().millisecondsSinceEpoch;
  if (val is int) return val;
  if (val is double) return val.toInt();
  if (val is String) {
    final trimmed = val.trim();
    // 优先尝试纯数字（新格式）
    final n = int.tryParse(trimmed);
    if (n != null) return n;
    // 兼容历史 ISO 8601 字符串（如 "2026-01-15T10:05:00.000Z"）
    final dt = DateTime.tryParse(trimmed);
    if (dt != null) return dt.toUtc().millisecondsSinceEpoch;
  }
  return DateTime.now().millisecondsSinceEpoch;
}

/// 解析可空 UTC 毫秒时间戳，返回本地时区 DateTime。
/// null / 0 视为无效，返回 null。同时兼容历史 ISO 8601 字符串。
DateTime? _parseDateField(dynamic val) {
  if (val == null) return null;
  int ms;
  if (val is int) {
    ms = val;
  } else if (val is double) {
    ms = val.toInt();
  } else if (val is String) {
    final trimmed = val.trim();
    // 优先尝试纯数字（新格式）
    final n = int.tryParse(trimmed);
    if (n != null) {
      ms = n;
    } else {
      // 兼容历史 ISO 8601 字符串
      final dt = DateTime.tryParse(trimmed);
      if (dt != null) return dt.toUtc().millisecondsSinceEpoch > 0
          ? dt.toLocal()
          : null;
      return null;
    }
  } else {
    return null;
  }
  if (ms <= 0) return null;
  // UTC 毫秒时间戳 → 本地时区 DateTime（+8 自动应用于显示）
  return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
}


