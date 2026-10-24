import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FeatureTipService {
  static const String _prefix = 'tip_shown_';
  static const String _badgePrefix = 'feature_badge_seen_';
  static const String _checklistDismissedKey =
      'onboarding_checklist_dismissed_v1';

  /// 通知 UI 引导提示、新功能徽章或探索清单状态已变更
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// 检查是否已经显示过特定引导
  static Future<bool> hasTipBeenShown(String tipId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_prefix$tipId') ?? false;
  }

  /// 标记特定引导已显示
  static Future<void> markTipShown(String tipId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefix$tipId', true);
    revision.value++;
  }

  /// 检查某个新功能微徽章（NEW / 蓝点）是否尚未被用户点击查看
  static Future<bool> isFeatureBadgeUnread(String badgeId) async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool('$_badgePrefix$badgeId') ?? false);
  }

  /// 批量获取已读的新功能徽章集合
  static Future<Set<String>> getSeenFeatureBadges() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = <String>{};
    for (final key in prefs.getKeys()) {
      if (key.startsWith(_badgePrefix) && (prefs.getBool(key) ?? false)) {
        seen.add(key.substring(_badgePrefix.length));
      }
    }
    return seen;
  }

  /// 页面组件类型名到百宝箱功能 ID 的映射：只有当用户真正打开对应功能页面时才自动标记为已体验
  static const List<(String, List<String>)> _widgetTypeToFeatureIds = [
    ('FixedScheduleEditorScreen', ['fixed_schedule_related_todo']),
    ('TodoPlanScreen', ['todo_plan_center']),
    ('PlanWeeklyAvailabilityScreen', ['weekly_plan_availability']),
    ('WeeklyPlanAvailabilityPage', ['weekly_plan_availability']),
    ('AddTodoScreen', ['todos_and_countdowns']),
    ('AddCountdownScreen', ['todos_and_countdowns']),
    ('FolderManageScreen', ['todo_folders_and_groups']),
    ('WeeklyCourseScreen', ['course_schedule_and_import']),
    ('CourseCalendarAdjustmentScreen', ['course_holiday_adjustment']),
    ('DeviceCalendarReadPage', ['device_calendar_read']),
    ('CalendarSyncPage', ['calendar_sync_and_ics']),
    ('RecurrenceSeriesMergePage', ['recurrence_series_merge']),
    (
      'NotificationSettingsPage',
      ['notification_multi_reminders', 'tip_special_code_live_island'],
    ),
    ('PomodoroScreen', ['pomodoro_focus', 'pomodoro_stats_board']),
    ('TimeLogScreen', ['time_log_and_backfill']),
    ('PlanBlockStatsScreen', ['plan_execution_review_stats']),
    ('ScreenTimeDetailScreen', ['screen_time_and_app_limits']),
    ('BatchTagPage', ['batch_tag_and_rebind']),
    ('PersonalTimelineScreen', ['personal_timeline_report']),
    ('MedalWallPage', ['medal_wall_achievements']),
    ('JournalHomeScreen', ['private_journal']),
    ('FinanceHomeScreen', ['finance_and_ai_bill']),
    ('FinanceAutomationScreen', ['finance_recurring_and_templates']),
    ('FinanceFutureCommitmentsScreen', ['finance_loans_and_commitments']),
    ('FinanceLoanScreen', ['finance_loans_and_commitments']),
    ('HabitCenterScreen', ['habit_center']),
    ('ChallengeCenterScreen', ['thirty_day_challenge']),
    ('ThirtyDayChallengeScreen', ['thirty_day_challenge']),
    ('MathMenuScreen', ['math_wake_up_quiz']),
    ('TodoChatScreen', ['ai_assistant_and_tutorial']),
    ('AiAssistantTutorialScreen', ['ai_assistant_and_tutorial']),
    ('McpIntroductionPage', ['mcp_external_ai_bridge']),
    ('UnifiedWaterfallScreen', ['team_waterfall_and_gantt']),
    ('AiUsageCostScreen', ['ai_usage_cost_ledger']),
    ('SyncHealthPage', ['sync_health_diagnostics']),
    ('DeviceVersionDetailPage', ['sync_health_diagnostics']),
    ('GlobalSearchOverlay', ['global_search_command_palette']),
    ('TeamManagementScreen', ['team_collaboration']),
    ('ConflictInboxScreen', ['cloud_sync_and_conflict_inbox']),
    ('LanSyncScreen', ['lan_direct_sync']),
    ('BandSyncScreen', ['xiaomi_band_sync']),
    ('AnimationSettingsPage', ['animation_liquid_glass']),
    ('DataExportPage', ['data_backup_and_restore']),
    ('DataImportPage', ['data_backup_and_restore']),
    ('PlatformSpecificSettingsPage', ['platform_island_and_widgets']),
    ('HistoricalTodosScreen', ['tip_recycle_bin_multi_restore']),
    ('HomeLayoutSettingsPage', ['tip_customize_home_and_drawer']),
    ('SidebarMenuSettingsPage', ['tip_customize_home_and_drawer']),
    ('ThemeColorSettingsPage', ['tip_global_theme_color']),
    ('WallpaperSettingsPage', ['tip_bing_and_custom_wallpaper']),
    ('HomeTextConfigPage', ['tip_custom_salutation_and_greetings']),
  ];

  /// 标记某个新功能微徽章为已体验/已读
  static Future<void> markFeatureBadgeSeen(String badgeId) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('$_badgePrefix$badgeId') ?? false) return;
    await prefs.setBool('$_badgePrefix$badgeId', true);
    revision.value++;
  }

  /// 当用户真正打开某个具体功能界面时自动记录为已体验
  static Future<void> recordWidgetOpened(Object page) async {
    final typeName = page.runtimeType.toString();
    final matchedIds = <String>[];
    for (final (needle, featureIds) in _widgetTypeToFeatureIds) {
      if (typeName.contains(needle)) {
        matchedIds.addAll(featureIds);
      }
    }
    if (matchedIds.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    var changed = false;
    for (final id in matchedIds) {
      final key = '$_badgePrefix$id';
      if (!(prefs.getBool(key) ?? false)) {
        await prefs.setBool(key, true);
        changed = true;
      }
    }
    if (changed) {
      revision.value++;
    }
  }

  /// 重置所有引导状态、新功能徽章与新手探索卡片隐藏状态
  static Future<void> resetAllTips() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where(
          (k) =>
              k.startsWith(_prefix) ||
              k.startsWith(_badgePrefix) ||
              k == _checklistDismissedKey,
        )
        .toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
    revision.value++;
  }
}
