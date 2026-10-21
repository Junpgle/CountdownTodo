import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../storage_service.dart';
import 'conflict_visibility_service.dart';
import 'database_helper.dart';
import 'storage/app_settings_storage.dart';
import 'storage/user_session_storage.dart';

enum SyncHealthModule {
  todos,
  countdowns,
  pomodoro,
  timeLogs,
  planBlocks,
  fixedSchedules,
  habits,
  finance,
  screenTime,
  courses,
  other,
}

extension SyncHealthModulePresentation on SyncHealthModule {
  String get label => switch (this) {
    SyncHealthModule.todos => '待办与清单',
    SyncHealthModule.countdowns => '倒计时',
    SyncHealthModule.pomodoro => '专注记录',
    SyncHealthModule.timeLogs => '时间日志',
    SyncHealthModule.planBlocks => '规划',
    SyncHealthModule.fixedSchedules => '固定日程',
    SyncHealthModule.habits => '习惯',
    SyncHealthModule.finance => '记账',
    SyncHealthModule.screenTime => '屏幕时间',
    SyncHealthModule.courses => '课表',
    SyncHealthModule.other => '其他同步项目',
  };

  String get description => switch (this) {
    SyncHealthModule.todos => '待办、清单和文件夹',
    SyncHealthModule.countdowns => '倒数日和纪念日',
    SyncHealthModule.pomodoro => '专注记录与标签',
    SyncHealthModule.timeLogs => '手动记录的时间明细',
    SyncHealthModule.planBlocks => '日程规划块',
    SyncHealthModule.fixedSchedules => '固定日程与外部日历',
    SyncHealthModule.habits => '目标、规则和打卡',
    SyncHealthModule.finance => '账单、分类、预算和贷款',
    SyncHealthModule.screenTime => '设备应用使用时间',
    SyncHealthModule.courses => '课程删除记录需从课表设置检查',
    SyncHealthModule.other => '此类数据由对应功能单独处理',
  };

  bool get usesGenericSync => switch (this) {
    SyncHealthModule.todos ||
    SyncHealthModule.countdowns ||
    SyncHealthModule.pomodoro ||
    SyncHealthModule.timeLogs ||
    SyncHealthModule.planBlocks ||
    SyncHealthModule.fixedSchedules ||
    SyncHealthModule.habits ||
    SyncHealthModule.finance => true,
    SyncHealthModule.screenTime ||
    SyncHealthModule.courses ||
    SyncHealthModule.other => false,
  };
}

class SyncHealthOperation {
  const SyncHealthOperation({
    required this.targetTable,
    required this.operationType,
    required this.timestamp,
    required this.error,
    required this.isVersionConflict,
  });

  final String targetTable;
  final String operationType;
  final int timestamp;
  final String error;
  final bool isVersionConflict;

  bool get hasError => error.isNotEmpty && !isVersionConflict;

  bool get isWaiting => error.isEmpty && !isVersionConflict;
}

class SyncHealthModuleStatus {
  SyncHealthModuleStatus({
    required this.module,
    required List<SyncHealthOperation> operations,
    required this.conflictCount,
    this.localPendingCount = 0,
    this.cloudSyncEnabled = true,
  }) : operations = List.unmodifiable(operations);

  final SyncHealthModule module;
  final List<SyncHealthOperation> operations;
  final int conflictCount;
  final int localPendingCount;
  final bool cloudSyncEnabled;

  int get queuedOperationCount => operations.length;

  int get pendingCount => queuedOperationCount + localPendingCount;

  int get failedCount => operations.where((item) => item.hasError).length;

  int get waitingCount => operations.where((item) => item.isWaiting).length;

  int get retryableCount {
    if (module == SyncHealthModule.courses ||
        module == SyncHealthModule.other ||
        (module == SyncHealthModule.finance && !cloudSyncEnabled)) {
      return 0;
    }
    final retryableOperations = operations
        .where((item) => !item.isVersionConflict)
        .length;
    if (module == SyncHealthModule.finance ||
        module == SyncHealthModule.screenTime) {
      return retryableOperations + localPendingCount;
    }
    return retryableOperations;
  }

