class TaiService {
  static Future<String?> getSavedDbPath() async => null;

  static Future<void> saveDbPath(String path) async {}

  static Future<bool> validateDb(String path) async => false;

  static Future<List<Map<String, dynamic>>> readDailyStats({
    required String dbPath,
    required String date,
  }) async =>
      const [];

  static Future<List<Map<String, dynamic>>> getTodayStats() async => const [];

  static Future<String?> detectDefaultPath() async => null;
}
