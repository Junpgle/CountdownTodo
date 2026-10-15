import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/plan_availability.dart';
import '../models/plan_weekly_availability.dart';
import 'plan_todo_guard.dart';

class PlanWeeklyPreferencesSnapshot {
  const PlanWeeklyPreferencesSnapshot(this.rules, this.key, {this.error});
  final PlanWeeklyRules? rules;
  final String key;
  final String? error;
}

abstract final class PlanWeeklyAvailabilityPreferences {
  static final revision = ValueNotifier<int>(0);
  static Future<void>? _pending;
  static String storageKey(String username) =>
      'plan_weekly_availability_v1_$username';
  static PlanWeeklyPreferencesSnapshot _read(
    SharedPreferences prefs,
    String username,
  ) {
    final raw = prefs.get(storageKey(username));
    if (raw == null) {
      final rules = PlanWeeklyRules.initial();
      return PlanWeeklyPreferencesSnapshot(rules, rules.fingerprint);
    }
    try {
      if (raw is! String || raw.length > 8192) throw const FormatException();
      final rules = PlanWeeklyRules.fromJson(jsonDecode(raw));
      return PlanWeeklyPreferencesSnapshot(rules, rules.fingerprint);
    } catch (_) {
      return PlanWeeklyPreferencesSnapshot(
        null,
        jsonEncode(['invalid', raw]),
        error: '每周可安排时间无法读取，请修复规则或明确选择本次不使用',
      );
    }
  }

  static Future<PlanWeeklyPreferencesSnapshot> load(String username) async {
    final pending = _pending;
    if (pending != null) await pending;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return _read(prefs, username);
  }

  static Future<void> save(
    PlanTodoIdentity identity,
    PlanWeeklyRules rules, {
    required String expectedKey,
  }) {
    // Validate and freeze before queueing; one failed write cannot poison later writes.
    final frozen = PlanWeeklyRules.fromJson(rules.toJson());
    final previous = _pending;
    final write = () async {
      if (previous != null) await previous;
      await identity.check();
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      if (_read(prefs, identity.username).key != expectedKey) {
        throw const PlanAvailabilityException('每周可安排时间已变化，请重新读取后再编辑');
      }
      await identity.check();
      if (!await prefs.setString(
        storageKey(identity.username),
        frozen.fingerprint,
      )) {
        throw const PlanAvailabilityException('每周可安排时间保存失败，修改仍保留在页面');
      }
      await identity.check();
      revision.value++;
    }();
    final pending = write.catchError((Object _) {});
    _pending = pending;
    unawaited(
      pending.then((_) {
        if (identical(_pending, pending)) _pending = null;
      }),
    );
    return write;
  }

  static Future<void> validateQuery(PlanAvailabilityQuery query) async {
    final context = query.weekly;
    if (context == null || context.ignored) return;
    final latest = await load(query.username);
    if (latest.error != null) throw PlanAvailabilityException(latest.error!);
    if (latest.key != context.fingerprint) {
      throw const PlanAvailabilityException('每周可安排时间已变化，请重新查找');
    }
  }
}
