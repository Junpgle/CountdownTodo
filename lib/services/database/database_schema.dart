part of '../database_helper.dart';

Future<void> _ensureCourseTableSchema(Database db) async {
  try {
    final info = await db.rawQuery("PRAGMA table_info(courses)");
    if (info.isEmpty) return;

    final columnsToAdd = [
      {'name': 'is_deleted', 'type': 'INTEGER DEFAULT 0'},
      {'name': 'version', 'type': 'INTEGER DEFAULT 1'},
      {'name': 'updated_at', 'type': 'INTEGER DEFAULT 0'},
      {'name': 'created_at', 'type': 'INTEGER DEFAULT 0'},
      {'name': 'semester_id', 'type': "TEXT DEFAULT 'default'"},
    ];

    for (final column in columnsToAdd) {
      if (!info.any((row) => row['name'] == column['name'])) {
        await db.execute(
          "ALTER TABLE courses ADD COLUMN ${column['name']} ${column['type']};",
        );
        //           debugPrint("✅ Database: 修复字段 courses.${column['name']}");
      }
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_courses_date_start '
      'ON courses(date, start_time)',
    );
  } catch (e) {
    //       debugPrint("⚠️ Database: 检查/修复 courses 表结构失败: $e");
  }
}

Future<void> _ensureTodoClientLocalSchema(Database db) async {
  try {
    final info = await db.rawQuery("PRAGMA table_info(todos)");
    if (info.isEmpty) return;

    final columnsToAdd = [
      {'name': 'image_path', 'type': 'TEXT'},
      {'name': 'original_text', 'type': 'TEXT'},
      {'name': 'recurrence_series_id', 'type': 'TEXT'},
    ];

    for (final column in columnsToAdd) {
      if (!info.any((row) => row['name'] == column['name'])) {
        await db.execute(
          "ALTER TABLE todos ADD COLUMN ${column['name']} ${column['type']};",
        );
        //           debugPrint("✅ Database: 修复字段 todos.${column['name']}");
      }
    }
  } catch (e) {
    //       debugPrint("⚠️ Database: 检查/修复 todos 本地来源字段失败: $e");
  }
}

Future<void> _ensureTodoSkipStateSchema(Database db) async {
  final todoColumns = await db.rawQuery('PRAGMA table_info(todos)');
  if (todoColumns.isEmpty) return;
  final todoNames = todoColumns.map((row) => row['name']).toSet();
  if (!todoNames.contains('is_skipped')) {
    await db.execute(
      'ALTER TABLE todos ADD COLUMN is_skipped INTEGER NOT NULL DEFAULT 0',
    );
  }
  if (!todoNames.contains('is_skipped_sync_pending')) {
    await db.execute(
      'ALTER TABLE todos ADD COLUMN is_skipped_sync_pending INTEGER NOT NULL DEFAULT 0',
    );
  }

  await db.execute('''
    CREATE TABLE IF NOT EXISTS todo_completions (
      todo_uuid TEXT,
      user_id INTEGER,
      is_completed INTEGER,
      is_skipped INTEGER NOT NULL DEFAULT 0,
      is_skipped_sync_pending INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER,
      PRIMARY KEY(todo_uuid, user_id)
    )
  ''');
  final completionColumns = await db.rawQuery(
    'PRAGMA table_info(todo_completions)',
  );
  final completionNames = completionColumns.map((row) => row['name']).toSet();
  if (!completionNames.contains('is_skipped')) {
    await db.execute(
      'ALTER TABLE todo_completions ADD COLUMN is_skipped INTEGER NOT NULL DEFAULT 0',
    );
  }
  if (!completionNames.contains('is_skipped_sync_pending')) {
    await db.execute(
      'ALTER TABLE todo_completions ADD COLUMN is_skipped_sync_pending INTEGER NOT NULL DEFAULT 0',
    );
  }
}

