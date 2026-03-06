/**
 * Math Quiz App Backend - Cloudflare Worker
 * 终极生产级：Delta Sync (增量同步) + Versioning (并发控制) + 逻辑删除
 */

const SYNC_LIMITS = {
  free: 500,
  pro: 2000,
  admin: 99999
};

// 🛡️ 鉴权：生成 HMAC 签名 Token
async function signToken(userId, env) {
  const secret = env.API_SECRET || "math_quiz_default_secret_key_2026_super_safe";
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(userId.toString()));
  const sigHex = Array.from(new Uint8Array(signature)).map(b => b.toString(16).padStart(2, '0')).join('');
  return `${userId}.${sigHex}`;
}

// 🛡️ 鉴权：验证请求中的 Token 并提取真实的 UserId
async function requireAuth(request, env) {
  const authHeader = request.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) return null;
  const token = authHeader.substring(7);
  const parts = token.split('.');
  if (parts.length !== 2) return null;
  const userIdStr = parts[0];
  const expectedToken = await signToken(userIdStr, env);
  if (token === expectedToken) {
    return parseInt(userIdStr, 10);
  }
  return null;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // === 1. CORS 配置 ===
    const corsHeaders = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS, PATCH",
      "Access-Control-Allow-Headers": "Content-Type, x-user-id, Authorization",
    };

    if (request.method === "OPTIONS") return new Response("OK", { headers: corsHeaders });

    const jsonResponse = (data, status = 200) => {
      return new Response(JSON.stringify(data), { status: status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    };

    const errorResponse = (msg, status = 400) => jsonResponse({ error: msg }, status);

    try {
      if (!env.math_quiz_db) throw new Error(`数据库绑定失败！`);
      const DB = env.math_quiz_db;

      // 🛡️ 全局提取当前请求的真实受信任用户 ID
      const authUserId = await requireAuth(request, env);

      // --------------------------
      // 模块 A: 用户认证 (Auth) (保留原有逻辑)
      // --------------------------
      if (url.pathname === "/api/auth/register" && request.method === "POST") {
         // ... (保留原有的注册逻辑) ...
         return errorResponse("注册接口请参考旧版代码，此处略以突出核心重构");
      }
      if (url.pathname === "/api/auth/login" && request.method === "POST") {
        const { email, password } = await request.json();
        const user = await DB.prepare("SELECT * FROM users WHERE email = ?").bind(email).first();
        if (!user) return errorResponse("用户不存在", 404);
        const inputHash = await hashPassword(password);
        if (inputHash !== user.password_hash) return errorResponse("密码错误", 401);

        const token = await signToken(user.id, env);

        return jsonResponse({
          success: true,
          token: token,
          user: { id: user.id, username: user.username, email: user.email, avatar_url: user.avatar_url, tier: user.tier }
        });
      }

      // --------------------------
      // 🚀 模块 B: 核心 Delta Sync (增量同步)
      // --------------------------
      if (url.pathname === "/api/sync" && request.method === "POST") {
        if (!authUserId) return errorResponse("未授权", 401);

        const { user_id, last_sync_time = 0, device_id, todos = [], countdowns = [], screen_time } = await request.json();

        if (authUserId !== parseInt(user_id, 10)) return errorResponse("越权操作被拒绝", 403);
        if (!device_id) return errorResponse("缺少 device_id", 400);

        // 1. 频率与额度控制
        const now = Date.now();
        const limitError = await enforceSyncLimit(user_id, DB, now);
        if (limitError === 'IGNORE') {
            // 防风暴：距离上次同步太近，直接返回服务器时间，忽略本次合并
            return jsonResponse({ success: true, server_todos: [], server_countdowns: [], new_sync_time: now });
        } else if (limitError) {
            return errorResponse(limitError, 429);
        }

        // ==========================================
        // 第一步：处理客户端上传的增量变化 (Todos)
        // ==========================================
        if (Array.isArray(todos) && todos.length > 0) {
          const statements = [];
          for (const t of todos) {
            const existing = await DB.prepare("SELECT version FROM todos WHERE id = ?").bind(t.id).first();

            if (!existing) {
              // 不存在，直接插入
              statements.push(DB.prepare(`
                INSERT INTO todos (id, user_id, content, is_completed, is_deleted, updated_at, created_at, version, device_id, due_date)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
              `).bind(
                t.id, authUserId, t.content, t.is_completed ? 1 : 0, t.is_deleted ? 1 : 0,
                t.updated_at, t.created_at, t.version || 1, device_id, t.due_date || null
              ));
            } else if (t.version > existing.version) {
              // 存在且版本更高，允许覆盖
              statements.push(DB.prepare(`
                UPDATE todos SET content = ?, is_completed = ?, is_deleted = ?, updated_at = ?, version = ?, device_id = ?, due_date = ?
                WHERE id = ?
              `).bind(
                t.content, t.is_completed ? 1 : 0, t.is_deleted ? 1 : 0, t.updated_at, t.version, device_id, t.due_date || null, t.id
              ));
            }
          }
          if (statements.length > 0) await DB.batch(statements);
        }

        // ==========================================
        // 第二步：处理客户端上传的增量变化 (Countdowns)
        // ==========================================
        if (Array.isArray(countdowns) && countdowns.length > 0) {
          const statements = [];
          for (const c of countdowns) {
            const existing = await DB.prepare("SELECT version FROM countdowns WHERE id = ?").bind(c.id).first();

            if (!existing) {
              statements.push(DB.prepare(`
                INSERT INTO countdowns (id, user_id, title, target_time, is_deleted, updated_at, created_at, version, device_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
              `).bind(
                c.id, authUserId, c.title, c.target_time, c.is_deleted ? 1 : 0,
                c.updated_at, c.created_at, c.version || 1, device_id
              ));
            } else if (c.version > existing.version) {
              statements.push(DB.prepare(`
                UPDATE countdowns SET title = ?, target_time = ?, is_deleted = ?, updated_at = ?, version = ?, device_id = ?
                WHERE id = ?
              `).bind(
                c.title, c.target_time, c.is_deleted ? 1 : 0, c.updated_at, c.version, device_id, c.id
              ));
            }
          }
          if (statements.length > 0) await DB.batch(statements);
        }

        // ==========================================
        // 第三步：提取服务器的新变化返回给客户端
        // ==========================================
        // 核心：查询 updated_at > last_sync_time 的数据，并且排除当前设备刚刚上传的数据
        const serverTodos = await DB.prepare(`
          SELECT * FROM todos
          WHERE user_id = ? AND updated_at > ? AND (device_id != ? OR device_id IS NULL)
        `).bind(authUserId, last_sync_time, device_id).all();

        const serverCountdowns = await DB.prepare(`
          SELECT * FROM countdowns
          WHERE user_id = ? AND updated_at > ? AND (device_id != ? OR device_id IS NULL)
        `).bind(authUserId, last_sync_time, device_id).all();

        // 提取账号状态 (用于 UI 刷新)
        const userRow = await DB.prepare("SELECT tier FROM users WHERE id = ?").bind(authUserId).first();
        const tier = userRow ? userRow.tier : 'free';
        const syncLimit = SYNC_LIMITS[tier] || SYNC_LIMITS.free;

        const today = new Date().toISOString().split('T')[0];
        const record = await DB.prepare("SELECT sync_count FROM sync_limits WHERE user_id = ? AND sync_date = ?").bind(authUserId, today).first();

        return jsonResponse({
          success: true,
          server_todos: serverTodos.results,
          server_countdowns: serverCountdowns.results,
          new_sync_time: now, // 核心：下发全新的时间戳
          status: {
             tier: tier,
             sync_count: record ? record.sync_count : 1,
             sync_limit: syncLimit
          }
        });
      }

      // ... (其他 API 如 courses, leaderboard 保持不变，此处为节省篇幅略过) ...

      return errorResponse("API Endpoint Not Found", 404);

    } catch (e) {
      return errorResponse(`Server Error: ${e.message}`, 500);
    }
  },
};

