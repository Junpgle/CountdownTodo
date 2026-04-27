const sqlite3 = require('sqlite3').verbose();
const path = require('path');
const https = require('https');
const dns = require('dns');

// 🚀 强制 IPv4，避开阿里云底层 fetch 和 IPv6 路由黑洞
dns.setDefaultResultOrder('ipv4first');

// 🔒 核心修复：引入 dotenv 并强制从脚本所在目录加载 .env 文件
require('dotenv').config({ path: path.join(__dirname, '.env') });

// 获取绝对路径，确保在 crontab 定时任务中执行时不会找不到数据库
const dbPath = path.join(__dirname, 'database.db');
const db = new sqlite3.Database(dbPath);

const CF_EXPORT_URL = "https://mathquiz.junpgle.me/api/admin/s2s_export";
const API_SECRET = process.env.API_SECRET;

// 封装基于 Promise 的 DB 操作
const dbGet = (sql, params = []) => new Promise((res, rej) => db.get(sql, params, (err, row) => err ? rej(err) : res(row)));
const dbRun = (sql, params = []) => new Promise((res, rej) => db.run(sql, params, function(err) { err ? rej(err) : res(this); }));

// 格式化日志输出
const log = (msg) => console.log(`[${new Date().toISOString()}] ${msg}`);
const errorLog = (msg, err) => console.error(`[${new Date().toISOString()}] ❌ ${msg}`, err);

