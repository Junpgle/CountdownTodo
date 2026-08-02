part of 'storage_service.dart';
// ignore_for_file: annotate_overrides, unused_element, unused_element_parameter

mixin _StorageCore on _StorageServiceBase {
  void triggerRefresh() {
    _refreshDebouncer?.cancel();
    _refreshDebouncer = Timer(const Duration(milliseconds: 100), () {
      dataRefreshNotifier.value++;
      onDataChangedHook?.call();
    });
  }

  void triggerWallpaperRefresh() {
    wallpaperRefreshNotifier.value++;
  }

  void setForceFlushProtectedUuids(Set<String> uuids) {
    _forceFlushProtectedUuids = uuids;
  }

  Future<void> _updateOplogRowsByIds(
    Database db,
    Set<int> ids,
    Map<String, Object?> values,
  ) async {
    const chunkSize = 500;
    final orderedIds = ids.toList()..sort();
    for (var start = 0; start < orderedIds.length; start += chunkSize) {
      final end = start + chunkSize < orderedIds.length
          ? start + chunkSize
          : orderedIds.length;
      final chunk = orderedIds.sublist(start, end);
      if (chunk.isEmpty) continue;
      final placeholders = List.filled(chunk.length, '?').join(',');
      await db.update(
        'op_logs',
        values,
        where: 'id IN ($placeholders)',
        whereArgs: chunk,
      );
    }
  }

  void requestSync(String username) {
    if (username.isEmpty) return;
    _queuedSyncUsername = username;
    if (_syncDebouncer != null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsed = now - _lastSyncRequestAt;
    final delayMs = _isSyncing
        ? _minSyncInterval.inMilliseconds
        : (_minSyncInterval.inMilliseconds - elapsed)
            .clamp(0, _minSyncInterval.inMilliseconds);

    _scheduleQueuedSync(Duration(milliseconds: delayMs));
  }

  void _scheduleQueuedSync(Duration delay) {
    _syncDebouncer?.cancel();
    _syncDebouncer = Timer(delay, () {
      _syncDebouncer = null;
      if (_isSyncing) {
        _scheduleQueuedSync(_minSyncInterval);
        return;
      }

      final username = _queuedSyncUsername;
      _queuedSyncUsername = null;
      if (username == null || username.isEmpty) return;
      unawaited(syncData(username));
    });
  }

  int _normalizedRecurrenceIndex(TodoItem item) {
    final int idx = item.recurrence.index;
    return idx >= 0 && idx < RecurrenceType.values.length ? idx : 0;
  }

  int _normalizedCustomIntervalDays(TodoItem item) {
    final int? raw = item.customIntervalDays;
    if (item.recurrence == RecurrenceType.customDays) {
      return (raw != null && raw > 0) ? raw : 1;
    }
    return (raw != null && raw >= 0) ? raw : 0;
  }

  int? _parseNullableInt(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString());
  }

  Future<void> ignoreRemoteItem({
    required String table,
    required String uuid,
    String? teamUuid,
  }) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert(
        'ignored_remote_items',
        {
          'uuid': uuid,
          'team_uuid': teamUuid,
          'table_name': table,
          'ignored_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
    debugPrint("🚫 [忽略项] 已记录 $table.$uuid 至忽略表");
  }

  Future<void> unignoreRemoteItem(String uuid) async {
    final db = await DatabaseHelper.instance.database;
    await db
        .delete('ignored_remote_items', where: 'uuid = ?', whereArgs: [uuid]);
  }

  Future<bool> isItemIgnored(String uuid) async {
    final db = await DatabaseHelper.instance.database;
    final results = await db
        .query('ignored_remote_items', where: 'uuid = ?', whereArgs: [uuid]);
    return results.isNotEmpty;
  }

  String _todoRequestKey(
    String username, {
    required bool includeDeleted,
    required int? limit,
  }) {
    return '$username|includeDeleted=$includeDeleted|limit=${limit ?? "all"}';
  }

  List<TodoItem> _cloneTodoItems(List<TodoItem> items) {
    return items.map((item) => TodoItem.fromJson(item.toJson())).toList();
  }

  Future<void> _clearTodoPrefsMirror(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("${keyTodos}_$username");
    await prefs.remove(keyTodos);
  }

  String _scopedKey(String baseKey, String? username) {
    if (username == null || username.isEmpty) return baseKey;
    return "${baseKey}_$username";
  }

  Future<String> getDeviceFriendlyName() async =>
      UserSessionStorage.getDeviceFriendlyName();
  Future<String?> getCurrentUsername() =>
      UserSessionStorage.getCurrentUsername();
  Future<bool> rollbackLocalItem(
      String table, int logId, String username) async {
    try {
      // 1. 执行 SQL 层的物理回滚
      final success = await DatabaseHelper.instance.rollbackFromLocalLog(logId);
      if (!success) return false;

      // 2. 🚀 关键：立即从 DB 重载该表的数据并刷新内存/Prefs 缓存
      if (table == 'todos') {
        final List<TodoItem> freshTodos =
            await DatabaseHelper.instance.getTodos();
        await saveTodos(username, freshTodos, sync: false, isSyncSource: true);
      } else if (table == 'countdowns') {
        final List<CountdownItem> freshCds =
            await DatabaseHelper.instance.getCountdowns();
        await saveCountdowns(username, freshCds,
            sync: false, isSyncSource: true);
      }

      // 3. 触发 UI 刷新信号
      triggerRefresh();
      return true;
    } catch (e) {
      debugPrint("❌ rollbackLocalItem error: $e");
      return false;
    }
  }

  Future<String> getDeviceId() => UserSessionStorage.getDeviceId();
  Future<void> initTheme() async {
    final prefs = await StorageService.prefs;
    themeNotifier.value = prefs.getString(keyThemeMode) ?? 'system';
    themeColorModeNotifier.value =
        prefs.getString(keyThemeColorMode) ?? 'default';
    int? colorVal = prefs.getInt(keyCustomThemeColor);
    if (colorVal != null) {
      customThemeColorNotifier.value = Color(colorVal);
    }
  }

  Future<bool> register(String username, String password) =>
      UserSessionStorage.register(username, password);
  Future<bool> login(String username, String password) =>
      UserSessionStorage.login(username, password);
  Future<void> saveLoginSession(String username, {String? token}) =>
      UserSessionStorage.saveLoginSession(username, token: token);
  Future<String?> getLoginSession() => UserSessionStorage.getLoginSession();
  Future<void> clearLoginSession() => UserSessionStorage.clearLoginSession();
  Future<void> saveSettings(Map<String, dynamic> settings) async {
    final prefs = await StorageService.prefs;
    await prefs.setString(keySettings, jsonEncode(settings));
  }

  Future<Map<String, dynamic>> getSettings() async {
    final prefs = await StorageService.prefs;
    String? jsonStr = prefs.getString(keySettings);
    if (jsonStr != null) return Map<String, dynamic>.from(jsonDecode(jsonStr));
    return {
      'operators': ['+', '-'],
      'min_num1': 0,
      'max_num1': 50,
      'min_num2': 0,
      'max_num2': 50,
      'max_result': 100,
    };
  }

  Future<void> saveWindowsScheduledReminders(
      List<Map<String, dynamic>> reminders) async {
    final prefs = await StorageService.prefs;
    await prefs.setString(keyWindowsScheduledReminders, jsonEncode(reminders));
  }

  Future<List<Map<String, dynamic>>> getWindowsScheduledReminders() async {
    final prefs = await StorageService.prefs;
    String? jsonStr = prefs.getString(keyWindowsScheduledReminders);
    if (jsonStr == null || jsonStr.isEmpty) return [];
    try {
      final List<dynamic> list = jsonDecode(jsonStr);
      return list.map((item) => Map<String, dynamic>.from(item)).toList();
    } catch (e) {
      debugPrint("解析 Windows 预约提醒失败: $e");
      return [];
    }
  }

  Future<void> savePomodoroTags(
          String username, List<Map<String, dynamic>> tags) =>
      PomodoroStorage.savePomodoroTags(username, tags);
  Future<void> saveHistory(
      String username, int score, int duration, String details) async {
    final prefs = await SharedPreferences.getInstance();
    String key = "history_$username";
    List<String> history = prefs.getStringList(key) ?? [];
    Map<String, dynamic> recordMap = {
      'date': DateTime.now().toIso8601String(),
      'score': score,
      'duration': duration,
      'details': details
    };
    history.insert(0, jsonEncode(recordMap));
    await prefs.setStringList(key, history);
  }

  Future<List<String>> getHistory(String username) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> rawList = prefs.getStringList("history_$username") ?? [];
    return rawList.map((item) {
      try {
        var map = jsonDecode(item);
        if (map is Map) {
          String timeStr = DateFormat('yyyy-MM-dd HH:mm:ss')
              .format(DateTime.parse(map['date']));
          return "时间: $timeStr\n得分: ${map['score']}\n用时: ${map['duration']}秒\n详情:\n${map['details']}\n-----------------";
        }
        return item;
      } catch (e) {
        return item;
      }
    }).toList();
  }

  Future<Map<String, dynamic>> getMathStats(String username) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> rawList = prefs.getStringList("history_$username") ?? [];
    int totalQuestions = 0, totalCorrect = 0, bestTime = 999999, todayCount = 0;
    bool hasPerfectScore = false;
    DateTime now = DateTime.now();
    for (var item in rawList) {
      try {
        var map = jsonDecode(item);
        int score = map['score'], duration = map['duration'];
        if (map['date'] != null) {
          DateTime date = DateTime.parse(map['date']);
          if (date.year == now.year &&
              date.month == now.month &&
              date.day == now.day) {
            todayCount++;
          }
        }
        totalQuestions += 10;
        totalCorrect += (score ~/ 10);
        if (score == 100) {
          hasPerfectScore = true;
          if (duration < bestTime) bestTime = duration;
        }
      } catch (e) {
        RegExp scoreReg = RegExp(r"得分: (\d+)");
        var match = scoreReg.firstMatch(item);
        if (match != null) {
          int score = int.parse(match.group(1)!);
          totalQuestions += 10;
          totalCorrect += (score ~/ 10);
        }
      }
    }
    double accuracy =
        totalQuestions == 0 ? 0.0 : (totalCorrect / totalQuestions);
    return {
      'accuracy': accuracy,
      'bestTime': hasPerfectScore ? bestTime : null,
      'todayCount': todayCount
    };
  }

  Future<void> updateLeaderboard(
      String username, int score, int duration) async {
    final prefs = await SharedPreferences.getInstance();
    List<dynamic> list = [];
    String? jsonStr = prefs.getString(keyLeaderboard);
    if (jsonStr != null) list = jsonDecode(jsonStr);
    list.add({'username': username, 'score': score, 'time': duration});
    list.sort((a, b) {
      if (a['score'] != b['score']) return b['score'].compareTo(a['score']);
      return a['time'].compareTo(b['time']);
    });
    if (list.length > 10) list = list.sublist(0, 10);
    await prefs.setString(keyLeaderboard, jsonEncode(list));
    requestSync(username);
  }

  Future<List<Map<String, dynamic>>> getLeaderboard() async {
    final prefs = await SharedPreferences.getInstance();
    String? jsonStr = prefs.getString(keyLeaderboard);
    if (jsonStr == null) return [];
    return List<Map<String, dynamic>>.from(jsonDecode(jsonStr));
  }

  Future<void> saveCountdowns(String username, List<CountdownItem> items,
          {bool sync = true, bool isSyncSource = false}) =>
      CountdownStorage.saveCountdowns(
        username,
        items,
        sync: sync,
        isSyncSource: isSyncSource,
        hasSubstantialChange: _hasSubstantialChange,
        recordLocalAudit: _recordLocalAuditOptimized,
        requestSync: requestSync,
        onCommitted: _inflightTodoRequests.clear,
      );
  Future<void> _clearGhostConflictFlags(dynamic db) =>
      StorageConflictCleanup.clearGhostConflictFlags(db);
  Future<List<CountdownItem>> getCountdowns(String username,
          {bool includeDeleted = false}) =>
      CountdownStorage.getCountdowns(
        username,
        includeDeleted: includeDeleted,
        saveMigratedCountdowns: saveCountdowns,
      );
  Future<void> deleteCountdownGlobally(
      String username, String idToDelete) async {
    List<CountdownItem> localCds = await getCountdowns(username);
    int index = localCds.indexWhere((t) => t.id == idToDelete);
    if (index != -1) {
      localCds[index].isDeleted = true;
      try {
        localCds[index].markAsChanged();
      } catch (_) {
        localCds[index].updatedAt = DateTime.now().millisecondsSinceEpoch;
        localCds[index].version += 1;
      }
      await saveCountdowns(username, localCds, sync: true);
    }
  }
}
