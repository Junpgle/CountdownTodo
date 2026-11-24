import 'package:flutter/foundation.dart';

import '../utils/app_platform.dart';

part 'settings_catalog/app_settings_catalog_part1.dart';
part 'settings_catalog/app_settings_catalog_part2.dart';
part 'settings_catalog/app_settings_catalog_part3.dart';

enum SettingsPageId {
  account,
  accountDevices,
  server,
  updates,
  syncHealth,
  preference,
  wallpaper,
  homeLayout,
  sidebar,
  homeText,
  animation,
  ai,
  llm,
  course,
  interconnect,
  lan,
  mcp,
  band,
  calendar,
  calendarRead,
  weeklyPlanAvailability,
  batchTag,
  tags,
  rebindTag,
  recurrenceMerge,
  exportData,
  importData,
  notifications,
  permissions,
  minor,
  platform,
  about,
  deviceVersions,
  help,
  guide,
  changelog,
  finance,
  financeAutomation,
  math,
  pomodoro,
}

class AiSettingsDestination {
  final String id;
  final String title;
  final String path;
  final String description;
  final SettingsPageId page;
  final List<String> labels;
  final Set<String> platforms;

  const AiSettingsDestination({
    required this.id,
    required this.title,
    required this.path,
    required this.description,
    required this.page,
    this.labels = const [],
    this.platforms = const {},
  });

  bool availableOn(String platform, {bool debug = !kReleaseMode}) =>
      platforms.every(
        (restriction) => switch (restriction) {
          'native' => platform != 'web',
          'mobile' => platform == 'android' || platform == 'ios',
          'debug' => debug,
          _ => platform == restriction,
        },
      );
}

/// Full directory of settings entries and controls. IDs remain stable in chat
/// history; routes and visible labels are app-owned, never supplied by the model.
abstract final class AppSettingsCatalog {
  static List<AiSettingsDestination> get available =>
      forPlatform(AppPlatform.isWeb ? 'web' : AppPlatform.operatingSystem);
  static List<AiSettingsDestination> forPlatform(
    String platform, {
    bool debug = !kReleaseMode,
  }) => [
    for (final item in destinations)
      if (item.availableOn(platform, debug: debug)) item,
  ];
  static const destinations = <AiSettingsDestination>[
    ..._appSettingsDestinationsPart1,
    ..._appSettingsDestinationsPart2,
    ..._appSettingsDestinationsPart3,
  ];
}
