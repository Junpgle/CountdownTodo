import { existsSync, statSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';

const recurrenceIndexes = Object.freeze({
  none: 0,
  daily: 1,
  customDays: 2,
  weekly: 3,
  monthly: 4,
  yearly: 5,
  weekdays: 6,
});

const recurrenceNames = Object.freeze(
  Object.fromEntries(
    Object.entries(recurrenceIndexes).map(([name, index]) => [index, name]),
  ),
);

const requiredColumns = Object.freeze({
  todos: [
    'uuid',
    'team_uuid',
    'group_id',
    'content',
    'remark',
    'team_name',
    'creator_id',
    'creator_name',
    'is_completed',
    'is_deleted',
    'version',
    'due_date',
    'created_date',
    'created_at',
    'updated_at',
    'collab_type',
    'recurrence',
    'recurrence_series_id',
    'custom_interval_days',
    'recurrence_end_date',
    'reminder_minutes',
    'has_conflict',
    'conflict_data',
    'is_all_day',
    'image_path',
    'original_text',
  ],
  todo_groups: ['uuid', 'team_uuid', 'name', 'is_deleted', 'updated_at'],
  op_logs: [
    'op_type',
    'target_table',
    'target_uuid',
    'data_json',
    'timestamp',
    'is_synced',
    'sync_error',
  ],
  local_audit_logs: [
    'team_uuid',
    'user_id',
    'target_table',
    'target_uuid',
    'op_type',
    'before_data',
    'after_data',
    'timestamp',
    'operator_name',
  ],
});

export class CountdownTodoDatabase {
  constructor(databasePath, { readOnly = false, now = () => Date.now() } = {}) {
    if (!databasePath) {
      throw new Error(
        '未配置数据库。请设置 COUNTDOWN_TODO_DATABASE 或传入 --database。',
      );
    }
    if (!existsSync(databasePath) || !statSync(databasePath).isFile()) {
      throw new Error(`找不到 CountdownTodo 数据库: ${databasePath}`);
    }

    this.databasePath = databasePath;
    this.readOnly = readOnly;
    this.now = now;
    this.database = new DatabaseSync(databasePath, { readOnly });
    this.database.exec('PRAGMA busy_timeout = 5000');
    this.database.exec('PRAGMA foreign_keys = ON');
    this.validateSchema();
  }

  validateSchema() {
    for (const [table, columns] of Object.entries(requiredColumns)) {
      const tableRow = this.database
        .prepare(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        )
        .get(table);
      if (!tableRow) {
        throw new Error(`数据库缺少 ${table} 表；请先用当前版本应用打开并迁移数据库`);
      }

      const existingColumns = new Set(
        this.database
          .prepare(`PRAGMA table_info(${table})`)
          .all()
          .map((row) => row.name),
      );
      const missing = columns.filter((column) => !existingColumns.has(column));
      if (missing.length > 0) {
        throw new Error(
          `数据库表 ${table} 缺少字段: ${missing.join(', ')}；请先运行应用完成迁移`,
        );
      }
    }
    return {
      databasePath: this.databasePath,
      readOnly: this.readOnly,
      schemaValid: true,
    };
  }

  close() {
    this.database.close();
  }

  listTodoGroups() {
    return this.database
      .prepare(
        `SELECT uuid, name, updated_at
         FROM todo_groups
         WHERE is_deleted = 0 AND team_uuid IS NULL
         ORDER BY name COLLATE NOCASE ASC`,
      )
      .all()
      .map((row) => ({
        id: row.uuid,
        name: row.name,
        updatedAt: toIso(row.updated_at),
      }));
  }

  listTodos({
    status = 'pending',
    query,
    groupId,
    dueFrom,
    dueBefore,
    limit = 50,
  } = {}) {
    const where = ['t.is_deleted = 0', 't.team_uuid IS NULL'];
    const values = [];

    if (status === 'pending') {
      where.push('t.is_completed = 0');
    } else if (status === 'completed') {
      where.push('t.is_completed = 1');
    } else if (status !== 'all') {
      throw new Error(`不支持的 status: ${status}`);
    }

    if (query?.trim()) {
      const pattern = `%${query.trim()}%`;
      where.push('(t.content LIKE ? OR COALESCE(t.remark, \'\') LIKE ?)');
      values.push(pattern, pattern);
    }
    if (groupId) {
      where.push('t.group_id = ?');
      values.push(groupId);
    }
    if (dueFrom || dueBefore) {
      where.push('CAST(t.due_date AS INTEGER) > 0');
    }
    if (dueFrom) {
      where.push('CAST(t.due_date AS INTEGER) >= ?');
      values.push(parseBoundary(dueFrom, 'start'));
    }
    if (dueBefore) {
      where.push('CAST(t.due_date AS INTEGER) <= ?');
      values.push(parseBoundary(dueBefore, 'end'));
    }

    const safeLimit = Math.min(Math.max(Number(limit) || 50, 1), 200);
    values.push(safeLimit);
    const rows = this.database
      .prepare(
        `SELECT t.*, g.name AS group_name
         FROM todos t
         LEFT JOIN todo_groups g
           ON g.uuid = t.group_id AND g.is_deleted = 0
         WHERE ${where.join(' AND ')}
         ORDER BY
           CASE WHEN t.due_date IS NULL OR CAST(t.due_date AS INTEGER) <= 0
             THEN 1 ELSE 0 END,
           CAST(t.due_date AS INTEGER) ASC,
           t.updated_at DESC
         LIMIT ?`,
      )
      .all(...values);
    return rows.map(toTodo);
  }

  getTodo(todoId) {
    const row = this.#getTodoRow(todoId);
    return row && !row.team_uuid ? toTodo(row) : null;
  }

  createTodo(input) {
    this.#assertWritable();
    const title = requireTitle(input.title);
    const recurrence = input.recurrence ?? 'none';
    if (!(recurrence in recurrenceIndexes)) {
      throw new Error(`不支持的 recurrence: ${recurrence}`);
    }
    const time = normalizeTime(input.timeMode ?? 'unscheduled', input.dueDate);
    if (recurrence !== 'none' && time.dueDate === 0) {
      throw new Error('循环待办必须提供首次发生日期或截止时间');
    }
    if (recurrence === 'customDays' && !input.customIntervalDays) {
      throw new Error('customDays 循环必须提供 customIntervalDays');
    }
    const id = randomUUID();
    const now = this.now();
    const recurrenceEndDate =
      recurrence !== 'none' && input.recurrenceEndDate
        ? parseBoundary(input.recurrenceEndDate, 'end')
        : null;
    if (recurrenceEndDate != null && recurrenceEndDate < time.dueDate) {
      throw new Error('recurrenceEndDate 不能早于首次发生时间');
    }
    const rowValues = {
      uuid: id,
      content: title,
      remark: normalizeNullableText(input.remark),
      groupId: input.groupId ?? null,
      dueDate: time.dueDate,
      createdDate: time.createdDate,
      isAllDay: time.isAllDay,
      recurrence: recurrenceIndexes[recurrence],
      recurrenceSeriesId: recurrence === 'none' ? null : id,
      customIntervalDays:
        recurrence === 'customDays' ? input.customIntervalDays : 0,
      recurrenceEndDate,
      reminderMinutes: input.reminderMinutes ?? -1,
      createdAt: now,
      updatedAt: now,
    };
    rowValues.createdDate ??= now;

    return this.#transaction(() => {
      this.#assertGroupExists(input.groupId);
      this.database
        .prepare(
          `INSERT INTO todos (
             uuid, team_uuid, group_id, content, remark, team_name,
             creator_id, creator_name, is_completed, is_deleted, version,
             due_date, created_date, created_at, updated_at, collab_type,
             recurrence, recurrence_series_id, custom_interval_days,
             recurrence_end_date, reminder_minutes, has_conflict,
             conflict_data, is_all_day, image_path, original_text
           ) VALUES (
             ?, NULL, ?, ?, ?, NULL,
             NULL, NULL, 0, 0, 1,
             ?, ?, ?, ?, 0,
             ?, ?, ?,
             ?, ?, 0,
             NULL, ?, NULL, NULL
           )`,
        )
        .run(
          rowValues.uuid,
          rowValues.groupId,
          rowValues.content,
          rowValues.remark,
          rowValues.dueDate,
          rowValues.createdDate,
          rowValues.createdAt,
          rowValues.updatedAt,
          rowValues.recurrence,
          rowValues.recurrenceSeriesId,
          rowValues.customIntervalDays,
          rowValues.recurrenceEndDate,
          rowValues.reminderMinutes,
          rowValues.isAllDay,
        );
      const row = this.#getTodoRow(id, { includeDeleted: true });
      this.#insertAuditLog('INSERT', null, row);
      this.#insertOpLog(row);
      return toTodo(row);
    });
  }

  updateTodo(todoId, input) {
    this.#assertWritable();
    return this.#transaction(() => {
      const current = this.#requirePersonalTodo(todoId);
      const changes = [];
      const values = [];

      if (Object.hasOwn(input, 'title')) {
        changes.push('content = ?');
        values.push(requireTitle(input.title));
      }
      if (Object.hasOwn(input, 'remark')) {
        changes.push('remark = ?');
        values.push(normalizeNullableText(input.remark));
      }
      if (Object.hasOwn(input, 'groupId')) {
        this.#assertGroupExists(input.groupId);
        changes.push('group_id = ?');
        values.push(input.groupId ?? null);
      }
      if (Object.hasOwn(input, 'reminderMinutes')) {
        changes.push('reminder_minutes = ?');
        values.push(input.reminderMinutes ?? -1);
      }
      if (Object.hasOwn(input, 'timeMode')) {
        const time = normalizeTime(input.timeMode, input.dueDate);
        changes.push('created_date = ?', 'due_date = ?', 'is_all_day = ?');
        values.push(
          time.createdDate ?? Number(current.created_at),
          time.dueDate,
          time.isAllDay,
        );
      } else if (Object.hasOwn(input, 'dueDate')) {
        throw new Error('修改时间时必须同时提供 timeMode');
      }

      if (changes.length === 0) return toTodo(current);
      const updatedAt = Math.max(this.now(), Number(current.updated_at) + 1);
      changes.push('version = version + 1', 'updated_at = ?');
      values.push(updatedAt, todoId);

      this.database
        .prepare(`UPDATE todos SET ${changes.join(', ')} WHERE uuid = ?`)
        .run(...values);
      const row = this.#getTodoRow(todoId, { includeDeleted: true });
      this.#insertAuditLog('UPDATE', current, row);
      this.#insertOpLog(row);
      return toTodo(row);
    });
  }

  setTodoCompletion(todoId, completed = true) {
    this.#assertWritable();
    const target = completed ? 1 : 0;
    return this.#transaction(() => {
      const current = this.#requirePersonalTodo(todoId);
      if (Number(current.is_completed) === target) return toTodo(current);
      return this.#writeState(todoId, 'is_completed', target, current);
    });
  }

  deleteTodo(todoId) {
    this.#assertWritable();
    return this.#transaction(() => {
      const current = this.#requirePersonalTodo(todoId, { allowDeleted: true });
      if (Number(current.is_deleted) === 1) return toTodo(current);
      return this.#writeState(todoId, 'is_deleted', 1, current);
    });
  }

  #writeState(todoId, column, value, current) {
    const updatedAt = Math.max(this.now(), Number(current.updated_at) + 1);
    this.database
      .prepare(
        `UPDATE todos
         SET ${column} = ?, version = version + 1, updated_at = ?
         WHERE uuid = ?`,
      )
      .run(value, updatedAt, todoId);
    const row = this.#getTodoRow(todoId, { includeDeleted: true });
    this.#insertAuditLog('UPDATE', current, row);
    this.#insertOpLog(row);
    return toTodo(row);
  }

  #getTodoRow(todoId, { includeDeleted = false } = {}) {
    return this.database
      .prepare(
        `SELECT t.*, g.name AS group_name
         FROM todos t
         LEFT JOIN todo_groups g
           ON g.uuid = t.group_id AND g.is_deleted = 0
         WHERE t.uuid = ?${includeDeleted ? '' : ' AND t.is_deleted = 0'}
         LIMIT 1`,
      )
      .get(todoId);
  }

  #requirePersonalTodo(todoId, { allowDeleted = false } = {}) {
    const row = this.#getTodoRow(todoId, { includeDeleted: true });
    if (!row) throw new Error(`找不到待办: ${todoId}`);
    if (!allowDeleted && Number(row.is_deleted) === 1) {
      throw new Error(`待办已在回收站中: ${todoId}`);
    }
    if (row.team_uuid) {
      throw new Error('MCP 暂不允许修改团队待办，请在应用内完成此操作');
    }
    return row;
  }

  #assertGroupExists(groupId) {
    if (groupId == null || groupId === '') return;
    const row = this.database
      .prepare(
        `SELECT uuid FROM todo_groups
         WHERE uuid = ? AND is_deleted = 0 AND team_uuid IS NULL`,
      )
      .get(groupId);
    if (!row) throw new Error(`找不到个人待办分类: ${groupId}`);
  }

  #assertWritable() {
    if (this.readOnly) {
      throw new Error('MCP 服务当前以只读模式运行');
    }
  }

  #insertOpLog(row) {
    const timestamp = this.now();
    this.database
      .prepare(
        `INSERT INTO op_logs (
           op_type, target_table, target_uuid, data_json,
           timestamp, is_synced, sync_error
         ) VALUES ('UPSERT', 'todos', ?, ?, ?, 0, '')`,
      )
      .run(row.uuid, JSON.stringify(toSyncPayload(row)), timestamp);
  }

  #insertAuditLog(opType, beforeRow, afterRow) {
    this.database
      .prepare(
        `INSERT INTO local_audit_logs (
           team_uuid, user_id, target_table, target_uuid, op_type,
           before_data, after_data, timestamp, operator_name
         ) VALUES (NULL, 0, 'todos', ?, ?, ?, ?, ?, 'AI (MCP)')`,
      )
      .run(
        afterRow.uuid,
        opType,
        beforeRow == null ? null : JSON.stringify(toTodoPayload(beforeRow)),
        JSON.stringify(toTodoPayload(afterRow)),
        this.now(),
      );
  }

  #transaction(action) {
    this.database.exec('BEGIN IMMEDIATE');
    try {
      const result = action();
      this.database.exec('COMMIT');
      return result;
    } catch (error) {
      try {
        this.database.exec('ROLLBACK');
      } catch {
        // Preserve the original database error.
      }
      throw error;
    }
  }
}

