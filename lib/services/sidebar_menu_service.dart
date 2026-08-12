import 'dart:convert';

import 'package:flutter/material.dart';

import '../storage_service.dart';
import 'storage/storage_key_scope.dart';

enum SidebarMenuTarget {
  features,
  utilities,
}

class SidebarMenuPair {
  final List<String> features;
  final List<String> utilities;

  const SidebarMenuPair({
    required this.features,
    required this.utilities,
  });
}

class SidebarMenuItemDefinition {
  final String key;
  final String title;
  final IconData icon;
  final SidebarMenuTarget defaultTarget;

  const SidebarMenuItemDefinition({
    required this.key,
    required this.title,
    required this.icon,
    required this.defaultTarget,
  });
}

/// Stores the configurable entries shown in the home drawer.
///
/// The setting is scoped to the current account so users can keep different
/// drawer layouts on the same device. New menu entries are appended to their
/// default group during normalization for a safe upgrade path.
class SidebarMenuService {
  const SidebarMenuService._();

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Base keys used by the backup importer before the current username is
  /// appended. Keep this list in one place so import/export stay compatible.
  static const Set<String> userScopedKeys = {
    'sidebar_menu_order_features',
    'sidebar_menu_order_utilities',
    'sidebar_menu_visibility',
  };

  static bool isUserSpecificKey(String key) => userScopedKeys.contains(key);

  static const Map<String, SidebarMenuItemDefinition> definitions = {
    'teams': SidebarMenuItemDefinition(
      key: 'teams',
      title: '群组团队',
      icon: Icons.people_rounded,
      defaultTarget: SidebarMenuTarget.features,
    ),
    'aiAssistant': SidebarMenuItemDefinition(
      key: 'aiAssistant',
      title: 'AI 助手',
      icon: Icons.smart_toy_outlined,
      defaultTarget: SidebarMenuTarget.features,
    ),
    'timeline': SidebarMenuItemDefinition(
      key: 'timeline',
      title: '个人报告',
      icon: Icons.timeline_rounded,
      defaultTarget: SidebarMenuTarget.features,
    ),
    'journal': SidebarMenuItemDefinition(
      key: 'journal',
      title: '日记',
      icon: Icons.auto_stories_rounded,
      defaultTarget: SidebarMenuTarget.features,
    ),
    'screenTime': SidebarMenuItemDefinition(
      key: 'screenTime',
      title: '时间日志',
      icon: Icons.pie_chart_rounded,
      defaultTarget: SidebarMenuTarget.features,
    ),
    'planCenter': SidebarMenuItemDefinition(
      key: 'planCenter',
      title: '规划中心',
      icon: Icons.edit_calendar_rounded,
      defaultTarget: SidebarMenuTarget.features,
    ),
    'habits': SidebarMenuItemDefinition(
      key: 'habits',
      title: '习惯中心',
      icon: Icons.repeat_rounded,
      defaultTarget: SidebarMenuTarget.features,
    ),
    'challengeCenter': SidebarMenuItemDefinition(
      key: 'challengeCenter',
      title: '挑战中心',
      icon: Icons.auto_awesome_rounded,
      defaultTarget: SidebarMenuTarget.features,
    ),
    'changelog': SidebarMenuItemDefinition(
      key: 'changelog',
      title: '更新日志',
      icon: Icons.system_update_rounded,
      defaultTarget: SidebarMenuTarget.utilities,
    ),
    'update': SidebarMenuItemDefinition(
      key: 'update',
      title: '检查更新',
      icon: Icons.system_update_rounded,
      defaultTarget: SidebarMenuTarget.utilities,
    ),
  };

  static const List<String> _defaultFeatures = [
    'teams',
    'aiAssistant',
    'timeline',
    'journal',
    'screenTime',
    'planCenter',
    'habits',
    'challengeCenter',
  ];

  static const List<String> _defaultUtilities = [
    'changelog',
    'update',
  ];

  static List<String> defaultOrder(SidebarMenuTarget target) {
    return List<String>.from(
      target == SidebarMenuTarget.features
          ? _defaultFeatures
          : _defaultUtilities,
    );
  }

