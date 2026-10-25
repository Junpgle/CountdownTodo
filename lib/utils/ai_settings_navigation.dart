import 'package:flutter/material.dart';

import '../screens/plan_weekly_availability_screen.dart';

import '../features/finance/screens/finance_automation_screen.dart';
import '../features/finance/screens/finance_settings_screen.dart';
import '../screens/about_screen.dart';
import '../screens/animation_settings_page.dart';
import '../screens/band_sync_screen.dart';
import '../screens/course_calendar_adjustment_screen.dart';
import '../course_import/widgets/course_adaptation_screen.dart';
import '../screens/feature_guide_screen.dart';
import '../screens/help/feature_explorer_screen.dart';
import '../screens/help/help_center_screen.dart';
import '../screens/home_settings_screen.dart';
import '../screens/pomodoro_screen.dart';
import '../screens/pomodoro/unified_tag_manager_screen.dart';
import '../screens/settings/rebind_tag_page.dart';
import '../services/pomodoro_service.dart';
import '../screens/settings_screen.dart';
import '../screens/settings/batch_tag_page.dart';
import '../screens/settings/calendar_sync_page.dart';
import '../screens/settings/device_calendar_read_page.dart';
import '../screens/settings/device_version_detail_page.dart';
import '../screens/settings/home_text_config_page.dart';
import '../screens/settings/lan_sync_screen.dart';
import '../screens/settings/llm_config_page.dart';
import '../screens/settings/notification_settings_page.dart';
import '../screens/settings/server_choice_page.dart';
import '../screens/settings/pages/ai_assistant_settings_page.dart';
import '../screens/settings/pages/course_settings_page.dart';
import '../screens/settings/pages/data_export_page.dart';
import '../screens/settings/pages/data_import_page.dart';
import '../screens/settings/pages/home_layout_settings_page.dart';
import '../screens/settings/pages/interconnect_settings_page.dart';
import '../screens/settings/pages/mcp_introduction_page.dart';
import '../screens/settings/pages/minor_mode_settings_page.dart';
import '../screens/settings/pages/permission_settings_page.dart';
import '../screens/settings/pages/platform_specific_settings_page.dart';
import '../screens/settings/pages/preference_settings_page.dart';
import '../screens/settings/pages/recurrence_series_merge_page.dart';
import '../screens/settings/pages/sync_health_page.dart';
import '../screens/settings/pages/sidebar_menu_settings_page.dart';
import '../screens/settings/wallpaper_settings_page.dart';
import '../services/ai_settings_navigation_service.dart';
import '../services/app_settings_catalog.dart';
import '../storage_service.dart';
import '../widgets/settings_focus_page.dart';
import 'settings_navigation.dart';

