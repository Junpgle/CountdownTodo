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
  int createdAt;  // 创建时间戳 (毫秒)

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
    'id': id,
    'content': title,
    'is_completed': isDone ? 1 : 0,
    'is_deleted': isDeleted ? 1 : 0,
    'version': version,
    'updated_at': updatedAt,
    'created_at': createdAt,
    'recurrence': recurrence.index,
    'customIntervalDays': customIntervalDays,
    'recurrenceEndDate': recurrenceEndDate?.toIso8601String(),
    'due_date': dueDate?.toIso8601String(),
  };

  factory TodoItem.fromJson(Map<String, dynamic> json) {
    // 兼容旧数据，如果没有 id 则赋予一个 UUID
    String parsedId = json['id']?.toString() ?? const Uuid().v4();
    if (!parsedId.contains('-')) parsedId = const Uuid().v4(); // 如果旧数据是自增ID，强制转UUID

    return TodoItem(
      id: parsedId,
      title: json['content'] ?? json['title'] ?? '',
      isDone: json['is_completed'] == 1 || json['is_completed'] == true || json['isDone'] == true,
      isDeleted: json['is_deleted'] == 1 || json['is_deleted'] == true || json['isDeleted'] == true,
      version: json['version'] ?? 1,
      updatedAt: _parseTimestamp(json['updated_at'] ?? json['lastUpdated']),
      createdAt: _parseTimestamp(json['created_at'] ?? json['createdAt']),
      recurrence: RecurrenceType.values[json['recurrence'] ?? 0],
      customIntervalDays: json['customIntervalDays'],
      recurrenceEndDate: json['recurrenceEndDate'] != null ? DateTime.tryParse(json['recurrenceEndDate'].toString()) : null,
      dueDate: json['due_date'] != null ? DateTime.tryParse(json['due_date'].toString()) : null,
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
    'id': id,
    'title': title,
    'target_time': targetDate.toIso8601String(),
    'is_deleted': isDeleted ? 1 : 0,
    'version': version,
    'updated_at': updatedAt,
    'created_at': createdAt,
  };

  factory CountdownItem.fromJson(Map<String, dynamic> json) {
    String parsedId = json['id']?.toString() ?? const Uuid().v4();
    if (!parsedId.contains('-')) parsedId = const Uuid().v4();

    return CountdownItem(
      id: parsedId,
      title: json['title'] ?? '',
      targetDate: DateTime.tryParse(json['target_time'] ?? json['targetDate'] ?? '') ?? DateTime.now(),
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