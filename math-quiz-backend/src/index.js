/**
 * Math Quiz App Backend - Cloudflare Worker
 * 终极生产级：Delta Sync (增量同步) + 彻底解决 UUID 映射问题 + 移除危险的同名合并逻辑
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

        const user = await DB.prepare("SELECT * FROM users WHERE id = ?").bind(user_id).first();
        if (!user) return errorResponse("用户不存在", 404);

        const oldHash = await hashPassword(old_password);
        if (oldHash !== user.password_hash) return errorResponse("当前密码错误", 401);

        const newHash = await hashPassword(new_password);
        await DB.prepare("UPDATE users SET password_hash = ? WHERE id = ?").bind(newHash, user_id).run();

        return jsonResponse({ success: true, message: "密码修改成功" });
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
      // 🚀 模块 C: 核心 Delta Sync
      // --------------------------
      if (url.pathname === "/api/sync" && request.method === "POST") {
        if (!authUserId) return errorResponse("未授权", 401);

        const payload = await request.json();
        const { user_id, last_sync_time = 0, device_id, screen_time } = payload;
        const todos = payload.todos || payload.todosChanges || [];
        const countdowns = payload.countdowns || payload.countdownsChanges || [];

        if (authUserId !== parseInt(user_id, 10)) return errorResponse("越权操作被拒绝", 403);
        if (!device_id) return errorResponse("缺少 device_id", 400);

        const now = Date.now();
        const limitError = await enforceSyncLimit(user_id, DB, now);
        if (limitError === 'IGNORE') {
            return jsonResponse({ success: true, server_todos: [], server_countdowns: [], new_sync_time: now });
        } else if (limitError) {
            return errorResponse(limitError, 429);
        }

        const batchStatements = [];

        // 1. 处理 Todos
        if (Array.isArray(todos)) {
          for (const t of todos) {
            // 🚀 修复点 1：同时接收 uuid, id, _id 三种可能的字段格式
            const tUuid = String(t.uuid ?? t.id ?? t._id);
            const tContent = String(t.content ?? t.title ?? "");
            const tIsCompleted = (t.is_completed ?? t.isCompleted ?? t.isDone) ? 1 : 0;
            const tIsDeleted = (t.is_deleted ?? t.isDeleted) ? 1 : 0;
            const tUpdatedAt = parseInt(t.updated_at ?? t.updatedAt ?? now, 10);
            const tVersion = parseInt(t.version || 1, 10);

            // 🚀 修复：智能解析 due_date（处理毫秒时间戳和 ISO 日期字符串两种格式）
            let tDueDate = null;
            const dueDateRaw = t.due_date ?? t.dueDate;
            if (dueDateRaw) {
              const asInt = parseInt(dueDateRaw, 10);
              // 如果能解析为整数且位数 >= 13，则是毫秒时间戳
              if (!isNaN(asInt) && dueDateRaw.toString().length >= 13) {
                tDueDate = asInt;
              } else {
                // 否则当作 ISO 日期字符串解析
                const dt = new Date(dueDateRaw);
                if (!isNaN(dt.getTime())) {
                  tDueDate = dt.getTime();
                }
              }
            }

            const tCreatedDate = (t.created_date ?? t.createdDate) ? parseInt(t.created_date ?? t.createdDate, 10) : null;

            let existing = await DB.prepare("SELECT id, version, due_date, created_date FROM todos WHERE uuid = ? AND user_id = ?").bind(tUuid, authUserId).first();

            // 兜底策略：兼容完全没有 UUID 的上古时代旧数据
            if (!existing) {
              existing = await DB.prepare("SELECT id, version, due_date, created_date FROM todos WHERE user_id = ? AND content = ? AND (uuid IS NULL OR uuid = '')").bind(authUserId, tContent).first();
            }

            if (!existing) {
              // 彻底没找到，是真正的新数据
              batchStatements.push(DB.prepare(`
                INSERT INTO todos (uuid, user_id, content, is_completed, is_deleted, updated_at, version, device_id, due_date, created_date)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
              `).bind(tUuid, authUserId, tContent, tIsCompleted, tIsDeleted, tUpdatedAt, tVersion, device_id, tDueDate, tCreatedDate));
            } else {
              // 找到了老数据！执行版本 LWW (Last Write Wins) 冲突覆盖策略
              const finalDueDate = tDueDate || existing.due_date;
              const finalCreatedDate = tCreatedDate || existing.created_date; // 🚀 新增：保留已有的业务开始时间
              if (tVersion > existing.version || tUpdatedAt > parseInt(existing.updated_at || 0) || !existing.uuid) {
                  batchStatements.push(DB.prepare(`
                    UPDATE todos SET uuid = ?, content = ?, is_completed = ?, is_deleted = ?, updated_at = ?, version = ?, device_id = ?, due_date = ?, created_date = ?
                    WHERE id = ?
                  `).bind(tUuid, tContent, tIsCompleted, tIsDeleted, tUpdatedAt, tVersion, device_id, finalDueDate, finalCreatedDate, existing.id));
              }
            }
          }
        }

        // 2. 处理 Countdowns
        if (Array.isArray(countdowns)) {
          for (const c of countdowns) {
            // 🚀 修复点 2：倒数日同理
            const cUuid = String(c.uuid ?? c.id ?? c._id);
            const cTitle = String(c.title ?? "");

            // 🚀 修复：智能解析 target_time（处理毫秒时间戳和 ISO 日期字符串两种格式）
            let cTargetTime = null;
            const targetTimeRaw = c.target_time ?? c.targetTime ?? c.targetDate;
            if (targetTimeRaw) {
              const asInt = parseInt(targetTimeRaw, 10);
              // 如果能解析为整数且位数 >= 13，则是毫秒时间戳
              if (!isNaN(asInt) && targetTimeRaw.toString().length >= 13) {
                cTargetTime = asInt;
              } else {
                // 否则当作 ISO 日期字符串解析
                const dt = new Date(targetTimeRaw);
                if (!isNaN(dt.getTime())) {
                  cTargetTime = dt.getTime();
                }
              }
            }

            const cIsDeleted = (c.is_deleted ?? c.isDeleted) ? 1 : 0;
            const cUpdatedAt = parseInt(c.updated_at ?? c.updatedAt ?? now, 10);
            const cVersion = parseInt(c.version || 1, 10);

            let existing = await DB.prepare("SELECT id, version, target_time FROM countdowns WHERE uuid = ? AND user_id = ?").bind(cUuid, authUserId).first();

            if (!existing) {
               existing = await DB.prepare("SELECT id, version, target_time FROM countdowns WHERE user_id = ? AND title = ? AND (uuid IS NULL OR uuid = '')").bind(authUserId, cTitle).first();
            }

            if (!existing) {
              batchStatements.push(DB.prepare(`
                INSERT INTO countdowns (uuid, user_id, title, target_time, is_deleted, updated_at, version, device_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
              `).bind(cUuid, authUserId, cTitle, cTargetTime, cIsDeleted, cUpdatedAt, cVersion, device_id));
            } else {
              const finalTargetTime = cTargetTime || existing.target_time;
              if (cVersion > existing.version || cUpdatedAt > parseInt(existing.updated_at || 0) || !existing.uuid) {
                  batchStatements.push(DB.prepare(`
                    UPDATE countdowns SET uuid = ?, title = ?, target_time = ?, is_deleted = ?, updated_at = ?, version = ?, device_id = ?
                    WHERE id = ?
                  `).bind(cUuid, cTitle, finalTargetTime, cIsDeleted, cUpdatedAt, cVersion, device_id, existing.id));
              }
            }
          }
        }

        // 3. 屏幕时间
        if (screen_time && screen_time.device_name && screen_time.record_date && Array.isArray(screen_time.apps)) {
          const { device_name, record_date, apps } = screen_time;
          apps.forEach(app => {
            batchStatements.push(DB.prepare(`
              INSERT INTO screen_time_logs (user_id, device_name, record_date, app_name, duration)
              VALUES (?, ?, ?, ?, ?) ON CONFLICT(user_id, device_name, record_date, app_name)
              DO UPDATE SET duration = excluded.duration, updated_at = CURRENT_TIMESTAMP
            `).bind(authUserId, device_name.trim(), record_date, app.app_name, app.duration));
          });
        }

        // 提交所有客户端传来的批处理操作
        if (batchStatements.length > 0) await DB.batch(batchStatements);

        // ⚠️ 删除了之前那个非常危险的服务端按名字合并(deduplicateItems)的逻辑！

        // ==========================================
        // 4. 拉取最终的增量数据下发给客户端
        // ==========================================

        const serverTodosRaw = await DB.prepare(`
          SELECT * FROM todos
          WHERE user_id = ? AND updated_at > ? AND (device_id != ? OR device_id IS NULL)
        `).bind(authUserId, last_sync_time, device_id).all();

        const serverCountdownsRaw = await DB.prepare(`
          SELECT * FROM countdowns
          WHERE user_id = ? AND updated_at > ? AND (device_id != ? OR device_id IS NULL)
        `).bind(authUserId, last_sync_time, device_id).all();

        // 🚀 辅助函数：智能转换时间戳（处理毫秒时间戳和 ISO 字符串两种格式）
        const normalizeTimestamp = (val) => {
          if (val === null || val === undefined) return null;

          // 如果已经是数字，直接返回（毫秒时间戳）
          if (typeof val === 'number') {
            return val;
          }

          // 如果是字符串
          if (typeof val === 'string') {
            // 首先尝试当作整数解析（防止 SQLite 返回字符串化的毫秒时间戳）
            const asInt = parseInt(val, 10);
            if (!isNaN(asInt) && asInt > 0) {
              // 如果是一个很大的数字（13 位以上），就是毫秒时间戳
              if (asInt.toString().length >= 13) {
                return asInt;
              }
            }

            // 尝试当作 ISO 8601 字符串解析（SQLite TIMESTAMP 格式）
            const dt = new Date(val);
            if (!isNaN(dt.getTime())) {
              return dt.getTime();
            }
          }

          return null;
        };

        // 🚀 修复点 3：下发时不再删除 UUID。确保下发的记录中既有 id 也有 uuid，让 Flutter 端完美兼容无缝解析
        const mappedTodos = serverTodosRaw.results.map(row => {
            const idStr = row.uuid || String(row.id);
            // 🚀 修复时区问题：智能转换所有时间戳字段（处理毫秒时间戳和 ISO 字符串两种格式）
            return {
              ...row,
              id: idStr,
              uuid: idStr,
              created_at: normalizeTimestamp(row.created_at),     // 物理创建时间
              updated_at: normalizeTimestamp(row.updated_at),     // 最后修改时间
              created_date: normalizeTimestamp(row.created_date),  // 业务开始时间
              due_date: normalizeTimestamp(row.due_date)          // 截止时间
            };
        });

        const mappedCountdowns = serverCountdownsRaw.results.map(row => {
             const idStr = row.uuid || String(row.id);
             return {
               ...row,
               id: idStr,
               uuid: idStr,
               // 🚀 修复：所有时间戳字段都要智能转换
               created_at: normalizeTimestamp(row.created_at),
               updated_at: normalizeTimestamp(row.updated_at),
               target_time: normalizeTimestamp(row.target_time)
             };
        });

        // 提取账号状态
        const userRow = await DB.prepare("SELECT tier FROM users WHERE id = ?").bind(authUserId).first();
        const tier = userRow ? userRow.tier : 'free';
        const syncLimit = SYNC_LIMITS[tier] || SYNC_LIMITS.free;
        const todayStr = new Date().toISOString().split('T')[0];
        const record = await DB.prepare("SELECT sync_count FROM sync_limits WHERE user_id = ? AND sync_date = ?").bind(authUserId, todayStr).first();

        return jsonResponse({
          success: true,
          server_todos: mappedTodos,
          server_countdowns: mappedCountdowns,
          new_sync_time: now,
          status: { tier, sync_count: record ? record.sync_count : 1, sync_limit: syncLimit }
        });
      }

      // --------------------------
      // 模块 D: 屏幕使用时间 (Screen Time)
      // --------------------------
      if (url.pathname === "/api/screen_time" && request.method === "POST") {
        if (!authUserId) return errorResponse("未授权", 401);
        const { user_id, device_name, record_date, apps } = await request.json();
        if (authUserId !== parseInt(user_id, 10)) return errorResponse("越权操作被拒绝", 403);

        const now = Date.now();
        const limitError = await enforceSyncLimit(user_id, DB, now);
        if (limitError && limitError !== 'IGNORE') return errorResponse(limitError, 429);

        const batchStatements = apps.map(app => DB.prepare(`
          INSERT INTO screen_time_logs (user_id, device_name, record_date, app_name, duration)
          VALUES (?, ?, ?, ?, ?) ON CONFLICT(user_id, device_name, record_date, app_name)
          DO UPDATE SET duration = excluded.duration, updated_at = CURRENT_TIMESTAMP
        `).bind(authUserId, device_name.trim(), record_date, app.app_name, app.duration));

        if (batchStatements.length > 0) await DB.batch(batchStatements);
        return jsonResponse({ success: true });
      }

      if (url.pathname === "/api/screen_time" && request.method === "GET") {
        if (!authUserId) return errorResponse("未授权", 401);
        const userId = url.searchParams.get("user_id");
        const date = url.searchParams.get("date");
        if (authUserId !== parseInt(userId, 10)) return errorResponse("越权访问被拒绝", 403);

        const { results } = await DB.prepare(`
          SELECT COALESCE(m.mapped_name, s.app_name) AS app_name, COALESCE(m.category, '未分类') AS category, s.device_name, SUM(s.duration) AS duration
          FROM screen_time_logs s LEFT JOIN app_name_mappings m ON s.app_name = m.package_name
          WHERE s.user_id = ? AND s.record_date = ?
          GROUP BY COALESCE(m.mapped_name, s.app_name), COALESCE(m.category, '未分类'), s.device_name
          ORDER BY duration DESC
        `).bind(userId, date).all();
        return jsonResponse(results);
      }

      // --------------------------
      // 模块 E: 课程表 (Courses)
      // --------------------------
      if (url.pathname === "/api/courses" && request.method === "GET") {
        if (!authUserId) return errorResponse("未授权", 401);
        const userId = url.searchParams.get("user_id");
        const semester = url.searchParams.get("semester") || "default";
        if (authUserId !== parseInt(userId, 10)) return errorResponse("越权访问被拒绝", 403);

        const { results } = await DB.prepare(`SELECT * FROM courses WHERE user_id = ? AND semester = ? AND is_deleted = 0 ORDER BY week_index, weekday, start_time`).bind(userId, semester).all();
        return jsonResponse(results);
      }

      if (url.pathname === "/api/courses" && request.method === "POST") {
        if (!authUserId) return errorResponse("未授权", 401);
        const { user_id, courses, semester = "default" } = await request.json();
        if (authUserId !== parseInt(user_id, 10)) return errorResponse("越权操作被拒绝", 403);

        const now = Date.now();
        const limitError = await enforceSyncLimit(user_id, DB, now);
        if (limitError && limitError !== 'IGNORE') return errorResponse(limitError, 429);

        const batchStatements = [DB.prepare("DELETE FROM courses WHERE user_id = ? AND semester = ?").bind(user_id, semester)];
        for (const c of courses) {
          batchStatements.push(DB.prepare(`INSERT INTO courses (user_id, semester, course_name, room_name, teacher_name, start_time, end_time, weekday, week_index, lesson_type, created_at, updated_at, is_deleted) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)`).bind(user_id, semester, c.course_name, c.room_name, c.teacher_name, c.start_time, c.end_time, c.weekday, c.week_index, c.lesson_type, now, now));
        }

        if (batchStatements.length > 0) await DB.batch(batchStatements);
        return jsonResponse({ success: true });
      }

      return errorResponse("API Endpoint Not Found", 404);

    } catch (e) {
      return errorResponse(`Server Error: ${e.message}`, 500);
    }
  },
};

/**
 * 🚀 同步频率检查逻辑
 */
