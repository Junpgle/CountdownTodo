const sqlite3 = require('sqlite3').verbose();
const path = require('path');
const https = require('https');

require('dotenv').config({ path: path.join(__dirname, '.env') });

const dbPath = path.join(__dirname, 'database.db');
const db = new sqlite3.Database(dbPath);

const CF_URL = "https://mathquiz.junpgle.me/api/admin/s2s_receive_merge";
const API_SECRET = process.env.API_SECRET;

// 🚀 分批配置：每批次发送 300 条
const BATCH_SIZE = 300;

const dbAll = (sql, params = []) => new Promise((res, rej) => db.all(sql, params, (err, rows) => err ? rej(err) : res(rows)));

/**
 * 🚀 深度数据清洗与 Schema 补全
 */
function sanitize(obj, template = null) {
    if (Array.isArray(obj)) {
        return obj.map(item => sanitize(item, template));
    } else if (obj !== null && typeof obj === 'object') {
        const newObj = template ? { ...template } : {};
        for (const key in obj) {
            newObj[key] = sanitize(obj[key]);
        }
        for (const key in newObj) {
            if (newObj[key] === undefined) newObj[key] = null;
        }
        return newObj;
    }
    return obj === undefined ? null : obj;
}

/**
 * 🚀 执行单次分批发送
 */
async function postToCloudflare(payload) {
    return new Promise((resolve, reject) => {
        const dataString = JSON.stringify(payload, (key, value) => value === undefined ? null : value);
        const url = new URL(CF_URL);

        const options = {
            hostname: url.hostname,
            port: url.port || 443,
            path: url.pathname + url.search,
            method: 'POST',
            family: 4,
            rejectUnauthorized: false,
            timeout: 60000,
            headers: {
                'Content-Type': 'application/json',
                'User-Agent': 'MathQuiz-S2S-Client/1.0 (Aliyun Node.js Batch)',
                'x-admin-secret': API_SECRET,
                'Content-Length': Buffer.byteLength(dataString)
            }
        };

        const req = https.request(options, (res) => {
            let body = '';
            res.on('data', chunk => body += chunk);
            res.on('end', () => {
                try {
                    const parsed = JSON.parse(body);
                    if (res.statusCode >= 200 && res.statusCode < 300 && parsed.success) {
                        resolve(parsed);
                    } else {
                        reject(new Error(`远端拒绝: ${JSON.stringify(parsed)}`));
                    }
                } catch (e) {
                    reject(new Error(`解析失败: ${body}`));
                }
            });
        });

        req.on('timeout', () => { req.destroy(); reject(new Error('超时 (>60s)')); });
        req.on('error', (e) => reject(e));
        req.write(dataString);
        req.end();
    });
}