  bool get canRetry => retryableCount > 0;

  bool get needsAttention => pendingCount > 0 || conflictCount > 0;
}

class SyncHealthSnapshot {
  SyncHealthSnapshot({
    required this.username,
    required List<SyncHealthModuleStatus> modules,
    required this.lastSuccessfulRequestAt,
    required this.lastScreenTimeSyncAt,
  }) : modules = List.unmodifiable(modules);

  final String username;
  final List<SyncHealthModuleStatus> modules;
  final DateTime? lastSuccessfulRequestAt;
  final DateTime? lastScreenTimeSyncAt;

  int get totalPendingCount =>
      modules.fold(0, (total, module) => total + module.pendingCount);

  int get totalRetryableCount =>
      modules.fold(0, (total, module) => total + module.retryableCount);

  int get totalConflictCount =>
      modules.fold(0, (total, module) => total + module.conflictCount);

  int get totalFailedCount =>
      modules.fold(0, (total, module) => total + module.failedCount);

  bool get hasAttention => modules.any((module) => module.needsAttention);

  SyncHealthModuleStatus statusFor(SyncHealthModule module) =>
      modules.firstWhere((status) => status.module == module);
}

class SyncHealthSyncSelection {
  const SyncHealthSyncSelection({
    required this.todos,
    required this.countdowns,
    required this.pomodoro,
    required this.timeLogs,
    required this.planBlocks,
    required this.fixedSchedules,
    required this.habits,
    required this.finance,
    required this.screenTime,
  });

  factory SyncHealthSyncSelection.fromModules(
    Iterable<SyncHealthModule> modules,
  ) {
    final selected = modules.toSet();
    return SyncHealthSyncSelection(
      todos: selected.contains(SyncHealthModule.todos),
      countdowns: selected.contains(SyncHealthModule.countdowns),
      pomodoro: selected.contains(SyncHealthModule.pomodoro),
      timeLogs: selected.contains(SyncHealthModule.timeLogs),
      planBlocks: selected.contains(SyncHealthModule.planBlocks),
      fixedSchedules: selected.contains(SyncHealthModule.fixedSchedules),
      habits: selected.contains(SyncHealthModule.habits),
      finance: selected.contains(SyncHealthModule.finance),
      screenTime: selected.contains(SyncHealthModule.screenTime),
    );
  }

  final bool todos;
  final bool countdowns;
  final bool pomodoro;
  final bool timeLogs;
  final bool planBlocks;
  final bool fixedSchedules;
  final bool habits;
  final bool finance;
  final bool screenTime;

  bool get hasAnyDomain =>
      todos ||
      countdowns ||
      pomodoro ||
      timeLogs ||
      planBlocks ||
      fixedSchedules ||
      habits ||
      finance ||
      screenTime;
}

class SyncHealthRetryResult {
  const SyncHealthRetryResult({
    required this.success,
    this.error,
    this.hasPartialFailure = false,
  });

  final bool success;
  final String? error;
  final bool hasPartialFailure;
}

class SyncHealthService {
  const SyncHealthService._();

  static const List<String> _financeTables = [
    'finance_categories',
    'finance_payment_methods',
    'finance_transactions',
    'finance_budgets',
    'finance_recurring_rules',
    'finance_entry_templates',
    'finance_loans',
    'finance_loan_installments',
  ];

  static const Map<String, SyncHealthModule> _tableModules = {
    'todos': SyncHealthModule.todos,
    'todo_groups': SyncHealthModule.todos,
    'countdowns': SyncHealthModule.countdowns,
    'pomodoro_records': SyncHealthModule.pomodoro,
    'pomodoro_tags': SyncHealthModule.pomodoro,
    'time_logs': SyncHealthModule.timeLogs,
    'todo_plan_blocks': SyncHealthModule.planBlocks,
    'fixed_schedules': SyncHealthModule.fixedSchedules,
    'habit_goals': SyncHealthModule.habits,
    'habit_goal_rule_revisions': SyncHealthModule.habits,
    'habit_checkins': SyncHealthModule.habits,
    'habit_sleep_coaching_plans': SyncHealthModule.habits,
    'courses': SyncHealthModule.courses,
  };