  static List<String> allKeys() => [
        ..._defaultFeatures,
        ..._defaultUtilities,
      ];

  static SidebarMenuItemDefinition definition(String key) {
    return definitions[key]!;
  }

  static Map<String, bool> defaultVisibility() {
    return {for (final key in allKeys()) key: true};
  }

  static List<String> _sanitizeOrder(
    Iterable<dynamic> raw,
    Set<String> allowed,
  ) {
    final result = <String>[];
    for (final value in raw) {
      final key = value.toString();
      if (allowed.contains(key) && !result.contains(key)) {
        result.add(key);
      }
    }
    return result;
  }

  static SidebarMenuPair normalizePair({
    required Iterable<dynamic> features,
    required Iterable<dynamic> utilities,
  }) {
    final allowed = allKeys().toSet();
    final normalizedFeatures = _sanitizeOrder(features, allowed);
    final normalizedUtilities = _sanitizeOrder(
      utilities,
      allowed.difference(normalizedFeatures.toSet()),
    );

    for (final key in _defaultFeatures) {
      if (!normalizedFeatures.contains(key) &&
          !normalizedUtilities.contains(key)) {
        normalizedFeatures.add(key);
      }
    }
    for (final key in _defaultUtilities) {
      if (!normalizedFeatures.contains(key) &&
          !normalizedUtilities.contains(key)) {
        normalizedUtilities.add(key);
      }
    }

    return SidebarMenuPair(
      features: normalizedFeatures,
      utilities: normalizedUtilities,
    );
  }

  static Map<String, bool> normalizeVisibility(Map<String, dynamic> raw) {
    return {
      for (final key in allKeys())
        key: raw[key] is bool ? raw[key] as bool : true,
    };
  }

  static Future<SidebarMenuPair> loadPair() async {
    final prefs = await StorageService.prefs;
    return normalizePair(
      features: _decodeList(prefs.getString(await _orderKey(
        SidebarMenuTarget.features,
      ))),
      utilities: _decodeList(prefs.getString(await _orderKey(
        SidebarMenuTarget.utilities,
      ))),
    );
  }

  static Future<Map<String, bool>> loadVisibility() async {
    final prefs = await StorageService.prefs;
    final raw = prefs.getString(await _visibilityKey());
    Map<String, dynamic> decoded = const {};
    if (raw != null && raw.isNotEmpty) {
      try {
        final value = jsonDecode(raw);
        if (value is Map) decoded = Map<String, dynamic>.from(value);
      } catch (_) {
        decoded = const {};
      }
    }
    return normalizeVisibility(decoded);
  }

  static Future<void> savePair({
    required Iterable<String> features,
    required Iterable<String> utilities,
  }) async {
    final pair = normalizePair(features: features, utilities: utilities);
    final prefs = await StorageService.prefs;
    await Future.wait([
      prefs.setString(
        await _orderKey(SidebarMenuTarget.features),
        jsonEncode(pair.features),
      ),
      prefs.setString(
        await _orderKey(SidebarMenuTarget.utilities),
        jsonEncode(pair.utilities),
      ),
    ]);
    revision.value++;
  }

  static Future<void> saveVisibility(Map<String, bool> visibility) async {
    final prefs = await StorageService.prefs;
    await prefs.setString(
      await _visibilityKey(),
      jsonEncode(normalizeVisibility(visibility)),
    );
    revision.value++;
  }

  static Future<void> reset() async {
    await savePair(
      features: _defaultFeatures,
      utilities: _defaultUtilities,
    );
    await saveVisibility(defaultVisibility());
  }

  static List<dynamic> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : const [];
    } catch (_) {
      return const [];
    }
  }

  static Future<String> _orderKey(SidebarMenuTarget target) async {
    final suffix =
        target == SidebarMenuTarget.features ? 'features' : 'utilities';
    return _scopedKey('sidebar_menu_order_$suffix');
  }

  static Future<String> _visibilityKey() async {
    return _scopedKey('sidebar_menu_visibility');
  }

  static Future<String> _scopedKey(String base) async {
    final prefs = await StorageService.prefs;
    final username = prefs.getString(StorageService.keyCurrentUser);
    return StorageKeyScope.scoped(base, username);
  }
}