Future<void> _ensureTodoCompletionTimestampSchema(Database db) async {
  final todoColumns = await db.rawQuery('PRAGMA table_info(todos)');
  if (todoColumns.isEmpty) return;
  final todoNames = todoColumns.map((row) => row['name']).toSet();
  if (!todoNames.contains('completed_at')) {
    await db.execute('ALTER TABLE todos ADD COLUMN completed_at INTEGER');
  }
  await db.execute('''
    UPDATE todos
    SET completed_at = CASE
      WHEN recurrence_series_id IS NOT NULL AND TRIM(recurrence_series_id) != ''
        THEN COALESCE(created_date, due_date, created_at, updated_at)
      ELSE updated_at
    END
    WHERE is_completed = 1 AND completed_at IS NULL
  ''');
}

Future<void> _ensureTodoPlanBlockSchema(Database db) async {
  try {
    // 检查表是否存在
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='todo_plan_blocks'",
    );
    if (tables.isEmpty) return;

    final info = await db.rawQuery("PRAGMA table_info(todo_plan_blocks)");
    final existingColumns = info.map((row) => row['name'] as String).toSet();

    // 直接逐列尝试添加，已存在则忽略
    final columnsToAdd = [
      {'name': 'pomodoro_minutes', 'type': 'INTEGER DEFAULT 25'},
      {'name': 'pomodoro_rounds', 'type': 'INTEGER DEFAULT 0'},
      {'name': 'calendar_event_id', 'type': 'TEXT'},
    ];

    for (final column in columnsToAdd) {
      if (!existingColumns.contains(column['name'])) {
        try {
          await db.execute(
            "ALTER TABLE todo_plan_blocks ADD COLUMN ${column['name']} ${column['type']};",
          );
          //             debugPrint("✅ Database: 修复字段 todo_plan_blocks.${column['name']}");
        } catch (e) {
          //             debugPrint(
          //                 "⚠️ Database: 添加 todo_plan_blocks.${column['name']} 失败: $e");
        }
      }
    }
  } catch (e) {
    //       debugPrint("⚠️ Database: 检查/修复 todo_plan_blocks 表结构失败: $e");
  }
}

Future<void> _ensureFixedScheduleSchema(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS fixed_schedules (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      title TEXT NOT NULL,
      date TEXT NOT NULL,
      start_time INTEGER,
      end_time INTEGER,
      status INTEGER NOT NULL DEFAULT 0,
      source INTEGER NOT NULL DEFAULT 0,
      location TEXT,
      remark TEXT,
      reminder_minutes TEXT,
      timezone TEXT,
      recurrence INTEGER NOT NULL DEFAULT 0,
      custom_interval_days INTEGER,
      recurrence_series_id TEXT,
      related_todo_ids TEXT,
      external_source TEXT,
      external_id TEXT,
      team_uuid TEXT,
      owner_user_id INTEGER,
      device_id TEXT,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      version INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');
  final columns = await db.rawQuery('PRAGMA table_info(fixed_schedules)');
  if (!columns.any((row) => row['name'] == 'custom_interval_days')) {
    await db.execute(
      'ALTER TABLE fixed_schedules ADD COLUMN custom_interval_days INTEGER',
    );
  }
  if (!columns.any((row) => row['name'] == 'owner_user_id')) {
    await db.execute(
      'ALTER TABLE fixed_schedules ADD COLUMN owner_user_id INTEGER',
    );
  }
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_fixed_schedules_date '
    'ON fixed_schedules(is_deleted, date, start_time)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_fixed_schedules_external '
    'ON fixed_schedules(external_source, external_id)',
  );
}

