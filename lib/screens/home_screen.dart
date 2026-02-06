import 'package:flutter/material.dart';
import 'quiz_screen.dart';
import 'other_screens.dart';
import 'login_screen.dart';

class HomeScreen extends StatelessWidget {
  final String username;
  const HomeScreen({super.key, required this.username});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("数学测验系统"),
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            onPressed: () {
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
            },
          )
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("欢迎, $username", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 40),

              _MenuButton(
                text: "开始答题",
                color: Colors.blue,
                icon: Icons.play_arrow,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => QuizScreen(username: username))),
              ),

              _MenuButton(
                text: "排行榜",
                color: Colors.red,
                icon: Icons.leaderboard,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LeaderboardScreen())),
              ),

              _MenuButton(
                text: "历史记录",
                color: Colors.purple,
                icon: Icons.history,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => HistoryScreen(username: username))),
              ),

              _MenuButton(
                text: "切换账号",
                color: Colors.orange,
                icon: Icons.switch_account,
                onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const _MenuButton({required this.text, required this.color, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: ElevatedButton.icon(
        icon: Icon(icon, color: Colors.white),
        label: Text(text, style: const TextStyle(fontSize: 18, color: Colors.white)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: onTap,
      ),
    );
  }
}