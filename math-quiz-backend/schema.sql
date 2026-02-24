-- 1. 用户表 (Users)
DROP TABLE IF EXISTS users;
CREATE TABLE users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  avatar_url TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 触发器：用户更新时自动刷新 updated_at
CREATE TRIGGER IF NOT EXISTS update_users_timestamp AFTER UPDATE ON users
BEGIN
  UPDATE users SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

-- 2. 增强版排行榜 (Leaderboard)
DROP TABLE IF EXISTS leaderboard;
CREATE TABLE leaderboard (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  username TEXT NOT NULL,
  score INTEGER NOT NULL,
  duration INTEGER NOT NULL,
  played_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
CREATE INDEX idx_leaderboard_rank ON leaderboard(score DESC, duration ASC);

-- 3. 待办事项表 (Todos)
DROP TABLE IF EXISTS todos;
CREATE TABLE todos (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  content TEXT NOT NULL,
  is_completed BOOLEAN DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
CREATE INDEX idx_todos_user ON todos(user_id);

-- 触发器：待办更新时自动刷新 updated_at
CREATE TRIGGER IF NOT EXISTS update_todos_timestamp AFTER UPDATE ON todos
BEGIN
  UPDATE todos SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

-- 4. 倒计时表 (Countdowns)
DROP TABLE IF EXISTS countdowns;
CREATE TABLE countdowns (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  title TEXT NOT NULL,
  target_time TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
CREATE INDEX idx_countdowns_user ON countdowns(user_id);

-- 触发器：倒计时更新时自动刷新 updated_at
CREATE TRIGGER IF NOT EXISTS update_countdowns_timestamp AFTER UPDATE ON countdowns
BEGIN
  UPDATE countdowns SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

-- 5. 待验证注册表 (Pending Registrations)
DROP TABLE IF EXISTS pending_registrations;
CREATE TABLE pending_registrations (
  email TEXT PRIMARY KEY,
  username TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  code TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 6. 屏幕使用时间表 (Screen Time Logs) - 新增
DROP TABLE IF EXISTS screen_time_logs;
CREATE TABLE screen_time_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  device_name TEXT NOT NULL,       -- 设备名称或标识，例如 "Win10-PC", "Office-Laptop"
  record_date DATE NOT NULL,       -- 记录日期，格式建议为 'YYYY-MM-DD'，方便按年月日分组查询
  app_name TEXT NOT NULL,          -- 应用程序名称，例如 "Google Chrome"
  duration INTEGER NOT NULL DEFAULT 0, -- 该应用在当天的使用总时长（秒）
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  -- 设置联合唯一约束：同一用户、同一设备、同一天、同一个应用只能有一条记录
  -- 这样可以非常方便地使用 INSERT ... ON CONFLICT DO UPDATE 语句进行数据同步累加
  UNIQUE(user_id, device_name, record_date, app_name)
);

-- 建立复合索引以加速：按用户、日期和设备的查询统计
CREATE INDEX idx_screen_time_query ON screen_time_logs(user_id, record_date, device_name);

-- 触发器：屏幕时间更新时自动刷新 updated_at
CREATE TRIGGER IF NOT EXISTS update_screen_time_timestamp AFTER UPDATE ON screen_time_logs
BEGIN
  UPDATE screen_time_logs SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;
