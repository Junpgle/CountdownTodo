const express = require('express');
console.log('\n\n🚀🚀🚀 [代码部署检查] 目标版本 V2026-04-18-BULLS-EYE 正在启动... 🚀🚀🚀\n\n');
const sqlite3 = require('sqlite3').verbose();
const cors = require('cors');
const bodyParser = require('body-parser');
const crypto = require('crypto');
const http = require('http');
const https = require('https');
const WebSocket = require('ws');

require('dotenv').config(); // 建议使用 dotenv 管理环境变量

const app = express();
const port = 8084;
const API_SECRET = process.env.API_SECRET;
const RESEND_API_KEY = process.env.RESEND_API_KEY || "";

// 🚀 核心：用 http 模块包装 express，由外部接管升级请求
const server = http.createServer(app);
const wss = new WebSocket.Server({ noServer: true });

// 内存中的专注状态缓存（不存数据库）
// 内存中的连接状态管理
// 结构: Map<RoomKey, Set<WebSocket>>，RoomKey 可能是 'user:${id}' 或 'team:${uuid}'
const roomManager = new Map();
// 反向查找：Map<WebSocket, Set<RoomKey>>
const clientSubscriptions = new Map();

function joinRoom(ws, roomKey) {
    if (!roomManager.has(roomKey)) roomManager.set(roomKey, new Set());
    roomManager.get(roomKey).add(ws);

    if (!clientSubscriptions.has(ws)) clientSubscriptions.set(ws, new Set());
    clientSubscriptions.get(ws).add(roomKey);
}

function leaveAllRooms(ws) {
    const rooms = clientSubscriptions.get(ws);
    if (rooms) {
        for (const roomKey of rooms) {
            const room = roomManager.get(roomKey);
            if (room) {
                room.delete(ws);
                if (room.size === 0) roomManager.delete(roomKey);
            }
        }
        clientSubscriptions.delete(ws);
    }

    // 🚀 核心修复：清理该设备启动的专注状态，防止内存泄漏 (GC 问题主因)
    const deviceId = ws.deviceId;
    const userId = ws.userId;

    if (deviceId) {
        if (userId) {
            const userState = userFocusStates.get(userId);
            if (userState && userState.sourceDevice === deviceId) {
                userFocusStates.delete(userId);
                console.log(`${getTime()} [GC清理] 已清理用户 ${userId} 设备 ${deviceId} 的残留个人专注状态`);
            }
        }

        // 团队状态清理
        for (const [teamUuid, state] of teamFocusStates.entries()) {
            if (state.sourceDevice === deviceId) {
                teamFocusStates.delete(teamUuid);
                console.log(`${getTime()} [GC清理] 已清理团队 ${teamUuid} 设备 ${deviceId} 的残留团队专注状态`);
            }
        }
    }
}

function broadcastToRoom(roomKey, payload, excludeWs = null) {
    const room = roomManager.get(roomKey);
    if (!room) {
        console.log(`${getTime()} [WS广播跳过] 房间 ${roomKey} 不存在或无成员`);
        return;
    }
    let message;
    try {
        message = JSON.stringify(payload);
        if (message.length > 65536) {
            console.warn(`${getTime()} [WS广播跳过] 房间: ${roomKey}, 动作: ${payload.action}, payload 过大: ${message.length}`);
            return;
        }
    } catch (e) {
        console.error(`${getTime()} [WS广播失败] payload 无法序列化: ${e.message}`);
        return;
    }
    let count = 0;
    for (const client of room) {
        if (client !== excludeWs && client.readyState === WebSocket.OPEN) {
            client.send(message);
            count++;
        }
    }
    console.log(`${getTime()} [WS广播成功] 房间: ${roomKey}, 动作: ${payload.action}, 已发送设备数: ${count}`);
}

// 获取用户所属的所有房间 Key
async function getUserRoomKeys(userId) {
    const keys = [`user:${userId}`];
    try {
        const teams = await dbAll("SELECT team_uuid FROM team_members WHERE user_id = ?", [userId]);
        for (const t of teams) keys.push(`team:${t.team_uuid}`);
    } catch (e) {
        console.error("Failed to get team rooms:", e);
    }
    return keys;
}

// 专注状态管理需适配多用户（暂存内存）
const teamFocusStates = new Map(); // team_uuid -> focusState
const userFocusStates = new Map(); // user_id -> focusState

let cachedManifest = null;

// --- 基础辅助函数 ---
function getTime() {
    const d = new Date();
    return `[${d.toLocaleString('zh-CN', { hour12: false }).replace(/\//g, '-')}]`;
}

// ==========================================
// 🚀 模块: App 更新检测与在线统计
// ==========================================
const MANIFEST_URL = "https://raw.githubusercontent.com/Junpgle/CountdownTodo/refs/heads/master/update_manifest.json";

let manifestFailCount = 0;
function fetchManifest() {
    // 🚀 核心优化：如果连续失败超过 5 次且内存紧张，暂时停止检测，防止僵尸请求堆积
    if (manifestFailCount > 5) {
        const usage = process.memoryUsage().heapUsed / 1024 / 1024;
        if (usage > 12) { // 如果内存占用超过 12MB 且一直失败，跳过此次请求
            console.log(`${getTime()} [更新模块] 内存紧张且持续超时，跳过此次检测以保护 GC`);
            return;
        }
    }

    const req = https.get(MANIFEST_URL, (res) => {
        let data = '';
        res.on('data', (chunk) => { data += chunk; });
        res.on('end', () => {
            try {
                if (res.statusCode === 200) {
                    cachedManifest = JSON.parse(data);
                    manifestFailCount = 0; // 重置失败计数
                    console.log(`${getTime()} [更新模块] 成功获取最新版本: v${cachedManifest.version_name}`);
                }
            } catch (e) {
                console.error(`${getTime()} [更新模块] 解析失败:`, e.message);
            }
        });
    }).on('error', (e) => {
        manifestFailCount++;
        console.error(`${getTime()} [更新模块] 请求失败 (${manifestFailCount}):`, e.message);
    });

    // 🚀 关键：增加 10 秒强制超时，防止在国内环境下 read ETIMEDOUT 导致 Socket 长期挂起
    req.setTimeout(10000, () => {
        req.destroy();
        manifestFailCount++;
    });
}

function hasNewVersion(latest, current) {
    try {
        const cleanLatest = latest.split('+')[0].split('-')[0];
        const cleanCurrent = current.split('+')[0].split('-')[0];
        const v1 = cleanLatest.split('.').map(Number);
        const v2 = cleanCurrent.split('.').map(Number);
        const len = Math.max(v1.length, v2.length);
        for (let i = 0; i < len; i++) {
            const p1 = v1[i] || 0;
            const p2 = v2[i] || 0;
            if (p1 > p2) return true;
            if (p1 < p2) return false;
        }
    } catch (e) {
    }
    return false;
}

// 提取核心统计逻辑供接口和定时任务公用
function getOnlineStatsData() {
    const stats = {};
    let totalOnline = 0;

    // 🚀 优化：直接遍历 roomManager，减少中间大对象生成
    if (typeof roomManager !== 'undefined') {
        const seenClients = new Set();
        for (const room of roomManager.values()) {
            for (const client of room) {
                if (seenClients.has(client)) continue;
                seenClients.add(client);
                
                const p = client.platform || 'unknown', v = client.clientVersion || 'unknown';
                if (!stats[p]) stats[p] = {};
                if (!stats[p][v]) stats[p][v] = 0;
                stats[p][v]++;
                totalOnline++;
            }
        }
        seenClients.clear(); // 显式提示 GC
    }

    return { stats, totalOnline };
}

function printOnlineStats() {
    const { stats, totalOnline } = getOnlineStatsData();
    if (totalOnline > 0) {
        console.log(`\n${getTime()} 📊 === 当前在线设备分布统计 === 📊`);
        console.log(`${getTime()} 总计在线: ${totalOnline} 台设备`);
        for (const [platform, versions] of Object.entries(stats)) {
            console.log(`${getTime()} 💻 平台 [${platform}]:`);
            const sortedVersions = Object.keys(versions).sort((a, b) => b.localeCompare(a));
            for (const v of sortedVersions) console.log(`${getTime()}    ├─ v${v.padEnd(6, ' ')} : ${versions[v]} 台`);
        }
    }
}

fetchManifest();
setInterval(fetchManifest, 10 * 60 * 1000);
setInterval(printOnlineStats, 15 * 60 * 1000);

// 🚀 核心修复：定时清理过期专注状态（超过 12 小时无人更新视为僵尸状态）
setInterval(() => {
    const now = Date.now();
    const expiry = 12 * 60 * 60 * 1000;
    
    let count = 0;
    for (const [key, state] of userFocusStates.entries()) {
        if (now - (state.timestamp || 0) > expiry) {
            userFocusStates.delete(key);
            count++;
        }
    }
    for (const [key, state] of teamFocusStates.entries()) {
        if (now - (state.timestamp || 0) > expiry) {
            teamFocusStates.delete(key);
            count++;
        }
    }
    if (count > 0) console.log(`${getTime()} [GC定期清理] 已清理 ${count} 条过期的僵尸专注状态`);
}, 60 * 60 * 1000); // 每小时执行一次

// ==========================================
// 🌐 Express 中间件与数据库封装
// ==========================================
app.use(cors({
    origin: '*',
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS', 'PATCH'],
    allowedHeaders: ['Content-Type', 'x-user-id', 'Authorization']
}));
app.use(bodyParser.json({ limit: '10mb' }));

// 🚀 健康检查根路由：为 ApiService.ping() 提供支持
app.get('/', (req, res) => res.json({ status: 'online', name: 'Uni-Sync API', version: '4.0.0' }));

// 🚀 核心隔离：调试环境强制使用独立的数据库文件，防止污染生产环境数据
const db = new sqlite3.Database('./database_debug.db', (err) => {
    if (!err) {
        // 🚀 性能优化：启用 WAL 模式和合理的缓存设置，减少磁盘 I/O 阻塞引发的 GC 压力
        db.run("PRAGMA journal_mode = WAL");
        db.run("PRAGMA synchronous = NORMAL");
        db.run("PRAGMA cache_size = -2000"); // 限制 2MB 缓存，保护微小内存环境
    }
});
const dbRun = (sql, params = []) => new Promise((res, rej) => db.run(sql, params, function (err) {
    err ? rej(err) : res(this);
}));
const dbAll = (sql, params = []) => new Promise((res, rej) => db.all(sql, params, (err, rows) => err ? rej(err) : res(rows)));
const dbGet = (sql, params = []) => new Promise((res, rej) => db.get(sql, params, (err, row) => err ? rej(err) : res(row)));

// --- 数据库并发锁 (防止 SQLite 事务冲突) ---
const dbLock = {
    _queue: [],
    _busy: false,
    async acquire() {
        if (!this._busy) {
            this._busy = true;
            return this._release.bind(this);
        }
        return new Promise(resolve => {
            this._queue.push(resolve);
        });
    },
    _release() {
        if (this._queue.length > 0) {
            const nextResolve = this._queue.shift();
            nextResolve(this._release.bind(this));
        } else {
            this._busy = false;
        }
    }
};

// ==========================================
// 🛡️ 核心机制对齐：加密、鉴权、时间戳、限流
// ==========================================
const SYNC_LIMITS = { free: 500, Pro: 2000, ProMax: 5000, admin: 99999 };

function hashPassword(password) {
    return crypto.createHash('sha256').update(password).digest('hex');
}

function signToken(userId) {
    const hmac = crypto.createHmac('sha256', API_SECRET);
    hmac.update(userId.toString());
    return `${userId}.${hmac.digest('hex')}`;
}

const requireAuth = (req, res, next) => {
    const authHeader = req.headers['authorization'];
    if (!authHeader || !authHeader.startsWith("Bearer ")) return res.status(401).json({ error: "未授权" });
    const token = authHeader.substring(7);
    const parts = token.split('.');
    if (parts.length !== 2) return res.status(401).json({ error: "Token格式错误" });

    const userIdStr = parts[0];
    if (token === signToken(userIdStr)) {
        req.userId = parseInt(userIdStr, 10);
        return next();
    }
    return res.status(401).json({ error: "无效的Token" });
};

/**
 * 🚀 Uni-Sync 安全：PoW (工作量证明) 校验
 * 核心目的：防止自动化脚本刷接口
 */
function verifyPoW(challenge, nonce, difficulty = 4) {
    if (!challenge || !nonce) return false;
    const hash = crypto.createHash('sha256').update(challenge + nonce).digest('hex');
    // 检查前 difficulty 位是否全为 0
    return hash.startsWith('0'.repeat(difficulty));
}

function generateChallenge(userId) {
    // 🚀 Uni-Sync 安全加固：让难题仅在 5 分钟内有效
    const expiry = Date.now() + (5 * 60 * 1000);
    return userId + "_" + expiry + "_" + crypto.randomBytes(8).toString('hex');
}

/**
 * 校验逻辑
 */
function isChallengeValid(challenge, userId) {
    try {
        const parts = challenge.split('_');
        if (parts[0] !== userId.toString()) return false;
        if (Date.now() > parseInt(parts[1])) return false; // 已过期
        return true;
    } catch (_) { return false; }
}

function normalizeToMs(val) {
    if (val === null || val === undefined) return 0;
    if (typeof val === 'number') return Math.floor(val);
    if (typeof val === 'string') {
        const trimmed = val.trim();
        if (!trimmed) return 0;
        const n = Number(trimmed);
        if (!isNaN(n)) return Math.floor(n);
        const d = new Date(trimmed);
        if (!isNaN(d.getTime())) return d.getTime();
    }
    return 0;
}

function safeJsonParse(val, fallback = null) {
    if (val === null || val === undefined || val === '') return fallback;
    try {
        return typeof val === 'string' ? JSON.parse(val) : val;
    } catch (_) {
        return fallback;
    }
}

async function getAuditAccessScope(table, uuid) {
    try {
        return await dbGet(
            `SELECT team_uuid, user_id FROM audit_logs WHERE target_table = ? AND target_uuid = ? ORDER BY timestamp DESC LIMIT 1`,
            [table, uuid]
        );
    } catch (e) {
        console.error(`${getTime()} [审计访问范围查询失败]`, e.message);
        return null;
    }
}

async function assertAuditAccess(req, table, uuid) {
    const scope = await getAuditAccessScope(table, uuid);
    if (!scope) {
        return { ok: false, code: 404, error: '未找到该记录' };
    }

    if (scope.team_uuid) {
        const membership = await dbGet(
            'SELECT role FROM team_members WHERE team_uuid = ? AND user_id = ?',
            [scope.team_uuid, req.userId]
        );
        if (!membership) {
            return { ok: false, code: 403, error: '无权限访问该团队记录' };
        }
        return { ok: true, scope };
    }

    if (scope.user_id !== req.userId) {
        return { ok: false, code: 403, error: '无权限访问该个人记录' };
    }

    return { ok: true, scope };
}

function getChinaDateStr(nowMs) {
    const d = new Date(nowMs + 28800000);
    return d.toISOString().split('T')[0];
}

/**
 * 核心：智能冲突检测
 * 检测同一人在个人范围内，或同一团队内是否存在时间重叠
 */
async function checkItemConflict(item, userId) {
    const startTime = normalizeToMs(item.start_time || item.startTime || item.created_date || item.createdDate);
    const endTime = normalizeToMs(item.end_time || item.endTime || item.due_date || item.dueDate);
    const teamUuid = item.team_uuid || item.teamUuid;
    const itemUuid = item.uuid || item.id;

    if (!startTime || !endTime) return null;
    
    // 🚀 核心修复：全天任务不参与时间重叠检测
    const isAllDay = (item.is_all_day || item.isAllDay || (endTime - startTime >= 23.5 * 3600 * 1000)) ? 1 : 0;
    if (isAllDay) return null;

    // 团队内“单天时间冲突”改由客户端基于本地数据判定，服务端不再参与该类冲突检测。
    if (teamUuid) return null;

    let sql, params;
    // 个人范围内的冲突检测
    sql = `SELECT uuid, user_id, team_uuid, start_time, end_time, is_deleted, 'course' AS source_type, course_name as title FROM courses WHERE user_id = ? AND team_uuid IS NULL AND is_deleted = 0 AND ((start_time < ? AND end_time > ?) OR (start_time < ? AND end_time > ?) OR (start_time >= ? AND end_time <= ?)) AND uuid != ?
           UNION ALL
           SELECT uuid, user_id, team_uuid, start_time, end_time, is_deleted, 'pomodoro' AS source_type, '专注记录' as title FROM pomodoro_records WHERE user_id = ? AND team_uuid IS NULL AND is_deleted = 0 AND ((start_time < ? AND end_time > ?) OR (start_time < ? AND end_time > ?) OR (start_time >= ? AND end_time <= ?)) AND uuid != ?
           UNION ALL
           SELECT uuid, user_id, team_uuid, created_date as start_time, due_date as end_time, is_deleted, 'todo' AS source_type, content as title FROM todos WHERE user_id = ? AND team_uuid IS NULL AND is_deleted = 0 AND is_all_day = 0 AND ((created_date < ? AND due_date > ?) OR (created_date < ? AND due_date > ?) OR (created_date >= ? AND due_date <= ?)) AND uuid != ?
           LIMIT 1`;
    params = [
        userId, endTime, startTime, startTime, startTime, startTime, endTime, itemUuid,
        userId, endTime, startTime, startTime, startTime, startTime, endTime, itemUuid,
        userId, endTime, startTime, startTime, startTime, startTime, endTime, itemUuid
    ];

    try {
        const conflict = await dbGet(sql, params);
        if (conflict) {
            // 返回包含冲突源类型的详细信息
            return {
                ...conflict,
                conflict_type: 'schedule_overlap',
                message: `检测到时间重叠冲突 (${conflict.source_type}: ${conflict.uuid})`
            };
        }
        return null;
    } catch (e) {
        console.error("Conflict check error:", e);
        return null;
    }
}

async function enforceSyncLimit(userId, now) {
    const today = getChinaDateStr(now);
    try {
        const userRow = await dbGet("SELECT tier FROM users WHERE id = ?", [userId]);
        const tier = userRow ? userRow.tier : 'free';
        const limit = SYNC_LIMITS[tier] || SYNC_LIMITS.free;

        const record = await dbGet("SELECT * FROM sync_limits WHERE user_id = ? AND sync_date = ?", [userId, today]);

        if (!record) {
            await dbRun("INSERT OR REPLACE INTO sync_limits (user_id, sync_date, sync_count, last_sync_time) VALUES (?, ?, ?, ?)", [userId, today, 1, now]);
            return null;
        }

        if (record.last_sync_time && (now - parseInt(record.last_sync_time) < 3000)) return 'IGNORE';

        // 🚀 Uni-Sync 行为防御：禁止被封禁用户同步
        if (record.is_banned === 1) return 'BANNED';

        if (record.sync_count >= limit) {
            // 🚀 安全加固：如果超过限额两倍，自动触发熔断封禁
            if (record.sync_count >= limit * 2) {
                await dbRun("UPDATE sync_limits SET is_banned = 1 WHERE user_id = ? AND sync_date = ?", [userId, today]);
                return 'BANNED';
            }
            return `今日同步次数已达上限 (${limit}次)`;
        }

        await dbRun("UPDATE sync_limits SET sync_count = sync_count + 1, last_sync_time = ? WHERE user_id = ? AND sync_date = ?", [now, userId, today]);
        return null;
    } catch (e) {
        console.error("Sync Limit Error:", e.message);
        return null;
    }
}

/**
 * 🚀 Uni-Sync 核心：审计日志捕获器
 * 记录数据变动前后的 JSON 快照，支撑一键回滚
 */
function compactSnapshot(raw, tableName = '') {
    if (!raw || typeof raw !== 'object') return raw;

    const source = raw.conflict_data && typeof raw.conflict_data === 'string'
        ? { ...raw, conflict_data: undefined }
        : { ...raw };

    const commonKeys = [
        'uuid', 'id', 'user_id', 'team_uuid', 'team_name', 'creator_id', 'creator_name',
        'is_deleted', 'version', 'device_id', 'created_at', 'updated_at'
    ];
    const tableKeys = {
        todos: [
            'content', 'title', 'is_completed', 'due_date', 'created_date',
            'recurrence', 'custom_interval_days', 'recurrence_end_date',
            'remark', 'group_id', 'category_id', 'collab_type',
            'reminder_minutes', 'is_all_day'
        ],
        countdowns: ['title', 'target_time', 'is_completed'],
        todo_groups: ['name', 'is_expanded'],
        courses: [
            'semester', 'course_name', 'room_name', 'teacher_name', 'start_time',
            'end_time', 'weekday', 'week_index', 'lesson_type'
        ],
        pomodoro_tags: ['name', 'color'],
        pomodoro_records: [
            'todo_uuid', 'start_time', 'end_time', 'planned_duration',
            'actual_duration', 'status'
        ],
        time_logs: ['title', 'tag_uuids', 'start_time', 'end_time', 'remark']
    };

    const keys = [...commonKeys, ...(tableKeys[tableName] || [])];
    const compact = {};
    for (const key of keys) {
        if (Object.prototype.hasOwnProperty.call(source, key)) {
            let value = source[key];
            if (typeof value === 'string' && value.length > 4096) {
                value = value.slice(0, 4096);
            }
            compact[key] = value;
        }
    }
    return compact;
}

function safeSnapshotJson(raw, tableName = '') {
    if (!raw) return null;
    const compact = compactSnapshot(raw, tableName);
    const text = JSON.stringify(compact);
    if (text.length <= 32768) return text;
    return JSON.stringify({
        uuid: compact.uuid || compact.id || null,
        version: compact.version ?? null,
        updated_at: compact.updated_at ?? null,
        team_uuid: compact.team_uuid ?? null,
        content: compact.content || compact.title || compact.name || '',
        _truncated: true
    });
}