function normalizeTime(timeMode, dueDate) {
  if (timeMode === 'unscheduled') {
    return { createdDate: null, dueDate: 0, isAllDay: 0 };
  }
  if (!dueDate) {
    throw new Error(`${timeMode} 待办必须提供 dueDate`);
  }
  if (timeMode === 'dateOnly') {
    const [year, month, day] = parseLocalDate(dueDate, 'dateOnly 的 dueDate');
    const start = new Date(year, month - 1, day);
    const end = new Date(
      year,
      month - 1,
      day,
      23,
      59,
    );
    return {
      createdDate: start.getTime(),
      dueDate: end.getTime(),
      isAllDay: 1,
    };
  }
  if (timeMode === 'deadline') {
    const milliseconds = Date.parse(dueDate);
    if (!Number.isFinite(milliseconds)) {
      throw new Error(`无效截止时间: ${dueDate}`);
    }
    return {
      createdDate: milliseconds,
      dueDate: milliseconds,
      isAllDay: 0,
    };
  }
  throw new Error(`不支持的 timeMode: ${timeMode}`);
}

function parseBoundary(value, edge) {
  if (/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    const [year, month, day] = parseLocalDate(value, '日期');
    const date = new Date(
      year,
      month - 1,
      day,
      edge === 'end' ? 23 : 0,
      edge === 'end' ? 59 : 0,
      edge === 'end' ? 59 : 0,
      edge === 'end' ? 999 : 0,
    );
    return date.getTime();
  }
  const milliseconds = Date.parse(value);
  if (!Number.isFinite(milliseconds)) throw new Error(`无效时间: ${value}`);
  return milliseconds;
}