  static const Map<String, SyncHealthModule> _conflictTables = {
    'todos': SyncHealthModule.todos,
    'todo_groups': SyncHealthModule.todos,
    'countdowns': SyncHealthModule.countdowns,
    'pomodoro_records': SyncHealthModule.pomodoro,
    'pomodoro_tags': SyncHealthModule.pomodoro,
    'todo_plan_blocks': SyncHealthModule.planBlocks,
    'fixed_schedules': SyncHealthModule.fixedSchedules,
    'habit_goals': SyncHealthModule.habits,
    'habit_goal_rule_revisions': SyncHealthModule.habits,
  };

  static SyncHealthModule moduleForTable(String table) =>
      _tableModules[table] ?? SyncHealthModule.other;

  static Future<SyncHealthSnapshot> load(String username) async {
    final normalizedUsername = username.trim();
    final session = await UserSessionStorage.captureSession(normalizedUsername);
    if (session == null) throw StateError('账户已切换，请刷新同步状态');

    final db = await DatabaseHelper.instance.databaseForUser(session.username);
    final pendingRows = await db.query(
      'op_logs',
      where: 'is_synced = 0',
      orderBy: 'timestamp DESC, id DESC',
    );

    final operationsByModule = <SyncHealthModule, List<SyncHealthOperation>>{
      for (final module in SyncHealthModule.values) module: [],
    };
    final conflictKeysByModule = <SyncHealthModule, Set<String>>{
      for (final module in SyncHealthModule.values) module: <String>{},
    };

    for (final row in pendingRows) {
      final table = row['target_table']?.toString() ?? 'unknown';
      final module = moduleForTable(table);
      final error = row['sync_error']?.toString().trim() ?? '';
      final isVersionConflict = error == 'server_conflict';
      final uuid = row['target_uuid']?.toString().trim() ?? '';
      if (isVersionConflict && uuid.isNotEmpty) {
        conflictKeysByModule[module]!.add('$table:$uuid');
      }
      operationsByModule[module]!.add(
        SyncHealthOperation(
          targetTable: table,
          operationType: row['op_type']?.toString() ?? 'UPDATE',
          timestamp: (row['timestamp'] as num?)?.toInt() ?? 0,
          error: error,
          isVersionConflict: isVersionConflict,
        ),
      );
    }

    for (final entry in _conflictTables.entries) {
      final table = entry.key;
      final module = entry.value;
      if (!await _tableExists(db, table)) continue;
      final columns = await db.rawQuery('PRAGMA table_info($table)');
      final columnNames = columns
          .map((column) => column['name']?.toString())
          .whereType<String>()
          .toSet();
      if (!columnNames.contains('uuid') ||
          !columnNames.contains('has_conflict')) {
        continue;
      }
      final selectedColumns = <String>[
        'uuid',
        'has_conflict',
        if (columnNames.contains('is_deleted')) 'is_deleted',
        if (columnNames.contains('conflict_data')) 'conflict_data',
      ];
      final activeFilter = columnNames.contains('is_deleted')
          ? 'has_conflict = 1 AND COALESCE(is_deleted, 0) = 0'
          : 'has_conflict = 1';
      final rows = await db.query(
        table,
        columns: selectedColumns,
        where: activeFilter,
      );
      for (final row in rows) {
        final uuid = row['uuid']?.toString().trim() ?? '';
        if (uuid.isEmpty) continue;
        final conflictData = _decodeConflictData(row['conflict_data']);
        if (table == 'todos' &&
            ConflictVisibilityService.isLocalScheduleConflictData(
              conflictData,
            )) {
          continue;
        }
        conflictKeysByModule[module]!.add('$table:$uuid');
      }
    }

    final financeSyncEnabled =
        await AppSettingsStorage.isFinanceCloudSyncEnabled(session.username);
    var financePendingCount = 0;
    for (final table in _financeTables) {
      if (!await _tableExists(db, table)) continue;
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS count FROM $table WHERE pending_sync = 1',
      );
      financePendingCount += (rows.first['count'] as num?)?.toInt() ?? 0;
    }

