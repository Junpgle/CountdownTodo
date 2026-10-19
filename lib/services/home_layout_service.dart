import 'dart:convert';

import '../storage_service.dart';
import 'storage/storage_key_scope.dart';

/// The four persisted dashboard groups. A pair of groups shares one component
/// pool so a component can move from one group to the other.
enum HomeLayoutTarget { mobileHome, mobileFocus, wideLeft, wideRight }

class HomeLayoutPair {
  final List<String> first;
  final List<String> second;

  const HomeLayoutPair({required this.first, required this.second});
}

/// Persists and validates the order of dashboard sections.
///
/// Layout preferences are scoped to the signed-in account, matching the
/// dashboard data they arrange. The fallback key keeps the setting usable
/// before a user has signed in.
class HomeLayoutService {
  const HomeLayoutService._();

  static const int defaultHabitDisplayLimit = 3;
  static const int minHabitDisplayLimit = 1;
  static const int maxHabitDisplayLimit = 5;

  static const Map<HomeLayoutTarget, List<String>> _defaults = {
    HomeLayoutTarget.mobileHome: ['banners', 'countdowns', 'agenda', 'todos'],
    HomeLayoutTarget.mobileFocus: [
      'timeline',
      'pomodoro',
      'finance',
      'habits',
      'screenTime',
      'math',
    ],
    HomeLayoutTarget.wideLeft: ['banners', 'countdowns', 'todos'],
    HomeLayoutTarget.wideRight: [
      'agenda',
      'timeline',
      'pomodoro',
      'finance',
      'habits',
      'screenTime',
      'math',
    ],
  };

  static List<String> defaultOrder(HomeLayoutTarget target) =>
      List<String>.from(_defaults[target]!);

  static List<String> sectionKeys(
    HomeLayoutTarget firstTarget,
    HomeLayoutTarget secondTarget,
  ) {
    final result = <String>[];
    for (final target in [firstTarget, secondTarget]) {
      for (final key in _defaults[target]!) {
        if (!result.contains(key)) result.add(key);
      }
    }
    return result;
  }