async function enforceSyncLimit(userId, DB, now) {
  const today = new Date(now).toISOString().split('T')[0];
  try {
    const userRow = await DB.prepare("SELECT tier FROM users WHERE id = ?").bind(userId).first();
    const tier = userRow ? userRow.tier : 'free';
    const limit = SYNC_LIMITS[tier] || SYNC_LIMITS.free;

    const record = await DB.prepare("SELECT * FROM sync_limits WHERE user_id = ? AND sync_date = ?").bind(userId, today).first();

    if (!record) {
      await DB.prepare("INSERT INTO sync_limits (user_id, sync_date, sync_count, last_sync_time) VALUES (?, ?, ?, ?)").bind(userId, today, 1, now).run();
      return null;
    }

    if (now - parseInt(record.last_sync_time) < 3000) return 'IGNORE';
    if (record.sync_count >= limit) return `今日同步次数已达上限 (${limit}次)`;

    await DB.prepare("UPDATE sync_limits SET sync_count = sync_count + 1, last_sync_time = ? WHERE user_id = ? AND sync_date = ?").bind(now, userId, today).run();
    return null;
  } catch (e) { return null; }
}

async function hashPassword(password) {
  const msgUint8 = new TextEncoder().encode(password);
  const hashBuffer = await crypto.subtle.digest("SHA-256", msgUint8);
  return Array.from(new Uint8Array(hashBuffer)).map(b => b.toString(16).padStart(2, "0")).join("");
}
