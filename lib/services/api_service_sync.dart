part of 'api_service.dart';

Future<Map<String, dynamic>> _apiSyncPostDeltaSync({
  required int userId,
  required int lastSyncTime,
  required String deviceId,
  required List<Map<String, dynamic>> todosChanges,
  required List<Map<String, dynamic>> countdownsChanges,
  List<Map<String, dynamic>> todoGroupsChanges = const [],
  Map<String, dynamic>? screenTime,
  bool forceFullSync = false,
  List<Map<String, dynamic>> timeLogsChanges = const [],
  List<Map<String, dynamic>> planBlocksChanges = const [],
  List<Map<String, dynamic>> fixedSchedulesChanges = const [],
  bool fixedSchedulesFullSync = false,
  List<Map<String, dynamic>> pomodoroChanges = const [],
  List<Map<String, dynamic>> tagChanges = const [],
  List<Map<String, dynamic>> habitGoalsChanges = const [],
  List<Map<String, dynamic>> habitRuleChanges = const [],
  List<Map<String, dynamic>> habitCheckInChanges = const [],
  List<Map<String, dynamic>> habitSleepCoachingPlanChanges = const [],
  List<Map<String, dynamic>> habitDrinkOptionChanges = const [],
  bool habitFullSync = false,
  int? habitLastSyncTime,
  bool syncHabits = true,
  List<Map<String, dynamic>> financeCategoryChanges = const [],
  List<Map<String, dynamic>> financePaymentMethodChanges = const [],
  List<Map<String, dynamic>> financeTransactionChanges = const [],
  List<Map<String, dynamic>> financeLoanChanges = const [],
  List<Map<String, dynamic>> financeLoanInstallmentChanges = const [],
  List<Map<String, dynamic>> financeBudgetChanges = const [],
  List<Map<String, dynamic>> financeRecurringRuleChanges = const [],
  List<Map<String, dynamic>> financeTemplateChanges = const [],
  bool financeFullSync = false,
  int? financeLastSyncTime,
  bool syncFinance = true,
}) async {
  try {
    final Map<String, dynamic> body = {
      'user_id': userId,
      'last_sync_time': lastSyncTime,
      'device_id': deviceId,
      'todos': todosChanges,
      'todo_groups': todoGroupsChanges,
      'countdowns': countdownsChanges,
      'time_logs_changes': timeLogsChanges,
      'todo_plan_blocks_changes': planBlocksChanges,
      'fixed_schedules_changes': fixedSchedulesChanges,
      'fixed_schedules_full_sync': fixedSchedulesFullSync,
      'pomodoro_records_changes': pomodoroChanges,
      'pomodoro_tags_changes': tagChanges,
      'habit_goals_changes': habitGoalsChanges,
      'habit_goal_rules_changes': habitRuleChanges,
      'habit_checkins_changes': habitCheckInChanges,
      'habit_sleep_coaching_plans_changes': habitSleepCoachingPlanChanges,
      'habit_drink_options_changes': habitDrinkOptionChanges,
      'habit_full_sync': habitFullSync,
      'sync_habits': syncHabits,
      'finance_categories_changes': financeCategoryChanges,
      'finance_payment_methods_changes': financePaymentMethodChanges,
      'finance_transactions_changes': financeTransactionChanges,
      'finance_loans_changes': financeLoanChanges,
      'finance_loan_installments_changes': financeLoanInstallmentChanges,
      'finance_budgets_changes': financeBudgetChanges,
      'finance_recurring_rules_changes': financeRecurringRuleChanges,
      'finance_entry_templates_changes': financeTemplateChanges,
      'finance_full_sync': financeFullSync,
      'sync_finance': syncFinance,
      'force_full_sync': forceFullSync,
    };

    if (habitLastSyncTime != null) {
      body['habit_last_sync_time'] = habitLastSyncTime;
    }

    if (financeLastSyncTime != null) {
      body['finance_last_sync_time'] = financeLastSyncTime;
    }

    if (screenTime != null) {
      body['screen_time'] = screenTime;
    }
    body['client_capabilities'] = {'finance_transfers_v1': 1};

    final syncClient = createApiHttpClient();
    ApiService._deltaSyncClient?.close();
    ApiService._deltaSyncClient = syncClient;
    late final http.Response response;
    try {
      response = await ApiService._request(
        'POST',
        '/api/sync',
        body: body,
        client: syncClient,
      );
    } finally {
      if (identical(ApiService._deltaSyncClient, syncClient)) {
        ApiService._deltaSyncClient = null;
      }
      syncClient.close();
    }

    dynamic data;
    try {
      data = jsonDecode(response.body);
    } catch (_) {
      return {
        'success': false,
        'statusCode': response.statusCode,
        'message': '服务端响应格式异常 (HTTP ${response.statusCode})',
      };
    }

    if (data is! Map<String, dynamic>) {
      return {
        'success': false,
        'statusCode': response.statusCode,
        'message': '服务端响应结构异常 (HTTP ${response.statusCode})',
      };
    }

    if (response.statusCode == 200 && data['success'] == true) {
      // 解析冲突信息
      final List<dynamic> rawConflicts = data['conflicts'] ?? [];

      return {
        'success': true,
        'conflicts': rawConflicts,
        'server_todos': data['server_todos'] ?? [],
        'todo_maintenance_rejected_uuids':
            data['todo_maintenance_rejected_uuids'] ?? [],
        'server_todo_groups': data['server_todo_groups'] ?? [],
        'server_countdowns': data['server_countdowns'] ?? [],
        'new_sync_time': data['new_sync_time'],
        'server_time_logs': data['server_time_logs'] ?? [],
        'server_pomodoros': data['server_pomodoro_records'] ?? [],
        'server_tags': data['server_pomodoro_tags'] ?? [],
        'server_plan_blocks': data['server_plan_blocks'] ?? [],
        'server_fixed_schedules': data['server_fixed_schedules'] ?? [],
        'server_habit_goals': data['server_habit_goals'] ?? [],
        'server_habit_goal_rules': data['server_habit_goal_rules'] ?? [],
        'server_habit_checkins': data['server_habit_checkins'] ?? [],
        'server_habit_sleep_coaching_plans':
            data['server_habit_sleep_coaching_plans'] ?? [],
        'server_habit_drink_options': data['server_habit_drink_options'] ?? [],
        'new_habit_sync_time': data['new_habit_sync_time'],
        'server_finance_categories': data['server_finance_categories'] ?? [],
        'server_finance_payment_methods':
            data['server_finance_payment_methods'] ?? [],
        'server_finance_transactions':
            data['server_finance_transactions'] ?? [],
        // Keep these nullable so a finance_v1 server that predates the
        // loan tables cannot be mistaken for an empty loan snapshot.
        'server_finance_loans': data['server_finance_loans'],
        'server_finance_loan_installments':
            data['server_finance_loan_installments'],
        'server_finance_budgets': data['server_finance_budgets'] ?? [],
        'server_finance_recurring_rules':
            data['server_finance_recurring_rules'] ?? [],
        'server_finance_entry_templates':
            data['server_finance_entry_templates'] ?? [],
        'new_finance_sync_time': data['new_finance_sync_time'],
        // Keep a missing acknowledgement field distinguishable from an
        // empty acknowledgement list. This prevents a partially deployed
        // server from advancing the finance cursor or clearing pending rows.
        'finance_acknowledged_changes': data['finance_acknowledged_changes'],
        'finance_conflicts': data['finance_conflicts'] ?? [],
        'finance_full_sync_required':
            data['finance_full_sync_required'] == true,
        'sync_capabilities': data['sync_capabilities'],
        'joined_team_uuids': data['joined_team_uuids'],
        'independent_completions': data['independent_completions'], // 🚀 独立完成状态
        'status': data['status'],
      };
    } else if (response.statusCode == 401) {
      return {
        'success': false,
        'statusCode': 401,
        'code': data['code'],
        'message': data['error'] ?? '登录凭证已失效 (401)',
      };
    } else if (response.statusCode == 429) {
      return {
        'success': false,
        'statusCode': 429,
        'message': data['error'] ?? '今日同步次数已达上限',
        'isLimitExceeded': true,
      };
    } else {
      return {
        'success': false,
        'statusCode': response.statusCode,
        'message': data['error'] ?? '服务端异常 (HTTP ${response.statusCode})',
      };
    }
  } catch (e) {
    return {
      'success': false,
      'message': SyncErrorFormatter.formatTransportError(e),
    };
  }
}