/**
 * 🚀 核心同步频率检查逻辑 (带有防风暴机制)
 */
async function enforceSyncLimit(userId, DB, now) {
  if (!userId) return null;
  const today = new Date(now).toISOString().split('T')[0];

  try {
    const userRow = await DB.prepare("SELECT tier FROM users WHERE id = ?").bind(userId).first();
    const tier = userRow ? userRow.tier : 'free';
    const MAX_SYNCS = SYNC_LIMITS[tier] || SYNC_LIMITS.free;

    const record = await DB.prepare("SELECT * FROM sync_limits WHERE user_id = ?").bind(userId).first();

    if (!record || record.sync_date !== today) {
      await DB.prepare("INSERT OR REPLACE INTO sync_limits (user_id, sync_date, sync_count, last_sync_time) VALUES (?, ?, ?, ?)")
        .bind(userId, today, 1, now).run();
      return null;
    }

    const lastSyncTime = parseInt(record.last_sync_time) || 0;
    // 🛡️ 防风暴：如果距离上次同步小于 3 秒，忽略本次同步计数
    if (now - lastSyncTime < 3000) {
      return 'IGNORE';
    }

    if (record.sync_count >= MAX_SYNCS) {
      let msg = `今日同步次数已达上限 (${MAX_SYNCS}次)，请明天再试。`;
      if (tier === 'free') msg += " 升级为 Pro 可解锁更高额度。";
      return msg;
    }

    await DB.prepare("UPDATE sync_limits SET sync_count = sync_count + 1, last_sync_time = ? WHERE user_id = ?")
      .bind(now, userId).run();

    return null;

  } catch (e) {
    return null;
  }
}

async function hashPassword(password) {
  const msgUint8 = new TextEncoder().encode(password);
  const hashBuffer = await crypto.subtle.digest("SHA-256", msgUint8);
  return Array.from(new Uint8Array(hashBuffer)).map(b => b.toString(16).padStart(2, "0")).join("");
}
