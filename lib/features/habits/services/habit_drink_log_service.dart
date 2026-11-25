import 'package:flutter/widgets.dart';

import '../../../services/storage/habit_storage.dart';
import '../../../services/storage/user_session_storage.dart';
import '../../../storage_service.dart';
import '../models/habit_checkin.dart';
import '../models/habit_drink_option.dart';
import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../repositories/habit_repository.dart';
import '../utils/habit_emoji_utils.dart';
import 'habit_rule_resolver.dart';

export '../models/habit_drink_option.dart';

/// 戒掉饮料相关习惯的「今日喝了什么」记录、自定义饮品图标与日历展示服务。
///
/// - 每日饮品打卡复用 [HabitCheckIn.note] 与 [HabitCheckIn.dedupeKey]；
/// - 常用饮品图标保存在 `habit_drink_options` 表，通过统一增量同步引擎实现云同步。
abstract final class HabitDrinkLogService {
  /// 默认预设饮品模板（使用稳定 UUID，确保多端编辑/删除可按 LWW 精确合并）。
  static const List<({String uuid, String icon, String label})> _defaultSpecs =
      [
        (uuid: 'preset_milk_tea', icon: '🧋', label: '奶茶'),
        (uuid: 'preset_beverage', icon: '🥤', label: '饮料'),
        (uuid: 'preset_coffee', icon: '☕', label: '咖啡'),
        (uuid: 'preset_juice', icon: '🧃', label: '果汁'),
        (uuid: 'preset_tea', icon: '🍵', label: '茶饮'),
        (uuid: 'preset_alcohol', icon: '🍺', label: '酒水'),
      ];

  /// 自定义饮品时的快捷图标候选。
  static const List<String> suggestedIcons = <String>[
    '🧋',
    '🥤',
    '☕',
    '🧃',
    '🍵',
    '🍺',
    '🍋',
    '🥥',
    '🥛',
    '🍓',
    '🍑',
    '🍇',
    '🍉',
    '🍹',
    '🍸',
    '🍷',
    '🫧',
    '🧊',
    '🍫',
    '🍰',
  ];

  static const Set<String> _knownDrinkIcons = <String>{
    '🧋',
    '🥤',
    '☕',
    '🧃',
    '🍵',
    '🍺',
    '🍋',
    '🥥',
    '🥛',
    '🍓',
    '🍑',
    '🍇',
    '🍉',
    '🍹',
    '🍸',
    '🍷',
    '🫧',
    '🧊',
    '🍫',
    '🍰',
  };

  /// 同步构建一份默认预设选项列表（不落库）。
  static List<HabitDrinkOption> defaultOptions() {
    return [
      for (var i = 0; i < _defaultSpecs.length; i++)
        HabitDrinkOption(
          uuid: _defaultSpecs[i].uuid,
          icon: _defaultSpecs[i].icon,
          label: _defaultSpecs[i].label,
          sortOrder: i,
          createdAt: i + 1,
          updatedAt: i + 1,
        ),
    ];
  }

  /// 读取当前账号的常用饮品图标列表（若尚未自定义过则返回默认预设）。
  static Future<List<HabitDrinkOption>> getOptions() async {
    final allRows = await HabitStorage.getDrinkOptions(includeDeleted: true);
    if (allRows.isEmpty) {
      return defaultOptions();
    }
    return allRows.where((option) => !option.isDeleted).toList(growable: false);
  }