function parseLocalDate(value, label) {
  const parts = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!parts) throw new Error(`${label} 必须使用 YYYY-MM-DD 格式`);
  const year = Number(parts[1]);
  const month = Number(parts[2]);
  const day = Number(parts[3]);
  const date = new Date(year, month - 1, day);
  if (
    date.getFullYear() !== year ||
    date.getMonth() !== month - 1 ||
    date.getDate() !== day
  ) {
    throw new Error(`无效日期: ${value}`);
  }
  return [year, month, day];
}

function requireTitle(value) {
  const title = value?.trim();
  if (!title) throw new Error('待办标题不能为空');
  return title;
}

function normalizeNullableText(value) {
  if (value == null) return null;
  const text = value.trim();
  return text || null;
}

function toTodo(row) {
  const dueMilliseconds = positiveMilliseconds(row.due_date);
  const recurrenceEndMilliseconds = positiveMilliseconds(
    row.recurrence_end_date,
  );
  const isAllDay =
    Number(row.is_all_day) === 1 ||
    looksLikeLegacyDateOnly(row.created_date, dueMilliseconds);
  return {
    id: row.uuid,
    title: row.content,
    remark: row.remark ?? null,
    completed: Number(row.is_completed) === 1,
    deleted: Number(row.is_deleted) === 1,
    timeMode: dueMilliseconds == null
      ? 'unscheduled'
      : isAllDay
        ? 'dateOnly'
        : 'deadline',
    dueDate: dueMilliseconds == null
      ? null
      : isAllDay
        ? toLocalDate(dueMilliseconds)
        : new Date(dueMilliseconds).toISOString(),
    groupId: row.group_id ?? null,
    groupName: row.group_name ?? null,
    reminderMinutes:
      row.reminder_minutes == null || Number(row.reminder_minutes) < 0
        ? null
        : Number(row.reminder_minutes),
    recurrence: recurrenceNames[Number(row.recurrence)] ?? 'none',
    recurrenceSeriesId: row.recurrence_series_id ?? null,
    customIntervalDays: row.custom_interval_days ?? null,
    recurrenceEndDate: recurrenceEndMilliseconds == null
      ? null
      : toLocalDate(recurrenceEndMilliseconds),
    teamId: row.team_uuid ?? null,
    version: Number(row.version),
    createdAt: toIso(row.created_at),
    updatedAt: toIso(row.updated_at),
  };
}

