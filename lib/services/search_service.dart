import 'package:flutter/material.dart';
import '../models.dart';
import '../screens/about_screen.dart';
import '../screens/team_management_screen.dart';
import '../storage_service.dart';
import 'database_helper.dart';
import 'package:intl/intl.dart';
import '../screens/home_settings_screen.dart';
import '../screens/animation_settings_page.dart';
import '../screens/settings/wallpaper_settings_page.dart';
import '../screens/settings/llm_config_page.dart';

import '../screens/band_sync_screen.dart';
import '../screens/settings/lan_sync_screen.dart';
import '../screens/settings/notification_settings_page.dart';
import '../utils/page_transitions.dart';
import '../widgets/todo_section_widget.dart';
import '../screens/pomodoro_screen.dart';
import '../screens/time_log_screen.dart';


class SearchResultWithScore {
  final SearchResult result;
  final int score;
  SearchResultWithScore(this.result, this.score);
}

class SearchService {
  static final SearchService instance = SearchService._();
  SearchService._();

  int _latestSearchId = 0;
  bool _isWarmedUp = false;

  Future<void> warmup() async {
    if (_isWarmedUp) return;
    _isWarmedUp = true;
    debugPrint("🔍 SearchService: Index warmup completed.");
  }

  // --- 静态设置项索引库 ---
  static final List<SearchResult> _staticSettings = [
    SearchResult(
      id: 'setting_login',
      title: '账户登录 / 注册',
      subtitle: '管理 Uni-Sync 云同步账号',
      icon: Icons.account_circle,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 账号',
      extraData: {'route': '/login'},
    ),
    SearchResult(
      id: 'setting_server_choice',
      title: '云端线路选择 (阿里云/Cloudflare)',
      subtitle: '切换数据同步服务器',
      icon: Icons.cloud_queue,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 账号',
      extraData: {'route': '/settings', 'target': 'server_choice'},
    ),
    SearchResult(
      id: 'setting_lan_sync',
      title: '局域网同步 / 离线同步',
      subtitle: '在同一局域网内直接传输数据',
      icon: Icons.sync_alt,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 高级',
      extraData: {'route': '/settings/lan_sync'},
    ),
    SearchResult(
      id: 'setting_animation',
      title: '动画效果 / 界面动效',
      subtitle: '调整应用转场与视觉效果',
      icon: Icons.animation,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 视觉',
      extraData: {'route': '/settings/animation'},
    ),
    SearchResult(
      id: 'setting_wallpaper',
      title: '壁纸设置 / 背景图片',
      subtitle: '自定义首页背景',
      icon: Icons.image,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 视觉',
      extraData: {'route': '/settings/wallpaper'},
    ),
    SearchResult(
      id: 'setting_llm_config',
      title: 'AI 助手配置 / LLM 设置',
      subtitle: '配置智能助手的 API 密钥与模型',
      icon: Icons.auto_awesome,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 高级',
      extraData: {'route': '/settings/llm_config'},
    ),
    SearchResult(
      id: 'setting_cache_clean',
      title: '清理缓存 / 存储空间',
      subtitle: '删除临时文件并重算缓存大小',
      icon: Icons.cleaning_services,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 高级',
      extraData: {'route': '/settings', 'target': 'cache'},
    ),
    SearchResult(
      id: 'setting_band_sync',
      title: '手环同步 / 小米手环',
      subtitle: '与小米手环同步待办、课程、倒计时',
      icon: Icons.watch,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 高级',
      extraData: {'route': '/settings/band_sync'},
    ),
    SearchResult(
      id: 'setting_about',
      title: '关于应用 / 版本更新',
      subtitle: '查看当前版本、公告与更新日志',
      icon: Icons.info_outline,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 关于',
      extraData: {'route': '/about'},
    ),
    // 🚀 课表相关
    SearchResult(
      id: 'setting_course_import',
      title: '课表导入 / 课程导入 / 导入课表 / 课程表',
      subtitle: '支持教务系统、智能文件嗅探导入',
      icon: Icons.school,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 课表',
      extraData: {'route': '/settings', 'target': 'smart_import'},
    ),
    SearchResult(
      id: 'setting_course_sync',
      title: '课表同步 / 从云端获取课表',
      subtitle: '将云端备份的课程同步到本机',
      icon: Icons.cloud_download,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 课表',
      extraData: {'route': '/settings', 'target': 'course_sync'},
    ),
    SearchResult(
      id: 'setting_course_upload',
      title: '上传课表 / 课表备份',
      subtitle: '将本地课表保存到云端',
      icon: Icons.cloud_upload,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 课表',
      extraData: {'route': '/settings', 'target': 'course_upload'},
    ),
    // 🚀 学期相关
    SearchResult(
      id: 'setting_semester_start',
      title: '开学日期 / 学期开始',
      subtitle: '设置当前学期的起始日期',
      icon: Icons.calendar_today,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 学期',
      extraData: {'route': '/settings', 'target': 'semester_start'},
    ),
    SearchResult(
      id: 'setting_semester_end',
      title: '放假日期 / 学期结束',
      subtitle: '设置当前学期的结束日期',
      icon: Icons.event,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 学期',
      extraData: {'route': '/settings', 'target': 'semester_end'},
    ),
    SearchResult(
      id: 'setting_semester_sync',
      title: '学期同步 / 同步日期',
      subtitle: '从云端同步开学与放假日期',
      icon: Icons.sync_problem,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 学期',
      extraData: {'route': '/settings', 'target': 'semester_sync'},
    ),
    // 🚀 通知相关
    SearchResult(
      id: 'setting_notifications',
      title: '通知设置 / 消息提醒 / 课程提醒',
      subtitle: '管理系统通知、课程闹钟提醒',
      icon: Icons.notifications,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 通知',
      extraData: {'route': '/settings', 'target': 'notifications'},
    ),
    SearchResult(
      id: 'setting_live_updates',
      title: '实时活动 / 动态岛通知 / Live Updates',
      subtitle: 'Android 16+ 实时状态显示支持',
      icon: Icons.notifications_active,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 高级',
      extraData: {'route': '/settings', 'target': 'live_updates'},
    ),
    SearchResult(
      id: 'setting_test_notification',
      title: '测试通知 / 验证推送',
      subtitle: '发送一条测试通知以验证权限是否正常',
      icon: Icons.notification_important,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 通知',
      extraData: {'route': '/settings', 'target': 'test_notif'},
    ),
    // 🚀 团队协作
    SearchResult(
      id: 'setting_team_management',
      title: '团队协作 / 创建团队 / 加入团队',
      subtitle: '管理您的所有协作团队',
      icon: Icons.groups,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 团队',
      extraData: {'route': '/teams'},
    ),
    SearchResult(
      id: 'setting_team_announcement',
      title: '团队公告 / 公告列表',
      subtitle: '查看您所在团队发布的最新消息',
      icon: Icons.campaign,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 团队',
      extraData: {'route': '/teams', 'target': 'announcements'},
    ),
    SearchResult(
      id: 'setting_team_messages',
      title: '团队消息中心 / 消息通知',
      subtitle: '管理入队申请与系统通知',
      icon: Icons.message,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 团队',
      extraData: {'route': '/teams', 'target': 'messages'},
    ),
    SearchResult(
      id: 'setting_team_members',
      title: '团队成员 / 成员管理 / 踢人 / 权限',
      subtitle: '查看或管理团队内的合作伙伴',
      icon: Icons.manage_accounts,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 团队',
      extraData: {'route': '/teams', 'target': 'members'},
    ),
    // 🚀 业务模块直达
    SearchResult(
      id: 'feature_pomodoro_stats',
      title: '番茄钟统计 / 专注统计 / 效率分析',
      subtitle: '查看每日、每周的专注时长分布',
      icon: Icons.bar_chart,
      type: SearchResultType.log,
      extraData: {'route': '/pomodoro/stats'},
    ),
    SearchResult(
      id: 'feature_time_log_manual',
      title: '时间日志补录 / 手动记账 / 补录时间',
      subtitle: '手动补录错过的专注或学习时段',
      icon: Icons.more_time,
      type: SearchResultType.log,
      extraData: {'route': '/time_log/manual'},
    ),
  ];

