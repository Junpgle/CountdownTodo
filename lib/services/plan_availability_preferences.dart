import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/plan_availability.dart';

class PlanAvoidancePreferences {
  const PlanAvoidancePreferences(
    this.options,
    this.selectedIndices, {
    this.bufferBefore = 0,
    this.bufferAfter = 0,
    this.bufferError,
  });

  final List<PlanDailyTimeWindow> options;
  final Set<int> selectedIndices;
  final int bufferBefore, bufferAfter;
  final String? bufferError;
  String get bufferKey => '$bufferBefore:$bufferAfter';
  String get avoidanceKey => keyFor(options, selectedIndices);

  static String keyFor(
    List<PlanDailyTimeWindow> options,
    Set<int> selectedIndices,
  ) => keyForWindows([
    for (var i = 0; i < options.length; i++)
      if (selectedIndices.contains(i)) options[i],
  ]);

  static String keyForWindows(Iterable<PlanDailyTimeWindow> windows) {
    final entries = [
      for (final window in windows)
        [window.label, window.startMinutes, window.endMinutes],
    ]..sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
    return jsonEncode(entries);
  }
}

/// Local, account-scoped defaults for the next availability search.
class PlanAvailabilityPreferences {
  static const defaultWindows = [
    PlanDailyTimeWindow('午休', 720, 840),
    PlanDailyTimeWindow('午餐', 690, 750),
    PlanDailyTimeWindow('晚餐', 1080, 1140),
  ];

  static String _key(String username) =>
      'plan_availability_avoidance_$username';
  static Future<void>? _pendingWrites;

  static Future<PlanAvoidancePreferences> load(String username) async {
    // Reopening immediately after a tap must see that tap's persisted value.
    final pending = _pendingWrites;
    if (pending != null) await pending;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.get(_key(username));
    final options = List<PlanDailyTimeWindow>.of(defaultWindows);
    final selected = <int>{};
    if (raw == null) return PlanAvoidancePreferences(options, selected);
    var before = 0, after = 0;
    String? bufferError;
    if (raw is! String) {
      return PlanAvoidancePreferences(
        options,
        selected,
        bufferError: '查找设置无法读取，请重置前后缓冲后再查找',
      );
    }
    try {
      final data = jsonDecode(raw);
      if (data is! Map || ![1, 2].contains(data['version'])) {
        return PlanAvoidancePreferences(
          options,
          selected,
          bufferError: '查找设置版本无法识别，请重置前后缓冲后再查找',
        );
      }
      if (data['version'] == 2) {
        final b = data['buffer_before'], a = data['buffer_after'];
        if (b is! int || a is! int || b < 0 || a < 0 || b > 120 || a > 120) {
          bufferError = '缓冲设置无法读取，请重置前后缓冲后再查找';
        } else {
          before = b;
          after = a;
        }
      }
      if (data['windows'] is! List) {
        return PlanAvoidancePreferences(
          options,
          selected,
          bufferBefore: before,
          bufferAfter: after,
          bufferError: data['version'] == 2
              ? bufferError ?? '查找设置无法读取，请重置前后缓冲后再查找'
              : null,
        );
      }
      final entries = data['windows'] as List;
      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        if (entry is! Map) continue;
        final label = entry['label'];
        final start = entry['start'];
        final end = entry['end'];
        if (label is! String ||
            label.trim().isEmpty ||
            start is! int ||
            end is! int ||
            start < 0 ||
            end > 1440 ||
            end <= start) {
          continue;
        }
        final window = PlanDailyTimeWindow(label, start, end);
        final index = i < defaultWindows.length ? i : options.length;
        if (i < defaultWindows.length) {
          options[i] = window;
        } else {
          options.add(window);
        }
        if (entry['enabled'] == true) selected.add(index);
      }
    } on FormatException {
      bufferError = '查找设置无法读取，请重置前后缓冲后再查找';
    }
    return PlanAvoidancePreferences(
      options,
      selected,
      bufferBefore: before,
      bufferAfter: after,
      bufferError: bufferError,
    );
  }

  static Future<void> validateQueryDefaults(PlanAvailabilityQuery query) async {
    final validateBuffers =
        query.bufferDefaultsKey != null && !query.bufferOverride;
    final validateAvoidance =
        query.avoidanceDefaultsKey != null && !query.avoidanceOverride;
    if (!validateBuffers && !validateAvoidance) return;
    final current = await load(query.username);
    if (validateBuffers) {
      if (current.bufferError != null) {
        throw PlanAvailabilityException(current.bufferError!);
      }
      if (current.bufferKey != query.bufferDefaultsKey) {
        throw const PlanAvailabilityException('缓冲默认设置已变化，请重新查找；当前输入已保留');
      }
    }
    if (validateAvoidance) {
      if (current.bufferError != null) {
        throw PlanAvailabilityException(current.bufferError!);
      }
      if (current.avoidanceKey != query.avoidanceDefaultsKey) {
        throw const PlanAvailabilityException('避让默认设置已变化，请重新查找；当前输入已保留');
      }
      if (PlanAvoidancePreferences.keyForWindows(query.avoidWindows) !=
          query.avoidanceDefaultsKey) {
        throw const PlanAvailabilityException('查找避让条件已变化，请重新查找；当前输入已保留');
      }
    }
  }

  static Future<void> save(
    String username,
    List<PlanDailyTimeWindow> options,
    Set<PlanDailyTimeWindow> selected, {
    int? bufferBefore,
    int? bufferAfter,
  }) {
    // Capture now, before awaiting earlier writes or widget disposal.
    final windows = {
      'windows': [
        for (final window in options)
          {
            'label': window.label,
            'start': window.startMinutes,
            'end': window.endMinutes,
            'enabled': selected.contains(window),
          },
      ],
    };
    final previous = _pendingWrites;
    final write = () async {
      if (previous != null) await previous;
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      var before = bufferBefore, after = bufferAfter;
      if (before == null || after == null) {
        final old = prefs.getString(_key(username));
        try {
          final data = old == null ? null : jsonDecode(old);
          if (data is Map && data['version'] == 2) {
            before ??= data['buffer_before'] as int;
            after ??= data['buffer_after'] as int;
          }
        } catch (_) {
          throw StateError('缓冲设置无法读取，请先重置');
        }
      }
      before ??= 0;
      after ??= 0;
      if (before < 0 || before > 120 || after < 0 || after > 120) {
        throw StateError('前后缓冲须为0–120分钟');
      }
      final raw = jsonEncode({
        ...windows,
        'version': 2,
        'buffer_before': before,
        'buffer_after': after,
      });
      if (!await prefs.setString(_key(username), raw)) {
        throw StateError('Unable to save availability preferences');
      }
    }();
    final pending = write.catchError((Object _) {});
    _pendingWrites = pending;
    unawaited(
      pending.then((_) {
        if (identical(_pendingWrites, pending)) _pendingWrites = null;
      }),
    );
    return write;
  }
}
