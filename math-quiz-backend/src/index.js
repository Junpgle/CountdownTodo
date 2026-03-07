/**
 * Math Quiz App Backend - Cloudflare Worker
 * 终极生产级：Delta Sync (增量同步) + 彻底解决 UUID 映射问题 + 修复清空日期的 null 覆盖 Bug
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

// 🕐 统一时间规范（v2 - 简洁版）
// 规范：所有时间字段存储和传输均使用 UTC 毫秒时间戳 (number)。
function normalizeToMs(val) {
  if (val === null || val === undefined) return 0;
  if (typeof val === 'number') return Math.floor(val);
  if (typeof val === 'string') {
    const trimmed = val.trim();
    if (!trimmed) return 0;

    // 🚀 修复：使用 Number() 直接转换，完美兼容 "1741276800000.0" 等 D1 数据库格式化现象
    const n = Number(trimmed);
    if (!isNaN(n)) return Math.floor(n);

    // 再尝试 ISO 8601 字符串
    const d = new Date(trimmed);
    if (!isNaN(d.getTime())) return d.getTime();
  }
  return 0;
}

// 🌍 时区工具：获取东八区（北京时间）的当前日期 YYYY-MM-DD
function getChinaDateStr(nowMs) {
  // 加上 8 小时的毫秒数 (8 * 60 * 60 * 1000 = 28800000)
  const d = new Date(nowMs + 28800000);
  return d.toISOString().split('T')[0];
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
      // 模块 A-2: 账户状态查询 (User Status)
      // --------------------------
      if (url.pathname === "/api/user/status" && request.method === "GET") {
        const userIdStr = url.searchParams.get("user_id");
        if (!userIdStr) return errorResponse("缺少 user_id 参数", 400);

        // 🚀 核心修复：必须强制转换为 Int，因为 url 取出来的是 String，D1 会直接拒绝匹配 INTEGER 字段，导致返回 null
        const userId = parseInt(userIdStr, 10);

        const userRow = await DB.prepare("SELECT tier FROM users WHERE id = ?").bind(userId).first();
        if (!userRow) return errorResponse("用户不存在", 404);

        const tier = userRow.tier || 'free';
        const syncLimit = SYNC_LIMITS[tier] || SYNC_LIMITS.free;

        const todayStr = getChinaDateStr(Date.now());
        const record = await DB.prepare("SELECT sync_count FROM sync_limits WHERE user_id = ? AND sync_date = ?").bind(userId, todayStr).first();

        return jsonResponse({
          success: true,
          tier: tier,
          sync_count: record ? record.sync_count : 0,
          sync_limit: syncLimit
        });
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
            return jsonResponse({ success: true, server_todos: [], server_countdowns: [], new_sync_time: last_sync_time });
        } else if (limitError) {
            return errorResponse(limitError, 429);
        }

        const batchStatements = [];

        // ── 检查 todos 表是否已有扩展列 ──
        const todoColumns = await DB.prepare("PRAGMA table_info(todos)").all();
        const todoColNames = new Set(todoColumns.results.map(r => r.name));
        const hasRecurrence       = todoColNames.has('recurrence');
        const hasCustomInterval   = todoColNames.has('custom_interval_days');
        const hasRecurrenceEnd    = todoColNames.has('recurrence_end_date');
        const hasRemark           = todoColNames.has('remark');

        // 1. 处理 Todos
        if (Array.isArray(todos)) {
          for (const t of todos) {
            const tUuid = String(t.uuid ?? t.id ?? t._id);
            const tContent = String(t.content ?? t.title ?? "");
            const tIsCompleted = (t.is_completed ?? t.isCompleted ?? t.isDone) ? 1 : 0;
            const tIsDeleted   = (t.is_deleted ?? t.isDeleted) ? 1 : 0;
            const tUpdatedAtClient = normalizeToMs(t.updated_at ?? t.updatedAt ?? now);
            const tVersion = parseInt(t.version || 1, 10);
            const tCreatedAt = normalizeToMs(t.created_at ?? t.createdAt) || now;

            const hasDueDate = 'due_date' in t || 'dueDate' in t;
            let tDueDate = null;
            if (hasDueDate) {
              const raw = t.due_date ?? t.dueDate;
              tDueDate = raw != null ? (normalizeToMs(raw) || null) : null;
            }

            const hasCreatedDate = 'created_date' in t || 'createdDate' in t;
            let tCreatedDate = null;
            if (hasCreatedDate) {
              const raw = t.created_date ?? t.createdDate;
              tCreatedDate = raw != null ? (normalizeToMs(raw) || null) : null;
            }

            const isRecurrenceProvided = hasRecurrence && ('recurrence' in t);
            const tRecurrence = isRecurrenceProvided ? parseInt(t.recurrence ?? 0, 10) : 0;

            const isCustomIntervalProvided = hasCustomInterval && ('custom_interval_days' in t || 'customIntervalDays' in t);
            let tCustomIntervalDays = null;
            if (isCustomIntervalProvided) {
              const raw = t.customIntervalDays ?? t.custom_interval_days;
              tCustomIntervalDays = raw != null ? parseInt(raw, 10) : null;
            }

            const isRecurrenceEndProvided = hasRecurrenceEnd && ('recurrence_end_date' in t || 'recurrenceEndDate' in t);
            let tRecurrenceEndDate = null;
            if (isRecurrenceEndProvided) {
              const raw = t.recurrenceEndDate ?? t.recurrence_end_date;
              tRecurrenceEndDate = raw != null ? (normalizeToMs(raw) || null) : null;
            }

            const isRemarkProvided = hasRemark && ('remark' in t);
            const tRemark = isRemarkProvided ? (t.remark != null ? String(t.remark) : null) : null;

            const extraCols = [
              hasRecurrence     ? 'recurrence'            : null,
              hasCustomInterval ? 'custom_interval_days'  : null,
              hasRecurrenceEnd  ? 'recurrence_end_date'   : null,
              hasRemark         ? 'remark'                : null,
            ].filter(Boolean);
            const extraColStr = extraCols.length > 0 ? ', ' + extraCols.join(', ') : '';

            let existing = await DB.prepare(
              `SELECT id, version, created_at, due_date, created_date, updated_at, uuid${extraColStr} FROM todos WHERE uuid = ? AND user_id = ?`
            ).bind(tUuid, authUserId).first();

            if (!existing) {
              existing = await DB.prepare(
                `SELECT id, version, created_at, due_date, created_date, updated_at, uuid${extraColStr} FROM todos WHERE user_id = ? AND content = ? AND (uuid IS NULL OR uuid = '')`
              ).bind(authUserId, tContent).first();
            }

            if (!existing) {
              let insertCols = `uuid, user_id, content, is_completed, is_deleted, created_at, updated_at, version, device_id, due_date, created_date`;
              let insertPlaceholders = `?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?`;
              let insertValues = [tUuid, authUserId, tContent, tIsCompleted, tIsDeleted, tCreatedAt, now, tVersion, device_id, tDueDate, tCreatedDate];

              if (hasRecurrence)     { insertCols += ', recurrence';            insertPlaceholders += ', ?'; insertValues.push(tRecurrence); }
              if (hasCustomInterval) { insertCols += ', custom_interval_days';  insertPlaceholders += ', ?'; insertValues.push(tCustomIntervalDays); }
              if (hasRecurrenceEnd)  { insertCols += ', recurrence_end_date';   insertPlaceholders += ', ?'; insertValues.push(tRecurrenceEndDate); }
              if (hasRemark)         { insertCols += ', remark';                insertPlaceholders += ', ?'; insertValues.push(tRemark); }

              let stmt = DB.prepare(`INSERT INTO todos (${insertCols}) VALUES (${insertPlaceholders})`);
              batchStatements.push(stmt.bind(...insertValues));

            } else {
              const finalDueDate     = hasDueDate       ? tDueDate           : (existing.due_date ?? null);
              const finalCreatedDate = hasCreatedDate   ? tCreatedDate       : (existing.created_date ?? null);

              const existingCreatedAt = normalizeToMs(existing.created_at) || tCreatedAt;
              const finalCreatedAt    = Math.min(tCreatedAt, existingCreatedAt) || existingCreatedAt;

              const existingUpdatedAtMs = normalizeToMs(existing.updated_at);
              if (tVersion > existing.version || tUpdatedAtClient > existingUpdatedAtMs || !existing.uuid) {
                let setClauses = [
                  'uuid = ?', 'content = ?', 'is_completed = ?', 'is_deleted = ?',
                  'created_at = ?', 'updated_at = ?', 'version = ?', 'device_id = ?',
                  'due_date = ?', 'created_date = ?'
                ];
                let setValues = [tUuid, tContent, tIsCompleted, tIsDeleted, finalCreatedAt, now, tVersion, device_id, finalDueDate, finalCreatedDate];

                if (hasRecurrence) {
                  setClauses.push('recurrence = ?');
                  setValues.push(isRecurrenceProvided ? tRecurrence : (existing.recurrence ?? 0));
                }
                if (hasCustomInterval) {
                  setClauses.push('custom_interval_days = ?');
                  setValues.push(isCustomIntervalProvided ? tCustomIntervalDays : (existing.custom_interval_days ?? null));
                }
                if (hasRecurrenceEnd) {
                  setClauses.push('recurrence_end_date = ?');
                  setValues.push(isRecurrenceEndProvided ? tRecurrenceEndDate : (existing.recurrence_end_date ?? null));
                }
                if (hasRemark) {
                  setClauses.push('remark = ?');
                  setValues.push(isRemarkProvided ? tRemark : (existing.remark ?? null));
                }

                setValues.push(existing.id);
                let stmt = DB.prepare(`UPDATE todos SET ${setClauses.join(', ')} WHERE id = ?`);
                batchStatements.push(stmt.bind(...setValues));
              }
            }
          }
        }

        // 2. 处理 Countdowns
        if (Array.isArray(countdowns)) {
          for (const c of countdowns) {
            const cUuid = String(c.uuid ?? c.id ?? c._id);
            const cTitle = String(c.title ?? "");

            const hasTargetTime = 'target_time' in c || 'targetTime' in c || 'targetDate' in c;
            let cTargetTime = null;
            if (hasTargetTime) {
              const raw = c.target_time ?? c.targetTime ?? c.targetDate;
              cTargetTime = raw != null ? (normalizeToMs(raw) || null) : null;
            }

            const cIsDeleted = (c.is_deleted ?? c.isDeleted) ? 1 : 0;
            const cUpdatedAtClient = normalizeToMs(c.updated_at ?? c.updatedAt ?? now);
            const cVersion = parseInt(c.version || 1, 10);
            const cCreatedAt = normalizeToMs(c.created_at ?? c.createdAt) || now;

            let existing = await DB.prepare(
              "SELECT id, version, created_at, target_time, updated_at, uuid FROM countdowns WHERE uuid = ? AND user_id = ?"
            ).bind(cUuid, authUserId).first();

            if (!existing) {
              existing = await DB.prepare(
                "SELECT id, version, created_at, target_time, updated_at, uuid FROM countdowns WHERE user_id = ? AND title = ? AND (uuid IS NULL OR uuid = '')"
              ).bind(authUserId, cTitle).first();
            }

            if (!existing) {
              batchStatements.push(DB.prepare(
                `INSERT INTO countdowns (uuid, user_id, title, target_time, is_deleted, created_at, updated_at, version, device_id)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
              ).bind(cUuid, authUserId, cTitle, cTargetTime, cIsDeleted, cCreatedAt, now, cVersion, device_id));
            } else {
              const finalTargetTime   = hasTargetTime ? cTargetTime : (existing.target_time ?? null);
              const existingCreatedAt = normalizeToMs(existing.created_at) || cCreatedAt;
              const finalCreatedAt    = Math.min(cCreatedAt, existingCreatedAt) || existingCreatedAt;
              const existingUpdatedAtMs = normalizeToMs(existing.updated_at);

              if (cVersion > (existing.version || 0) || cUpdatedAtClient > existingUpdatedAtMs || !existing.uuid) {
                batchStatements.push(DB.prepare(
                  `UPDATE countdowns SET uuid=?, title=?, target_time=?, is_deleted=?, created_at=?, updated_at=?, version=?, device_id=? WHERE id=?`
                ).bind(cUuid, cTitle, finalTargetTime, cIsDeleted, finalCreatedAt, now, cVersion, device_id, existing.id));
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

        if (batchStatements.length > 0) await DB.batch(batchStatements);

        // ==========================================
        // 4. 拉取最终的增量数据下发给客户端
        // ==========================================
        let serverTodosRaw;
        let serverCountdownsRaw;

        if (last_sync_time === 0) {
          // 🚀 核心修复：全量同步（本地被清除）时，必须无视 device_id 强制拉取云端所有数据！
          // 否则本设备曾经创建的数据会因为 `device_id != ?` 过滤拦截，导致数据永远拉不回来。
          serverTodosRaw = await DB.prepare(`
            SELECT * FROM todos WHERE user_id = ?
          `).bind(authUserId).all();

          serverCountdownsRaw = await DB.prepare(`
            SELECT * FROM countdowns WHERE user_id = ?
          `).bind(authUserId).all();
        } else {
          // 增量同步：排除本设备刚刚自己提交的数据
          serverTodosRaw = await DB.prepare(`
            SELECT * FROM todos
            WHERE user_id = ? AND (device_id != ? OR device_id IS NULL)
          `).bind(authUserId, device_id).all();

          serverCountdownsRaw = await DB.prepare(`
            SELECT * FROM countdowns
            WHERE user_id = ? AND (device_id != ? OR device_id IS NULL)
          `).bind(authUserId, device_id).all();
        }

        const normalizeTimestamp = (val) => normalizeToMs(val);
        const nullableTimestamp = (val) => {
          const ms = normalizeToMs(val);
          return ms > 0 ? ms : null;
        };

        const filteredTodos = serverTodosRaw.results.filter(row => normalizeToMs(row.updated_at) > last_sync_time);
        const filteredCountdowns = serverCountdownsRaw.results.filter(row => normalizeToMs(row.updated_at) > last_sync_time);

        const mappedTodos = filteredTodos.map(row => {
            const idStr = row.uuid || String(row.id);
            return {
              id: idStr,
              uuid: idStr,
              content: row.content,
              is_completed: row.is_completed,
              is_deleted: row.is_deleted,
              version: row.version,
              device_id: row.device_id,
              created_at:   normalizeTimestamp(row.created_at),
              updated_at:   normalizeTimestamp(row.updated_at),
              created_date: nullableTimestamp(row.created_date),
              due_date:     nullableTimestamp(row.due_date),
              recurrence:         row.recurrence         ?? 0,
              customIntervalDays: row.custom_interval_days ?? null,
              recurrenceEndDate:  nullableTimestamp(row.recurrence_end_date),
              recurrence_end_date:nullableTimestamp(row.recurrence_end_date),
              remark: row.remark ?? null,
            };
        });

        const mappedCountdowns = filteredCountdowns.map(row => {
             const idStr = row.uuid || String(row.id);
             return {
               id: idStr,
               uuid: idStr,
               title: row.title,
               is_deleted: row.is_deleted,
               version: row.version,
               device_id: row.device_id,
               created_at:  normalizeTimestamp(row.created_at),
               updated_at:  normalizeTimestamp(row.updated_at),
               target_time: nullableTimestamp(row.target_time),
             };
        });

        const userRow = await DB.prepare("SELECT tier FROM users WHERE id = ?").bind(authUserId).first();
        const tier = userRow ? userRow.tier : 'free';
        const syncLimit = SYNC_LIMITS[tier] || SYNC_LIMITS.free;
        const todayStr = getChinaDateStr(now);
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
        const userIdStr = url.searchParams.get("user_id");
        const userId = parseInt(userIdStr, 10); // 🚀 统一修复 Get 请求
        const date = url.searchParams.get("date");
        if (authUserId !== userId) return errorResponse("越权访问被拒绝", 403);

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
        const userIdStr = url.searchParams.get("user_id");
        const userId = parseInt(userIdStr, 10); // 🚀 统一修复 Get 请求
        const semester = url.searchParams.get("semester") || "default";
        if (authUserId !== userId) return errorResponse("越权访问被拒绝", 403);

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

      // --------------------------
      // 模块 F: 数据库迁移
      // --------------------------
      if (url.pathname === "/api/admin/migrate" && request.method === "POST") {
        if (!authUserId) return errorResponse("未授权", 401);
        if (authUserId !== 1) return errorResponse("仅管理员可执行迁移", 403);

        const migrations = [
          `ALTER TABLE todos ADD COLUMN recurrence INTEGER DEFAULT 0`,
          `ALTER TABLE todos ADD COLUMN custom_interval_days INTEGER`,
          `ALTER TABLE todos ADD COLUMN recurrence_end_date INTEGER`,
          `ALTER TABLE sync_limits ADD COLUMN last_sync_time INTEGER DEFAULT 0`
        ];

        const results = [];
        for (const sql of migrations) {
          try {
            await DB.prepare(sql).run();
            results.push({ sql, status: 'ok' });
          } catch (e) {
            const isDup = e.message && (e.message.includes('duplicate') || e.message.includes('already exists'));
            results.push({ sql, status: isDup ? 'already_exists' : `error: ${e.message}` });
          }
        }
        return jsonResponse({ success: true, results });
      }

      // --------------------------
      // 模块 G: 历史数据修复
      // --------------------------
      if (url.pathname === "/api/admin/fix_timestamps" && request.method === "POST") {
        if (!authUserId) return errorResponse("未授权", 401);
        if (authUserId !== 1) return errorResponse("仅管理员可执行修复", 403);

        const allTodos = await DB.prepare("SELECT id, created_at, updated_at, due_date, created_date FROM todos").all();
        let todoFixed = 0;
        const todoBatch = [];
        for (const row of allTodos.results) {
          const newCreatedAt  = normalizeToMs(row.created_at);
          const newUpdatedAt  = normalizeToMs(row.updated_at);
          const newDueDate    = normalizeToMs(row.due_date)    || null;
          const newCreatedDate= normalizeToMs(row.created_date)|| null;

          const changed =
            String(newCreatedAt)   !== String(row.created_at)  ||
            String(newUpdatedAt)   !== String(row.updated_at)  ||
            String(newDueDate)     !== String(row.due_date)    ||
            String(newCreatedDate) !== String(row.created_date);

          if (changed) {
            todoBatch.push(
              DB.prepare(
                "UPDATE todos SET created_at=?, updated_at=?, due_date=?, created_date=? WHERE id=?"
              ).bind(newCreatedAt, newUpdatedAt, newDueDate, newCreatedDate, row.id)
            );
            todoFixed++;
          }
        }

        const allCds = await DB.prepare("SELECT id, created_at, updated_at, target_time FROM countdowns").all();
        let cdFixed = 0;
        const cdBatch = [];
        for (const row of allCds.results) {
          const newCreatedAt = normalizeToMs(row.created_at);
          const newUpdatedAt = normalizeToMs(row.updated_at);
          const newTargetTime= normalizeToMs(row.target_time) || null;

          const changed =
            String(newCreatedAt)  !== String(row.created_at) ||
            String(newUpdatedAt)  !== String(row.updated_at) ||
            String(newTargetTime) !== String(row.target_time);

          if (changed) {
            cdBatch.push(
              DB.prepare(
                "UPDATE countdowns SET created_at=?, updated_at=?, target_time=? WHERE id=?"
              ).bind(newCreatedAt, newUpdatedAt, newTargetTime, row.id)
            );
            cdFixed++;
          }
        }

        const allBatch = [...todoBatch, ...cdBatch];
        for (let i = 0; i < allBatch.length; i += 100) {
          await DB.batch(allBatch.slice(i, i + 100));
        }

        return jsonResponse({
          success: true,
          todos_fixed: todoFixed,
          countdowns_fixed: cdFixed,
          total_todos: allTodos.results.length,
          total_countdowns: allCds.results.length,
        });
      }

      // --------------------------
      // 模块 H: 番茄钟标签 (pomodoro_tags)
      // --------------------------

      // 拉取用户标签
      if (url.pathname === "/api/pomodoro/tags" && request.method === "GET") {
        if (!authUserId) return errorResponse("未授权", 401);
        const { results } = await DB.prepare(
          "SELECT uuid, name, color, is_deleted, version, created_at, updated_at FROM pomodoro_tags WHERE user_id = ? ORDER BY created_at ASC"
        ).bind(authUserId).all();
        return jsonResponse(results);
      }

      // Delta Sync 上传标签
      if (url.pathname === "/api/pomodoro/tags" && request.method === "POST") {
        if (!authUserId) return errorResponse("未授权", 401);
        const { tags } = await request.json();
        if (!Array.isArray(tags)) return errorResponse("tags 格式错误");
        const now = Date.now();
        const batch = [];
        for (const tag of tags) {
          const uuid = String(tag.uuid ?? '');
          if (!uuid) continue;
          const name      = String(tag.name ?? '');
          const color     = String(tag.color ?? '#607D8B');
          const isDeleted = (tag.is_deleted ?? tag.isDeleted) ? 1 : 0;
          const version   = parseInt(tag.version ?? 1, 10);
          const createdAt = normalizeToMs(tag.created_at ?? tag.createdAt) || now;
          const updatedAt = normalizeToMs(tag.updated_at ?? tag.updatedAt) || now;

          const existing = await DB.prepare(
            "SELECT version, updated_at FROM pomodoro_tags WHERE uuid = ? AND user_id = ?"
          ).bind(uuid, authUserId).first();

          if (!existing) {
            batch.push(DB.prepare(
              "INSERT INTO pomodoro_tags (uuid, user_id, name, color, is_deleted, version, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?)"
            ).bind(uuid, authUserId, name, color, isDeleted, version, createdAt, updatedAt));
          } else if (version > (existing.version || 0) || updatedAt > normalizeToMs(existing.updated_at)) {
            batch.push(DB.prepare(
              "UPDATE pomodoro_tags SET name=?, color=?, is_deleted=?, version=?, updated_at=? WHERE uuid=? AND user_id=?"
            ).bind(name, color, isDeleted, version, updatedAt, uuid, authUserId));
          }
        }
        if (batch.length > 0) await DB.batch(batch);
        // 返回最新标签（含已删除，供客户端 LWW 合并）
        const { results } = await DB.prepare(
          "SELECT uuid, name, color, is_deleted, version, created_at, updated_at FROM pomodoro_tags WHERE user_id = ? ORDER BY created_at ASC"
        ).bind(authUserId).all();
        return jsonResponse({ success: true, tags: results });
      }

      // --------------------------
      // 模块 I: 番茄钟记录 (pomodoro_records)
      // --------------------------

      // 上传专注记录
      if (url.pathname === "/api/pomodoro/records" && request.method === "POST") {
        if (!authUserId) return errorResponse("未授权", 401);
        const body = await request.json();
        // 支持单条 { record: {...} } 或批量 { records: [...] }
        const records = Array.isArray(body.records) ? body.records
                      : (body.record ? [body.record] : []);
        if (records.length === 0) return errorResponse("records 为空");
        const now = Date.now();
        const batch = [];

        for (const r of records) {
          const uuid             = String(r.uuid ?? '');
          if (!uuid) continue;
          const todoUuid         = r.todo_uuid   ? String(r.todo_uuid)   : null;
          const startTime        = normalizeToMs(r.start_time)  || now;
          const endTime          = r.end_time != null ? (normalizeToMs(r.end_time) || null) : null;
          const plannedDuration  = typeof r.planned_duration === 'number' ? r.planned_duration : parseInt(r.planned_duration || 25*60, 10);
          const actualDuration   = r.actual_duration != null ? parseInt(r.actual_duration, 10) : null;
          const status           = ['completed','interrupted','switched'].includes(r.status) ? r.status : 'completed';
          const deviceId         = r.device_id   ? String(r.device_id)   : null;
          const isDeleted        = (r.is_deleted ?? r.isDeleted) ? 1 : 0;
          const version          = parseInt(r.version ?? 1, 10);
          const createdAt        = normalizeToMs(r.created_at ?? r.createdAt) || now;
          const updatedAt        = normalizeToMs(r.updated_at ?? r.updatedAt) || now;

          const existing = await DB.prepare(
            "SELECT version, updated_at FROM pomodoro_records WHERE uuid = ? AND user_id = ?"
          ).bind(uuid, authUserId).first();

          if (!existing) {
            batch.push(DB.prepare(`
              INSERT INTO pomodoro_records
                (uuid, user_id, todo_uuid, start_time, end_time, planned_duration, actual_duration, status, device_id, is_deleted, version, created_at, updated_at)
              VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
            `).bind(uuid, authUserId, todoUuid, startTime, endTime, plannedDuration, actualDuration, status, deviceId, isDeleted, version, createdAt, updatedAt));
          } else if (version > (existing.version || 0) || updatedAt > normalizeToMs(existing.updated_at)) {
            batch.push(DB.prepare(`
              UPDATE pomodoro_records SET
                todo_uuid=?, start_time=?, end_time=?, planned_duration=?, actual_duration=?,
                status=?, device_id=?, is_deleted=?, version=?, updated_at=?
              WHERE uuid=? AND user_id=?
            `).bind(todoUuid, startTime, endTime, plannedDuration, actualDuration, status, deviceId, isDeleted, version, updatedAt, uuid, authUserId));
          }

          // 同步 todo_tags 关联
          if (Array.isArray(r.tag_uuids) && r.tag_uuids.length > 0 && todoUuid) {
            for (const tagUuid of r.tag_uuids) {
              batch.push(DB.prepare(
                "INSERT OR REPLACE INTO todo_tags (todo_uuid, tag_uuid, is_deleted, updated_at) VALUES (?,?,0,?)"
              ).bind(todoUuid, String(tagUuid), now));
            }
          }
        }

        if (batch.length > 0) await DB.batch(batch);
        return jsonResponse({ success: true });
      }

      // 拉取专注记录（按时间范围）
      if (url.pathname === "/api/pomodoro/records" && request.method === "GET") {
        if (!authUserId) return errorResponse("未授权", 401);
        const fromMs = parseInt(url.searchParams.get("from") || "0", 10);
        const toMs   = parseInt(url.searchParams.get("to")   || String(Date.now()), 10);
        const { results } = await DB.prepare(`
          SELECT * FROM pomodoro_records
          WHERE user_id = ? AND is_deleted = 0
            AND start_time >= ? AND start_time <= ?
          ORDER BY start_time DESC
        `).bind(authUserId, fromMs, toMs).all();
        return jsonResponse(results);
      }

      // --------------------------
      // 模块 J: 番茄钟设置同步 (pomodoro_settings)
      // --------------------------

      if (url.pathname === "/api/pomodoro/settings" && request.method === "POST") {
        if (!authUserId) return errorResponse("未授权", 401);
        const { default_focus_duration, default_rest_duration, default_loop_count } = await request.json();
        const now = Date.now();
        await DB.prepare(`
          INSERT INTO pomodoro_settings (user_id, default_focus_duration, default_rest_duration, default_loop_count, updated_at)
          VALUES (?,?,?,?,?)
          ON CONFLICT(user_id) DO UPDATE SET
            default_focus_duration = excluded.default_focus_duration,
            default_rest_duration  = excluded.default_rest_duration,
            default_loop_count     = excluded.default_loop_count,
            updated_at             = excluded.updated_at
        `).bind(authUserId, default_focus_duration ?? 1500, default_rest_duration ?? 300, default_loop_count ?? 4, now).run();
        return jsonResponse({ success: true });
      }

      if (url.pathname === "/api/pomodoro/settings" && request.method === "GET") {
        if (!authUserId) return errorResponse("未授权", 401);
        const row = await DB.prepare(
          "SELECT * FROM pomodoro_settings WHERE user_id = ?"
        ).bind(authUserId).first();
        return jsonResponse(row ?? {
          user_id: authUserId,
          default_focus_duration: 1500,
          default_rest_duration: 300,
          default_loop_count: 4,
        });
      }

      return errorResponse("API Endpoint Not Found", 404);

    } catch (e) {
      return errorResponse(`Server Error: ${e.message}`, 500);
    }
  },
};

/**
 * 🚀 同步频率检查与防抖核心逻辑 (引入防崩降级策略)
 */