async function safeMergeSync() {
    // 🚀 计算增量切断时间（7天前）
    const cutoffTime = Date.now() - (7 * 24 * 60 * 60 * 1000);

    console.log(`\n[${new Date().toISOString()}] 🚨 开始强效分批同步 (Aliyun -> Cloudflare)...`);
    console.log(`[未来保障] 课程表已加入 7 天增量筛选，配合分批机制应对大数据挑战。`);

    try {
        const templates = {
            user: { id: null, username: "", email: "", password_hash: "", tier: null, avatar_url: null, semester_start: null, semester_end: null, created_at: null, updated_at: null, version: 1 },
            todo: { uuid: null, user_id: null, content: "", is_completed: 0, is_deleted: 0, version: 1, device_id: null, created_at: null, updated_at: null, due_date: null, created_date: null, recurrence: 0, custom_interval_days: null, recurrence_end_date: null, remark: null, group_id: null },
            todo_group: { uuid: null, user_id: null, name: "", is_expanded: 0, is_deleted: 0, version: 1, created_at: null, updated_at: null },
            countdown: { uuid: null, user_id: null, title: "", target_time: null, is_deleted: 0, version: 1, device_id: null, created_at: null, updated_at: null },
            timeLog: { uuid: null, user_id: null, title: "", tag_uuids: "[]", start_time: null, end_time: null, remark: null, is_deleted: 0, version: 1, device_id: null, created_at: null, updated_at: null },
            pomoRecord: { uuid: null, user_id: null, todo_uuid: null, start_time: null, end_time: null, planned_duration: 0, actual_duration: 0, status: "completed", device_id: null, is_deleted: 0, version: 1, created_at: null, updated_at: null },
            todoTag: { todo_uuid: null, tag_uuid: null, is_deleted: 0, updated_at: null, version: 1 },
            screenTime: { user_id: null, device_name: "", record_date: "", app_name: "", duration: 0, updated_at: null },
            course: { user_id: null, semester: "default", course_name: "", room_name: "", teacher_name: "", start_time: null, end_time: null, weekday: null, week_index: null, lesson_type: null, is_deleted: 0, created_at: null, updated_at: null, date: "" }
        };

        const userMappingList = sanitize(await dbAll(`SELECT id, username, email, password_hash, avatar_url, semester_start, semester_end, created_at, updated_at, version FROM users`), templates.user);

        const userFilter = "CAST(user_id AS INTEGER) IN (SELECT id FROM users)";
        const cutoffStr = new Date(cutoffTime).toISOString().replace('T', ' ').split('.')[0];

        // 🚀 核心优化：课程表也只查询最近 7 天内变动的，并在本地完成最新记录提取
        const incrementalCourses = await dbAll(`
            SELECT * FROM courses 
            WHERE id IN (
                SELECT MAX(id) FROM courses 
                WHERE ${userFilter} AND (updated_at > ? OR created_at > ?)
                GROUP BY user_id, semester, week_index, weekday, start_time
            )
        `, [cutoffTime, cutoffTime]);

        const allTables = {
            // ── 增量同步区 (筛选最近 7 天) ──
            todos: { data: await dbAll(`SELECT * FROM todos WHERE (updated_at > ? OR created_at > ?) AND ${userFilter}`, [cutoffTime, cutoffTime]), template: templates.todo },
            todo_groups: { data: await dbAll(`SELECT * FROM todo_groups WHERE (updated_at > ? OR created_at > ?) AND ${userFilter}`, [cutoffTime, cutoffTime]), template: templates.todo_group },
            countdowns: { data: await dbAll(`SELECT * FROM countdowns WHERE (updated_at > ? OR created_at > ?) AND ${userFilter}`, [cutoffTime, cutoffTime]), template: templates.countdown },
            time_logs: { data: await dbAll(`SELECT * FROM time_logs WHERE (updated_at > ? OR created_at > ?) AND ${userFilter}`, [cutoffTime, cutoffTime]), template: templates.timeLog },
            pomodoro_records: { data: await dbAll(`SELECT * FROM pomodoro_records WHERE (updated_at > ? OR created_at > ?) AND ${userFilter}`, [cutoffTime, cutoffTime]), template: templates.pomoRecord },
            todo_tags: { data: await dbAll(`SELECT * FROM todo_tags WHERE updated_at > ? AND todo_uuid IN (SELECT uuid FROM todos)`, [cutoffTime]), template: templates.todoTag },
            screen_time_logs: {
                data: await dbAll(`SELECT * FROM screen_time_logs WHERE (updated_at > ? OR updated_at > ?) AND ${userFilter}`, [cutoffTime, cutoffStr]),
                template: templates.screenTime
            },
            courses: { data: incrementalCourses, template: templates.course },

            // ── 全量同步区 (数据量通常较小且稳定) ──
            pomodoro_tags: { data: await dbAll(`SELECT * FROM pomodoro_tags WHERE ${userFilter}`), template: null },
            pomodoro_settings: { data: await dbAll(`SELECT * FROM pomodoro_settings WHERE ${userFilter}`), template: null },
            leaderboard: { data: await dbAll(`SELECT * FROM leaderboard WHERE ${userFilter}`), template: null },
            app_name_mappings: { data: await dbAll("SELECT * FROM app_name_mappings"), template: null }
        };

        let totalSynced = 0;

        console.log(`[${new Date().toISOString()}] 👤 正在预同步 ${userMappingList.length} 个用户账号...`);
        await postToCloudflare({ users: userMappingList });

        for (const [tableName, config] of Object.entries(allTables)) {
            const records = config.data;
            if (!records || records.length === 0) continue;

            console.log(`[${new Date().toISOString()}] 📦 处理表 [${tableName}]: ${records.length} 条记录...`);

            for (let i = 0; i < records.length; i += BATCH_SIZE) {
                const chunk = records.slice(i, i + BATCH_SIZE);
                const sanitizedChunk = sanitize(chunk, config.template);

                const payload = {
                    users: userMappingList,
                    [tableName]: sanitizedChunk
                };

                const progress = `(${i + sanitizedChunk.length}/${records.length})`;
                process.stdout.write(`   🚀 发送 ${tableName} 分批 ${progress}... `);

                const result = await postToCloudflare(payload);
                totalSynced += (result.synced_records || 0);

                process.stdout.write(`✅ 成功\n`);
            }
        }

        console.log(`\n[${new Date().toISOString()}] ✨ 同步任务圆满结束！共处理了 ${totalSynced} 条变动。`);

    } catch (e) {
        console.error(`\n[${new Date().toISOString()}] ❌ 过程异常中断:`, e.message);
        process.exit(1);
    } finally {
        db.close();
    }
}

safeMergeSync();