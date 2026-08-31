part of 'storage_service.dart';
// ignore_for_file: annotate_overrides, unused_element, unused_element_parameter

mixin _StorageSettings on _StorageServiceBase {
  Future<bool> syncScreenTimeAlone(String username, String deviceName) async {
    final prefs = await SharedPreferences.getInstance();
    int? userId = prefs.getInt('current_user_id');
    if (userId == null) {
      debugPrint("syncScreenTimeAlone: user not logged in");
      return false;
    }

    try {
      final localPackage = await getLocalScreenTimeMap();
      final apps = localPackage['apps'] as List<dynamic>?;
      final date = localPackage['date'] as String?;

      if (apps == null || apps.isEmpty || date == null) {
        debugPrint("syncScreenTimeAlone: no data to upload");
        return false;
      }

      final formattedApps = apps
          .whereType<Map>()
          .map((e) => {
                'app_name': e['app_name']?.toString() ?? 'Unknown',
                'duration': (e['duration'] is int) ? e['duration'] : 0,
              })
          .toList();

      final success = await ApiService.uploadScreenTime(
        userId: userId,
        deviceName: deviceName,
        date: date,
        apps: formattedApps,
      );

      if (success) {
        await prefs.remove(_scopedKey(keyLocalScreenTime, username));
        return true;
      } else {
        debugPrint("syncScreenTimeAlone failed");
        return false;
      }
    } catch (e) {
      debugPrint("syncScreenTimeAlone error: $e");
      return false;
    }
  }

  Future<void> saveAppSetting(String key, dynamic value) async {
    final prefs = await StorageService.prefs;
    String finalKey = key;

    // 🚀 全局设置例外列表 (不进行账户隔离的设置)
    const List<String> globalSettings = [
      keyThemeMode,
      keyServerChoice,
      keySystemStartupEnabled,
      keyDeviceId,
      'update_channel',
    ];

    if (!globalSettings.contains(key)) {
      final String? username = prefs.getString(keyCurrentUser);
      if (username != null && username.isNotEmpty) {
        finalKey = StorageKeyScope.scoped(key, username);
      }
    }

    if (value is int) await prefs.setInt(finalKey, value);
    if (value is String) await prefs.setString(finalKey, value);
    if (value is bool) await prefs.setBool(finalKey, value);
    if (key == keyThemeMode) themeNotifier.value = value;
  }

  Future<int> getSyncInterval() async {
    final prefs = await StorageService.prefs;
    final String? username = prefs.getString(keyCurrentUser);
    if (username != null && username.isNotEmpty) {
      return prefs.getInt(StorageKeyScope.scoped(keySyncInterval, username)) ??
          (prefs.getInt(keySyncInterval) ?? 0);
    }
    return prefs.getInt(keySyncInterval) ?? 0;
  }

  Future<bool> getConflictDetectionEnabled() async {
    final prefs = await StorageService.prefs;
    final String? username = prefs.getString(keyCurrentUser);
    if (username != null && username.isNotEmpty) {
      return prefs.getBool(
            StorageKeyScope.scoped(keyConflictDetectionEnabled, username),
          ) ??
          (prefs.getBool(keyConflictDetectionEnabled) ?? false);
    }
    return prefs.getBool(keyConflictDetectionEnabled) ?? false;
  }

  Future<String> getThemeMode() async {
    final prefs = await StorageService.prefs;
    return prefs.getString(keyThemeMode) ?? 'system';
  }

  Future<void> setThemeColorMode(String mode) async {
    final prefs = await StorageService.prefs;
    await prefs.setString(keyThemeColorMode, mode);
    themeColorModeNotifier.value = mode;
  }

  Future<void> setCustomThemeColor(Color color) async {
    final prefs = await StorageService.prefs;
    await prefs.setInt(keyCustomThemeColor, color.toARGB32());
    customThemeColorNotifier.value = color;
  }

  void setAppWallpaperColor(Color? color) {
    appWallpaperColorNotifier.value = color;
  }

  Future<void> saveServerChoice(String choice) async {
    final prefs = await StorageService.prefs;
    await prefs.setString(keyServerChoice, choice);
    ApiService.setServerChoice(choice);
  }

  Future<String> getServerChoice() async {
    final prefs = await StorageService.prefs;
    return prefs.getString(keyServerChoice) ?? 'aliyun';
  }

  Future<void> saveHomeTextConfig(Map<String, dynamic> config) async {
    final prefs = await StorageService.prefs;
    final String? username = prefs.getString(keyCurrentUser);
    final key = username != null && username.isNotEmpty
        ? "${_keyHomeTextConfig}_$username"
        : _keyHomeTextConfig;
    await prefs.setString(key, jsonEncode(config));
  }

  Future<Map<String, dynamic>> getHomeTextConfig() async {
    final prefs = await StorageService.prefs;
    final String? username = prefs.getString(keyCurrentUser);
    final key = username != null && username.isNotEmpty
        ? "${_keyHomeTextConfig}_$username"
        : _keyHomeTextConfig;
    final String? jsonStr = prefs.getString(key);
    if (jsonStr != null) {
      return Map<String, dynamic>.from(jsonDecode(jsonStr));
    }
    return {};
  }

  Future<bool> getSemesterEnabled() async {
    final prefs = await StorageService.prefs;
    final String? username = prefs.getString(keyCurrentUser);
    if (username == null || username.isEmpty) {
      return prefs.getBool(keySemesterProgressEnabled) ?? false;
    }

    final bool? scoped =
        prefs.getBool("${keySemesterProgressEnabled}_$username");
    if (scoped == null) {
      final bool global = prefs.getBool(keySemesterProgressEnabled) ?? false;
      await prefs.setBool("${keySemesterProgressEnabled}_$username", global);
      return global;
    }
    return scoped;
  }

  Future<DateTime?> getSemesterStart() async {
    final prefs = await StorageService.prefs;
    final String? username = prefs.getString(keyCurrentUser);
    if (username == null || username.isEmpty) {
      String? s = prefs.getString(keySemesterStart);
      return s != null ? DateTime.tryParse(s) : null;
    }

    String? s = prefs.getString("${keySemesterStart}_$username");

    // 迁移检查：如果用户没有设置过隔离的日期，回退一次全局数据
    if (s == null) {
      s = prefs.getString(keySemesterStart);
      if (s != null) {
        await prefs.setString("${keySemesterStart}_$username", s);
      }
    }

    return s != null ? DateTime.tryParse(s) : null;
  }

  Future<DateTime?> getSemesterEnd() async {
    final prefs = await StorageService.prefs;
    final String? username = prefs.getString(keyCurrentUser);
    if (username == null || username.isEmpty) {
      String? s = prefs.getString(keySemesterEnd);
      return s != null ? DateTime.tryParse(s) : null;
    }

    String? s = prefs.getString("${keySemesterEnd}_$username");
    if (s == null) {
      s = prefs.getString(keySemesterEnd);
      if (s != null) {
        await prefs.setString("${keySemesterEnd}_$username", s);
      }
    }
    return s != null ? DateTime.tryParse(s) : null;
  }

  Future<List<SemesterInfo>> getSemesters() async {
    final prefs = await StorageService.prefs;
    final String? username = prefs.getString(keyCurrentUser);
    final String key = username != null && username.isNotEmpty
        ? "${keySemesters}_$username"
        : keySemesters;

    final String? jsonStr = prefs.getString(key);
    if (jsonStr == null || jsonStr.isEmpty) {
      // 迁移：如果没有任何学期数据，从旧的 semesterStart 创建一个默认学期
      final oldStart = await getSemesterStart();
      if (oldStart != null) {
        final defaultSemester = SemesterInfo(
          id: 'default',
          name: '当前学期',
          startDate: oldStart,
          isCurrent: true,
        );
        await saveSemesters([defaultSemester]);
        return [defaultSemester];
      }
      return [];
    }

    try {
      final List<dynamic> list = jsonDecode(jsonStr);
      return list
          .map((e) => SemesterInfo.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveSemesters(List<SemesterInfo> semesters) async {
    final prefs = await StorageService.prefs;
    final String? username = prefs.getString(keyCurrentUser);
    final String key = username != null && username.isNotEmpty
        ? "${keySemesters}_$username"
        : keySemesters;

    final jsonStr = jsonEncode(semesters.map((s) => s.toJson()).toList());
    await prefs.setString(key, jsonStr);

    // 同步更新旧的 semesterStart/semesterEnd（兼容）
    final current = semesters.where((s) => s.isCurrent).toList();
    if (current.isNotEmpty) {
      await prefs.setString(
          username != null && username.isNotEmpty
              ? "${keySemesterStart}_$username"
              : keySemesterStart,
          current.first.startDate.toIso8601String());
      if (current.first.endDate != null) {
        await prefs.setString(
            username != null && username.isNotEmpty
                ? "${keySemesterEnd}_$username"
                : keySemesterEnd,
            current.first.endDate!.toIso8601String());
      }
    }
  }

  Future<String> getActiveSemesterId() async {
    final prefs = await StorageService.prefs;
    final String? username = prefs.getString(keyCurrentUser);
    final String key = username != null && username.isNotEmpty
        ? "${keyActiveSemester}_$username"
        : keyActiveSemester;

    return prefs.getString(key) ?? 'default';
  }

  Future<void> setActiveSemesterId(String semesterId) async {
    final prefs = await StorageService.prefs;
    final String? username = prefs.getString(keyCurrentUser);
    final String key = username != null && username.isNotEmpty
        ? "${keyActiveSemester}_$username"
        : keyActiveSemester;

    await prefs.setString(key, semesterId);
  }

  Future<DateTime?> getSemesterStartById(String semesterId) async {
    final semesters = await getSemesters();
    try {
      final semester = semesters.firstWhere((s) => s.id == semesterId);
      return semester.startDate;
    } catch (_) {
      return null;
    }
  }

  Future<SemesterInfo?> getSemesterByDate(DateTime date) async {
    final semesters = await getSemesters();
    for (final semester in semesters) {
      final start = DateTime(semester.startDate.year, semester.startDate.month,
          semester.startDate.day);
      final end = semester.endDate != null
          ? DateTime(semester.endDate!.year, semester.endDate!.month,
              semester.endDate!.day)
          : start.add(const Duration(days: 120)); // 默认4个月

      if (!date.isBefore(start) && !date.isAfter(end)) {
        return semester;
      }
    }
    return null;
  }

  Future<void> updateLastAutoSyncTime(String username) async {
    final prefs = await StorageService.prefs;
    await prefs.setInt(
        "${keyLastAutoSync}_$username", DateTime.now().millisecondsSinceEpoch);
  }

  Future<DateTime?> getLastAutoSyncTime(String username) async {
    final prefs = await StorageService.prefs;
    int? timestamp = prefs.getInt("${keyLastAutoSync}_$username");
    if (timestamp != null) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true)
          .toLocal();
    }
    return null;
  }

  Future<void> saveIslandBounds(
      String islandId, Map<String, dynamic> bounds) async {
    try {
      final prefs = await StorageService.prefs;
      await prefs.setString('island_bounds_$islandId', jsonEncode(bounds));
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> getIslandBounds(String islandId) async {
    try {
      final prefs = await StorageService.prefs;
      final s = prefs.getString('island_bounds_$islandId');
      if (s == null || s.isEmpty) return null;
      final m = jsonDecode(s);
      if (m is Map && m.isNotEmpty) return Map<String, dynamic>.from(m);
    } catch (_) {}
    return null;
  }

  Future<int> getLLMRetryCount() async {
    final prefs = await StorageService.prefs;
    return prefs.getInt(keyLlmRetryCount) ?? 3;
  }

  Future<void> setLLMRetryCount(int count) async {
    final prefs = await StorageService.prefs;
    await prefs.setInt(keyLlmRetryCount, count);
  }

  Future<void> savePendingTodoConfirm({
    required String imagePath,
    List<Map<String, dynamic>> results = const [],
    List<Map<String, dynamic>> financeResults = const [],
    String status = 'success',
    String? compressedPath,
    String? sourceKey,
    int currentAttempt = 1,
    int maxAttempts = 1,
    String? errorMsg,
  }) async {
    final prefs = await StorageService.prefs;
    final data = jsonEncode({
      'imagePath': imagePath,
      'results': results,
      'financeResults': financeResults,
      'status': status,
      'compressedPath': compressedPath,
      'sourceKey': sourceKey,
      'currentAttempt': currentAttempt,
      'maxAttempts': maxAttempts,
      'errorMsg': errorMsg,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    await prefs.setString(keyPendingTodoConfirm, data);
  }

  Future<void> updatePendingTodoConfirmStatus({
    required String status,
    int? currentAttempt,
    int? maxAttempts,
    String? errorMsg,
    List<Map<String, dynamic>>? results,
    List<Map<String, dynamic>>? financeResults,
  }) async {
    final existing = await getPendingTodoConfirm();
    if (existing == null) return;

    final prefs = await StorageService.prefs;
    final data = jsonEncode({
      ...existing,
      'status': status,
      'currentAttempt': currentAttempt ?? existing['currentAttempt'] ?? 1,
      'maxAttempts': maxAttempts ?? existing['maxAttempts'] ?? 1,
      'errorMsg': errorMsg ?? existing['errorMsg'],
      'results': results ?? existing['results'] ?? [],
      'financeResults': financeResults ?? existing['financeResults'] ?? [],
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    await prefs.setString(keyPendingTodoConfirm, data);
  }

  Future<Map<String, dynamic>?> getPendingTodoConfirm() async {
    final prefs = await StorageService.prefs;
    final data = prefs.getString(keyPendingTodoConfirm);
    if (data == null) return null;
    try {
      return jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearPendingTodoConfirm() async {
    final prefs = await StorageService.prefs;
    await prefs.remove(keyPendingTodoConfirm);
  }

  Future<bool> isLiveActivityNotificationEnabled() =>
      AppSettingsStorage.isLiveActivityNotificationEnabled();
  Future<void> setLiveActivityNotificationEnabled(bool enabled) =>
      AppSettingsStorage.setLiveActivityNotificationEnabled(enabled);
  Future<bool> isNormalNotificationEnabled() =>
      AppSettingsStorage.isNormalNotificationEnabled();
  Future<void> setNormalNotificationEnabled(bool enabled) =>
      AppSettingsStorage.setNormalNotificationEnabled(enabled);
  Future<bool> isCourseNotificationEnabled() =>
      AppSettingsStorage.isCourseNotificationEnabled();
  Future<void> setCourseNotificationEnabled(bool enabled) =>
      AppSettingsStorage.setCourseNotificationEnabled(enabled);
  Future<bool> isQuizNotificationEnabled() =>
      AppSettingsStorage.isQuizNotificationEnabled();
  Future<void> setQuizNotificationEnabled(bool enabled) =>
      AppSettingsStorage.setQuizNotificationEnabled(enabled);
  Future<bool> isTodoSummaryNotificationEnabled() =>
      AppSettingsStorage.isTodoSummaryNotificationEnabled();
  Future<void> setTodoSummaryNotificationEnabled(bool enabled) =>
      AppSettingsStorage.setTodoSummaryNotificationEnabled(enabled);
  Future<bool> isSpecialTodoNotificationEnabled() =>
      AppSettingsStorage.isSpecialTodoNotificationEnabled();
  Future<void> setSpecialTodoNotificationEnabled(bool enabled) =>
      AppSettingsStorage.setSpecialTodoNotificationEnabled(enabled);
  Future<bool> isPomodoroNotificationEnabled() =>
      AppSettingsStorage.isPomodoroNotificationEnabled();
  Future<void> setPomodoroNotificationEnabled(bool enabled) =>
      AppSettingsStorage.setPomodoroNotificationEnabled(enabled);
  Future<bool> isTodoRecognizeNotificationEnabled() =>
      AppSettingsStorage.isTodoRecognizeNotificationEnabled();
  Future<void> setTodoRecognizeNotificationEnabled(bool enabled) =>
      AppSettingsStorage.setTodoRecognizeNotificationEnabled(enabled);
  Future<bool> isTodoLiveNotificationEnabled() =>
      AppSettingsStorage.isTodoLiveNotificationEnabled();
  Future<void> setTodoLiveNotificationEnabled(bool enabled) =>
      AppSettingsStorage.setTodoLiveNotificationEnabled(enabled);
  Future<bool> isPomodoroEndNotificationEnabled() =>
      AppSettingsStorage.isPomodoroEndNotificationEnabled();
  Future<void> setPomodoroEndNotificationEnabled(bool enabled) =>
      AppSettingsStorage.setPomodoroEndNotificationEnabled(enabled);
  Future<bool> isReminderNotificationEnabled() =>
      AppSettingsStorage.isReminderNotificationEnabled();
  Future<void> setReminderNotificationEnabled(bool enabled) =>
      AppSettingsStorage.setReminderNotificationEnabled(enabled);
  Future<int> getCourseReminderMinutes() =>
      AppSettingsStorage.getCourseReminderMinutes();
  Future<void> setCourseReminderMinutes(int minutes) =>
      AppSettingsStorage.setCourseReminderMinutes(minutes);
  Future<bool> isPrivacyPolicyAgreed() =>
      AppSettingsStorage.isPrivacyPolicyAgreed();
  Future<void> setPrivacyPolicyAgreed(bool agreed, {String? date}) =>
      AppSettingsStorage.setPrivacyPolicyAgreed(agreed, date: date);
  Future<bool> isPrivacyPolicyUpToDate() =>
      AppSettingsStorage.isPrivacyPolicyUpToDate();
  Future<void> withdrawPrivacyAgreement() =>
      AppSettingsStorage.withdrawPrivacyAgreement();
  void dispose() {
    _recurrenceCheckCache.clear();
    _attemptedRecurrenceSeriesRepairUploads.clear();
    _lastRecurrenceCheckDate = null;
  }

  Future<String> getWallpaperProvider() =>
      AppSettingsStorage.getWallpaperProvider();
  Future<void> saveWallpaperProvider(String provider) =>
      AppSettingsStorage.saveWallpaperProvider(provider);
  Future<String> getWallpaperImageFormat() =>
      AppSettingsStorage.getWallpaperImageFormat();
  Future<void> saveWallpaperImageFormat(String format) =>
      AppSettingsStorage.saveWallpaperImageFormat(format);
  Future<int> getWallpaperIndex() => AppSettingsStorage.getWallpaperIndex();
  Future<void> saveWallpaperIndex(int index) =>
      AppSettingsStorage.saveWallpaperIndex(index);
  Future<String> getWallpaperMkt() => AppSettingsStorage.getWallpaperMkt();
  Future<void> saveWallpaperMkt(String mkt) =>
      AppSettingsStorage.saveWallpaperMkt(mkt);
  Future<String> getWallpaperResolution() =>
      AppSettingsStorage.getWallpaperResolution();
  Future<void> saveWallpaperResolution(String resolution) =>
      AppSettingsStorage.saveWallpaperResolution(resolution);
  Future<int?> getWallpaperCacheCleanupTime() =>
      AppSettingsStorage.getWallpaperCacheCleanupTime();
  Future<void> saveWallpaperCacheCleanupTime(int timestamp) =>
      AppSettingsStorage.saveWallpaperCacheCleanupTime(timestamp);
  Future<String?> getWallpaperCustomPath() =>
      AppSettingsStorage.getWallpaperCustomPath();
  Future<void> saveWallpaperCustomPath(String path) =>
      AppSettingsStorage.saveWallpaperCustomPath(path);
  Future<void> clearWallpaperCustomPath() =>
      AppSettingsStorage.clearWallpaperCustomPath();
  Future<bool> getTodoFoldersInline() =>
      AppSettingsStorage.getTodoFoldersInline();
  Future<void> setTodoFoldersInline(bool inline) =>
      AppSettingsStorage.setTodoFoldersInline(inline);
  Future<String> getTodoFolderDisplayMode() =>
      AppSettingsStorage.getTodoFolderDisplayMode();
  Future<void> setTodoFolderDisplayMode(String mode) =>
      AppSettingsStorage.setTodoFolderDisplayMode(mode);
  Future<void> saveLastCourseImportUrl(String url) =>
      AppSettingsStorage.saveLastCourseImportUrl(url);
  Future<String?> getLastCourseImportUrl() =>
      AppSettingsStorage.getLastCourseImportUrl();
  Future<Map<String, int>> getCategoryReminderMinutes(String username) =>
      AppSettingsStorage.getCategoryReminderMinutes(username);
  Future<void> saveCategoryReminderMinutes(
          String username, Map<String, int> data) =>
      AppSettingsStorage.saveCategoryReminderMinutes(username, data);
  Future<List<Map<String, dynamic>>> getSyncFailures() async {
    final db = await DatabaseHelper.instance.database;
    return await db.query('op_logs',
        where: "sync_error IS NOT NULL AND sync_error != '' AND is_synced = 0",
        orderBy: 'timestamp DESC');
  }

  Future<void> resolveConflictLocally({
    required String uuid,
    required String table,
    required Map<String, dynamic> resolvedData,
    bool createOplog = false,
    bool touchUpdatedAt = true,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final batch = db.batch();

    resolvedData['has_conflict'] = 0;
    resolvedData.remove('conflict_data');
    resolvedData.remove('serverVersionData');
    final now = DateTime.now().millisecondsSinceEpoch;
    final resolvedUpdatedAt = touchUpdatedAt
        ? now
        : (resolvedData['updated_at'] ??
            resolvedData['updatedAt'] ??
            DateTime.now().millisecondsSinceEpoch);
    resolvedData['updated_at'] = resolvedUpdatedAt;

    switch (table) {
      case 'todos':
        batch.update(
          'todos',
          {
            'has_conflict': 0,
            'version': resolvedData['version'],
            'updated_at': resolvedUpdatedAt,
            'created_at': resolvedData['created_at'] ??
                resolvedData['createdAt'] ??
                resolvedUpdatedAt,
            'content': resolvedData['content'] ?? resolvedData['title'] ?? '',
            'is_deleted': resolvedData['is_deleted'] == 1 ||
                    resolvedData['is_deleted'] == true
                ? 1
                : 0,
            'is_completed': resolvedData['is_completed'] == 1 ||
                    resolvedData['is_completed'] == true
                ? 1
                : 0,
            'due_date':
                resolvedData['due_date'] ?? resolvedData['dueDate'] ?? 0,
            'remark': resolvedData['remark'],
            'group_id': resolvedData['group_id'] ?? resolvedData['groupId'],
            'team_uuid': resolvedData['team_uuid'] ?? resolvedData['teamUuid'],
            'recurrence': resolvedData['recurrence'] ?? 0,
            'custom_interval_days': resolvedData['custom_interval_days'] ??
                resolvedData['customIntervalDays'] ??
                0,
            'recurrence_end_date': resolvedData['recurrence_end_date'] ??
                resolvedData['recurrenceEndDate'],
            'is_all_day': resolvedData['is_all_day'] == 1 ||
                    resolvedData['is_all_day'] == true ||
                    resolvedData['isAllDay'] == true
                ? 1
                : 0,
            'reminder_minutes': resolvedData['reminder_minutes'] ??
                resolvedData['reminderMinutes'] ??
                -1,
            'created_date': resolvedData['created_date'] ??
                resolvedData['createdDate'] ??
                0,
            'collab_type':
                resolvedData['collab_type'] ?? resolvedData['collabType'] ?? 0,
          },
          where: 'uuid = ?',
          whereArgs: [uuid],
        );
        break;

      case 'countdowns':
        final targetTime = resolvedData['target_time'] ??
            resolvedData['targetTime'] ??
            resolvedData['target_date'] ??
            0;
        batch.update(
          'countdowns',
          {
            'has_conflict': 0,
            'version': resolvedData['version'],
            'updated_at': resolvedUpdatedAt,
            'title': resolvedData['title'] ?? '',
            'is_deleted': resolvedData['is_deleted'] == 1 ||
                    resolvedData['is_deleted'] == true
                ? 1
                : 0,
            'is_completed': resolvedData['is_completed'] == 1 ||
                    resolvedData['is_completed'] == true
                ? 1
                : 0,
            'target_time': targetTime is int ? targetTime : 0,
            'team_uuid': resolvedData['team_uuid'] ?? resolvedData['teamUuid'],
          },
          where: 'uuid = ?',
          whereArgs: [uuid],
        );
        break;

      case 'todo_groups':
        batch.update(
          'todo_groups',
          {
            'has_conflict': 0,
            'version': resolvedData['version'],
            'updated_at': resolvedUpdatedAt,
            'name': resolvedData['name'] ?? '',
            'is_deleted': resolvedData['is_deleted'] == 1 ||
                    resolvedData['is_deleted'] == true
                ? 1
                : 0,
            'is_expanded': resolvedData['is_expanded'] == 1 ||
                    resolvedData['is_expanded'] == true
                ? 1
                : 0,
            'team_uuid': resolvedData['team_uuid'] ?? resolvedData['teamUuid'],
          },
          where: 'uuid = ?',
          whereArgs: [uuid],
        );
        break;
      case 'habit_goals':
        batch.update(
          'habit_goals',
          {
            'has_conflict': 0,
            'version': resolvedData['version'],
            'updated_at': resolvedUpdatedAt,
            'name': resolvedData['name'] ?? '',
            'icon': resolvedData['icon'],
            'source_type':
                resolvedData['source_type'] ?? resolvedData['sourceType'] ?? 2,
            'source_ids':
                resolvedData['source_ids'] ?? resolvedData['sourceIds'],
            'current_rule_uuid': resolvedData['current_rule_uuid'] ??
                resolvedData['currentRuleUuid'],
            'display_mode': resolvedData['display_mode'] ??
                resolvedData['displayMode'] ??
                0,
            'default_focus_minutes': resolvedData['default_focus_minutes'] ??
                resolvedData['defaultFocusMinutes'],
            'sort_order':
                resolvedData['sort_order'] ?? resolvedData['sortOrder'] ?? 0,
            'is_archived': resolvedData['is_archived'] == 1 ||
                    resolvedData['is_archived'] == true
                ? 1
                : 0,
            'is_deleted': resolvedData['is_deleted'] == 1 ||
                    resolvedData['is_deleted'] == true
                ? 1
                : 0,
            'device_id': resolvedData['device_id'] ?? resolvedData['deviceId'],
            'created_at': resolvedData['created_at'] ??
                resolvedData['createdAt'] ??
                resolvedUpdatedAt,
          },
          where: 'uuid = ?',
          whereArgs: [uuid],
        );
        break;
      case 'habit_goal_rule_revisions':
        batch.update(
          'habit_goal_rule_revisions',
          {
            'has_conflict': 0,
            'version': resolvedData['version'],
            'updated_at': resolvedUpdatedAt,
            'habit_uuid':
                resolvedData['habit_uuid'] ?? resolvedData['habitUuid'],
            'effective_from_date': resolvedData['effective_from_date'] ??
                resolvedData['effectiveFromDate'],
            'effective_to_date': resolvedData['effective_to_date'] ??
                resolvedData['effectiveToDate'],
            'period_type':
                resolvedData['period_type'] ?? resolvedData['periodType'] ?? 0,
            'weekdays_mask': resolvedData['weekdays_mask'] ??
                resolvedData['weekdaysMask'] ??
                127,
            'custom_interval_days': resolvedData['custom_interval_days'] ??
                resolvedData['customIntervalDays'],
            'target_value': resolvedData['target_value'] ??
                resolvedData['targetValue'] ??
                0,
            'unit': resolvedData['unit'],
            'target_time_minute': resolvedData['target_time_minute'] ??
                resolvedData['targetTimeMinute'],
            'time_comparison': resolvedData['time_comparison'] ??
                resolvedData['timeComparison'] ??
                0,
            'time_tolerance_minutes': resolvedData['time_tolerance_minutes'] ??
                resolvedData['timeToleranceMinutes'] ??
                0,
            'day_boundary_minute': resolvedData['day_boundary_minute'] ??
                resolvedData['dayBoundaryMinute'] ??
                0,
            'quick_values_json': resolvedData['quick_values_json'] ??
                resolvedData['quickValuesJson'],
            'reminder_policy_json': resolvedData['reminder_policy_json'] ??
                resolvedData['reminderPolicyJson'],
            'is_deleted': resolvedData['is_deleted'] == 1 ||
                    resolvedData['is_deleted'] == true
                ? 1
                : 0,
            'device_id': resolvedData['device_id'] ?? resolvedData['deviceId'],
            'created_at': resolvedData['created_at'] ??
                resolvedData['createdAt'] ??
                resolvedUpdatedAt,
          },
          where: 'uuid = ?',
          whereArgs: [uuid],
        );
        break;
    }

    batch.delete(
      'op_logs',
      where: 'is_synced = 0 AND target_table = ? AND target_uuid = ?',
      whereArgs: [table, uuid],
    );

    if (createOplog) {
      batch.insert('op_logs', {
        'op_type': 'UPSERT',
        'target_table': table,
        'target_uuid': uuid,
        'data_json': jsonEncode(resolvedData),
        'timestamp': now,
        'is_synced': 0,
        'sync_error': '',
      });
    }

    // Also clear conflict_data
    try {
      await db.rawUpdate(
        'UPDATE $table SET conflict_data = NULL WHERE uuid = ?',
        [uuid],
      );
    } catch (_) {}

    await batch.commit(noResult: true);
    _inflightTodoRequests.clear();

    // Invalidate SharedPreferences cache so next load picks up the resolved item
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString(keyCurrentUser) ?? 'default';
    final key = table == 'todos'
        ? StorageKeyScope.scoped(keyTodos, username)
        : table == 'countdowns'
            ? StorageKeyScope.scoped(keyCountdowns, username)
            : StorageKeyScope.scoped(keyTodoGroups, username);
    await prefs.remove(key);

    triggerRefresh({
      if (table == 'todos') DataRefreshDomain.todos,
      if (table == 'todo_groups') DataRefreshDomain.todoGroups,
      if (table == 'countdowns') DataRefreshDomain.countdowns,
      if (table == 'todo_plan_blocks') DataRefreshDomain.planBlocks,
      if (table == 'fixed_schedules') DataRefreshDomain.fixedSchedules,
    });
    recentlyResolvedUuids.add(uuid);
    recentlyResolvedTimes[uuid] = DateTime.now();
    debugPrint(
        '🔒 [MemoryShield] Locked recently resolved item in memory shield: $uuid (with timestamp)');
  }
}
