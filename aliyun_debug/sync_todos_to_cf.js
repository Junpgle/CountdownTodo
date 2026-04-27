const sqlite3 = require('sqlite3').verbose();
const path = require('path');
const https = require('https');

require('dotenv').config({ path: path.join(__dirname, '.env') });

const dbPath = path.join(__dirname, 'database.db');
const db = new sqlite3.Database(dbPath);

const CF_URL = "https://mathquiz.junpgle.me/api/admin/s2s_receive_merge";
const API_SECRET = process.env.API_SECRET;
const BATCH_SIZE = 300;

const dbAll = (sql, params = []) => new Promise((res, rej) => db.all(sql, params, (err, rows) => err ? rej(err) : res(rows)));

function sanitize(obj, template = null) {
    if (Array.isArray(obj)) return obj.map(item => sanitize(item, template));
    if (obj !== null && typeof obj === 'object') {
        const newObj = template ? { ...template } : {};
        for (const key in obj) newObj[key] = (obj[key] === undefined ? null : obj[key]);
        return newObj;
    }
    return obj === undefined ? null : obj;
}

async function postToCloudflare(payload) {
    return new Promise((resolve, reject) => {
        const dataString = JSON.stringify(payload);
        const url = new URL(CF_URL);
        const options = {
            hostname: url.hostname,
            path: url.pathname,
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'x-admin-secret': API_SECRET,
                'Content-Length': Buffer.byteLength(dataString)
            }
        };
        const req = https.request(options, (res) => {
            let body = '';
            res.on('data', chunk => body += chunk);
            res.on('end', () => resolve(JSON.parse(body)));
        });
        req.on('error', (e) => reject(e));
        req.write(dataString);
        req.end();
    });
}

async function repairTodosOnly() {
    console.log(`\n🚀 开始单向同步修复: Todos 表 (Aliyun -> Cloudflare)`);
    try {
        const todoTemplate = { 
            uuid: null, user_id: null, content: "", is_completed: 0, is_deleted: 0, 
            version: 1, device_id: null, created_at: null, updated_at: null, 
            due_date: null, created_date: null, recurrence: 0, 
            custom_interval_days: null, recurrence_end_date: null, 
            remark: null, group_id: null 
        };

        // 1. 获取所有用户映射 (必要的前提)
        const users = await dbAll(`SELECT id, username, email, password_hash, tier, avatar_url, semester_start, semester_end, created_at FROM users`);
        console.log(`👤 已加载 ${users.length} 个用户特征。`);

        // 2. 获取所有的 Todos (不设时间限制，全量扫描)
        const allTodos = await dbAll(`SELECT * FROM todos WHERE user_id IN (SELECT id FROM users)`);
        console.log(`📦 待处理任务总数: ${allTodos.length} 条。`);

        // 3. 分批发送
        for (let i = 0; i < allTodos.length; i += BATCH_SIZE) {
            const chunk = sanitize(allTodos.slice(i, i + BATCH_SIZE), todoTemplate);
            const payload = { users, todos: chunk };
            
            process.stdout.write(`   📡 发送分批 [${i + chunk.length}/${allTodos.length}]... `);
            const res = await postToCloudflare(payload);
            
            if (res.success) process.stdout.write(`✅ 成功 (云端处理记录数: ${res.synced_records})\n`);
            else process.stdout.write(`❌ 失败: ${res.error}\n`);
        }

        console.log(`\n✨ 任务修复完成！`);
    } catch (e) {
        console.error(`\n❌ 同步失败:`, e.message);
    } finally {
        db.close();
    }
}

repairTodosOnly();