async function enforceSyncLimit(rawUserId, DB, now) {
  // 🚀 防御性编程：无论是谁调用，只要丢进来的 user_id，一律强转为整型！
  const userId = parseInt(rawUserId, 10);
  const today = getChinaDateStr(now);

  try {
    const userRow = await DB.prepare("SELECT tier FROM users WHERE id = ?").bind(userId).first();
    const tier = userRow ? userRow.tier : 'free';
    const limit = SYNC_LIMITS[tier] || SYNC_LIMITS.free;

    const record = await DB.prepare("SELECT * FROM sync_limits WHERE user_id = ? AND sync_date = ?").bind(userId, today).first();

    if (!record) {
      try {
        // 🚀 核心修复：使用 INSERT OR REPLACE 解决 user_id 存在 UNIQUE 约束导致的跨日报错问题，并兼顾并发安全
        await DB.prepare("INSERT OR REPLACE INTO sync_limits (user_id, sync_date, sync_count, last_sync_time) VALUES (?, ?, ?, ?)").bind(userId, today, 1, now).run();
      } catch (err) {
        await DB.prepare("INSERT OR REPLACE INTO sync_limits (user_id, sync_date, sync_count) VALUES (?, ?, ?)").bind(userId, today, 1).run();
      }
      return null;
    }

    if (record.last_sync_time && (now - parseInt(record.last_sync_time) < 3000)) return 'IGNORE';
    if (record.sync_count >= limit) return `今日同步次数已达上限 (${limit}次)`;

    try {
      await DB.prepare("UPDATE sync_limits SET sync_count = sync_count + 1, last_sync_time = ? WHERE user_id = ? AND sync_date = ?").bind(now, userId, today).run();
    } catch (err) {
      await DB.prepare("UPDATE sync_limits SET sync_count = sync_count + 1 WHERE user_id = ? AND sync_date = ?").bind(userId, today).run();
    }

    return null;
  } catch (e) {
    console.error("Sync Limit Error: ", e.message);
    return null;
  }
}

async function hashPassword(password) {
  const msgUint8 = new TextEncoder().encode(password);
  const hashBuffer = await crypto.subtle.digest("SHA-256", msgUint8);
  return Array.from(new Uint8Array(hashBuffer)).map(b => b.toString(16).padStart(2, "0")).join("");
}