    final screenTimePackage = await StorageService.getLocalScreenTimeMap(
      username: session.username,
    );
    final screenTimeApps = screenTimePackage['apps'];
    final screenTimePendingCount = screenTimeApps is List
        ? screenTimeApps.whereType<Map>().length
        : 0;
    final lastSuccessfulRequestAt = await StorageService.getLastAutoSyncTime(
      session.username,
    );
    final lastScreenTimeSyncAt = await StorageService.getLastScreenTimeSync();
    await UserSessionStorage.ensureCurrentSession(session);

    final modules = SyncHealthModule.values
        .map((module) {
          final localPendingCount = switch (module) {
            SyncHealthModule.finance => financePendingCount,
            SyncHealthModule.screenTime => screenTimePendingCount,
            _ => 0,
          };
          return SyncHealthModuleStatus(
            module: module,
            operations: operationsByModule[module]!,
            conflictCount: conflictKeysByModule[module]!.length,
            localPendingCount: localPendingCount,
            cloudSyncEnabled: module == SyncHealthModule.finance
                ? financeSyncEnabled
                : true,
          );
        })
        .toList(growable: false);

    return SyncHealthSnapshot(
      username: session.username,
      modules: modules,
      lastSuccessfulRequestAt: lastSuccessfulRequestAt,
      lastScreenTimeSyncAt: lastScreenTimeSyncAt,
    );
  }

  static Future<SyncHealthRetryResult> retryModules({
    required String username,
    required Iterable<SyncHealthModule> modules,
  }) async {
    final selection = SyncHealthSyncSelection.fromModules(modules);
    if (!selection.hasAnyDomain) {
      return const SyncHealthRetryResult(
        success: false,
        error: '所选项目需要在对应模块中处理',
      );
    }

    final session = await UserSessionStorage.captureSession(username);
    if (session == null) {
      return const SyncHealthRetryResult(
        success: false,
        error: '账户已切换，请刷新同步状态',
      );
    }

    final financeEnabled =
        selection.finance &&
        await AppSettingsStorage.isFinanceCloudSyncEnabled(session.username);
    if (selection.finance && !financeEnabled) {
      return const SyncHealthRetryResult(
        success: false,
        error: '记账云同步未开启，数据仍只保存在本机',
      );
    }

    try {
      final result = await StorageService.syncData(
        session.username,
        syncTodos: selection.todos,
        syncCountdowns: selection.countdowns,
        syncTimeLogs: selection.timeLogs,
        syncPomodoro: selection.pomodoro,
        syncPlanBlocks: selection.planBlocks,
        syncFixedSchedules: selection.fixedSchedules,
        syncHabits: selection.habits,
        syncFinance: financeEnabled,
        syncScreenTime: selection.screenTime,
        forceFullSync: false,
        financeSyncExplicitlyAuthorized: false,
      );
      await UserSessionStorage.ensureCurrentSession(session);
      if (result['success'] != true) {
        return SyncHealthRetryResult(
          success: false,
          error: result['error']?.toString() ?? '同步未执行，请稍后重试',
        );
      }
      await StorageService.updateLastAutoSyncTime(session.username);
      return const SyncHealthRetryResult(success: true);
    } catch (error) {
      return SyncHealthRetryResult(success: false, error: error.toString());
    }
  }

  static Future<bool> _tableExists(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
      [table],
    );
    return rows.isNotEmpty;
  }

  static Map<String, dynamic>? _decodeConflictData(Object? raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is! String || raw.trim().isEmpty || raw.trim() == 'null') {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {
      return null;
    }
    return null;
  }
}