Future<bool> _apiSyncIgnoreRemoteItem({
  required String uuid,
  required String table,
  String? teamUuid,
}) async {
  try {
    final response = await ApiService._request(
      'POST',
      '/api/sync/ignore_remote_item',
      body: {'uuid': uuid, 'table_name': table, 'team_uuid': teamUuid},
    );
    return response.statusCode == 200;
  } catch (e) {
    //       debugPrint("🚫 [ApiService] 忽略上报失败: $e");
    return false;
  }
}

Future<bool> _apiSyncUploadScreenTime({
  required int userId,
  required String deviceName,
  required String date,
  required List<Map<String, dynamic>> apps,
}) async {
  try {
    final response = await ApiService._request(
      'POST',
      '/api/screen_time',
      body: {
        'user_id': userId,
        'device_name': deviceName,
        'record_date': date,
        'apps': apps,
      },
    );
    return response.statusCode == 200;
  } catch (e) {
    return false;
  }
}

Future<List<dynamic>> _apiSyncFetchScreenTime(
  int userId,
  String date, {
  bool throwOnError = false,
}) async {
  try {
    final response = await ApiService._request(
      'GET',
      '/api/screen_time?user_id=$userId&date=$date',
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    if (throwOnError) {
      throw StateError('screen_time HTTP ${response.statusCode}');
    }
    return [];
  } catch (e) {
    if (throwOnError) rethrow;
    return [];
  }
}

Future<Map<String, dynamic>> _apiSyncDebugResetDatabase() async {
  try {
    final response = await ApiService._request(
      'POST',
      '/api/debug/reset_database',
    );
    return jsonDecode(response.body);
  } catch (e) {
    return {'success': false, 'error': e.toString()};
  }
}

Future<List<dynamic>?> _apiSyncFetchAppMappings() async {
  try {
    final response = await ApiService._request(
      'GET',
      '/api/mappings',
      includeAuth: false,
    );
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is List) return decoded;
    }
  } catch (e) {
    // ignore
  }
  return null;
}

