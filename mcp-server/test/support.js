import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';

export function createTestDatabase() {
  const directory = mkdtempSync(path.join(tmpdir(), 'countdown-todo-mcp-'));
  const databasePath = path.join(directory, 'test.db');
  const database = new DatabaseSync(databasePath);
  database.exec(`
    CREATE TABLE todos (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      team_uuid TEXT,
      group_id TEXT,
      content TEXT NOT NULL,
      remark TEXT,
      team_name TEXT,
      creator_id TEXT,
      creator_name TEXT,
      is_completed INTEGER NOT NULL DEFAULT 0,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      version INTEGER NOT NULL DEFAULT 1,
      due_date INTEGER,
      created_date INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      collab_type INTEGER NOT NULL DEFAULT 0,
      recurrence INTEGER NOT NULL DEFAULT 0,
      recurrence_series_id TEXT,
      custom_interval_days INTEGER NOT NULL DEFAULT 0,
      recurrence_end_date INTEGER,
      reminder_minutes INTEGER,
      has_conflict INTEGER DEFAULT 0,
      conflict_data TEXT,
      is_all_day INTEGER DEFAULT 0,
      image_path TEXT,
      original_text TEXT
    );

    CREATE TABLE todo_groups (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      team_uuid TEXT,
      name TEXT NOT NULL,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL DEFAULT 0
    );

    CREATE TABLE op_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      op_type TEXT NOT NULL,
      target_table TEXT NOT NULL,
      target_uuid TEXT NOT NULL,
      data_json TEXT,
      timestamp INTEGER NOT NULL,
      is_synced INTEGER NOT NULL DEFAULT 0,
      sync_error TEXT NOT NULL DEFAULT ''
    );

    CREATE TABLE local_audit_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      team_uuid TEXT,
      user_id INTEGER,
      target_table TEXT,
      target_uuid TEXT,
      op_type TEXT,
      before_data TEXT,
      after_data TEXT,
      timestamp INTEGER,
      operator_name TEXT
    );
  `);
  database
    .prepare(
      `INSERT INTO todo_groups (uuid, team_uuid, name, is_deleted, updated_at)
       VALUES (?, NULL, ?, 0, ?)`,
    )
    .run('11111111-1111-4111-8111-111111111111', '工作', 1_700_000_000_000);
  database.close();
  return { directory, databasePath };
}
