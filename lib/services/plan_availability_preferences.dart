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
  static String _windowsKey(String username) =>
      'plan_availability_avoidance_windows_$username';
  static String _buffersKey(String username) =>
      'plan_availability_buffers_$username';
  static Future<void>? _pendingWrites;

  static Future<PlanAvoidancePreferences> load(String username) async {
    // Reopening immediately after a tap must see that tap's persisted value.
    final pending = _pendingWrites;
    if (pending != null) await pending;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final options = List<PlanDailyTimeWindow>.of(defaultWindows);
    final selected = <int>{};
    var before = 0, after = 0;
    String? bufferError;
    final legacyRaw = prefs.get(_key(username));
    final rawWindows = prefs.get(_windowsKey(username));
    final rawBuffers = prefs.get(_buffersKey(username));
    Map? legacy;
    var legacyInvalid = false;
    if (legacyRaw != null && (rawWindows == null || rawBuffers == null)) {
      if (legacyRaw is! String) {
        legacyInvalid = true;
      } else {
        try {
          final data = jsonDecode(legacyRaw);
          if (data is Map && [1, 2].contains(data['version'])) {
            legacy = data;
          } else {
            legacyInvalid = true;
          }
        } on FormatException {
          legacyInvalid = true;
        }
      }
    }

    void readWindows(Object? value, {required int version}) {
      final data = value is String ? jsonDecode(value) : null;
      if (data is! Map || data['version'] != version || data['windows'] is! List) {
        bufferError ??= '查找设置无法读取，请重置前后缓冲后再查找';
        return;
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
    }

    if (rawWindows != null) {
      try {
        readWindows(rawWindows, version: 1);
      } on FormatException {
        bufferError = '查找设置无法读取，请重置前后缓冲后再查找';
      }
    } else if (legacy != null) {
      readWindows(jsonEncode(legacy), version: legacy['version'] as int);
    } else if (legacyInvalid) {
      bufferError = '查找设置无法读取，请重置前后缓冲后再查找';
    }

    if (rawBuffers != null) {
      try {
        final data = rawBuffers is String ? jsonDecode(rawBuffers) : null;
        final b = data is Map && data['version'] == 1 ? data['before'] : null;
        final a = data is Map && data['version'] == 1 ? data['after'] : null;
        if (b is! int || a is! int || b < 0 || a < 0 || b > 120 || a > 120) {
          bufferError = '缓冲设置无法读取，请重置前后缓冲后再查找';
        } else {
          before = b;
          after = a;
        }
      } on FormatException {
        bufferError = '缓冲设置无法读取，请重置前后缓冲后再查找';
      }
    } else if (legacy != null && legacy['version'] == 2) {
      final b = legacy['buffer_before'], a = legacy['buffer_after'];
      if (b is! int || a is! int || b < 0 || a < 0 || b > 120 || a > 120) {
        bufferError = '缓冲设置无法读取，请重置前后缓冲后再查找';
      } else {
        before = b;
        after = a;
      }
    } else if (legacyInvalid) {
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
    bool updateAvoidance = true,
    bool updateBuffers = true,
  }) {
    // Capture now, before awaiting earlier writes or widget disposal.
    final windows = [
      for (final window in options)
        {
          'label': window.label,
          'start': window.startMinutes,
          'end': window.endMinutes,
          'enabled': selected.contains(window),
        },
    ];
    final previous = _pendingWrites;
    final write = () async {
      if (previous != null) await previous;
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      if (updateAvoidance) {
        final raw = jsonEncode({'version': 1, 'windows': windows});
        if (!await prefs.setString(_windowsKey(username), raw)) {
          throw StateError('Unable to save availability avoidance settings');
        }
      }

      if (updateBuffers) {
        var before = bufferBefore, after = bufferAfter;
        if (before == null || after == null) {
          final raw = prefs.get(_buffersKey(username));
          Map? data;
          var splitBufferData = false;
          if (raw is String) {
            try {
              final decoded = jsonDecode(raw);
              if (decoded is Map && decoded['version'] == 1) {
                data = decoded;
                splitBufferData = true;
              }
            } catch (_) {
              throw StateError('缓冲设置无法读取，请先重置');
            }
          } else if (raw == null) {
            final legacyRaw = prefs.get(_key(username));
            if (legacyRaw is String) {
              try {
                final decoded = jsonDecode(legacyRaw);
                if (decoded is Map && [1, 2].contains(decoded['version'])) {
                  data = decoded;
                }
              } catch (_) {
                throw StateError('缓冲设置无法读取，请先重置');
              }
            } else if (legacyRaw != null) {
              throw StateError('缓冲设置无法读取，请先重置');
            }
          } else {
            throw StateError('缓冲设置无法读取，请先重置');
          }
          if (data != null) {
            final storedBefore = splitBufferData
                ? data['before']
                : data['version'] == 2
                ? data['buffer_before']
                : 0;
            final storedAfter = splitBufferData
                ? data['after']
                : data['version'] == 2
                ? data['buffer_after']
                : 0;
            if (storedBefore is! int ||
                storedAfter is! int ||
                storedBefore < 0 ||
                storedAfter < 0 ||
                storedBefore > 120 ||
                storedAfter > 120) {
              throw StateError('缓冲设置无法读取，请先重置');
            }
            before ??= storedBefore;
            after ??= storedAfter;
          }
        }
        before ??= 0;
        after ??= 0;
        if (before < 0 || before > 120 || after < 0 || after > 120) {
          throw StateError('前后缓冲须为0–120分钟');
        }
        final raw = jsonEncode({
          'version': 1,
          'before': before,
          'after': after,
        });
        if (!await prefs.setString(_buffersKey(username), raw)) {
          throw StateError('Unable to save availability buffers');
        }
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