Future<List<dynamic>> _apiSyncFetchCourses(
  int userId, {
  String? semester,
}) async {
  try {
    final uri = Uri.parse('${ApiService._effectiveBaseUrl}/api/courses')
        .replace(
          queryParameters: {
            'user_id': userId.toString(),
            'semester': ?semester,
          },
        );
    final response = await ApiService._request('GET', uri.toString());
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return decoded is List ? decoded : [];
    }
    return [];
  } catch (e) {
    return [];
  }
}

Future<List<dynamic>> _apiSyncFetchCoursesForSemesters(
  int userId,
  Iterable<String> semesterIds, {
  bool includeAll = true,
}) async {
  final normalizedSemesters = <String>{
    for (final id in semesterIds)
      if (id.trim().isNotEmpty) id.trim(),
    'default',
  };

  final requests = <Future<List<dynamic>>>[];
  if (includeAll) {
    requests.add(ApiService.fetchCourses(userId, semester: 'all'));
  }
  requests.addAll(
    normalizedSemesters.map((semester) async {
      final courses = await ApiService.fetchCourses(userId, semester: semester);
      return courses.map((course) {
        if (course is! Map) return course;
        final map = Map<String, dynamic>.from(course);
        if (map['semester'] == null && map['semester_id'] == null) {
          map['semester'] = semester;
        }
        return map;
      }).toList();
    }),
  );

  final responses = await Future.wait(requests);
  final result = <dynamic>[];
  final seen = <String>{};
  for (final response in responses) {
    for (final course in response) {
      if (course is! Map) continue;
      final map = Map<String, dynamic>.from(course);
      final semester =
          (map['semester'] ??
                  map['semester_id'] ??
                  map['semesterId'] ??
                  'default')
              .toString();
      final stableId = (map['uuid'] ?? map['id'])?.toString();
      final identity = stableId == null || stableId.isEmpty
          ? <Object?>[
              semester,
              map['course_name'] ?? map['courseName'],
              map['room_name'] ?? map['roomName'],
              map['teacher_name'] ?? map['teacherName'],
              map['start_time'] ?? map['startTime'],
              map['end_time'] ?? map['endTime'],
              map['weekday'],
              map['week_index'] ?? map['weekIndex'],
              map['date'],
            ].join('|')
          : '$semester|$stableId';
      if (seen.add(identity)) result.add(map);
    }
  }
  return result;
}

List<String> _apiSyncSemesterIdsFromSettings(Map<String, dynamic>? settings) {
  final rawSemesters = settings?['semesters'];
  if (rawSemesters is! List) return const [];
  return rawSemesters
      .whereType<Map>()
      .map((semester) => semester['id']?.toString() ?? '')
      .where((id) => id.trim().isNotEmpty)
      .toList();
}

Future<List<dynamic>> _apiSyncFetchAllCourses(int userId) async {
  final settings = await ApiService.fetchUserSettings();
  return ApiService.fetchCoursesForSemesters(
    userId,
    ApiService.semesterIdsFromSettings(settings),
  );
}

Future<bool> _apiSyncSupportsAtomicCourseUpload() async {
  try {
    final response = await ApiService._request(
      'GET',
      '/api/capabilities',
      timeout: const Duration(seconds: 5),
    );
    if (response.statusCode != 200) return false;
    final data = jsonDecode(response.body);
    return data is Map &&
        (data['capabilities'] is Map) &&
        (data['capabilities']['atomic_course_upload'] == true);
  } catch (_) {
    return false;
  }
}

