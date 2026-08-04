import 'package:flutter/material.dart';
import '../models.dart';
import '../screens/about_screen.dart';
import '../screens/team_management_screen.dart';
import '../storage_service.dart';
import 'database_helper.dart';
import 'pomodoro_service.dart';
import 'package:intl/intl.dart';
import '../screens/home_settings_screen.dart';
import '../utils/page_transitions.dart';
import '../widgets/todo_section_widget.dart';
import '../screens/pomodoro_screen.dart';
import '../screens/time_log_screen.dart';
import 'course_service.dart';
import '../screens/screen_time_detail_screen.dart';
import '../screens/course_screens.dart';
import '../screens/personal_timeline_screen.dart';
import '../features/habits/models/habit_goal.dart';
import '../features/habits/repositories/habit_repository.dart';
import '../features/habits/screens/habit_detail_screen.dart';
import '../features/habits/screens/habit_center_screen.dart';
import '../features/thirty_day_challenge/repositories/thirty_day_challenge_repository.dart';
import '../features/thirty_day_challenge/screens/thirty_day_challenge_screen.dart';

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
      id: 'setting_sync_interval',
      title: '自动同步频率 / 同步间隔',
      subtitle: '设置后台自动同步的时间间隔',
      icon: Icons.sync_outlined,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 账号',
      extraData: {'route': '/settings', 'target': 'sync_interval'},
    ),
    SearchResult(
      id: 'setting_conflict_detection',
      title: '冲突检测 / 待办时间冲突',
      subtitle: '检测待办时间重叠并提示冲突',
      icon: Icons.warning_amber_outlined,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 账号',
      extraData: {'route': '/settings', 'target': 'conflict_detection'},
    ),
    SearchResult(
      id: 'setting_lan_sync',
      title: '局域网同步 / 离线同步',
      subtitle: '在同一局域网内直接传输数据',
      icon: Icons.sync_alt,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 高级',
      extraData: {'route': '/settings', 'target': 'lan_sync'},
    ),
    SearchResult(
      id: 'setting_mcp',
      title: 'MCP / 模型上下文协议 / 外部 AI 接入',
      subtitle: '让兼容的 AI 客户端读取或管理个人待办',
      icon: Icons.hub_outlined,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 数据与互联',
      extraData: {'route': '/settings', 'target': 'mcp'},
    ),
    SearchResult(
      id: 'setting_animation',
      title: '动画效果 / 界面动效',
      subtitle: '调整应用转场与视觉效果',
      icon: Icons.animation,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 视觉',
      extraData: {'route': '/settings', 'target': 'animation'},
    ),
    SearchResult(
      id: 'setting_wallpaper',
      title: '壁纸设置 / 背景图片',
      subtitle: '自定义首页背景',
      icon: Icons.image,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 视觉',
      extraData: {'route': '/settings', 'target': 'wallpaper'},
    ),
    SearchResult(
      id: 'setting_llm_config',
      title: 'AI 助手 / LLM 设置',
      subtitle: '配置智能助手的 API 密钥与模型',
      icon: Icons.auto_awesome,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 高级',
      extraData: {'route': '/settings', 'target': 'llm_config'},
    ),
    SearchResult(
      id: 'setting_llm_retry',
      title: '图片识别重试次数 / AI 重试',
      subtitle: '识别超时后自动重试的次数',
      icon: Icons.replay_outlined,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 系统与外观',
      extraData: {'route': '/settings', 'target': 'llm_retry'},
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
      extraData: {'route': '/settings', 'target': 'band_sync'},
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
      id: 'setting_course_adapt',
      title: '请求课表适配 / 申请适配',
      subtitle: '如果没有你的学校，点此申请',
      icon: Icons.auto_awesome,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 课表',
      extraData: {'route': '/settings', 'target': 'course_adapt'},
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
      id: 'setting_tai_db',
      title: 'Tai 屏幕时间数据库 / 屏幕时间数据',
      subtitle: '选择 Tai 生成的 data.db 文件',
      icon: Icons.timer_outlined,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 平台专属',
      extraData: {'route': '/settings', 'target': 'tai_db'},
    ),
    SearchResult(
      id: 'setting_force_refresh_island',
      title: '强制刷新悬浮窗位置 / 刷新灵动岛',
      subtitle: '将灵动岛悬浮窗重置到屏幕中央',
      icon: Icons.refresh_rounded,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 平台专属',
      extraData: {'route': '/settings', 'target': 'force_refresh'},
    ),
    SearchResult(
      id: 'setting_island_priority',
      title: '灵动岛优先级设置 / 悬浮窗优先级',
      subtitle: '配置哪些应用可以抢占灵动岛显示',
      icon: Icons.priority_high_rounded,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 平台专属',
      extraData: {'route': '/settings', 'target': 'island_priority'},
    ),
    SearchResult(
      id: 'setting_island_support',
      title: '检测状态栏超级岛支持 / OriginOS 超级岛',
      subtitle: '检测 Android 设备的状态栏超级岛能力',
      icon: Icons.phone_android_outlined,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 平台专属',
      extraData: {'route': '/settings', 'target': 'island_support'},
    ),
    SearchResult(
      id: 'setting_mac_status_bar',
      title: '启用刘海灵动岛 / macOS 顶部灵动岛',
      subtitle: '专注时在屏幕顶部显示倒计时',
      icon: Icons.call_to_action_rounded,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 平台专属',
      extraData: {'route': '/settings', 'target': 'mac_status_bar'},
    ),
    SearchResult(
      id: 'setting_mac_island_shortcut',
      title: '隐藏恢复灵动岛快捷键 / macOS 快捷键',
      subtitle: '设置全局快捷键临时隐藏或恢复灵动岛',
      icon: Icons.keyboard_command_key_rounded,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 平台专属',
      extraData: {'route': '/settings', 'target': 'mac_island_shortcut'},
    ),
    SearchResult(
      id: 'setting_mac_island_reminders',
      title: '在灵动岛显示提醒 / 顶部提醒',
      subtitle: '让待办、课程和计划提醒在灵动岛展开',
      icon: Icons.notifications_active_outlined,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 平台专属',
      extraData: {'route': '/settings', 'target': 'mac_island_reminders'},
    ),
    SearchResult(
      id: 'setting_mac_island_clipboard_links',
      title: '检测剪贴板网址 / 灵动岛网址提示',
      subtitle: '复制网页链接时在灵动岛提示打开',
      icon: Icons.link_rounded,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 平台专属',
      extraData: {'route': '/settings', 'target': 'mac_island_clipboard_links'},
    ),
    SearchResult(
      id: 'setting_mac_island_test',
      title: '测试灵动岛提醒 / 测试顶部提醒',
      subtitle: '立即显示一条测试提醒，检查位置和交互',
      icon: Icons.play_circle_outline_rounded,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 平台专属',
      extraData: {'route': '/settings', 'target': 'mac_island_test'},
    ),
    SearchResult(
      id: 'setting_mac_island_without_notch',
      title: '无刘海屏幕也显示灵动岛 / 外接显示器',
      subtitle: '在无刘海 Mac 顶部显示居中胶囊',
      icon: Icons.desktop_mac_outlined,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 平台专属',
      extraData: {'route': '/settings', 'target': 'mac_island_without_notch'},
    ),
    SearchResult(
      id: 'setting_test_notification',
      title: '测试通知 / 验证推送',
      subtitle: '发送一条测试通知以验证权限是否正常',
      icon: Icons.notification_important,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 通知',
      extraData: {'route': '/settings', 'target': 'test_notification'},
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
    // 🚀 最近新增的系统设置：这里保持与各设置页的 targetId 一致，
    // 这样搜索结果可以直接打开对应设置项，而不是只打开设置首页。
    SearchResult(
      id: 'setting_theme',
      title: '深色模式 / 主题模式',
      subtitle: '跟随系统、浅色或深色显示',
      icon: Icons.dark_mode_outlined,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 系统与外观',
      extraData: {'route': '/settings', 'target': 'theme'},
    ),
    SearchResult(
      id: 'setting_theme_color',
      title: '全局主题颜色 / 配色',
      subtitle: '自定义应用的主色调',
      icon: Icons.color_lens_outlined,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 系统与外观',
      extraData: {'route': '/settings', 'target': 'theme_color'},
    ),
    SearchResult(
      id: 'setting_home_layout',
      title: '首页组件顺序 / 首页布局',
      subtitle: '调整首页模块排列、分组和习惯展示数量',
      icon: Icons.dashboard_customize_outlined,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 系统与外观',
      extraData: {'route': '/settings', 'target': 'home_layout'},
    ),
    SearchResult(
      id: 'setting_home_text',
      title: '首页文字自定义 / 问候语',
      subtitle: '自定义首页问候语、日期格式和用户名显示',
      icon: Icons.text_fields_outlined,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 系统与外观',
      extraData: {'route': '/settings', 'target': 'home_text'},
    ),
    SearchResult(
      id: 'setting_update_source',
      title: '更新检查源 / 版本更新源',
      subtitle: '选择 GitHub 或阿里云更新源',
      icon: Icons.cloud_sync_outlined,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 系统与外观',
      extraData: {'route': '/settings', 'target': 'update_source'},
    ),
    SearchResult(
      id: 'setting_help_center',
      title: '帮助与反馈 / 使用指南',
      subtitle: '查看功能说明、快速上手和常见问题',
      icon: Icons.help_outline_rounded,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 系统与外观',
      extraData: {'route': '/settings', 'target': 'help_center'},
    ),
    SearchResult(
      id: 'setting_changelog',
      title: '更新日志',
      subtitle: '查看当前版本及历史更新内容',
      icon: Icons.system_update_outlined,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 系统与外观',
      extraData: {'route': '/settings', 'target': 'changelog'},
    ),
    SearchResult(
      id: 'setting_feature_guide',
      title: '版本引导 / 新功能介绍',
      subtitle: '重新查看功能介绍与使用引导',
      icon: Icons.school_outlined,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 系统与外观',
      extraData: {'route': '/settings', 'target': 'feature_guide'},
    ),
    SearchResult(
      id: 'setting_data_migration',
      title: '旧版本地数据一键迁移 / 数据迁移',
      subtitle: '迁移待办、课程、课表与习惯数据',
      icon: Icons.move_to_inbox_outlined,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 系统与外观',
      extraData: {'route': '/settings', 'target': 'migration'},
    ),
    SearchResult(
      id: 'setting_calendar_sync',
      title: '系统日历同步 / 日历 ICS',
      subtitle: '将课程、待办和倒数日写入或导出到日历',
      icon: Icons.calendar_month_outlined,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 数据与互联',
      extraData: {'route': '/settings', 'target': 'calendar_sync'},
    ),
    SearchResult(
      id: 'setting_batch_tag',
      title: '批量添加标签 / 批量标签',
      subtitle: '为番茄钟和时间日志批量添加标签',
      icon: Icons.label_outline,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 数据与互联',
      extraData: {'route': '/settings', 'target': 'batch_tag'},
    ),
    SearchResult(
      id: 'setting_recurrence_merge',
      title: '重复待办合并 / 循环系列合并',
      subtitle: '手动选择并归并被拆开的循环系列',
      icon: Icons.merge_type_rounded,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 数据与互联',
      extraData: {'route': '/settings', 'target': 'recurrence_merge'},
    ),
    SearchResult(
      id: 'setting_data_export',
      title: '数据导出 / 备份数据',
      subtitle: '将待办、课程、倒数日等数据导出为文件',
      icon: Icons.upload_file_outlined,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 数据与互联',
      extraData: {'route': '/settings', 'target': 'data_export'},
    ),
    SearchResult(
      id: 'setting_data_import',
      title: '数据导入 / 恢复备份',
      subtitle: '从备份文件恢复或合并数据',
      icon: Icons.download_outlined,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 数据与互联',
      extraData: {'route': '/settings', 'target': 'data_import'},
    ),
    SearchResult(
      id: 'setting_no_course_behavior',
      title: '无课时板块行为 / 无课安排',
      subtitle: '设置没有课程时首页课表板块的显示方式',
      icon: Icons.view_agenda_outlined,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 课表与学期',
      extraData: {'route': '/settings', 'target': 'no_course_behavior'},
    ),
    SearchResult(
      id: 'setting_course_calendar_adjustment',
      title: '校历偏移动态调整 / 调休与停课',
      subtitle: '设置停课日期，以及补哪一天的课',
      icon: Icons.event_repeat_outlined,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 课表与学期',
      extraData: {'route': '/settings', 'target': 'course_calendar_adjustment'},
    ),
    SearchResult(
      id: 'setting_semester_management',
      title: '学期管理 / 多学期课表',
      subtitle: '添加、编辑或清除学期课程数据',
      icon: Icons.school_outlined,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 课表与学期',
      extraData: {'route': '/settings', 'target': 'semester_management'},
    ),
    SearchResult(
      id: 'setting_semester_sync',
      title: '同步学期日期 / 从云端同步开学放假时间',
      subtitle: '将另一设备设置的学期日期同步到本机',
      icon: Icons.sync_outlined,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 课表与学期',
      extraData: {'route': '/settings', 'target': 'semester_sync'},
    ),
    SearchResult(
      id: 'setting_permissions',
      title: '权限管理 / 应用权限',
      subtitle: '查看和管理通知、日历、悬浮窗等权限',
      icon: Icons.security_outlined,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 权限管理',
      extraData: {'route': '/settings', 'target': 'permissions'},
    ),
    SearchResult(
      id: 'setting_notification_management',
      title: '通知管理 / 浏览器通知 / 消息提醒',
      subtitle: '管理待办、课程、番茄钟和实时活动提醒',
      icon: Icons.notifications_outlined,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 通知管理',
      extraData: {'route': '/settings', 'target': 'notifications'},
    ),
    SearchResult(
      id: 'setting_float_window',
      title: '悬浮窗与灵动岛 / 动态岛',
      subtitle: '配置桌面悬浮窗、灵动岛和实时活动',
      icon: Icons.stars_rounded,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 平台专属',
      extraData: {'route': '/settings', 'target': 'float_window_style'},
    ),
    SearchResult(
      id: 'setting_android_live_updates',
      title: 'Android 16 实时活动 / Live Updates',
      subtitle: '配置实时状态显示支持',
      icon: Icons.notifications_active_outlined,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 平台专属',
      extraData: {'route': '/settings', 'target': 'live_updates'},
    ),
    // 业务入口：即使用户还没有创建具体数据，也可以通过搜索打开模块。
    SearchResult(
      id: 'feature_habit_center',
      title: '习惯中心 / 习惯追踪 / 习惯打卡',
      subtitle: '记录习惯、查看连续记录和完成趋势',
      icon: Icons.track_changes_rounded,
      type: SearchResultType.habit,
      extraData: {'route': '/habits'},
    ),
    SearchResult(
      id: 'feature_challenge_center',
      title: '30天找到全新自我 / 挑战中心 / 自定义挑战',
      subtitle: '创建、记录和分享自己的挑战',
      icon: Icons.auto_awesome_rounded,
      type: SearchResultType.challenge,
      extraData: {'route': '/challenge'},
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
    if (query.trim().isEmpty) {
      return await guessSearch();
    }

    final currentSearchId = ++_latestSearchId;
    final q = query.toLowerCase().trim();

    // 🚀 异步记录搜索历史
    DatabaseHelper.instance
        .insertSearchHistory(q)
        .catchError((e) => debugPrint("Record search history error: $e"));

    final searchTerms = _extractSearchTerms(q);
    final scoredResults = <SearchResultWithScore>[];

    // 1. 静态索引扫描
    for (var s in _staticSettings) {
      int score = _calculateScore(
        s.title.toLowerCase(),
        s.subtitle?.toLowerCase(),
        s.breadcrumb?.toLowerCase(),
        q,
        searchTerms,
      );
      if (score > 0) scoredResults.add(SearchResultWithScore(s, score));
    }

    // 2. 习惯与挑战扫描
    try {
      final featureItems = await _searchHabitsAndChallenges(searchTerms);
      if (currentSearchId != _latestSearchId) return [];
      for (final item in featureItems) {
        final score = _calculateScore(
          item.title.toLowerCase(),
          item.subtitle?.toLowerCase(),
          null,
          q,
          searchTerms,
        );
        if (score > 0) {
          scoredResults.add(SearchResultWithScore(item, score + 8));
        }
      }
    } catch (_) {
      // 习惯/挑战属于增强搜索，读取失败不影响其他搜索结果。
    }

    // 3. 数据库扫描
    // 🚀 修复：DB 查询结果已经由 SQL LIKE/FTS 确认与 query 相关，
    // 不能再用 _calculateScore 二次过滤（否则备注匹配但不在 subtitle 里的条目会被丢弃）。
    // 用 score+10 保证 DB 结果优先展示，同时仍按标题相关度排序。
    try {
      final dbItems = await _searchDatabase(q, searchTerms);
      if (currentSearchId != _latestSearchId) return [];
      for (var item in dbItems) {
        final score = _calculateScore(
          item.title.toLowerCase(),
          item.subtitle?.toLowerCase(),
          null,
          q,
          searchTerms,
        );
        // DB 已过滤，保底给 score=1，避免备注命中却被丢弃
        scoredResults
            .add(SearchResultWithScore(item, (score > 0 ? score : 1) + 10));
      }
    } catch (e) {
      // debugPrint("Database search error: $e");
    }

    scoredResults.sort((a, b) => b.score.compareTo(a.score));

    // 5. 强制去重：根据 ID 过滤重复项（防止数据库中存在冗余数据导致展示混乱）
    final seenIds = <String>{};
    final finalResults = <SearchResult>[];
    for (var sr in scoredResults) {
      if (!seenIds.contains(sr.result.id)) {
        seenIds.add(sr.result.id);
        finalResults.add(sr.result);
      }
    }

    // 6. 动态动作注入
    if (q.contains('新') || q.contains('加')) {
      finalResults.insert(
          0,
          SearchResult(
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

  List<String> _extractSearchTerms(String query) {
    return query
        .split(RegExp(r'[\s,，;；]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  bool _matchesAllTerms(String text, List<String> terms) {
    final lower = text.toLowerCase();
    return terms.every((term) => lower.contains(term.toLowerCase()));
  }

  Future<List<SearchResult>> _searchHabitsAndChallenges(
      List<String> searchTerms) async {
    final results = <SearchResult>[];

    try {
      final goals = await HabitRepository.getGoals();
      for (final goal in goals) {
        if (goal.isDeleted) continue;
        final sourceLabel = switch (goal.sourceType) {
          HabitSourceType.recurringTodo => '完成型',
          HabitSourceType.pomodoroTag => '专注时长型',
          HabitSourceType.quantityCheckIn => '数量型',
          HabitSourceType.timeCheckIn => '时间点型',
          HabitSourceType.durationCheckIn => '独立时长型',
        };
        final searchable = '${goal.name} 习惯 $sourceLabel'
            '${goal.isArchived ? ' 已归档 归档习惯' : ''}';
        if (!_matchesAllTerms(searchable, searchTerms)) continue;

        results.add(SearchResult(
          id: 'db_habit_${goal.uuid}',
          title: goal.name.isEmpty ? '未命名习惯' : goal.name,
          subtitle: '习惯 · $sourceLabel${goal.isArchived ? ' · 已归档' : ''}',
          icon: Icons.track_changes_rounded,
          type: SearchResultType.habit,
          extraData: {
            'route': '/habits',
            'habit_uuid': goal.uuid,
          },
        ));
      }
    } catch (_) {}

    try {
      // 未开始挑战时，静态“挑战中心”入口已经足够；避免每次输入关键词
      // 都为用户创建一份默认挑战状态。
      if (!await ThirtyDayChallengeRepository.hasStarted()) return results;
      final state = await ThirtyDayChallengeRepository.load();
      final taskTitles = state.tasks.map((task) => task.title).toList();
      final searchable = [
        state.challengeTitle,
        '挑战',
        '挑战中心',
        '30天',
        ...taskTitles,
      ].join(' ');

      if (_matchesAllTerms(searchable, searchTerms)) {
        final normalizedTerms = searchTerms.map((term) => term.toLowerCase());
        final matchedTasks = state.tasks
            .where((task) => normalizedTerms
                .any((term) => task.title.toLowerCase().contains(term)))
            .take(2)
            .map((task) => task.title)
            .join('、');
        final progress = '${state.completedCount}/${state.tasks.length} 项已完成';
        results.add(SearchResult(
          id: 'db_challenge_current',
          title: state.challengeTitle,
          subtitle: matchedTasks.isEmpty
              ? '挑战 · $progress'
              : '挑战 · $progress · 相关任务：$matchedTasks',
          icon: Icons.auto_awesome_rounded,
          type: SearchResultType.challenge,
          extraData: {'route': '/challenge'},
        ));
      }
    } catch (_) {}

    return results;
  }

  int _calculateScore(String title, String? subtitle, String? breadcrumb,
      String query, List<String> terms) {
    if (terms.isEmpty) return 0;
    if (terms.length == 1) {
      final term = terms.first;
      if (title == term) return 100;
      if (title.startsWith(term)) return 80;
      if (title.contains(term)) return 50;
      if (subtitle?.contains(term) ?? false) return 20;
      if (breadcrumb?.contains(term) ?? false) return 10;
      return 0;
    }

    final haystack =
        '$title ${subtitle ?? ''} ${breadcrumb ?? ''}'.toLowerCase();
    if (!_matchesAllTerms(haystack, terms)) return 0;

    var score = 0;
    for (final term in terms) {
      if (title == term) {
        score += 100;
      } else if (title.startsWith(term)) {
        score += 80;
      } else if (title.contains(term)) {
        score += 50;
      } else if (subtitle?.contains(term) ?? false) {
        score += 20;
      } else if (breadcrumb?.contains(term) ?? false) {
        score += 10;
      } else {
        score += 5;
      }
    }
    return score + terms.length * 10;
  }

  Future<List<SearchResult>> _searchDatabase(
      String query, List<String> searchTerms) async {
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

        if (year != null &&
            month >= 1 &&
            month <= 12 &&
            day >= 1 &&
            day <= 31) {
          targetDate = DateTime(year, month, day);
          break;
        }
      }
    }

    final isDateQuery = targetDate != null;
    final startOfDay = targetDate != null
        ? DateTime(targetDate.year, targetDate.month, targetDate.day)
        : null;
    final endOfDay = startOfDay?.add(const Duration(days: 1));
    final now = DateTime.now();
    final targetDateValue = targetDate;
    final isTodayQuery = isDateQuery &&
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
        final matchedTodos = allTodos
            .where((t) {
              if (t.isDeleted) return false;
              if (t.dueDate != null &&
                  t.dueDate!.isAfter(
                      startOfDay!.subtract(const Duration(milliseconds: 1))) &&
                  t.dueDate!.isBefore(endOfDay!)) {
                return true;
              }
              if (t.createdDate != null) {
                final cd = DateTime.fromMillisecondsSinceEpoch(t.createdDate!);
                if (cd.isAfter(startOfDay!
                        .subtract(const Duration(milliseconds: 1))) &&
                    cd.isBefore(endOfDay!)) {
                  return true;
                }
              }
              return false;
            })
            .take(20)
            .toList();

        todos = matchedTodos
            .map((t) => {
                  'uuid': t.id,
                  'content': t.title,
                  'is_completed': t.isDone ? 1 : 0,
                  'is_deleted': 0,
                  'due_date': t.dueDate?.millisecondsSinceEpoch,
                  'created_date': t.createdDate,
                  'team_name': t.teamName,
                  'remark': t.remark,
                })
            .toList();
      } else {
        final todoMap = <String, Map<String, dynamic>>{};
        for (final term in searchTerms) {
          for (final row in await db.searchTodos(term)) {
            todoMap[row['uuid'].toString()] = row;
          }
        }
        todos = todoMap.values.where((t) {
          final haystack = [
            t['content']?.toString(),
            t['remark']?.toString(),
            t['team_name']?.toString(),
          ].where((s) => s != null && s.isNotEmpty).join(' ').toLowerCase();
          return _matchesAllTerms(haystack, searchTerms);
        }).toList();
      }
    } catch (e) {
      // debugPrint('Todo search error: $e');
    }

    for (var t in todos) {
      // 构建副标题：备注（优先）+ 截止时间 + 归属团队
      // 🚀 修复：备注始终显示在副标题第一行，而非仅作兜底
      final metaParts = <String>[];
      final dueDateMs = t['due_date'];
      if (dueDateMs != null && dueDateMs != 0) {
        metaParts.add(
            '截止 ${DateFormat('MM/dd').format(DateTime.fromMillisecondsSinceEpoch(dueDateMs is int ? dueDateMs : int.tryParse(dueDateMs.toString()) ?? 0))}');
      }
      final createdDateMs = t['created_date'];
      if (createdDateMs != null && createdDateMs != 0) {
        metaParts.add(
            '开始 ${DateFormat('MM/dd').format(DateTime.fromMillisecondsSinceEpoch(createdDateMs is int ? createdDateMs : int.tryParse(createdDateMs.toString()) ?? 0))}');
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
        icon: t['is_completed'] == 1
            ? Icons.check_circle
            : Icons.radio_button_unchecked,
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
      final courseMap = <String, Map<String, dynamic>>{};
      for (final term in searchTerms) {
        for (final row in await db.searchCourses(term)) {
          courseMap[row['uuid'].toString()] = row;
        }
      }
      final courses = courseMap.values.where((c) {
        final haystack = [c['course_name'], c['teacher_name'], c['room_name']]
            .where((s) => s != null)
            .map((s) => s.toString())
            .join(' ')
            .toLowerCase();
        return _matchesAllTerms(haystack, searchTerms);
      }).toList();
      for (var c in courses) {
        // 构建时间描述：第几周 + 星期几 + 第几节
        final weekIdx = c['week_index'];
        final weekday = c['weekday'];
        const weekdayNames = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
        final weekdayStr = (weekday != null && weekday >= 1 && weekday <= 7)
            ? weekdayNames[weekday]
            : '';
        final startSlot = c['start_time'];
        final endSlot = c['end_time'];
        final timePart = (startSlot != null && endSlot != null)
            ? '第 $startSlot-$endSlot 节'
            : '';
        final weekPart = weekIdx != null ? '第 $weekIdx 周' : '';
        final subtitle = [weekPart, weekdayStr, timePart, c['room_name'] ?? '']
            .where((s) => s.isNotEmpty)
            .join(' · ');

        dbItems.add(SearchResult(
          id: 'db_course_${c['uuid']}',
          title: c['course_name'] ?? '未知课程',
          subtitle:
              subtitle.isNotEmpty ? subtitle : (c['teacher_name'] ?? '未知教师'),
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
      // debugPrint('Course search error: $e');
    }

    // ── 倒计时 ────────────────────────────────────────────────────────────
    try {
      final countdownMap = <String, Map<String, dynamic>>{};
      for (final term in searchTerms) {
        for (final row in await db.searchCountdowns(term)) {
          countdownMap[row['uuid'].toString()] = row;
        }
      }
      final countdowns = countdownMap.values.where((cd) {
        final haystack = [cd['title'], cd['team_name']]
            .where((s) => s != null)
            .map((s) => s.toString())
            .join(' ')
            .toLowerCase();
        return _matchesAllTerms(haystack, searchTerms);
      }).toList();
      for (var cd in countdowns) {
        String subtitle = '未设置日期';
        final targetMs = cd['target_time'];
        if (targetMs != null) {
          final target = DateTime.fromMillisecondsSinceEpoch(targetMs is int
              ? targetMs
              : int.tryParse(targetMs.toString()) ?? 0);
          final diff = target.difference(now).inDays;
          final dateStr = DateFormat('yyyy/MM/dd').format(target);
          subtitle =
              diff >= 0 ? '还有 $diff 天 · $dateStr' : '已过 ${-diff} 天 · $dateStr';
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
      // debugPrint('Countdown search error: $e');
    }

    // ── 时间日志 ──────────────────────────────────────────────────────────
    // 🚀 修复：时间日志存在 SharedPreferences，统一用 StorageService
    try {
      final allLogs = await StorageService.getTimeLogs(username);
      final matchedLogs = allLogs
          .where((l) {
            if (l.isDeleted) return false;
            if (isDateQuery) {
              final start = DateTime.fromMillisecondsSinceEpoch(l.startTime);
              return start.isAfter(
                      startOfDay!.subtract(const Duration(milliseconds: 1))) &&
                  start.isBefore(endOfDay!);
            }
            final haystack =
                [l.title, l.remark].whereType<String>().join(' ').toLowerCase();
            return _matchesAllTerms(haystack, searchTerms);
          })
          .take(15)
          .toList();

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
      // debugPrint('Time log search error: $e');
    }

    // ── 时间日志标签 ─────────────────────────────────────────────────────
    // 搜索标签名，点击可跳转到该标签的折线图统计界面
    try {
      final allTags = await PomodoroService.getTags();
      final matchedTags = allTags
          .where((t) => _matchesAllTerms(t.name.toLowerCase(), searchTerms));
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
      // debugPrint('Tag search error: $e');
    }

    // ── 屏幕使用时间 (App 搜索) ─────────────────────────────────────────
    // 日期查询时：直接展示目标日期的聚合屏幕时间；普通关键词查询时：按应用名匹配历史缓存。
    if (isDateQuery) {
      try {
        final seenApps = <String>{};

        void addScreenTimeApps(List<dynamic> stats,
            {required bool includeAll}) {
          for (var item in stats) {
            if (item is! Map) continue;
            final appName = item['app_name']?.toString().trim() ?? '';
            if (appName.isEmpty) continue;

            final normalized = appName.toLowerCase();
            if (seenApps.contains(normalized)) continue;

            final matchesQuery =
                includeAll || _matchesAllTerms(normalized, searchTerms);
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

        final history = await StorageService.getScreenTimeHistory();
        final targetDateKey = DateFormat('yyyy-MM-dd').format(startOfDay!);
        final targetDayStats = history[targetDateKey];

        if (targetDayStats != null && targetDayStats.isNotEmpty) {
          addScreenTimeApps(targetDayStats, includeAll: true);
        } else if (isTodayQuery) {
          final screenTimeCache = await StorageService.getScreenTimeCache();
          if (screenTimeCache.isNotEmpty) {
            addScreenTimeApps(screenTimeCache, includeAll: true);
          }
        }
      } catch (e) {
        // debugPrint('Screen time search error: $e');
      }
    } else {
      try {
        final seenApps = <String>{};

        void addScreenTimeApps(List<dynamic> stats) {
          for (var item in stats) {
            if (item is! Map) continue;
            final appName = item['app_name']?.toString().trim() ?? '';
            if (appName.isEmpty) continue;

            final normalized = appName.toLowerCase();
            if (seenApps.contains(normalized)) continue;
            if (!normalized.contains(q)) continue;

            seenApps.add(normalized);
            dbItems.add(SearchResult(
              id: 'db_app_$normalized',
              title: appName,
              subtitle: '屏幕使用时间 · 点击查看应用详情',
              icon: Icons.smartphone_rounded,
              type: SearchResultType.app,
              extraData: {
                'app_name': appName,
                'route': '/screen_time/app',
              },
            ));
          }
        }

        final screenTimeCache = await StorageService.getScreenTimeCache();
        if (screenTimeCache.isNotEmpty) {
          addScreenTimeApps(screenTimeCache);
        }

        final history = await StorageService.getScreenTimeHistory();
        for (final dayEntry in history.entries) {
          final dayStats = dayEntry.value;
          if (dayStats.isEmpty) continue;
          addScreenTimeApps(dayStats);
        }
      } catch (e) {
        // debugPrint('Screen time search error: $e');
      }
    }

    // ── 番茄钟 (仅日期搜索时展示) ──────────────────────────────────────────
    if (isDateQuery) {
      try {
        final allPoms = await PomodoroService.getRecords();
        final matchedPoms = allPoms
            .where((p) {
              final start = DateTime.fromMillisecondsSinceEpoch(p.startTime);
              return start.isAfter(
                      startOfDay!.subtract(const Duration(milliseconds: 1))) &&
                  start.isBefore(endOfDay!);
            })
            .take(15)
            .toList();
        for (var p in matchedPoms) {
          final start = DateTime.fromMillisecondsSinceEpoch(p.startTime);
          final end = p.endTime != null
              ? DateTime.fromMillisecondsSinceEpoch(p.endTime!)
              : start.add(Duration(minutes: p.effectiveDuration ~/ 60));
          final mins = p.effectiveDuration ~/ 60;
          dbItems.add(SearchResult(
            id: 'db_pom_${p.uuid}',
            title: p.todoTitle?.isNotEmpty == true ? p.todoTitle! : '专注记录',
            subtitle:
                '$mins 分钟 · ${DateFormat('HH:mm').format(start)} - ${DateFormat('HH:mm').format(end)} · ${p.isCompleted ? "完成" : "中断"}',
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
        // debugPrint('Pomodoro search error: $e');
      }
    }

    // ── 待办文件夹 ────────────────────────────────────────────────────────
    try {
      final groupMap = <String, Map<String, dynamic>>{};
      for (final term in searchTerms) {
        for (final row in await db.searchTodoGroups(term)) {
          groupMap[row['uuid'].toString()] = row;
        }
      }
      final groups = groupMap.values.where((g) {
        final haystack = [g['name'], g['team_name']]
            .where((s) => s != null)
            .map((s) => s.toString())
            .join(' ')
            .toLowerCase();
        return _matchesAllTerms(haystack, searchTerms);
      }).toList();
      for (var g in groups) {
        dbItems.add(SearchResult(
          id: 'db_group_${g['uuid']}',
          title: g['name'] ?? '未命名文件夹',
          subtitle:
              g['team_name'] != null ? '团队文件夹 · ${g['team_name']}' : '个人文件夹',
          icon: Icons.folder_rounded,
          type: SearchResultType.todoGroup,
          extraData: {'uuid': g['uuid'], 'table': 'todo_groups'},
        ));
      }
    } catch (e) {
      // debugPrint('Todo group search error: $e');
    }
    return dbItems;
  }

  /// 🚀 猜你想搜：非常轻量的启发式“小模型”
  /// 基于时间、任务紧急度、搜索历史、近期活动进行智能推荐
  Future<List<SearchResult>> guessSearch() async {
    final suggestions = <SearchResult>[];
    final db = DatabaseHelper.instance;
    final now = DateTime.now();
    final username = await StorageService.getLoginSession() ?? 'default';

    // 1. 时间维度：根据时刻推荐
    final hour = now.hour;

    // 🚀 新增：基于“最近”课程的推荐 (全量时间轴最近)
    try {
      final username = await StorageService.getLoginSession();
      if (username != null) {
        final allCourses = await CourseService.getAllCourses(username);
        if (allCourses.isNotEmpty) {
          CourseItem? nearestCourse;
          int minDiffSeconds = 0x7FFFFFFF; // 很大一个数
          String reason = "";

          for (var c in allCourses) {
            try {
              final dateParts = c.date.split('-');
              if (dateParts.length != 3) continue;

              final startDt = DateTime(
                  int.parse(dateParts[0]),
                  int.parse(dateParts[1]),
                  int.parse(dateParts[2]),
                  c.startTime ~/ 100,
                  c.startTime % 100);
              final endDt = DateTime(
                  int.parse(dateParts[0]),
                  int.parse(dateParts[1]),
                  int.parse(dateParts[2]),
                  c.endTime ~/ 100,
                  c.endTime % 100);

              // 1. 如果正在进行，优先级最高
              if (now.isAfter(startDt) && now.isBefore(endDt)) {
                nearestCourse = c;
                minDiffSeconds = 0;
                reason = "正在进行的课程";
                break;
              }

              // 2. 计算绝对距离
              final diffToStart = now.difference(startDt).inSeconds.abs();
              final diffToEnd = now.difference(endDt).inSeconds.abs();
              final localMin =
                  diffToStart < diffToEnd ? diffToStart : diffToEnd;

              if (localMin < minDiffSeconds) {
                minDiffSeconds = localMin;
                nearestCourse = c;
                reason = now.isBefore(startDt) ? "即将开始的课程" : "最近结束的课程";
              }
            } catch (_) {}
          }

          if (nearestCourse != null) {
            suggestions.add(SearchResult(
              id: 'guess_recent_course',
              title: nearestCourse.courseName,
              subtitle: '🎓 $reason · ${nearestCourse.roomName}',
              icon: Icons.school_rounded,
              type: SearchResultType.recommend,
              extraData: {
                'action': 'apply_query',
                'query': nearestCourse.courseName,
              },
            ));
          }
        }
      }
    } catch (_) {}

    if (hour >= 6 && hour <= 10) {
      suggestions.add(SearchResult(
        id: 'guess_today_plan',
        title: '查看今日课表与待办',
        subtitle: '✨ 早安！开启高效的一天',
        icon: Icons.wb_sunny_outlined,
        type: SearchResultType.recommend,
        extraData: {'action': 'navigate', 'route': '/course/weekly'},
      ));
    } else if (hour >= 21 || hour <= 2) {
      suggestions.add(SearchResult(
        id: 'guess_today_stats',
        title: '查看今日完成情况',
        subtitle: '🌙 晚安！回顾今日成就，展望下周规划',
        icon: Icons.insert_chart_outlined,
        type: SearchResultType.recommend,
        extraData: {
          'action': 'navigate',
          'route': '/personal_timeline',
          'initialDimension': 0 // 🚀 1 代表周视图
        },
      ));
    }

    // 2. 紧急维度：逾期任务探测 (权重最高)
    try {
      final allTodos = await StorageService.getTodos(username);
      final overdue = allTodos
          .where((t) =>
              !t.isDone &&
              !t.isDeleted &&
              t.dueDate != null &&
              t.dueDate!.isBefore(now))
          .toList();
      if (overdue.isNotEmpty) {
        suggestions.add(SearchResult(
          id: 'guess_overdue',
          title: '处理逾期任务 (${overdue.length})',
          subtitle: '⚠️ 发现已截止但未完成的任务，建议优先处理',
          icon: Icons.priority_high_rounded,
          type: SearchResultType.recommend,
          extraData: {'action': 'filter_overdue'},
        ));
      }
    } catch (_) {}

    // 3. 历史频率维度：最常搜索 (Top 1)
    try {
      final topHistory = await db.getRecentSearches(limit: 1); // 不按时段，按绝对频率
      if (topHistory.isNotEmpty) {
        final h = topHistory.first;
        suggestions.add(SearchResult(
          id: 'guess_most_frequent',
          title: h['query'],
          subtitle: '💡 您最常搜索的内容',
          icon: Icons.lightbulb_outline_rounded,
          type: SearchResultType.recommend,
          extraData: {'action': 'apply_query', 'query': h['query']},
        ));
      }
    } catch (_) {}

    // 4. 历史时间维度：最近搜索 (时段敏感型，展示前 5 条)
    try {
      final history =
          await db.getRecentSearches(limit: 5, currentHour: now.hour);
      for (var h in history) {
        // 如果已经作为“最常搜索”推荐过了，就不再在历史里重复显示（可选）
        suggestions.add(SearchResult(
          id: 'history_${h['query']}',
          title: h['query'],
          subtitle: '最近搜过',
          icon: Icons.history_rounded,
          type: SearchResultType.history,
          extraData: {'action': 'apply_query', 'query': h['query']},
        ));
      }
    } catch (_) {}

    // 4. 活动维度：近期专注活动
    try {
      final poms = await PomodoroService.getRecords();
      if (poms.isNotEmpty) {
        final lastPom = poms.first;
        if (lastPom.todoTitle != null && lastPom.todoTitle!.isNotEmpty) {
          suggestions.add(SearchResult(
            id: 'guess_recent_focus',
            title: '继续搜索: ${lastPom.todoTitle}',
            subtitle: '🔥 您最近正在专注这项任务',
            icon: Icons.local_fire_department_rounded,
            type: SearchResultType.recommend,
            extraData: {'action': 'ai_query', 'query': lastPom.todoTitle},
          ));
        }
      }
    } catch (_) {}

    // 5. 统计维度：今日屏幕时间
    suggestions.add(SearchResult(
      id: 'guess_screen_time',
      title: '今日屏幕使用时长',
      subtitle: '📊 看看今天在手机上花了多少时间',
      icon: Icons.pie_chart_rounded,
      type: SearchResultType.recommend,
      extraData: {'action': 'navigate', 'route': '/screen_time'},
    ));

    return suggestions;
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
      if ((action == 'ai_query' || action == 'apply_query') && query != null) {
        // 交给 UI 层处理：重新设置 Search Bar 的文本并触发搜索
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("正在搜索: $query"),
            duration: const Duration(seconds: 1)));
      } else if (action == 'new_todo') {
        _executeAction(context, action);
      } else if (action == 'navigate') {
        _navigateByRoute(context, route ?? '', data);
      } else if (action == 'filter_overdue') {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("已跳转至待办列表 - 逾期筛选")));
      }
      return;
    }

    if (route != null) {
      _navigateByRoute(context, route, data);
    } else if (result.type == SearchResultType.todo) {
      _handleTodoEdit(context, result);
    } else if (result.type == SearchResultType.todoGroup) {
      _handleTodoGroupNavigation(context, result);
    } else if (result.type == SearchResultType.course ||
        data['type'] == 'course_detail') {
      _handleCourseNavigation(context, result);
    }
  }

  static void _handleTodoEdit(BuildContext context, SearchResult result) async {
    try {
      final uuid = result.extraData?['uuid'];
      if (uuid == null) {
        // debugPrint("❌ _handleTodoEdit: uuid is null");
        return;
      }

      final db = DatabaseHelper.instance;
      final todoMap = await db.getTodoByUuid(uuid);
      if (todoMap == null) {
        // debugPrint("❌ _handleTodoEdit: todo not found for uuid=$uuid");
        return;
      }

      final username = await StorageService.getLoginSession();
      if (username == null) {
        // debugPrint("❌ _handleTodoEdit: no login session");
        return;
      }

      // 🚀 核心修复：due_date 在 DB 中是 TEXT (jsonType)，需要安全转 int
      int? toInt(dynamic v) {
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
        version: (todoMap['version'] is int)
            ? todoMap['version']
            : int.tryParse(todoMap['version'].toString()) ?? 1,
        updatedAt: (todoMap['updated_at'] is int)
            ? todoMap['updated_at']
            : int.tryParse(todoMap['updated_at'].toString()),
        createdAt: (todoMap['created_at'] is int)
            ? todoMap['created_at']
            : int.tryParse(todoMap['created_at'].toString()),
        createdDate: toInt(todoMap['created_date']),
        dueDate: toInt(todoMap['due_date']) != null
            ? DateTime.fromMillisecondsSinceEpoch(toInt(todoMap['due_date'])!)
            : null,
        remark: todoMap['remark']?.toString(),
        groupId: todoMap['group_id']?.toString(),
        teamUuid: todoMap['team_uuid']?.toString(),
        teamName: todoMap['team_name']?.toString(),
        collabType: (todoMap['collab_type'] is int)
            ? todoMap['collab_type']
            : int.tryParse(todoMap['collab_type'].toString()) ?? 0,
        reminderMinutes: toInt(todoMap['reminder_minutes']),
      );

      final allTodos = await StorageService.getTodos(username);
      final allGroups = await StorageService.getTodoGroups(username);
      final canonicalTodo = allTodos.cast<TodoItem?>().firstWhere(
                (candidate) => candidate?.id == todo.id,
                orElse: () => null,
              ) ??
          todo;

      if (context.mounted) {
        Navigator.push(
          context,
          PageTransitions.material(
            builder: (_) => TodoEditScreen(
              // 使用完整存储模型，保留循环规则和 recurrenceSeriesId，
              // 这样从全局搜索进入编辑页也能访问同系列的其他期次。
              todo: canonicalTodo,
              todos: allTodos,
              onTodosChanged: (newList) async {
                await StorageService.saveTodos(username, newList);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text("待办已更新"),
                        behavior: SnackBarBehavior.floating),
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
        // debugPrint("❌ _handleTodoEdit: context not mounted after async ops");
      }
    } catch (e) {
      // debugPrint("❌ _handleTodoEdit crash: $e\n$stack");
    }
  }

  static void _handleTodoGroupNavigation(
      BuildContext context, SearchResult result) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text("已跳转至文件夹: ${result.title}"),
      behavior: SnackBarBehavior.floating,
    ));
  }

  static void _handleCourseNavigation(
      BuildContext context, SearchResult result) async {
    try {
      final uuid = result.extraData?['uuid'];
      if (uuid == null) return;

      final db = DatabaseHelper.instance;
      final maps = await db.searchCourses(''); // 暂时全量搜或者加个 getCourseByUuid
      final courseMap = maps.firstWhere(
          (m) => m['uuid'].toString() == uuid.toString(),
          orElse: () => {});

      if (courseMap.isNotEmpty) {
        final course = CourseItem.fromJson(courseMap);
        if (context.mounted) {
          Navigator.push(
              context,
              PageTransitions.material(
                  builder: (_) => CourseDetailScreen(course: course)));
        }
      }
    } catch (e) {
      // debugPrint("❌ _handleCourseNavigation error: $e");
    }
  }

  static void _navigateByRoute(
      BuildContext context, String route, Map<String, dynamic> data) async {
    final target = data['target'] as String?;
    Widget? page;
    final username = await StorageService.getLoginSession() ?? 'default';
    if (!context.mounted) return;

    if (route == '/time_log/tag') {
      final tagUuid = data['tag_uuid'];
      if (tagUuid != null) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        Navigator.push(
            context,
            PageTransitions.material(
                builder: (_) => TimeLogScreen(
                    username: username, initialTagUuid: tagUuid)));
      }
      return;
    }

    if (route == '/screen_time/app') {
      final appName = data['app_name'];
      if (appName != null) {
        final history = await StorageService.getScreenTimeHistory();
        final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
        if (history[todayKey] == null || history[todayKey]!.isEmpty) {
          final cachedToday = await StorageService.getScreenTimeCache();
          if (cachedToday.isNotEmpty) {
            history[todayKey] = cachedToday;
          }
        }
        if (!context.mounted) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
        Navigator.push(
            context,
            PageTransitions.material(
                builder: (_) => AppDetailScreen(
                      appName: appName,
                      historyStats: history,
                      filter: DeviceFilter.all,
                      range: ScreenTimeRange.day,
                      anchorDate: DateTime.now(),
                    )));
      }
      return;
    }

    switch (route) {
      case '/pomodoro/stats':
        final dim = data['initialDimension'] as int? ?? 0;
        page = PomodoroScreen(
            username: username, initialTab: 1, initialDimension: dim);
        break;
      case '/personal_timeline':
        final dimIndex = data['initialDimension'] as int? ?? 0;
        final dim = dimIndex >= 0 && dimIndex < TimelineDimension.values.length
            ? TimelineDimension.values[dimIndex]
            : TimelineDimension.daily;
        page = PersonalTimelineScreen(
          username: username,
          initialDimension: dim,
        );
        break;
      case '/time_log/manual':
        page = TimeLogScreen(username: username);
        break;
      case '/settings':
        page = SettingsPage(initialTarget: target);
        break;
      case '/about':
        page = const AboutScreen();
        break;
      case '/login':
        Navigator.pushNamed(context, '/login');
        return;
      case '/teams':
        if (context.mounted) {
          Navigator.push(
              context,
              PageTransitions.slideHorizontal(TeamManagementScreen(
                  username: username, initialTarget: target)));
        }
        return;
      case '/today':
        Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      case '/course/weekly':
        page = WeeklyCourseScreen(username: username);
        break;
      case '/tomorrow':
        Navigator.of(context).popUntil((route) => route.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("已跳转至主页 - 请查看明日安排"),
            behavior: SnackBarBehavior.floating));
        return;
      case '/screen_time':
        final cache = await StorageService.getScreenTimeCache();
        page = ScreenTimeDetailScreen(todayStats: cache);
        break;
      case '/habits':
        final habitUuid = data['habit_uuid']?.toString();
        if (habitUuid != null && habitUuid.isNotEmpty) {
          final goals = await HabitRepository.getGoals();
          HabitGoal? goal;
          for (final candidate in goals) {
            if (candidate.uuid == habitUuid) {
              goal = candidate;
              break;
            }
          }
          page = goal == null
              ? HabitCenterScreen(username: username)
              : HabitDetailScreen(goal: goal, username: username);
        } else {
          page = HabitCenterScreen(username: username);
        }
        break;
      case '/challenge':
        page = const ThirtyDayChallengeScreen();
        break;
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
}
