import 'package:flutter/material.dart';
import '../models.dart';
import '../Storage_Service.dart';

class QuizScreen extends StatefulWidget {
  final String username;
  const QuizScreen({super.key, required this.username});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  List<Question> questions = [];
  int currentIndex = 0;
  final TextEditingController _answerController = TextEditingController();
  late DateTime startTime;
  bool isFinished = false;

  @override
  void initState() {
    super.initState();
    startNewTest();
  }

  void startNewTest() {
    setState(() {
      questions = QuestionGenerator.generate(10);
      currentIndex = 0;
      isFinished = false;
      startTime = DateTime.now();
      _answerController.clear();
    });
  }

  void _submitAnswer() {
    if (_answerController.text.isEmpty) return;

    setState(() {
      questions[currentIndex].userAnswer = int.tryParse(_answerController.text);
      questions[currentIndex].isAnswered = true;
    });

    if (currentIndex < questions.length - 1) {
      setState(() {
        currentIndex++;
        _answerController.clear();
      });
    } else {
      _finishTest();
    }
  }

  void _prevQuestion() {
    if (currentIndex > 0) {
      setState(() {
        currentIndex--;
        // 如果题目已回答，回填答案
        if (questions[currentIndex].isAnswered) {
          _answerController.text = questions[currentIndex].userAnswer.toString();
        } else {
          _answerController.clear();
        }
      });
    }
  }

  void _finishTest() async {
    DateTime endTime = DateTime.now();
    int duration = endTime.difference(startTime).inSeconds;
    int score = 0;
    String details = "";

    for (var q in questions) {
      if (q.checkAnswer()) score += 10;
      details += "${q.toString()}\n";
    }

    // 保存数据
    await StorageService.saveHistory(widget.username, score, duration, details);
    await StorageService.updateLeaderboard(widget.username, score, duration);

    String comment;
    if (score >= 90) comment = "SMART";
    else if (score >= 80) comment = "GOOD";
    else if (score >= 70) comment = "OK";
    else if (score >= 60) comment = "PASS";
    else comment = "TRY AGAIN";

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("测试完成"),
        content: Text("得分: $score\n用时: ${duration}秒\n评价: $comment"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx); // 关弹窗
              Navigator.pop(context); // 退出答题页
            },
            child: const Text("返回主菜单"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              startNewTest(); // 再来一次
            },
            child: const Text("再来一次"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Question q = questions[currentIndex];

    return Scaffold(
      appBar: AppBar(title: Text("第 ${currentIndex + 1} / 10 题")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const Spacer(),
            Text(
              "${q.num1} ${q.operatorSymbol} ${q.num2} = ?",
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            TextField(
              controller: _answerController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24),
              decoration: const InputDecoration(
                hintText: "请输入答案",
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submitAnswer(),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: currentIndex == 0 ? null : _prevQuestion,
                  child: const Text("上一题"),
                ),
                ElevatedButton(
                  onPressed: _submitAnswer,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                  child: Text(currentIndex == questions.length - 1 ? "提交试卷" : "下一题"),
                ),
              ],
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}