function toTodoPayload(row) {
  return {
    id: row.uuid,
    uuid: row.uuid,
    content: row.content,
    is_completed: Number(row.is_completed),
    is_deleted: Number(row.is_deleted),
    version: Number(row.version),
    updated_at: Number(row.updated_at),
    created_at: Number(row.created_at),
    created_date: nullableMilliseconds(row.created_date),
    due_date: nullableMilliseconds(row.due_date),
    recurrence: Number(row.recurrence),
    recurrence_series_id: row.recurrence_series_id ?? null,
    recurrenceSeriesId: row.recurrence_series_id ?? null,
    customIntervalDays: row.custom_interval_days ?? null,
    custom_interval_days: row.custom_interval_days ?? null,
    recurrenceEndDate: nullableMilliseconds(row.recurrence_end_date),
    recurrence_end_date: nullableMilliseconds(row.recurrence_end_date),
    remark: row.remark ?? null,
    image_path: row.image_path ?? null,
    original_text: row.original_text ?? null,
    group_id: row.group_id ?? null,
    reminder_minutes:
      row.reminder_minutes == null ? null : Number(row.reminder_minutes),
    team_uuid: row.team_uuid ?? null,
    creator_id: row.creator_id ?? null,
    creator_name: row.creator_name ?? null,
    team_name: row.team_name ?? null,
    collab_type: Number(row.collab_type),
    is_all_day: Number(row.is_all_day),
    has_conflict: Number(row.has_conflict),
    conflict_data: row.conflict_data ?? null,
  };
}