Future<Map<String, dynamic>> _apiSyncUploadCourses({
  required int userId,
  required List<Map<String, dynamic>> courses,
  String semester = "default",
  bool replaceAll = false,
  bool atomicAllSemesters = false,
}) async {
  try {
    final response = await ApiService._request(
      'POST',
      '/api/courses',
      body: {
        'user_id': userId,
        'semester': semester,
        'replace_all': replaceAll,
        if (atomicAllSemesters) 'atomic_all_semesters': true,
        'courses': courses,
      },
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200 && data['success'] == true) {
      return {'success': true, 'message': data['message'] ?? '课表同步成功'};
    } else if (response.statusCode == 429) {
      return {
        'success': false,
        'message': data['error'] ?? '今日同步次数已达上限',
        'isLimitExceeded': true,
      };
    } else {
      return {'success': false, 'message': data['error'] ?? '课表同步失败'};
    }
  } catch (e) {
    return {'success': false, 'message': '网络异常: $e'};
  }
}

Future<bool> _apiSyncUploadUserSettings({
  required int? semesterStartMs,
  required int? semesterEndMs,
  List<Map<String, dynamic>>? semesters, // 新增：多学期列表
}) async {
  try {
    final body = <String, dynamic>{
      'semester_start': semesterStartMs,
      'semester_end': semesterEndMs,
    };
    if (semesters != null) {
      body['semesters'] = semesters;
    }
    final response = await ApiService._request(
      'POST',
      '/api/settings',
      body: body,
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['success'] == true;
    }
    return false;
  } catch (e) {
    return false;
  }
}

Future<Map<String, dynamic>?> _apiSyncFetchUserSettings() async {
  try {
    final response = await ApiService._request('GET', '/api/settings');
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    return null;
  } catch (e) {
    return null;
  }
}

