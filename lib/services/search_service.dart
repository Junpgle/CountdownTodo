import 'package:flutter/material.dart';
import '../models.dart';
import '../screens/about_screen.dart';
import '../screens/team_management_screen.dart';
import '../storage_service.dart';
import 'database_helper.dart';
import 'pomodoro_service.dart';
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
import '../screens/screen_time_detail_screen.dart';

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
    final username = await StorageService.getLoginSession() ?? 'default';
    final q = query.toLowerCase().trim();

    // ── 日期查询解析 (支持 "今天", "昨天", "04/24" 等) ────────────────────
    DateTime? targetDate;
    if (q == '今天' || q == '今日' || q == '今' || q == 'today') {
      targetDate = DateTime.now();
    } else if (q == '昨天' || q == '昨日' || q == 'yesterday') {
      targetDate = DateTime.now().subtract(const Duration(days: 1));
    } else if (q == '前天') {
      targetDate = DateTime.now().subtract(const Duration(days: 2));
    } else if (q == '大前天') {
      targetDate = DateTime.now().subtract(const Duration(days: 3));
    } else if (q == '明天' || q == '明日' || q == 'tomorrow') {
      targetDate = DateTime.now().add(const Duration(days: 1));
    } else if (q == '后天') {
      targetDate = DateTime.now().add(const Duration(days: 2));
    } else if (q == '大后天') {
      targetDate = DateTime.now().add(const Duration(days: 3));
    } else {
      final now = DateTime.now();
      final patterns = <RegExp>[
        RegExp(r'^(\d{4})[./\-/年](\d{1,2})[./\-/月](\d{1,2})[日号]?$'),
        RegExp(r'^(\d{1,2})[./\-/月](\d{1,2})[日号]?$'),
      ];

      for (final pattern in patterns) {
        final match = pattern.firstMatch(q);
        if (match == null) continue;

        int? year;
        int month;
        int day;
        if (match.groupCount == 3 && match.group(1)!.length == 4) {
          year = int.tryParse(match.group(1)!);
          month = int.tryParse(match.group(2)!) ?? 0;
          day = int.tryParse(match.group(3)!) ?? 0;
        } else {
          year = now.year;
          month = int.tryParse(match.group(1)!) ?? 0;
          day = int.tryParse(match.group(2)!) ?? 0;
        }

        if (year != null && month >= 1 && month <= 12 && day >= 1 && day <= 31) {
          targetDate = DateTime(year, month, day);
          break;
        }
      }
    }

    final isDateQuery = targetDate != null;
    final startOfDay = targetDate != null ? DateTime(targetDate.year, targetDate.month, targetDate.day) : null;
    final endOfDay = startOfDay?.add(const Duration(days: 1));
    final now = DateTime.now();
    final targetDateValue = targetDate;
    final isTodayQuery =
        isDateQuery &&
        targetDateValue != null &&
        targetDateValue.year == now.year &&
        targetDateValue.month == now.month &&
        targetDateValue.day == now.day;
    final dateQueryHint = isDateQuery && startOfDay != null
        ? '搜索到${DateFormat('yyyy年M月d日').format(startOfDay)}的结果'
        : null;

    // ── 待办事项 ──────────────────────────────────────────────────────────
    List<Map<String, dynamic>> todos = [];
    try {
      if (isDateQuery) {
        final allTodos = await StorageService.getTodos(username);
        final matchedTodos = allTodos.where((t) {
          if (t.isDeleted) return false;
          if (t.dueDate != null && t.dueDate!.isAfter(startOfDay!.subtract(const Duration(milliseconds: 1))) && t.dueDate!.isBefore(endOfDay!)) return true;
          if (t.createdDate != null) {
            final cd = DateTime.fromMillisecondsSinceEpoch(t.createdDate!);
            if (cd.isAfter(startOfDay!.subtract(const Duration(milliseconds: 1))) && cd.isBefore(endOfDay!)) return true;
          }
          return false;
        }).take(20).toList();

        todos = matchedTodos.map((t) => {
          'uuid': t.id,
          'content': t.title,
          'is_completed': t.isDone ? 1 : 0,
          'is_deleted': 0,
          'due_date': t.dueDate?.millisecondsSinceEpoch,
          'created_date': t.createdDate,
          'team_name': t.teamName,
          'remark': t.remark,
        }).toList();
      } else {
        todos = await db.searchTodos(query);
      }
    } catch (e) {
      debugPrint('Todo search error: $e');
    }
    
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
          if (dateQueryHint != null) 'date_query_hint': dateQueryHint,
        },
      ));
    }

    // ── 课程 ─────────────────────────────────────────────────────────────
    try {
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
            if (dateQueryHint != null) 'date_query_hint': dateQueryHint,
          },
        ));
      }
    } catch (e) {
      debugPrint('Course search error: $e');
    }

    // ── 倒计时 ────────────────────────────────────────────────────────────
    try {
      final countdowns = await db.searchCountdowns(query);
      for (var cd in countdowns) {
        String subtitle = '未设置日期';
        final targetMs = cd['target_time'];
        if (targetMs != null) {
          final target = DateTime.fromMillisecondsSinceEpoch(targetMs is int ? targetMs : int.tryParse(targetMs.toString()) ?? 0);
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
          extraData: {
            'uuid': cd['uuid'],
            'table': 'countdowns',
            if (dateQueryHint != null) 'date_query_hint': dateQueryHint,
          },
        ));
      }
    } catch (e) {
      debugPrint('Countdown search error: $e');
    }

    // ── 时间日志 ──────────────────────────────────────────────────────────
    // 🚀 修复：时间日志存在 SharedPreferences，统一用 StorageService
    try {
      final allLogs = await StorageService.getTimeLogs(username);
      final matchedLogs = allLogs.where((l) {
        if (l.isDeleted) return false;
        if (isDateQuery) {
          final start = DateTime.fromMillisecondsSinceEpoch(l.startTime);
          return start.isAfter(startOfDay!.subtract(const Duration(milliseconds: 1))) && start.isBefore(endOfDay!);
        }
        return l.title.toLowerCase().contains(q) || (l.remark?.toLowerCase().contains(q) ?? false);
      }).take(15).toList();

      for (var l in matchedLogs) {
        final start = DateTime.fromMillisecondsSinceEpoch(l.startTime);
        final end = DateTime.fromMillisecondsSinceEpoch(l.endTime);
        final mins = end.difference(start).inMinutes;
        dbItems.add(SearchResult(
          id: 'db_log_${l.id}',
          title: l.title.isNotEmpty ? l.title : '未命名专注',
          subtitle: '$mins 分钟 · ${DateFormat('MM/dd HH:mm').format(start)}'
              '${l.remark?.isNotEmpty == true ? ' · ${l.remark}' : ''}',
          icon: Icons.history_edu_rounded,
          type: SearchResultType.log,
          extraData: {
            'uuid': l.id,
            'table': 'time_logs',
            if (dateQueryHint != null) 'date_query_hint': dateQueryHint,
          },
        ));
      }
    } catch (e) {
      debugPrint('Time log search error: $e');
    }

    // ── 时间日志标签 ─────────────────────────────────────────────────────
    // 搜索标签名，点击可跳转到该标签的折线图统计界面
    try {
      final allTags = await PomodoroService.getTags();
      final q = query.toLowerCase();
      final matchedTags = allTags.where((t) => t.name.toLowerCase().contains(q));
      for (var tag in matchedTags) {
        dbItems.add(SearchResult(
          id: 'db_tag_${tag.uuid}',
          title: tag.name,
          subtitle: '专注标签 · 点击查看折线图统计',
          icon: Icons.label_rounded,
          type: SearchResultType.tag,
          extraData: {
            'tag_uuid': tag.uuid,
            'tag_name': tag.name,
            'tag_color': tag.color,
            'route': '/time_log/tag',
          },
        ));
      }
    } catch (e) {
      debugPrint('Tag search error: $e');
    }

    // ── 屏幕使用时间 (App 搜索) ─────────────────────────────────────────
    // 兼容桌面同步缓存与移动端本地缓存；今日查询时直接展示当天使用过的应用。
    if (!isDateQuery || isTodayQuery) {
      try {
        final seenApps = <String>{};

        void addScreenTimeApps(List<dynamic> stats, {required bool includeAll}) {
          for (var item in stats) {
            if (item is! Map) continue;
            final appName = item['app_name']?.toString().trim() ?? '';
            if (appName.isEmpty) continue;

            final normalized = appName.toLowerCase();
            if (seenApps.contains(normalized)) continue;

            final matchesQuery = includeAll || normalized.contains(q);
            if (!matchesQuery) continue;

            seenApps.add(normalized);
            final subtitle = '屏幕使用时间 · 点击查看应用详情';

            dbItems.add(SearchResult(
              id: 'db_app_$normalized',
              title: appName,
              subtitle: subtitle,
              icon: Icons.smartphone_rounded,
              type: SearchResultType.app,
              extraData: {
                'app_name': appName,
                'route': '/screen_time/app',
                if (dateQueryHint != null) 'date_query_hint': dateQueryHint,
              },
            ));
          }
        }

        final screenTimeCache = await StorageService.getScreenTimeCache();
        if (screenTimeCache.isNotEmpty) {
          addScreenTimeApps(screenTimeCache, includeAll: isTodayQuery);
        }

        final history = await StorageService.getScreenTimeHistory();
        if (isTodayQuery) {
          final todayKey = DateFormat('yyyy-MM-dd').format(now);
          final todayStats = history[todayKey];
          if (todayStats != null && todayStats.isNotEmpty) {
            addScreenTimeApps(todayStats, includeAll: true);
          }
        } else {
          for (final dayEntry in history.entries) {
            final dayStats = dayEntry.value;
            if (dayStats.isEmpty) continue;
            addScreenTimeApps(dayStats, includeAll: false);
          }
        }
      } catch (e) {
        debugPrint('Screen time search error: $e');
      }
    }

    // ── 番茄钟 (仅日期搜索时展示) ──────────────────────────────────────────
    if (isDateQuery) {
      try {
        final allPoms = await PomodoroService.getRecords();
        final matchedPoms = allPoms.where((p) {
          final start = DateTime.fromMillisecondsSinceEpoch(p.startTime);
          return start.isAfter(startOfDay!.subtract(const Duration(milliseconds: 1))) && start.isBefore(endOfDay!);
        }).take(15).toList();
        for (var p in matchedPoms) {
          final start = DateTime.fromMillisecondsSinceEpoch(p.startTime);
          final end = p.endTime != null ? DateTime.fromMillisecondsSinceEpoch(p.endTime!) : start.add(Duration(minutes: p.effectiveDuration ~/ 60));
          final mins = p.effectiveDuration ~/ 60;
          dbItems.add(SearchResult(
            id: 'db_pom_${p.uuid}',
            title: p.todoTitle?.isNotEmpty == true ? p.todoTitle! : '专注记录',
                  subtitle: '$mins 分钟 · ${DateFormat('HH:mm').format(start)} - ${DateFormat('HH:mm').format(end)} · ${p.isCompleted ? "完成" : "中断"}',
            icon: Icons.timer_outlined,
            type: SearchResultType.log, // 与时间日志归在一组
              extraData: {
                'uuid': p.uuid,
                'table': 'pomodoro_records',
                if (dateQueryHint != null) 'date_query_hint': dateQueryHint,
              },
          ));
        }
      } catch (e) {
        debugPrint('Pomodoro search error: $e');
      }
    }

    // ── 待办文件夹 ────────────────────────────────────────────────────────
    try {
      final groups = await db.searchTodoGroups(query);
      for (var g in groups) {
        dbItems.add(SearchResult(
          id: 'db_group_${g['uuid']}',
          title: g['name'] ?? '未命名文件夹',
          subtitle: g['team_name'] != null
              ? '团队文件夹 · ${g['team_name']}'
              : '个人文件夹',
          icon: Icons.folder_rounded,
          type: SearchResultType.todoGroup,
          extraData: {'uuid': g['uuid'], 'table': 'todo_groups'},
        ));
      }
    } catch (e) {
      debugPrint('Todo group search error: $e');
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

    if (route == '/time_log/tag') {
      final tagUuid = data['tag_uuid'];
      if (tagUuid != null) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        Navigator.push(context, MaterialPageRoute(builder: (_) => TimeLogScreen(username: username, initialTagUuid: tagUuid)));
      }
      return;
    }
    
    if (route == '/screen_time/app') {
      final appName = data['app_name'];
      if (appName != null) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        final history = await StorageService.getScreenTimeHistory();
        final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
        if (history[todayKey] == null || history[todayKey]!.isEmpty) {
          final cachedToday = await StorageService.getScreenTimeCache();
          if (cachedToday.isNotEmpty) {
            history[todayKey] = cachedToday;
          }
        }
        Navigator.push(context, MaterialPageRoute(builder: (_) => AppDetailScreen(
          appName: appName,
          historyStats: history,
          filter: DeviceFilter.all,
        )));
      }
      return;
    }

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
