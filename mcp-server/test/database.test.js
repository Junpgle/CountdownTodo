import assert from 'node:assert/strict';
import { rmSync } from 'node:fs';
import test from 'node:test';
import { DatabaseSync } from 'node:sqlite';

import { CountdownTodoDatabase } from '../src/database.js';
import { createTestDatabase } from './support.js';

test('creates, queries, updates, completes and soft deletes a todo', () => {
  const fixture = createTestDatabase();
  const repository = new CountdownTodoDatabase(fixture.databasePath, {
    now: () => 1_800_000_000_000,
  });

  try {
    const created = repository.createTodo({
      title: '准备 MCP 发布',
      remark: '补充文档',
      timeMode: 'dateOnly',
      dueDate: '2026-08-02',
      groupId: '11111111-1111-4111-8111-111111111111',
      recurrence: 'none',
      reminderMinutes: 30,
    });
    assert.equal(created.title, '准备 MCP 发布');
    assert.equal(created.timeMode, 'dateOnly');
    assert.equal(created.dueDate, '2026-08-02');
    assert.equal(created.groupName, '工作');

    const listed = repository.listTodos({ query: 'MCP' });
    assert.equal(listed.length, 1);
    assert.equal(listed[0].id, created.id);

    const updated = repository.updateTodo(created.id, {
      title: '发布 MCP 服务',
      remark: null,
      timeMode: 'deadline',
      dueDate: '2026-08-02T09:30:00+08:00',
    });
    assert.equal(updated.title, '发布 MCP 服务');
    assert.equal(updated.remark, null);
    assert.equal(updated.timeMode, 'deadline');
    assert.equal(updated.version, 2);

    const completed = repository.setTodoCompletion(created.id, true);
    assert.equal(completed.completed, true);
    assert.equal(completed.version, 3);
    assert.equal(repository.listTodos({ status: 'pending' }).length, 0);
    assert.equal(repository.listTodos({ status: 'completed' }).length, 1);

    const deleted = repository.deleteTodo(created.id);
    assert.equal(deleted.deleted, true);
    assert.equal(deleted.version, 4);
    assert.equal(repository.deleteTodo(created.id).version, 4);
    assert.equal(repository.getTodo(created.id), null);
  } finally {
    repository.close();
  }

  const database = new DatabaseSync(fixture.databasePath, { readOnly: true });
  const logs = database
    .prepare('SELECT * FROM op_logs ORDER BY id ASC')
    .all();
  assert.equal(logs.length, 4);
  assert.equal(logs.every((row) => row.is_synced === 0), true);
  const lastPayload = JSON.parse(logs.at(-1).data_json);
  assert.equal(lastPayload.is_deleted, 1);
  assert.equal(lastPayload.version, 4);
  const auditLogs = database
    .prepare('SELECT * FROM local_audit_logs ORDER BY id ASC')
    .all();
  assert.equal(auditLogs.length, 4);
  assert.equal(auditLogs[0].op_type, 'INSERT');
  assert.equal(auditLogs.slice(1).every((row) => row.op_type === 'UPDATE'), true);
  assert.equal(auditLogs.every((row) => row.operator_name === 'AI (MCP)'), true);
  assert.equal(JSON.parse(auditLogs.at(-1).after_data).is_deleted, 1);
  database.close();
  rmSync(fixture.directory, { recursive: true, force: true });
});

test('rejects team writes and database writes in read-only mode', () => {
  const fixture = createTestDatabase();
  const database = new DatabaseSync(fixture.databasePath);
  database
    .prepare(
      `INSERT INTO todos (
        uuid, team_uuid, content, is_completed, is_deleted, version,
        due_date, created_date, created_at, updated_at, collab_type,
        recurrence, recurrence_series_id, custom_interval_days,
        recurrence_end_date, reminder_minutes, is_all_day
      ) VALUES (?, ?, ?, 0, 0, 1, 0, ?, ?, ?, 0, 0, NULL, 0, NULL, -1, 0)`,
    )
    .run(
      '22222222-2222-4222-8222-222222222222',
      '33333333-3333-4333-8333-333333333333',
      '团队任务',
      1_700_000_000_000,
      1_700_000_000_000,
      1_700_000_000_000,
    );
  database.close();

  const repository = new CountdownTodoDatabase(fixture.databasePath);
  assert.equal(repository.listTodos({ status: 'all' }).length, 0);
  assert.equal(
    repository.getTodo('22222222-2222-4222-8222-222222222222'),
    null,
  );
  assert.throws(
    () =>
      repository.setTodoCompletion(
        '22222222-2222-4222-8222-222222222222',
        true,
      ),
    /团队待办/,
  );
  repository.close();

  const readOnly = new CountdownTodoDatabase(fixture.databasePath, {
    readOnly: true,
  });
  assert.equal(readOnly.listTodos({ status: 'all' }).length, 0);
  assert.throws(
    () => readOnly.createTodo({ title: '不能创建' }),
    /只读模式/,
  );
  readOnly.close();
  rmSync(fixture.directory, { recursive: true, force: true });
});

