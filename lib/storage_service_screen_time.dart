part of 'storage_service.dart';

// ignore_for_file: unused_element, unused_element_parameter, annotate_overrides

mixin _StorageScreenTime on _StorageServiceBase {
  static const int _screenTimeHistoryWriteBatchSize = 30;

  Future<void> saveTimeLogs(
    String username,
    List<TimeLogItem> items, {
    bool sync = true,
  }) async {
    await PomodoroStorage.saveTimeLogs(
      username,
      items,
      sync: sync,
      requestSync: requestSync,
    );
    triggerRefresh({DataRefreshDomain.timeLogs});
  }

  Future<List<TimeLogItem>> getTimeLogs(
    String username, {
    int? limit,
    DateTime? from,
    DateTime? to,
  }) => PomodoroStorage.getTimeLogs(
    username,
    limit: limit,
    from: from,
    to: to,
    saveMigratedTimeLogs: saveTimeLogs,
  );
  Future<bool> deleteTimeLogGlobally(String username, String idToDelete) async {
    List<TimeLogItem> localLogs = await getTimeLogs(username);
    int index = localLogs.indexWhere((t) => t.id == idToDelete);

    if (index == -1) return false;

    localLogs[index].isDeleted = true;
    localLogs[index].markAsChanged();

    await saveTimeLogs(username, localLogs, sync: true);
    return true;
  }

  Future<void> saveLocalScreenTime(
    Map<dynamic, dynamic> stats, {
    String? username,
  }) async {
    final prefs = await StorageService.prefs;
    final requestedUsername = username?.trim();
    final effectiveUsername = requestedUsername?.isNotEmpty == true
        ? requestedUsername
        : prefs.getString(keyCurrentUser);
    if (requestedUsername != null) {
      await UserSessionStorage.ensureCurrentUsername(requestedUsername);
    }
    final key = _scopedKey(keyLocalScreenTime, effectiveUsername);
    await prefs.setString(key, jsonEncode(stats));
  }

  Future<Map<String, dynamic>?> getLocalScreenTimePackage({
    String? username,
  }) async {
    final prefs = await StorageService.prefs;
    final requestedUsername = username?.trim();
    final effectiveUsername = requestedUsername?.isNotEmpty == true
        ? requestedUsername
        : prefs.getString(keyCurrentUser);
    if (requestedUsername != null) {
      await UserSessionStorage.ensureCurrentUsername(requestedUsername);
    }
    final key = _scopedKey(keyLocalScreenTime, effectiveUsername);
    String? s = prefs.getString(key);
    // 仅在未登录的旧版流程中读取全局 key。登录后禁止回退到可能属于
    // 其他账号的缓存，避免账号切换时串出屏幕时间数据。
    if (s == null && (effectiveUsername == null || effectiveUsername.isEmpty)) {
      s = prefs.getString(keyLocalScreenTime);
    }
    return s != null ? jsonDecode(s) as Map<String, dynamic> : null;
  }

  Future<Map<String, dynamic>> getLocalScreenTimeMap({String? username}) async {
    return await getLocalScreenTimePackage(username: username) ?? {};
  }

  Future<List<dynamic>> getLocalScreenTime({String? username}) async {
    final map = await getLocalScreenTimeMap(username: username);
    return map['apps'] as List<dynamic>? ?? [];
  }

  Future<void> _migrateLegacyScreenTimeHistoryIfNeeded(
    SharedPreferences prefs,
    String? effectiveUsername,
  ) async {
    final migrationKey =
        'migrated_screentime_${effectiveUsername ?? 'anonymous'}';
    if (prefs.getBool(migrationKey) ?? false) return;

    final historyKey = _scopedKey(keyScreenTimeHistory, effectiveUsername);
    String? jsonStr = prefs.getString(historyKey);
    final isAnonymous = effectiveUsername == null || effectiveUsername.isEmpty;
    if (jsonStr == null && isAnonymous) {
      jsonStr = prefs.getString(keyScreenTimeHistory);
    }
    if (jsonStr != null && jsonStr.isNotEmpty) {
      debugPrint("🚀 发现 ScreenTime 历史记录，正在执行 SQL 迁移...");
      dynamic decoded;
      try {
        decoded = jsonDecode(jsonStr);
      } catch (e) {
        // 损坏的旧 JSON 无法恢复，直接清理并标记已完成，避免每次启动重复解析失败。
        debugPrint("⚠️ ScreenTime 迁移解析失败，已清理损坏的旧缓存: $e");
        await prefs.remove(historyKey);
        if (isAnonymous) {
          await prefs.remove(keyScreenTimeHistory);
        }
        await prefs.setBool(migrationKey, true);
        return;
      }

      if (decoded is Map<String, dynamic>) {
        final historiesToMigrate = <String, List<dynamic>>{};
        for (final entry in decoded.entries) {
          if (entry.value is List) {
            historiesToMigrate[entry.key] = entry.value as List<dynamic>;
          }
        }
        if (historiesToMigrate.isNotEmpty) {
          try {
            await _saveScreenTimeHistoryBatchToSql(
              historiesToMigrate,
              username: effectiveUsername,
            );
          } catch (e) {
            // Keep the old per-date recovery path if one batch cannot commit.
            debugPrint("⚠️ ScreenTime 批量迁移失败，改为逐日期保存: $e");
            for (final entry in historiesToMigrate.entries) {
              await saveScreenTimeHistoryToSql(
                entry.key,
                entry.value,
                username: effectiveUsername,
              );
            }
          }
        }
      }
      await prefs.remove(historyKey);
      if (isAnonymous) {
        await prefs.remove(keyScreenTimeHistory);
      }
      debugPrint("✅ ScreenTime 迁移完成并已清理 Prefs");
    }
    await prefs.setBool(migrationKey, true);
  }

  Future<void> saveScreenTimeCache(
    List<dynamic> stats, {
    String? username,
  }) async {
    if (stats.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final requestedUsername = username?.trim();
    final currentUsername = prefs.getString(keyCurrentUser)?.trim();
    final effectiveUsername = requestedUsername?.isNotEmpty == true
        ? requestedUsername
        : (currentUsername?.isNotEmpty == true ? currentUsername : null);
    if (requestedUsername != null) {
      await UserSessionStorage.ensureCurrentUsername(requestedUsername);
    }
    final cacheKey = _scopedKey(keyScreenTimeCache, effectiveUsername);
    final syncKey = _scopedKey(keyLastScreenTimeSync, effectiveUsername);
    final now = DateTime.now();
    final String today = time_utils.AppTimeFormats.date(now);

    // 1. 直接将历史记录写入 SQLite（一次性迁移旧版 SharedPreferences 历史后彻底单源化）
    try {
      await _migrateLegacyScreenTimeHistoryIfNeeded(prefs, effectiveUsername);
      await saveScreenTimeHistoryToSql(
        today,
        stats,
        username: effectiveUsername,
      );
    } catch (e) {
      debugPrint("⚠️ ScreenTime 历史写入 SQL 失败: $e");
    }

    // 2. 更新“当前视图快照” (keyScreenTimeCache)
    await prefs.setString(cacheKey, jsonEncode(stats));

    // 更新最后同步成功的时间戳（记录到毫秒）
    await prefs.setInt(syncKey, now.millisecondsSinceEpoch);
    screenTimeRefreshNotifier.value++;
  }

  Future<void> saveScreenTimeHistoryToSql(
    String date,
    List<dynamic> stats, {
    String? username,
  }) => _saveScreenTimeHistoryBatchToSql({date: stats}, username: username);

  Future<void> _saveScreenTimeHistoryBatchToSql(
    Map<String, List<dynamic>> history, {
    String? username,
  }) async {
    if (history.isEmpty) return;

    final dbHelper = DatabaseHelper.instance;
    final normalizedUsername = username?.trim();
    final hasUsername =
        normalizedUsername != null && normalizedUsername.isNotEmpty;
    if (hasUsername) {
      await UserSessionStorage.ensureCurrentUsername(normalizedUsername);
    }
    final db = !hasUsername
        ? await dbHelper.database
        : await dbHelper.databaseForUser(normalizedUsername);

    // History migration and cloud repair may cover many dates. Commit a
    // bounded group together so each date does not open its own transaction.
    final dates = history.keys.toList(growable: false);
    for (
      var start = 0;
      start < dates.length;
      start += _screenTimeHistoryWriteBatchSize
    ) {
      final batch = db.batch();
      final nextStart = start + _screenTimeHistoryWriteBatchSize;
      final end = nextStart < dates.length ? nextStart : dates.length;
      for (var index = start; index < end; index++) {
        final date = dates[index];
        // 覆盖写：先删除该日期的旧记录。
        batch.delete(
          'screen_time',
          where: 'record_date = ?',
          whereArgs: [date],
        );

        for (final stat in history[date]!) {
          batch.insert('screen_time', {
            'record_date': date,
            'package_name': stat['package_name']?.toString() ?? '',
            'app_name': stat['app_name']?.toString() ?? '',
            'device_name': stat['device_name']?.toString() ?? '',
            'category': stat['category']?.toString() ?? '未分类',
            'duration': (stat['duration'] is num)
                ? (stat['duration'] as num).toInt()
                : 0,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          });
        }
      }
      await batch.commit(noResult: true);
    }
  }

  Future<List<dynamic>> getScreenTimeCache() async {
    final prefs = await StorageService.prefs;
    final String? username = prefs.getString(keyCurrentUser);
    final cacheKey = _scopedKey(keyScreenTimeCache, username);
    final syncKey = _scopedKey(keyLastScreenTimeSync, username);

    // 检查缓存是否是今天的
    int? lastSyncMs = prefs.getInt(syncKey);
    if (lastSyncMs == null && (username == null || username.isEmpty)) {
      lastSyncMs = prefs.getInt(keyLastScreenTimeSync);
    }
    if (lastSyncMs != null) {
      DateTime lastSyncDate = DateTime.fromMillisecondsSinceEpoch(lastSyncMs)
          .toLocal();
      DateTime now = DateTime.now();

      // 如果缓存日期不是今天，说明缓存已过期，返回空列表触发新的同步
      if (lastSyncDate.year != now.year ||
          lastSyncDate.month != now.month ||
          lastSyncDate.day != now.day) {
        debugPrint("缓存已过期 (日期不匹配)，清理过期数据");
        await prefs.remove(cacheKey);
        return [];
      }
    }

    String? jsonStr = prefs.getString(cacheKey);
    if (jsonStr == null && (username == null || username.isEmpty)) {
      jsonStr = prefs.getString(keyScreenTimeCache);
    }
    if (jsonStr != null) {
      try {
        return jsonDecode(jsonStr);
      } catch (_) {
        return [];
      }
    }
    return [];
  }

  Future<Map<String, List<dynamic>>> getScreenTimeHistory({
    String? username,
    String? fromDate,
    String? toDate,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final requestedUsername = username?.trim();
    final currentUsername = prefs.getString(keyCurrentUser)?.trim();
    final effectiveUsername = requestedUsername?.isNotEmpty == true
        ? requestedUsername
        : (currentUsername?.isNotEmpty == true ? currentUsername : null);
    if (requestedUsername != null) {
      await UserSessionStorage.ensureCurrentUsername(requestedUsername);
    }
    final dbHelper = DatabaseHelper.instance;

    try {
      // 1. 一次性从旧版 Prefs 迁移到 SQLite 并清理 Prefs
      await _migrateLegacyScreenTimeHistoryIfNeeded(prefs, effectiveUsername);

      final db = effectiveUsername == null || effectiveUsername.isEmpty
          ? await dbHelper.database
          : await dbHelper.databaseForUser(effectiveUsername);
      final where = <String>[];
      final whereArgs = <Object?>[];
      if (fromDate != null) {
        where.add('record_date >= ?');
        whereArgs.add(fromDate);
      }
      if (toDate != null) {
        where.add('record_date < ?');
        whereArgs.add(toDate);
      }
      // 2. 按日期范围从 SQL 读取并分组
      final List<Map<String, dynamic>> maps = await db.query(
        'screen_time',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: whereArgs.isEmpty ? null : whereArgs,
        orderBy: 'record_date DESC',
      );

      Map<String, List<dynamic>> result = {};
      for (var m in maps) {
        String date = m['record_date']?.toString() ?? '';
        if (date.isEmpty) continue;
        result.putIfAbsent(date, () => []);
        result[date]!.add({
          'package_name': m['package_name'],
          'app_name': m['app_name'],
          'device_name': m['device_name'],
          'category': m['category'],
          'duration': m['duration'],
        });
      }
      final int userId = prefs.getInt('current_user_id') ?? 0;
      if (userId > 0) {
        final datesNeedingDeviceNames = result.entries
            .where(
              (entry) => entry.value.any((item) {
                final deviceName = item['device_name']?.toString() ?? '';
                return deviceName.isEmpty;
              }),
            )
            .map((entry) => entry.key)
            .toList();

        for (
          var start = 0;
          start < datesNeedingDeviceNames.length;
          start += _screenTimeHistoryWriteBatchSize
        ) {
          final nextStart = start + _screenTimeHistoryWriteBatchSize;
          final end = nextStart < datesNeedingDeviceNames.length
              ? nextStart
              : datesNeedingDeviceNames.length;
          final cloudHistoryToSave = <String, List<dynamic>>{};
          for (var index = start; index < end; index++) {
            final date = datesNeedingDeviceNames[index];
            try {
              final cloudStats = await ApiService.fetchScreenTime(userId, date);
              if (cloudStats.isNotEmpty) {
                cloudHistoryToSave[date] = cloudStats;
              }
            } catch (e) {
              debugPrint("⚠️ ScreenTime History 云端补齐失败($date): $e");
            }
          }
          if (cloudHistoryToSave.isNotEmpty) {
            try {
              await _saveScreenTimeHistoryBatchToSql(
                cloudHistoryToSave,
                username: effectiveUsername,
              );
              result.addAll(cloudHistoryToSave);
            } catch (e) {
              // Retain per-date recovery so one malformed date cannot block others.
              debugPrint("⚠️ ScreenTime 批量补齐失败，改为逐日期保存: $e");
              for (final entry in cloudHistoryToSave.entries) {
                try {
                  await saveScreenTimeHistoryToSql(
                    entry.key,
                    entry.value,
                    username: effectiveUsername,
                  );
                  result[entry.key] = entry.value;
                } catch (saveError) {
                  debugPrint(
                    "⚠️ ScreenTime History 云端补齐保存失败(${entry.key}): $saveError",
                  );
                }
              }
            }
          }
        }
      }
      return result;
    } catch (e) {
      debugPrint("⚠️ ScreenTime History SQL 异常: $e");
    }
    return {};
  }

  Future<void> updateLastScreenTimeSync({String? username}) async {
    final prefs = await SharedPreferences.getInstance();
    final requestedUsername = username?.trim();
    final currentUsername = prefs.getString(keyCurrentUser)?.trim();
    final effectiveUsername = requestedUsername?.isNotEmpty == true
        ? requestedUsername
        : (currentUsername?.isNotEmpty == true ? currentUsername : null);
    if (requestedUsername != null) {
      await UserSessionStorage.ensureCurrentUsername(requestedUsername);
    }
    await prefs.setInt(
      _scopedKey(keyLastScreenTimeSync, effectiveUsername),
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<DateTime?> getLastScreenTimeSync() async {
    final prefs = await SharedPreferences.getInstance();
    final String? username = prefs.getString(keyCurrentUser);
    int? timestamp = prefs.getInt(_scopedKey(keyLastScreenTimeSync, username));
    if (timestamp == null && (username == null || username.isEmpty)) {
      timestamp = prefs.getInt(keyLastScreenTimeSync);
    }
    if (timestamp != null) {
      return AppTimeFormats.localFromServerTimestamp(timestamp);
    }
    return null;
  }

  Future<void> syncAppMappings() async {
    final prefs = await SharedPreferences.getInstance();
    int? lastSync = prefs.getInt(keyLastMappingsSync);
    DateTime now = DateTime.now();
    if (lastSync != null) {
      try {
        final lastDate = AppTimeFormats.localFromServerTimestamp(lastSync);
        final elapsed = now.difference(lastDate);
        if (!elapsed.isNegative && elapsed < const Duration(days: 7)) return;
      } on RangeError {
        // Repair an out-of-range persisted timestamp with the next response.
      }
    }
    final mappings = await ApiService.fetchAppMappings();
    if (mappings == null) return;
    final lookupMap = <String, String>{};
    for (final item in mappings) {
      if (item is! Map) continue;
      final packageName = item['package_name'];
      final mappedName = item['mapped_name'];
      final category = item['category'];
      final cat = category is String && category.isNotEmpty ? category : '未分类';
      if (packageName is String && packageName.isNotEmpty) {
        lookupMap[packageName] = cat;
      }
      if (mappedName is String && mappedName.isNotEmpty) {
        lookupMap[mappedName] = cat;
      }
    }
    await prefs.setString(keyAppMappings, jsonEncode(lookupMap));
    await prefs.setInt(keyLastMappingsSync, now.millisecondsSinceEpoch);
  }

  Future<Map<String, String>> getAppMappings() async {
    final prefs = await SharedPreferences.getInstance();
    String? jsonStr = prefs.getString(keyAppMappings);
    if (jsonStr != null) {
      try {
        return Map<String, String>.from(jsonDecode(jsonStr));
      } catch (_) {}
    }
    return {};
  }

  Future<void> resetSyncTime(String username) async {
    final prefs = await SharedPreferences.getInstance();
    final habitSyncServerScope = base64Url
        .encode(utf8.encode(ApiService.effectiveBaseUrl))
        .replaceAll('=', '');
    await prefs.remove('last_sync_time_${ApiService.syncServerKey}_$username');
    await prefs.remove(
      'habit_last_sync_time_${ApiService.syncServerKey}_$username',
    );
    await prefs.remove(
      'habit_sync_cursor_v1_${habitSyncServerScope}_$username',
    );
    await prefs.remove(
      'habit_sync_cursor_capability_v1_${habitSyncServerScope}_$username',
    );
    // 兼容早期实现误用 syncServerKey 生成的旧 key。
    await prefs.remove(
      'habit_sync_cursor_v1_${ApiService.syncServerKey}_$username',
    );
    await prefs.remove(
      'habit_sync_cursor_capability_v1_${ApiService.syncServerKey}_$username',
    );
    await prefs.remove('last_sync_time_aliyun_$username');
    await prefs.remove('last_sync_time_aliyun_test_$username');
    await prefs.remove('last_sync_time_cf_$username');
    await prefs.remove('last_sync_time_$username'); // 兼容旧版本
    final financeSyncServerScope = base64Url
        .encode(utf8.encode(ApiService.effectiveBaseUrl))
        .replaceAll('=', '');
    await prefs.remove(
      'finance_last_sync_time_${ApiService.syncServerKey}_$username',
    );
    await prefs.remove('finance_sync_v1_${financeSyncServerScope}_$username');
  }
}