Future<Map<String, dynamic>?> _apiSyncFetchUserStatus(int userId) async {
  try {
    final response = await ApiService._request(
      'GET',
      '/api/user/status?user_id=$userId',
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    return null;
  } catch (_) {
    return null;
  }
}

Future<List<dynamic>> _apiSyncFetchPomodoroTags([int? userId]) async {
  try {
    final String urlPostfix = userId != null ? '?user_id=$userId' : '';
    final response = await ApiService._request(
      'GET',
      '/api/pomodoro/tags$urlPostfix',
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    return [];
  } catch (e) {
    return [];
  }
}

Future<List<dynamic>> _apiSyncFetchTodos(int userId) async {
  try {
    final response = await ApiService._request(
      'GET',
      '/api/todos?user_id=$userId',
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    return [];
  } catch (e) {
    return [];
  }
}

Future<List<dynamic>> _apiSyncFetchCountdowns(int userId) async {
  try {
    final response = await ApiService._request(
      'GET',
      '/api/countdowns?user_id=$userId',
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    return [];
  } catch (e) {
    return [];
  }
}

Future<List<dynamic>> _apiSyncFetchTimeLogs(int userId) async {
  try {
    final response = await ApiService._request(
      'GET',
      '/api/time_logs?user_id=$userId',
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    return [];
  } catch (e) {
    return [];
  }
}

Future<bool> _apiSyncSyncPomodoroTags(List<Map<String, dynamic>> tags) async {
  try {
    final response = await ApiService._request(
      'POST',
      '/api/pomodoro/tags',
      body: {'tags': tags},
    );
    if (response.statusCode != 200) return false;
    final data = jsonDecode(response.body);
    final conflicts = data is Map ? data['conflicts'] : null;
    return conflicts is! List || conflicts.isEmpty;
  } catch (e) {
    return false;
  }
}

Future<bool> _apiSyncUploadPomodoroRecord(Map<String, dynamic> record) async {
  try {
    final response = await ApiService._request(
      'POST',
      '/api/pomodoro/records',
      body: {'record': record},
    );
    if (response.statusCode != 200) return false;
    final data = jsonDecode(response.body);
    final conflicts = data is Map ? data['conflicts'] : null;
    return conflicts is! List || conflicts.isEmpty;
  } catch (e) {
    return false;
  }
}

Future<Map<String, dynamic>> _apiSyncMigrationRegister({
  required String email,
  required String username,
  required String password,
  String tier = 'free',
  int? semesterStart,
  int? semesterEnd,
}) async {
  final response = await ApiService._request(
    'POST',
    '/api/migrate_register',
    body: {
      'email': email,
      'username': username,
      'password': password,
      'tier': tier,
      'semester_start': semesterStart,
      'semester_end': semesterEnd,
    },
    includeAuth: false,
  );
  return jsonDecode(response.body);
}

Future<bool> _apiSyncUploadPomodoroRecords(
  List<Map<String, dynamic>> records, {
  http.Client? client,
}) async {
  try {
    final response = await ApiService._request(
      'POST',
      '/api/pomodoro/records',
      body: {'records': records},
      client: client,
    );
    if (response.statusCode != 200) return false;
    final data = jsonDecode(response.body);
    final conflicts = data is Map ? data['conflicts'] : null;
    return conflicts is! List || conflicts.isEmpty;
  } catch (e) {
    return false;
  }
}

Future<List<dynamic>> _apiSyncFetchPomodoroRecords([
  int? userId,
  int? fromMs,
  int? toMs,
  bool includeDeleted = false,
  bool useUpdatedAt = false,
  http.Client? client,
]) async {
  try {
    final params = <String, String>{};
    if (userId != null) params['user_id'] = userId.toString();
    if (fromMs != null) params['from'] = fromMs.toString();
    if (toMs != null) params['to'] = toMs.toString();
    if (includeDeleted) params['include_deleted'] = '1';
    if (useUpdatedAt && fromMs != null) {
      params['updated_since'] = fromMs.toString();
    }
    final uri = Uri.parse(
      '${ApiService._effectiveBaseUrl}/api/pomodoro/records',
    ).replace(queryParameters: params.isEmpty ? null : params);
    final response = await ApiService._request(
      'GET',
      uri.toString(),
      client: client,
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    return [];
  } catch (e) {
    return [];
  }
}

Future<bool> _apiSyncSyncPomodoroSettings(Map<String, dynamic> settings) async {
  try {
    final response = await ApiService._request(
      'POST',
      '/api/pomodoro/settings',
      body: settings,
    );
    return response.statusCode == 200;
  } catch (e) {
    return false;
  }
}

Future<Map<String, dynamic>?> _apiSyncFetchPomodoroSettings() async {
  try {
    final response = await ApiService._request('GET', '/api/pomodoro/settings');
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(response.body));
    }
    return null;
  } catch (e) {
    return null;
  }
}

Future<Map<String, dynamic>?> _apiSyncFetchActivePomodoroFromOtherDevice(
  String currentDeviceId,
) async {
  try {
    final uri = Uri.parse('${ApiService._effectiveBaseUrl}/api/pomodoro/active')
        .replace(queryParameters: {'device_id': currentDeviceId});
    final response = await ApiService._request('GET', uri.toString());
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['active'] == true) {
        return data['record'] as Map<String, dynamic>?;
      }
    }
    return null;
  } catch (_) {
    return null;
  }
}

Future<Map<String, dynamic>?> _apiSyncFetchOnlineStats() async {
  try {
    final response = await ApiService._request(
      'GET',
      '/api/online_stats',
      timeout: const Duration(seconds: 5),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    return null;
  } catch (e) {
    return null;
  }
}

Future<Map<String, dynamic>?> _apiSyncFetchDeviceVersionStats() async {
  try {
    final response = await ApiService._request(
      'GET',
      '/api/device_version_stats',
      timeout: const Duration(seconds: 5),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    return null;
  } catch (e) {
    return null;
  }
}

Future<Map<String, dynamic>?> _apiSyncFetchPomodoroCommunityStats({
  required int fromMs,
  required int toMs,
}) async {
  try {
    final uri =
        Uri.parse(
          '${ApiService._effectiveBaseUrl}/api/pomodoro/community_stats',
        ).replace(
          queryParameters: {'from': fromMs.toString(), 'to': toMs.toString()},
        );
    final response = await ApiService._request(
      'GET',
      uri.toString(),
      timeout: const Duration(seconds: 5),
      includeAuth: false,
    );
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic> && decoded['success'] == true) {
        final data = decoded['data'];
        if (data is Map<String, dynamic>) {
          return data;
        }
      }
    }
    return null;
  } catch (_) {
    return null;
  }
}

Future<bool> _apiSyncUploadPomodoroSessions(
  List<Map<String, dynamic>> sessions,
) => ApiService.uploadPomodoroRecords(sessions);

Future<List<dynamic>> _apiSyncFetchPomodoroSessions({
  int? fromMs,
  int? toMs,
  bool includeDeleted = false,
  bool useUpdatedAt = false,
  http.Client? client,
}) => ApiService.fetchPomodoroRecords(
  null,
  fromMs,
  toMs,
  includeDeleted,
  useUpdatedAt,
  client,
);
