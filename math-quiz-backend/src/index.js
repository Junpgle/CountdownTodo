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

// 🕐 统一时间规范（v2 - 简洁版）
// 规范：所有时间字段存储和传输均使用 UTC 毫秒时间戳 (number)。
// Date.now() 本身就是 UTC epoch，无需任何时区偏移。
// 新数据统一使用 UTC 毫秒整数；历史数据库中可能存有 ISO 字符串，兼容解析但不再写入。
function normalizeToMs(val) {
  if (val === null || val === undefined) return 0;
  if (typeof val === 'number') return Math.floor(val);
  if (typeof val === 'string') {
    const trimmed = val.trim();
    // 先尝试纯数字（新格式）
    const n = parseInt(trimmed, 10);
    if (!isNaN(n) && String(n) === trimmed) return n;
    // 再尝试 ISO 8601 字符串（兼容历史数据库中触发器写入的旧格式）
    const d = new Date(trimmed);
    if (!isNaN(d.getTime())) return d.getTime();
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
            // 返回原来的 last_sync_time，不推进水位线，防止漏同步
            return jsonResponse({ success: true, server_todos: [], server_countdowns: [], new_sync_time: last_sync_time });
        } else if (limitError) {
            return errorResponse(limitError, 429);
        }

        const batchStatements = [];

        // ── 检查 todos 表是否已有扩展列（迁移后才有）──
        // 用一次 PRAGMA 查询缓存列信息，避免每行都查
        const todoColumns = await DB.prepare("PRAGMA table_info(todos)").all();
        const todoColNames = new Set(todoColumns.results.map(r => r.name));
        const hasRecurrence       = todoColNames.has('recurrence');
        const hasCustomInterval   = todoColNames.has('custom_interval_days');
        const hasRecurrenceEnd    = todoColNames.has('recurrence_end_date');

        // 1. 处理 Todos
        if (Array.isArray(todos)) {
          for (const t of todos) {
            const tUuid = String(t.uuid ?? t.id ?? t._id);
            const tContent = String(t.content ?? t.title ?? "");
            const tIsCompleted = (t.is_completed ?? t.isCompleted ?? t.isDone) ? 1 : 0;
            const tIsDeleted   = (t.is_deleted ?? t.isDeleted) ? 1 : 0;
            const tUpdatedAtClient = normalizeToMs(t.updated_at ?? t.updatedAt ?? now);
            const tVersion = parseInt(t.version || 1, 10);

            // created_at：物理创建时间，透传客户端原值（UTC ms），不使用 now
            const tCreatedAt = normalizeToMs(t.created_at ?? t.createdAt) || now;

            // due_date / created_date：存为 UTC ms 整数（覆盖 TEXT/TIMESTAMP 列的 ISO 默认值）
            let tDueDate = null;
            const dueDateRaw = t.due_date ?? t.dueDate;
            if (dueDateRaw != null) {
              const ms = normalizeToMs(dueDateRaw);
              if (ms > 0) tDueDate = ms;
            }

            let tCreatedDate = null;
            const createdDateRaw = t.created_date ?? t.createdDate;
            if (createdDateRaw != null) {
              const ms = normalizeToMs(createdDateRaw);
              if (ms > 0) tCreatedDate = ms;
            }

            // 循环字段（仅在列已存在时才处理）
            const tRecurrence = hasRecurrence ? parseInt(t.recurrence ?? 0, 10) : undefined;
            const tCustomIntervalDays = hasCustomInterval
              ? ((t.customIntervalDays != null || t.custom_interval_days != null)
                  ? parseInt(t.customIntervalDays ?? t.custom_interval_days, 10)
                  : null)
              : undefined;
            let tRecurrenceEndDate = undefined;
            if (hasRecurrenceEnd) {
              const recEndRaw = t.recurrenceEndDate ?? t.recurrence_end_date;
              if (recEndRaw != null) {
                const ms = normalizeToMs(recEndRaw);
                tRecurrenceEndDate = ms > 0 ? ms : null;
              } else {
                tRecurrenceEndDate = null;
              }
            }

            // SELECT 只查实际存在的列
            const extraCols = [
              hasRecurrence     ? 'recurrence'            : null,
              hasCustomInterval ? 'custom_interval_days'  : null,
              hasRecurrenceEnd  ? 'recurrence_end_date'   : null,
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
              // ── INSERT ──
              // 基础列（表中已有）
              let insertCols = `uuid, user_id, content, is_completed, is_deleted, created_at, updated_at, version, device_id, due_date, created_date`;
              let insertPlaceholders = `?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?`;
              let insertValues = [tUuid, authUserId, tContent, tIsCompleted, tIsDeleted, tCreatedAt, now, tVersion, device_id, tDueDate, tCreatedDate];

              if (hasRecurrence)     { insertCols += ', recurrence';            insertPlaceholders += ', ?'; insertValues.push(tRecurrence); }
              if (hasCustomInterval) { insertCols += ', custom_interval_days';  insertPlaceholders += ', ?'; insertValues.push(tCustomIntervalDays); }
              if (hasRecurrenceEnd)  { insertCols += ', recurrence_end_date';   insertPlaceholders += ', ?'; insertValues.push(tRecurrenceEndDate); }

              let stmt = DB.prepare(`INSERT INTO todos (${insertCols}) VALUES (${insertPlaceholders})`);
              batchStatements.push(stmt.bind(...insertValues));

            } else {
              // ── UPDATE ──
              // ⚠️ 保护：已有值的字段不能被 null 覆盖
              const finalDueDate     = tDueDate     ?? existing.due_date     ?? null;
              const finalCreatedDate = tCreatedDate ?? existing.created_date ?? null;
              // created_at 取最小值（保留最早的物理创建时间）
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
                  setValues.push(tRecurrence);
                }
                if (hasCustomInterval) {
                  const finalCI = tCustomIntervalDays != null ? tCustomIntervalDays : (existing.custom_interval_days ?? null);
                  setClauses.push('custom_interval_days = ?');
                  setValues.push(finalCI);
                }
                if (hasRecurrenceEnd) {
                  const finalRE = tRecurrenceEndDate ?? existing.recurrence_end_date ?? null;
                  setClauses.push('recurrence_end_date = ?');
                  setValues.push(finalRE);
                }

                setValues.push(existing.id);
                let stmt = DB.prepare(`UPDATE todos SET ${setClauses.join(', ')} WHERE id = ?`);
                batchStatements.push(stmt.bind(...setValues));
              }
            }
          }
        }

        // 2. 处理 Countdowns
        // countdowns 表结构已确认：id, user_id, title, target_time, created_at, updated_at, is_deleted, device_id, version, uuid
        if (Array.isArray(countdowns)) {
          for (const c of countdowns) {
            const cUuid = String(c.uuid ?? c.id ?? c._id);
            const cTitle = String(c.title ?? "");

            // target_time：UTC ms 整数
            let cTargetTime = null;
            const targetTimeRaw = c.target_time ?? c.targetTime ?? c.targetDate;
            if (targetTimeRaw != null) {
              const ms = normalizeToMs(targetTimeRaw);
              if (ms > 0) cTargetTime = ms;
            }

            const cIsDeleted = (c.is_deleted ?? c.isDeleted) ? 1 : 0;
            const cUpdatedAtClient = normalizeToMs(c.updated_at ?? c.updatedAt ?? now);
            const cVersion = parseInt(c.version || 1, 10);
            // created_at：透传客户端原值
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
              // ⚠️ 保护：target_time 有新值才覆盖
              const finalTargetTime   = cTargetTime ?? existing.target_time ?? null;
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

        // 提交所有客户端传来的批处理操作
        if (batchStatements.length > 0) await DB.batch(batchStatements);

        // ⚠️ 删除了之前那个非常危险的服务端按名字合并(deduplicateItems)的逻辑！

        // ==========================================
        // 4. 拉取最终的增量数据下发给客户端
        // ==========================================

        // 所有 updated_at 均为 UTC 毫秒整数，用 normalizeToMs 统一转换后与 last_sync_time 比较。
        const serverTodosRaw = await DB.prepare(`
          SELECT * FROM todos
          WHERE user_id = ? AND (device_id != ? OR device_id IS NULL)
        `).bind(authUserId, device_id).all();

        const serverCountdownsRaw = await DB.prepare(`
          SELECT * FROM countdowns
          WHERE user_id = ? AND (device_id != ? OR device_id IS NULL)
        `).bind(authUserId, device_id).all();

        // 所有时间字段均为 UTC 毫秒时间戳，直接转数字
        const normalizeTimestamp = (val) => normalizeToMs(val);
        // 可空时间字段：0 / null 统一返回 null，避免 Flutter 把 0 解析为 1970-01-01
        const nullableTimestamp = (val) => {
          const ms = normalizeToMs(val);
          return ms > 0 ? ms : null;
        };

        // 只下发 updated_at > last_sync_time 的增量记录
        const filteredTodos = serverTodosRaw.results.filter(row => normalizeToMs(row.updated_at) > last_sync_time);
        const filteredCountdowns = serverCountdownsRaw.results.filter(row => normalizeToMs(row.updated_at) > last_sync_time);

        // 下发时明确映射每个字段，时间字段全部规范化为 UTC ms int
        const mappedTodos = filteredTodos.map(row => {
            const idStr = row.uuid || String(row.id);
            const mapped = {
              id: idStr,
              uuid: idStr,
              content: row.content,
              is_completed: row.is_completed,
              is_deleted: row.is_deleted,
              version: row.version,
              device_id: row.device_id,
              created_at:   normalizeTimestamp(row.created_at),  // 物理创建时间
              updated_at:   normalizeTimestamp(row.updated_at),  // 最后修改时间
              created_date: nullableTimestamp(row.created_date), // 任务开始时间（可为 null）
              due_date:     nullableTimestamp(row.due_date),     // 任务截止时间（可为 null）
              // 循环字段：若列不存在则返回默认值，Flutter 端可正常解析
              recurrence:         row.recurrence         ?? 0,
              customIntervalDays: row.custom_interval_days ?? null,
              recurrenceEndDate:  nullableTimestamp(row.recurrence_end_date),
              recurrence_end_date:nullableTimestamp(row.recurrence_end_date),
            };
            return mapped;
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
               target_time: nullableTimestamp(row.target_time), // 不能降级成 0/1970
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

      // --------------------------
      // 模块 F: 数据库迁移 — 幂等，可重复调用
      // --------------------------
      if (url.pathname === "/api/admin/migrate" && request.method === "POST") {
        if (!authUserId) return errorResponse("未授权", 401);
        if (authUserId !== 1) return errorResponse("仅管理员可执行迁移", 403);

        // todos 表缺少 3 列（countdowns 表结构已完整，无需迁移）
        const migrations = [
          `ALTER TABLE todos ADD COLUMN recurrence INTEGER DEFAULT 0`,
          `ALTER TABLE todos ADD COLUMN custom_interval_days INTEGER`,
          `ALTER TABLE todos ADD COLUMN recurrence_end_date INTEGER`,
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
      // 模块 G: 历史数据修复 — 把所有 ISO 字符串时间字段转为 UTC ms 整数
      // 幂等：已经是整数的行不会被修改（normalizeToMs 对整数原样返回）
      // --------------------------
      if (url.pathname === "/api/admin/fix_timestamps" && request.method === "POST") {
        if (!authUserId) return errorResponse("未授权", 401);
        if (authUserId !== 1) return errorResponse("仅管理员可执行修复", 403);

        // ── 修复 todos ──
        const allTodos = await DB.prepare("SELECT id, created_at, updated_at, due_date, created_date FROM todos").all();
        let todoFixed = 0;
        const todoBatch = [];
        for (const row of allTodos.results) {
          const newCreatedAt  = normalizeToMs(row.created_at);
          const newUpdatedAt  = normalizeToMs(row.updated_at);
          const newDueDate    = normalizeToMs(row.due_date)    || null;
          const newCreatedDate= normalizeToMs(row.created_date)|| null;

          // 只有当至少一个字段值发生变化时才更新
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

        // ── 修复 countdowns ──
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

        // 分批提交（D1 每次 batch 上限 100 条）
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