  Future<List<SearchResult>> search(String query) async {
    if (query.trim().isEmpty) return [];
    
    final currentSearchId = ++_latestSearchId;
    final q = query.toLowerCase().trim();
    final scoredResults = <SearchResultWithScore>[];

    // 1. 静态索引扫描
    for (var s in _staticSettings) {
      int score = _calculateScore(s.title.toLowerCase(), s.subtitle?.toLowerCase(), s.breadcrumb?.toLowerCase(), q);
      if (score > 0) scoredResults.add(SearchResultWithScore(s, score));
    }

    // 2. 数据库扫描
    // 🚀 修复：DB 查询结果已经由 SQL LIKE/FTS 确认与 query 相关，
    // 不能再用 _calculateScore 二次过滤（否则备注匹配但不在 subtitle 里的条目会被丢弃）。
    // 用 score+10 保证 DB 结果优先展示，同时仍按标题相关度排序。
    try {
      final dbItems = await _searchDatabase(q);
      if (currentSearchId != _latestSearchId) return [];
      for (var item in dbItems) {
        final score = _calculateScore(item.title.toLowerCase(), item.subtitle?.toLowerCase(), null, q);
        // DB 已过滤，保底给 score=1，避免备注命中却被丢弃
        scoredResults.add(SearchResultWithScore(item, (score > 0 ? score : 1) + 10));
      }
    } catch (e) {
      debugPrint("Database search error: $e");
    }

    scoredResults.sort((a, b) => b.score.compareTo(a.score));
    
    // 4. 强制去重：根据 ID 过滤重复项（防止数据库中存在冗余数据导致展示混乱）
    final seenIds = <String>{};
    final finalResults = <SearchResult>[];
    for (var sr in scoredResults) {
      if (!seenIds.contains(sr.result.id)) {
        seenIds.add(sr.result.id);
        finalResults.add(sr.result);
      }
    }

    // 5. 动态动作注入
    if (q.contains('新') || q.contains('加')) {
      finalResults.insert(0, SearchResult(
        id: 'action_new_todo',
        title: '快速新建待办',
        subtitle: '点击立即创建新任务',
        icon: Icons.add_task,
        type: SearchResultType.action,
        extraData: {'action': 'new_todo'},
      ));
    }

    finalResults.add(SearchResult(
      id: 'ai_search_helper',
      title: '询问 AI 助手...',
      subtitle: '基于 "$query" 寻找更多智能建议',
      icon: Icons.auto_awesome,
      type: SearchResultType.action,
      extraData: {'action': 'ai_query', 'query': query},
    ));

    return finalResults;
  }