function toSyncPayload(row) {
  const payload = toTodoPayload(row);
  const conflictData = parseConflictData(payload.conflict_data);
  if (
    conflictData?.conflict_type === 'local_schedule_conflict' ||
    conflictData?.source === 'local_detector'
  ) {
    payload.has_conflict = 0;
    delete payload.conflict_data;
  }
  return payload;
}

function parseConflictData(value) {
  if (value == null || value === '') return null;
  if (typeof value === 'object') return value;
  try {
    const decoded = JSON.parse(value);
    return decoded && typeof decoded === 'object' ? decoded : null;
  } catch {
    return null;
  }
}

function nullableMilliseconds(value) {
  if (value == null || value === '') return null;
  const number = Number(value);
  if (Number.isFinite(number) && number > 0) return number;
  const parsed = Date.parse(String(value));
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

function positiveMilliseconds(value) {
  return nullableMilliseconds(value);
}

function toIso(value) {
  const milliseconds = positiveMilliseconds(value);
  return milliseconds == null ? null : new Date(milliseconds).toISOString();
}

function toLocalDate(milliseconds) {
  const date = new Date(milliseconds);
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function looksLikeLegacyDateOnly(createdDate, dueMilliseconds) {
  const startMilliseconds = positiveMilliseconds(createdDate);
  if (startMilliseconds == null || dueMilliseconds == null) return false;
  const start = new Date(startMilliseconds);
  const due = new Date(dueMilliseconds);
  const startsAtMidnight =
    start.getHours() === 0 &&
    start.getMinutes() === 0 &&
    start.getSeconds() === 0 &&
    start.getMilliseconds() === 0;
  if (!startsAtMidnight || dueMilliseconds <= startMilliseconds) return false;
  const endsAtEndOfDay = due.getHours() === 23 && due.getMinutes() === 59;
  const endsAtLaterMidnight =
    due.getHours() === 0 &&
    due.getMinutes() === 0 &&
    due.getSeconds() === 0 &&
    due.getMilliseconds() === 0;
  return endsAtEndOfDay || endsAtLaterMidnight;
}
