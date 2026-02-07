import 'package:flutter/material.dart';
import '../models.dart';
import '../storage_service.dart';
import '../notification_service.dart';

// 新增：用于保存会话状态的类
class QuizSession {
  final List<Question> questions;
  int currentIndex;
  final DateTime startTime;
  final String username;

  QuizSession({
    required this.questions,
    required this.currentIndex,
    required this.startTime,
    required this.username,
  });
}

class QuizScreen extends StatefulWidget {
  final String username;
  const QuizScreen({super.key, required this.username});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  // 新增：静态变量，用于在页面销毁后依然保留状态（只要App没被杀掉）
  static QuizSession? _currentSession;

  List<Question> questions = [];
  int currentIndex = 0;
  final TextEditingController _answerController = TextEditingController();
  late DateTime startTime;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkAndLoadSession();
  }

  @override
  void dispose() {
    // 退出界面时不取消通知，也不清空 _currentSession，实现“暂存”
    _answerController.dispose();
    super.dispose();
  }

  // 新增：检查是否有可恢复的会话
  void _checkAndLoadSession() {
    // 如果有存档，且存档的用户是当前用户，则恢复
    if (_currentSession != null && _currentSession!.username == widget.username) {
      print("恢复上次的答题进度");
      setState(() {
        questions = _currentSession!.questions;
        currentIndex = _currentSession!.currentIndex;
        startTime = _currentSession!.startTime;
        isLoading = false;
      });

      // 恢复输入框内容（如果当前题已作答）
      if (questions[currentIndex].isAnswered && questions[currentIndex].userAnswer != null) {
        _answerController.text = questions[currentIndex].userAnswer.toString();
      }

      // 恢复通知显示
      _updateNotification();
    } else {
      // 没有存档，开始新测试
      startNewTest();
    }
  }

  void startNewTest() async {
    setState(() { isLoading = true; });

    // 获取配置
    var settings = await StorageService.getSettings();
    // 生成题目
    var newQuestions = QuestionGenerator.generate(10, settings);

    if (!mounted) return;

    if (newQuestions.isEmpty) {
      setState(() { isLoading = false; questions = []; });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('生成的题目为空，请检查设置范围是否合理')),
      );
      return;
    }

    DateTime now = DateTime.now();

    // 初始化状态
    setState(() {
      questions = newQuestions;
      currentIndex = 0;
      startTime = now;
      _answerController.clear();
      isLoading = false;
    });

    // 新增：保存到静态会话中
    _currentSession = QuizSession(
        questions: newQuestions,
        currentIndex: 0,
        startTime: now,
        username: widget.username
    );

    // 题目生成成功，立即发送第一题的通知
    _updateNotification();
  }

  // 辅助方法：发送当前题目的通知
  void _updateNotification() {
    if (questions.isEmpty || currentIndex >= questions.length) return;

    Question q = questions[currentIndex];
    String displayOp = q.operatorSymbol;
    if (displayOp == '*') displayOp = '×';
    if (displayOp == '/') displayOp = '÷';

    NotificationService.updateQuizNotification(
      currentIndex: currentIndex,
      totalCount: questions.length,
      questionText: "${q.num1} $displayOp ${q.num2} = ?",
      isOver: false,
    );
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

      // 新增：同步进度到静态会话
      if (_currentSession != null) {
        _currentSession!.currentIndex = currentIndex;
      }

      // 切换到下一题，更新通知
      _updateNotification();
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

      // 新增：同步进度到静态会话
      if (_currentSession != null) {
        _currentSession!.currentIndex = currentIndex;
      }

      // 返回上一题，更新通知
      _updateNotification();
    }
  }

  void _finishTest() async {
    // 答题结束，清空静态会话，这样下次进来就是新的一局
    _currentSession = null;

    DateTime endTime = DateTime.now();
    int duration = endTime.difference(startTime).inSeconds;
    int score = 0;
    String details = "";

    for (var q in questions) {
      if (q.checkAnswer()) score += 10;
      details += "${q.toString()}\n";
    }

    // 答题结束，发送结束通知（根据 NotificationService 的逻辑，isOver: true 会自动取消通知）
    NotificationService.updateQuizNotification(
      currentIndex: questions.length,
      totalCount: questions.length,
      questionText: "Done",
      isOver: true,
      score: score,
    );

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
              Navigator.pop(ctx); // 关掉 Dialog
              Navigator.pop(context); // 退出 QuizScreen
            },
            child: const Text("返回主菜单"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              startNewTest(); // 重新开始，这会创建新的 Session
            },
            child: const Text("再来一次"),
          )
        ],
      ),
    );
  }

  // 手动放弃考试（如果需要的话，可以在 AppBar 加个按钮调用这个）
  void _quitTest() {
    _currentSession = null;
    NotificationService.cancelNotification();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text("准备中...")),
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
      appBar: AppBar(
        title: Text("第 ${currentIndex + 1} / 10 题"),
        // 可选：添加一个强制重置的按钮，以防用户想从头开始
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "重新开始",
            onPressed: () async {
              bool? confirm = await showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text("重新开始？"),
                  content: const Text("当前进度将丢失。"),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("取消")),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("确定")),
                  ],
                ),
              );
              if (confirm == true) {
                startNewTest();
              }
            },
          )
        ],
      ),
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