async function recordAuditLog({ team_uuid, user_id, target_table, target_uuid, op_type, before_data, after_data }) {
    try {
        const enrich = async (raw) => {
            if (!raw || typeof raw !== 'object') return raw;
            const data = compactSnapshot(raw, target_table);
            if (data.group_id && !data.group_name) {
                const g = await dbGet("SELECT name FROM todo_groups WHERE uuid = ?", [data.group_id]);
                if (g) data.group_name = g.name;
            }
            if (data.team_uuid && !data.team_name) {
                const t = await dbGet("SELECT name FROM teams WHERE uuid = ?", [data.team_uuid]);
                if (t) data.team_name = t.name;
            }
            return data;
        };
        const finalBefore = await enrich(before_data);
        const finalAfter = await enrich(after_data);

        const sql = `INSERT INTO audit_logs
                     (team_uuid, user_id, target_table, target_uuid, op_type, before_data, after_data, timestamp)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`;
        const params = [
            team_uuid || null,
            user_id,
            target_table,
            target_uuid,
            op_type,
            safeSnapshotJson(finalBefore, target_table),
            safeSnapshotJson(finalAfter, target_table),
            Date.now()
        ];
        await dbRun(sql, params);

        // 🚀 实时感知：如果是在团队范围内，广播审计更新（用于统计或实时 UI 反馈）
        if (team_uuid) {
            broadcastToRoom(`team:${team_uuid}`, {
                action: 'AUDIT_LOG_CREATED',
                target_table,
                op_type,
                user_id,
                timestamp: Date.now()
            });
        }
    } catch (e) {
        console.error("❌ Audit Log Capture Failed:", e.message);
    }
}

// ==========================================
// 🛠️ 初始化表结构
// ==========================================
const initializeTables = async () => {
    const tables = [
        `users (id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT, email TEXT UNIQUE, password_hash TEXT, tier TEXT DEFAULT 'free', avatar_url TEXT, semester_start INTEGER, semester_end INTEGER, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)`,
        `pending_registrations (email TEXT PRIMARY KEY, username TEXT, password_hash TEXT, code TEXT, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)`,
        `sync_limits (user_id INTEGER, sync_date TEXT, sync_count INTEGER DEFAULT 0, last_sync_time INTEGER DEFAULT 0, is_banned INTEGER DEFAULT 0, PRIMARY KEY (user_id, sync_date))`,
        `todos (id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT, user_id INTEGER, content TEXT, is_completed INTEGER DEFAULT 0, is_deleted INTEGER DEFAULT 0, version INTEGER DEFAULT 1, device_id TEXT, category_id TEXT, created_at INTEGER, updated_at INTEGER, due_date INTEGER, created_date INTEGER, recurrence INTEGER DEFAULT 0, custom_interval_days INTEGER, recurrence_end_date INTEGER, remark TEXT, group_id TEXT, collab_type INTEGER DEFAULT 0, UNIQUE(user_id, uuid))`,
        `todo_groups (id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT, user_id INTEGER, name TEXT, is_expanded INTEGER DEFAULT 0, is_deleted INTEGER DEFAULT 0, version INTEGER DEFAULT 1, updated_at INTEGER, created_at INTEGER, UNIQUE(user_id, uuid))`,
        `countdowns (id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT, user_id INTEGER, title TEXT, target_time INTEGER, is_deleted INTEGER DEFAULT 0, version INTEGER DEFAULT 1, device_id TEXT, created_at INTEGER, updated_at INTEGER, UNIQUE(user_id, uuid))`,
        `time_logs (uuid TEXT, user_id INTEGER, title TEXT, tag_uuids TEXT, start_time INTEGER, end_time INTEGER, remark TEXT, is_deleted INTEGER DEFAULT 0, version INTEGER DEFAULT 1, device_id TEXT, created_at INTEGER, updated_at INTEGER, PRIMARY KEY (user_id, uuid))`,
        // 🚨 屏幕时间表：包含 device_name，不包含 device_id
        `screen_time_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER, device_name TEXT, record_date TEXT, app_name TEXT, duration INTEGER DEFAULT 0, updated_at INTEGER DEFAULT CURRENT_TIMESTAMP, UNIQUE(user_id, device_name, record_date, app_name))`,
        `app_name_mappings (package_name TEXT PRIMARY KEY, mapped_name TEXT, category TEXT)`,
        `courses (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER, semester TEXT DEFAULT 'default', course_name TEXT, room_name TEXT, teacher_name TEXT, start_time INTEGER, end_time INTEGER, weekday INTEGER, week_index INTEGER, lesson_type TEXT, is_deleted INTEGER DEFAULT 0, created_at INTEGER, updated_at INTEGER)`,
        `pomodoro_tags (uuid TEXT, user_id INTEGER, name TEXT, color TEXT DEFAULT '#607D8B', is_deleted INTEGER DEFAULT 0, version INTEGER DEFAULT 1, created_at INTEGER, updated_at INTEGER, PRIMARY KEY (user_id, uuid))`,
        `pomodoro_records (uuid TEXT, user_id INTEGER, todo_uuid TEXT, start_time INTEGER, end_time INTEGER, planned_duration INTEGER, actual_duration INTEGER, status TEXT, device_id TEXT, is_deleted INTEGER DEFAULT 0, version INTEGER DEFAULT 1, created_at INTEGER, updated_at INTEGER, PRIMARY KEY (user_id, uuid))`,
        `pomodoro_settings (user_id INTEGER PRIMARY KEY, default_focus_duration INTEGER DEFAULT 1500, default_rest_duration INTEGER DEFAULT 300, default_loop_count INTEGER DEFAULT 4, timer_mode INTEGER DEFAULT 0, updated_at INTEGER)`,
        `todo_tags (todo_uuid TEXT, tag_uuid TEXT, is_deleted INTEGER DEFAULT 0, updated_at INTEGER, PRIMARY KEY(todo_uuid, tag_uuid))`,
        `leaderboard (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER, username TEXT, score INTEGER DEFAULT 0, duration INTEGER, played_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)`,
        `device_versions (device_id TEXT PRIMARY KEY, user_id INTEGER, platform TEXT, version TEXT, last_seen_at INTEGER)`,
        `password_resets (email TEXT PRIMARY KEY, code TEXT, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)`,
        // --- 协作系统新增表 ---
        `teams (id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT UNIQUE, name TEXT, creator_id INTEGER, created_at INTEGER)`,
        `team_members (team_uuid TEXT, user_id INTEGER, role INTEGER DEFAULT 1, joined_at INTEGER, PRIMARY KEY(team_uuid, user_id))`,
        `team_invitations (code TEXT PRIMARY KEY, team_uuid TEXT, creator_id INTEGER, expires_at INTEGER, max_uses INTEGER DEFAULT 1, current_uses INTEGER DEFAULT 0)`,
        // --- 审计与审批流新增表 (Uni-Sync V4.0) ---
        `audit_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, team_uuid TEXT, user_id INTEGER, target_table TEXT, target_uuid TEXT, op_type TEXT, before_data TEXT, after_data TEXT, timestamp INTEGER)`,
        `team_join_requests (id INTEGER PRIMARY KEY AUTOINCREMENT, team_uuid TEXT, user_id INTEGER, status INTEGER DEFAULT 0, message TEXT, requested_at INTEGER, processed_at INTEGER, processor_id INTEGER, UNIQUE(team_uuid, user_id))`,
        `team_tombstones (id INTEGER PRIMARY KEY AUTOINCREMENT, team_uuid TEXT, item_uuid TEXT, updated_at INTEGER)`,
        // --- 协作增强：独立待办状态 ---
        `todo_completions (todo_uuid TEXT, user_id INTEGER, is_completed INTEGER, updated_at INTEGER, PRIMARY KEY(todo_uuid, user_id))`,
        // --- 消息中心 (Uni-Sync V4.0) ---
        `team_system_messages (id INTEGER PRIMARY KEY AUTOINCREMENT, team_uuid TEXT, user_id INTEGER, type TEXT, message TEXT, timestamp INTEGER, is_read INTEGER DEFAULT 0)`,
        // --- 团队公告 (Uni-Sync 4.0) ---
        `team_announcements (uuid TEXT PRIMARY KEY, team_uuid TEXT, creator_id INTEGER, title TEXT, content TEXT, is_priority INTEGER DEFAULT 0, expires_at INTEGER, created_at INTEGER, updated_at INTEGER)`,
        `team_announcements (uuid TEXT PRIMARY KEY, team_uuid TEXT, creator_id INTEGER, title TEXT, content TEXT, is_priority INTEGER DEFAULT 0, expires_at INTEGER, created_at INTEGER, updated_at INTEGER)`,
        `team_announcement_reads (announcement_uuid TEXT, user_id INTEGER, read_at INTEGER, PRIMARY KEY(announcement_uuid, user_id))`,
        `user_ignored_items (user_id INTEGER, uuid TEXT, table_name TEXT, ignored_at INTEGER, PRIMARY KEY(user_id, uuid))`,
        `is_all_day_migration (id INTEGER PRIMARY KEY)`
    ];
    for (const t of tables) {
        await dbRun(`CREATE TABLE IF NOT EXISTS ${t}`);
    }

    // 🚀 确保所有业务表都有 conflict 字段 (Uni-Sync 4.0 冲突检测基座)
    const tablesWithConflict = ['todos', 'countdowns', 'todo_groups', 'time_logs', 'courses', 'pomodoro_records', 'pomodoro_tags'];
    for (const tableName of tablesWithConflict) {
        const cols = await dbAll(`PRAGMA table_info(${tableName})`);
        if (!cols.some(c => c.name === 'has_conflict')) {
            await dbRun(`ALTER TABLE ${tableName} ADD COLUMN has_conflict INTEGER DEFAULT 0`);
            console.log(`✅ 成功为 ${tableName} 表同步了 has_conflict 字段`);
        }
        if (!cols.some(c => c.name === 'conflict_data')) {
            await dbRun(`ALTER TABLE ${tableName} ADD COLUMN conflict_data TEXT`);
            console.log(`✅ 成功为 ${tableName} 表同步了 conflict_data 字段`);
        }
        await dbRun(`UPDATE ${tableName} SET conflict_data = NULL, has_conflict = 0 WHERE conflict_data IS NOT NULL AND LENGTH(conflict_data) > 32768`);
    }
    await dbRun(`UPDATE todos SET created_at = COALESCE(NULLIF(created_date, 0), updated_at, ?) WHERE created_at IS NULL OR created_at = 0`, [Date.now()]);
    await dbRun(`UPDATE audit_logs SET before_data = NULL WHERE before_data IS NOT NULL AND LENGTH(before_data) > 32768`);
    await dbRun(`UPDATE audit_logs SET after_data = NULL WHERE after_data IS NOT NULL AND LENGTH(after_data) > 32768`);
};
initializeTables().then(async () => {
    // 🚀 数据库迁移：确保 todos 表列齐全
    try {
        const columns = await dbAll("PRAGMA table_info(todos)");
        const colNames = new Set(columns.map(c => c.name));

        if (!colNames.has('group_id')) {
            await dbRun("ALTER TABLE todos ADD COLUMN group_id TEXT");
            console.log("✅ 成功为 todos 表同步了 group_id 字段");
        }
        if (!colNames.has('remark')) {
            await dbRun("ALTER TABLE todos ADD COLUMN remark TEXT");
            console.log("✅ 成功为 todos 表同步了 remark 字段");
        }
        if (!colNames.has('category_id')) {
            await dbRun("ALTER TABLE todos ADD COLUMN category_id TEXT");
            console.log("✅ 成功为 todos 表同步了 category_id 字段");
        }
        if (!colNames.has('due_date')) {
            await dbRun("ALTER TABLE todos ADD COLUMN due_date INTEGER");
        }
        if (!colNames.has('created_date')) {
            await dbRun("ALTER TABLE todos ADD COLUMN created_date INTEGER");
        }
        if (!colNames.has('recurrence')) {
            await dbRun("ALTER TABLE todos ADD COLUMN recurrence INTEGER DEFAULT 0");
        }
        if (!colNames.has('custom_interval_days')) {
            await dbRun("ALTER TABLE todos ADD COLUMN custom_interval_days INTEGER");
        }
        if (!colNames.has('recurrence_end_date')) {
            await dbRun("ALTER TABLE todos ADD COLUMN recurrence_end_date INTEGER");
        }
        if (!colNames.has('team_uuid')) {
            await dbRun("ALTER TABLE todos ADD COLUMN team_uuid TEXT");
        }
        if (!colNames.has('collab_type')) {
            await dbRun("ALTER TABLE todos ADD COLUMN collab_type INTEGER DEFAULT 0");
        }
        if (!colNames.has('reminder_minutes')) {
            await dbRun("ALTER TABLE todos ADD COLUMN reminder_minutes INTEGER");
            console.log("✅ 成功为 todos 表同步了 reminder_minutes 字段");
        }
        if (!colNames.has('is_all_day')) {
            await dbRun("ALTER TABLE todos ADD COLUMN is_all_day INTEGER DEFAULT 0");
            console.log("✅ 成功为 todos 表同步了 is_all_day 字段");
        }

        // 检查其余核心表的 team_uuid
        const checkTeamUuid = async (tableName) => {
            const cols = await dbAll(`PRAGMA table_info(${tableName})`);
            if (!cols.some(c => c.name === 'team_uuid')) {
                await dbRun(`ALTER TABLE ${tableName} ADD COLUMN team_uuid TEXT`);
                console.log(`✅ 成功为 ${tableName} 表补全了 team_uuid 字段`);
            }
        };

        await checkTeamUuid('todo_groups');
        await checkTeamUuid('countdowns');
        await checkTeamUuid('time_logs');
        await checkTeamUuid('pomodoro_records');
        await checkTeamUuid('courses');

        // 检查 todo_groups
        const groupCols = await dbAll("PRAGMA table_info(todo_groups)");
        const groupColNames = new Set(groupCols.map(c => c.name));
        if (!groupColNames.has('name')) {
            await dbRun("ALTER TABLE todo_groups ADD COLUMN name TEXT");
        }
        if (!groupColNames.has('is_expanded')) {
            await dbRun("ALTER TABLE todo_groups ADD COLUMN is_expanded INTEGER DEFAULT 0");
        }

        // --- 协作迁移：为所有业务表增加 team_uuid ---
        const tablesToExtend = ['todos', 'todo_groups', 'countdowns', 'time_logs', 'courses', 'pomodoro_records', 'pomodoro_tags'];
        for (const tableName of tablesToExtend) {
            const tableCols = await dbAll(`PRAGMA table_info(${tableName})`);
            const hasTeamUuid = tableCols.some(c => c.name === 'team_uuid');
            if (!hasTeamUuid) {
                await dbRun(`ALTER TABLE ${tableName} ADD COLUMN team_uuid TEXT`);
                console.log(`✅ 成功为 ${tableName} 表同步了 team_uuid 字段`);
            }
        }

        // 补齐 courses 的 uuid 字段 (如果缺失)
        const courseCols = await dbAll("PRAGMA table_info(courses)");
        if (!courseCols.some(c => c.name === 'uuid')) {
            await dbRun("ALTER TABLE courses ADD COLUMN uuid TEXT");
            console.log("✅ 成功为 courses 表同步了 uuid 字段");
        }

        // 检查 team_members 的 joined_at
        const memberCols = await dbAll("PRAGMA table_info(team_members)");
        if (!memberCols.some(c => c.name === 'joined_at')) {
            await dbRun("ALTER TABLE team_members ADD COLUMN joined_at INTEGER");
            await dbRun("UPDATE team_members SET joined_at = ?", [Date.now()]);
            console.log("✅ 成功为 team_members 表补全了 joined_at 字段");
        }

        // 🚀 数据库迁移：确保 team_announcements 表列齐全 (Uni-Sync 4.0)
        const annCols = await dbAll("PRAGMA table_info(team_announcements)");
        const annColNames = new Set(annCols.map(c => c.name));
        if (annColNames.size > 0) {
            if (!annColNames.has('is_priority')) {
                await dbRun("ALTER TABLE team_announcements ADD COLUMN is_priority INTEGER DEFAULT 0");
                console.log("✅ 成功为 team_announcements 表同步了 is_priority 字段");
            }
            if (!annColNames.has('expires_at')) {
                await dbRun("ALTER TABLE team_announcements ADD COLUMN expires_at INTEGER");
                console.log("✅ 成功为 team_announcements 表同步了 expires_at 字段");
            }
        }
    } catch (e) {
        console.error("❌ 数据库系统自检/迁移失败:", e.message);
    }
});

// ==========================================
// 🚀 模块: 在线数据接口暴露
// ==========================================
app.get('/api/online_stats', (req, res) => {
    // 调用提取出来的统计函数
    const data = getOnlineStatsData();
    res.json({
        success: true,
        data: data
    });
});

// 🚀 新增接口：查询所有设备历史停留的版本统计（包含离线设备）
app.get('/api/device_version_stats', async (req, res) => {
    try {
        const rows = await dbAll(`
            SELECT platform, version, COUNT(device_id) as device_count
            FROM device_versions
            GROUP BY platform, version
            ORDER BY platform ASC, version DESC
        `);

        // 将扁平的 SQL 结果格式化为按平台分类的树状结构
        const stats = {};
        let totalDevices = 0;

        for (const row of rows) {
            if (!stats[row.platform]) stats[row.platform] = {};
            stats[row.platform][row.version] = row.device_count;
            totalDevices += row.device_count;
        }

        res.json({
            success: true,
            data: {
                stats,
                totalDevices
            }
        });
    } catch (err) {
        console.error("查询设备版本分布失败:", err);
        res.status(500).json({ error: "内部服务器错误" });
    }
});

// ==========================================
// 🔌 WebSocket 核心：协议升级与实时中转
// ==========================================
server.on('upgrade', (request, socket, head) => {
    const url = new URL(request.url, `http://${request.headers.host}`);
    const token = url.searchParams.get('token');

    // 🛡️ 保安检查：利用原有 signToken 逻辑校验
    if (!token) {
        socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
        socket.destroy();
        return;
    }

    const parts = token.split('.');
    const userIdStr = parts[0];
    if (token !== signToken(userIdStr)) {
        socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
        socket.destroy();
        return;
    }

    // 校验通过，升级连接
    wss.handleUpgrade(request, socket, head, (ws) => {
        ws.userId = parseInt(userIdStr); // 🚀 关键：转为数字以匹配数据库 id 字段
        wss.emit('connection', ws, request);
    });
});

