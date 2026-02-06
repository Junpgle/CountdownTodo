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
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    startNewTest();
  }

  void startNewTest() async {
    setState(() { isLoading = true; });

    // 获取配置
    var settings = await StorageService.getSettings();
    // 生成题目
    var newQuestions = QuestionGenerator.generate(10, settings);

    setState(() {
      questions = newQuestions;
      currentIndex = 0;
      startTime = DateTime.now();
      _answerController.clear();
      isLoading = false;
    });

    if (questions.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('生成的题目为空，请检查设置范围是否合理')),
      );
    }
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

    await StorageService.saveHistory(widget.username, score, duration, details);
    await StorageService.updateLeaderboard(widget.username, score, duration);

    String comment;
    if (score >= 90) {
      comment = "SMART";
    } else if (score >= 80) {comment = "GOOD";}
    else if (score >= 70) {comment = "OK";}
    else if (score >= 60) {comment = "PASS";}
    else {comment = "TRY AGAIN";}

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("测试完成"),
        content: Text("得分: $score\n用时: $duration秒\n评价: $comment"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text("返回主菜单"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              startNewTest();
            },
            child: const Text("再来一次"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text("生成题目中...")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("错误")),
        body: const Center(child: Text("无法生成题目，请调整设置范围")),
      );
    }

    Question q = questions[currentIndex];
    // 显示更友好的运算符号
    String displayOp = q.operatorSymbol;
    if (displayOp == '*') displayOp = '×';
    if (displayOp == '/') displayOp = '÷';

    return Scaffold(
      appBar: AppBar(title: Text("第 ${currentIndex + 1} / 10 题")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const Spacer(),
            Text(
              "${q.num1} $displayOp ${q.num2} = ?",
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