/// 生成按登录用户隔离的 SharedPreferences Key。
///
/// 未登录时保留原始 Key，兼容登录前的全局缓存和历史迁移逻辑。
abstract final class StorageKeyScope {
  static String scoped(String baseKey, String? username) {
    if (username == null || username.isEmpty) return baseKey;
    return '${baseKey}_$username';
  }
}
