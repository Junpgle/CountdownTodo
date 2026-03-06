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
    'id': id,           // 兼容本地读取
    'uuid': id,         // 对齐后端数据库主键
    'content': title,
    'is_completed': isDone ? 1 : 0,
    'is_deleted': isDeleted ? 1 : 0,
    'version': version,
    'updated_at': updatedAt,
    'created_at': createdAt,       // 🚀 物理创建时间（记录何时被添加到系统）
    'created_date': createdDate,   // 🚀 业务开始时间（用户设定的任务开始时间）
    'recurrence': recurrence.index,
    'customIntervalDays': customIntervalDays,
    'recurrenceEndDate': recurrenceEndDate?.millisecondsSinceEpoch,  // 🚀 修复：发送毫秒时间戳
    'due_date': dueDate?.millisecondsSinceEpoch,  // 🚀 修复：发送毫秒时间戳
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
      createdAt: _parseTimestamp(json['created_at'] ?? json['createdAt']), // 🚀 回归物理创建本意

      // 🚀 独立解析业务开始时间，不再和 createdAt 混用
      createdDate: (json['created_date'] != null)
          ? _parseTimestamp(json['created_date'])
          : ((json['createdDate'] != null) ? _parseTimestamp(json['createdDate']) : null),

      recurrence: RecurrenceType.values[json['recurrence'] ?? 0],
      customIntervalDays: json['customIntervalDays'],
      // 🚀 修复：正确解析 recurrenceEndDate（可能是毫秒时间戳或 ISO 字符串）
      recurrenceEndDate: _parseDateField(json['recurrenceEndDate']),
      // 🚀 修复：正确解析 dueDate（可能是毫秒时间戳或 ISO 字符串）
      dueDate: _parseDateField(json['due_date']),
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
    'target_time': targetDate.millisecondsSinceEpoch,  // 🚀 修复：发送毫秒时间戳而不是 ISO 字符串
    'is_deleted': isDeleted ? 1 : 0,
    'version': version,
    'updated_at': updatedAt,
    'created_at': createdAt,
  };

  factory CountdownItem.fromJson(Map<String, dynamic> json) {
    // 优先读取后端的 uuid 字段
    String parsedId = json['uuid']?.toString() ?? json['id']?.toString() ?? const Uuid().v4();
    if (!parsedId.contains('-')) parsedId = const Uuid().v4();

    return CountdownItem(
      id: parsedId,
      title: json['title'] ?? '',
      // 🚀 修复：正确解析 targetDate（可能是毫秒时间戳或 ISO 字符串）
      targetDate: _parseDateField(json['target_time'] ?? json['targetDate']) ?? DateTime.now(),
      isDeleted: json['is_deleted'] == 1 || json['is_deleted'] == true || json['isDeleted'] == true,
      version: json['version'] ?? 1,
      updatedAt: _parseTimestamp(json['updated_at'] ?? json['lastUpdated']),
      createdAt: _parseTimestamp(json['created_at'] ?? json['createdAt']),
    );
  }
}

// 🛡️ 时间戳安全解析器
int _parseTimestamp(dynamic val) {
  if (val == null) return DateTime.now().millisecondsSinceEpoch;
  if (val is int) return val;
  if (val is double) return val.toInt();
  if (val is String) {
    int? parsed = int.tryParse(val);
    if (parsed != null) return parsed;
    DateTime? dt = DateTime.tryParse(val);
    if (dt != null) return dt.millisecondsSinceEpoch;
  }
  return DateTime.now().millisecondsSinceEpoch;
}

// 🛡️ 日期字段安全解析器（处理毫秒时间戳和 ISO 字符串两种格式）
DateTime? _parseDateField(dynamic val) {
  if (val == null) return null;

  // 如果是整数，当作毫秒时间戳处理
  if (val is int) {
    return DateTime.fromMillisecondsSinceEpoch(val);
  }

  // 如果是浮点数，转为整数后当作毫秒时间戳处理
  if (val is double) {
    return DateTime.fromMillisecondsSinceEpoch(val.toInt());
  }

  // 如果是字符串
  if (val is String) {
    // 首先尝试当作毫秒时间戳（纯数字字符串）
    int? asInt = int.tryParse(val);
    if (asInt != null && asInt > 0) {
      // 如果是一个很大的数字（13 位以上），就是毫秒时间戳
      if (val.length >= 13) {
        return DateTime.fromMillisecondsSinceEpoch(asInt);
      }
    }

    // 尝试当作 ISO 8601 字符串解析
    DateTime? dt = DateTime.tryParse(val);
    if (dt != null) return dt;
  }

  return null;
}