/// 习惯追踪表结构（V36）。
///
/// 幂等创建，可在升级、新建和每次打开时安全调用。
Future<void> _ensureHabitSchema(Database db) async {
  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS habit_goals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        icon TEXT,
        source_type INTEGER NOT NULL DEFAULT 2,
        source_ids TEXT,
        current_rule_uuid TEXT,
        display_mode INTEGER NOT NULL DEFAULT 0,
        default_focus_minutes INTEGER,
        sort_order INTEGER NOT NULL DEFAULT 0,
        is_archived INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        version INTEGER NOT NULL DEFAULT 1,
        device_id TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        has_conflict INTEGER DEFAULT 0,
        conflict_data TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS habit_goal_rule_revisions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        habit_uuid TEXT NOT NULL,
        effective_from_date TEXT,
        effective_to_date TEXT,
        period_type INTEGER NOT NULL DEFAULT 0,
        weekdays_mask INTEGER NOT NULL DEFAULT 127,
        custom_interval_days INTEGER,
        target_value REAL NOT NULL DEFAULT 0,
        unit TEXT,
        target_time_minute INTEGER,
        time_comparison INTEGER NOT NULL DEFAULT 0,
        time_tolerance_minutes INTEGER NOT NULL DEFAULT 0,
        day_boundary_minute INTEGER NOT NULL DEFAULT 0,
        quick_values_json TEXT,
        reminder_policy_json TEXT,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        version INTEGER NOT NULL DEFAULT 1,
        device_id TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        has_conflict INTEGER DEFAULT 0,
        conflict_data TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS habit_checkins (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        habit_uuid TEXT NOT NULL,
        rule_revision_uuid TEXT,
        occurred_at INTEGER NOT NULL,
        logical_date TEXT NOT NULL,
        timezone_offset_minutes INTEGER NOT NULL DEFAULT 0,
        value REAL NOT NULL DEFAULT 0,
        note TEXT,
        source TEXT NOT NULL DEFAULT 'manual',
        dedupe_key TEXT,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        version INTEGER NOT NULL DEFAULT 1,
        device_id TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS habit_sleep_coaching_plans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        kind TEXT NOT NULL DEFAULT 'sleep_routine',
        enabled INTEGER NOT NULL DEFAULT 0,
        paused INTEGER NOT NULL DEFAULT 0,
        step_minutes INTEGER NOT NULL DEFAULT 15,
        stage_days INTEGER NOT NULL DEFAULT 4,
        started_logical_date TEXT,
        baseline_bedtime_minute INTEGER,
        baseline_wake_minute INTEGER,
        baseline_sleep_minutes INTEGER,
        paused_stage_index INTEGER,
        paused_progress_days INTEGER,
        paused_logical_date TEXT,
        timezone_offset_minutes INTEGER,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        version INTEGER NOT NULL DEFAULT 1,
        device_id TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS habit_drink_options (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        icon TEXT NOT NULL DEFAULT '🥤',
        label TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        version INTEGER NOT NULL DEFAULT 1,
        device_id TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_habit_goals_active '
      'ON habit_goals(is_deleted, is_archived, sort_order)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_habit_rules_effective '
      'ON habit_goal_rule_revisions(habit_uuid, effective_from_date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_habit_checkins_day '
      'ON habit_checkins(habit_uuid, logical_date, is_deleted)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_habit_checkins_updated '
      'ON habit_checkins(updated_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_habit_sleep_coaching_plans_updated '
      'ON habit_sleep_coaching_plans(updated_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_habit_drink_options_updated '
      'ON habit_drink_options(updated_at)',
    );

    // V42：旧版本允许同一导入日志产生多个相同 dedupe_key。先保留
    // updated_at/version 最新的一条，再创建唯一索引；否则已有重复数据
    // 会让数据库升级直接失败。
    final duplicateDedupeKeys = await db.rawQuery('''
      SELECT dedupe_key
      FROM habit_checkins
      WHERE dedupe_key IS NOT NULL
      GROUP BY dedupe_key
      HAVING COUNT(*) > 1
    ''');
    for (final duplicate in duplicateDedupeKeys) {
      final dedupeKey = duplicate['dedupe_key']?.toString();
      if (dedupeKey == null || dedupeKey.isEmpty) continue;
      final rows = await db.query(
        'habit_checkins',
        columns: ['uuid'],
        where: 'dedupe_key = ?',
        whereArgs: [dedupeKey],
        orderBy: 'updated_at DESC, version DESC, uuid DESC',
      );
      for (final row in rows.skip(1)) {
        final uuid = row['uuid']?.toString();
        if (uuid == null || uuid.isEmpty) continue;
        await db.delete('habit_checkins', where: 'uuid = ?', whereArgs: [uuid]);
      }
    }
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_habit_checkins_dedupe '
      'ON habit_checkins(dedupe_key) WHERE dedupe_key IS NOT NULL',
    );
    // V37：为已存在的库补充 default_focus_minutes 列（幂等）。
    try {
      final goalInfo = await db.rawQuery('PRAGMA table_info(habit_goals)');
      if (!goalInfo.any((row) => row['name'] == 'default_focus_minutes')) {
        await db.execute(
          'ALTER TABLE habit_goals ADD COLUMN default_focus_minutes INTEGER',
        );
      }
    } catch (e) {
      // 忽略：新建库时该列已存在。
    }
    // V41：为已存在的睡眠训练计划补充逻辑时区字段（幂等）。
    try {
      final planInfo = await db.rawQuery(
        'PRAGMA table_info(habit_sleep_coaching_plans)',
      );
      if (!planInfo.any((row) => row['name'] == 'timezone_offset_minutes')) {
        await db.execute(
          'ALTER TABLE habit_sleep_coaching_plans '
          'ADD COLUMN timezone_offset_minutes INTEGER',
        );
      }
    } catch (e) {
      // 忽略：新建库时该列已存在。
    }
    // V43：为已存在的睡眠训练计划补充暂停检查点字段（幂等）。
    try {
      final planInfo = await db.rawQuery(
        'PRAGMA table_info(habit_sleep_coaching_plans)',
      );
      final planColumns = planInfo.map((row) => row['name']).toSet();
      if (!planColumns.contains('paused_stage_index')) {
        await db.execute(
          'ALTER TABLE habit_sleep_coaching_plans '
          'ADD COLUMN paused_stage_index INTEGER',
        );
      }
      if (!planColumns.contains('paused_progress_days')) {
        await db.execute(
          'ALTER TABLE habit_sleep_coaching_plans '
          'ADD COLUMN paused_progress_days INTEGER',
        );
      }
      if (!planColumns.contains('paused_logical_date')) {
        await db.execute(
          'ALTER TABLE habit_sleep_coaching_plans '
          'ADD COLUMN paused_logical_date TEXT',
        );
      }
    } catch (e) {
      // 忽略：新建库时这些列已存在。
    }
    // V38：为规则表补充同步字段 device_id / has_conflict / conflict_data（幂等）。
    try {
      final ruleInfo = await db.rawQuery(
        'PRAGMA table_info(habit_goal_rule_revisions)',
      );
      final ruleCols = ruleInfo.map((row) => row['name']).toSet();
      if (!ruleCols.contains('device_id')) {
        await db.execute(
          'ALTER TABLE habit_goal_rule_revisions ADD COLUMN device_id TEXT',
        );
      }
      if (!ruleCols.contains('has_conflict')) {
        await db.execute(
          'ALTER TABLE habit_goal_rule_revisions ADD COLUMN has_conflict INTEGER DEFAULT 0',
        );
      }
      if (!ruleCols.contains('conflict_data')) {
        await db.execute(
          'ALTER TABLE habit_goal_rule_revisions ADD COLUMN conflict_data TEXT',
        );
      }
    } catch (e) {
      // 忽略：新建库时这些列已存在。
    }
  } catch (e) {
    //       debugPrint('⚠️ Database: 检查/修复 habit 表结构失败: $e');
  }
}