abstract final class AiSettingsNavigation {
  static Widget? pageFor(String id, {required String username}) {
    final destination = AiSettingsNavigationService.destination(id);
    if (destination == null) return null;
    final page = switch (destination.page) {
      SettingsPageId.account || SettingsPageId.updates => SettingsPage(
        initialTarget: id == 'change_password' ? id : 'account',
        openInitialTargetAsRoot: true,
      ),
      SettingsPageId.server => Builder(
        builder: (context) => FutureBuilder<String>(
          future: StorageService.getServerChoice(),
          builder: (context, snapshot) => snapshot.hasData
              ? ServerChoicePage(initialServerChoice: snapshot.data!)
              : const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                ),
        ),
      ),
      SettingsPageId.preference => const PreferenceSettingsPage(),
      SettingsPageId.animation => AnimationSettingsPage(
        initialTarget: id == 'liquid_glass' || id == 'liquid_glass_transparency'
            ? id
            : null,
      ),
      SettingsPageId.wallpaper => const WallpaperSettingsPage(),
      SettingsPageId.homeLayout => const HomeLayoutSettingsPage(),
      SettingsPageId.sidebar => const SidebarMenuSettingsPage(),
      SettingsPageId.homeText => const HomeTextConfigPage(),
      SettingsPageId.ai => const AiAssistantSettingsPage(),
      SettingsPageId.llm => LLMConfigPage(
        initialTarget: id,
        initialStep: switch (id) {
          'llm_providers' => 0,
          'llm_api_keys' => 1,
          'llm_text_model' ||
          'llm_vision_model' ||
          'llm_recognition' ||
          'llm_text_prompt' ||
          'llm_vision_prompt' ||
          'llm_test' ||
          'llm_prompt_reset' ||
          'llm_custom_text' ||
          'llm_custom_vision' => 2,
          _ => null,
        },
      ),
      SettingsPageId.course => switch (id) {
        'course_calendar_adjustment' ||
        'course_holidays' ||
        'course_transfers' => const CourseCalendarAdjustmentScreen(),
        'course_adapt' => const CourseAdaptationScreen(),
        'semester_start' ||
        'semester_end' ||
        'semester_name' => CourseSettingsPage(initialTarget: id),
        _ => const CourseSettingsPage(),
      },
      SettingsPageId.interconnect => InterconnectSettingsPage(
        username: username,
      ),
      SettingsPageId.lan => const LanSyncScreen(),
      SettingsPageId.mcp => const McpIntroductionPage(),
      SettingsPageId.band => const BandSyncScreen(),
      SettingsPageId.calendar => const CalendarSyncPage(),
      SettingsPageId.calendarRead => const DeviceCalendarReadPage(),
      SettingsPageId.weeklyPlanAvailability => PlanWeeklyAvailabilityScreen(
        username: username,
      ),
      SettingsPageId.batchTag => BatchTagPage(username: username),
      SettingsPageId.rebindTag => RebindTagPage(username: username),
      SettingsPageId.tags => Builder(
        builder: (context) => FutureBuilder<List<PomodoroTag>>(
          future: PomodoroService.getTags(),
          builder: (context, snapshot) => snapshot.hasData
              ? UnifiedTagManagerScreen(allTags: snapshot.data!)
              : Scaffold(
                  body: Center(
                    child: snapshot.hasError
                        ? const Text('标签加载失败，请返回后重试')
                        : const CircularProgressIndicator(),
                  ),
                ),
        ),
      ),
      SettingsPageId.recurrenceMerge => RecurrenceSeriesMergePage(
        username: username,
      ),
      SettingsPageId.syncHealth => SyncHealthPage(username: username),
      SettingsPageId.exportData => const DataExportPage(),
      SettingsPageId.importData => const DataImportPage(),
      SettingsPageId.notifications => const NotificationSettingsPage(),
      SettingsPageId.permissions => const PermissionSettingsPage(),
      SettingsPageId.minor => const MinorModeSettingsPage(),
      SettingsPageId.platform => const PlatformSpecificSettingsPage(),
      SettingsPageId.about => const AboutScreen(),
      SettingsPageId.deviceVersions => const DeviceVersionDetailPage(),
      SettingsPageId.help =>
        id == 'feature_explorer'
            ? FeatureExplorerScreen(username: username)
            : const HelpCenterScreen(),
      SettingsPageId.guide => FeatureGuideScreen(
        mode: FeatureGuideMode.guide,
        loggedInUser: username,
      ),
      SettingsPageId.changelog => FeatureGuideScreen(
        mode: FeatureGuideMode.changelog,
        loggedInUser: username,
      ),
      SettingsPageId.finance => FinanceSettingsScreen(
        username: username,
        initialPreferences: !{
          'finance_settings',
          'finance_expense_categories',
          'finance_income_categories',
          'finance_payment_methods',
        }.contains(id),
        initialCatalogSection: switch (id) {
          'finance_income_categories' => 'income',
          'finance_payment_methods' => 'payment',
          _ => 'expense',
        },
      ),
      SettingsPageId.financeAutomation => const FinanceAutomationScreen(),
      SettingsPageId.math => const SettingsScreen(),
      SettingsPageId.pomodoro => PomodoroScreen(
        username: username,
        initialSettingsTarget: id,
      ),
    };
    // These destinations already reveal an exact control, or open their own
    // editor/dialog. Every other labelled control uses the shared locator.
    if (destination.labels.isEmpty ||
        id == 'feature_explorer' ||
        id == 'liquid_glass' ||
        id == 'liquid_glass_transparency' ||
        id == 'course_calendar_adjustment' ||
        id == 'course_adapt' ||
        id == 'llm_custom_text' ||
        id == 'llm_custom_vision' ||
        id == 'semester_start' ||
        id == 'semester_end' ||
        id == 'semester_name' ||
        (destination.page == SettingsPageId.pomodoro &&
            {
              'pomodoro_settings',
              'pomodoro_focus',
              'pomodoro_break',
              'pomodoro_cycles',
            }.contains(id))) {
      return page;
    }
    return SettingsFocusPage(
      labels: destination.labels,
      fallbackLabels: _fallbackLabels(destination),
      child: page,
    );
  }

  static List<String> _fallbackLabels(AiSettingsDestination item) =>
      switch (item.page) {
        SettingsPageId.wallpaper => ['壁纸来源'],
        SettingsPageId.homeText => ['时间问候语模式', '随机问候语模式'],
        SettingsPageId.course => ['学期管理'],
        SettingsPageId.minor => ['状态'],
        SettingsPageId.llm => ['配置 API Key', '选择模型'],
        _ => const [],
      };

  static Future<void> open({
    required BuildContext context,
    required String target,
    required String username,
    required GlobalKey sourceKey,
  }) async {
    final destination = AiSettingsNavigationService.destination(target);
    final page = pageFor(target, username: username);
    if (destination == null || page == null || !context.mounted) return;
    await SettingsNavigation.push<void>(
      context: context,
      page: page,
      sourceKey: sourceKey,
      settings: RouteSettings(name: destination.path),
      placeholderIcon: Icons.settings_rounded,
    );
  }
}
