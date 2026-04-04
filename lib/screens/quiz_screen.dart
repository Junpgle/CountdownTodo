import 'package:flutter/material.dart';
import '../models.dart';
import '../storage_service.dart';
import '../services/notification_service.dart';

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

class _QuizScreenState extends State<QuizScreen>
    with SingleTickerProviderStateMixin {
  // 新增：静态变量，用于在页面销毁后依然保留状态（只要App没被杀掉）
  static QuizSession? _currentSession;

  List<Question> questions = [];
  int currentIndex = 0;
  final TextEditingController _answerController = TextEditingController();
  late DateTime startTime;
  bool isLoading = true;

  // 动画相关
  late PageController _pageController;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  bool? _lastAnswerCorrect; // null=无反馈, true=正确, false=错误
  Color _feedbackColor = Colors.transparent;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
    _checkAndLoadSession();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _shakeController.dispose();
    _answerController.dispose();
    super.dispose();
  }

  // 新增：检查是否有可恢复的会话
  void _checkAndLoadSession() {
    // 如果有存档，且存档的用户是当前用户，则恢复
    if (_currentSession != null &&
        _currentSession!.username == widget.username) {
      print("恢复上次的答题进度");
      setState(() {
        questions = _currentSession!.questions;
        currentIndex = _currentSession!.currentIndex;
        startTime = _currentSession!.startTime;
        isLoading = false;
      });

      // 恢复输入框内容（如果当前题已作答）
      if (questions[currentIndex].isAnswered &&
          questions[currentIndex].userAnswer != null) {
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
    setState(() {
      isLoading = true;
    });

    // 获取配置
    var settings = await StorageService.getSettings();
    // 生成题目
    var newQuestions = QuestionGenerator.generate(10, settings);

    if (!mounted) return;

    if (newQuestions.isEmpty) {
      setState(() {
        isLoading = false;
        questions = [];
      });
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
      _lastAnswerCorrect = null;
      _feedbackColor = Colors.transparent;
    });

    _pageController.jumpToPage(0);

    // 新增：保存到静态会话中
    _currentSession = QuizSession(
        questions: newQuestions,
        currentIndex: 0,
        startTime: now,
        username: widget.username);

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

    bool isCorrect = int.tryParse(_answerController.text) ==
        questions[currentIndex].correctAnswer;

    setState(() {
      questions[currentIndex].userAnswer = int.tryParse(_answerController.text);
      questions[currentIndex].isAnswered = true;
      _lastAnswerCorrect = isCorrect;
      _feedbackColor = isCorrect
          ? Colors.green.withOpacity(0.3)
          : Colors.red.withOpacity(0.3);
    });

    if (isCorrect) {
      // 正确：绿色闪烁
      _playCorrectFlash();
    } else {
      // 错误：红色抖动
      _shakeController.forward(from: 0);
    }

    // 延迟后自动切换到下一题
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      if (currentIndex < questions.length - 1) {
        _goToNextQuestion();
      } else {
        _finishTest();
      }
    });
  }

  void _playCorrectFlash() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _feedbackColor = Colors.green.withOpacity(0.1);
      });
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      setState(() {
        _feedbackColor = Colors.transparent;
      });
    });
  }

  void _goToNextQuestion() {
    int nextIndex = currentIndex + 1;
    setState(() {
      currentIndex = nextIndex;
      _answerController.clear();
      _lastAnswerCorrect = null;
      _feedbackColor = Colors.transparent;
    });

    _pageController.animateToPage(
      currentIndex,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );

    // 新增：同步进度到静态会话
    if (_currentSession != null) {
      _currentSession!.currentIndex = currentIndex;
    }

    // 切换到下一题，更新通知
    _updateNotification();
  }

  void _prevQuestion() {
    if (currentIndex > 0) {
      setState(() {
        currentIndex--;
        if (questions[currentIndex].isAnswered) {
          _answerController.text =
              questions[currentIndex].userAnswer.toString();
        } else {
          _answerController.clear();
        }
        _lastAnswerCorrect = null;
        _feedbackColor = Colors.transparent;
      });

      _pageController.animateToPage(
        currentIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );

      // 新增：同步进度到静态会话
      if (_currentSession != null) {
        _currentSession!.currentIndex = currentIndex;
      }

      // 返回上一题，更新通知
      _updateNotification();
    }
  }

  void _onPageChanged(int page) {
    setState(() {
      currentIndex = page;
      if (questions[currentIndex].isAnswered) {
        _answerController.text = questions[currentIndex].userAnswer.toString();
      } else {
        _answerController.clear();
      }
      _lastAnswerCorrect = null;
      _feedbackColor = Colors.transparent;
    });

    if (_currentSession != null) {
      _currentSession!.currentIndex = currentIndex;
    }

    _updateNotification();
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
    } else if (score >= 80) {
      comment = "GOOD";
    } else if (score >= 70) {
      comment = "OK";
    } else if (score >= 60) {
      comment = "PASS";
    } else {
      comment = "TRY AGAIN";
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("测试完成"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<int>(
              tween: IntTween(begin: 0, end: score),
              duration: const Duration(milliseconds: 1500),
              curve: Curves.easeOut,
              builder: (context, value, child) {
                return Text(
                  "得分: $value",
                  style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue),
                );
              },
            ),
            const SizedBox(height: 8),
            Text("用时: $duration秒"),
            const SizedBox(height: 4),
            Text("评价: $comment",
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
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

  Widget _buildQuestionCard(Question q, int index) {
    String displayOp = q.operatorSymbol;
    if (displayOp == '*') displayOp = '×';
    if (displayOp == '/') displayOp = '÷';

    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        double shakeOffset = 0;
        if (_lastAnswerCorrect == false && _shakeController.isAnimating) {
          shakeOffset =
              (_shakeAnimation.value * 10) * (index == currentIndex ? 1 : 0);
          if (shakeOffset.abs() < 0.5) shakeOffset = 0;
        }
        return Transform.translate(
          offset: Offset(shakeOffset, 0),
          child: child,
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: _feedbackColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _lastAnswerCorrect != null && index == currentIndex
                ? (_lastAnswerCorrect! ? Colors.green : Colors.red)
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: Center(
          child: Text(
            "${q.num1} $displayOp ${q.num2} = ?",
            style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
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

    return Scaffold(
      appBar: AppBar(
        title: Text("第 ${currentIndex + 1} / ${questions.length} 题"),
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
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text("取消")),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text("确定")),
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
            // 进度条
            TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: 0,
                end: questions.isNotEmpty
                    ? (currentIndex + 1) / questions.length
                    : 0,
              ),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
              builder: (context, value, child) {
                return Column(
                  children: [
                    LinearProgressIndicator(
                      value: value,
                      backgroundColor: Colors.grey[200],
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.blue),
                      minHeight: 8,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "进度: ${currentIndex + 1} / ${questions.length}",
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            // PageView 题目区域
            Expanded(
              flex: 2,
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                itemCount: questions.length,
                itemBuilder: (context, index) {
                  return _buildQuestionCard(questions[index], index);
                },
              ),
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
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white),
                  child: Text(
                      currentIndex == questions.length - 1 ? "提交试卷" : "下一题"),
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
