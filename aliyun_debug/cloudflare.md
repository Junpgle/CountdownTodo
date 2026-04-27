CREATE TABLE app_name_mappings (   package_name TEXT PRIMARY KEY,   mapped_name TEXT NOT NULL , category TEXT DEFAULT '未分类')
CREATE TABLE countdowns (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,       -- 关联 users.id
  title TEXT NOT NULL,            -- 倒计时标题 (e.g. "期末考试")
  target_time TIMESTAMP NOT NULL, -- 目标时间
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP, is_deleted BOOLEAN DEFAULT 0, device_id TEXT, version INTEGER DEFAULT 1, uuid TEXT,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
)
CREATE TABLE courses (     id INTEGER PRIMARY KEY AUTOINCREMENT,     user_id INTEGER NOT NULL,     course_name TEXT NOT NULL,     room_name TEXT NOT NULL,     teacher_name TEXT NOT NULL,     start_time INTEGER NOT NULL,     end_time INTEGER NOT NULL,     weekday INTEGER NOT NULL,     week_index INTEGER NOT NULL,     lesson_type TEXT,     created_at INTEGER NOT NULL,     updated_at INTEGER NOT NULL,     is_deleted INTEGER DEFAULT 0, semester TEXT DEFAULT 'default', date TEXT DEFAULT '',     FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE )
CREATE TABLE leaderboard (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,       -- 关联 users.id
  username TEXT NOT NULL,         -- 冗余存储一份当时的用户名，方便快速查询（快照）
  score INTEGER NOT NULL,
  duration INTEGER NOT NULL,      -- 耗时（秒）
  played_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
)
CREATE TABLE pending_registrations (
  email TEXT PRIMARY KEY,       -- 邮箱作为主键，防止重复发送堆积
  username TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  code TEXT NOT NULL,           -- 6位数字验证码
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
CREATE TABLE pomodoro_records (      uuid TEXT PRIMARY KEY,      user_id INTEGER NOT NULL,      todo_uuid TEXT,                          start_time INTEGER NOT NULL,             end_time INTEGER,                        planned_duration INTEGER NOT NULL,       actual_duration INTEGER,                status TEXT CHECK(status IN ('completed', 'interrupted', 'switched')),      device_id TEXT,                          is_deleted INTEGER DEFAULT 0,      version INTEGER DEFAULT 1,      created_at INTEGER NOT NULL,      updated_at INTEGER NOT NULL  )
CREATE TABLE pomodoro_settings (      user_id INTEGER PRIMARY KEY,      default_focus_duration INTEGER DEFAULT 1500,      default_rest_duration INTEGER DEFAULT 300,         default_loop_count INTEGER DEFAULT 4,             updated_at INTEGER NOT NULL  )
CREATE TABLE pomodoro_tags (      uuid TEXT PRIMARY KEY,      user_id INTEGER NOT NULL,                name TEXT NOT NULL,      color TEXT,      is_deleted INTEGER DEFAULT 0,           version INTEGER DEFAULT 1,              created_at INTEGER NOT NULL,             updated_at INTEGER NOT NULL          )
CREATE TABLE screen_time_logs (   id INTEGER PRIMARY KEY AUTOINCREMENT,   user_id INTEGER NOT NULL,   device_name TEXT NOT NULL,          record_date DATE NOT NULL,          app_name TEXT NOT NULL,             duration INTEGER NOT NULL DEFAULT 0,    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,   updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,   FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,   UNIQUE(user_id, device_name, record_date, app_name) )
CREATE TABLE sqlite_sequence(name,seq)
CREATE TABLE sync_limits (     user_id INTEGER PRIMARY KEY,      sync_date DATE NOT NULL,      sync_count INTEGER DEFAULT 0,      last_sync_time DATETIME , device_id TEXT)
CREATE TABLE time_logs (   uuid TEXT PRIMARY KEY,   user_id INTEGER NOT NULL,   title TEXT NOT NULL,   tag_uuids TEXT,   start_time INTEGER NOT NULL,   end_time INTEGER NOT NULL,   remark TEXT,   version INTEGER DEFAULT 1,   is_deleted INTEGER DEFAULT 0,   device_id TEXT,   created_at INTEGER NOT NULL,   updated_at INTEGER NOT NULL )
CREATE TABLE todo_tags (     todo_uuid TEXT NOT NULL,     tag_uuid TEXT NOT NULL,     is_deleted INTEGER DEFAULT 0,     updated_at INTEGER NOT NULL,     PRIMARY KEY (todo_uuid, tag_uuid) )
CREATE TABLE todos (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,       -- 关联 users.id
  content TEXT NOT NULL,          -- 待办内容
  is_completed BOOLEAN DEFAULT 0, -- 0:未完成, 1:已完成
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP, is_deleted BOOLEAN DEFAULT 0, due_date TEXT, created_date TEXT, version INTEGER DEFAULT 1, device_id TEXT, uuid TEXT, recurrence INTEGER DEFAULT 0, custom_interval_days INTEGER, recurrence_end_date INTEGER, remark TEXT,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
)
CREATE TABLE users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,     -- 邮箱作为唯一标识，用于登录
  password_hash TEXT NOT NULL,    -- 存储加密后的密码
  avatar_url TEXT,                -- 用户头像地址 (可选)
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
, tier TEXT DEFAULT 'free', semester_start INTEGER, semester_end INTEGER)