Future<void> _ensureSuggestionFeedbackSchema(Database db) async {
  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS suggestion_feedback (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        keyword TEXT NOT NULL,
        suggestion_type TEXT NOT NULL,
        suggested_value TEXT NOT NULL,
        accepted INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_suggestion_feedback_lookup '
      'ON suggestion_feedback(keyword, suggestion_type, suggested_value)',
    );
  } catch (e) {
    //       debugPrint('⚠️ Database: 检查/修复 suggestion_feedback 表失败: $e');
  }
}

/// 本地私密日记表结构。日记不写入 op_logs，也不参与云端同步。
Future<void> _ensurePlanEditorDraftSchema(Database db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS local_plan_editor_drafts (
    uuid TEXT PRIMARY KEY,
    member_id INTEGER NOT NULL,
    target_uuid TEXT NOT NULL,
    revision INTEGER NOT NULL,
    format_version INTEGER NOT NULL,
    todo_uuid TEXT NOT NULL,
    title TEXT NOT NULL,
    start_time INTEGER NOT NULL,
    end_time INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    form_json TEXT NOT NULL
  )''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_local_plan_drafts_member '
    'ON local_plan_editor_drafts(member_id, updated_at DESC, uuid)',
  );
}

Future<void> _ensureJournalSchema(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS journal_entries (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      title TEXT,
      content TEXT NOT NULL DEFAULT '',
      occurred_at INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      is_deleted INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS journal_attachments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      entry_uuid TEXT NOT NULL,
      local_path TEXT,
      image_data BLOB,
      mime_type TEXT NOT NULL DEFAULT 'image/jpeg',
      width INTEGER,
      height INTEGER,
      sort_order INTEGER NOT NULL DEFAULT 0,
      file_size INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      FOREIGN KEY(entry_uuid) REFERENCES journal_entries(uuid) ON DELETE CASCADE
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_journal_entries_date '
    'ON journal_entries(is_deleted, occurred_at DESC, created_at DESC)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_journal_attachments_entry '
    'ON journal_attachments(entry_uuid, sort_order)',
  );
}

