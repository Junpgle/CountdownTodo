const sqlite3 = require('sqlite3').verbose();
const crypto = require('crypto');

// 🛡️ 目标数据库：必须与 server.js 中的隔离文件名一致
const db = new sqlite3.Database('./database_debug.db');

function hashPassword(password) {
    return crypto.createHash('sha256').update(password).digest('hex');
}

const dbRun = (sql, params = []) => new Promise((res, rej) => db.run(sql, params, (err) => err ? rej(err) : res()));
const dbGet = (sql, params = []) => new Promise((res, rej) => db.get(sql, params, (err, row) => err ? rej(err) : res(row)));
const dbAll = (sql, params = []) => new Promise((res, rej) => db.all(sql, params, (err, rows) => err ? rej(err) : res(rows)));

async function seed() {
    console.log("🚀 [Seeder] 正在初始化多用户测试环境...");

    try {
        // 1. 初始化表结构 (防崩溃)
        await dbRun(`CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT, email TEXT UNIQUE, password_hash TEXT, tier TEXT DEFAULT 'free', created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)`);
        await dbRun(`CREATE TABLE IF NOT EXISTS todo_groups (id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT, user_id INTEGER, name TEXT, is_deleted INTEGER DEFAULT 0, updated_at INTEGER, created_at INTEGER, UNIQUE(user_id, uuid))`);
        await dbRun(`CREATE TABLE IF NOT EXISTS todos (id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT, user_id INTEGER, content TEXT, is_completed INTEGER DEFAULT 0, is_deleted INTEGER DEFAULT 0, version INTEGER DEFAULT 1, updated_at INTEGER, created_at INTEGER, group_id TEXT, team_uuid TEXT, UNIQUE(user_id, uuid))`);
        await dbRun(`CREATE TABLE IF NOT EXISTS teams (id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT UNIQUE, name TEXT, creator_id INTEGER, created_at INTEGER)`);
        await dbRun(`CREATE TABLE IF NOT EXISTS team_members (team_uuid TEXT, user_id INTEGER, role INTEGER DEFAULT 1, joined_at INTEGER, PRIMARY KEY(team_uuid, user_id))`);

        // 2. 注入多账号
        const users = [
            { name: '测试选手', email: 'test@test.com', tier: 'Pro' },
            { name: '摸鱼专家', email: 'expert@test.com', tier: 'free' },
            { name: '超级大佬', email: 'boss@test.com', tier: 'ProMax' },
            { name: '测试用户1', email: 'test1@test.com', tier: 'ProMax' },
            { name: '测试用户2', email: 'test2@test.com', tier: 'ProMax' },
            { name: '测试用户3', email: 'test3@test.com', tier: 'ProMax' },
            { name: '测试用户4', email: 'test4@test.com', tier: 'ProMax' }

        ];

        const passHash = hashPassword('123456');
        for (const u of users) {
            await dbRun(`INSERT OR IGNORE INTO users (username, email, password_hash, tier) VALUES (?, ?, ?, ?)`, 
                [u.name, u.email, passHash, u.tier]);
        }
        
        const allUsers = await dbAll("SELECT id, username FROM users WHERE email LIKE '%@test.com'");
        console.log(`✅ [Users] 已注入 ${allUsers.length} 个测试账号 (ID: ${allUsers.map(u => u.id).join(', ')})`);

        // // 3. 创建共享团队
        // const creator = allUsers.find(u => u.username === '测试选手');
        // const teamUuid = 'debug-shared-squad';
        // await dbRun(`INSERT OR REPLACE INTO teams (uuid, name, creator_id, created_at) VALUES (?, ?, ?, ?)`,
        //     [teamUuid, '🌟 跨界开发协作组', creator.id, Date.now()]);

        // // 4. 将所有用户加入团队
        // for (const u of allUsers) {
        //     const role = (u.id === creator.id) ? 0 : 1; // 创始人设为 Admin
        //     await dbRun(`INSERT OR REPLACE INTO team_members (team_uuid, user_id, role, joined_at) VALUES (?, ?, ?, ?)`,
        //         [teamUuid, u.id, role, Date.now()]);
        //
        //     // 为每个用户创建一个个人文件夹
        //     const gUuid = `folder-${u.id}`;
        //     await dbRun(`INSERT OR REPLACE INTO todo_groups (uuid, user_id, name, updated_at, created_at) VALUES (?, ?, ?, ?, ?)`,
        //         [gUuid, u.id, `📂 ${u.username} 的私货`, Date.now(), Date.now()]);
        //
        //     // 为每个用户创建一个属于团队的待办
        //     await dbRun(`INSERT OR REPLACE INTO todos (uuid, user_id, content, is_completed, updated_at, created_at, team_uuid) VALUES (?, ?, ?, ?, ?, ?, ?)`,
        //         [`todo-team-${u.id}`, u.id, `📣 来自 ${u.username} 的进度汇报`, 0, Date.now(), Date.now(), teamUuid]);
        // }
        //
        // console.log(`✅ [Collaboration] 多人协作环境已就绪。所有账号密码均为 123456`);
        // console.log("✨ [Done] 数据注入成功！");

    } catch (err) {
        console.error("❌ [Error] 注入失败:", err);
    } finally {
        db.close();
    }
}

seed();
