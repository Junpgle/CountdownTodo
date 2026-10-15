import 'dart:io';

import 'package:countdown_todo/services/app_settings_catalog.dart';
import 'package:countdown_todo/services/ai_settings_navigation_service.dart';
import 'package:countdown_todo/utils/ai_settings_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

// Audit against the pages that actually render each catalogued setting, so
// renaming/removing a control cannot silently leave an unusable AI destination.
const pageSources = <SettingsPageId, List<String>>{
  SettingsPageId.tags: ['lib/screens/pomodoro/unified_tag_manager_screen.dart'],
  SettingsPageId.rebindTag: ['lib/screens/settings/rebind_tag_page.dart'],
  SettingsPageId.account: [
    'lib/screens/settings/widgets/account_section.dart',
    'lib/screens/settings/widgets/sync_settings_section.dart',
  ],
  SettingsPageId.updates: [
    'lib/screens/settings/widgets/update_settings_section.dart',
  ],
  SettingsPageId.server: ['lib/screens/settings/server_choice_page.dart'],
  SettingsPageId.preference: [
    'lib/screens/settings/pages/preference_settings_page.dart',
  ],
  SettingsPageId.wallpaper: [
    'lib/screens/settings/wallpaper_settings_page.dart',
  ],
  SettingsPageId.homeLayout: [
    'lib/screens/settings/pages/home_layout_settings_page.dart',
  ],
  SettingsPageId.sidebar: [
    'lib/screens/settings/pages/sidebar_menu_settings_page.dart',
    'lib/services/sidebar_menu_service.dart',
  ],
  SettingsPageId.homeText: ['lib/screens/settings/home_text_config_page.dart'],
  SettingsPageId.animation: ['lib/screens/animation_settings_page.dart'],
  SettingsPageId.ai: [
    'lib/screens/settings/pages/ai_assistant_settings_page.dart',
    'lib/widgets/ai_context_mode_selector.dart',
  ],
  SettingsPageId.llm: ['lib/screens/settings/llm_config_page.dart'],
  SettingsPageId.course: [
    'lib/screens/settings/pages/course_settings_page.dart',
    'lib/screens/course_calendar_adjustment_screen.dart',
  ],
  SettingsPageId.interconnect: [
    'lib/screens/settings/pages/interconnect_settings_page.dart',
  ],
  SettingsPageId.lan: ['lib/screens/settings/lan_sync_screen.dart'],
  SettingsPageId.mcp: ['lib/screens/settings/pages/mcp_introduction_page.dart'],
  SettingsPageId.band: ['lib/screens/band_sync_screen.dart'],
  SettingsPageId.calendar: ['lib/screens/settings/calendar_sync_page.dart'],
  SettingsPageId.calendarRead: [
    'lib/screens/settings/device_calendar_read_page.dart',
  ],
  SettingsPageId.batchTag: ['lib/screens/settings/batch_tag_page.dart'],
  SettingsPageId.recurrenceMerge: [
    'lib/screens/settings/pages/recurrence_series_merge_page.dart',
  ],
  SettingsPageId.exportData: [
    'lib/screens/settings/pages/data_export_page.dart',
  ],
  SettingsPageId.importData: [
    'lib/screens/settings/pages/data_import_page.dart',
  ],
  SettingsPageId.notifications: [
    'lib/screens/settings/notification_settings_page.dart',
  ],
  SettingsPageId.permissions: [
    'lib/screens/settings/pages/permission_settings_page.dart',
    'lib/screens/settings/widgets/permission_section.dart',
    'lib/screens/settings/handlers/permission_handler.dart',
  ],
  SettingsPageId.minor: [
    'lib/screens/settings/pages/minor_mode_settings_page.dart',
  ],
  SettingsPageId.platform: [
    'lib/screens/settings/pages/platform_specific_settings_page.dart',
  ],
  SettingsPageId.about: ['lib/screens/about_screen.dart'],
  SettingsPageId.deviceVersions: [
    'lib/screens/settings/device_version_detail_page.dart',
  ],
  SettingsPageId.help: ['lib/screens/help/help_center_screen.dart'],
  SettingsPageId.guide: ['lib/screens/feature_guide_screen.dart'],
  SettingsPageId.changelog: ['lib/screens/feature_guide_screen.dart'],
  SettingsPageId.finance: [
    'lib/features/finance/screens/finance_settings_screen.dart',
    'lib/features/finance/widgets/finance_catalog_manager.dart',
  ],
  SettingsPageId.financeAutomation: [
    'lib/features/finance/screens/finance_automation_screen.dart',
  ],
  SettingsPageId.math: ['lib/screens/settings_screen.dart'],
  SettingsPageId.pomodoro: ['lib/screens/pomodoro/views/workbench_view.dart'],
};

void main() {
  test('all settings pages have unique catalogue destinations', () {
    final items = AppSettingsCatalog.destinations;
    final ids = items.map((item) => item.id).toSet();
    expect(ids.length, items.length);
    expect(
      items.map((item) => item.page).toSet(),
      SettingsPageId.values.toSet(),
    );
  });

  test('catalogue labels belong to their real destination pages', () {
    for (final item in AppSettingsCatalog.destinations) {
      expect(item.path, isNotEmpty, reason: item.id);
      expect(item.description, isNotEmpty, reason: item.id);
      if (item.labels.isEmpty) continue;
      final source = pageSources[item.page]!
          .map((path) => File(path).readAsStringSync())
          .join('\n');
      expect(
        item.labels.any(source.contains),
        isTrue,
        reason: '${item.id}: ${item.labels}',
      );
    }
  });

  test('platform filters exclude unavailable native and OS controls', () {
    for (final platform in [
      'web',
      'android',
      'ios',
      'windows',
      'macos',
      'linux',
    ]) {
      final available = AppSettingsCatalog.forPlatform(platform, debug: false);
      final ids = available.map((item) => item.id).toSet();
      expect(
        ids,
        containsAll([
          'liquid_glass_transparency',
          'ai_context_mode',
          'finance_settings',
          'math_settings',
        ]),
      );
      expect(ids.contains('mac_status_bar'), platform == 'macos');
      expect(ids.contains('float_window_style'), platform == 'windows');
      expect(ids.contains('band_sync'), platform == 'android');
      expect(
        ids.contains('calendar_read'),
        platform == 'android' || platform == 'ios',
      );
      expect(ids.contains('permissions'), platform != 'web');
      expect(ids, isNot(contains('about_frame_monitor')));
    }
    expect(
      AppSettingsCatalog.forPlatform(
        'macos',
        debug: true,
      ).map((item) => item.id),
      contains('about_frame_monitor'),
    );
  });

  test('every offered native-tool destination resolves to a real page', () {
    for (final item in AiSettingsNavigationService.availableDestinations) {
      expect(
        AiSettingsNavigation.pageFor(item.id, username: 'test'),
        isNotNull,
        reason: item.id,
      );
    }
  });
}
