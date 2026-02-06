import 'dart:math';

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

  // 验证答案
  bool checkAnswer() {
    return isAnswered && userAnswer == correctAnswer;
  }

  // 转换为字符串便于存储或显示
  @override
  String toString() {
    String result = "$num1 $operatorSymbol $num2 = ${userAnswer ?? '?'}";
    if (isAnswered) {
      result += (userAnswer == correctAnswer) ? " (正确)" : " (错误, 正解: $correctAnswer)";
    } else {
      result += " (未作答)";
    }
    return result;
  }
}

class QuestionGenerator {
  static List<Question> generate(int count) {
    List<Question> questions = [];
    Random rng = Random();

    int i = 0;
    while (i < count) {
      int n1 = rng.nextInt(50); // 0-49
      int n2 = rng.nextInt(50);
      bool isPlus = rng.nextBool();
      String op = isPlus ? '+' : '-';
      int ans;

      if (isPlus) {
        ans = n1 + n2;
        if (ans > 50) continue; // 结果不能超过50
      } else {
        if (n1 < n2) {
          int temp = n1;
          n1 = n2;
          n2 = temp;
        }
        ans = n1 - n2;
      }

      questions.add(Question(
        num1: n1,
        num2: n2,
        operatorSymbol: op,
        correctAnswer: ans,
      ));
      i++;
    }
    return questions;
  }
}