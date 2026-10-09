import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/plan_availability.dart';

class PlanAvoidancePreferences {
  const PlanAvoidancePreferences(this.options, this.selectedIndices);

  final List<PlanDailyTimeWindow> options;
  final Set<int> selectedIndices;
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
    final raw = prefs.get(_key(username));
    final options = List<PlanDailyTimeWindow>.of(defaultWindows);
    final selected = <int>{};
    if (raw is! String) return PlanAvoidancePreferences(options, selected);
    try {
      final data = jsonDecode(raw);
      if (data is! Map || data['version'] != 1 || data['windows'] is! List) {
        return PlanAvoidancePreferences(options, selected);
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
      // Corrupt or old local data should not prevent planning.
    }
    return PlanAvoidancePreferences(options, selected);
  }

  static Future<void> save(
    String username,
    List<PlanDailyTimeWindow> options,
    Set<PlanDailyTimeWindow> selected,
  ) {
    // Capture now, before awaiting earlier writes or widget disposal.
    final raw = jsonEncode({
      'version': 1,
      'windows': [
        for (final window in options)
          {
            'label': window.label,
            'start': window.startMinutes,
            'end': window.endMinutes,
            'enabled': selected.contains(window),
          },
      ],
    });
    final previous = _pendingWrites;
    final write = () async {
      if (previous != null) await previous;
      final prefs = await SharedPreferences.getInstance();
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