  /// 新增一个自定义常用饮品图标，并触发云同步。
  static Future<HabitDrinkOption> addOption({
    required String icon,
    required String label,
    String username = '',
  }) async {
    final cleanIcon = HabitEmojiUtils.normalizeIcon(icon, fallback: '🥤');
    final cleanLabel = label.trim().isEmpty ? '饮品' : label.trim();
    final existing = await _ensureSeededAndLoadAll();
    final active = existing.where((e) => !e.isDeleted).toList();
    final nextOrder = active.isEmpty
        ? 0
        : active.map((e) => e.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
    final deviceId = await UserSessionStorage.getDeviceId();
    final option = HabitDrinkOption(
      icon: cleanIcon,
      label: cleanLabel,
      sortOrder: nextOrder,
      deviceId: deviceId,
    );
    await HabitStorage.saveDrinkOptions([option]);
    await _requestSync(username);
    return option;
  }

  /// 编辑已有常用饮品图标与名称，并触发云同步。
  static Future<HabitDrinkOption> updateOption(
    HabitDrinkOption option, {
    required String icon,
    required String label,
    String username = '',
  }) async {
    final cleanIcon = HabitEmojiUtils.normalizeIcon(icon, fallback: '🥤');
    final cleanLabel = label.trim().isEmpty ? '饮品' : label.trim();
    final allRows = await _ensureSeededAndLoadAll();
    final deviceId = await UserSessionStorage.getDeviceId();
    final target =
        allRows.where((item) => item.uuid == option.uuid).firstOrNull ??
        HabitDrinkOption.fromJson(option.toJson());
    target
      ..icon = cleanIcon
      ..label = cleanLabel
      ..isDeleted = false
      ..deviceId = deviceId
      ..markAsChanged();
    await HabitStorage.saveDrinkOptions([target]);
    await _requestSync(username);
    return target;
  }

  /// 逻辑删除某个常用饮品图标，并触发云同步。
  static Future<void> deleteOption(
    HabitDrinkOption option, {
    String username = '',
  }) async {
    final allRows = await _ensureSeededAndLoadAll();
    final deviceId = await UserSessionStorage.getDeviceId();
    final target =
        allRows.where((item) => item.uuid == option.uuid).firstOrNull ??
        HabitDrinkOption.fromJson(option.toJson());
    target
      ..isDeleted = true
      ..deviceId = deviceId
      ..markAsChanged();
    await HabitStorage.saveDrinkOptions([target]);
    await _requestSync(username);
  }

  /// 恢复默认 6 个常用饮品图标（软删除多余自定义项，恢复预设项），并触发云同步。
  static Future<List<HabitDrinkOption>> resetToDefaults({
    String username = '',
  }) async {
    final allRows = await HabitStorage.getDrinkOptions(includeDeleted: true);
    final byUuid = {for (final row in allRows) row.uuid: row};
    final defaultUuids = {for (final spec in _defaultSpecs) spec.uuid};
    final deviceId = await UserSessionStorage.getDeviceId();
    final changes = <HabitDrinkOption>[];

    for (var i = 0; i < _defaultSpecs.length; i++) {
      final spec = _defaultSpecs[i];
      final existing = byUuid[spec.uuid];
      if (existing != null) {
        existing
          ..icon = spec.icon
          ..label = spec.label
          ..sortOrder = i
          ..isDeleted = false
          ..deviceId = deviceId
          ..markAsChanged();
        changes.add(existing);
      } else {
        changes.add(
          HabitDrinkOption(
            uuid: spec.uuid,
            icon: spec.icon,
            label: spec.label,
            sortOrder: i,
            deviceId: deviceId,
          ),
        );
      }
    }

    for (final row in allRows) {
      if (!defaultUuids.contains(row.uuid) && !row.isDeleted) {
        row
          ..isDeleted = true
          ..deviceId = deviceId
          ..markAsChanged();
        changes.add(row);
      }
    }

    if (changes.isNotEmpty) {
      await HabitStorage.saveDrinkOptions(changes);
      await _requestSync(username);
    }
    return getOptions();
  }

  /// 首次发生自定义编辑时，先把默认预设写入本地表并参与云同步，
  /// 确保多端看到一致的完整列表。
  static Future<List<HabitDrinkOption>> _ensureSeededAndLoadAll() async {
    final existing = await HabitStorage.getDrinkOptions(includeDeleted: true);
    if (existing.isNotEmpty) return existing;
    final deviceId = await UserSessionStorage.getDeviceId();
    final seeded = [
      for (var i = 0; i < _defaultSpecs.length; i++)
        HabitDrinkOption(
          uuid: _defaultSpecs[i].uuid,
          icon: _defaultSpecs[i].icon,
          label: _defaultSpecs[i].label,
          sortOrder: i,
          deviceId: deviceId,
        ),
    ];
    await HabitStorage.saveDrinkOptions(seeded);
    return seeded;
  }

  static Future<void> _requestSync(String username) async {
    final explicitUsername = username.trim();
    final resolvedUsername = explicitUsername.isNotEmpty
        ? explicitUsername
        : ((await StorageService.getCurrentUsername())?.trim() ?? '');
    if (resolvedUsername.isNotEmpty) {
      StorageService.requestSync(resolvedUsername);
    }
    StorageService.triggerRefresh(const {DataRefreshDomain.habits});
  }

  /// 判断习惯是否为「戒掉饮料 / 控糖戒饮」类习惯。
  static bool isDrinkChoiceHabit(HabitGoal goal) {
    return isDrinkChoiceName(goal.name);
  }

  /// 判断习惯名称是否属于「戒掉饮料 / 控糖戒饮」类习惯。
  static bool isDrinkChoiceName(String rawName) {
    final name = rawName.trim();
    if (name.isEmpty) return false;
    const directKeywords = <String>[
      '戒掉饮料',
      '戒饮料',
      '戒奶茶',
      '戒饮',
      '戒糖',
      '控糖',
      '不喝饮料',
      '少喝饮料',
      '不喝奶茶',
      '少喝奶茶',
    ];
    for (final keyword in directKeywords) {
      if (name.contains(keyword)) return true;
    }
    const abstainWords = <String>['戒', '不喝', '少喝', '控制', '远离', '告别'];
    const drinkWords = <String>['饮料', '奶茶', '汽水', '快乐水', '含糖', '甜饮'];
    final hasAbstain = abstainWords.any(name.contains);
    final hasDrink = drinkWords.any(name.contains);
    return hasAbstain && hasDrink;
  }

  /// 从单条打卡记录中提取饮品图标（兼容预设与任意用户自定义 emoji 图标）。
  static String? extractDrinkIconFromCheckIn(HabitCheckIn checkIn) {
    if (checkIn.isDeleted ||
        checkIn.source == HabitCheckInSource.skip ||
        checkIn.source == HabitCheckInSource.freeze) {
      return null;
    }
    final note = checkIn.note?.trim() ?? '';
    if (note.isEmpty) return null;

    // 1. 若通过饮品选择器写入（dedupeKey 含 /drink/），优先提取首段图标
    final leadingToken = _extractLeadingEmojiToken(note);
    if (leadingToken != null) {
      return leadingToken;
    }

    // 2. 匹配已知预设饮品图标
    for (final spec in _defaultSpecs) {
      if (note.contains(spec.icon)) return spec.icon;
    }
    for (final icon in _knownDrinkIcons) {
      if (note.contains(icon)) return icon;
    }

    // 3. 兼容用户手写纯文字备注
    if (note.contains('奶茶')) return '🧋';
    if (note.contains('饮料') || note.contains('汽水') || note.contains('可乐')) {
      return '🥤';
    }
    if (note.contains('咖啡')) return '☕';
    if (note.contains('果汁')) return '🧃';
    if (note.contains('酒')) return '🍺';
    return null;
  }

  /// 提取 `icon label` 格式中开头的 emoji / 符号图标（支持自定义与复合 emoji）。
  static String? _extractLeadingEmojiToken(String note) {
    final spaceIndex = note.indexOf(' ');
    final head = spaceIndex > 0
        ? note.substring(0, spaceIndex).trim()
        : note.trim();
    if (head.isEmpty || head.characters.length != 1) return null;
    if (HabitEmojiUtils.isEmojiGrapheme(head)) {
      return head;
    }
    final firstRune = head.runes.first;
    // 排除普通 ASCII 字母/数字与常见中日韩汉字，保留其余单个符号。
    final isAsciiAlphaNum = (firstRune >= 0x20 && firstRune <= 0x7E);
    final isCjk =
        (firstRune >= 0x4E00 && firstRune <= 0x9FFF) ||
        (firstRune >= 0x3400 && firstRune <= 0x4DBF);
    if (isAsciiAlphaNum || isCjk) return null;
    return head;
  }

  /// 从某天的打卡列表中提取去重后的饮品图标列表（预设优先，其次自定义顺序）。
  static List<String> extractDrinkIcons(List<HabitCheckIn> dayCheckIns) {
    final foundSet = <String>{};
    final extraOrder = <String>[];
    for (final checkIn in dayCheckIns) {
      final icon = extractDrinkIconFromCheckIn(checkIn);
      if (icon != null && foundSet.add(icon)) {
        extraOrder.add(icon);
      }
    }
    if (foundSet.isEmpty) return const <String>[];
    final ordered = <String>[];
    for (final spec in _defaultSpecs) {
      if (foundSet.contains(spec.icon)) {
        ordered.add(spec.icon);
      }
    }
    for (final icon in extraOrder) {
      if (!ordered.contains(icon)) {
        ordered.add(icon);
      }
    }
    return ordered;
  }

  /// 返回某天某个习惯在日历格子上应显示的图标列表：
  /// - 若当天有饮品选择记录，直接返回对应的饮品图标（如 `['🧋']` 或 `['🍋', '🥤']`）；
  /// - 否则回退到习惯自身的图标。
  static List<String> displayIconsForHabitOnDay({
    required HabitGoal goal,
    required List<HabitCheckIn> dayCheckIns,
  }) {
    final drinkIcons = extractDrinkIcons(dayCheckIns);
    if (drinkIcons.isNotEmpty) return drinkIcons;
    final fallback = goal.icon.trim().isNotEmpty ? goal.icon.trim() : '🎯';
    return <String>[fallback];
  }

  /// 生成某天已选饮品的可读摘要（如 `🧋 奶茶 · 🍋 柠檬茶`）。
  static String formatDrinkSummary(List<HabitCheckIn> dayCheckIns) {
    final icons = extractDrinkIcons(dayCheckIns);
    if (icons.isEmpty) return '';
    final noteByIcon = <String, String>{};
    for (final checkIn in dayCheckIns) {
      final icon = extractDrinkIconFromCheckIn(checkIn);
      if (icon == null) continue;
      final trimmed = checkIn.note?.trim() ?? '';
      if (trimmed.isNotEmpty) {
        noteByIcon.putIfAbsent(icon, () => trimmed);
      }
    }
    final labels = <String>[];
    for (final icon in icons) {
      final recordedNote = noteByIcon[icon];
      if (recordedNote != null && recordedNote.isNotEmpty) {
        labels.add(recordedNote);
      } else {
        final spec = _defaultSpecs.where((s) => s.icon == icon).firstOrNull;
        labels.add(spec != null ? '${spec.icon} ${spec.label}' : icon);
      }
    }
    return labels.join(' · ');
  }

  /// 判断单条打卡记录是否为「戒饮类习惯的破戒饮品记录」（记为打卡失败）。
  static bool isDrinkFailureCheckIn(HabitGoal goal, HabitCheckIn checkIn) {
    if (!isDrinkChoiceHabit(goal)) return false;
    return extractDrinkIconFromCheckIn(checkIn) != null;
  }

  /// 判断某天是否已记录「没喝饮料（打卡成功）」。
  static bool hasNoDrinkSuccess(
    HabitGoal goal,
    List<HabitCheckIn> dayCheckIns,
  ) {
    if (extractDrinkIcons(dayCheckIns).isNotEmpty) return false;
    return dayCheckIns.any(
      (checkIn) =>
          !checkIn.isDeleted &&
          checkIn.source != HabitCheckInSource.skip &&
          checkIn.source != HabitCheckInSource.freeze &&
          !isDrinkFailureCheckIn(goal, checkIn),
    );
  }

  /// 切换或设置某天的「没喝饮料（打卡成功）」状态。
  ///
  /// - 设为成功时：清除当天所有破戒饮品记录与跳过标记，并写入达标打卡；
  /// - 取消成功时：移除当天非破戒的成功打卡记录。
  static Future<bool> setNoDrinkSuccessForDay({
    required HabitGoal goal,
    required List<HabitGoalRuleRevision> rules,
    required DateTime logicalDate,
    required bool success,
    String username = '',
  }) async {
    final normalizedDate = DateTime(
      logicalDate.year,
      logicalDate.month,
      logicalDate.day,
    );
    final dayKey = HabitRuleResolver.dayKey(normalizedDate);
    final existing = await HabitRepository.getCheckIns(
      habitUuid: goal.uuid,
      fromDate: dayKey,
      toDate: dayKey,
    );

    if (!success) {
      final successRecords = existing
          .where(
            (checkIn) =>
                !checkIn.isDeleted &&
                checkIn.source != HabitCheckInSource.skip &&
                checkIn.source != HabitCheckInSource.freeze &&
                !isDrinkFailureCheckIn(goal, checkIn),
          )
          .toList(growable: false);
      if (successRecords.isNotEmpty) {
        for (final checkIn in successRecords) {
          checkIn
            ..isDeleted = true
            ..markAsChanged();
        }
        await HabitRepository.saveCheckInsBatch(successRecords);
      }
      return false;
    }

    // 标记为「没喝（打卡成功）」前，清除当天的饮品破戒记录与跳过标记。
    final toClear = existing
        .where(
          (checkIn) =>
              !checkIn.isDeleted &&
              (checkIn.source == HabitCheckInSource.skip ||
                  isDrinkFailureCheckIn(goal, checkIn)),
        )
        .toList(growable: false);
    if (toClear.isNotEmpty) {
      for (final checkIn in toClear) {
        checkIn
          ..isDeleted = true
          ..markAsChanged();
      }
      await HabitRepository.saveCheckInsBatch(toClear);
    }

    if (goal.sourceType == HabitSourceType.recurringTodo) {
      await HabitRepository.setCompletion(
        goal: goal,
        logicalDate: normalizedDate,
        done: true,
        username: username,
      );
      return true;
    }

    final hasSuccessAlready = existing.any(
      (checkIn) =>
          !checkIn.isDeleted &&
          checkIn.source != HabitCheckInSource.skip &&
          checkIn.source != HabitCheckInSource.freeze &&
          !isDrinkFailureCheckIn(goal, checkIn),
    );
    if (hasSuccessAlready) return true;

    final rule = _resolveRule(goal, rules, normalizedDate);
    final occurredAt = _resolveOccurredAt(
      rule: rule,
      logicalDate: normalizedDate,
    );
    final targetValue = rule.targetValue > 0 ? rule.targetValue : 1.0;
    await HabitRepository.addCheckIn(
      goal: goal,
      rule: rule,
      localOccurredAt: occurredAt,
      value: goal.sourceType == HabitSourceType.timeCheckIn ? 0.0 : targetValue,
      dedupeKey: HabitCheckIn.buildDedupeKey(goal.uuid, 'no-drink/$dayKey'),
    );
    return true;
  }

  /// 切换指定日期的某个饮品破戒记录：已选则取消，未选则添加（记为打卡失败）。
  static Future<bool> toggleDrinkForDay({
    required HabitGoal goal,
    required List<HabitGoalRuleRevision> rules,
    required DateTime logicalDate,
    required HabitDrinkOption option,
  }) async {
    final normalizedDate = DateTime(
      logicalDate.year,
      logicalDate.month,
      logicalDate.day,
    );
    final dayKey = HabitRuleResolver.dayKey(normalizedDate);
    final existing = await HabitRepository.getCheckIns(
      habitUuid: goal.uuid,
      fromDate: dayKey,
      toDate: dayKey,
    );

    final matching = existing
        .where(
          (checkIn) =>
              !checkIn.isDeleted &&
              checkIn.source != HabitCheckInSource.skip &&
              checkIn.source != HabitCheckInSource.freeze &&
              extractDrinkIconFromCheckIn(checkIn) == option.icon,
        )
        .toList(growable: false);

    if (matching.isNotEmpty) {
      for (final checkIn in matching) {
        checkIn
          ..isDeleted = true
          ..markAsChanged();
      }
      await HabitRepository.saveCheckInsBatch(matching);
      return false;
    }

    // 选到饮料表示破戒失败：自动清除当天的「没喝成功」记录与跳过标记。
    final conflicting = existing
        .where(
          (checkIn) =>
              !checkIn.isDeleted &&
              (checkIn.source == HabitCheckInSource.skip ||
                  (checkIn.source != HabitCheckInSource.freeze &&
                      !isDrinkFailureCheckIn(goal, checkIn))),
        )
        .toList(growable: false);
    if (conflicting.isNotEmpty) {
      for (final item in conflicting) {
        item
          ..isDeleted = true
          ..markAsChanged();
      }
      await HabitRepository.saveCheckInsBatch(conflicting);
    }

    final rule = _resolveRule(goal, rules, normalizedDate);
    final occurredAt = _resolveOccurredAt(
      rule: rule,
      logicalDate: normalizedDate,
    );

    await HabitRepository.addCheckIn(
      goal: goal,
      rule: rule,
      localOccurredAt: occurredAt,
      value: 0.0,
      note: option.noteText,
      dedupeKey: HabitCheckIn.buildDedupeKey(
        goal.uuid,
        'drink/$dayKey/${option.uuid}',
      ),
    );
    return true;
  }

  /// 清空指定日期的所有饮品记录。
  static Future<void> clearDrinksForDay({
    required HabitGoal goal,
    required DateTime logicalDate,
  }) async {
    final normalizedDate = DateTime(
      logicalDate.year,
      logicalDate.month,
      logicalDate.day,
    );
    final dayKey = HabitRuleResolver.dayKey(normalizedDate);
    final existing = await HabitRepository.getCheckIns(
      habitUuid: goal.uuid,
      fromDate: dayKey,
      toDate: dayKey,
    );
    final drinkCheckIns = existing
        .where((checkIn) => extractDrinkIconFromCheckIn(checkIn) != null)
        .toList(growable: false);
    if (drinkCheckIns.isEmpty) return;
    for (final checkIn in drinkCheckIns) {
      checkIn
        ..isDeleted = true
        ..markAsChanged();
    }
    await HabitRepository.saveCheckInsBatch(drinkCheckIns);
  }

  static HabitGoalRuleRevision _resolveRule(
    HabitGoal goal,
    List<HabitGoalRuleRevision> rules,
    DateTime logicalDate,
  ) {
    final effective = HabitRuleResolver.effectiveRule(rules, logicalDate);
    if (effective != null) return effective;
    if (rules.isNotEmpty) return rules.first;
    return HabitGoalRuleRevision(
      habitUuid: goal.uuid,
      effectiveFromDate: HabitRuleResolver.dayKey(logicalDate),
      periodType: HabitPeriodType.daily,
      targetValue: 1,
    );
  }

  static DateTime _resolveOccurredAt({
    required HabitGoalRuleRevision rule,
    required DateTime logicalDate,
  }) {
    final now = DateTime.now();
    final todayLogical = HabitRuleResolver.logicalDateFor(
      now,
      rule.dayBoundaryMinute,
    );
    if (todayLogical.year == logicalDate.year &&
        todayLogical.month == logicalDate.month &&
        todayLogical.day == logicalDate.day) {
      return now;
    }
    final safeMinute = rule.dayBoundaryMinute >= 720
        ? (rule.dayBoundaryMinute + 30).clamp(0, 1439)
        : 720;
    return DateTime(
      logicalDate.year,
      logicalDate.month,
      logicalDate.day,
      safeMinute ~/ 60,
      safeMinute % 60,
    );
  }

  /// 统计戒掉饮料习惯的累计与近 7 天饮品摄入情况（按饮品打卡记录聚合）。
  static HabitDrinkStats summarizeDrinkLogs({
    required HabitGoal goal,
    required List<HabitCheckIn> allCheckIns,
    DateTime? referenceDate,
  }) {
    if (!isDrinkChoiceHabit(goal)) {
      return const HabitDrinkStats.empty();
    }
    final now = referenceDate ?? DateTime.now();
    final endDate = DateTime(now.year, now.month, now.day);
    final startDate = HabitRuleResolver.addCalendarDays(endDate, -6);

    var totalDrinks = 0;
    var last7DaysDrinks = 0;
    final totalDays = <String>{};
    final last7Days = <String>{};
    final breakdownMap = <String, _MutableDrinkBreakdown>{};

    for (final checkIn in allCheckIns) {
      final icon = extractDrinkIconFromCheckIn(checkIn);
      if (icon == null) continue;

      totalDrinks += 1;
      totalDays.add(checkIn.logicalDate);

      final parsedDay = HabitRuleResolver.parseDayKey(checkIn.logicalDate);
      final inLast7Days =
          parsedDay != null &&
          !parsedDay.isBefore(startDate) &&
          !parsedDay.isAfter(endDate);
      if (inLast7Days) {
        last7DaysDrinks += 1;
        last7Days.add(checkIn.logicalDate);
      }

      final label = _extractDrinkLabel(icon, checkIn.note);
      final entry = breakdownMap.putIfAbsent(
        icon,
        () => _MutableDrinkBreakdown(icon: icon, label: label),
      );
      entry.totalCount += 1;
      if (inLast7Days) {
        entry.last7DaysCount += 1;
      }
    }

    final breakdown =
        breakdownMap.values
            .map(
              (item) => HabitDrinkBreakdownItem(
                icon: item.icon,
                label: item.label,
                totalCount: item.totalCount,
                last7DaysCount: item.last7DaysCount,
              ),
            )
            .toList()
          ..sort((a, b) {
            final byLast7 = b.last7DaysCount.compareTo(a.last7DaysCount);
            if (byLast7 != 0) return byLast7;
            return b.totalCount.compareTo(a.totalCount);
          });

    return HabitDrinkStats(
      totalDrinks: totalDrinks,
      totalDrinkDays: totalDays.length,
      last7DaysDrinks: last7DaysDrinks,
      last7DaysDrinkDays: last7Days.length,
      breakdown: List<HabitDrinkBreakdownItem>.unmodifiable(breakdown),
    );
  }

  static String _extractDrinkLabel(String icon, String? note) {
    final trimmed = note?.trim() ?? '';
    if (trimmed.startsWith(icon)) {
      final rest = trimmed.substring(icon.length).trim();
      if (rest.isNotEmpty) return rest;
    }
    final spec = _defaultSpecs.where((s) => s.icon == icon).firstOrNull;
    if (spec != null) return spec.label;
    return trimmed.isNotEmpty ? trimmed : icon;
  }
}

class _MutableDrinkBreakdown {
  final String icon;
  final String label;
  int totalCount = 0;
  int last7DaysCount = 0;

  _MutableDrinkBreakdown({required this.icon, required this.label});
}

/// 单个饮品品类的累计与近 7 天统计项。
class HabitDrinkBreakdownItem {
  final String icon;
  final String label;
  final int totalCount;
  final int last7DaysCount;

  const HabitDrinkBreakdownItem({
    required this.icon,
    required this.label,
    required this.totalCount,
    required this.last7DaysCount,
  });
}

/// 戒掉饮料习惯的饮品摄入统计摘要。
class HabitDrinkStats {
  final int totalDrinks;
  final int totalDrinkDays;
  final int last7DaysDrinks;
  final int last7DaysDrinkDays;
  final List<HabitDrinkBreakdownItem> breakdown;

  const HabitDrinkStats({
    required this.totalDrinks,
    required this.totalDrinkDays,
    required this.last7DaysDrinks,
    required this.last7DaysDrinkDays,
    required this.breakdown,
  });

  const HabitDrinkStats.empty()
    : totalDrinks = 0,
      totalDrinkDays = 0,
      last7DaysDrinks = 0,
      last7DaysDrinkDays = 0,
      breakdown = const <HabitDrinkBreakdownItem>[];
}
