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
                'User-Agent': 'MathQuiz-S2S-Client/1.0 (Aliyun Node.js CourseOnly)',
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

    console.log(`\n[${new Date().toISOString()}] 🚨 开始【仅课表】专项同步 (Aliyun -> Cloudflare)...`);

    try {
        const templates = {
            user: { id: null, username: "", email: "", password_hash: "", tier: null, avatar_url: null, semester_start: null, semester_end: null, created_at: null, updated_at: null, version: 1 },
            course: { user_id: null, semester: "default", course_name: "", room_name: "", teacher_name: "", start_time: null, end_time: null, weekday: null, week_index: null, lesson_type: null, is_deleted: 0, created_at: null, updated_at: null, date: "" }
        };

        // 1. 依然需要获取用户映射表（确保课表记录能正确挂载到云端用户 ID 上）
        const userMappingList = sanitize(await dbAll(`SELECT id, username, email, password_hash, avatar_url, semester_start, semester_end, created_at, updated_at, version FROM users`), templates.user);

        const userFilter = "CAST(user_id AS INTEGER) IN (SELECT id FROM users)";

        // 2. 提取课表数据（保留了 7 天增量，如果你想全量同步，可以把 WHERE 里的时间过滤去掉）
        const incrementalCourses = await dbAll(`
            SELECT * FROM courses 
            WHERE id IN (
                SELECT MAX(id) FROM courses 
                WHERE ${userFilter} AND (updated_at > ? OR created_at > ?)
                GROUP BY user_id, semester, week_index, weekday, start_time
            )
        `, [cutoffTime, cutoffTime]);

        // 🚀 allTables 列表现在极度精简，只剩下 courses
        const allTables = {
            courses: { data: incrementalCourses, template: templates.course }
        };

        let totalSynced = 0;

        // 3. 预同步用户信息（建立 ID 映射基础）
        console.log(`[${new Date().toISOString()}] 👤 正在预同步用户信息以建立外键关联...`);
        await postToCloudflare({ users: userMappingList });

        // 4. 循环同步课表
        for (const [tableName, config] of Object.entries(allTables)) {
            const records = config.data;
            if (!records || records.length === 0) {
                console.log(`[${new Date().toISOString()}] ℹ️ 表 [${tableName}] 最近 7 天没有变动记录。`);
                continue;
            }

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

        console.log(`\n[${new Date().toISOString()}] ✨ 专项同步任务圆满结束！`);

    } catch (e) {
        console.error(`\n[${new Date().toISOString()}] ❌ 过程异常中断:`, e.message);
        process.exit(1);
    } finally {
        db.close();
    }
}

safeMergeSync();