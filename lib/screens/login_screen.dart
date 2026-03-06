import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../storage_service.dart';
import 'home_dashboard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passController = TextEditingController();

  // 新增：验证码输入框
  final TextEditingController _codeController = TextEditingController();

  bool _isLoading = false;
  bool _isRegisterMode = false;

  // 新增：是否正在等待输入验证码
  bool _awaitingVerification = false;

  // 记录本地检测到的老用户名
  String? _legacyLocalUser;

  @override
  void initState() {
    super.initState();
    _checkLocalLegacyAccount();
  }

  @override
  void dispose() {
    _userController.dispose();
    _emailController.dispose();
    _passController.dispose();
    _codeController.dispose(); // 记得销毁
    super.dispose();
  }

  // 1. 检查是否有本地老用户数据
  void _checkLocalLegacyAccount() async {
    final prefs = await SharedPreferences.getInstance();
    String? legacyUser = prefs.getString('login_session');

    if (legacyUser != null && legacyUser.isNotEmpty) {
      setState(() {
        _legacyLocalUser = legacyUser;
        _userController.text = legacyUser;
        _isRegisterMode = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('检测到本地存档，注册后自动同步数据'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  // 2. 同步数据 (带安全鉴权的重构版)
  Future<void> _syncLocalDataToCloud(int targetUserId, String currentUsername) async {
    final String sourceUsername = _legacyLocalUser ?? currentUsername;
    print("同步数据: $sourceUsername -> ID: $targetUserId");

    try {
      final prefs = await SharedPreferences.getInstance();

      // 同步分数
      int localScore = prefs.getInt('${sourceUsername}_best_score') ?? 0;
      int localDuration = prefs.getInt('${sourceUsername}_best_duration') ?? 0;
      if (localScore > 0) {
        await ApiService.uploadScore(
          userId: targetUserId,
          username: currentUsername,
          score: localScore,
          duration: localDuration > 0 ? localDuration : 60,
        );
      }

      // 同步待办
      String? todosJson = prefs.getString('todos_$sourceUsername') ?? prefs.getString('todos');
      if (todosJson != null) {
        try {
          List<dynamic> localTodos = jsonDecode(todosJson);
          for (var item in localTodos) {
            String content = item['title'] ?? item['content'] ?? '';
            bool isDone = item['isDone'] ?? item['isCompleted'] ?? false;
            if (content.isNotEmpty && !isDone) {
              // 🚀 核心修复：为老数据统一补齐 createdDate 作为其唯一的身份 ID
              await ApiService.addTodo(
                targetUserId,
                content,
                isCompleted: isDone,
                timestamp: DateTime.now().toIso8601String(),
                createdDate: DateTime.now().toIso8601String(),
              );
            }
          }
        } catch (_) {}
      }

      // 同步倒计时
      String? countdownsJson = prefs.getString('countdowns_$sourceUsername') ?? prefs.getString('countdowns');
      if (countdownsJson != null) {
        try {
          List<dynamic> localCountdowns = jsonDecode(countdownsJson);
          for (var item in localCountdowns) {
            String title = item['title'] ?? '';
            String dateStr = item['date'] ?? item['targetTime'] ?? '';
            if (title.isNotEmpty && dateStr.isNotEmpty) {
              DateTime? targetTime = DateTime.tryParse(dateStr);
              if (targetTime != null && targetTime.isAfter(DateTime.now())) {
                // 🚀 核心修复：传递标准的时间字符串
                await ApiService.addCountdown(
                  targetUserId,
                  title,
                  targetTime,
                  DateTime.now().toIso8601String(),
                );
              }
            }
          }
        } catch (_) {}
      }
    } catch (e) {
      print("同步错误: $e");
    }
  }

  // 处理登录
  void _handleLogin() async {
    String email = _emailController.text.trim();
    String pass = _passController.text.trim();

    if (email.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入邮箱和密码')));
      return;
    }

    setState(() => _isLoading = true);
    var result = await ApiService.login(email, pass);

    if (!mounted) return;

    if (result['success'] == true) {
      final user = result['user'];
      final String token = result['token'] ?? ''; // 🚀 提取后端返回的安全 Token

      // 🚀 第 1 步：必须先保存并激活 Token，使后续的接口调用能够通过后端的安全鉴权
      await StorageService.saveLoginSession(user['username'], token: token);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('current_user_id', user['id']);

      // 🚀 第 2 步：此时调用同步方法，内部携带安全 Token，畅通无阻
      if (_legacyLocalUser != null) {
        await _syncLocalDataToCloud(user['id'], user['username']);
      }

      // 第 3 步：完成跳转
      _finalizeLoginAndNavigate(user['username']);
    } else {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('登录失败：${result['message']}')));
    }
  }

  // 处理注册 (改造为两步验证)
  void _handleRegister() async {
    String user = _userController.text.trim();
    String email = _emailController.text.trim();
    String pass = _passController.text.trim();

    // 基础校验
    if (!_awaitingVerification) {
      if (user.isEmpty || email.isEmpty || pass.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写完整注册信息')));
        return;
      }
    } else {
      if (_codeController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入邮箱收到的验证码')));
        return;
      }
    }

    setState(() => _isLoading = true);

    // 调用 API
    var regResult = await ApiService.register(
        user,
        email,
        pass,
        code: _awaitingVerification ? _codeController.text.trim() : null
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (regResult['success'] == true) {
      // 场景 1: 邮件发送成功，等待输入验证码
      if (regResult['require_verify'] == true) {
        setState(() {
          _awaitingVerification = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('验证码已发送至邮箱，请查收并输入')),
        );
      }
      // 场景 2: 验证码校验通过，注册完成 -> 自动登录
      else {
        _performAutoLoginAfterRegister(email, pass, user);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(regResult['message'] ?? '操作失败')),
      );
    }
  }

  // 辅助：注册成功后自动登录并同步
  void _performAutoLoginAfterRegister(String email, String pass, String username) async {
    setState(() => _isLoading = true);
    var loginResult = await ApiService.login(email, pass);

    if (loginResult['success'] == true) {
      final userInfo = loginResult['user'];
      final String token = loginResult['token'] ?? ''; // 🚀 提取 Token

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('注册成功，正在同步数据...')));

      // 🚀 核心防御：在触发 API 调用前，优先锁定并激活本地 Token 凭证
      await StorageService.saveLoginSession(username, token: token);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('current_user_id', userInfo['id']);

      // 同步老数据
      await _syncLocalDataToCloud(userInfo['id'], username);

      _finalizeLoginAndNavigate(username);
    } else {
      setState(() { _isLoading = false; _awaitingVerification = false; _isRegisterMode = false; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('注册成功，请手动登录')));
    }
  }

  // 辅助：完成界面跳转 (不再处理业务逻辑)
  void _finalizeLoginAndNavigate(String username) {
    if (!mounted) return;
    setState(() => _isLoading = false);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => HomeDashboard(username: username)),
    );
  }

  // 切换模式时重置状态
  void _toggleMode() {
    setState(() {
      _isRegisterMode = !_isRegisterMode;
      _awaitingVerification = false; // 重置验证状态
      _codeController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isRegisterMode ? (_awaitingVerification ? '输入验证码' : '注册并同步') : '登录')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                  _awaitingVerification ? Icons.mark_email_read : Icons.cloud_upload,
                  size: 80,
                  color: Theme.of(context).colorScheme.primary
              ),
              const SizedBox(height: 20),

              Text(
                  _awaitingVerification
                      ? "验证邮箱"
                      : (_isRegisterMode ? "账号升级" : "欢迎回来"),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)
              ),

              const SizedBox(height: 10),
              if (_legacyLocalUser != null && !_awaitingVerification && _isRegisterMode)
                Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(8)),
                  child: Text("本地存档: $_legacyLocalUser\n注册后自动同步", textAlign: TextAlign.center, style: TextStyle(color: Colors.amber.shade900, fontSize: 12)),
                ),

              // === 验证码模式 UI ===
              if (_awaitingVerification) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.0),
                  child: Text("我们向您的邮箱发送了一封包含验证码的邮件，请在下方输入：", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, letterSpacing: 5),
                  decoration: const InputDecoration(
                    hintText: '6位验证码',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: _handleRegister, // 这里复用方法，带上 code 提交
                    child: const Text("验证并完成注册"),
                  ),
                ),
                const SizedBox(height: 15),
                TextButton(
                  onPressed: () => setState(() => _awaitingVerification = false), // 返回修改邮箱
                  child: const Text("返回修改邮箱"),
                ),
              ]

              // === 普通登录/注册 UI ===
              else ...[
                if (_isRegisterMode) ...[
                  TextField(
                    controller: _userController,
                    decoration: const InputDecoration(labelText: '设置用户名', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
                  ),
                  const SizedBox(height: 15),
                ],

                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: '邮箱', border: OutlineInputBorder(), prefixIcon: Icon(Icons.email)),
                  enabled: !_awaitingVerification, // 验证时锁定
                ),
                const SizedBox(height: 15),

                TextField(
                  controller: _passController,
                  decoration: const InputDecoration(labelText: '密码', border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock)),
                  obscureText: true,
                  enabled: !_awaitingVerification,
                ),
                const SizedBox(height: 30),

                if (_isLoading)
                  const CircularProgressIndicator()
                else
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton(
                          onPressed: _isRegisterMode ? _handleRegister : _handleLogin,
                          child: Text(_isRegisterMode ? "获取验证码" : "登录"),
                        ),
                      ),
                      const SizedBox(height: 15),
                      TextButton(
                        onPressed: _toggleMode,
                        child: Text(_isRegisterMode ? "已有云端账号？去登录" : "新用户注册"),
                      ),
                    ],
                  )
              ],
            ],
          ),
        ),
      ),
    );
  }
}