  int _calculateScore(String title, String? subtitle, String? breadcrumb, String query) {
    if (title == query) return 100;
    if (title.startsWith(query)) return 80;
    if (title.contains(query)) return 50;
    if (subtitle?.contains(query) ?? false) return 20;
    if (breadcrumb?.contains(query) ?? false) return 10;
    return 0;
  }

  Future<List<SearchResult>> _searchDatabase(String query) async {
    final dbItems = <SearchResult>[];
    final db = DatabaseHelper.instance;

    // ── 待办事项 ──────────────────────────────────────────────────────────
    final todos = await db.searchTodos(query);
    for (var t in todos) {
      // 构建副标题：备注（优先）+ 截止时间 + 归属团队
      // 🚀 修复：备注始终显示在副标题第一行，而非仅作兜底
      final metaParts = <String>[];
      final dueDateMs = t['due_date'];
      if (dueDateMs != null && dueDateMs != 0) {
        metaParts.add('截止 ${DateFormat('MM/dd').format(DateTime.fromMillisecondsSinceEpoch(dueDateMs is int ? dueDateMs : int.tryParse(dueDateMs.toString()) ?? 0))}');
      }
      final createdDateMs = t['created_date'];
      if (createdDateMs != null && createdDateMs != 0) {
        metaParts.add('开始 ${DateFormat('MM/dd').format(DateTime.fromMillisecondsSinceEpoch(createdDateMs is int ? createdDateMs : int.tryParse(createdDateMs.toString()) ?? 0))}');
      }
      if (t['team_name'] != null && (t['team_name'] as String).isNotEmpty) {
        metaParts.add('团队: ${t['team_name']}');
      }
      final remarkStr = t['remark']?.toString().trim();
      // subtitle = 备注（若有）＋元信息（若有）
      final subtitle = [
        if (remarkStr != null && remarkStr.isNotEmpty) remarkStr,
        if (metaParts.isNotEmpty) metaParts.join(' · '),
      ].join('  |  ');
      final displaySubtitle = subtitle.isNotEmpty ? subtitle : '个人待办';

      dbItems.add(SearchResult(
        id: 'db_todo_${t['uuid']}',
        title: t['content'] ?? '未命名任务',
        subtitle: displaySubtitle,
        icon: t['is_completed'] == 1 ? Icons.check_circle : Icons.radio_button_unchecked,
        type: SearchResultType.todo,
        extraData: {
          'uuid': t['uuid'],
          'table': 'todos',
          'is_completed': t['is_completed'],
          'due_date': dueDateMs,
          'team_name': t['team_name'],
          'remark': remarkStr,
        },
      ));
    }

    // ── 课程 ─────────────────────────────────────────────────────────────
    final courses = await db.searchCourses(query);
    for (var c in courses) {
      // 构建时间描述：第几周 + 星期几 + 第几节
      final weekIdx = c['week_index'];
      final weekday = c['weekday'];
      const weekdayNames = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      final weekdayStr = (weekday != null && weekday >= 1 && weekday <= 7) ? weekdayNames[weekday] : '';
      final startSlot = c['start_time'];
      final endSlot = c['end_time'];
      final timePart = (startSlot != null && endSlot != null) ? '第 $startSlot-$endSlot 节' : '';
      final weekPart = weekIdx != null ? '第 $weekIdx 周' : '';
      final subtitle = [weekPart, weekdayStr, timePart, c['room_name'] ?? ''].where((s) => s.isNotEmpty).join(' · ');

      dbItems.add(SearchResult(
        id: 'db_course_${c['uuid']}',
        title: c['course_name'] ?? '未知课程',
        subtitle: subtitle.isNotEmpty ? subtitle : (c['teacher_name'] ?? '未知教师'),
        icon: Icons.school,
        type: SearchResultType.course,
        extraData: {
          'uuid': c['uuid'],
          'table': 'courses',
          'teacher_name': c['teacher_name'],
          'room_name': c['room_name'],
          'week_index': weekIdx,
          'weekday': weekday,
        },
      ));
    }

    // ── 倒计时 ────────────────────────────────────────────────────────────
    final countdowns = await db.searchCountdowns(query);
    for (var cd in countdowns) {
      String subtitle = '未设置日期';
      final targetMs = cd['target_time'];
      if (targetMs != null) {
        final target = DateTime.fromMillisecondsSinceEpoch(targetMs is int ? targetMs : int.tryParse(targetMs.toString()) ?? 0);
        final now = DateTime.now();
        final diff = target.difference(now).inDays;
        final dateStr = DateFormat('yyyy/MM/dd').format(target);
        subtitle = diff >= 0 ? '还有 $diff 天 · $dateStr' : '已过 ${-diff} 天 · $dateStr';
      }
      dbItems.add(SearchResult(
        id: 'db_countdown_${cd['uuid']}',
        title: cd['title'] ?? '未命名倒计时',
        subtitle: subtitle,
        icon: Icons.timer_outlined,
        type: SearchResultType.countdown,
        extraData: {'uuid': cd['uuid'], 'table': 'countdowns'},
      ));
    }

    // ── 时间日志 ──────────────────────────────────────────────────────────
    final logs = await db.searchTimeLogs(query);
    for (var l in logs) {
      final startMs = l['start_time'];
      final endMs = l['end_time'];
      String durationStr = '';
      String dateStr = '';
      if (startMs != null && endMs != null) {
        final start = DateTime.fromMillisecondsSinceEpoch(startMs is int ? startMs : int.tryParse(startMs.toString()) ?? 0);
        final end = DateTime.fromMillisecondsSinceEpoch(endMs is int ? endMs : int.tryParse(endMs.toString()) ?? 0);
        final mins = end.difference(start).inMinutes;
        durationStr = '$mins 分钟';
        dateStr = DateFormat('MM/dd HH:mm').format(start);
      }
      dbItems.add(SearchResult(
        id: 'db_log_${l['uuid']}',
        title: l['title']?.toString().isNotEmpty == true ? l['title'] : '未命名专注',
        subtitle: [durationStr, dateStr, l['remark'] ?? ''].where((s) => s.isNotEmpty).join(' · '),
        icon: Icons.history_edu_rounded,
        type: SearchResultType.log,
        extraData: {'uuid': l['uuid'], 'table': 'time_logs'},
      ));
    }

    // ── 待办文件夹 ────────────────────────────────────────────────────────
    final groups = await db.searchTodoGroups(query);
    for (var g in groups) {
      dbItems.add(SearchResult(
        id: 'db_group_${g['uuid']}',
        title: g['name'] ?? '未命名文件夹',
        subtitle: g['team_name'] != null ? '团队文件夹 · ${g['team_name']}' : '个人文件夹',
        icon: Icons.folder_rounded,
        type: SearchResultType.todoGroup,
        extraData: {'uuid': g['uuid'], 'table': 'todo_groups'},
      ));
    }
    return dbItems;
  }
}

