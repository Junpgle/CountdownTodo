/**
 * Math Quiz App Backend - Cloudflare Worker
 * 终极生产级：Delta Sync (增量同步) + Versioning (并发控制) + 逻辑删除
 * 包含所有完整业务模块（注册/排榜/课表/屏幕时间等）
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

// 🚀 全能时间解析器 (用于部分旧业务模块)
function getTimeMs(t) {
  if (!t) return 0;
  if (typeof t === 'number') return t;
  if (typeof t === 'string') {
    if (/^\d+$/.test(t)) return parseInt(t, 10);
    const parsed = new Date(t).getTime();
    return isNaN(parsed) ? 0 : parsed;
  }
  return 0;
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
      // 模块 A: 用户认证 (Auth)
      // --------------------------
      if (url.pathname === "/api/auth/register" && request.method === "POST") {
        const body = await request.json();
        const { email, code, username, password } = body;

        if (code) {
            if (!email) return errorResponse("验证需提供邮箱");
            const pending = await DB.prepare("SELECT * FROM pending_registrations WHERE email = ?").bind(email).first();
            if (!pending) return errorResponse("验证请求不存在或已过期，请重新注册");
            if (pending.code !== code.toString()) return errorResponse("验证码错误");

            const createdTime = new Date(pending.created_at).getTime();
            if (Date.now() - createdTime > 15 * 60 * 1000) return errorResponse("验证码已过期，请重新获取");

            try {
              await DB.prepare("INSERT INTO users (username, email, password_hash) VALUES (?, ?, ?)").bind(pending.username, pending.email, pending.password_hash).run();
              await DB.prepare("DELETE FROM pending_registrations WHERE email = ?").bind(email).run();
              return jsonResponse({ success: true, message: "注册成功，请登录" });
            } catch (e) {
              if (e.message && e.message.includes("UNIQUE")) return errorResponse("该邮箱已完成注册，请直接登录");
              throw e;
            }
        }

        if (!username || !email || !password) return errorResponse("缺少必要字段");
        if (!env.RESEND_API_KEY) return errorResponse("服务端未配置邮件服务", 500);

        const existing = await DB.prepare("SELECT id FROM users WHERE email = ?").bind(email).first();
        if (existing) return errorResponse("该邮箱已被注册，请直接登录");

        const newCode = Math.floor(100000 + Math.random() * 900000).toString();
        const passwordHash = await hashPassword(password);

        await DB.prepare("INSERT OR REPLACE INTO pending_registrations (email, username, password_hash, code) VALUES (?, ?, ?, ?)")
          .bind(email, username, passwordHash, newCode).run();

        const resendResponse = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: { "Authorization": `Bearer ${env.RESEND_API_KEY}`, "Content-Type": "application/json" },
          body: JSON.stringify({
            from: "Math Quiz <Math&Quiz@junpgle.me>",
            to: email,
            subject: "验证您的账号 - Math Quiz",
            html: `<div style="font-family: sans-serif; padding: 20px;"><h2>欢迎注册!</h2><p>您的验证码是：</p><p style="font-size: 32px; font-weight: bold; letter-spacing: 5px; color: #4F46E5;">${newCode}</p></div>`
          })
        });

        if (!resendResponse.ok) return errorResponse("验证邮件发送失败");
        return jsonResponse({ success: true, message: "验证码已发送", require_verify: true });
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

      if (url.pathname === "/api/auth/change_password" && request.method === "POST") {
        if (!authUserId) return errorResponse("未授权", 401);
        const { user_id, old_password, new_password } = await request.json();
        if (authUserId !== parseInt(user_id, 10)) return errorResponse("无权操作此账号", 403);

        if (!user_id || !old_password || !new_password) return errorResponse("缺少参数");

        const user = await DB.prepare("SELECT * FROM users WHERE id = ?").bind(user_id).first();
        if (!user) return errorResponse("用户不存在", 404);

        const oldHash = await hashPassword(old_password);
        if (oldHash !== user.password_hash) return errorResponse("当前密码错误", 401);

        const newHash = await hashPassword(new_password);
        await DB.prepare("UPDATE users SET password_hash = ? WHERE id = ?").bind(newHash, user_id).run();

        return jsonResponse({ success: true, message: "密码修改成功" });
      }

      if (url.pathname === "/api/user/status" && request.method === "GET") {
        if (!authUserId) return errorResponse("未授权", 401);
        const userId = url.searchParams.get("user_id");
        if (authUserId !== parseInt(userId, 10)) return errorResponse("越权访问被拒绝", 403);

        const userRow = await DB.prepare("SELECT tier FROM users WHERE id = ?").bind(userId).first();
        const tier = userRow ? userRow.tier : 'free';
        const sync_limit = SYNC_LIMITS[tier] || SYNC_LIMITS.free;

        const today = new Date().toISOString().split('T')[0];
        const record = await DB.prepare("SELECT sync_count FROM sync_limits WHERE user_id = ? AND sync_date = ?").bind(userId, today).first();
        const sync_count = record ? record.sync_count : 0;

        return jsonResponse({ success: true, tier: tier, sync_count: sync_count, sync_limit: sync_limit });
      }

      // --------------------------
      // 模块 B: 排行榜 (Leaderboard)
      // --------------------------
      if (url.pathname === "/api/leaderboard" && request.method === "GET") {
        const { results } = await DB.prepare("SELECT username, score, duration, played_at FROM leaderboard ORDER BY score DESC, duration ASC LIMIT 50").all();
        return jsonResponse(results);
      }

      if ((url.pathname === "/api/leaderboard" || url.pathname === "/api/score") && request.method === "POST") {
        if (!authUserId) return errorResponse("未授权", 401);
        const { user_id, username, score, duration } = await request.json();
        if (authUserId !== parseInt(user_id, 10)) return errorResponse("越权操作被拒绝", 403);

        await DB.prepare("INSERT INTO leaderboard (user_id, username, score, duration) VALUES (?, ?, ?, ?)")
          .bind(user_id, username, score, duration).run();
        return jsonResponse({ success: true });
      }

      // --------------------------
      // 🚀 模块 C: 核心 Delta Sync (增量同步引擎)
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
        // 第三步：同步过程中顺便处理 Screen Time
        // ==========================================
        if (screen_time && screen_time.device_name && screen_time.record_date && Array.isArray(screen_time.apps)) {
          const { device_name, record_date, apps } = screen_time;
          const statements = apps.map(app => {
            return DB.prepare(`
              INSERT INTO screen_time_logs (user_id, device_name, record_date, app_name, duration)
              VALUES (?, ?, ?, ?, ?)
              ON CONFLICT(user_id, device_name, record_date, app_name)
              DO UPDATE SET duration = excluded.duration, updated_at = CURRENT_TIMESTAMP
            `).bind(user_id, device_name.trim(), record_date, app.app_name, app.duration);
          });
          if (statements.length > 0) await DB.batch(statements);
        }

        // ==========================================
        // 第四步：提取服务器的新变化返回给客户端
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

      // --------------------------
      // 模块 D: 屏幕使用时间 (Screen Time)
      // --------------------------
      if (url.pathname === "/api/screen_time" && request.method === "POST") {
        if (!authUserId) return errorResponse("未授权", 401);
        const body = await request.json();
        let { user_id, device_name, record_date, apps } = body;
        if (authUserId !== parseInt(user_id, 10)) return errorResponse("越权操作被拒绝", 403);

        if (!user_id || !device_name || !record_date || !Array.isArray(apps)) return errorResponse("参数错误");

        // 使用现有的时间戳判断逻辑，复用现在毫秒级的时间
        const now = Date.now();
        const limitError = await enforceSyncLimit(user_id, DB, now);
        if (limitError && limitError !== 'IGNORE') return errorResponse(limitError, 429);

        try {
          const statements = apps.map(app => {
           return DB.prepare(`
             INSERT INTO screen_time_logs (user_id, device_name, record_date, app_name, duration)
             VALUES (?, ?, ?, ?, ?)
             ON CONFLICT(user_id, device_name, record_date, app_name)
             DO UPDATE SET duration = excluded.duration, updated_at = CURRENT_TIMESTAMP
           `).bind(user_id, device_name.trim(), record_date, app.app_name, app.duration);
          });
          await DB.batch(statements);
          return jsonResponse({ success: true, received_device: device_name });
        } catch (e) {
          return errorResponse("数据库更新失败: " + e.message, 500);
        }
      }

      if (url.pathname === "/api/screen_time" && request.method === "GET") {
        if (!authUserId) return errorResponse("未授权", 401);
        const userId = url.searchParams.get("user_id");
        if (authUserId !== parseInt(userId, 10)) return errorResponse("越权访问被拒绝", 403);

        const date = url.searchParams.get("date");
        if (!userId || !date) return errorResponse("缺少参数");

        const { results } = await DB.prepare(`
          SELECT
            COALESCE(m.mapped_name, s.app_name) AS app_name,
            COALESCE(m.category, '未分类') AS category,
            s.device_name,
            SUM(s.duration) AS duration
          FROM screen_time_logs s
          LEFT JOIN app_name_mappings m ON s.app_name = m.package_name
          WHERE s.user_id = ? AND s.record_date = ?
          GROUP BY COALESCE(m.mapped_name, s.app_name), COALESCE(m.category, '未分类'), s.device_name
          ORDER BY duration DESC
        `).bind(userId, date).all();

        return jsonResponse(results);
      }

      // --------------------------
      // 模块 E: 映射与调试 (Mappings & Debug)
      // --------------------------
      if (url.pathname === "/api/mappings" && request.method === "GET") {
        const { results } = await DB.prepare(`SELECT package_name, mapped_name, category FROM app_name_mappings`).all();
        return jsonResponse(results);
      }

      if (url.pathname === "/api/debug/reset_database" && request.method === "POST") {
        if (!authUserId) return errorResponse("未授权", 401);
        try {
          // 清空所有主要业务表
          await DB.batch([
            DB.prepare("DELETE FROM courses"),
            DB.prepare("DELETE FROM screen_time_logs"),
            DB.prepare("DELETE FROM countdowns"),
            DB.prepare("DELETE FROM todos"),
            DB.prepare("DELETE FROM leaderboard")
            // 不删除 users, sync_limits 和 mappings
          ]);
          return jsonResponse({ success: true, message: "所有业务数据已重置" });
        } catch (e) {
          return errorResponse("重置失败", 500);
        }
      }

      // --------------------------
      // 模块 F: 课程表 (Courses)
      // --------------------------
      if (url.pathname === "/api/courses" && request.method === "GET") {
        if (!authUserId) return errorResponse("未授权", 401);
        const userId = url.searchParams.get("user_id");
        if (authUserId !== parseInt(userId, 10)) return errorResponse("越权访问被拒绝", 403);

        const semester = url.searchParams.get("semester") || "default";

        const { results } = await DB.prepare(`
          SELECT * FROM courses WHERE user_id = ? AND semester = ? AND is_deleted = 0 ORDER BY week_index, weekday, start_time
        `).bind(userId, semester).all();
        return jsonResponse(results);
      }

      if (url.pathname === "/api/courses" && request.method === "POST") {
        if (!authUserId) return errorResponse("未授权", 401);
        const { user_id, courses, semester = "default" } = await request.json();
        if (authUserId !== parseInt(user_id, 10)) return errorResponse("越权操作被拒绝", 403);
        if (!Array.isArray(courses)) return errorResponse("参数错误");

        const now = Date.now();
        const limitError = await enforceSyncLimit(user_id, DB, now);
        if (limitError && limitError !== 'IGNORE') return errorResponse(limitError, 429);

        const timestamp = Date.now();
        try {
          const statements = [
            DB.prepare("DELETE FROM courses WHERE user_id = ? AND semester = ?").bind(user_id, semester)
          ];
          for (const c of courses) {
            statements.push(
              DB.prepare(`
                INSERT INTO courses (
                  user_id, semester, course_name, room_name, teacher_name, start_time, end_time, weekday, week_index, lesson_type, created_at, updated_at, is_deleted
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
              `).bind(
                user_id, semester, c.course_name || '未知', c.room_name || '未知', c.teacher_name || '未知',
                c.start_time || 0, c.end_time || 0, c.weekday || 1, c.week_index || 1, c.lesson_type || null, timestamp, timestamp
              )
            );
          }
          await DB.batch(statements);
          return jsonResponse({ success: true, message: `成功同步 ${courses.length} 节课程` });
        } catch (e) {
          return errorResponse("课表同步失败: " + e.message, 500);
        }
      }

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
