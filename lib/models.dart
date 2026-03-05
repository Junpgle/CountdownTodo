import 'dart:math';

// --- 测验相关 ---

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

// --- 效率功能相关 (新增部分) ---

// 🚀 抽取出的通用安全时间解析器，防止脏数据引发崩溃
DateTime _parseTimeSafely(dynamic val, {bool isNullable = false, DateTime? fallback}) {
  if (val == null) return isNullable ? (fallback ?? DateTime.now()) : DateTime.now();
  if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
  if (val is String) return DateTime.tryParse(val) ?? (fallback ?? DateTime.now());
  return fallback ?? DateTime.now();
}

class CountdownItem {
  String title;
  DateTime targetDate;
  DateTime lastUpdated; // 新增：记录最后修改时间

  CountdownItem({
    required this.title,
    required this.targetDate,
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'targetDate': targetDate.toIso8601String(),
    'lastUpdated': lastUpdated.millisecondsSinceEpoch, // 统一存储为时间戳
  };

  factory CountdownItem.fromJson(Map<String, dynamic> json) => CountdownItem(
    title: json['title'] ?? '',
    targetDate: _parseTimeSafely(json['targetDate']),
    lastUpdated: _parseTimeSafely(json['lastUpdated']), // 🚀 兼容 int 和 String
  );
}

enum RecurrenceType { none, daily, customDays }

class TodoItem {
  String id;
  String title;
  bool isDone;
  RecurrenceType recurrence;
  int? customIntervalDays; // 隔几天重复
  DateTime? recurrenceEndDate; // 重复截止日期
  DateTime lastUpdated; // 上次更新状态的时间
  DateTime? dueDate; // 单次待办的截止日期
  DateTime createdAt; // 新增：待办的创建日期

  TodoItem({
    required this.id,
    required this.title,
    this.isDone = false,
    this.recurrence = RecurrenceType.none,
    this.customIntervalDays,
    this.recurrenceEndDate,
    required this.lastUpdated,
    this.dueDate,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now(); // 若未提供则默认为今日

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'isDone': isDone,
    'recurrence': recurrence.index,
    'customIntervalDays': customIntervalDays,
    'recurrenceEndDate': recurrenceEndDate?.toIso8601String(),
    'lastUpdated': lastUpdated.millisecondsSinceEpoch, // 🚀 核心修复：统一存储为数字时间戳，不再使用 String
    'dueDate': dueDate?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
  };

  factory TodoItem.fromJson(Map<String, dynamic> json) => TodoItem(
    id: json['id'] ?? '',
    title: json['title'] ?? '',
    isDone: json['isDone'] ?? false,
    recurrence: RecurrenceType.values[json['recurrence'] ?? 0],
    customIntervalDays: json['customIntervalDays'],
    recurrenceEndDate: json['recurrenceEndDate'] != null ? _parseTimeSafely(json['recurrenceEndDate']) : null,
    // 🚀 核心修复：兼容老数据库里的 String 时间和新版本的 int 时间戳
    lastUpdated: _parseTimeSafely(json['lastUpdated']),
    dueDate: json['dueDate'] != null ? _parseTimeSafely(json['dueDate']) : null,
    createdAt: _parseTimeSafely(json['createdAt']),
  );
}