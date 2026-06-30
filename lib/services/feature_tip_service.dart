import 'package:shared_preferences/shared_preferences.dart';

class FeatureTipService {
  static const String _prefix = 'tip_shown_';

  /// 检查是否已经显示过特定引导
  static Future<bool> hasTipBeenShown(String tipId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_prefix$tipId') ?? false;
  }

  /// 标记特定引导已显示
  static Future<void> markTipShown(String tipId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefix$tipId', true);
  }

  /// 重置所有引导状态（用于调试）
  static Future<void> resetAllTips() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}