wss.on('connection', (ws, req) => {
    const userId = ws.userId;
    const url = new URL(req.url, `http://${req.headers.host}`);
    const deviceId = url.searchParams.get('deviceId');
    const platform = url.searchParams.get('platform') || 'unknown';
    const clientVersion = url.searchParams.get('version') || 'unknown';

    if (!deviceId) {
        ws.close(1008, 'Missing deviceId');
        return;
    }

    // 3. 绑定设备信息
    ws.deviceId = deviceId;
    ws.platform = platform;
    ws.clientVersion = clientVersion;

    // 4. 加入房间 (个人房间 + 所有加入的团队房间)
    getUserRoomKeys(userId).then(rooms => {
        for (const roomKey of rooms) joinRoom(ws, roomKey);
        console.log(`${getTime()} [WS上线] 用户 ${userId} 设备 ${deviceId} 已加入房间: ${rooms.join(', ')}`);
    });

    // 🚀 持久化记录设备最后上线的平台和版本
    if (clientVersion !== 'unknown') {
        dbRun(`INSERT INTO device_versions (device_id, user_id, platform, version, last_seen_at)
               VALUES (?, ?, ?, ?, ?)
                   ON CONFLICT(device_id) DO UPDATE SET
                    user_id = excluded.user_id, platform = excluded.platform, version = excluded.version, last_seen_at = excluded.last_seen_at`,
            [deviceId, userId, platform, clientVersion, Date.now()])
            .catch(e => console.error(`${getTime()} [DB错误] 记录设备版本失败:`, e.message));
    }

    // 5. 🚀 更新检测推送
    if (cachedManifest && clientVersion !== 'unknown') {
        if (hasNewVersion(cachedManifest.version_name, clientVersion)) {
            ws.send(JSON.stringify({ action: 'UPDATE_AVAILABLE', manifest: cachedManifest }));
        }
    }

    // 🚀 新增：推送待处理申请/邀请红点 (用于 UI 实时更新)
    const pushPendingStats = async () => {
        try {
            const joinReqs = await dbGet("SELECT COUNT(*) as count FROM team_join_requests r JOIN teams t ON r.team_uuid = t.uuid WHERE t.creator_id = ? AND r.status = 0", [userId]);
            const invites = await dbGet("SELECT COUNT(*) as count FROM team_join_requests WHERE user_id = ? AND status = 3", [userId]);
            ws.send(JSON.stringify({ action: 'PENDING_COUNTS', join_requests: joinReqs?.count || 0, invitations: invites?.count || 0 }));
        } catch (e) { console.error("Push stats error:", e); }
    };
    pushPendingStats();

    // 6. 🚀 推送全量状态（包含个人和所属团队）
    const pushFocusStates = async () => {
        const personalFocus = userFocusStates.get(userId);
        if (personalFocus) ws.send(JSON.stringify({ action: 'SYNC_FOCUS', ...personalFocus }));

        const rooms = await getUserRoomKeys(userId);
        for (const roomKey of rooms) {
            if (roomKey.startsWith('team:')) {
                const teamUuid = roomKey.split(':')[1];
                const teamFocus = teamFocusStates.get(teamUuid);
                if (teamFocus) ws.send(JSON.stringify({ action: 'SYNC_FOCUS', ...teamFocus }));
            }
        }
    };
    pushFocusStates();

    ws.on('message', async (messageAsString) => {
        try {
            const data = JSON.parse(messageAsString);
            if (data.action === 'PING' || data.action === 'HEARTBEAT') {
                ws.send(JSON.stringify({ action: 'PONG', timestamp: Date.now() }));
                return;
            }

            // 🚀 核心修复：支持动态订阅团队房间
            if (data.type === 'subscribe') {
                const teamUuids = data.teamUuids || [];
                for (const uuid of teamUuids) {
                    joinRoom(ws, `team:${uuid}`);
                }
                console.log(`${getTime()} [WS订阅] 用户 ${userId} 订阅了团队: ${teamUuids.join(', ')}`);
                return;
            }

            const targetRoom = data.team_uuid ? `team:${data.team_uuid}` : `user:${userId}`;
            const payload = { sourceDevice: deviceId, timestamp: Date.now(), ...data };

            // 维护专注状态（支持团队/个人隔离）
            if (data.action === 'START' || data.action === 'RECONNECT_SYNC') {
                // 🚀 核心防御：如果关联的待办已完成，拒绝开启/恢复专注状态，防止“幽灵计时”复活
                const tUuid = data.todo_uuid || data.todoUuid;
                if (tUuid) {
                    try {
                        const todo = await dbGet("SELECT is_completed FROM todos WHERE uuid = ?", [tUuid]);
                        if (todo && todo.is_completed === 1) {
                            console.log(`${getTime()} [WS防御] 拒绝为已完成任务 ${tUuid} 开启/恢复专注`);
                            return;
                        }
                    } catch (e) { console.error("Check todo status error:", e); }
                }

                if (data.team_uuid) teamFocusStates.set(data.team_uuid, payload);
                else userFocusStates.set(userId, payload);
            } else if (['STOP', 'INTERRUPT', 'FINISH', 'CLEAR_FOCUS', 'IDLE_REPORT'].includes(data.action)) {
                if (data.team_uuid) {
                    const state = teamFocusStates.get(data.team_uuid);
                    // 🚀 补擦除逻辑：如果是 IDLE_REPORT，必须是原发起设备才能擦除
                    if (data.action === 'IDLE_REPORT') {
                        if (state && state.sourceDevice === deviceId) {
                            teamFocusStates.delete(data.team_uuid);
                            console.log(`${getTime()} [补擦除] 团队房间 ${data.team_uuid} 的发起设备 ${deviceId} 已恢复连接并上报空闲，清理残留状态`);
                            broadcastToRoom(targetRoom, { ...payload, action: 'CLEAR_FOCUS' }, ws);
                        }
                        return; // 不下发 IDLE_REPORT 广播
                    }
                    teamFocusStates.delete(data.team_uuid);
                } else {
                    const state = userFocusStates.get(userId);
                    // 🚀 补擦除逻辑：如果是 IDLE_REPORT，必须是原发起设备才能擦除
                    if (data.action === 'IDLE_REPORT') {
                        if (state && state.sourceDevice === deviceId) {
                            userFocusStates.delete(userId);
                            console.log(`${getTime()} [补擦除] 用户 ${userId} 的发起设备 ${deviceId} 已恢复连接并上报空闲，清理残留状态`);
                            broadcastToRoom(targetRoom, { ...payload, action: 'CLEAR_FOCUS' }, ws);
                        }
                        return; // 不下发 IDLE_REPORT 广播
                    }
                    userFocusStates.delete(userId);
                    // 🚀 额外兜底：如果提供了 todo_uuid 且未传 team_uuid，尝试清理可能存在的团队状态
                    if (data.todo_uuid || data.todoUuid) {
                        const tUuid = data.todo_uuid || data.todoUuid;
                        for (const [tKey, state] of teamFocusStates.entries()) {
                            if ((state.todo_uuid === tUuid || state.todoUuid === tUuid) && state.sourceDevice === deviceId) {
                                teamFocusStates.delete(tKey);
                                console.log(`${getTime()} [补擦除-兜底] 通过 todo_uuid 清理了发起设备 ${deviceId} 的团队残留 ${tKey}`);
                            }
                        }
                    }
                }
            }

            // 广播给对应房间的其他设备
            broadcastToRoom(targetRoom, payload, ws);

        } catch (e) {
            console.error(`${getTime()} [WS错误] 解析消息失败:`, e);
        }
    });

    ws.on('close', () => {
        leaveAllRooms(ws);
        console.log(`${getTime()} [下线] 用户 ${userId} 的设备 ${deviceId} 已断开。`);
    });

    // 🚀 核心修复：心跳检测，防止僵尸连接占用内存
    ws.isAlive = true;
    ws.on('pong', () => { ws.isAlive = true; });
});

// 🚀 每 30 秒进行一次全量心跳检查
const interval = setInterval(() => {
    wss.clients.forEach((ws) => {
        if (ws.isAlive === false) {
            console.log(`${getTime()} [GC清理] 发现僵尸连接，强制终止: 用户 ${ws.userId} 设备 ${ws.deviceId}`);
            return ws.terminate();
        }
        ws.isAlive = false;
        ws.ping();
    });
}, 30000);

wss.on('close', () => clearInterval(interval));


// ==========================================
// 模块 A: 用户认证 (Auth)
// ==========================================
app.post('/api/auth/register', async (req, res) => {
    const { email, code, username, password } = req.body;

    if (code) {
        if (!email) return res.status(400).json({ error: "验证需提供邮箱" });
        const pending = await dbGet("SELECT * FROM pending_registrations WHERE email = ?", [email]);
        if (!pending) return res.status(400).json({ error: "验证请求不存在或已过期，请重新注册" });
        if (pending.code !== code.toString()) return res.status(400).json({ error: "验证码错误" });

        const createdTime = new Date(pending.created_at + 'Z').getTime();
        if (Date.now() - createdTime > 15 * 60 * 1000) return res.status(400).json({ error: "验证码已过期，请重新获取" });

        try {
            await dbRun("INSERT INTO users (username, email, password_hash) VALUES (?, ?, ?)", [pending.username, pending.email, pending.password_hash]);
            await dbRun("DELETE FROM pending_registrations WHERE email = ?", [email]);
            return res.json({ success: true, message: "注册成功，请登录" });
        } catch (e) {
            if (e.message.includes("UNIQUE")) return res.status(400).json({ error: "该邮箱已完成注册，请直接登录" });
            return res.status(500).json({ error: e.message });
        }
    }

    if (!username || !email || !password) return res.status(400).json({ error: "缺少必要字段" });
    if (!RESEND_API_KEY) return res.status(500).json({ error: "服务端未配置邮件服务" });

    const existing = await dbGet("SELECT id FROM users WHERE email = ?", [email]);
    if (existing) return res.status(400).json({ error: "该邮箱已被注册，请直接登录" });

    const newCode = Math.floor(100000 + Math.random() * 900000).toString();
    const hash = hashPassword(password);

    await dbRun("INSERT OR REPLACE INTO pending_registrations (email, username, password_hash, code) VALUES (?, ?, ?, ?)", [email, username, hash, newCode]);

    const resendResponse = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { "Authorization": `Bearer ${RESEND_API_KEY}`, "Content-Type": "application/json" },
        body: JSON.stringify({
            from: "Math Quiz <Math&Quiz@junpgle.me>",
            to: email,
            subject: "验证您的账号 - Math Quiz",
            html: `<div style="font-family: sans-serif; padding: 20px;"><h2>欢迎注册!</h2><p>您的验证码是：</p><p style="font-size: 32px; font-weight: bold; letter-spacing: 5px; color: #4F46E5;">${newCode}</p></div>`
        })
    });

    if (!resendResponse.ok) return res.status(400).json({ error: "验证邮件发送失败" });
    res.json({ success: true, message: "验证码已发送", require_verify: true });
});

app.post('/api/migrate_register', async (req, res) => {
    const { email, username, password, tier, semester_start, semester_end } = req.body;
    try {
        const hash = hashPassword(password);
        try {
            await dbRun(`
                INSERT INTO users (email, username, password_hash, tier, semester_start, semester_end)
                VALUES (?, ?, ?, ?, ?, ?)
            `, [email, username, hash, tier || 'free', semester_start, semester_end]);
        } catch (dbErr) {
            if (dbErr.message.includes('UNIQUE')) {
                return res.status(400).json({ success: false, error: "该邮箱已被注册，为了安全已拦截覆盖！" });
            }
            throw dbErr;
        }

        const user = await dbGet('SELECT * FROM users WHERE email = ?', [email]);
        const token = signToken(user.id);

        res.json({ success: true, token: token, user_id: user.id, user: user, message: '迁移同步成功' });
    } catch (err) {
        res.status(500).json({ success: false, error: err.message });
    }
});

// 算力挑战获取接口 (用于防止刷注册/刷申请)
app.get('/api/auth/pow_challenge', requireAuth, (req, res) => {
    const challenge = generateChallenge(req.userId);
    res.json({ success: true, challenge, difficulty: 4 });
});

app.post('/api/auth/login', async (req, res) => {
    const { email, password } = req.body;
    const user = await dbGet("SELECT * FROM users WHERE email = ?", [email]);
    if (!user) return res.status(404).json({ error: "用户不存在" });

    if (hashPassword(password) !== user.password_hash) return res.status(401).json({ error: "密码错误" });

    res.json({
        success: true,
        token: signToken(user.id),
        user: { id: user.id, username: user.username, email: user.email, avatar_url: user.avatar_url, tier: user.tier }
    });
});

// ==========================================
// 🔐 忘记密码：步骤1 - 请求发送验证码
// ==========================================
app.post('/api/auth/forgot_password', async (req, res) => {
    const { email } = req.body;

    if (!email) return res.status(400).json({ error: "请提供绑定的邮箱地址" });
    if (!RESEND_API_KEY) return res.status(500).json({ error: "服务端未配置邮件服务" });

    // 1. 检查邮箱是否已注册
    const user = await dbGet("SELECT id FROM users WHERE email = ?", [email]);
    if (!user) return res.status(404).json({ error: "该邮箱尚未注册" });

    // 2. 为了防止服务器重启前没有建表，动态确保表存在（容错机制）
    await dbRun(`CREATE TABLE IF NOT EXISTS password_resets (email TEXT PRIMARY KEY, code TEXT, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)`);

    // 在插入新记录前，检查最后一次请求时间
    const existingRequest = await dbGet("SELECT created_at FROM password_resets WHERE email = ?", [email]);
    if (existingRequest) {
        const lastRequestTime = new Date(existingRequest.created_at + 'Z').getTime();
        if (Date.now() - lastRequestTime < 60 * 1000) { // 60秒冷却
            return res.status(429).json({ error: "获取验证码过于频繁，请 1 分钟后再试" });
        }
    }

    // 3. 生成 6 位验证码并存入数据库
    const newCode = Math.floor(100000 + Math.random() * 900000).toString();
    await dbRun("INSERT OR REPLACE INTO password_resets (email, code) VALUES (?, ?)", [email, newCode]);

    // 4. 调用 Resend 发送邮件
    const resendResponse = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { "Authorization": `Bearer ${RESEND_API_KEY}`, "Content-Type": "application/json" },
        body: JSON.stringify({
            from: "Math Quiz <Math&Quiz@junpgle.me>", // 保持与注册邮件一致
            to: email,
            subject: "重置您的密码 - Math Quiz",
            html: `<div style="font-family: sans-serif; padding: 20px;">
                    <h2>重置密码请求</h2>
                    <p>我们收到了您重置密码的请求。您的验证码是：</p>
                    <p style="font-size: 32px; font-weight: bold; letter-spacing: 5px; color: #E53E3E;">${newCode}</p>
                    <p style="color: #666; font-size: 14px;">此验证码在 15 分钟内有效。如果您未请求重置密码，请忽略此邮件。</p>
                   </div>`
        })
    });

    if (!resendResponse.ok) return res.status(400).json({ error: "验证邮件发送失败，请稍后再试" });
    res.json({ success: true, message: "重置验证码已发送至您的邮箱" });
});

// ==========================================
// 🔐 忘记密码：步骤2 - 校验验证码并修改密码
// ==========================================
app.post('/api/auth/reset_password', async (req, res) => {
    const { email, code, new_password } = req.body;

    if (!email || !code || !new_password) return res.status(400).json({ error: "缺少必要字段：邮箱、验证码或新密码" });

    // 1. 查找验证码记录
    const resetRecord = await dbGet("SELECT * FROM password_resets WHERE email = ?", [email]);
    if (!resetRecord) return res.status(400).json({ error: "未找到该邮箱的重置请求，请重新获取验证码" });

    // 2. 校验验证码是否正确
    if (resetRecord.code !== code.toString()) return res.status(400).json({ error: "验证码错误" });

    // 3. 校验验证码是否过期 (15分钟)
    // 注意：SQLite 的 CURRENT_TIMESTAMP 是 UTC 时间，需追加 'Z' 解析
    const createdTime = new Date(resetRecord.created_at + 'Z').getTime();
    if (Date.now() - createdTime > 15 * 60 * 1000) {
        await dbRun("DELETE FROM password_resets WHERE email = ?", [email]); // 清理过期记录
        return res.status(400).json({ error: "验证码已过期，请重新获取" });
    }

    try {
        // 4. 加密新密码并更新数据库
        if (new_password.length < 6) return res.status(400).json({ error: "密码长度不能少于 6 位" });
        const hash = hashPassword(new_password);
        await dbRun("UPDATE users SET password_hash = ? WHERE email = ?", [hash, email]);

        // 5. 使用完毕后清理验证码记录
        await dbRun("DELETE FROM password_resets WHERE email = ?", [email]);

        res.json({ success: true, message: "密码重置成功，请使用新密码登录" });
    } catch (e) {
        res.status(500).json({ error: "重置密码时发生错误: " + e.message });
    }
});

app.post('/api/auth/change_password', requireAuth, async (req, res) => {
    const { user_id, old_password, new_password } = req.body;
    if (req.userId !== parseInt(user_id, 10)) return res.status(403).json({ error: "无权操作此账号" });

    const user = await dbGet("SELECT * FROM users WHERE id = ?", [user_id]);
    if (!user) return res.status(404).json({ error: "用户不存在" });

    if (hashPassword(old_password) !== user.password_hash) return res.status(401).json({ error: "当前密码错误" });

    await dbRun("UPDATE users SET password_hash = ? WHERE id = ?", [hashPassword(new_password), user_id]);
    res.json({ success: true, message: "密码修改成功" });
});

// --- Uni-Sync 安全：获取 PoW 挑战 ---
app.get('/api/auth/challenge', requireAuth, (req, res) => {
    res.json({
        success: true,
        challenge: generateChallenge(req.userId),
        difficulty: 4 // 后期可根据服务器压力动态调整
    });
});

app.get('/api/user/status', async (req, res) => {
    const userId = parseInt(req.query.user_id, 10);
    if (!userId) return res.status(400).json({ error: "缺少 user_id 参数" });

    const userRow = await dbGet("SELECT tier FROM users WHERE id = ?", [userId]);
    if (!userRow) return res.status(404).json({ error: "用户不存在" });

    const tier = userRow.tier || 'free';
    const syncLimit = SYNC_LIMITS[tier] || SYNC_LIMITS.free;
    const todayStr = getChinaDateStr(Date.now());
    const record = await dbGet("SELECT sync_count FROM sync_limits WHERE user_id = ? AND sync_date = ?", [userId, todayStr]);

    res.json({ success: true, tier, sync_count: record ? record.sync_count : 0, sync_limit: syncLimit });
});

// ==========================================
// 🚀 模块 B: 团队与协作 (Collaboration)
// ==========================================