test('preserves legacy date-only semantics when the explicit flag is absent', () => {
  const fixture = createTestDatabase();
  const start = new Date(2026, 7, 6).getTime();
  const due = new Date(2026, 7, 6, 23, 59).getTime();
  const database = new DatabaseSync(fixture.databasePath);
  database
    .prepare(
      `INSERT INTO todos (
        uuid, team_uuid, content, is_completed, is_deleted, version,
        due_date, created_date, created_at, updated_at, collab_type,
        recurrence, recurrence_series_id, custom_interval_days,
        recurrence_end_date, reminder_minutes, is_all_day
      ) VALUES (?, NULL, ?, 0, 0, 1, ?, ?, ?, ?, 0, 0, NULL, 0, 0, -1, 0)`,
    )
    .run(
      '44444444-4444-4444-8444-444444444444',
      '旧版日期待办',
      due,
      start,
      start,
      start,
    );
  database.close();

  const repository = new CountdownTodoDatabase(fixture.databasePath, {
    readOnly: true,
  });
  const todo = repository.getTodo('44444444-4444-4444-8444-444444444444');
  assert.equal(todo.timeMode, 'dateOnly');
  assert.equal(todo.dueDate, '2026-08-06');
  repository.close();
  rmSync(fixture.directory, { recursive: true, force: true });
});

test('keeps local conflict details in audit history but strips them from sync', () => {
  const fixture = createTestDatabase();
  const repository = new CountdownTodoDatabase(fixture.databasePath, {
    now: () => 1_800_000_000_000,
  });
  const created = repository.createTodo({ title: '冲突任务' });
  repository.close();

  const database = new DatabaseSync(fixture.databasePath);
  database
    .prepare(
      `UPDATE todos
       SET has_conflict = 1, conflict_data = ?
       WHERE uuid = ?`,
    )
    .run(
      JSON.stringify({
        conflict_type: 'local_schedule_conflict',
        source: 'local_detector',
      }),
      created.id,
    );
  database.close();

  const reopened = new CountdownTodoDatabase(fixture.databasePath, {
    now: () => 1_800_000_000_100,
  });
  reopened.updateTodo(created.id, { title: '已调整冲突任务' });
  reopened.close();

  const verification = new DatabaseSync(fixture.databasePath, {
    readOnly: true,
  });
  const syncPayload = JSON.parse(
    verification
      .prepare('SELECT data_json FROM op_logs ORDER BY id DESC LIMIT 1')
      .get().data_json,
  );
  assert.equal(syncPayload.has_conflict, 0);
  assert.equal(Object.hasOwn(syncPayload, 'conflict_data'), false);

  const auditPayload = JSON.parse(
    verification
      .prepare(
        'SELECT after_data FROM local_audit_logs ORDER BY id DESC LIMIT 1',
      )
      .get().after_data,
  );
  assert.equal(auditPayload.has_conflict, 1);
  assert.match(auditPayload.conflict_data, /local_schedule_conflict/);
  verification.close();
  rmSync(fixture.directory, { recursive: true, force: true });
});

test('due date filters do not include unscheduled todos', () => {
  const fixture = createTestDatabase();
  const repository = new CountdownTodoDatabase(fixture.databasePath);
  repository.createTodo({ title: '未安排任务' });
  repository.createTodo({
    title: '有日期任务',
    timeMode: 'dateOnly',
    dueDate: '2026-08-10',
  });

  const filtered = repository.listTodos({ dueBefore: '2026-08-31' });
  assert.deepEqual(filtered.map((todo) => todo.title), ['有日期任务']);
  repository.close();
  rmSync(fixture.directory, { recursive: true, force: true });
});