  static Map<String, bool> defaultVisibility(
    HomeLayoutTarget firstTarget,
    HomeLayoutTarget secondTarget,
  ) {
    return {
      for (final key in sectionKeys(firstTarget, secondTarget)) key: true,
      'agendaSchedules': true,
      'agendaPlans': true,
    };
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

  /// Normalizes two groups together without putting a moved component back in
  /// its previous group.
  static HomeLayoutPair normalizePair({
    required HomeLayoutTarget firstTarget,
    required HomeLayoutTarget secondTarget,
    required Iterable<dynamic> firstOrder,
    required Iterable<dynamic> secondOrder,
    Map<String, dynamic> visibility = const {},
  }) {
    var firstRaw = firstOrder.toList(), secondRaw = secondOrder.toList();
    if (![...firstRaw, ...secondRaw].contains('agenda')) {
      final all = [...firstRaw, ...secondRaw];
      final anchor = (visibility['courses'] != false && all.contains('courses'))
          ? 'courses'
          : (visibility['planBlocks'] != false && all.contains('planBlocks'))
          ? 'planBlocks'
          : all.contains('courses')
          ? 'courses'
          : 'planBlocks';
      List<dynamic> merge(List<dynamic> raw) => [
        for (final key in raw)
          if (key == anchor)
            'agenda'
          else if (key != 'courses' && key != 'planBlocks')
            key,
      ];
      firstRaw = merge(firstRaw);
      secondRaw = merge(secondRaw);
    }
    final allowed = <String>{
      ..._defaults[firstTarget]!,
      ..._defaults[secondTarget]!,
    };
    final first = _sanitizeOrder(firstRaw, allowed);
    final second = _sanitizeOrder(secondRaw, allowed.difference(first.toSet()));

    // Add newly introduced sections to their original default group. This
    // keeps upgrades safe while preserving an intentional cross-group move.
    for (final key in _defaults[firstTarget]!) {
      if (!first.contains(key) && !second.contains(key)) first.add(key);
    }
    for (final key in _defaults[secondTarget]!) {
      if (!first.contains(key) && !second.contains(key)) second.add(key);
    }
    return HomeLayoutPair(first: first, second: second);
  }

  static Map<String, bool> normalizeVisibility({
    required HomeLayoutTarget firstTarget,
    required HomeLayoutTarget secondTarget,
    required Map<String, dynamic> raw,
  }) {
    bool flag(String key, bool fallback) =>
        raw[key] is bool ? raw[key] as bool : fallback;
    return {
      for (final key in sectionKeys(firstTarget, secondTarget))
        key: raw[key] is bool
            ? raw[key] as bool
            : key == 'agenda'
            ? (raw['courses'] != false || raw['planBlocks'] != false)
            : true,
      'agendaSchedules': flag('agendaSchedules', flag('courses', true)),
      'agendaPlans': flag('agendaPlans', flag('planBlocks', true)),
    };
  }

  /// Normalizes old/corrupt values while preserving the user's valid order.
  /// Missing sections are appended in the current default order so adding a
  /// new section does not make it disappear for existing users.
  static List<String> normalizeOrder(
    Iterable<dynamic> raw,
    Iterable<String> defaults,
  ) {
    final allowed = defaults.toSet();
    final result = <String>[];
    for (final value in raw) {
      final key = value.toString();
      if (allowed.contains(key) && !result.contains(key)) {
        result.add(key);
      }
    }
    for (final key in defaults) {
      if (!result.contains(key)) result.add(key);
    }
    return result;
  }

  static Future<List<String>> load(HomeLayoutTarget target) async {
    final prefs = await StorageService.prefs;
    final raw = prefs.getString(await _key(target));
    if (raw == null || raw.isEmpty) return defaultOrder(target);

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return normalizeOrder(decoded, _defaults[target]!);
      }
    } catch (_) {
      // Fall back to the current defaults if a preference was corrupted.
    }
    return defaultOrder(target);
  }

  static Future<HomeLayoutPair> loadPair(
    HomeLayoutTarget firstTarget,
    HomeLayoutTarget secondTarget,
  ) async {
    final prefs = await StorageService.prefs;
    final firstRaw = prefs.getString(await _key(firstTarget));
    final secondRaw = prefs.getString(await _key(secondTarget));
    final visibility = await _readVisibility(firstTarget);
    return normalizePair(
      firstTarget: firstTarget,
      secondTarget: secondTarget,
      firstOrder: _decodeList(firstRaw),
      secondOrder: _decodeList(secondRaw),
      visibility: visibility,
    );
  }

  static Future<Map<String, bool>> loadVisibility(
    HomeLayoutTarget firstTarget,
    HomeLayoutTarget secondTarget,
  ) async {
    return normalizeVisibility(
      firstTarget: firstTarget,
      secondTarget: secondTarget,
      raw: await _readVisibility(firstTarget),
    );
  }

  static Future<Map<String, dynamic>> _readVisibility(
    HomeLayoutTarget target,
  ) async {
    final prefs = await StorageService.prefs;
    final raw = prefs.getString(await _visibilityKey(target));
    Map<String, dynamic> decoded = const {};
    if (raw != null && raw.isNotEmpty) {
      try {
        final value = jsonDecode(raw);
        if (value is Map) {
          decoded = Map<String, dynamic>.from(value);
        }
      } catch (_) {
        decoded = const {};
      }
    }
    return decoded;
  }

  static Future<void> save(
    HomeLayoutTarget target,
    Iterable<String> order,
  ) async {
    final prefs = await StorageService.prefs;
    final normalized = _sanitizeOrder(order, _defaults[target]!.toSet());
    await prefs.setString(await _key(target), jsonEncode(normalized));
  }

  static Future<void> savePair({
    required HomeLayoutTarget firstTarget,
    required HomeLayoutTarget secondTarget,
    required Iterable<String> firstOrder,
    required Iterable<String> secondOrder,
  }) async {
    final pair = normalizePair(
      firstTarget: firstTarget,
      secondTarget: secondTarget,
      firstOrder: firstOrder,
      secondOrder: secondOrder,
    );
    final prefs = await StorageService.prefs;
    await Future.wait([
      prefs.setString(await _key(firstTarget), jsonEncode(pair.first)),
      prefs.setString(await _key(secondTarget), jsonEncode(pair.second)),
    ]);
  }

  static Future<void> saveVisibility({
    required HomeLayoutTarget firstTarget,
    required HomeLayoutTarget secondTarget,
    required Map<String, bool> visibility,
  }) async {
    final normalized = normalizeVisibility(
      firstTarget: firstTarget,
      secondTarget: secondTarget,
      raw: visibility,
    );
    final prefs = await StorageService.prefs;
    await prefs.setString(
      await _visibilityKey(firstTarget),
      jsonEncode(normalized),
    );
  }

  static Future<int> loadHabitDisplayLimit() async {
    final prefs = await StorageService.prefs;
    return _normalizeHabitDisplayLimit(
      prefs.getInt(await _habitDisplayLimitKey()),
    );
  }

  static Future<void> saveHabitDisplayLimit(int limit) async {
    final prefs = await StorageService.prefs;
    await prefs.setInt(
      await _habitDisplayLimitKey(),
      _normalizeHabitDisplayLimit(limit),
    );
  }

  static Future<void> reset(HomeLayoutTarget target) =>
      save(target, _defaults[target]!);

  static List<dynamic> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : const [];
    } catch (_) {
      return const [];
    }
  }

  static String targetKey(HomeLayoutTarget target) {
    switch (target) {
      case HomeLayoutTarget.mobileHome:
        return 'mobile_home';
      case HomeLayoutTarget.mobileFocus:
        return 'mobile_focus';
      case HomeLayoutTarget.wideLeft:
        return 'wide_left';
      case HomeLayoutTarget.wideRight:
        return 'wide_right';
    }
  }

  static Future<String> _key(HomeLayoutTarget target) async {
    return _scopedKey('home_layout_${targetKey(target)}');
  }

  static Future<String> _visibilityKey(HomeLayoutTarget target) async {
    final deviceKey = switch (target) {
      HomeLayoutTarget.mobileHome || HomeLayoutTarget.mobileFocus => 'mobile',
      HomeLayoutTarget.wideLeft || HomeLayoutTarget.wideRight => 'wide',
    };
    return _scopedKey('home_layout_visibility_$deviceKey');
  }

  static Future<String> _scopedKey(String base) async {
    final prefs = await StorageService.prefs;
    final username = prefs.getString(StorageService.keyCurrentUser);
    return StorageKeyScope.scoped(base, username);
  }

  static Future<String> _habitDisplayLimitKey() async {
    final prefs = await StorageService.prefs;
    final username = prefs.getString(StorageService.keyCurrentUser);
    return StorageKeyScope.scoped('home_habit_display_limit', username);
  }

  static int _normalizeHabitDisplayLimit(int? value) {
    return (value ?? defaultHabitDisplayLimit)
        .clamp(minHabitDisplayLimit, maxHabitDisplayLimit)
        .toInt();
  }
}
