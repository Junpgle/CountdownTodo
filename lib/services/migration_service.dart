import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../storage_service.dart';
import '../models.dart';
import 'api_service.dart';
import 'course_service.dart';

/// 临时 HTTP 覆盖类，用于在迁移期间忽略可能存在的 SSL 证书问题
class _IgnoreSslHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

class MigrationService {
  /// 一键迁移：从旧 Cloudflare D1 拉取数据，推送到新阿里云 ECS。
  static Future<void> runMigration({
    required BuildContext context,
    required String oldUrl,
    required String newUrl,
    required String email,
    required String password,
    required Function(String) onProgress,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // 🌟 防弹机制 1：临时忽略所有 SSL 证书问题
    HttpOverrides.global = _IgnoreSslHttpOverrides();

    // 🌟 防弹机制 2：自动纠正手滑填错的 https 协议
    // 很多时候阿里云 ECS 没配域名和证书，直接填 https://IP:8082 必报 HandshakeException
    if (newUrl.startsWith('https://') && (newUrl.contains(':8082') || RegExp(r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}').hasMatch(newUrl))) {
      newUrl = newUrl.replaceFirst('https://', 'http://');
      onProgress("⚠️ 检测到新服务器为裸 IP 或特定端口，已自动修正为 http:// 协议以防止握手失败...");
    }

    try {
      // ==========================================
      // 1. 登录旧服务器 (Cloudflare D1)
      // ==========================================
      onProgress("正在连接旧服务器 (Cloudflare D1)...");
      ApiService.setBaseUrlOverride(oldUrl);

      final loginRes = await ApiService.login(email, password);
      if (loginRes['success'] != true) {
        throw Exception("旧服务器登录失败: ${loginRes['message'] ?? loginRes['error']}");
      }
      onProgress("✅ 登录旧服务器成功，开始拉取完整数据...");

      final Map<String, dynamic> user = loginRes['user'] is Map<String, dynamic> ? loginRes['user'] : {};
      final int oldUserId = user['id'] ?? user['user_id'] ?? 0;
      final String oldToken = loginRes['token'] ?? '';
      final String username = user['username'] ?? '';
      final String tier = user['tier'] ?? 'free';
      final int? semesterStart = user['semester_start'];
      final int? semesterEnd = user['semester_end'];

      if (oldUserId == 0) throw Exception("无法获取旧服务器的用户 ID");

      // 临时存入旧环境的 Token，供后续 fetch 使用
      await prefs.setString('auth_token', oldToken);
      ApiService.setToken(oldToken);

      // ==========================================
      // 2. 从旧环境拉取数据并存入本地
      // ==========================================
      onProgress("📥 拉取旧待办事项...");
      final todosRaw = await ApiService.fetchTodos(oldUserId);
      final todos = todosRaw.map((e) => TodoItem.fromJson(e)).toList();
      await StorageService.saveTodos(oldUserId.toString(), todos);

      onProgress("📥 拉取旧倒计时...");
      final countdownsRaw = await ApiService.fetchCountdowns(oldUserId);
      final countdowns = countdownsRaw.map((e) => CountdownItem.fromJson(e)).toList();
      await StorageService.saveCountdowns(oldUserId.toString(), countdowns);

      onProgress("📥 拉取时间记录...");
      final timeLogsRaw = await ApiService.fetchTimeLogs(oldUserId);
      final timeLogs = timeLogsRaw.map((e) => TimeLogItem.fromJson(e)).toList();
      await StorageService.saveTimeLogs(oldUserId.toString(), timeLogs);

      onProgress("📥 拉取专注历史与设置...");
      List<dynamic> pomodoroRecords = [];
      try { pomodoroRecords = await ApiService.fetchPomodoroRecords(oldUserId); } catch (_) {}

      List<dynamic> pomodoroTags = [];
      try {
        pomodoroTags = await ApiService.fetchPomodoroTags(oldUserId);
        await StorageService.savePomodoroTags(oldUserId.toString(), pomodoroTags.cast<Map<String,dynamic>>());
      } catch (_) {}

      onProgress("📥 拉取课表数据...");
      List<dynamic> courses = [];
      try { courses = await ApiService.fetchCourses(oldUserId); } catch (_) {}

      if (courses.isNotEmpty) {
        final courseItems = courses.map((c) => CourseItem(
          courseName: c['course_name'] ?? '',
          roomName: c['room_name'] ?? '',
          teacherName: c['teacher_name'] ?? '',
          startTime: (c['start_time'] as num?)?.toInt() ?? 0,
          endTime: (c['end_time'] as num?)?.toInt() ?? 0,
          weekday: (c['weekday'] as num?)?.toInt() ?? 1,
          weekIndex: (c['week_index'] as num?)?.toInt() ?? 1,
          lessonType: c['lesson_type'] ?? '',
          date: c['date'] ?? '',
        )).toList();
        await CourseService.saveCourses(courseItems);
      }

      // ==========================================
      // 3. 切到新阿里云服务器，注册/接管账号
      // ==========================================
      onProgress("🔄 数据拉取完毕，正在连接阿里云新服务器...");
      ApiService.setBaseUrlOverride(newUrl);

      Map<String, dynamic> registerRes = {};

      // 🌟 增强方案：先尝试直接登录（防止用户在新服务器已经注册过）
      onProgress("🔍 正在检查新服务器是否已有您的账号...");
      try {
        final loginCheck = await ApiService.login(email, password);
        if (loginCheck['success'] == true) {
          onProgress("✅ 新服务器已有您的账号，直接关联...");
          registerRes = loginCheck;
        }
      } catch (_) {
        // 忽略登录报错，继续走下方的迁移注册流程
      }

      // 如果未登录成功，调用专属迁移注册接口
      if (registerRes.isEmpty || registerRes['success'] != true) {
        onProgress("🔐 正在于新服务器同步您的账户凭证...");
        registerRes = await ApiService.migrationRegister(
          email: email,
          username: username,
          password: password,
          tier: tier,
          semesterStart: semesterStart,
          semesterEnd: semesterEnd,
        );
      }

      if (registerRes['success'] != true) {
        final errorMsg = registerRes['message'] ?? registerRes['error'] ?? '未知错误';

        throw Exception("新服务器账号交接失败: $errorMsg");
      }

      final String newToken = registerRes['token'] ?? '';
      // 兼容两种返回格式
      final int newUserId = registerRes['user_id'] ?? registerRes['user']?['id'] ?? 0;

      if (newUserId == 0) throw Exception("无法分配新服务器的用户 ID");

      // 覆盖本地存的凭证
      await prefs.setString('auth_token', newToken);
      await prefs.setInt('current_user_id', newUserId);
      ApiService.setToken(newToken);

      // ==========================================
      // ⚠️ 关键步骤：数据归属权转换 (UserId 映射)
      // ==========================================
      if (oldUserId != newUserId) {
        onProgress("⚙️ 正在转换数据归属权 (ID: $oldUserId ➡️ $newUserId)...");
        // 如果旧 ID 是 15，新 ID 是 2，必须把本地存的 key 从 15 改成 2，否则 syncData 找不到数据！
        await _migrateLocalDataUserId(oldUserId.toString(), newUserId.toString());
      }

      onProgress("🚀 凭证同步成功！准备向阿里云上传数据...");

      // ==========================================
      // 4. 全量上传数据到新服务器
      // ==========================================
      onProgress("📤 上传待办事项、倒计时与时间记录...");
      await StorageService.syncData(newUserId.toString(), forceFullSync: true);

      if (courses.isNotEmpty) {
        onProgress("📤 上传课表...");
        await CourseService.syncCoursesToCloud(newUserId);
      }

      if (pomodoroRecords.isNotEmpty) {
        onProgress("📤 上传专注记录...");
        // 发送前必须把记录里的 oldUserId 强制替换为 newUserId
        final updatedRecords = pomodoroRecords.cast<Map<String,dynamic>>().map((r) {
          r['user_id'] = newUserId;
          return r;
        }).toList();
        await ApiService.uploadPomodoroRecords(updatedRecords);
      }

      onProgress("✅ 所有数据已完美迁移至阿里云！");

    } catch (e) {
      onProgress("❌ 迁移中断: ${e.toString()}");
      rethrow; // 抛出异常让 UI 层可以弹窗提示
    } finally {
      // 无论成功失败，恢复动态选择的逻辑，防止后续请求全发错地方
      ApiService.clearBaseUrlOverride();
      // 恢复 HTTP SSL 限制，保证后续业务安全性
      HttpOverrides.global = null;
    }
  }

  /// 内部辅助函数：将本地通过 SharedPreferences 存储的旧用户数据，转移给新用户 ID
  static Future<void> _migrateLocalDataUserId(String oldId, String newId) async {
    final prefs = await SharedPreferences.getInstance();
    final keysToMigrate = ['todos_$oldId', 'countdowns_$oldId', 'time_logs_$oldId', 'pomodoro_tags_$oldId'];

    for (String oldKey in keysToMigrate) {
      if (prefs.containsKey(oldKey)) {
        String newKey = oldKey.replaceAll('_$oldId', '_$newId');
        String data = prefs.getString(oldKey)!;
        await prefs.setString(newKey, data);
        await prefs.remove(oldKey); // 转移后清理旧数据
      }
    }
  }
}