import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart'; // 新增 UUID 用于老数据迁移
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

  final TextEditingController _codeController = TextEditingController();

  bool _isLoading = false;
  bool _isRegisterMode = false;
  bool _awaitingVerification = false;
  String? _legacyLocalUser;
  String _serverChoice = 'aliyun';

  @override
  void initState() {
    super.initState();
    _checkLocalLegacyAccount();
    _loadServerChoice();
  }

  void _loadServerChoice() async {
    final choice = await StorageService.getServerChoice();
    if (mounted) setState(() => _serverChoice = choice);
  }

  void _onServerChoiceChanged(String? val) async {
    if (val == null) return;
    setState(() => _serverChoice = val);
    ApiService.setServerChoice(val);
    await StorageService.saveServerChoice(val);
  }

  @override
  void dispose() {
    _userController.dispose();
    _emailController.dispose();
    _passController.dispose();
    _codeController.dispose();
    super.dispose();
  }

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

  // 🚀 核心重构：将原本的单次调用替换为组装成 Delta Sync 数据包批量上传
  Future<void> _syncLocalDataToCloud(int targetUserId, String currentUsername) async {
    final String sourceUsername = _legacyLocalUser ?? currentUsername;
    print("同步老旧存档数据: $sourceUsername -> ID: $targetUserId");

    try {
      final prefs = await SharedPreferences.getInstance();
      final String deviceId = prefs.getString('app_device_uuid') ?? const Uuid().v4();

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

      List<Map<String, dynamic>> dirtyTodos = [];
      List<Map<String, dynamic>> dirtyCountdowns = [];

      // 提取老待办并组装成增量同步包
      String? todosJson = prefs.getString('todos_$sourceUsername') ?? prefs.getString('todos');
      if (todosJson != null) {
        try {
          List<dynamic> localTodos = jsonDecode(todosJson);
          for (var item in localTodos) {
            String content = item['title'] ?? item['content'] ?? '';
            bool isDone = item['isDone'] ?? item['isCompleted'] ?? false;
            if (content.isNotEmpty && !isDone) {
              int nowMs = DateTime.now().millisecondsSinceEpoch;
              dirtyTodos.add({
                'id': const Uuid().v4(),
                'content': content,
                'is_completed': isDone ? 1 : 0,
                'is_deleted': 0,
                'version': 1,
                'updated_at': nowMs,
                'created_at': nowMs,
                'device_id': deviceId
              });
            }
          }
        } catch (_) {}
      }

      // 提取老倒计时并组装成增量同步包
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
                int nowMs = DateTime.now().millisecondsSinceEpoch;
                dirtyCountdowns.add({
                  'id': const Uuid().v4(),
                  'title': title,
                  'target_time': targetTime.millisecondsSinceEpoch,
                  'is_deleted': 0,
                  'version': 1,
                  'updated_at': nowMs,
                  'created_at': nowMs,
                  'device_id': deviceId
                });
              }
            }
          }
        } catch (_) {}
      }

      // 如果有数据，直接发往 Delta Sync 接口完成上传
      if (dirtyTodos.isNotEmpty || dirtyCountdowns.isNotEmpty) {
        await ApiService.postDeltaSync(
          userId: targetUserId,
          lastSyncTime: 0,
          deviceId: deviceId,
          todosChanges: dirtyTodos,
          countdownsChanges: dirtyCountdowns,
        );
      }

    } catch (e) {
      print("老数据迁移错误: $e");
    }
  }

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
      final String token = result['token'] ?? '';

      await StorageService.saveLoginSession(user['username'], token: token);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('current_user_id', user['id']);

      if (_legacyLocalUser != null) {
        await _syncLocalDataToCloud(user['id'], user['username']);
      }

      _finalizeLoginAndNavigate(user['username']);
    } else {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('登录失败：${result['message']}')));
    }
  }

  void _handleRegister() async {
    String user = _userController.text.trim();
    String email = _emailController.text.trim();
    String pass = _passController.text.trim();

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

    var regResult = await ApiService.register(
        user,
        email,
        pass,
        code: _awaitingVerification ? _codeController.text.trim() : null
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (regResult['success'] == true) {
      if (regResult['require_verify'] == true) {
        setState(() {
          _awaitingVerification = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('验证码已发送至邮箱，请查收并输入')),
        );
      }
      else {
        _performAutoLoginAfterRegister(email, pass, user);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(regResult['message'] ?? '操作失败')),
      );
    }
  }

  void _performAutoLoginAfterRegister(String email, String pass, String username) async {
    setState(() => _isLoading = true);
    var loginResult = await ApiService.login(email, pass);

    if (loginResult['success'] == true) {
      final userInfo = loginResult['user'];
      final String token = loginResult['token'] ?? '';

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('注册成功，正在同步数据...')));

      await StorageService.saveLoginSession(username, token: token);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('current_user_id', userInfo['id']);

      await _syncLocalDataToCloud(userInfo['id'], username);

      _finalizeLoginAndNavigate(username);
    } else {
      setState(() { _isLoading = false; _awaitingVerification = false; _isRegisterMode = false; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('注册成功，请手动登录')));
    }
  }

  void _finalizeLoginAndNavigate(String username) {
    if (!mounted) return;
    setState(() => _isLoading = false);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => HomeDashboard(username: username)),
    );
  }

  void _toggleMode() {
    setState(() {
      _isRegisterMode = !_isRegisterMode;
      _awaitingVerification = false;
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
                    onPressed: _handleRegister,
                    child: const Text("验证并完成注册"),
                  ),
                ),
                const SizedBox(height: 15),
                TextButton(
                  onPressed: () => setState(() => _awaitingVerification = false),
                  child: const Text("返回修改邮箱"),
                ),
              ]
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
                  enabled: !_awaitingVerification,
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
                      const SizedBox(height: 30),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.cloud_queue, size: 18, color: Colors.grey),
                          const SizedBox(width: 6),
                          const Text('服务器: ', style: TextStyle(color: Colors.grey, fontSize: 13)),
                          DropdownButton<String>(
                            value: _serverChoice,
                            underline: const SizedBox(),
                            style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 13),
                            items: const [
                              DropdownMenuItem(value: 'cloudflare', child: Text('Cloudflare (推荐)')),
                              DropdownMenuItem(value: 'aliyun', child: Text('阿里云ECS')),
                            ],
                            onChanged: _onServerChoiceChanged,
                          ),
                        ],
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