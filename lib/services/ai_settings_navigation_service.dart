import 'dart:convert';

import 'app_settings_catalog.dart';
export 'app_settings_catalog.dart' show AiSettingsDestination;

/// The model selects an ID; titles, paths and actual routes are owned by the app.
abstract final class AiSettingsNavigationService {
  static const toolName = 'propose_settings_navigation';
  static const destinations = AppSettingsCatalog.destinations;
  static List<AiSettingsDestination> get availableDestinations =>
      AppSettingsCatalog.available;

  static AiSettingsDestination? destination(String id) {
    for (final item in availableDestinations) {
      if (item.id == id) return item;
    }
    return null;
  }

  static List<String> validateTargets(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<String>()
        .where((id) => destination(id) != null)
        .toSet()
        .take(3)
        .toList(growable: false);
  }

  static Map<String, dynamic> buildDefinition() => {
    'type': 'function',
    'function': {
      'name': toolName,
      'description':
          '当用户想查找、调整应用设置或询问设置在哪里时，展示一键直达卡片。'
          '只提供入口，不会修改设置或自动跳转。选择最具体的选项，最多3项。\n'
          '${availableDestinations.map((item) => '${item.id}: ${item.path}；${item.description}').join('\n')}',
      'parameters': {
        'type': 'object',
        'properties': {
          'targets': {
            'type': 'array',
            'minItems': 1,
            'maxItems': 3,
            'uniqueItems': true,
            'items': {
              'type': 'string',
              'enum': availableDestinations.map((item) => item.id).toList(),
            },
          },
        },
        'required': ['targets'],
        'additionalProperties': false,
      },
    },
  };

  static String buildPrompt({required bool nativeToolCalls}) =>
      '【应用设置导航】\n用户想找设置、调整应用外观或功能偏好时，提供最具体的设置入口卡片，'
      '由用户点击后进入设置手动调整，不要声称已修改。液态玻璃透明度请选择liquid_glass_transparency。'
      '${nativeToolCalls ? '使用propose_settings_navigation工具。' : '\n可选入口：\n${availableDestinations.map((item) => '${item.id}: ${item.path}；${item.description}').join('\n')}\n在正文后输出[SETTINGS_START]{"targets":["入口ID"]}[SETTINGS_END]，最多3个有效ID，不编造入口。'}';

  static List<String> targetsFromArguments(String arguments) {
    try {
      final decoded = jsonDecode(arguments);
      return decoded is Map ? validateTargets(decoded['targets']) : const [];
    } catch (_) {
      return const [];
    }
  }

  static List<String> extractTargets(String content) {
    final targets = <String>[];
    for (final match in RegExp(
      r'\[SETTINGS_START\](.*?)\[SETTINGS_END\]',
      dotAll: true,
    ).allMatches(content)) {
      try {
        final decoded = jsonDecode(match.group(1)!.trim());
        if (decoded is Map) targets.addAll(validateTargets(decoded['targets']));
      } catch (_) {
        // Incomplete or invalid model output never becomes a navigation route.
      }
    }
    return validateTargets(targets);
  }

  static String cleanContent(String content) => content
      .replaceAll(
        RegExp(r'\[SETTINGS_START\].*?(?:\[SETTINGS_END\]|$)', dotAll: true),
        '',
      )
      .trim();
}