// 获取用户加入的所有团队
app.get('/api/teams', requireAuth, async (req, res) => {
    try {
        const teams = await dbAll(`
            SELECT t.*, tm.role,
                   (SELECT COUNT(*) FROM team_members WHERE team_uuid = t.uuid) as member_count,
                   (SELECT code FROM team_invitations WHERE team_uuid = t.uuid AND expires_at > ? ORDER BY expires_at DESC LIMIT 1) as invite_code
            FROM teams t
                JOIN team_members tm ON t.uuid = tm.team_uuid
            WHERE tm.user_id = ?
        `, [Date.now(), req.userId]);
        res.json({ success: true, teams });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// 获取跨团队未读重要公告 (用于首页置顶)
app.get('/api/teams/announcements/unread_priority', requireAuth, async (req, res) => {
    try {
        const now = Date.now();
        const announcements = await dbAll(`
            SELECT a.*, u.username as creator_name, t.name as team_name
            FROM team_announcements a
            JOIN users u ON a.creator_id = u.id
            JOIN teams t ON a.team_uuid = t.uuid
            JOIN team_members tm ON a.team_uuid = tm.team_uuid
            WHERE tm.user_id = ? 
              AND a.is_priority = 1 
              AND (a.expires_at IS NULL OR a.expires_at > ?)
              AND NOT EXISTS (
                  SELECT 1 FROM team_announcement_reads 
                  WHERE announcement_uuid = a.uuid AND user_id = ?
              )
            ORDER BY a.created_at DESC
        `, [req.userId, now, req.userId]);
        res.json({ success: true, announcements });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// 创建团队
app.post('/api/teams/create', requireAuth, async (req, res) => {
    const { name } = req.body;
    if (!name) return res.status(400).json({ error: "团队名称不能为空" });
    const teamUuid = crypto.randomUUID ? crypto.randomUUID() : crypto.randomBytes(16).toString('hex');
    const now = Date.now();

    const release = await dbLock.acquire();
    let inTransaction = false;
    try {
        await dbRun('BEGIN TRANSACTION');
        inTransaction = true;
        await dbRun("INSERT INTO teams (uuid, name, creator_id, created_at) VALUES (?, ?, ?, ?)", [teamUuid, name, req.userId, now]);
        await dbRun("INSERT INTO team_members (team_uuid, user_id, role, joined_at) VALUES (?, ?, ?, ?)", [teamUuid, req.userId, 0, now]); // Role 0 为管理员
        await dbRun('COMMIT');
        inTransaction = false;
        res.json({ success: true, team_uuid: teamUuid });
    } catch (e) {
        if (inTransaction) await dbRun('ROLLBACK');
        res.status(500).json({ error: e.message });
    } finally {
        release();
    }
});

// 生成邀请码 (管理员权限)
app.post('/api/teams/invite', requireAuth, async (req, res) => {
    const { team_uuid, expires_in_days = 7, max_uses = 5 } = req.body;

    const membership = await dbGet("SELECT role FROM team_members WHERE team_uuid = ? AND user_id = ?", [team_uuid, req.userId]);
    if (!membership || membership.role !== 0) return res.status(403).json({ error: "只有管理员能生成邀请码" });

    const code = Math.random().toString(36).substring(2, 8).toUpperCase();
    const expiresAt = Date.now() + expires_in_days * 24 * 60 * 60 * 1000;

    try {
        await dbRun("INSERT INTO team_invitations (code, team_uuid, creator_id, expires_at, max_uses) VALUES (?, ?, ?, ?, ?)",
            [code, team_uuid, req.userId, expiresAt, max_uses]);
        res.json({ success: true, code, expires_at: expiresAt });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// 直接通过邮箱邀请
app.post('/api/teams/members/add', requireAuth, async (req, res) => {
    const { team_uuid, email } = req.body;
    const membership = await dbGet("SELECT role FROM team_members WHERE team_uuid = ? AND user_id = ?", [team_uuid, req.userId]);
    if (!membership || membership.role !== 0) return res.status(403).json({ error: "只有管理员可以邀请成员" });

    const invitee = await dbGet("SELECT id FROM users WHERE email = ?", [email]);
    if (!invitee) return res.status(404).json({ error: "该邮箱对应的用户不存在" });

    try {
        await dbRun(`INSERT INTO team_join_requests (team_uuid, user_id, status, requested_at)
                     VALUES (?, ?, 3, ?)
                         ON CONFLICT(team_uuid, user_id) DO UPDATE SET status=3, requested_at=excluded.requested_at`,
            [team_uuid, invitee.id, Date.now()]);

        broadcastToRoom(`user:${invitee.id}`, {
            action: 'NEW_INVITATION',
            team_uuid: team_uuid,
            team_name: (await dbGet("SELECT name FROM teams WHERE uuid = ?", [team_uuid]))?.name || '未知团队'
        });

        res.json({ success: true, message: "邀请已发出，待用户确认" });
    } catch (e) {
        if (e.message.includes("UNIQUE")) return res.status(400).json({ error: "该用户已在团队中" });
        res.status(500).json({ error: e.message });
    }
});

// 通过邀请码加入
// 🚀 旧版兼容：加入团队 (现在统一转为申请制)
app.post('/api/teams/join', requireAuth, async (req, res) => {
    const { code } = req.body;
    if (!code) return res.status(400).json({ error: "请输入邀请码" });

    try {
        const normalizedCode = String(code).trim().toUpperCase();
        const invite = await dbGet("SELECT * FROM team_invitations WHERE code = ? AND expires_at > ? AND current_uses < max_uses", [normalizedCode, Date.now()]);
        if (!invite) return res.status(404).json({ error: "邀请码无效或已过期" });

        // 🚀 Uni-Sync 4.0 增强：检查是否已是成员
        const existingMember = await dbGet("SELECT 1 FROM team_members WHERE team_uuid = ? AND user_id = ?", [invite.team_uuid, req.userId]);
        if (existingMember) return res.status(400).json({ error: "您已是该团队成员" });

        // 插入或更新申请状态为 Pending (0)
        await dbRun(`INSERT INTO team_join_requests (team_uuid, user_id, status, requested_at)
                     VALUES (?, ?, 0, ?)
                         ON CONFLICT(team_uuid, user_id) DO UPDATE SET status=0, requested_at=excluded.requested_at`,
            [invite.team_uuid, req.userId, Date.now()]);

        // 获取用户信息以提供更好的消息提示
        const user = await dbGet("SELECT username FROM users WHERE id = ?", [req.userId]);
        const team = await dbGet("SELECT name FROM teams WHERE uuid = ?", [invite.team_uuid]);

        // 记录系统消息
        await dbRun("INSERT INTO team_system_messages (team_uuid, user_id, type, message, timestamp) VALUES (?, ?, 'JOIN_REQUEST', ?, ?)",
            [invite.team_uuid, req.userId, `用户 ${user?.username || req.userId} 申请加入团队 「${team?.name || '未知团队'}」`, Date.now()]);

        broadcastToRoom(`team:${invite.team_uuid}`, { 
            action: 'NEW_JOIN_REQUEST', 
            team_uuid: invite.team_uuid, 
            user_id: req.userId,
            delta: { message: `用户 ${user?.username || req.userId} 申请加入团队 「${team?.name || '未知团队'}」` }
        });

        res.json({ success: true, message: "申请已提交，等待管理员审批" });
    } catch (e) {
        console.error(`${getTime()} [加入团队错误]`, e.message);
        res.status(500).json({ error: e.message });
    }
});

// 解散团队 (仅管理员)
app.post('/api/teams/delete', requireAuth, async (req, res) => {
    const { team_uuid } = req.body;
    const membership = await dbGet("SELECT role FROM team_members WHERE team_uuid = ? AND user_id = ?", [team_uuid, req.userId]);
    if (!membership || membership.role !== 0) return res.status(403).json({ error: "只有管理员能解散团队" });

    const release = await dbLock.acquire();
    let inTransaction = false;
    try {
        await dbRun('BEGIN TRANSACTION');
        inTransaction = true;
        await dbRun("DELETE FROM teams WHERE uuid = ?", [team_uuid]);
        await dbRun("DELETE FROM team_members WHERE team_uuid = ?", [team_uuid]);
        await dbRun("DELETE FROM team_invitations WHERE team_uuid = ?", [team_uuid]);
        // 将属于该团队的待办设为私有 (team_uuid = NULL)
        await dbRun("UPDATE todos SET team_uuid = NULL WHERE team_uuid = ?", [team_uuid]);
        await dbRun('COMMIT');
        inTransaction = false;
        res.json({ success: true });
    } catch (e) {
        if (inTransaction) await dbRun('ROLLBACK');
        res.status(500).json({ error: e.message });
    } finally {
        release();
    }
});

// 退出团队
app.post('/api/teams/leave', requireAuth, async (req, res) => {
    const { team_uuid } = req.body;
    try {
        // 记录退出消息
        await dbRun("INSERT INTO team_system_messages (team_uuid, user_id, type, message, timestamp) VALUES (?, ?, 'MEMBER_EXIT', ?, ?)",
            [team_uuid, req.userId, `成员已退出团队`, Date.now()]);

        await dbRun("DELETE FROM team_members WHERE team_uuid = ? AND user_id = ?", [team_uuid, req.userId]);
        
        // 通知管理员
        broadcastToRoom(`team:${team_uuid}`, { action: 'TEAM_MEMBER_LEFT', team_uuid: team_uuid, user_id: req.userId });
        
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// 获取独立待办的所有成员完成情况
app.get('/api/teams/todo_status', requireAuth, async (req, res) => {
    const { todo_uuid } = req.query;
    if (!todo_uuid) return res.status(400).json({ error: "缺少 todo_uuid" });

    try {
        // 先查出这个待办所在的团队，以及它是共享还是独立
        const todo = await dbGet("SELECT team_uuid, collab_type FROM todos WHERE uuid = ?", [todo_uuid]);
        if (!todo || !todo.team_uuid) return res.status(404).json({ error: "任务不存在或非团队任务" });

        // 校验权限：调用者必须属于该团队
        const membership = await dbGet("SELECT joined_at FROM team_members WHERE team_uuid = ? AND user_id = ?", [todo.team_uuid, req.userId]);
        if (!membership) return res.status(403).json({ error: "无权查看该团队任务状态" });

        // 查询团队所有成员及其完成情况
        const status = await dbAll(`
            SELECT u.id as user_id, u.username, u.email, u.avatar_url, tc.is_completed, tc.updated_at
            FROM users u
                     JOIN team_members tm ON u.id = tm.user_id
                     LEFT JOIN todo_completions tc ON u.id = tc.user_id AND tc.todo_uuid = ?
            WHERE tm.team_uuid = ?
        `, [todo_uuid, todo.team_uuid]);

        res.json({ success: true, data: status });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// 管理员重置成员任务状态 (撤回完成)
app.post('/api/teams/reset_todo_status', requireAuth, async (req, res) => {
    const { todo_uuid, target_user_id } = req.body;
    if (!todo_uuid || !target_user_id) return res.status(400).json({ success: false, error: "缺少必要参数" });

    try {
        // 1. 获取任务信息
        const todo = await dbGet("SELECT team_uuid FROM todos WHERE uuid = ?", [todo_uuid]);
        if (!todo || !todo.team_uuid) return res.status(404).json({ success: false, error: "任务不存在" });

        // 2. 校验权限：调用者必须是该团队的管理员
        const membership = await dbGet("SELECT role FROM team_members WHERE team_uuid = ? AND user_id = ?", [todo.team_uuid, req.userId]);
        if (!membership || membership.role !== 0) {
            return res.status(403).json({ success: false, error: "仅管理员可重置他人任务状态" });
        }

        // 3. 执行重置 (存入记录为 0 以保留更新时间)
        await dbRun(`INSERT OR REPLACE INTO todo_completions (todo_uuid, user_id, is_completed, updated_at) VALUES (?, ?, 0, ?)`,
            [todo_uuid, target_user_id, Date.now()]);

        console.log(`${getTime()} [任务管理] 管理员 ${req.userId} 重置了成员 ${target_user_id} 的任务完成状态: ${todo_uuid}`);
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ success: false, error: e.message });
    }
});

// 成员自行完成独立任务
app.post('/api/teams/self_complete_todo', requireAuth, async (req, res) => {
    const { todo_uuid } = req.body;
    if (!todo_uuid) return res.status(400).json({ success: false, error: "缺少 todo_uuid" });

    try {
        const todo = await dbGet("SELECT team_uuid, collab_type FROM todos WHERE uuid = ?", [todo_uuid]);
        if (!todo || todo.collab_type !== 1) return res.status(400).json({ success: false, error: "非独立协作任务" });

        const now = Date.now();
        await dbRun(`INSERT OR REPLACE INTO todo_completions (todo_uuid, user_id, is_completed, updated_at) VALUES (?, ?, 1, ?)`,
            [todo_uuid, req.userId, now]);

        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ success: false, error: e.message });
    }
});

// 成员自行撤回独立任务完成状态
app.post('/api/teams/self_reset_todo', requireAuth, async (req, res) => {
    const { todo_uuid } = req.body;
    if (!todo_uuid) return res.status(400).json({ success: false, error: "缺少 todo_uuid" });

    try {
        await dbRun(`INSERT OR REPLACE INTO todo_completions (todo_uuid, user_id, is_completed, updated_at) VALUES (?, ?, 0, ?)`,
            [todo_uuid, req.userId, Date.now()]);
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ success: false, error: e.message });
    }
});

// 获取团队成员列表
app.get('/api/teams/members', requireAuth, async (req, res) => {
    let { team_uuid } = req.query;
    if (!team_uuid) return res.status(400).json({ error: "缺少 team_uuid" });
    team_uuid = team_uuid.trim();

    console.log(`${getTime()} [团队管理] 用户 ${req.userId} 正在请求团队成员列表: ${team_uuid}`);

    // 校验发起者是否属于该团队
    const membership = await dbGet("SELECT joined_at FROM team_members WHERE team_uuid = ? AND user_id = ?", [team_uuid, req.userId]);
    if (!membership) {
        console.warn(`${getTime()} [权限拦截] 用户 ${req.userId} 不在团队 ${team_uuid} 中`);
        return res.status(403).json({ error: "无权查看该团队成员" });
    }

    try {
        const members = await dbAll(`
            SELECT u.id as user_id, u.username, u.email, u.avatar_url, tm.role, tm.joined_at
            FROM team_members tm
                     JOIN users u ON tm.user_id = u.id
            WHERE tm.team_uuid = ?
            ORDER BY tm.role ASC, tm.joined_at ASC
        `, [team_uuid]);
        console.log(`${getTime()} [团队管理] 成功返回 ${members.length} 名成员`);
        res.json({ success: true, members });
    } catch (e) {
        console.error(`${getTime()} [查询错误]`, e.message);
        res.status(500).json({ error: e.message });
    }
});

// 移除团队成员 (仅管理员)
app.post('/api/teams/members/remove', requireAuth, async (req, res) => {
    const { team_uuid, target_user_id } = req.body;

    // 1. 校验发起者权限
    const scanner = await dbGet("SELECT role FROM team_members WHERE team_uuid = ? AND user_id = ?", [team_uuid, req.userId]);
    if (!scanner || scanner.role !== 0) return res.status(403).json({ error: "只有管理员能移除成员" });

    if (parseInt(target_user_id) === req.userId) return res.status(400).json({ error: "不能移除自己" });

    try {
        await dbRun("DELETE FROM team_members WHERE team_uuid = ? AND user_id = ?", [team_uuid, target_user_id]);

        // 记录系统消息
        await dbRun("INSERT INTO team_system_messages (team_uuid, user_id, type, message, timestamp) VALUES (?, ?, 'MEMBER_REMOVED', ?, ?)",
            [team_uuid, target_user_id, `成员被移出团队`, Date.now()]);

        // 🚀 核心修复：通知被移除的用户，使其本地能够清理团队数据
        broadcastToRoom(`user:${target_user_id}`, {
            action: 'TEAM_REMOVED',
            team_uuid: team_uuid,
            message: "你已被移出团队"
        });

        // 同时通知团队房间其他成员
        broadcastToRoom(`team:${team_uuid}`, {
            action: 'TEAM_MEMBER_LEFT',
            team_uuid: team_uuid,
            user_id: target_user_id
        });

        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// ==========================================


// ==========================================
// 🚀 模块 B.2: 团队公告 (Announcements)
// ==========================================

// 发布公告 (仅管理员)
app.post('/api/teams/announcements/create', requireAuth, async (req, res) => {
    const { team_uuid, title, content, is_priority, expires_at } = req.body;
    if (!team_uuid || !title || !content) return res.status(400).json({ error: "参数不完整" });

    // 校验权限
    const membership = await dbGet("SELECT role FROM team_members WHERE team_uuid = ? AND user_id = ?", [team_uuid, req.userId]);
    if (!membership || membership.role !== 0) return res.status(403).json({ error: "只有管理员能发布公告" });

    const uuid = crypto.randomUUID ? crypto.randomUUID() : crypto.randomBytes(16).toString('hex');
    const now = Date.now();

    try {
        await dbRun("INSERT INTO team_announcements (uuid, team_uuid, creator_id, title, content, is_priority, expires_at, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [uuid, team_uuid, req.userId, title, content, is_priority ? 1 : 0, expires_at || null, now, now]);

        // 广播通知
        broadcastToRoom(`team:${team_uuid}`, {
            action: 'NEW_ANNOUNCEMENT',
            team_uuid,
            announcement: { uuid, title, content, is_priority: is_priority ? 1 : 0, expires_at: expires_at || null, created_at: now, creator_id: req.userId }
        });

        res.json({ success: true, uuid });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// 撤回公告 (仅管理员)
app.post('/api/teams/announcements/delete', requireAuth, async (req, res) => {
    const { announcement_uuid } = req.body;
    if (!announcement_uuid) return res.status(400).json({ error: "缺少公告 UUID" });

    try {
        const ann = await dbGet("SELECT team_uuid FROM team_announcements WHERE uuid = ?", [announcement_uuid]);
        if (!ann) return res.status(404).json({ error: "公告不存在" });

        // 校验权限
        const membership = await dbGet("SELECT role FROM team_members WHERE team_uuid = ? AND user_id = ?", [ann.team_uuid, req.userId]);
        if (!membership || membership.role !== 0) return res.status(403).json({ error: "无权撤回公告" });

        await dbRun("DELETE FROM team_announcements WHERE uuid = ?", [announcement_uuid]);
        await dbRun("DELETE FROM team_announcement_reads WHERE announcement_uuid = ?", [announcement_uuid]);

        broadcastToRoom(`team:${ann.team_uuid}`, {
            action: 'ANNOUNCEMENT_RECALLED',
            announcement_uuid
        });

        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// 获取团队公告列表
app.get('/api/teams/announcements', requireAuth, async (req, res) => {
    const { team_uuid } = req.query;
    if (!team_uuid) return res.status(400).json({ error: "缺少 team_uuid" });

    // 校验权限
    const membership = await dbGet("SELECT joined_at FROM team_members WHERE team_uuid = ? AND user_id = ?", [team_uuid, req.userId]);
    if (!membership) return res.status(403).json({ error: "无权查看该团队公告" });

    try {
        const now = Date.now();
        const announcements = await dbAll(`
            SELECT a.*, u.username as creator_name,
                   (SELECT COUNT(*) FROM team_announcement_reads WHERE announcement_uuid = a.uuid AND user_id = ?) as is_read
            FROM team_announcements a
            JOIN users u ON a.creator_id = u.id
            WHERE a.team_uuid = ? AND (a.expires_at IS NULL OR a.expires_at > ?)
            ORDER BY a.created_at DESC
        `, [req.userId, team_uuid, now]);
        res.json({ success: true, announcements });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// 确认已读
app.post('/api/teams/announcements/read', requireAuth, async (req, res) => {
    const { announcement_uuid } = req.body;
    if (!announcement_uuid) return res.status(400).json({ error: "缺少 announcement_uuid" });

    try {
        await dbRun("INSERT OR IGNORE INTO team_announcement_reads (announcement_uuid, user_id, read_at) VALUES (?, ?, ?)",
            [announcement_uuid, req.userId, Date.now()]);
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// 获取阅读统计 (仅管理员)
app.get('/api/teams/announcements/stats', requireAuth, async (req, res) => {
    const { announcement_uuid } = req.query;
    if (!announcement_uuid) return res.status(400).json({ error: "缺少 announcement_uuid" });

    try {
        const announcement = await dbGet("SELECT team_uuid, creator_id FROM team_announcements WHERE uuid = ?", [announcement_uuid]);
        if (!announcement) return res.status(404).json({ error: "公告不存在" });

        // 校验权限：管理员
        const membership = await dbGet("SELECT role FROM team_members WHERE team_uuid = ? AND user_id = ?", [announcement.team_uuid, req.userId]);
        if (!membership || membership.role !== 0) return res.status(403).json({ error: "只有管理员能查看统计" });

        const totalMembers = await dbGet("SELECT COUNT(*) as count FROM team_members WHERE team_uuid = ?", [announcement.team_uuid]);
        const readCount = await dbGet("SELECT COUNT(*) as count FROM team_announcement_reads WHERE announcement_uuid = ?", [announcement_uuid]);

        const readMembers = await dbAll(`
            SELECT u.username, r.read_at
            FROM team_announcement_reads r
            JOIN users u ON r.user_id = u.id
            WHERE r.announcement_uuid = ?
        `, [announcement_uuid]);

        res.json({
            success: true,
            total_members: totalMembers.count,
            read_count: readCount.count,
            read_rate: totalMembers.count > 0 ? (readCount.count / totalMembers.count) : 0,
            read_members: readMembers
        });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// ==========================================
// 🚀 模块 C: 核心 Delta Sync (增量同步)
// ==========================================
// --- 忽略项管理 ---
app.post('/api/sync/ignore_remote_item', requireAuth, async (req, res) => {
    const { uuid, table_name, team_uuid } = req.body;
    const user_id = req.user_id;

    if (!uuid || !table_name) {
        return res.status(400).json({ success: false, message: 'Missing parameters' });
    }

    try {
        await dbRun(
            `INSERT OR REPLACE INTO user_ignored_items (user_id, uuid, table_name, ignored_at) VALUES (?, ?, ?, ?)`,
            [user_id, uuid, table_name, Date.now()]
        );
        console.log(`${getTime()} [忽略记录] 用户 ${user_id} 忽略了 ${table_name}.${uuid}`);
        res.json({ success: true });
    } catch (e) {
        console.error('Failed to ignore item:', e);
        res.status(500).json({ success: false, message: e.message });
    }
});

app.post('/api/sync', requireAuth, async (req, res) => {
    const payload = req.body;
    const user_id = parseInt(payload.user_id, 10);
    const { last_sync_time = 0, device_id, screen_time } = payload;

    // 🛠️ 诊断日志：确认请求是否到达服务器
    console.log(`${getTime()} 🔄 [同步开始] 用户ID: ${user_id}, 设备: ${device_id}, 任务数: ${(payload.todos || []).length}`);
    const todos = payload.todos || payload.todos_changes || payload.todosChanges || [];
    const countdowns = payload.countdowns || payload.countdowns_changes || payload.countdownsChanges || [];
    // 🚀 增加 payload.todoGroups 别名兼容
    const todoGroups = payload.todo_groups || payload.todo_groups_changes || payload.todoGroupsChanges || payload.todoGroups || [];
    const timeLogs = payload.time_logs_changes || payload.timeLogsChanges || [];

    if (req.userId !== user_id) return res.status(403).json({ error: "越权操作被拒绝" });
    if (!device_id) return res.status(400).json({ error: "缺少 device_id" });

    const now = Date.now();
    const sync_conflicts = []; // 收集本次同步发现的冲突项

    // 🚀 核心工具：更鲁棒的差异检测，防止 null/0/-1 等默认值差异触发假冲突
    const isSame = (a, b, isReminder = false) => {
        const norm = (v) => (v === null || v === undefined || v === 0 || v === '0' || v === '' || v === 'null' || (isReminder && (v === -1 || v === '-1'))) ? null : v;
        return norm(a) === norm(b);
    };

    const limitError = await enforceSyncLimit(user_id, now);
    if (limitError === 'IGNORE') return res.json({ success: true, server_todos: [], server_countdowns: [], server_time_logs: [], new_sync_time: last_sync_time });
    if (limitError) return res.status(429).json({ error: limitError });

    const release = await dbLock.acquire();
    let inTransaction = false;
    try {
        await dbRun('BEGIN TRANSACTION');
        inTransaction = true;

        // 🚀 核心安全：获取用户当前加入的所有团队，用于越权检测与增量过滤
        const userTeams = await dbAll("SELECT team_uuid FROM team_members WHERE user_id = ?", [user_id]);
        const teamUuids = userTeams.map(t => t.team_uuid);

        // 🚀 记录本轮同步涉及到的房间，用于后续批量广播，防止“广播风暴”导致 OOM 和死循环
        const roomsToNotify = new Set();
        const addToNotify = (tUuid) => {
            if (tUuid) roomsToNotify.add(`team:${tUuid}`);
            else roomsToNotify.add(`user:${user_id}`);
        };

        // 1. 处理 Todos
        for (const t of todos) {
            const tUuid = String(t.uuid ?? t.id ?? t._id);
            const tContent = String(t.content ?? t.title ?? "");
            const tIsCompleted = (t.is_completed ?? t.isCompleted ?? t.isDone) ? 1 : 0;
            const tIsDeleted = (t.is_deleted ?? t.isDeleted) ? 1 : 0;
            const tUpdatedAtClient = normalizeToMs(t.updated_at ?? t.updatedAt ?? now);
            const tVersion = parseInt(t.version || 1, 10);
            let finalVersion = tVersion; // 🚀 用于广播的最终版本号
            const tCreatedAt = normalizeToMs(t.created_at ?? t.createdAt) || now;
            const tRecurrence = parseInt(t.recurrence ?? 0, 10);
            const tCustomIntervalDays = t.customIntervalDays ?? t.custom_interval_days ?? null;
            const tRecurrenceEndDate = ('recurrence_end_date' in t || 'recurrenceEndDate' in t) ? (normalizeToMs(t.recurrenceEndDate ?? t.recurrence_end_date) || null) : null;
            const tRemark = t.remark != null ? String(t.remark) : null;
            const tCollabTypeRaw = parseInt(t.collab_type ?? t.collabType ?? 0, 10);
            const tIsAllDayRaw = (t.is_all_day ?? t.isAllDay) ? 1 : 0;
            const tReminderMinutes = t.reminderMinutes ?? t.reminder_minutes ?? null;
            // 核心修复：仅通过 UUID 查找，不限制 user_id，确保同一任务在全库唯一，实现真正的多人协作
            let existing = await dbGet(`
                SELECT t.*, 
                       tm.name as team_name,
                       tg.name as group_name
                FROM todos t
                LEFT JOIN teams tm ON t.team_uuid = tm.uuid
                LEFT JOIN todo_groups tg ON t.group_id = tg.uuid
                WHERE t.uuid = ?
            `, [tUuid]);
            if (!existing) {
                existing = await dbGet(`
                    SELECT t.*, 
                           tm.name as team_name,
                           tg.name as group_name
                    FROM todos t
                    LEFT JOIN teams tm ON t.team_uuid = tm.uuid
                    LEFT JOIN todo_groups tg ON t.group_id = tg.uuid
                    WHERE t.user_id = ? AND t.content = ? AND (t.uuid IS NULL OR t.uuid = '')
                `, [user_id, tContent]);
            }

            let tTeamUuid = existing ? existing.team_uuid : null;
            if (t.hasOwnProperty('team_uuid') || t.hasOwnProperty('teamUuid')) {
                const targetTeam = t.team_uuid ?? t.teamUuid;
                // 🚀 安全检查：只能将任务分配给自己所属的团队
                if (targetTeam && !teamUuids.includes(targetTeam)) {
                    // 🚀 优化：对高频安全警告进行限流打印，防止日志灌满 I/O 导致 GC 卡顿
                    if (Math.random() < 0.05) {
                        console.warn(`[安全警报-抽样] 用户 ${user_id} 试图将任务 ${tUuid} 分配给未加入的团队 ${targetTeam}`);
                    }
                    tTeamUuid = existing ? existing.team_uuid : null;
                } else {
                    tTeamUuid = targetTeam;
                }
            }

            let tGroupId = existing ? existing.group_id : null;
            if (t.hasOwnProperty('group_id')) {
                tGroupId = t.group_id;
            } else if (t.hasOwnProperty('groupId')) {
                tGroupId = t.groupId;
            }

            let tDueDate = existing ? existing.due_date : null;
            if (t.hasOwnProperty('due_date') || t.hasOwnProperty('dueDate')) {
                tDueDate = normalizeToMs(t.due_date ?? t.dueDate) || null;
            }

            let tCreatedDate = existing ? existing.created_date : null;
            if (t.hasOwnProperty('created_date') || t.hasOwnProperty('createdDate')) {
                tCreatedDate = normalizeToMs(t.created_date ?? t.createdDate) || null;
            }

            let tCategoryId = existing ? existing.category_id : null;
            if (t.hasOwnProperty('category_id') || t.hasOwnProperty('categoryId')) {
                tCategoryId = t.category_id || t.categoryId || null;
            }

            // 🚀 核心修复：旧版本客户端兼容性处理 (字段继承)
            // 如果客户端没有传这些字段（旧版本），则保留服务端现有的值，防止被默认值(0)覆盖
            const tCollabType = (t.hasOwnProperty('collab_type') || t.hasOwnProperty('collabType'))
                ? tCollabTypeRaw
                : (existing ? (existing.collab_type ?? 0) : tCollabTypeRaw);

            const tIsAllDay = (t.hasOwnProperty('is_all_day') || t.hasOwnProperty('isAllDay'))
                ? tIsAllDayRaw
                : (existing ? (existing.is_all_day ?? 0) : tIsAllDayRaw);

            // 🚀 核心修复：强制净化逻辑。如果是全天任务，或者客户端传来 has_conflict = 0 且版本大幅增加，
            // 服务端应无条件信任客户端的“已解决”状态。
            let tHasConflictFromClient = (t.has_conflict ?? t.hasConflict) ? 1 : 0;
            if (tIsAllDay === 1 || tHasConflictFromClient === 0) {
                // 如果是全天任务，或者是客户端主动标记为“无冲突”
                tHasConflictFromClient = 0;
            }

            // 智能冲突检测 (逻辑冲突：时间重叠)
            const scheduleConflict = await checkItemConflict(t, user_id);
            if (scheduleConflict) sync_conflicts.push({ type: 'schedule_conflict', item: t, conflict_with: scheduleConflict });

            if (!existing) {
                // 新增任务：当前用户即为创建者
                const finalUpdatedAt = Math.max(tUpdatedAtClient, now);
                await dbRun(
                    `INSERT INTO todos (uuid, user_id, content, is_completed, is_deleted, created_at, updated_at, version, device_id, due_date, created_date, recurrence, custom_interval_days, recurrence_end_date, remark, group_id, team_uuid, category_id, collab_type, reminder_minutes, is_all_day) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
                    [tUuid, user_id, tContent, tIsCompleted, tIsDeleted, tCreatedAt, finalUpdatedAt, tVersion, device_id, tDueDate, tCreatedDate, tRecurrence, tCustomIntervalDays, tRecurrenceEndDate, tRemark, tGroupId, tTeamUuid, tCategoryId, tCollabType, tReminderMinutes, tIsAllDay]
                );

                await recordAuditLog({
                    team_uuid: tTeamUuid,
                    user_id,
                    target_table: 'todos',
                    target_uuid: tUuid,
                    op_type: 'INSERT',
                    after_data: t
                });

                // 🌟 独立任务特殊处理
                if (tCollabType === 1) {
                    await dbRun(`INSERT OR REPLACE INTO todo_completions (todo_uuid, user_id, is_completed, updated_at) VALUES (?, ?, ?, ?)`,
                        [tUuid, user_id, tIsCompleted, now]);
                }
            } else {
                // 🚀 安全检查：越权尝试拦截
                const isOwner = existing.user_id === user_id;
                const isTeamMember = existing.team_uuid && teamUuids.includes(existing.team_uuid);
                if (!isOwner && !isTeamMember) {
                    console.warn(`[拒绝越权修改] 用户 ${user_id} 试图修改不属于自己的任务 ${tUuid}`);
                    continue;
                }

                // 更新任务：检测版本冲突
                const serverVersion = existing.version || 0;
                // 🚀 核心修复：协作任务 (collab_type=1) 的完成状态存储在独立表中，主表中的状态不应触发冲突判定
                const isDataDifferent = 
                    !isSame(tContent, existing.content) || 
                    (tCollabType === 0 && !isSame(tIsCompleted, existing.is_completed)) || 
                    !isSame(tIsDeleted, existing.is_deleted) ||
                    !isSame(tRemark, existing.remark) ||
                    !isSame(tGroupId, existing.group_id) ||
                    !isSame(tTeamUuid, existing.team_uuid) ||
                    !isSame(tCategoryId, existing.category_id) ||
                    !isSame(tDueDate, existing.due_date) ||
                    !isSame(tCreatedDate, existing.created_date) ||
                    !isSame(tRecurrence, existing.recurrence) ||
                    !isSame(tIsAllDay, existing.is_all_day) ||
                    !isSame(tCollabType, existing.collab_type) ||
                    !isSame(tReminderMinutes, existing.reminder_minutes, true);
                
                let conflictDetected = false;
                if (tVersion <= serverVersion && isDataDifferent) {
                    // 🚀 冲突判定：客户端版本不高于服务端，但数据不同（说明服务端已被他人更新或客户端基于旧版修改）
                    conflictDetected = true;
                    sync_conflicts.push({
                        type: 'version_conflict',
                        item: t,
                        conflict_with: existing,
                        message: `检测到版本冲突 (Client V${tVersion} vs Server V${serverVersion})`
                    });

                    // 标记为冲突挂起 (Flagging)
                    await dbRun(`UPDATE todos SET has_conflict = 1, conflict_data = ?, updated_at = ? WHERE uuid = ?`, [safeSnapshotJson(existing, 'todos'), now, tUuid]);
                    console.log(`${getTime()} ⚠️ [冲突检测] 任务 ${tUuid} 已标记为冲突挂起`);
                }
                // 一旦判定冲突，本轮不再继续覆盖更新，避免冲突标记被随后逻辑清除。
                if (conflictDetected) {
                    continue;
                }

                // 更新逻辑
                const existingCreatedAt = normalizeToMs(existing.created_at) || tCreatedAt;
                const finalCreatedAt = Math.min(tCreatedAt, existingCreatedAt) || existingCreatedAt;
                const finalUpdatedAt = Math.max(tUpdatedAtClient, normalizeToMs(existing.updated_at) || 0, now);

                // 🚀 初始化 finalVersion 为当前服务端版本，防止 regression
                finalVersion = existing.version || tVersion;

                // 🚀 Gravestone 保护逻辑
                const finalIsDeleted = (existing.is_deleted === 1 && tIsDeleted === 0)
                    ? (tVersion > existing.version ? 0 : 1)
                    : tIsDeleted;

                if (tVersion > serverVersion || tUpdatedAtClient > normalizeToMs(existing.updated_at)) {
                    // 🚀 核心修复：版本号保护逻辑 (防止版本回退)
                    finalVersion = Math.max(tVersion, serverVersion + 1);

                    // 只有当新版本更高时才覆盖，否则保持现状或仅标记冲突
                    if (tCollabType === 0) {
                        await dbRun(
                            `UPDATE todos SET content=?, is_completed=?, is_deleted=?, created_at=?, updated_at=?, version=?, device_id=?, due_date=?, created_date=?, recurrence=?, custom_interval_days=?, recurrence_end_date=?, remark=?, group_id=?, team_uuid=?, category_id=?, collab_type=?, reminder_minutes=?, is_all_day=?, has_conflict=? WHERE uuid=?`,
                            [tContent, tIsCompleted, finalIsDeleted, finalCreatedAt, finalUpdatedAt, finalVersion, device_id, tDueDate, tCreatedDate, 'recurrence' in t ? tRecurrence : existing.recurrence, ('custom_interval_days' in t || 'customIntervalDays' in t) ? tCustomIntervalDays : existing.custom_interval_days, ('recurrence_end_date' in t || 'recurrenceEndDate' in t) ? tRecurrenceEndDate : existing.recurrence_end_date, 'remark' in t ? tRemark : existing.remark, tGroupId, tTeamUuid, tCategoryId, tCollabType, ('reminder_minutes' in t || 'reminderMinutes' in t) ? tReminderMinutes : existing.reminder_minutes, tIsAllDay, tHasConflictFromClient, tUuid]
                        );
                    } else {
                        await dbRun(
                            `UPDATE todos SET content=?, is_deleted=?, created_at=?, updated_at=?, version=?, device_id=?, due_date=?, created_date=?, recurrence=?, custom_interval_days=?, recurrence_end_date=?, remark=?, group_id=?, team_uuid=?, category_id=?, collab_type=?, reminder_minutes=?, is_all_day=?, has_conflict=? WHERE uuid=?`,
                            [tContent, finalIsDeleted, finalCreatedAt, finalUpdatedAt, finalVersion, device_id, tDueDate, tCreatedDate, 'recurrence' in t ? tRecurrence : existing.recurrence, ('custom_interval_days' in t || 'customIntervalDays' in t) ? tCustomIntervalDays : existing.custom_interval_days, ('recurrence_end_date' in t || 'recurrenceEndDate' in t) ? tRecurrenceEndDate : existing.recurrence_end_date, 'remark' in t ? tRemark : existing.remark, tGroupId, tTeamUuid, tCategoryId, tCollabType, ('reminder_minutes' in t || 'reminderMinutes' in t) ? tReminderMinutes : existing.reminder_minutes, tIsAllDay, tHasConflictFromClient, tUuid]
                        );
                        await dbRun(`INSERT OR REPLACE INTO todo_completions (todo_uuid, user_id, is_completed, updated_at) VALUES (?, ?, ?, ?)`,
                            [tUuid, user_id, tIsCompleted, finalUpdatedAt]);
                    }

                    if (isDataDifferent) {
                        await recordAuditLog({
                            team_uuid: tTeamUuid,
                            user_id,
                            target_table: 'todos',
                            target_uuid: tUuid,
                            op_type: 'UPDATE',
                            before_data: existing,
                            after_data: t
                        });
                    }
                }
            }
            // 🚀 联动清理：如果任务标记为完成或删除，清理内存中的 WebSocket 专注状态（解决用户反馈的结束任务远端还在计时问题）
            if (tIsCompleted === 1 || (existing && existing.is_deleted === 0 && tIsDeleted === 1)) {
                const cleanFocus = (stateMap, key, roomKey) => {
                    const state = stateMap.get(key);
                    if (state && (state.todo_uuid === tUuid || state.todoUuid === tUuid)) {
                        console.log(`${getTime()} [同步联动清理] 任务 ${tUuid} 已完成/删除，清理房间 ${roomKey} 的专注状态`);
                        stateMap.delete(key);
                        broadcastToRoom(roomKey, { action: 'FINISH', todo_uuid: tUuid, reason: 'task_completed' });
                    }
                };
                cleanFocus(userFocusStates, user_id, `user:${user_id}`);
                if (tTeamUuid) cleanFocus(teamFocusStates, tTeamUuid, `team:${tTeamUuid}`);
            }

            // 🚀 收集变更房间，待请求结束时统一广播
            addToNotify(tTeamUuid);
            const oldTeamUuid = existing ? existing.team_uuid : null;

            // 如果团队发生了变更（如撤回私有），记录墓碑并通知原团队房间刷新（防止幽灵数据）
            if (oldTeamUuid && oldTeamUuid !== tTeamUuid) {
                console.log(`${getTime()} 📢 [团队解绑] 记录墓碑并通知团队 ${oldTeamUuid} 移除任务 ${tUuid}`);
                await dbRun("INSERT INTO team_tombstones (team_uuid, item_uuid, updated_at) VALUES (?, ?, ?)", [oldTeamUuid, tUuid, now]);
                broadcastToRoom(`team:${oldTeamUuid}`, { action: 'TEAM_UPDATE', type: 'todo', data: { uuid: tUuid, team_uuid: null } });
            }
        }

        // 2. 处理 Countdowns
        for (const c of countdowns) {
            // 🚀 修复：增加 crypto.randomUUID() 兜底，防止存入 "undefined" 字符串导致无限覆盖
            const cUuidRaw = c.uuid ?? c.id ?? c._id ?? (crypto.randomUUID ? crypto.randomUUID() : crypto.randomBytes(16).toString('hex'));
            const cUuid = String(cUuidRaw);
            // 🚀 修复：兼容前端可能传 name 的情况
            const cTitle = String(c.title ?? c.name ?? "");
            const cTargetTime = ('target_time' in c || 'targetTime' in c || 'targetDate' in c) ? (normalizeToMs(c.target_time ?? c.targetTime ?? c.targetDate) || null) : null;
            const cIsDeleted = (c.is_deleted ?? c.isDeleted) ? 1 : 0;
            const cUpdatedAtClient = normalizeToMs(c.updated_at ?? c.updatedAt ?? now);
            const cVersion = parseInt(c.version || 1, 10);
            const cCreatedAt = normalizeToMs(c.created_at ?? c.createdAt) || now;

            let existing = await dbGet("SELECT * FROM countdowns WHERE uuid = ?", [cUuid]);
            if (!existing) existing = await dbGet("SELECT * FROM countdowns WHERE user_id = ? AND title = ? AND (uuid IS NULL OR uuid = '')", [user_id, cTitle]);

            let tTeamUuid = c.team_uuid || c.teamUuid || null;
            // 🚀 安全检查
            if (tTeamUuid && !teamUuids.includes(tTeamUuid)) tTeamUuid = existing ? existing.team_uuid : null;

            if (!existing) {
                await dbRun(`INSERT OR REPLACE INTO countdowns (uuid, user_id, title, target_time, is_deleted, created_at, updated_at, version, device_id, team_uuid) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
                    [cUuid, user_id, cTitle, cTargetTime, cIsDeleted, cCreatedAt, now, cVersion, device_id, tTeamUuid]);
                
                await recordAuditLog({ team_uuid: tTeamUuid, user_id, target_table: 'countdowns', target_uuid: cUuid, op_type: 'INSERT', after_data: c });
            } else {
                // 🚀 安全检查
                if (existing.user_id !== user_id && (!existing.team_uuid || !teamUuids.includes(existing.team_uuid))) {
                    console.warn(`[拒绝越权修改] 用户 ${user_id} 试图修改不属于自己的倒计时 ${cUuid}`);
                    continue;
                }
                const finalCreatedAt = Math.min(cCreatedAt, normalizeToMs(existing.created_at) || cCreatedAt);
                const oldTeamUuid = existing.team_uuid;

                // 冲突检测
                const serverVersion = existing.version || 0;
                const isDataDifferent = !isSame(cTitle, existing.title) || !isSame(cTargetTime, existing.target_time) || !isSame(cIsDeleted, existing.is_deleted);

                if (cVersion <= serverVersion && isDataDifferent) {
                    sync_conflicts.push({ type: 'version_conflict', item: c, conflict_with: existing, message: `倒计时冲突 (Client V${cVersion} vs Server V${serverVersion})` });
                    await dbRun(`UPDATE countdowns SET has_conflict = 1, conflict_data = ?, updated_at = ? WHERE uuid = ?`, [safeSnapshotJson(existing, 'countdowns'), now, cUuid]);
                    // 保持冲突挂起，避免同轮后续更新把 has_conflict 清零。
                    continue;
                }

                if (cVersion > serverVersion || cUpdatedAtClient > normalizeToMs(existing.updated_at) || !existing.uuid) {
                    const finalVersion = Math.max(cVersion, serverVersion + 1);
                    await dbRun(`UPDATE countdowns SET uuid=?, title=?, target_time=?, is_deleted=?, created_at=?, updated_at=?, version=?, device_id=?, team_uuid=?, has_conflict=0 WHERE uuid=?`,
                        [cUuid, cTitle, cTargetTime ?? existing.target_time, cIsDeleted, finalCreatedAt, now, finalVersion, device_id, tTeamUuid, cUuid]);

                    await recordAuditLog({ team_uuid: tTeamUuid, user_id, target_table: 'countdowns', target_uuid: cUuid, op_type: 'UPDATE', before_data: existing, after_data: c });

                    // 🚀 收集变更房间
                    addToNotify(tTeamUuid);

                    // 🚀 墓碑逻辑
                    if (oldTeamUuid && oldTeamUuid !== tTeamUuid) {
                        console.log(`${getTime()} 📢 [团队解绑-倒计时] 记录墓碑并通知团队 ${oldTeamUuid} 移除倒计时 ${cUuid}`);
                        await dbRun("INSERT INTO team_tombstones (team_uuid, item_uuid, updated_at) VALUES (?, ?, ?)", [oldTeamUuid, cUuid, now]);
                        broadcastToRoom(`team:${oldTeamUuid}`, { action: 'TEAM_UPDATE', type: 'countdown', data: { uuid: cUuid, team_uuid: null } });
                    }
                }
            }
        }

        // 2.5 处理 Todo Groups (文件夹)
        for (const g of todoGroups) {
            const gUuidRaw = g.uuid ?? g.id ?? g._id ?? (crypto.randomUUID ? crypto.randomUUID() : crypto.randomBytes(16).toString('hex'));
            const gUuid = String(gUuidRaw);
            const gName = String(g.name ?? g.title ?? "未命名分组");
            const gIsExpanded = (g.is_expanded ?? g.isExpanded) ? 1 : 0;
            const gIsDeleted = (g.is_deleted ?? g.isDeleted) ? 1 : 0;
            const gVersion = parseInt(g.version || 1, 10);
            const gUpdatedAtClient = normalizeToMs(g.updated_at ?? g.updatedAt ?? now);
            const gCreatedAt = normalizeToMs(g.created_at ?? g.createdAt) || now;
            let gTeamUuid = g.team_uuid || g.teamUuid || null;
            if (gTeamUuid && !teamUuids.includes(gTeamUuid)) gTeamUuid = null;

            let existing = await dbGet("SELECT user_id, team_uuid, uuid, version, updated_at, name, is_deleted FROM todo_groups WHERE uuid = ?", [gUuid]);
            if (!existing) {
                await dbRun(`INSERT OR REPLACE INTO todo_groups (uuid, user_id, name, is_expanded, is_deleted, version, created_at, updated_at, team_uuid) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
                    [gUuid, user_id, gName, gIsExpanded, gIsDeleted, gVersion, gCreatedAt, now, gTeamUuid]);
                await recordAuditLog({ team_uuid: gTeamUuid, user_id, target_table: 'todo_groups', target_uuid: gUuid, op_type: 'INSERT', after_data: g });
            } else {
                // 🚀 安全检查
                if (existing.user_id !== user_id && (!existing.team_uuid || !teamUuids.includes(existing.team_uuid))) {
                    console.warn(`[拒绝越权修改] 用户 ${user_id} 试图修改不属于自己的分组 ${gUuid}`);
                    continue;
                }
                // 冲突检测
                const isDataDifferent = !isSame(gName, existing.name) || !isSame(gIsDeleted, existing.is_deleted) || !isSame(gIsExpanded, existing.is_expanded);
                if (gVersion <= (existing.version || 0) && isDataDifferent) {
                    sync_conflicts.push({ type: 'version_conflict', item: g, conflict_with: existing, message: `分组冲突 (Client V${gVersion} vs Server V${existing.version})` });
                    await dbRun(`UPDATE todo_groups SET has_conflict = 1, conflict_data = ?, updated_at = ? WHERE uuid = ?`, [safeSnapshotJson(existing, 'todo_groups'), now, gUuid]);
                    // 保持冲突挂起，避免同轮后续更新把 has_conflict 清零。
                    continue;
                }

                if (gVersion > (existing.version || 0) || gUpdatedAtClient > normalizeToMs(existing.updated_at)) {
                    const finalVersion = Math.max(gVersion, (existing.version || 0) + 1);
                    await dbRun(`UPDATE todo_groups SET name=?, is_expanded=?, is_deleted=?, version=?, updated_at=?, team_uuid=?, has_conflict=0 WHERE uuid=?`,
                        [gName, gIsExpanded, gIsDeleted, finalVersion, now, gTeamUuid, gUuid]);
                    await recordAuditLog({ team_uuid: gTeamUuid, user_id, target_table: 'todo_groups', target_uuid: gUuid, op_type: 'UPDATE', before_data: existing, after_data: g });
                }
            }
        }

        // 2.6 处理 Pomodoro Tags
        const pomodoro_tags = payload.pomodoro_tags || payload.pomodoro_tags_changes || [];
        for (const tag of pomodoro_tags) {
            const uuid = String(tag.uuid ?? '');
            if (!uuid) continue;
            const name = String(tag.name ?? '');
            const color = String(tag.color ?? '#607D8B');
            const isDeleted = (tag.is_deleted ?? tag.isDeleted) ? 1 : 0;
            const version = parseInt(tag.version ?? 1, 10);
            const createdAt = normalizeToMs(tag.created_at ?? tag.createdAt) || now;
            const updatedAt = normalizeToMs(tag.updated_at ?? tag.updatedAt) || now;

            const existing = await dbGet("SELECT version, updated_at FROM pomodoro_tags WHERE uuid = ? AND user_id = ?", [uuid, user_id]);
            if (!existing) {
                await dbRun("INSERT OR REPLACE INTO pomodoro_tags (uuid, user_id, name, color, is_deleted, version, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?)", [uuid, user_id, name, color, isDeleted, version, createdAt, updatedAt]);
            } else if (version > (existing.version || 0) || updatedAt > normalizeToMs(existing.updated_at)) {
                await dbRun("UPDATE pomodoro_tags SET name = ?, color = ?, is_deleted = ?, version = ?, updated_at = ? WHERE uuid = ? AND user_id = ?", [name, color, isDeleted, version, updatedAt, uuid, user_id]);
            }
        }

        // 2.7 处理 Pomodoro Records
        const pomodoro_records = payload.pomodoro_records || payload.pomodoro_records_changes || [];
        for (const r of pomodoro_records) {
            const uuid = String(r.uuid ?? '');
            if (!uuid) continue;
            const todoUuid = r.todo_uuid ? String(r.todo_uuid) : null;
            const startTime = normalizeToMs(r.start_time) || now;
            const endTime = r.end_time != null ? (normalizeToMs(r.end_time) || null) : null;
            const plannedDuration = typeof r.planned_duration === 'number' ? r.planned_duration : parseInt(r.planned_duration || 25 * 60, 10);
            const actualDuration = r.actual_duration != null ? parseInt(r.actual_duration, 10) : null;
            const status = ['completed', 'interrupted', 'switched'].includes(r.status) ? r.status : 'completed';
            const deviceId = r.device_id ? String(r.device_id) : null;
            const isDeleted = (r.is_deleted ?? r.isDeleted) ? 1 : 0;
            const version = parseInt(r.version ?? 1, 10);
            const createdAt = normalizeToMs(r.created_at ?? r.createdAt) || now;
            const updatedAt = normalizeToMs(r.updated_at ?? r.updatedAt) || now;
            const existingRec = await dbGet("SELECT version, updated_at, team_uuid FROM pomodoro_records WHERE uuid = ? AND user_id = ?", [uuid, user_id]);
            const rTeamUuid = ('team_uuid' in r || 'teamUuid' in r) ? (r.team_uuid || r.teamUuid || null) : (existingRec ? existingRec.team_uuid : null);

            // 智能冲突检测
            const conflict = await checkItemConflict(r, user_id);
            if (conflict) sync_conflicts.push({ type: 'pomodoro', item: r, conflict_with: conflict });

            if (!existingRec) {
                await dbRun(`INSERT OR REPLACE INTO pomodoro_records (uuid, user_id, todo_uuid, start_time, end_time, planned_duration, actual_duration, status, device_id, is_deleted, version, created_at, updated_at, team_uuid) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
                    [uuid, user_id, todoUuid, startTime, endTime, plannedDuration, actualDuration, status, deviceId, isDeleted, version, createdAt, updatedAt, rTeamUuid]);
            } else if (version > (existingRec.version || 0) || updatedAt > normalizeToMs(existingRec.updated_at)) {
                await dbRun(`UPDATE pomodoro_records SET todo_uuid=?, start_time=?, end_time=?, planned_duration=?, actual_duration=?, status=?, device_id=?, is_deleted=?, version=?, updated_at=?, team_uuid=? WHERE uuid=? AND user_id=?`,
                    [todoUuid, startTime, endTime, plannedDuration, actualDuration, status, deviceId, isDeleted, version, updatedAt, rTeamUuid, uuid, user_id]);
            }
            broadcastToRoom(rTeamUuid ? `team:${rTeamUuid}` : `user:${user_id}`, { action: 'SYNC_DATA', type: 'pomodoro_record', data: r });
        }

        // 3. 处理 Time Logs
        for (const l of timeLogs) {
            const lUuid = String(l.uuid ?? l.id ?? l._id);
            const lTitle = String(l.title ?? "");
            const lTagUuids = JSON.stringify(l.tag_uuids ?? l.tagUuids ?? []);
            const lStartTime = normalizeToMs(l.start_time ?? l.startTime) || now;
            const lEndTime = normalizeToMs(l.end_time ?? l.endTime) || now;
            const lRemark = l.remark != null ? String(l.remark) : null;
            const lIsDeleted = (l.is_deleted ?? l.isDeleted) ? 1 : 0;
            const lUpdatedAtClient = normalizeToMs(l.updated_at ?? l.updatedAt ?? now);
            const lVersion = parseInt(l.version || 1, 10);
            const lCreatedAt = normalizeToMs(l.created_at ?? l.createdAt) || now;

            let existing = await dbGet("SELECT uuid, version, created_at, updated_at FROM time_logs WHERE uuid = ? AND user_id = ?", [lUuid, user_id]);

            if (!existing) {
                await dbRun(`INSERT OR REPLACE INTO time_logs (uuid, user_id, title, tag_uuids, start_time, end_time, remark, is_deleted, created_at, updated_at, version, device_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
                    [lUuid, user_id, lTitle, lTagUuids, lStartTime, lEndTime, lRemark, lIsDeleted, lCreatedAt, now, lVersion, device_id]);
            } else {
                const finalCreatedAt = Math.min(lCreatedAt, normalizeToMs(existing.created_at) || lCreatedAt);
                if (lVersion > (existing.version || 0) || lUpdatedAtClient > normalizeToMs(existing.updated_at) || !existing.uuid) {
                    await dbRun(`UPDATE time_logs SET title=?, tag_uuids=?, start_time=?, end_time=?, remark=?, is_deleted=?, created_at=?, updated_at=?, version=?, device_id=? WHERE uuid=?`,
                        [lTitle, lTagUuids, lStartTime, lEndTime, lRemark, lIsDeleted, finalCreatedAt, now, lVersion, device_id, existing.uuid]);
                }
            }
        }

        // 4. 处理屏幕时间
        if (screen_time) {
            const devName = screen_time.device_name || screen_time.deviceName;
            const recDate = screen_time.record_date || screen_time.recordDate;
            const apps = screen_time.apps;

            if (devName && recDate && Array.isArray(apps)) {
                for (const app of apps) {
                    const appName = app.app_name || app.appName;
                    await dbRun(`INSERT INTO screen_time_logs (user_id, device_name, record_date, app_name, duration)
                                 VALUES (?, ?, ?, ?, ?) ON CONFLICT(user_id, device_name, record_date, app_name)
                                 DO UPDATE SET duration = excluded.duration, updated_at = CURRENT_TIMESTAMP`,
                        [user_id, devName.trim(), recDate, appName, app.duration]);
                }
            }
        }

        await dbRun('COMMIT');
        inTransaction = false;

        // 🚀 核心安全：已经在事务开始处获取过 userTeams 和 teamUuids，此处复用即可
        const teamPlaceholders = teamUuids.length > 0 ? teamUuids.map(() => '?').join(',') : "'NONE'";

        // 🚀 获取当前用户忽略的 UUID，防止“僵尸项”在同步中反复复活
        const ignoredItemsRows = await dbAll("SELECT uuid FROM user_ignored_items WHERE user_id = ?", [user_id]);
        const ignoredUuidsSet = new Set(ignoredItemsRows.map(r => r.uuid));

        // 5. 拉取最终增量（包含个人且属于已加入团队的数据）
        let serverTodosRaw = [], serverCountdownsRaw = [], serverTimeLogsRaw = [], serverTodoGroupsRaw = [], serverPomodoroRecordsRaw = [];

        // 核心修复：关联名称，并增加 COALESCE 防止 null 导致显示 “匿名”
        // 🌟 核心改进：对于独立任务 (collab_type = 1)，状态必须从 todo_completions 中实时判定
        // 且同步时必须对比个人完成记录的更新时间 (updated_at)，否则 App 无法感知状态变更
        const todosQuery = `
            SELECT t.*,
                   (CASE
                        WHEN t.collab_type = 1 THEN COALESCE(tc.is_completed, 0)
                        ELSE t.is_completed
                       END) as actual_is_completed,
                   MAX(t.updated_at, COALESCE(tc.updated_at, 0)) as actual_updated_at,
                   COALESCE(u.username, '用户' || t.user_id) as creator_name,
                   COALESCE(tm.name, '个人团队') as team_name
            FROM todos t
                     LEFT JOIN users u ON t.user_id = u.id
                     LEFT JOIN teams tm ON t.team_uuid = tm.uuid
                     LEFT JOIN todo_completions tc ON tc.todo_uuid = t.uuid AND tc.user_id = ?
            WHERE (t.user_id = ? OR (t.team_uuid IN (${teamPlaceholders})))
              AND (t.updated_at >= ? OR (tc.updated_at IS NOT NULL AND tc.updated_at >= ?))
        `;

        try {
            const params = [user_id, user_id, ...teamUuids, last_sync_time, last_sync_time];
            serverTodosRaw = await dbAll(todosQuery, params);
        } catch (e) {
            console.error(`[同步查询错误: todos] 预期参数: ${4 + teamUuids.length}, 实传: ${params.length}, 错误: ${e.message}`);
            throw e;
        }

        // 🚀 核心修复：拉取墓碑数据（被撤回或剔除出团队的项）
        let tombstonesRaw = [];
        try {
            const tsParams = [...teamUuids, last_sync_time];
            const tsQuery = `SELECT item_uuid, updated_at FROM team_tombstones WHERE team_uuid IN (${teamPlaceholders}) AND updated_at >= ?`;
            tombstonesRaw = await dbAll(tsQuery, tsParams);
        } catch (e) {
            console.error(`[同步查询错误: tombstones] 预期参数: ${teamUuids.length + 1}, 实传: ${teamUuids.length + 1}, 错误: ${e.message}`);
        }

        // 其余业务数据也应包含团队内容及元数据
        const buildSyncQuery = (tableName) => {
            // 🚀 安全防御：防止 SQL 注入风险，严格限制可用表名
            const VALID_SYNC_TABLES = ['countdowns', 'todo_groups', 'time_logs', 'pomodoro_records', 'todos'];
            if (!VALID_SYNC_TABLES.includes(tableName)) {
                throw new Error(`Security Exception: Unrecognized sync target table "${tableName}"`);
            }
            return `
                SELECT t.*,
                       COALESCE(u.username, '用户' || t.user_id) as creator_name,
                       COALESCE(tm.name, '个人团队') as team_name
                FROM ${tableName} t
                         LEFT JOIN users u ON t.user_id = u.id
                         LEFT JOIN teams tm ON t.team_uuid = tm.uuid
                WHERE (t.user_id = ? OR (t.team_uuid IN (${teamPlaceholders})))
                  AND t.updated_at >= ?
            `;
        };

        const commonParams = [user_id, ...teamUuids, last_sync_time];
        const commonParamsNoTime = [user_id, ...teamUuids];
        const runSafeQuery = async (label, tableName) => {
            try {
                return await dbAll(buildSyncQuery(tableName), commonParams);
            } catch (e) {
                console.error(`[同步交互查询错误: ${label}] 表: ${tableName}, 预期参数: ${commonParams.length}, 错误: ${e.message}`);
                return [];
            }
        };

        serverCountdownsRaw = await runSafeQuery('countdowns', 'countdowns');
        serverTodoGroupsRaw = await runSafeQuery('todo_groups', 'todo_groups');
        serverTimeLogsRaw = await runSafeQuery('time_logs', 'time_logs');
        serverPomodoroRecordsRaw = await runSafeQuery('pomodoro_records', 'pomodoro_records');

        // 🚀 核心修复：排除掉用户当前仍有权访问的项（防止创建者撤回私有时误删本地数据）
        const activeUuids = new Set();
        [...serverTodosRaw, ...serverCountdownsRaw, ...serverTodoGroupsRaw, ...serverTimeLogsRaw, ...serverPomodoroRecordsRaw]
            .forEach(r => activeUuids.add(r.uuid || String(r.id)));
        const tombstones = tombstonesRaw.filter(t => !activeUuids.has(t.item_uuid));

        // 🚀 Uni-Sync 4.0: 增强型过滤逻辑，解决登录后刷不出数据的痛点
        // 🚀 性能优化：使用 Map 预索引团队加入时间，避免在过滤循环中重复执行 .find()
        const teamJoinedAtMap = new Map();
        userTeams.forEach(ut => teamJoinedAtMap.set(ut.team_uuid, ut.joined_at));

        const filterWithActualTime = (list) => {
            return list.filter(r => {
                // 🚀 核心过滤：如果该项已被用户忽略，则永不下发
                if (ignoredUuidsSet.has(r.uuid || String(r.id))) return false;

                // 🚀 防冲突机制：如果是当前设备刚传上来的，且不是协作项，则不再下发给它自己
                if (r.device_id === device_id && !r.team_uuid) return false;

                return true;
            });
        };

        const filter = (list) => {
            return list.filter(r => {
                // 🚀 核心过滤：如果该项已被用户忽略，则永不下发
                if (ignoredUuidsSet.has(r.uuid || String(r.id))) return false;

                if (r.device_id === device_id && !r.team_uuid) return false;
                return true;
            });
        };

        serverTodosRaw = filterWithActualTime(serverTodosRaw);
        serverCountdownsRaw = filter(serverCountdownsRaw);
        serverTodoGroupsRaw = filter(serverTodoGroupsRaw);
        serverTimeLogsRaw = filter(serverTimeLogsRaw);
        serverPomodoroRecordsRaw = filter(serverPomodoroRecordsRaw);

        const nullableTimestamp = (val) => { const ms = normalizeToMs(val); return ms > 0 ? ms : null; };

        // 🚀 修复 JSON 下发映射，防止前端解析崩溃（关键）
        res.json({
            success: true,
            conflicts: sync_conflicts,
            joined_team_uuids: teamUuids, // 🚀 关键：下发用户加入的团队 ID，供客户端清理孤儿团队数据
            server_todos: [
                ...serverTodosRaw.map(r => ({
                    id: r.uuid, uuid: r.uuid, content: r.content,
                    is_completed: r.actual_is_completed === 1 || r.actual_is_completed === true,
                    is_deleted: r.is_deleted === 1 || r.is_deleted === true, version: r.version, device_id: r.device_id, category_id: r.category_id ?? null, created_at: normalizeToMs(r.created_at),
                    updated_at: normalizeToMs(r.actual_updated_at || r.updated_at),
                    created_date: nullableTimestamp(r.created_date), due_date: nullableTimestamp(r.due_date), recurrence: r.recurrence ?? 0, customIntervalDays: r.custom_interval_days ?? null, custom_interval_days: r.custom_interval_days ?? null, recurrenceEndDate: nullableTimestamp(r.recurrence_end_date), recurrence_end_date: nullableTimestamp(r.recurrence_end_date), remark: r.remark ?? null, group_id: r.group_id ?? null, team_uuid: r.team_uuid ?? null, creator_name: r.creator_name ?? null, team_name: r.team_name ?? null, collab_type: r.collab_type ?? 0, reminder_minutes: r.reminder_minutes ?? null, reminderMinutes: r.reminder_minutes ?? null, is_all_day: r.is_all_day === 1 || r.is_all_day === true, isAllDay: r.is_all_day === 1 || r.is_all_day === true,
                    has_conflict: r.has_conflict === 1,
                    conflict_data: r.conflict_data ? JSON.parse(r.conflict_data) : null
                })),
                ...tombstones.map(t => ({
                    // 🚀 修复：墓碑数据必须补齐必填字段，否则会引发 Flutter/Dart 空指针崩溃！
                    uuid: t.item_uuid, content: "", is_deleted: true, updated_at: t.updated_at, version: 999999, is_completed: false
                }))
            ],
            server_countdowns: [
                ...serverCountdownsRaw.map(r => ({
                    id: r.uuid, uuid: r.uuid,
                    title: r.title || "", // 防空保护
                    is_deleted: r.is_deleted === 1 || r.is_deleted === true, version: r.version, device_id: r.device_id, created_at: normalizeToMs(r.created_at), updated_at: normalizeToMs(r.updated_at),
                    target_time: nullableTimestamp(r.target_time),
                    targetDate: nullableTimestamp(r.target_time), // 🚀 兼容某些前端版本
                    team_uuid: r.team_uuid ?? null, team_name: r.team_name ?? null, creator_name: r.creator_name ?? null,
                    has_conflict: r.has_conflict === 1,
                    conflict_data: r.conflict_data ? JSON.parse(r.conflict_data) : null
                })),
                ...tombstones.map(t => ({
                    // 🚀 修复：提供 title 和 target_time 默认值防止解析失败
                    uuid: t.item_uuid, title: "", target_time: null, is_deleted: true, updated_at: t.updated_at, version: 999999
                }))
            ],
            server_todo_groups: serverTodoGroupsRaw.map(r => ({
                id: r.uuid, uuid: r.uuid,
                name: r.name || "",
                title: r.name || "", // 🚀 双重映射：防止前端期待的是 title
                is_expanded: r.is_expanded === 1 || r.is_expanded === true, is_deleted: r.is_deleted === 1 || r.is_deleted === true, version: r.version, created_at: normalizeToMs(r.created_at), updated_at: normalizeToMs(r.updated_at),
                team_uuid: r.team_uuid ?? null, team_name: r.team_name ?? null, creator_name: r.creator_name ?? null,
                has_conflict: r.has_conflict === 1,
                conflict_data: r.conflict_data ? JSON.parse(r.conflict_data) : null
            })),
            // 🚀 兼容性防御：如果前端模型叫 server_todoGroups
            server_todoGroups: serverTodoGroupsRaw.map(r => ({
                id: r.uuid, uuid: r.uuid, name: r.name || "", title: r.name || "", is_expanded: r.is_expanded === 1 || r.is_expanded === true, is_deleted: r.is_deleted === 1 || r.is_deleted === true, version: r.version, created_at: normalizeToMs(r.created_at), updated_at: normalizeToMs(r.updated_at), team_uuid: r.team_uuid ?? null, team_name: r.team_name ?? null, creator_name: r.creator_name ?? null
            })),
            server_time_logs: serverTimeLogsRaw.filter(r => last_sync_time === 0 || normalizeToMs(r.updated_at) >= last_sync_time).map(r => {
                let parsedTags = [];
                try { parsedTags = JSON.parse(r.tag_uuids || '[]'); } catch (e) { }
                return { id: r.uuid, uuid: r.uuid, title: r.title, tag_uuids: parsedTags, start_time: normalizeToMs(r.start_time), end_time: normalizeToMs(r.end_time), remark: r.remark ?? null, is_deleted: r.is_deleted === 1 || r.is_deleted === true, version: r.version, device_id: r.device_id, created_at: normalizeToMs(r.created_at), updated_at: normalizeToMs(r.updated_at) };
            }),
            server_pomodoro_tags: (await dbAll(`SELECT * FROM pomodoro_tags WHERE (user_id = ? OR (team_uuid IN (${teamPlaceholders})))`, commonParamsNoTime)).filter(r => last_sync_time === 0 || normalizeToMs(r.updated_at) >= last_sync_time).map(r => ({
                uuid: r.uuid, name: r.name, color: r.color, is_deleted: r.is_deleted === 1 || r.is_deleted === true, version: r.version, created_at: normalizeToMs(r.created_at), updated_at: normalizeToMs(r.updated_at)
            })),
            server_pomodoro_records: serverPomodoroRecordsRaw.map(r => ({
                uuid: r.uuid, todo_uuid: r.todo_uuid, start_time: normalizeToMs(r.start_time), end_time: normalizeToMs(r.end_time), planned_duration: r.planned_duration, actual_duration: r.actual_duration, status: r.status, device_id: r.device_id, is_deleted: r.is_deleted === 1 || r.is_deleted === true, version: r.version, created_at: normalizeToMs(r.created_at), updated_at: normalizeToMs(r.updated_at), team_uuid: r.team_uuid || null
            })),
            joined_team_uuids: teamUuids, // 🚀 传回当前加入的团队列表
            independent_completions: await dbAll(`SELECT todo_uuid, is_completed FROM todo_completions WHERE user_id = ?`, [user_id]),
            new_sync_time: now
        });

        // 🚀 批量发送同步广播，每个房间仅发一次，大幅降低 WS 负载
        roomsToNotify.forEach(roomKey => {
            broadcastToRoom(roomKey, { action: 'SYNC_DATA' });
        });

    } catch (e) {
        if (inTransaction) await dbRun('ROLLBACK');
        console.error(`${getTime()} [同步严重错误]`, e.message);
        if (!res.headersSent) {
            res.status(500).json({ error: e.message });
        }
    } finally {
        release();
    }
});


// ==========================================
// 🚀 模块 C-2: 版本记录与一键回滚 (History & Rollback)
// ==========================================

/**
 * 获取特定项的操作历史
 */
app.get('/api/sync/history', requireAuth, async (req, res) => {
    const { uuid, table } = req.query;
    if (!uuid || !table) return res.status(400).json({ error: "缺少 uuid 或 table 参数" });

    try {
        const access = await assertAuditAccess(req, table, uuid);
        if (!access.ok) return res.status(access.code).json({ error: access.error });

        const history = await dbAll(`
            SELECT a.*, u.username as operator_name 
            FROM audit_logs a
            LEFT JOIN users u ON a.user_id = u.id
            WHERE a.target_table = ? AND a.target_uuid = ?
            ORDER BY a.timestamp DESC LIMIT 20
        `, [table, uuid]);

        // 解析数据以便前端展示
        const formattedHistory = history.map(h => ({
            ...h,
            before_data: safeJsonParse(h.before_data),
            after_data: safeJsonParse(h.after_data)
        }));

        res.json({ success: true, history: formattedHistory });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

/**
 * 执行回滚操作
 * 逻辑：取回 audit_logs 中的数据快照，通过版本号+1 的方式强行推送到所有设备
 */
app.post('/api/sync/rollback', requireAuth, async (req, res) => {
    const { log_id } = req.body;
    if (!log_id) return res.status(400).json({ error: "缺少 log_id" });

    const release = await dbLock.acquire();
    let inTransaction = false;
    try {
        const log = await dbGet("SELECT * FROM audit_logs WHERE id = ?", [log_id]);
        if (!log) throw new Error("找不到该记录");

        if (log.team_uuid) {
            const membership = await dbGet(
                "SELECT role FROM team_members WHERE team_uuid = ? AND user_id = ?",
                [log.team_uuid, req.userId]
            );
            if (!membership) return res.status(403).json({ error: "无权限回滚该团队记录" });
        } else if (log.user_id !== req.userId) {
            return res.status(403).json({ error: "无权限回滚该个人记录" });
        }

        const table = log.target_table;
        const uuid = log.target_uuid;
        const restoreData = safeJsonParse(log.before_data, safeJsonParse(log.after_data));
        if (!restoreData) throw new Error("快照数据丢失，无法回滚");

        await dbRun('BEGIN TRANSACTION');
        inTransaction = true;

        const current = await dbGet(`SELECT version FROM ${table} WHERE uuid = ?`, [uuid]);
        const nextVersion = (current ? (current.version || 0) : 0) + 1;
        const now = Date.now();

        if (table === 'todos') {
            await dbRun(
                `UPDATE todos SET 
                    content=?, is_completed=?, is_deleted=?, updated_at=?, version=?, has_conflict=0,
                    remark=?, group_id=?, team_uuid=?, due_date=?, created_date=?, 
                    recurrence=?, custom_interval_days=?, recurrence_end_date=?, 
                    collab_type=?, is_all_day=?, reminder_minutes=?
                 WHERE uuid=?`,
                [
                    restoreData.content, restoreData.is_completed || 0, restoreData.is_deleted || 0, now, nextVersion,
                    restoreData.remark || null, restoreData.group_id || null, restoreData.team_uuid || null,
                    restoreData.due_date || null, restoreData.created_date || null,
                    restoreData.recurrence || 0, restoreData.custom_interval_days || null, restoreData.recurrence_end_date || null,
                    restoreData.collab_type || 0, restoreData.is_all_day || 0, restoreData.reminder_minutes || null,
                    uuid
                ]
            );
        } else if (table === 'countdowns') {
            await dbRun(
                `UPDATE countdowns SET title=?, target_time=?, is_deleted=?, updated_at=?, version=?, has_conflict=0 WHERE uuid=?`,
                [restoreData.title, restoreData.target_time, restoreData.is_deleted || 0, now, nextVersion, uuid]
            );
        } else if (table === 'todo_groups') {
            await dbRun(
                `UPDATE todo_groups SET name=?, is_deleted=?, version=?, updated_at=?, has_conflict=0 WHERE uuid=?`,
                [restoreData.name, restoreData.is_deleted || 0, nextVersion, now, uuid]
            );
        } else {
            throw new Error(`暂不支持对表 ${table} 执行一键回滚`);
        }

        await recordAuditLog({
            team_uuid: log.team_uuid,
            user_id: req.userId,
            target_table: table,
            target_uuid: uuid,
            op_type: 'ROLLBACK',
            before_data: current,
            after_data: restoreData
        });

        await dbRun('COMMIT');
        inTransaction = false;

        if (log.team_uuid) {
            broadcastToRoom(`team:${log.team_uuid}`, { action: 'SYNC_DATA', type: table });
        }

        res.json({ success: true, message: "已成功恢复至指定版本", new_version: nextVersion });

    } catch (e) {
        if (inTransaction) await dbRun('ROLLBACK');
        res.status(500).json({ error: e.message });
    } finally {
        release();
    }
});

// ==========================================
// 🚀 冲突解决接口
// ==========================================
app.post('/api/sync/resolve_conflict', requireAuth, async (req, res) => {
    const { uuid, table, resolution, version, data } = req.body;

    if (!uuid || !table || !resolution) {
        return res.status(400).json({ error: "缺少必要参数 uuid/table/resolution" });
    }

    const validTables = ['todos', 'countdowns', 'todo_groups', 'pomodoro_records', 'pomodoro_tags'];
    if (!validTables.includes(table)) {
        return res.status(400).json({ error: `不支持的表类型: ${table}` });
    }

    const release = await dbLock.acquire();
    try {
        const existing = table === 'todos'
            ? await dbGet(`SELECT * FROM todos WHERE uuid = ?`, [uuid])
            : await dbGet(`SELECT * FROM ${table} WHERE uuid = ? AND user_id = ?`, [uuid, req.userId]);
        if (!existing) {
            return res.status(404).json({ error: "未找到对应记录" });
        }
        if (table === 'todos' && existing.user_id !== req.userId) {
            const membership = existing.team_uuid
                ? await dbGet("SELECT 1 FROM team_members WHERE team_uuid = ? AND user_id = ?", [existing.team_uuid, req.userId])
                : null;
            if (!membership) {
                return res.status(403).json({ error: "无权处理该团队待办冲突" });
            }
        }

        const now = Date.now();
        const pick = (obj, snake, camel, fallback = null) => {
            if (!obj) return fallback;
            if (Object.prototype.hasOwnProperty.call(obj, snake)) return obj[snake];
            if (camel && Object.prototype.hasOwnProperty.call(obj, camel)) return obj[camel];
            return fallback;
        };
        const pickMs = (obj, snake, camel, fallback = null) => {
            const raw = pick(obj, snake, camel, undefined);
            if (raw === undefined) return fallback;
            const ms = normalizeToMs(raw);
            return ms > 0 ? ms : null;
        };
        const pickBoolInt = (obj, snake, camel, fallback = 0) => {
            const raw = pick(obj, snake, camel, undefined);
            if (raw === undefined || raw === null) return fallback;
            return raw === 1 || raw === true || raw === '1' || raw === 'true' ? 1 : 0;
        };
        if (resolution === 'keep_local') {
            // Client kept local version — accept the bumped version and clear conflict
            const finalVersion = version || (existing.version || 0) + 1;
            const clientUpdatedAt = pickMs(data, 'updated_at', 'updatedAt', 0) || 0;
            const finalUpdatedAt = Math.max(clientUpdatedAt, normalizeToMs(existing.updated_at) || 0, now);
            let updateSql;
            let updateParams;

            if (table === 'todos') {
                updateSql = `UPDATE todos SET has_conflict = 0, conflict_data = NULL, version = ?, updated_at = ? WHERE uuid = ? AND user_id = ?`;
                updateParams = [finalVersion, finalUpdatedAt, uuid, req.userId];
            } else if (table === 'countdowns') {
                updateSql = `UPDATE countdowns SET has_conflict = 0, conflict_data = NULL, version = ?, updated_at = ? WHERE uuid = ? AND user_id = ?`;
                updateParams = [finalVersion, finalUpdatedAt, uuid, req.userId];
            } else if (table === 'todo_groups') {
                updateSql = `UPDATE todo_groups SET has_conflict = 0, conflict_data = NULL, version = ?, updated_at = ? WHERE uuid = ?`;
                updateParams = [finalVersion, finalUpdatedAt, uuid];
            } else if (table === 'pomodoro_records') {
                updateSql = `UPDATE pomodoro_records SET has_conflict = 0, conflict_data = NULL, version = ?, updated_at = ? WHERE uuid = ? AND user_id = ?`;
                updateParams = [finalVersion, finalUpdatedAt, uuid, req.userId];
            } else if (table === 'pomodoro_tags') {
                updateSql = `UPDATE pomodoro_tags SET has_conflict = 0, conflict_data = NULL, version = ?, updated_at = ? WHERE uuid = ? AND user_id = ?`;
                updateParams = [finalVersion, finalUpdatedAt, uuid, req.userId];
            }

            // If client provided full data with keep_local, overwrite server with local
            if (data && table === 'todos') {
                await dbRun(
                    `UPDATE todos SET has_conflict = 0, conflict_data = NULL,
                     content = ?, is_completed = ?, is_deleted = ?, version = ?, updated_at = ?, created_at = ?,
                     due_date = ?, remark = ?, group_id = ?, team_uuid = ?,
                     recurrence = ?, is_all_day = ?, reminder_minutes = ?, created_date = ?,
                     collab_type = ?, category_id = ?, custom_interval_days = ?, recurrence_end_date = ?, device_id = ?
                     WHERE uuid = ?`,
                    [
                        pick(data, 'content', 'title', existing.content),
                        pickBoolInt(data, 'is_completed', 'isCompleted', existing.is_completed),
                        pickBoolInt(data, 'is_deleted', 'isDeleted', existing.is_deleted),
                        finalVersion, finalUpdatedAt,
                        pickMs(data, 'created_at', 'createdAt', normalizeToMs(existing.created_at) || pickMs(data, 'created_date', 'createdDate', now) || now),
                        pickMs(data, 'due_date', 'dueDate', normalizeToMs(existing.due_date) || null),
                        pick(data, 'remark', null, existing.remark),
                        pick(data, 'group_id', 'groupId', existing.group_id),
                        pick(data, 'team_uuid', 'teamUuid', existing.team_uuid),
                        pick(data, 'recurrence', null, existing.recurrence ?? 0),
                        pickBoolInt(data, 'is_all_day', 'isAllDay', existing.is_all_day),
                        pick(data, 'reminder_minutes', 'reminderMinutes', existing.reminder_minutes),
                        pickMs(data, 'created_date', 'createdDate', normalizeToMs(existing.created_date) || null),
                        pick(data, 'collab_type', 'collabType', existing.collab_type ?? 0),
                        pick(data, 'category_id', 'categoryId', existing.category_id),
                        pick(data, 'custom_interval_days', 'customIntervalDays', existing.custom_interval_days),
                        pickMs(data, 'recurrence_end_date', 'recurrenceEndDate', normalizeToMs(existing.recurrence_end_date) || null),
                        pick(data, 'device_id', 'deviceId', existing.device_id),
                        uuid
                    ]
                );
            } else if (data && table === 'countdowns') {
                await dbRun(
                    `UPDATE countdowns SET has_conflict = 0, conflict_data = NULL,
                     title = ?, target_time = ?, is_deleted = ?, is_completed = ?,
                     version = ?, updated_at = ?, team_uuid = ?
                     WHERE uuid = ? AND user_id = ?`,
                    [
                        data.title || existing.title,
                        data.target_time || data.targetTime || existing.target_time,
                        data.is_deleted != null ? (data.is_deleted ? 1 : 0) : existing.is_deleted,
                        data.is_completed != null ? (data.is_completed ? 1 : 0) : existing.is_completed,
                        finalVersion, finalUpdatedAt,
                        data.team_uuid || data.teamUuid || existing.team_uuid,
                        uuid, req.userId
                    ]
                );
            } else if (data && table === 'todo_groups') {
                await dbRun(
                    `UPDATE todo_groups SET has_conflict = 0, conflict_data = NULL,
                     name = ?, is_deleted = ?, is_expanded = ?, version = ?, updated_at = ?,
                     team_uuid = ?
                     WHERE uuid = ?`,
                    [
                        data.name || existing.name,
                        data.is_deleted != null ? (data.is_deleted ? 1 : 0) : existing.is_deleted,
                        data.is_expanded != null ? (data.is_expanded ? 1 : 0) : existing.is_expanded,
                        finalVersion, finalUpdatedAt,
                        data.team_uuid || data.teamUuid || existing.team_uuid,
                        uuid
                    ]
                );
            } else {
                await dbRun(updateSql, updateParams);
            }
        } else if (resolution === 'accept_server') {
            // Client accepted server version — just clear the conflict flag
            if (table === 'todos') {
                const finalCreatedAt = normalizeToMs(existing.created_at) || normalizeToMs(existing.created_date) || now;
                await dbRun(`UPDATE todos SET has_conflict = 0, conflict_data = NULL, created_at = ?, updated_at = ? WHERE uuid = ?`, [finalCreatedAt, now, uuid]);
            } else if (table === 'countdowns') {
                await dbRun(`UPDATE countdowns SET has_conflict = 0, conflict_data = NULL, updated_at = ? WHERE uuid = ? AND user_id = ?`, [now, uuid, req.userId]);
            } else if (table === 'todo_groups') {
                await dbRun(`UPDATE todo_groups SET has_conflict = 0, conflict_data = NULL, updated_at = ? WHERE uuid = ?`, [now, uuid]);
            } else if (table === 'pomodoro_records') {
                await dbRun(`UPDATE pomodoro_records SET has_conflict = 0, conflict_data = NULL, updated_at = ? WHERE uuid = ? AND user_id = ?`, [now, uuid, req.userId]);
            } else if (table === 'pomodoro_tags') {
                await dbRun(`UPDATE pomodoro_tags SET has_conflict = 0, conflict_data = NULL, updated_at = ? WHERE uuid = ? AND user_id = ?`, [now, uuid, req.userId]);
            }
        } else {
            return res.status(400).json({ error: `未知 resolution: ${resolution}` });
        }

        res.json({ success: true, message: "冲突已解决" });
    } catch (e) {
        console.error("resolve_conflict error:", e);
        res.status(500).json({ error: e.message });
    } finally {
        release();
    }
});


// ==========================================
// 🚀 模块: 屏幕时间独立接口
// ==========================================
app.post('/api/screen_time', requireAuth, async (req, res) => {
    const { user_id, apps } = req.body;
    const device_name = req.body.device_name || req.body.deviceName;
    const record_date = req.body.record_date || req.body.recordDate;

    const now = Date.now();

    const release = await dbLock.acquire();
    let inTransaction = false;
    try {
        await dbRun('BEGIN TRANSACTION');
        inTransaction = true;
        for (const app of apps) {
            const appName = app.app_name || app.appName;
            await dbRun(`
                        INSERT INTO screen_time_logs (user_id, device_name, record_date, app_name, duration, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?)
                            ON CONFLICT(user_id, device_name, record_date, app_name)
                DO UPDATE SET duration = excluded.duration, updated_at = ?`,
                [user_id, device_name.trim(), record_date, appName, app.duration, now, now]);
        }
        await dbRun('COMMIT');
        inTransaction = false;
        res.json({ success: true });
    } catch (err) {
        if (inTransaction) await dbRun('ROLLBACK');
        res.status(500).json({ error: err.message });
    } finally {
        release();
    }
});

app.get('/api/screen_time', requireAuth, async (req, res) => {
    const userId = parseInt(req.query.user_id, 10);
    const date = req.query.date; // 格式 YYYY-MM-DD

    if (req.userId !== userId) {
        return res.status(403).json({ error: "越权访问" });
    }

    try {
        const sql = `
            SELECT
                COALESCE(m.mapped_name, s.app_name) AS app_name,
                COALESCE(m.category, '未分类') AS category,
                s.device_name,
                SUM(s.duration) AS duration
            FROM screen_time_logs s
                     LEFT JOIN app_name_mappings m ON s.app_name = m.package_name
            WHERE s.user_id = ? AND s.record_date = ?
            GROUP BY
                COALESCE(m.mapped_name, s.app_name),
                COALESCE(m.category, '未分类'),
                s.device_name
            ORDER BY duration DESC
        `;

        const rows = await dbAll(sql, [userId, date]);
        res.json(rows);
    } catch (err) {
        console.error("查询屏幕时间失败:", err);
        res.status(500).json({ error: "服务器内部错误" });
    }
});

// ==========================================
// 模块 E: 课程表、设置
// ==========================================
app.post('/api/settings', requireAuth, async (req, res) => {
    const semStart = req.body.semester_start != null ? normalizeToMs(req.body.semester_start) : null;
    const semEnd = req.body.semester_end != null ? normalizeToMs(req.body.semester_end) : null;
    await dbRun("UPDATE users SET semester_start = ?, semester_end = ? WHERE id = ?", [semStart, semEnd, req.userId]);
    res.json({ success: true });
});

app.get('/api/settings', requireAuth, async (req, res) => {
    const row = await dbGet("SELECT semester_start, semester_end FROM users WHERE id = ?", [req.userId]);
    res.json({ success: true, semester_start: row?.semester_start ?? null, semester_end: row?.semester_end ?? null });
});

app.post('/api/courses', requireAuth, async (req, res) => {
    const { user_id, courses, semester = "default" } = req.body;
    if (req.userId !== parseInt(user_id, 10)) return res.status(403).json({ error: "越权" });
    const now = Date.now();
    const release = await dbLock.acquire();
    let inTransaction = false;
    try {
        await dbRun("BEGIN TRANSACTION");
        inTransaction = true;
        await dbRun("DELETE FROM courses WHERE user_id = ? AND semester = ?", [user_id, semester]);
        for (const c of courses) {
            c.uuid = c.uuid || (crypto.randomUUID ? crypto.randomUUID() : crypto.randomBytes(16).toString('hex'));
            const scheduleConflict = await checkItemConflict(c, user_id);
            
            if (scheduleConflict) {
                console.log(`${getTime()} ⚠️ [冲突提醒] 课程同步发现时间重叠: ${c.course_name}`);
            }

            await dbRun(`INSERT INTO courses (uuid, user_id, semester, course_name, room_name, teacher_name, start_time, end_time, weekday, week_index, lesson_type, created_at, updated_at, is_deleted, team_uuid, has_conflict) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)`,
                [c.uuid, user_id, semester, c.course_name, c.room_name, c.teacher_name, c.start_time, c.end_time, c.weekday, c.week_index, c.lesson_type, now, now, c.team_uuid || null, scheduleConflict ? 1 : 0]);
            
            await recordAuditLog({ team_uuid: c.team_uuid, user_id, target_table: 'courses', target_uuid: c.uuid, op_type: 'SYNC', after_data: c });
        }
        await dbRun("COMMIT");
        inTransaction = false;
        res.json({ success: true });
    } catch (e) {
        if (inTransaction) await dbRun("ROLLBACK");
        console.error(`${getTime()} [课程同步错误]`, e.message);
        res.status(500).json({ error: e.message });
    } finally {
        release();
    }
});

app.get('/api/courses', requireAuth, async (req, res) => {
    const userId = parseInt(req.query.user_id, 10);
    const semester = req.query.semester || "default";
    if (req.userId !== userId) return res.status(403).json({ error: "越权" });
    const results = await dbAll(`SELECT * FROM courses WHERE user_id = ? AND semester = ? AND is_deleted = 0 ORDER BY week_index, weekday, start_time`, [userId, semester]);
    res.json(results);
});

// ==========================================
// 🍅 模块 H & I & J: 番茄钟完整逻辑
// ==========================================
app.get('/api/pomodoro/tags', requireAuth, async (req, res) => {
    const results = await dbAll("SELECT uuid, name, color, is_deleted, version, created_at, updated_at FROM pomodoro_tags WHERE user_id = ? ORDER BY created_at ASC", [req.userId]);
    res.json(results);
});

app.post('/api/pomodoro/tags', requireAuth, async (req, res) => {
    const { tags } = req.body;
    if (!Array.isArray(tags)) return res.status(400).json({ error: "tags 格式错误" });
    const now = Date.now();
    const release = await dbLock.acquire();
    let inTransaction = false;
    try {
        await dbRun("BEGIN TRANSACTION");
        inTransaction = true;
        for (const tag of tags) {
            const uuid = String(tag.uuid ?? '');
            if (!uuid) continue;
            const name = String(tag.name ?? '');
            const color = String(tag.color ?? '#607D8B');
            const isDeleted = (tag.is_deleted ?? tag.isDeleted) ? 1 : 0;
            const version = parseInt(tag.version ?? 1, 10);
            const createdAt = normalizeToMs(tag.created_at ?? tag.createdAt) || now;
            const updatedAt = normalizeToMs(tag.updated_at ?? tag.updatedAt) || now;

            const existing = await dbGet("SELECT uuid, version, updated_at, name FROM pomodoro_tags WHERE uuid = ? AND user_id = ?", [uuid, req.userId]);
            
            // 冲突检测 (版本冲突)
            const serverVersion = existing ? (existing.version || 0) : 0;
            if (existing && version <= serverVersion && name !== existing.name) {
                console.log(`${getTime()} ⚠️ [冲突检测] 番茄标签 ${uuid} 检测到版本冲突`);
                await dbRun(`UPDATE pomodoro_tags SET has_conflict = 1, conflict_data = ?, updated_at = ? WHERE uuid = ? AND user_id = ?`, [safeSnapshotJson(tag, 'pomodoro_tags'), now, uuid, req.userId]);
            }

            if (!existing) {
                await dbRun("INSERT OR REPLACE INTO pomodoro_tags (uuid, user_id, name, color, is_deleted, version, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?)", [uuid, req.userId, name, color, isDeleted, version, createdAt, updatedAt]);
                await recordAuditLog({ user_id: req.userId, target_table: 'pomodoro_tags', target_uuid: uuid, op_type: 'INSERT', after_data: tag });
            } else if (version > serverVersion || updatedAt > normalizeToMs(existing.updated_at)) {
                await dbRun(
                    "UPDATE pomodoro_tags SET name = ?, color = ?, is_deleted = ?, version = ?, updated_at = ?, has_conflict = 0 WHERE uuid = ? AND user_id = ?",
                    [name, color, isDeleted, version, updatedAt, uuid, req.userId]
                );
                await recordAuditLog({ user_id: req.userId, target_table: 'pomodoro_tags', target_uuid: uuid, op_type: 'UPDATE', before_data: existing, after_data: tag });
            }
        }
        await dbRun("COMMIT");
        inTransaction = false;
        const results = await dbAll("SELECT uuid, name, color, is_deleted, version, created_at, updated_at FROM pomodoro_tags WHERE user_id = ? ORDER BY created_at ASC", [req.userId]);
        res.json({ success: true, tags: results });
    } catch (e) {
        if (inTransaction) await dbRun("ROLLBACK");
        console.error(`${getTime()} [标签同步错误]`, e.message);
        res.status(500).json({ error: e.message });
    } finally {
        release();
    }
});

// --- Uni-Sync V4.0 新增审批流接口 ---

// 1. 发起加入申请
app.post('/api/teams/request_join', requireAuth, async (req, res) => {
    const { invite_code, message, pow_challenge, pow_nonce } = req.body;

    // 🚀 Uni-Sync 安全加固：强制校验算力证明
    if (!isChallengeValid(pow_challenge, req.userId)) {
        return res.status(403).json({ error: "安全难题已过期，请重新获取" });
    }
    if (!verifyPoW(pow_challenge, pow_nonce, 4)) {
        return res.status(403).json({ error: "算力证明验证失败" });
    }

    if (!invite_code) return res.status(400).json({ error: "需提供邀请码" });

    try {
        // 校验邀请码有效性
        const normalizedCode = String(invite_code).trim().toUpperCase();
        const invite = await dbGet("SELECT * FROM team_invitations WHERE code = ? AND expires_at > ? AND current_uses < max_uses", [normalizedCode, Date.now()]);
        if (!invite) return res.status(400).json({ error: "邀请码无效或已过期" });

        // 检查是否已是成员
        const existingMember = await dbGet("SELECT 1 FROM team_members WHERE team_uuid = ? AND user_id = ?", [invite.team_uuid, req.userId]);
        if (existingMember) return res.status(400).json({ error: "您已是该团队成员" });

        // 插入或更新申请状态为 Pending (0)
        await dbRun(`INSERT INTO team_join_requests (team_uuid, user_id, status, message, requested_at)
                     VALUES (?, ?, 0, ?, ?)
                         ON CONFLICT(team_uuid, user_id) DO UPDATE SET status=0, message=excluded.message, requested_at=excluded.requested_at`,
            [invite.team_uuid, req.userId, message || '', Date.now()]);

        // 🚀 Uni-Sync 4.0: 记录系统消息以供消息中心显示
        const user = await dbGet("SELECT username FROM users WHERE id = ?", [req.userId]);
        const team = await dbGet("SELECT name FROM teams WHERE uuid = ?", [invite.team_uuid]);
        
        await dbRun("INSERT INTO team_system_messages (team_uuid, user_id, type, message, timestamp) VALUES (?, ?, 'JOIN_REQUEST', ?, ?)",
            [invite.team_uuid, req.userId, `用户 ${user?.username || req.userId} 申请加入团队 「${team?.name || '未知团队'}」`, Date.now()]);

        // 实时通知该团队的所有管理员
        broadcastToRoom(`team:${invite.team_uuid}`, {
            action: 'NEW_JOIN_REQUEST',
            team_uuid: invite.team_uuid,
            user_id: req.userId,
            delta: { message: `用户 ${user?.username || req.userId} 申请加入团队 「${team?.name || '未知团队'}」` }
        });

        res.json({ success: true, message: "申请已提交，请等待管理员审批" });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// 2. 管理员获取待处理申请列表
app.get('/api/teams/pending_requests', requireAuth, async (req, res) => {
    const { team_uuid } = req.query;
    if (!team_uuid) return res.status(400).json({ error: "缺少团队ID" });

    try {
        // 鉴权：仅管理员可查
        const membership = await dbGet("SELECT role FROM team_members WHERE team_uuid = ? AND user_id = ?", [team_uuid, req.userId]);
        if (!membership || membership.role !== 0) return res.status(403).json({ error: "只有管理员能管理申请" });

        const requests = await dbAll(`
            SELECT r.*, u.username, u.email, u.avatar_url
            FROM team_join_requests r
                     JOIN users u ON r.user_id = u.id
            WHERE r.team_uuid = ? AND r.status = 0
            ORDER BY r.requested_at DESC
        `, [team_uuid]);

        res.json({ success: true, requests });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// 3. 审批处理 (同意/拒绝)
app.post('/api/teams/process_request', requireAuth, async (req, res) => {
    let { team_uuid, target_user_id, action } = req.body; // action: 'approve' or 'reject'
    
    // 🚀 Uni-Sync 4.0 增强：鲁棒性修正
    if (team_uuid) team_uuid = team_uuid.trim();
    if (target_user_id) target_user_id = parseInt(target_user_id, 10);
    if (!['approve', 'reject'].includes(action)) {
        return res.status(400).json({ error: 'action 仅支持 approve 或 reject' });
    }

    console.log(`${getTime()} [审批管理] 管理员 ${req.userId} 正在对用户 ${target_user_id} 执行 ${action} 操作 (团队: ${team_uuid})`);

    const release = await dbLock.acquire();
    let inTransaction = false;
    try {
        // 1. 鉴权
        const membership = await dbGet("SELECT role FROM team_members WHERE team_uuid = ? AND user_id = ?", [team_uuid, req.userId]);
        if (!membership || membership.role !== 0) {
            return res.status(403).json({ error: "权限不足，仅管理员可处理申请" });
        }

        // 查询当前状态，任何非 pending 状态都直接告知前端已处理，不报错
        const request = await dbGet(
            "SELECT status FROM team_join_requests WHERE team_uuid = ? AND user_id = ?",
            [team_uuid, target_user_id]
        );
        
        if (!request) {
            return res.status(404).json({ error: "未找到该加入申请" });
        }
        
        // ⭐ 关键修复：已处理过的请求，返回 409 + 当前真实状态，让前端刷新 UI
        if (request.status !== 0) {
            const statusMap = { 1: '已同意', 2: '已拒绝', 3: '邀请中' };
            return res.status(409).json({ 
                error: `该申请已处理`,
                current_status: request.status,
                current_status_text: statusMap[request.status] || '未知'
            });
        }

        if (action === 'approve') {
            await dbRun('BEGIN TRANSACTION');
            inTransaction = true;
            
            const updateResult = await dbRun(
                `UPDATE team_join_requests 
                 SET status = 1, processed_at = ?, processor_id = ? 
                 WHERE team_uuid = ? AND user_id = ? AND status = 0`,  // AND status=0 是最终防线
                [Date.now(), req.userId, team_uuid, target_user_id]
            );

            if (updateResult.changes === 0) {
                await dbRun('ROLLBACK');
                inTransaction = false;
                return res.status(409).json({ 
                    error: "操作失败：申请已被并行处理",
                    current_status: 1
                });
            }

            await dbRun(
                "INSERT OR IGNORE INTO team_members (team_uuid, user_id, role, joined_at) VALUES (?, ?, 1, ?)",
                [team_uuid, target_user_id, Date.now()]
            );

            await dbRun('COMMIT');
            inTransaction = false;

            const user = await dbGet("SELECT username FROM users WHERE id = ?", [target_user_id]);
            await dbRun(
                "INSERT INTO team_system_messages (team_uuid, user_id, type, message, timestamp) VALUES (?, ?, 'MEMBER_JOINED', ?, ?)",
                [team_uuid, target_user_id, `用户 ${user?.username || target_user_id} 已成功加入团队`, Date.now()]
            );

            broadcastToRoom(`user:${target_user_id}`, { action: 'JOIN_REQUEST_APPROVED', team_uuid });
            broadcastToRoom(`team:${team_uuid}`, { action: 'TEAM_MEMBER_JOINED', user_id: target_user_id });

        } else {
            const updateResult = await dbRun(
                `UPDATE team_join_requests 
                 SET status = 2, processed_at = ?, processor_id = ? 
                 WHERE team_uuid = ? AND user_id = ? AND status = 0`,
                [Date.now(), req.userId, team_uuid, target_user_id]
            );

            if (updateResult.changes === 0) {
                return res.status(409).json({ 
                    error: "拒绝失败：该申请已不在待处理状态",
                    current_status: request.status
                });
            }

            const user = await dbGet("SELECT username FROM users WHERE id = ?", [target_user_id]);
            await dbRun(
                "INSERT INTO team_system_messages (team_uuid, user_id, type, message, timestamp) VALUES (?, ?, 'JOIN_REQUEST_REJECTED', ?, ?)",
                [team_uuid, target_user_id, `管理员拒绝了用户 ${user?.username || target_user_id} 的入队申请`, Date.now()]
            );

            broadcastToRoom(`user:${target_user_id}`, { action: 'JOIN_REQUEST_REJECTED', team_uuid });
        }

        res.json({ success: true, message: action === 'approve' ? "已批准入队" : "已拒绝申请" });
    } catch (e) {
        if (inTransaction) await dbRun('ROLLBACK');
        console.error(`${getTime()} [审批错误]`, e.message);
        res.status(500).json({ error: e.message });
    } finally {
        release();
    }
});

// 4. 用户查询收到的团队邀请
app.get('/api/teams/invitations', requireAuth, async (req, res) => {
    try {
        const invitations = await dbAll(`
            SELECT r.*, t.name as team_name, u.username as inviter_name
            FROM team_join_requests r
                     JOIN teams t ON r.team_uuid = t.uuid
                     JOIN users u ON t.creator_id = u.id
            WHERE r.user_id = ? AND r.status = 3
            ORDER BY r.requested_at DESC
        `, [req.userId]);
        res.json({ success: true, invitations });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// 5. 用户响应邀请 (接受/拒绝)
app.post('/api/teams/respond_invitation', requireAuth, async (req, res) => {
    const { team_uuid, action } = req.body; // action: 'accept' or 'decline'

    if (!['accept', 'decline'].includes(action)) {
        return res.status(400).json({ error: 'action 仅支持 accept 或 decline' });
    }

    const release = await dbLock.acquire();
    let inTransaction = false;
    try {
        if (action === 'accept') {
            await dbRun('BEGIN TRANSACTION');
            inTransaction = true;
            const updateResult = await dbRun(
                "UPDATE team_join_requests SET status = 1, processed_at = ? WHERE team_uuid = ? AND user_id = ? AND status = 3",
                [Date.now(), team_uuid, req.userId]
            );

            if (updateResult.changes === 0) {
                await dbRun('ROLLBACK');
                inTransaction = false;
                release();
                return res.status(400).json({ error: "邀请已失效或不存在" });
            }

            await dbRun("INSERT OR IGNORE INTO team_members (team_uuid, user_id, role, joined_at) VALUES (?, ?, 1, ?)",
                [team_uuid, req.userId, Date.now()]);

            await dbRun('COMMIT');
            inTransaction = false;

            // 🚀 Uni-Sync 4.0: 记录邀请接受消息
            const user = await dbGet("SELECT username FROM users WHERE id = ?", [req.userId]);
            await dbRun("INSERT INTO team_system_messages (team_uuid, user_id, type, message, timestamp) VALUES (?, ?, 'MEMBER_JOINED', ?, ?)",
                [team_uuid, req.userId, `用户 ${user?.username || req.userId} 接受邀请并加入了团队`, Date.now()]);

            broadcastToRoom(`team:${team_uuid}`, { action: 'TEAM_MEMBER_JOINED', user_id: req.userId });
        } else {
            const deleteResult = await dbRun("DELETE FROM team_join_requests WHERE team_uuid = ? AND user_id = ? AND status = 3",
                [team_uuid, req.userId]);
            if (deleteResult.changes === 0) {
                return res.status(400).json({ error: "邀请已失效或不存在" });
            }

            // 🚀 Uni-Sync 4.0: 记录邀请拒绝消息
            const user = await dbGet("SELECT username FROM users WHERE id = ?", [req.userId]);
            await dbRun("INSERT INTO team_system_messages (team_uuid, user_id, type, message, timestamp) VALUES (?, ?, 'INVITATION_DECLINED', ?, ?)",
                [team_uuid, req.userId, `用户 ${user?.username || req.userId} 拒绝了团队邀请`, Date.now()]);
        }
        res.json({ success: true, message: action === 'accept' ? "已加入团队" : "已忽略邀请" });
    } catch (e) {
        if (inTransaction) await dbRun('ROLLBACK');
        res.status(500).json({ error: e.message });
    } finally {
        release();
    }
});

// 6. 获取团队系统消息 (仅管理员)
app.get('/api/teams/system_messages', requireAuth, async (req, res) => {
    const { team_uuid } = req.query;
    if (!team_uuid) return res.status(400).json({ error: "缺少 team_uuid" });

    try {
        // 校验管理员权限
        const membership = await dbGet("SELECT role FROM team_members WHERE team_uuid = ? AND user_id = ?", [team_uuid, req.userId]);
        if (!membership || membership.role !== 0) return res.status(403).json({ error: "权限不足" });

        const messages = await dbAll(`
            SELECT 
                m.*,
                u.username,
                u.avatar_url,
                -- 关键：联表查出申请的实时状态，前端据此决定是否渲染操作按钮
                r.status as request_status,
                r.id as request_id
            FROM team_system_messages m
            LEFT JOIN users u ON m.user_id = u.id
            -- 只有 JOIN_REQUEST 类型才关联 team_join_requests
            LEFT JOIN team_join_requests r 
                ON m.type = 'JOIN_REQUEST' 
                AND r.team_uuid = m.team_uuid 
                AND r.user_id = m.user_id
            WHERE m.team_uuid = ?
            ORDER BY m.timestamp DESC LIMIT 50
        `, [team_uuid]);
        
        res.json({ success: true, messages });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

app.get('/api/pomodoro/active', requireAuth, async (req, res) => {
    const deviceId = req.query.device_id || "";
    const fiveMinAgo = Date.now() - 5 * 60 * 1000;
    const row = await dbGet(`SELECT uuid, todo_uuid, start_time, planned_duration, device_id FROM pomodoro_records WHERE user_id = ? AND is_deleted = 0 AND end_time IS NULL AND start_time >= ? AND (device_id IS NULL OR device_id != ?) ORDER BY start_time DESC LIMIT 1`, [req.userId, fiveMinAgo, deviceId]);
    res.json(row ? { active: true, record: row } : { active: false });
});

app.post('/api/pomodoro/records', requireAuth, async (req, res) => {
    const body = req.body;
    const records = Array.isArray(body.records) ? body.records : (body.record ? [body.record] : []);
    if (records.length === 0) return res.status(400).json({ error: "records 为空" });
    const now = Date.now();

    try {
        await dbRun("BEGIN TRANSACTION");
        for (const r of records) {
            const uuid = String(r.uuid ?? '');
            if (!uuid) continue;
            const todoUuid = r.todo_uuid ? String(r.todo_uuid) : null;
            const startTime = normalizeToMs(r.start_time) || now;
            const endTime = r.end_time != null ? (normalizeToMs(r.end_time) || null) : null;
            const plannedDuration = typeof r.planned_duration === 'number' ? r.planned_duration : parseInt(r.planned_duration || 25 * 60, 10);
            const actualDuration = r.actual_duration != null ? parseInt(r.actual_duration, 10) : null;
            const status = ['completed', 'interrupted', 'switched'].includes(r.status) ? r.status : 'completed';
            const deviceId = r.device_id ? String(r.device_id) : null;
            const isDeleted = (r.is_deleted ?? r.isDeleted) ? 1 : 0;
            const version = parseInt(r.version ?? 1, 10);
            const createdAt = normalizeToMs(r.created_at ?? r.createdAt) || now;
            const updatedAt = normalizeToMs(r.updated_at ?? r.updatedAt) || now;
            const tagUuidsArr = Array.isArray(r.tag_uuids) ? r.tag_uuids.map(String) : [];

            const existing = await dbGet("SELECT version, updated_at, is_deleted, todo_uuid, start_time FROM pomodoro_records WHERE uuid = ? AND user_id = ?", [uuid, req.userId]);
            
            // 冲突检测 (版本冲突)
            const serverVersion = existing ? (existing.version || 0) : 0;
            const isDataDifferent = existing && (todoUuid !== (existing.todo_uuid || null) || startTime !== normalizeToMs(existing.start_time));
            
            if (existing && version <= serverVersion && isDataDifferent) {
                console.log(`${getTime()} ⚠️ [冲突检测] 番茄记录 ${uuid} 检测到版本冲突`);
                await dbRun(`UPDATE pomodoro_records SET has_conflict = 1, conflict_data = ?, updated_at = ? WHERE uuid = ? AND user_id = ?`, [safeSnapshotJson(r, 'pomodoro_records'), now, uuid, req.userId]);
            }

            if (!existing) {
                await dbRun(`INSERT OR REPLACE INTO pomodoro_records (uuid, user_id, todo_uuid, start_time, end_time, planned_duration, actual_duration, status, device_id, is_deleted, version, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)`,
                    [uuid, req.userId, todoUuid, startTime, endTime, plannedDuration, actualDuration, status, deviceId, isDeleted, version, createdAt, updatedAt]);
                await recordAuditLog({ user_id: req.userId, target_table: 'pomodoro_records', target_uuid: uuid, op_type: 'INSERT', after_data: r });
            } else if (version > serverVersion || updatedAt > normalizeToMs(existing.updated_at)) {
                await dbRun(`UPDATE pomodoro_records SET todo_uuid=?, start_time=?, end_time=?, planned_duration=?, actual_duration=?, status=?, device_id=?, is_deleted=?, version=?, updated_at=?, has_conflict=0 WHERE uuid=? AND user_id=?`,
                    [todoUuid, startTime, endTime, plannedDuration, actualDuration, status, deviceId, isDeleted, version, updatedAt, uuid, req.userId]);
                await recordAuditLog({ user_id: req.userId, target_table: 'pomodoro_records', target_uuid: uuid, op_type: 'UPDATE', before_data: existing, after_data: r });
            }

            if (tagUuidsArr.length > 0) {
                const tagsKey = todoUuid || uuid;
                for (const tagUuid of tagUuidsArr) {
                    await dbRun("INSERT OR REPLACE INTO todo_tags (todo_uuid, tag_uuid, is_deleted, updated_at) VALUES (?,?,0,?)", [tagsKey, tagUuid, now]);
                }
            }
        }
        await dbRun("COMMIT");
        res.json({ success: true });
    } catch (e) {
        await dbRun("ROLLBACK");
        console.error(`${getTime()} [记录提交失败]`, e.message);
        res.status(500).json({ error: e.message });
    }
});

app.get('/api/pomodoro/records', requireAuth, async (req, res) => {
    const fromMs = parseInt(req.query.from || "0", 10);
    const toMs = parseInt(req.query.to || String(Date.now()), 10);
    
    // 🚀 Uni-Sync 4.0: 针对增量同步逻辑优化
    // 如果 fromMs > 0，说明是增量同步请求，此时必须返回 updated_at 超过该时间的记录（包含已删除的 tombstone）
    // 如果 fromMs == 0，说明是全量拉取，此时仅返回未删除的记录
    let whereClause = `r.user_id = ? AND r.start_time <= ?`;
    let params = [req.userId, toMs];
    
    if (fromMs > 0) {
        whereClause += ` AND (r.updated_at >= ? OR r.start_time >= ?)`;
        params.push(fromMs, fromMs);
    } else {
        whereClause += ` AND r.is_deleted = 0 AND r.start_time >= ?`;
        params.push(fromMs);
    }

    try {
        const results = await dbAll(`
            SELECT r.*, t.content AS todo_title, GROUP_CONCAT(tt.tag_uuid) AS tag_uuids_concat
            FROM pomodoro_records r
                     LEFT JOIN todos t ON r.todo_uuid = t.uuid
                     LEFT JOIN todo_tags tt ON COALESCE(r.todo_uuid, r.uuid) = tt.todo_uuid AND tt.is_deleted = 0
            WHERE ${whereClause}
            GROUP BY r.uuid ORDER BY r.start_time DESC
        `, params);

        const enriched = results.map(r => ({
            ...r,
            is_deleted: r.is_deleted === 1 || r.is_deleted === true,
            tag_uuids: r.tag_uuids_concat ? r.tag_uuids_concat.split(',').filter(Boolean) : [],
            tag_uuids_concat: undefined
        }));
        res.json(enriched);
    } catch (err) {
        console.error("Fetch pomodoro records error:", err);
        res.status(500).json({ error: "Internal Server Error" });
    }
});

app.post('/api/pomodoro/settings', requireAuth, async (req, res) => {
    const { default_focus_duration, default_rest_duration, default_loop_count, timer_mode } = req.body;
    await dbRun(`INSERT INTO pomodoro_settings (user_id, default_focus_duration, default_rest_duration, default_loop_count, timer_mode, updated_at) VALUES (?,?,?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET default_focus_duration = excluded.default_focus_duration, default_rest_duration = excluded.default_rest_duration, default_loop_count = excluded.default_loop_count, timer_mode = excluded.timer_mode, updated_at = excluded.updated_at`,
        [req.userId, default_focus_duration ?? 1500, default_rest_duration ?? 300, default_loop_count ?? 4, timer_mode ?? 0, Date.now()]);
    res.json({ success: true });
});

app.get('/api/pomodoro/settings', requireAuth, async (req, res) => {
    const row = await dbGet("SELECT * FROM pomodoro_settings WHERE user_id = ?", [req.userId]);
    res.json(row ?? { user_id: req.userId, default_focus_duration: 1500, default_rest_duration: 300, default_loop_count: 4, timer_mode: 0 });
});

// 排行榜模块
app.get('/api/leaderboard', async (req, res) => {
    const results = await dbAll("SELECT username, score, duration, played_at FROM leaderboard ORDER BY score DESC, duration ASC LIMIT 50");
    res.json(results);
});

app.post(['/api/leaderboard', '/api/score'], requireAuth, async (req, res) => {
    const { user_id, username, score, duration } = req.body;
    if (req.userId !== parseInt(user_id, 10)) return res.status(403).json({ error: "越权操作被拒绝" });
    await dbRun("INSERT INTO leaderboard (user_id, username, score, duration) VALUES (?, ?, ?, ?)", [user_id, username, score, duration]);
    res.json({ success: true });
});

// 兜底 404
app.use((req, res) => res.status(404).json({ error: "API Endpoint Not Found" }));

server.listen(port, "0.0.0.0", async () => {
    console.log(`✅ 阿里云终极集成版 API (HTTP + WS) 已在端口 ${port} 就绪！`);

    // 🚀 确保数据库迁移检测执行
    console.log(`${getTime()} [系统启动] 正在进行数据库完整性自检...`);
    try {
        await initializeTables();

        // 强制再次检查 todos 是否有 team_uuid（双重保险）
        const checkAndAdd = async (table, column) => {
            const info = await dbAll(`PRAGMA table_info(${table})`);
            if (!info.some(c => c.name === column)) {
                console.log(`${getTime()} [紧急修复] 补全 ${table} 表的 ${column} 列`);
                await dbRun(`ALTER TABLE ${table} ADD COLUMN ${column} TEXT`);
            }
        };

        await checkAndAdd('todos', 'team_uuid');
        await checkAndAdd('todo_groups', 'team_uuid');
        await checkAndAdd('countdowns', 'team_uuid');
        await checkAndAdd('time_logs', 'team_uuid');
        await checkAndAdd('pomodoro_records', 'team_uuid');
        await checkAndAdd('courses', 'team_uuid');

        // 🚀 核心修复：补全缺失的 id 列（解决 SQLITE_ERROR: no such column: id）
        const ensureId = async (table) => {
            const cols = await dbAll(`PRAGMA table_info(${table})`);
            if (!cols.some(c => c.name === 'id')) {
                console.log(`${getTime()} [紧急修复] 为 ${table} 表补全 id 列`);
                await dbRun(`ALTER TABLE ${table} ADD COLUMN id INTEGER`);
            }
        };
        await ensureId('todos');
        await ensureId('countdowns');
        await ensureId('todo_groups');

        console.log(`${getTime()} [系统启动] 数据库全量检查通过。`);
    } catch (e) {
        console.error(`${getTime()} [系统启动] 数据库检查发生严重错误:`, e.message);
    }
});