/// 轻量个人记账表结构、预算、自动化和同步状态表（V45-V51）。
///
/// 记账数据默认只保存在当前用户自己的数据库中。金额使用整数分存储，
/// 分类和付款方式只做归档，不物理删除，以保证历史账单仍可正确展示。
Future<void> _ensureFinanceSchema(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS finance_categories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      type TEXT NOT NULL DEFAULT 'expense',
      icon TEXT NOT NULL DEFAULT '📦',
      icon_customized INTEGER NOT NULL DEFAULT 0,
      name_customized INTEGER NOT NULL DEFAULT 0,
      color_value INTEGER,
      parent_uuid TEXT,
      is_system INTEGER NOT NULL DEFAULT 0,
      is_archived INTEGER NOT NULL DEFAULT 0,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      sort_order INTEGER NOT NULL DEFAULT 0,
      version INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      pending_sync INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS finance_payment_methods (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      icon TEXT NOT NULL DEFAULT '💼',
      color_value INTEGER,
      is_system INTEGER NOT NULL DEFAULT 0,
      is_archived INTEGER NOT NULL DEFAULT 0,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      sort_order INTEGER NOT NULL DEFAULT 0,
      version INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      pending_sync INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS finance_transactions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      type TEXT NOT NULL DEFAULT 'expense',
      amount_minor INTEGER NOT NULL DEFAULT 0,
      currency_code TEXT NOT NULL DEFAULT 'CNY',
      category_uuid TEXT,
      payment_method_uuid TEXT,
      target_payment_method_uuid TEXT,
      transaction_date TEXT NOT NULL,
      occurred_at INTEGER,
      timezone_offset_minutes INTEGER NOT NULL DEFAULT 0,
      merchant TEXT,
      note TEXT,
      source TEXT NOT NULL DEFAULT 'manual',
      related_todo_uuid TEXT,
      related_plan_block_uuid TEXT,
      related_transaction_uuid TEXT,
      installment_group_uuid TEXT,
      installment_index INTEGER,
      installment_count INTEGER,
      installment_total_minor INTEGER,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      version INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      device_id TEXT,
      pending_sync INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS finance_budgets (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      month_key TEXT NOT NULL,
      category_uuid TEXT,
      payment_method_uuid TEXT,
      amount_minor INTEGER NOT NULL DEFAULT 0,
      currency_code TEXT NOT NULL DEFAULT 'CNY',
      note TEXT,
      balance_snapshot_at INTEGER,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      version INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      device_id TEXT,
      pending_sync INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS finance_recurring_rules (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      type TEXT NOT NULL DEFAULT 'expense',
      amount_minor INTEGER NOT NULL DEFAULT 0,
      currency_code TEXT NOT NULL DEFAULT 'CNY',
      category_uuid TEXT,
      payment_method_uuid TEXT,
      merchant TEXT,
      note TEXT,
      frequency TEXT NOT NULL DEFAULT 'monthly',
      day_of_month INTEGER NOT NULL DEFAULT 1,
      month_of_year INTEGER NOT NULL DEFAULT 1,
      start_date TEXT NOT NULL,
      end_date TEXT,
      reminder_minutes INTEGER NOT NULL DEFAULT 1440,
      auto_generate INTEGER NOT NULL DEFAULT 1,
      is_enabled INTEGER NOT NULL DEFAULT 1,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      last_generated_period TEXT,
      version INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      device_id TEXT,
      pending_sync INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS finance_entry_templates (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      type TEXT NOT NULL DEFAULT 'expense',
      amount_minor INTEGER NOT NULL DEFAULT 0,
      currency_code TEXT NOT NULL DEFAULT 'CNY',
      category_uuid TEXT,
      payment_method_uuid TEXT,
      merchant TEXT,
      note TEXT,
      use_count INTEGER NOT NULL DEFAULT 0,
      last_used_at INTEGER,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      version INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      device_id TEXT,
      pending_sync INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS finance_loans (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      lender TEXT,
      principal_minor INTEGER NOT NULL DEFAULT 0,
      currency_code TEXT NOT NULL DEFAULT 'CNY',
      annual_interest_rate_bps INTEGER NOT NULL DEFAULT 0,
      term_months INTEGER NOT NULL DEFAULT 1,
      start_date TEXT NOT NULL,
      repayment_day INTEGER NOT NULL DEFAULT 1,
      repayment_method TEXT NOT NULL DEFAULT 'equalPrincipalInterest',
      note TEXT,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      version INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      device_id TEXT,
      pending_sync INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS finance_loan_installments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      loan_uuid TEXT NOT NULL,
      installment_index INTEGER NOT NULL DEFAULT 1,
      due_date TEXT NOT NULL,
      payment_minor INTEGER NOT NULL DEFAULT 0,
      principal_minor INTEGER NOT NULL DEFAULT 0,
      interest_minor INTEGER NOT NULL DEFAULT 0,
      remaining_principal_minor INTEGER NOT NULL DEFAULT 0,
      is_paid INTEGER NOT NULL DEFAULT 0,
      paid_at INTEGER,
      payment_method_uuid TEXT,
      interest_transaction_uuid TEXT,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      version INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      device_id TEXT,
      pending_sync INTEGER NOT NULL DEFAULT 0
    )
  ''');

  const financeTables = [
    'finance_categories',
    'finance_payment_methods',
    'finance_transactions',
    'finance_budgets',
    'finance_recurring_rules',
    'finance_entry_templates',
    'finance_loans',
    'finance_loan_installments',
  ];
  final categoryColumns = await db.rawQuery(
    'PRAGMA table_info(finance_categories)',
  );
  if (!categoryColumns.any((row) => row['name'] == 'icon_customized')) {
    await db.execute(
      'ALTER TABLE finance_categories '
      'ADD COLUMN icon_customized INTEGER NOT NULL DEFAULT 0',
    );
  }
  if (!categoryColumns.any((row) => row['name'] == 'name_customized')) {
    await db.execute(
      'ALTER TABLE finance_categories '
      'ADD COLUMN name_customized INTEGER NOT NULL DEFAULT 0',
    );
  }
  final budgetColumns = await db.rawQuery('PRAGMA table_info(finance_budgets)');
  if (!budgetColumns.any((row) => row['name'] == 'payment_method_uuid')) {
    await db.execute(
      'ALTER TABLE finance_budgets ADD COLUMN payment_method_uuid TEXT',
    );
  }
  if (!budgetColumns.any((row) => row['name'] == 'balance_snapshot_at')) {
    await db.execute(
      'ALTER TABLE finance_budgets ADD COLUMN balance_snapshot_at INTEGER',
    );
    await db.execute(
      'UPDATE finance_budgets SET balance_snapshot_at = updated_at '
      'WHERE payment_method_uuid IS NOT NULL',
    );
  }
  final loanInstallmentColumns = await db.rawQuery(
    'PRAGMA table_info(finance_loan_installments)',
  );
  final addedLoanPaymentMethod = !loanInstallmentColumns.any(
    (row) => row['name'] == 'payment_method_uuid',
  );
  if (addedLoanPaymentMethod) {
    await db.execute(
      'ALTER TABLE finance_loan_installments ADD COLUMN payment_method_uuid TEXT',
    );
  }
  for (final table in financeTables) {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    var addedPendingColumn = false;
    if (!columns.any((row) => row['name'] == 'pending_sync')) {
      await db.execute(
        'ALTER TABLE $table ADD COLUMN pending_sync INTEGER NOT NULL DEFAULT 0',
      );
      addedPendingColumn = true;
    }
    if (addedPendingColumn) {
      final systemFilter =
          table == 'finance_categories' || table == 'finance_payment_methods'
          ? ' WHERE is_system = 0'
          : '';
      // Existing rows were written before the marker existed. Queue them
      // once so an offline edit made by an older app cannot be lost merely
      // because its timestamp is behind the current sync cursor.
      await db.execute('UPDATE $table SET pending_sync = 1$systemFilter');
    }
    if (table == 'finance_transactions') {
      final installmentColumns = <Map<String, String>>[
        {'name': 'installment_group_uuid', 'type': 'TEXT'},
        {'name': 'installment_index', 'type': 'INTEGER'},
        {'name': 'installment_count', 'type': 'INTEGER'},
        {'name': 'installment_total_minor', 'type': 'INTEGER'},
        {'name': 'target_payment_method_uuid', 'type': 'TEXT'},
      ];
      for (final column in installmentColumns) {
        if (!columns.any((row) => row['name'] == column['name'])) {
          await db.execute(
            'ALTER TABLE $table ADD COLUMN ${column['name']} ${column['type']}',
          );
        }
      }
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_${table}_pending '
      'ON $table(pending_sync, updated_at)',
    );
  }
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_finance_transactions_date '
    'ON finance_transactions(is_deleted, transaction_date DESC, occurred_at DESC)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_finance_transactions_updated '
    'ON finance_transactions(is_deleted, updated_at)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_finance_transactions_category '
    'ON finance_transactions(category_uuid, is_deleted, transaction_date)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_finance_transactions_balance '
    'ON finance_transactions(is_deleted, payment_method_uuid, transaction_date)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_finance_transactions_installment '
    'ON finance_transactions(installment_group_uuid, is_deleted, installment_index)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_finance_loans_active '
    'ON finance_loans(is_deleted, start_date, updated_at)',
  );
  if (addedLoanPaymentMethod) {
    await db.execute(
      'UPDATE finance_budgets SET pending_sync = 1 '
      'WHERE payment_method_uuid IS NOT NULL',
    );
  }
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_finance_loan_installments_loan '
    'ON finance_loan_installments(loan_uuid, is_deleted, installment_index)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_finance_loan_installments_due_date '
    'ON finance_loan_installments(is_deleted, due_date, loan_uuid, installment_index)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_finance_categories_active '
    'ON finance_categories(is_deleted, is_archived, type, sort_order)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_finance_payment_methods_active '
    'ON finance_payment_methods(is_deleted, is_archived, sort_order)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_finance_budgets_month '
    'ON finance_budgets(is_deleted, month_key, category_uuid)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_finance_budgets_payment_method_month '
    'ON finance_budgets(is_deleted, month_key, payment_method_uuid)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_finance_recurring_rules_active '
    'ON finance_recurring_rules(is_deleted, is_enabled, frequency, start_date)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_finance_templates_active '
    'ON finance_entry_templates(is_deleted, use_count DESC, last_used_at DESC)',
  );
}

/// AI 用量属于本机可观测性数据，不参与个人账单的云端同步；已经生成
/// 的记账汇总仍通过 finance_transactions 按用户原有规则同步。
Future<void> _ensureAiUsageSchema(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS ai_usage_records (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      provider TEXT NOT NULL,
      model TEXT NOT NULL,
      operation TEXT NOT NULL,
      prompt_tokens INTEGER NOT NULL DEFAULT 0,
      completion_tokens INTEGER NOT NULL DEFAULT 0,
      total_tokens INTEGER NOT NULL DEFAULT 0,
      cached_prompt_tokens INTEGER NOT NULL DEFAULT 0,
      image_tokens INTEGER NOT NULL DEFAULT 0,
      audio_tokens INTEGER NOT NULL DEFAULT 0,
      video_tokens INTEGER NOT NULL DEFAULT 0,
      reasoning_tokens INTEGER NOT NULL DEFAULT 0,
      audio_seconds INTEGER NOT NULL DEFAULT 0,
      image_count INTEGER NOT NULL DEFAULT 0,
      cost_micros INTEGER,
      is_priced INTEGER NOT NULL DEFAULT 0,
      ledger_key TEXT,
      created_at INTEGER NOT NULL
    )
  ''');
  final info = await db.rawQuery('PRAGMA table_info(ai_usage_records)');
  const columnsToAdd = <String, String>{
    'cached_prompt_tokens': 'INTEGER NOT NULL DEFAULT 0',
    'image_tokens': 'INTEGER NOT NULL DEFAULT 0',
    'audio_tokens': 'INTEGER NOT NULL DEFAULT 0',
    'video_tokens': 'INTEGER NOT NULL DEFAULT 0',
    'reasoning_tokens': 'INTEGER NOT NULL DEFAULT 0',
    'audio_seconds': 'INTEGER NOT NULL DEFAULT 0',
  };
  for (final entry in columnsToAdd.entries) {
    if (!info.any((row) => row['name'] == entry.key)) {
      await db.execute(
        'ALTER TABLE ai_usage_records ADD COLUMN ${entry.key} ${entry.value}',
      );
    }
  }
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_ai_usage_records_created '
    'ON ai_usage_records(created_at DESC)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_ai_usage_records_ledger '
    'ON ai_usage_records(ledger_key, is_priced)',
  );
  await db.execute('''
    CREATE TABLE IF NOT EXISTS ai_usage_ledger_links (
      ledger_key TEXT PRIMARY KEY,
      finance_transaction_uuid TEXT NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');
}

Future<void> _ensureTeamsSchema(Database db) async {
  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS teams (
        uuid TEXT PRIMARY KEY,
        name TEXT,
        creator_id INTEGER DEFAULT 0,
        created_at INTEGER DEFAULT 0,
        role INTEGER DEFAULT 1,
        member_count INTEGER DEFAULT 1,
        invite_code TEXT,
        updated_at INTEGER DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_teams_updated_at ON teams(updated_at)',
    );
  } catch (e) {
    //       debugPrint('⚠️ Database: 检查/修复 teams 表失败: $e');
  }
}

Future<void> _ensureScreenTimeSchema(Database db) async {
  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS screen_time (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        record_date TEXT,
        package_name TEXT,
        app_name TEXT,
        device_name TEXT,
        category TEXT,
        duration INTEGER,
        updated_at INTEGER
      )
    ''');

    final info = await db.rawQuery("PRAGMA table_info(screen_time)");
    final existingColumns = info.map((row) => row['name']).toSet();
    if (!existingColumns.contains('device_name')) {
      await db.execute("ALTER TABLE screen_time ADD COLUMN device_name TEXT;");
    }
    if (!existingColumns.contains('category')) {
      await db.execute("ALTER TABLE screen_time ADD COLUMN category TEXT;");
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_screen_time_date ON screen_time (record_date)',
    );
    //       debugPrint('✅ Database: screen_time schema ready');
  } catch (e) {
    //       debugPrint('⚠️ Database: screen_time schema repair failed: $e');
  }
}

Future<void> _ensureMissingIndexes(Database db) async {
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_op_logs_pending_timestamp '
    'ON op_logs(timestamp) WHERE is_synced = 0',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_plan_blocks_day ON todo_plan_blocks(is_deleted, start_time)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_plan_blocks_active_end ON todo_plan_blocks(is_deleted, end_time)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_plan_blocks_active_status ON todo_plan_blocks(is_deleted, status)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_plan_blocks_todo_active ON todo_plan_blocks(todo_uuid, is_deleted, start_time)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_todos_created ON todos(is_deleted, created_at)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_todos_completed_updated ON todos(is_deleted, is_completed, updated_at)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_todos_due_date ON todos(is_deleted, due_date)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_todos_overdue ON todos(is_deleted, is_completed, due_date)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_todos_created_date ON todos(is_deleted, created_date)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_todos_recurrence_series_date '
    'ON todos(recurrence_series_id, created_date, created_at)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_pomodoro_start ON pomodoro_records(is_deleted, start_time)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_pomodoro_todo_active ON pomodoro_records(todo_uuid, is_deleted, start_time)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_time_logs_start ON time_logs(is_deleted, start_time)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_search_history_time ON search_history(timestamp)',
  );
}
