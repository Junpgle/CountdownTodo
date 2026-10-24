import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FeatureTipService {
  static const String _prefix = 'tip_shown_';
  static const String _badgePrefix = 'feature_badge_seen_';
  static const String _checklistDismissedKey =
      'onboarding_checklist_dismissed_v1';

  /// 通知 UI 引导提示、新功能徽章或探索清单状态已变更
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// 检查是否已经显示过特定引导
  static Future<bool> hasTipBeenShown(String tipId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_prefix$tipId') ?? false;
  }

  /// 标记特定引导已显示
  static Future<void> markTipShown(String tipId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefix$tipId', true);
    revision.value++;
  }

  /// 检查某个新功能微徽章（NEW / 蓝点）是否尚未被用户点击查看
  static Future<bool> isFeatureBadgeUnread(String badgeId) async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool('$_badgePrefix$badgeId') ?? false);
  }

  /// 批量获取已读的新功能徽章集合
  static Future<Set<String>> getSeenFeatureBadges() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = <String>{};
    for (final key in prefs.getKeys()) {
      if (key.startsWith(_badgePrefix) && (prefs.getBool(key) ?? false)) {
        seen.add(key.substring(_badgePrefix.length));
      }
    }
    return seen;
  }

  /// 标记某个新功能微徽章为已读
  static Future<void> markFeatureBadgeSeen(String badgeId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_badgePrefix$badgeId', true);
    revision.value++;
  }

  /// 重置所有引导状态、新功能徽章与新手探索卡片隐藏状态
  static Future<void> resetAllTips() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where(
          (k) =>
              k.startsWith(_prefix) ||
              k.startsWith(_badgePrefix) ||
              k == _checklistDismissedKey,
        )
        .toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
    revision.value++;
  }
}
