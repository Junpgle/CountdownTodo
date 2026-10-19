import 'dart:convert';

import 'app_settings_catalog.dart';
export 'app_settings_catalog.dart' show AiSettingsDestination;

/// The model selects an ID; titles, paths and actual routes are owned by the app.
abstract final class AiSettingsNavigationService {
  static final RegExp _settingsBlockPattern = RegExp(
    r'\[SETTINGS_START\](.*?)\[SETTINGS_END\]',
    dotAll: true,
  );
  static final RegExp _settingsBlockCleanupPattern = RegExp(
    r'\[SETTINGS_START\].*?(?:\[SETTINGS_END\]|$)',
    dotAll: true,
  );
  static const toolName = 'propose_settings_navigation';
  static const destinations = AppSettingsCatalog.destinations;
  static List<AiSettingsDestination> get availableDestinations =>
      AppSettingsCatalog.available;

  /// Settings navigation competes with write proposals when both are offered
  /// as functions. Only expose it for a clear settings or settings-destination
  /// request, rather than on every ordinary data-management turn.
  static bool shouldOfferForRequest(String userMessage) {
    final text = userMessage.trim().toLowerCase();
    if (text.isEmpty) return false;

    const explicitSettingsRequests = [
      '设置在哪',
      '设置在哪里',
      '设置页面',
      '设置页',
      '设置入口',
      '设置项',
      '设置选项',
      '系统设置',
      '应用设置',
      '偏好设置',
      '功能设置',
      '打开设置',
      '进入设置',
      '前往设置',
      '怎么设置',
      '如何设置',
      '调整设置',
      '修改设置',
      '更改设置',
      '帮我找设置',
      '查找设置',
    ];
    if (explicitSettingsRequests.any(text.contains)) return true;

    const settingSubjects = [
      '主题',
      '深色模式',
      '浅色模式',
      '外观',
      '字体',
      '字号',
      '壁纸',
      '透明度',
      '背景',
      '账户管理',
      '账号管理',
      '修改密码',
      '同步频率',
      '同步间隔',
      '云端线路',
      'AI助手',
      'AI模型',
      '模型配置',
      'API配置',
      '语音识别',
      '通知设置',
      '权限设置',
      '默认提醒',
      '缓存',
      '数据导出',
      '数据导入',
      '首页布局',
      '侧边栏',
      '动画',
      '小米手环',
      '番茄设置',
    ];
    final mentionsSettingSubject =
        settingSubjects.any(text.contains) ||
        availableDestinations.any((item) {
          final labels = [item.title, ...item.labels];
          return labels.any(
            (label) =>
                label.trim().isNotEmpty && text.contains(label.toLowerCase()),
          );
        });
    if (!mentionsSettingSubject) return false;

    const settingsActions = [
      '在哪里',
      '在哪',
      '怎么进',
      '如何进',
      '怎么打开',
      '如何打开',
      '怎么调',
      '如何调',
      '入口',
      '设置',
      '配置',
      '调整',
      '调节',
      '调大',
      '调小',
      '修改',
      '更改',
      '改成',
      '改为',
      '换成',
      '设为',
      '设置成',
      '设置为',
      '打开',
      '关闭',
      '开启',
      '启用',
      '禁用',
      '放大',
      '缩小',
      '增大',
      '减小',
    ];
    return settingsActions.any(text.contains);
  }

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
    for (final match in _settingsBlockPattern.allMatches(content)) {
      try {
        final decoded = jsonDecode(match.group(1)!.trim());
        if (decoded is Map) targets.addAll(validateTargets(decoded['targets']));
      } catch (_) {
        // Incomplete or invalid model output never becomes a navigation route.
      }
    }
    return validateTargets(targets);
  }

  static String cleanContent(String content) =>
      content.replaceAll(_settingsBlockCleanupPattern, '').trim();
}