async function cronLwwSync() {
    log(`🔄 开始执行后台 LWW 同步 (Cloudflare -> Aliyun)...`);

    try {
        // 1. 发起网络请求抓取全量数据包
        const response = await new Promise((resolve, reject) => {
            const url = new URL(CF_EXPORT_URL);
            const options = {
                hostname: url.hostname,
                port: url.port || 443,
                path: url.pathname + url.search,
                method: 'GET',
                family: 4, // 强制 IPv4
                timeout: 60000, // 60秒超时保护
                headers: {
                    'User-Agent': 'MathQuiz-Cron-Sync/1.0',
                    'x-admin-secret': API_SECRET
                }
            };

            const req = https.request(options, (res) => {
                let body = '';
                res.on('data', chunk => body += chunk);
                res.on('end', () => {
                    try {
                        const parsed = JSON.parse(body);
                        resolve({ ok: res.statusCode === 200, data: parsed });
                    } catch (e) {
                        resolve({ ok: false, data: body });
                    }
                });
            });

            req.on('timeout', () => { req.destroy(); reject(new Error('请求超时')); });
            req.on('error', (e) => reject(e));
            req.end();
        });

        if (!response.ok || !response.data.success) {
            throw new Error(`Cloudflare 接口返回异常`);
        }

        const payload = response.data.data;
        const userIdMap = {}; // 动态 ID 映射表 (CF_ID -> Aliyun_ID)
        let mergedCount = 0;

        await dbRun("BEGIN TRANSACTION");

        // 2. Users 表对齐 (Email 唯一标识)
        if (payload.users) {
            for (const u of payload.users) {
                const existing = await dbGet("SELECT id FROM users WHERE email = ?", [u.email]);
                if (existing) {
                    userIdMap[u.id] = existing.id;
                    await dbRun(`UPDATE users SET username=?, password_hash=?, avatar_url=?, semester_start=?, semester_end=? WHERE id=?`,
                        [u.username, u.password_hash, u.avatar_url, u.semester_start, u.semester_end, existing.id]);
                } else {
                    const result = await dbRun(`INSERT INTO users (username, email, password_hash, tier, avatar_url, semester_start, semester_end, created_at) VALUES (?,?,?,?,?,?,?,?)`,
                        [u.username, u.email, u.password_hash, u.tier, u.avatar_url, u.semester_start, u.semester_end, u.created_at]);
                    userIdMap[u.id] = result.lastID;
                }
            }
        }

        const getMappedId = (oldId) => userIdMap[oldId] || oldId;

        // 3. 执行核心 LWW 智能合并 (Last-Write-Wins)
        // Todos
        if (payload.todos) {
            mergedCount += payload.todos.length;
            for (const t of payload.todos) {
                if (!t.uuid) continue;
                await dbRun(`
                    INSERT INTO todos (uuid, user_id, content, is_completed, is_deleted, version, device_id, created_at, updated_at, due_date, created_date, recurrence, custom_interval_days, recurrence_end_date, remark, group_id)
                    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                        ON CONFLICT(uuid) DO UPDATE SET
                        content=excluded.content, is_completed=excluded.is_completed, is_deleted=excluded.is_deleted, version=excluded.version, device_id=excluded.device_id, updated_at=excluded.updated_at, due_date=excluded.due_date, created_date=excluded.created_date, recurrence=excluded.recurrence, custom_interval_days=excluded.custom_interval_days, recurrence_end_date=excluded.recurrence_end_date, remark=excluded.remark, group_id=excluded.group_id
                                             WHERE excluded.updated_at > todos.updated_at OR (excluded.updated_at = todos.updated_at AND excluded.version > todos.version)
                `, [t.uuid, getMappedId(t.user_id), t.content, t.is_completed, t.is_deleted, t.version, t.device_id, t.created_at, t.updated_at, t.due_date, t.created_date, t.recurrence, t.custom_interval_days, t.recurrence_end_date, t.remark, t.group_id]);
            }
        }

        // Todo Groups
        if (payload.todo_groups) {
            mergedCount += payload.todo_groups.length;
            for (const g of payload.todo_groups) {
                if (!g.uuid) continue;
                await dbRun(`
                    INSERT INTO todo_groups (uuid, user_id, name, is_expanded, is_deleted, version, created_at, updated_at)
                    VALUES (?,?,?,?,?,?,?,?)
                        ON CONFLICT(uuid) DO UPDATE SET
                        name=excluded.name, is_expanded=excluded.is_expanded, is_deleted=excluded.is_deleted, version=excluded.version, updated_at=excluded.updated_at
                                             WHERE excluded.updated_at > todo_groups.updated_at OR (excluded.updated_at = todo_groups.updated_at AND excluded.version > todo_groups.version)
                `, [g.uuid, getMappedId(g.user_id), g.name, g.is_expanded, g.is_deleted, g.version, g.created_at, g.updated_at]);
            }
        }

        // Todo Tags (关联关系) - 🚀 核心修复：补全待办标签同步
        if (payload.todo_tags) {
            mergedCount += payload.todo_tags.length;
            for (const tt of payload.todo_tags) {
                await dbRun(`
                    INSERT INTO todo_tags (todo_uuid, tag_uuid, is_deleted, updated_at)
                    VALUES (?,?,?,?)
                        ON CONFLICT(todo_uuid, tag_uuid) DO UPDATE SET
                        is_deleted=excluded.is_deleted, updated_at=excluded.updated_at
                                             WHERE excluded.updated_at > todo_tags.updated_at
                `, [tt.todo_uuid, tt.tag_uuid, tt.is_deleted, tt.updated_at]);
            }
        }

        // Countdowns
        if (payload.countdowns) {
            mergedCount += payload.countdowns.length;
            for (const c of payload.countdowns) {
                if (!c.uuid) continue;
                await dbRun(`
                    INSERT INTO countdowns (uuid, user_id, title, target_time, is_deleted, version, device_id, created_at, updated_at)
                    VALUES (?,?,?,?,?,?,?,?,?)
                        ON CONFLICT(uuid) DO UPDATE SET
                        title=excluded.title, target_time=excluded.target_time, is_deleted=excluded.is_deleted, version=excluded.version, device_id=excluded.device_id, updated_at=excluded.updated_at
                                             WHERE excluded.updated_at > countdowns.updated_at OR (excluded.updated_at = countdowns.updated_at AND excluded.version > countdowns.version)
                `, [c.uuid, getMappedId(c.user_id), c.title, c.target_time, c.is_deleted, c.version, c.device_id, c.created_at, c.updated_at]);
            }
        }

        // Time Logs
        if (payload.time_logs) {
            mergedCount += payload.time_logs.length;
            for (const l of payload.time_logs) {
                if (!l.uuid) continue;
                await dbRun(`
                    INSERT INTO time_logs (uuid, user_id, title, tag_uuids, start_time, end_time, remark, is_deleted, version, device_id, created_at, updated_at)
                    VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
                        ON CONFLICT(uuid) DO UPDATE SET
                        title=excluded.title, tag_uuids=excluded.tag_uuids, start_time=excluded.start_time, end_time=excluded.end_time, remark=excluded.remark, is_deleted=excluded.is_deleted, version=excluded.version, device_id=excluded.device_id, updated_at=excluded.updated_at
                                             WHERE excluded.updated_at > time_logs.updated_at OR (excluded.updated_at = time_logs.updated_at AND excluded.version > time_logs.version)
                `, [l.uuid, getMappedId(l.user_id), l.title, l.tag_uuids, l.start_time, l.end_time, l.remark, l.is_deleted, l.version, l.device_id, l.created_at, l.updated_at]);
            }
        }

        // Pomodoro Records
        if (payload.pomodoro_records) {
            mergedCount += payload.pomodoro_records.length;
            for (const p of payload.pomodoro_records) {
                if (!p.uuid) continue;
                await dbRun(`
                    INSERT INTO pomodoro_records (uuid, user_id, todo_uuid, start_time, end_time, planned_duration, actual_duration, status, device_id, is_deleted, version, created_at, updated_at)
                    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
                        ON CONFLICT(uuid) DO UPDATE SET
                        todo_uuid=excluded.todo_uuid, start_time=excluded.start_time, end_time=excluded.end_time, planned_duration=excluded.planned_duration, actual_duration=excluded.actual_duration, status=excluded.status, device_id=excluded.device_id, is_deleted=excluded.is_deleted, version=excluded.version, updated_at=excluded.updated_at
                                             WHERE excluded.updated_at > pomodoro_records.updated_at OR (excluded.updated_at = pomodoro_records.updated_at AND excluded.version > pomodoro_records.version)
                `, [p.uuid, getMappedId(p.user_id), p.todo_uuid, p.start_time, p.end_time, p.planned_duration, p.actual_duration, p.status, p.device_id, p.is_deleted, p.version, p.created_at, p.updated_at]);
            }
        }

        // Pomodoro Tags
        if (payload.pomodoro_tags) {
            for (const p of payload.pomodoro_tags) {
                if (!p.uuid) continue;
                await dbRun(`
                    INSERT INTO pomodoro_tags (uuid, user_id, name, color, is_deleted, version, created_at, updated_at)
                    VALUES (?,?,?,?,?,?,?,?)
                        ON CONFLICT(uuid) DO UPDATE SET
                        name=excluded.name, color=excluded.color, is_deleted=excluded.is_deleted, version=excluded.version, updated_at=excluded.updated_at
                                             WHERE excluded.updated_at > pomodoro_tags.updated_at OR (excluded.updated_at = pomodoro_tags.updated_at AND excluded.version > pomodoro_tags.version)
                `, [p.uuid, getMappedId(p.user_id), p.name, p.color, p.is_deleted, p.version, p.created_at, p.updated_at]);
            }
        }

        // Pomodoro Settings - 🚀 核心修复：补全专注设置同步
        if (payload.pomodoro_settings) {
            for (const s of payload.pomodoro_settings) {
                await dbRun(`
                    INSERT INTO pomodoro_settings (user_id, default_focus_duration, default_rest_duration, default_loop_count, timer_mode, updated_at)
                    VALUES (?,?,?,?,?,?)
                        ON CONFLICT(user_id) DO UPDATE SET
                        default_focus_duration=excluded.default_focus_duration, default_rest_duration=excluded.default_rest_duration, default_loop_count=excluded.default_loop_count, timer_mode=excluded.timer_mode, updated_at=excluded.updated_at
                                             WHERE excluded.updated_at > pomodoro_settings.updated_at
                `, [getMappedId(s.user_id), s.default_focus_duration, s.default_rest_duration, s.default_loop_count, s.timer_mode, s.updated_at]);
            }
        }

        // Courses - 🚀 核心修复：补全课程表同步
        if (payload.courses) {
            for (const c of payload.courses) {
                // 课程表逻辑：如果没有稳定 UUID，则依赖复合键判断，或直接插入新记录（如果云端拉取的 ID 已经是唯一的）
                // 这里的逻辑参考 full_sync_to_cf.js 的清洗逻辑
                await dbRun(`
                    INSERT INTO courses (user_id, semester, course_name, room_name, teacher_name, start_time, end_time, weekday, week_index, lesson_type, is_deleted, created_at, updated_at)
                    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
                `, [getMappedId(c.user_id), c.semester, c.course_name, c.room_name, c.teacher_name, c.start_time, c.end_time, c.weekday, c.week_index, c.lesson_type, c.is_deleted, c.created_at, c.updated_at]);
            }
        }

        // Screen Time Logs
        if (payload.screen_time_logs) {
            for (const s of payload.screen_time_logs) {
                await dbRun(`
                    INSERT INTO screen_time_logs (user_id, device_name, record_date, app_name, duration, updated_at)
                    VALUES (?,?,?,?,?,?)
                        ON CONFLICT(user_id, device_name, record_date, app_name) DO UPDATE SET
                        duration=excluded.duration, updated_at=excluded.updated_at
                                                                                    WHERE excluded.updated_at > screen_time_logs.updated_at
                `, [getMappedId(s.user_id), s.device_name, s.record_date, s.app_name, s.duration, s.updated_at]);
            }
        }

        await dbRun("COMMIT");
        log(`✅ LWW 同步完成！共拉取并安全处理了约 ${mergedCount} 条活跃业务记录。`);

    } catch (e) {
        await dbRun("ROLLBACK").catch(()=>{});
        errorLog("同步任务中断", e.message);
        // 🚀 核心修复：告诉系统失败了
        process.exit(1);
    } finally {
        db.close();
    }
}

cronLwwSync();