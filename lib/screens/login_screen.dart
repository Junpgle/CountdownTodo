import 'package:flutter/material.dart';
import '/Storage_Service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();

  void _handleLogin() async {
    String user = _userController.text.trim();
    String pass = _passController.text.trim();
    if (user.isEmpty || pass.isEmpty) return;

    bool success = await StorageService.login(user, pass);
    if (success) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => HomeScreen(username: user)),
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('登录失败：用户名不存在或密码错误')),
      );
    }
  }

  void _handleRegister() async {
    String user = _userController.text.trim();
    String pass = _passController.text.trim();
    if (user.isEmpty || pass.isEmpty) return;

    bool success = await StorageService.register(user, pass);
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('注册成功，请登录')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('注册失败：用户名已存在')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('小学生数学测验 - 登录')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("数学测验系统", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 30),
            TextField(
              controller: _userController,
              decoration: const InputDecoration(labelText: '用户名', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _passController,
              decoration: const InputDecoration(labelText: '密码', border: OutlineInputBorder()),
              obscureText: true,
            ),
            const SizedBox(height: 30),
            Row(
              children: [
                Expanded(child: ElevatedButton(onPressed: _handleLogin, child: const Text("登录"))),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton(onPressed: _handleRegister, child: const Text("注册"))),
              ],
            )
          ],
        ),
      ),
    );
  }
}