class SearchNavigationHandler {
  static void handle(BuildContext context, SearchResult result) {
    final data = result.extraData;
    if (data == null) return;

    final route = data['route'] as String?;
    final action = data['action'] as String?;
    final query = data['query'] as String?;

    if (action != null) {
      if (action == 'ai_query' && query != null) {
        _showAISuggestion(context, query);
      } else if (action == 'new_todo') {
        _executeAction(context, action);
      }
      return;
    }

    if (route != null) {
      _navigateByRoute(context, route, data);
    } else if (result.type == SearchResultType.todo) {
      _handleTodoEdit(context, result);
    } else if (result.type == SearchResultType.todoGroup) {
      _handleTodoGroupNavigation(context, result);
    }
  }

  static void _handleTodoEdit(BuildContext context, SearchResult result) async {
    try {
      final uuid = result.extraData?['uuid'];
      if (uuid == null) {
        debugPrint("❌ _handleTodoEdit: uuid is null");
        return;
      }

      final db = DatabaseHelper.instance;
      final todoMap = await db.getTodoByUuid(uuid);
      if (todoMap == null) {
        debugPrint("❌ _handleTodoEdit: todo not found for uuid=$uuid");
        return;
      }

      final username = await StorageService.getLoginSession();
      if (username == null) {
        debugPrint("❌ _handleTodoEdit: no login session");
        return;
      }

      // 🚀 核心修复：due_date 在 DB 中是 TEXT (jsonType)，需要安全转 int
      int? _toInt(dynamic v) {
        if (v == null) return null;
        if (v is int) return v == 0 ? null : v;
        final parsed = int.tryParse(v.toString());
        return (parsed == null || parsed == 0) ? null : parsed;
      }

      final todo = TodoItem(
        id: todoMap['uuid']?.toString(),
        title: todoMap['content']?.toString() ?? '',
        isDone: todoMap['is_completed'] == 1,
        isDeleted: todoMap['is_deleted'] == 1,
        version: (todoMap['version'] is int) ? todoMap['version'] : int.tryParse(todoMap['version'].toString()) ?? 1,
        updatedAt: (todoMap['updated_at'] is int) ? todoMap['updated_at'] : int.tryParse(todoMap['updated_at'].toString()),
        createdAt: (todoMap['created_at'] is int) ? todoMap['created_at'] : int.tryParse(todoMap['created_at'].toString()),
        createdDate: _toInt(todoMap['created_date']),
        dueDate: _toInt(todoMap['due_date']) != null
            ? DateTime.fromMillisecondsSinceEpoch(_toInt(todoMap['due_date'])!)
            : null,
        remark: todoMap['remark']?.toString(),
        groupId: todoMap['group_id']?.toString(),
        teamUuid: todoMap['team_uuid']?.toString(),
        teamName: todoMap['team_name']?.toString(),
        collabType: (todoMap['collab_type'] is int) ? todoMap['collab_type'] : int.tryParse(todoMap['collab_type'].toString()) ?? 0,
        reminderMinutes: _toInt(todoMap['reminder_minutes']),
      );

      final allTodos = await StorageService.getTodos(username);
      final allGroups = await StorageService.getTodoGroups(username);

      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TodoEditScreen(
              todo: todo,
              todos: allTodos,
              onTodosChanged: (newList) async {
                await StorageService.saveTodos(username, newList);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("待办已更新"), behavior: SnackBarBehavior.floating),
                  );
                }
              },
              todoGroups: allGroups,
              onGroupsChanged: (newGroups) async {
                await StorageService.saveTodoGroups(username, newGroups);
              },
              username: username,
            ),
          ),
        );
      } else {
        debugPrint("❌ _handleTodoEdit: context not mounted after async ops");
      }
    } catch (e, stack) {
      debugPrint("❌ _handleTodoEdit crash: $e\n$stack");
    }
  }


  static void _handleTodoGroupNavigation(BuildContext context, SearchResult result) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text("已跳转至文件夹: ${result.title}"),
      behavior: SnackBarBehavior.floating,
    ));
  }

  static void _navigateByRoute(BuildContext context, String route, Map<String, dynamic> data) async {
    final target = data['target'] as String?;
    Widget? page;
    final username = await StorageService.getLoginSession() ?? 'default';

    switch (route) {
      case '/pomodoro/stats':
        page = PomodoroScreen(username: username, initialTab: 1);
        break;
      case '/time_log/manual':
        page = TimeLogScreen(username: username);
        break;
      case '/settings': 
        page = SettingsPage(initialTarget: target); 
        break;
      case '/settings/animation': 
        page = const AnimationSettingsPage(); 
        break;
      case '/settings/wallpaper': page = const WallpaperSettingsPage(); break;
      case '/settings/llm_config': page = const LLMConfigPage(); break;
      case '/settings/notifications': page = const NotificationSettingsPage(); break;
      case '/settings/lan_sync': page = const LanSyncScreen(); break;
      case '/settings/band_sync': page = const BandSyncScreen(); break;
      case '/about': page = const AboutScreen(); break;
      case '/login': Navigator.pushNamed(context, '/login'); return;
      case '/teams': 
        if (context.mounted) {
          Navigator.push(context, PageTransitions.slideHorizontal(
            TeamManagementScreen(username: username, initialTarget: target)
          ));
        }
        return;
    }

    if (page != null && context.mounted) {
      Navigator.push(context, PageTransitions.slideHorizontal(page));
    }
  }

  static void _executeAction(BuildContext context, String action) {
    if (action == 'new_todo') {
      Navigator.of(context).popUntil((route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("请在首页点击 + 号或通过快捷方式新建待办"),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  static void _showAISuggestion(BuildContext context, String query) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.purple),
            SizedBox(width: 8),
            Text("AI 智能分析"),
          ],
        ),
        content: Text("AI 正在深度分析您的意图：\n\"$query\"\n\n(此处可对接现有的 LLMService 实现智能创建或问答)"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("了解")),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
