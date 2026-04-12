/**
 * Math Quiz App Backend - Cloudflare Worker
 * 终极生产级：Delta Sync (增量同步) + 彻底解决 UUID 映射问题 + 密码重置
 * [新增] 忘记密码 / 重置密码完整流程
 * [新增] 支持 S2S (Server to Server) 智能安全合并，动态映射双端不一致的 User ID
 */

const SYNC_LIMITS = {
  free: 500,
  pro: 2000,
  admin: 99999
};

// 🛡️ 鉴权：生成 HMAC 签名 Token
async function signToken(userId, env) {
  const secret = env.API_SECRET;
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

// 🕐 统一时间规范
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

function getChinaDateStr(nowMs) {
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
      "Access-Control-Allow-Headers": "Content-Type, x-user-id, Authorization, x-admin-secret",
    };

    if (request.method === "OPTIONS") return new Response("OK", { headers: corsHeaders });

    const jsonResponse = (data, status = 200) => {
      return new Response(JSON.stringify(data), { status: status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    };

    const errorResponse = (msg, status = 400) => jsonResponse({ error: msg }, status);

    try {
      if (!env.math_quiz_db) throw new Error(`数据库绑定失败！`);
      const DB = env.math_quiz_db;

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

      // ==========================================
      // 🔐 忘记密码：步骤1 - 请求发送验证码
      // ==========================================
      if (url.pathname === "/api/auth/forgot_password" && request.method === "POST") {
        const { email } = await request.json();

        if (!email) return errorResponse("请提供绑定的邮箱地址");
        if (!env.RESEND_API_KEY) return errorResponse("服务端未配置邮件服务", 500);

        // 1. 检查邮箱是否已注册
        const user = await DB.prepare("SELECT id FROM users WHERE email = ?").bind(email).first();
        if (!user) return errorResponse("该邮箱尚未注册", 404);

        // 2. 容错建表：确保 password_resets 表存在
        await DB.prepare(`CREATE TABLE IF NOT EXISTS password_resets (email TEXT PRIMARY KEY, code TEXT, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)`).run();

        // 3. 防频繁发信检查 (60秒冷却)
        const existingRequest = await DB.prepare("SELECT created_at FROM password_resets WHERE email = ?").bind(email).first();
        if (existingRequest) {
            const lastRequestTime = new Date(existingRequest.created_at + 'Z').getTime();
            if (Date.now() - lastRequestTime < 60 * 1000) {
                return errorResponse("获取验证码过于频繁，请 1 分钟后再试", 429);
            }
        }

        // 4. 生成 6 位验证码并存入数据库
        const newCode = Math.floor(100000 + Math.random() * 900000).toString();
        await DB.prepare("INSERT OR REPLACE INTO password_resets (email, code) VALUES (?, ?)").bind(email, newCode).run();

        // 5. 调用 Resend 发送邮件
        const resendResponse = await fetch("https://api.resend.com/emails", {
            method: "POST",
            headers: {"Authorization": `Bearer ${env.RESEND_API_KEY}`, "Content-Type": "application/json"},
            body: JSON.stringify({
                from: "Math Quiz <Math&Quiz@junpgle.me>",
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

        if (!resendResponse.ok) return errorResponse("验证邮件发送失败，请稍后再试", 400);
        return jsonResponse({success: true, message: "重置验证码已发送至您的邮箱"});
      }

      // ==========================================
      // 🔐 忘记密码：步骤2 - 校验验证码并修改密码
      // ==========================================
      if (url.pathname === "/api/auth/reset_password" && request.method === "POST") {
        const { email, code, new_password } = await request.json();

        if (!email || !code || !new_password) return errorResponse("缺少必要字段：邮箱、验证码或新密码");

        // 前置校验密码长度，节省 CPU 计算资源
        if (new_password.length < 6) return errorResponse("密码长度不能少于 6 位");

        // 1. 查找验证码记录
        const resetRecord = await DB.prepare("SELECT * FROM password_resets WHERE email = ?").bind(email).first();
        if (!resetRecord) return errorResponse("未找到该邮箱的重置请求，请重新获取验证码");

        // 2. 校验验证码是否正确
        if (resetRecord.code !== code.toString()) return errorResponse("验证码错误");

        // 3. 校验验证码是否过期 (15分钟)
        const createdTime = new Date(resetRecord.created_at + 'Z').getTime();
        if (Date.now() - createdTime > 15 * 60 * 1000) {
            await DB.prepare("DELETE FROM password_resets WHERE email = ?").bind(email).run(); // 清理过期记录
            return errorResponse("验证码已过期，请重新获取");
        }

        // 4. 加密新密码并更新数据库
        const hash = await hashPassword(new_password);
        await DB.prepare("UPDATE users SET password_hash = ? WHERE email = ?").bind(hash, email).run();

        // 5. 使用完毕后清理验证码记录
        await DB.prepare("DELETE FROM password_resets WHERE email = ?").bind(email).run();

        return jsonResponse({success: true, message: "密码重置成功，请使用新密码登录"});
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
      // 模块 A-2: 账户状态查询
      // --------------------------
      if (url.pathname === "/api/user/status" && request.method === "GET") {
        const userIdStr = url.searchParams.get("user_id");
        if (!userIdStr) return errorResponse("缺少 user_id 参数", 400);

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
      // 模块 B: 排行榜
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

        let payload;
        try {
          payload = await request.json();
        } catch (e) {
          return errorResponse("请求体 JSON 格式错误", 400);
        }

        const { user_id, last_sync_time = 0, device_id, screen_time } = payload;
        const todos = payload.todos || payload.todos_changes || payload.todosChanges || [];
        const countdowns = payload.countdowns || payload.countdowns_changes || payload.countdownsChanges || [];
        const todoGroups = payload.todo_groups || payload.todo_groups_changes || payload.todoGroupsChanges || [];
        const timeLogs = payload.time_logs_changes || payload.timeLogsChanges || [];

        if (authUserId !== parseInt(user_id, 10)) return errorResponse("越权操作被拒绝", 403);
        if (!device_id) return errorResponse("缺少 device_id", 400);

        console.log(`[SYNC] userId=${user_id} deviceId=${device_id} todos=${todos.length} countdowns=${countdowns.length} timeLogs=${timeLogs.length} screenTime=${screen_time ? 'present' : 'empty'}`);

        const now = Date.now();
        const limitError = await enforceSyncLimit(user_id, DB, now);
        if (limitError === 'IGNORE') {
            return jsonResponse({ success: true, server_todos: [], server_countdowns: [], server_time_logs: [], new_sync_time: last_sync_time });
        } else if (limitError) {
            return errorResponse(limitError, 429);
        }

        const batchStatements = [];

        // 0. 容错建表与增量表架构更新
        await DB.prepare(`CREATE TABLE IF NOT EXISTS todo_groups (id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT, user_id INTEGER, name TEXT, is_expanded INTEGER DEFAULT 0, is_deleted INTEGER DEFAULT 0, version INTEGER DEFAULT 1, updated_at INTEGER, created_at INTEGER, UNIQUE(user_id, uuid))`).run();

        const todoColumns = await DB.prepare("PRAGMA table_info(todos)").all();
        let todoColNames = new Set(todoColumns.results.map(r => r.name));

        if (!todoColNames.has('group_id')) {
            try {
                await DB.prepare("ALTER TABLE todos ADD COLUMN group_id TEXT").run();
                // 刷新列名集合
                const refreshedTodoColumns = await DB.prepare("PRAGMA table_info(todos)").all();
                todoColNames = new Set(refreshedTodoColumns.results.map(r => r.name));
            } catch(e) {
                console.error("Failed to add group_id column:", e.message);
            }
        }

        const hasRecurrence       = todoColNames.has('recurrence');
        const hasCustomInterval   = todoColNames.has('custom_interval_days');
        const hasRecurrenceEnd    = todoColNames.has('recurrence_end_date');
        const hasRemark           = todoColNames.has('remark');
        const hasGroupId          = todoColNames.has('group_id');

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

            const extraCols = [
              hasRecurrence     ? 'recurrence'            : null,
              hasCustomInterval ? 'custom_interval_days'  : null,
              hasRecurrenceEnd  ? 'recurrence_end_date'   : null,
              hasRemark         ? 'remark'                : null,
              hasGroupId        ? 'group_id'              : null,
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

            let tGroupId = null;
            if (t.hasOwnProperty('group_id')) {
              tGroupId = t.group_id;
            } else if (t.hasOwnProperty('groupId')) {
              tGroupId = t.groupId;
            } else if (existing && hasGroupId) {
              tGroupId = existing.group_id;
            }

            if (!existing) {
              let insertCols = `uuid, user_id, content, is_completed, is_deleted, created_at, updated_at, version, device_id, due_date, created_date`;
              let insertPlaceholders = `?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?`;
              let insertValues = [tUuid, authUserId, tContent, tIsCompleted, tIsDeleted, tCreatedAt, now, tVersion, device_id, tDueDate, tCreatedDate];

              if (hasRecurrence)     { insertCols += ', recurrence';            insertPlaceholders += ', ?'; insertValues.push(tRecurrence); }
              if (hasCustomInterval) { insertCols += ', custom_interval_days';  insertPlaceholders += ', ?'; insertValues.push(tCustomIntervalDays); }
              if (hasRecurrenceEnd)  { insertCols += ', recurrence_end_date';   insertPlaceholders += ', ?'; insertValues.push(tRecurrenceEndDate); }
              if (hasRemark)         { insertCols += ', remark';                insertPlaceholders += ', ?'; insertValues.push(tRemark); }
              if (hasGroupId)        { insertCols += ', group_id';              insertPlaceholders += ', ?'; insertValues.push(tGroupId); }

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

                if (hasGroupId) {
                  setClauses.push('group_id = ?');
                  setValues.push(tGroupId);
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
              const finalCreatedAt    = Math.min(cCreatedAt, normalizeToMs(existing.created_at) || cCreatedAt);
              if (cVersion > (existing.version || 0) || cUpdatedAtClient > normalizeToMs(existing.updated_at) || !existing.uuid) {
                batchStatements.push(DB.prepare(
                  `UPDATE countdowns SET uuid=?, title=?, target_time=?, is_deleted=?, created_at=?, updated_at=?, version=?, device_id=? WHERE id=?`
                ).bind(cUuid, cTitle, finalTargetTime, cIsDeleted, finalCreatedAt, now, cVersion, device_id, existing.id));
              }
            }
          }
        }

        // 2.5 处理 Todo Groups (文件夹)
        if (Array.isArray(todoGroups)) {
          for (const g of todoGroups) {
            const gUuid = String(g.uuid ?? g.id ?? g._id);
            const gName = String(g.name ?? "未命名分组");
            const gIsExpanded = (g.is_expanded ?? g.isExpanded) ? 1 : 0;
            const gIsDeleted = (g.is_deleted ?? g.isDeleted) ? 1 : 0;
            const gVersion = parseInt(g.version || 1, 10);
            const gUpdatedAtClient = normalizeToMs(g.updated_at ?? g.updatedAt ?? now);
            const gCreatedAt = normalizeToMs(g.created_at ?? g.createdAt) || now;

            const existing = await DB.prepare("SELECT uuid, version, updated_at FROM todo_groups WHERE uuid = ? AND user_id = ?").bind(gUuid, authUserId).first();
            if (!existing) {
              batchStatements.push(DB.prepare(`INSERT INTO todo_groups (uuid, user_id, name, is_expanded, is_deleted, version, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`).bind(gUuid, authUserId, gName, gIsExpanded, gIsDeleted, gVersion, gCreatedAt, now));
            } else if (gVersion > (existing.version || 0) || gUpdatedAtClient > normalizeToMs(existing.updated_at)) {
              batchStatements.push(DB.prepare(`UPDATE todo_groups SET name=?, is_expanded=?, is_deleted=?, version=?, updated_at=? WHERE uuid=? AND user_id=?`).bind(gName, gIsExpanded, gIsDeleted, gVersion, now, gUuid, authUserId));
            }
          }
        }

        // 3. 处理 Time Logs
        if (Array.isArray(timeLogs)) {
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

            let existing = await DB.prepare("SELECT uuid, version, created_at, updated_at FROM time_logs WHERE uuid = ? AND user_id = ?").bind(lUuid, authUserId).first();

            if (!existing) {
              batchStatements.push(DB.prepare(
                `INSERT INTO time_logs (uuid, user_id, title, tag_uuids, start_time, end_time, remark, is_deleted, created_at, updated_at, version, device_id)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
              ).bind(lUuid, authUserId, lTitle, lTagUuids, lStartTime, lEndTime, lRemark, lIsDeleted, lCreatedAt, now, lVersion, device_id));
            } else {
              const finalCreatedAt = Math.min(lCreatedAt, normalizeToMs(existing.created_at) || lCreatedAt);
              if (lVersion > (existing.version || 0) || lUpdatedAtClient > normalizeToMs(existing.updated_at) || !existing.uuid) {
                batchStatements.push(DB.prepare(
                  `UPDATE time_logs SET title=?, tag_uuids=?, start_time=?, end_time=?, remark=?, is_deleted=?, created_at=?, updated_at=?, version=?, device_id=? WHERE uuid=?`
                ).bind(lTitle, lTagUuids, lStartTime, lEndTime, lRemark, lIsDeleted, finalCreatedAt, now, lVersion, device_id, existing.uuid));
              }
            }
          }
        }

        // 4. 屏幕时间
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

        // 5. 拉取最终的增量数据
        let serverTodosRaw, serverCountdownsRaw, serverTimeLogsRaw, serverTodoGroupsRaw;

        if (last_sync_time === 0) {
          serverTodosRaw = await DB.prepare(`SELECT * FROM todos WHERE user_id = ?`).bind(authUserId).all();
          serverCountdownsRaw = await DB.prepare(`SELECT * FROM countdowns WHERE user_id = ?`).bind(authUserId).all();
          serverTodoGroupsRaw = await DB.prepare(`SELECT * FROM todo_groups WHERE user_id = ?`).bind(authUserId).all();
          serverTimeLogsRaw = await DB.prepare(`SELECT * FROM time_logs WHERE user_id = ?`).bind(authUserId).all();
        } else {
          serverTodosRaw = await DB.prepare(`SELECT * FROM todos WHERE user_id = ? AND (device_id != ? OR device_id IS NULL)`).bind(authUserId, device_id).all();
          serverCountdownsRaw = await DB.prepare(`SELECT * FROM countdowns WHERE user_id = ? AND (device_id != ? OR device_id IS NULL)`).bind(authUserId, device_id).all();
          serverTodoGroupsRaw = await DB.prepare(`SELECT * FROM todo_groups WHERE user_id = ?`).bind(authUserId).all();
          serverTimeLogsRaw = await DB.prepare(`SELECT * FROM time_logs WHERE user_id = ? AND (device_id != ? OR device_id IS NULL)`).bind(authUserId, device_id).all();
        }

        const normalizeTimestamp = (val) => normalizeToMs(val);
        const nullableTimestamp = (val) => { const ms = normalizeToMs(val); return ms > 0 ? ms : null; };

        const filteredTodos = serverTodosRaw.results.filter(row => normalizeToMs(row.updated_at) > last_sync_time);
        const filteredCountdowns = serverCountdownsRaw.results.filter(row => normalizeToMs(row.updated_at) > last_sync_time);
        const filteredTimeLogs = serverTimeLogsRaw.results.filter(row => normalizeToMs(row.updated_at) > last_sync_time);

        const mappedTodos = filteredTodos.map(row => {
            const idStr = row.uuid || String(row.id);
            return {
              id: idStr, uuid: idStr, content: row.content, is_completed: row.is_completed, is_deleted: row.is_deleted, version: row.version, device_id: row.device_id,
              created_at: normalizeTimestamp(row.created_at), updated_at: normalizeTimestamp(row.updated_at), created_date: nullableTimestamp(row.created_date), due_date: nullableTimestamp(row.due_date), recurrence: row.recurrence ?? 0, customIntervalDays: row.custom_interval_days ?? null, recurrenceEndDate: nullableTimestamp(row.recurrence_end_date), recurrence_end_date: nullableTimestamp(row.recurrence_end_date), remark: row.remark ?? null, group_id: row.group_id ?? null,
            };
        });

        const mappedTodoGroups = serverTodoGroupsRaw.results.filter(row => normalizeToMs(row.updated_at) > last_sync_time).map(row => {
            const idStr = row.uuid || String(row.id);
            return {
              id: idStr, uuid: idStr, name: row.name, is_expanded: row.is_expanded === 1, is_deleted: row.is_deleted === 1, version: row.version,
              created_at: normalizeTimestamp(row.created_at), updated_at: normalizeTimestamp(row.updated_at)
            };
        });

        const mappedCountdowns = filteredCountdowns.map(row => {
             const idStr = row.uuid || String(row.id);
             return { id: idStr, uuid: idStr, title: row.title, is_deleted: row.is_deleted, version: row.version, device_id: row.device_id, created_at: normalizeTimestamp(row.created_at), updated_at: normalizeTimestamp(row.updated_at), target_time: nullableTimestamp(row.target_time) };
        });

        const mappedTimeLogs = filteredTimeLogs.map(row => {
             const idStr = row.uuid;
             let parsedTags = []; try { parsedTags = JSON.parse(row.tag_uuids || '[]'); } catch (e) { }
             return { id: idStr, uuid: idStr, title: row.title, tag_uuids: parsedTags, start_time: normalizeTimestamp(row.start_time), end_time: normalizeTimestamp(row.end_time), remark: row.remark ?? null, is_deleted: row.is_deleted, version: row.version, device_id: row.device_id, created_at: normalizeTimestamp(row.created_at), updated_at: normalizeTimestamp(row.updated_at) };
        });

        const userRow = await DB.prepare("SELECT tier FROM users WHERE id = ?").bind(authUserId).first();
        const tier = userRow ? userRow.tier : 'free';
        const syncLimit = SYNC_LIMITS[tier] || SYNC_LIMITS.free;
        const todayStr = getChinaDateStr(now);
        const record = await DB.prepare("SELECT sync_count FROM sync_limits WHERE user_id = ? AND sync_date = ?").bind(authUserId, todayStr).first();

        return jsonResponse({
          success: true,
          server_todos: mappedTodos,
          server_todo_groups: mappedTodoGroups,
          server_countdowns: mappedCountdowns,
          server_time_logs: mappedTimeLogs,
          new_sync_time: now,
          status: { tier, sync_count: record ? record.sync_count : 1, sync_limit: syncLimit }
        });
      }

      // --------------------------
      // 模块 D: 屏幕使用时间
      // --------------------------
      if (url.pathname === "/api/screen_time" && request.method === "POST") {
        if (!authUserId) return errorResponse("未授权", 401);

        let body;
        try {
          body = await request.json();
        } catch (e) {
          return errorResponse("请求体 JSON 格式错误", 400);
        }

        const { user_id, device_name, record_date, apps } = body;
        if (!user_id) return errorResponse("缺少 user_id", 400);
        if (!device_name) return errorResponse("缺少 device_name", 400);
        if (!record_date) return errorResponse("缺少 record_date", 400);
        if (!apps || !Array.isArray(apps)) return errorResponse("缺少 apps 数组", 400);

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
        const userId = parseInt(url.searchParams.get("user_id"), 10);
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
      // 模块 E: 课程表 & 用户设置
      // --------------------------
      if (url.pathname === "/api/courses" && request.method === "GET") {
        if (!authUserId) return errorResponse("未授权", 401);
        const userId = parseInt(url.searchParams.get("user_id"), 10);
        const semester = url.searchParams.get("semester") || "default";
        if (authUserId !== userId) return errorResponse("越权", 403);
        const { results } = await DB.prepare(`SELECT * FROM courses WHERE user_id = ? AND semester = ? AND is_deleted = 0 ORDER BY week_index, weekday, start_time`).bind(userId, semester).all();
        return jsonResponse(results);
      }

      if (url.pathname === "/api/courses" && request.method === "POST") {
        if (!authUserId) return errorResponse("未授权", 401);
        const { user_id, courses, semester = "default" } = await request.json();
        if (authUserId !== parseInt(user_id, 10)) return errorResponse("越权", 403);
        const now = Date.now();
        const limitError = await enforceSyncLimit(user_id, DB, now);
        if (limitError && limitError !== 'IGNORE') return errorResponse(limitError, 429);

        const batchStatements = [DB.prepare("DELETE FROM courses WHERE user_id = ? AND semester = ?").bind(user_id, semester)];
        for (const c of courses) {
          batchStatements.push(DB.prepare(`INSERT INTO courses (user_id, semester, course_name, room_name, teacher_name, start_time, end_time, weekday, week_index, lesson_type, created_at, updated_at, is_deleted) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)`).bind(user_id, semester, c.course_name, c.room_name, c.teacher_name, c.start_time, c.end_time, c.weekday, c.week_index, c.lesson_type, 0, now, now));
        }
        if (batchStatements.length > 0) await DB.batch(batchStatements);
        return jsonResponse({ success: true });
      }

      if (url.pathname === "/api/settings" && request.method === "GET") {
        if (!authUserId) return errorResponse("未授权", 401);
        const row = await DB.prepare("SELECT semester_start, semester_end FROM users WHERE id = ?").bind(authUserId).first();
        return jsonResponse({ success: true, semester_start: row?.semester_start ?? null, semester_end: row?.semester_end ?? null });
      }

      if (url.pathname === "/api/settings" && request.method === "POST") {
        if (!authUserId) return errorResponse("未授权", 401);
        const body = await request.json();
        const semStart = body.semester_start != null ? normalizeToMs(body.semester_start) : null;
        const semEnd = body.semester_end != null ? normalizeToMs(body.semester_end) : null;
        await DB.prepare("UPDATE users SET semester_start = ?, semester_end = ? WHERE id = ?").bind(semStart, semEnd, authUserId).run();
        return jsonResponse({ success: true });
      }

      // --------------------------
      // 模块 H/I/J: 番茄钟
      // --------------------------
      if (url.pathname === "/api/pomodoro/tags" && request.method === "GET") {
        if (!authUserId) return errorResponse("未授权", 401);
        const { results } = await DB.prepare("SELECT uuid, name, color, is_deleted, version, created_at, updated_at FROM pomodoro_tags WHERE user_id = ? ORDER BY created_at ASC").bind(authUserId).all();
        return jsonResponse(results);
      }

      if (url.pathname === "/api/pomodoro/tags" && request.method === "POST") {
        if (!authUserId) return errorResponse("未授权", 401);
        const { tags } = await request.json();
        if (!Array.isArray(tags)) return errorResponse("tags 格式错误");
        const now = Date.now();
        const batch = [];
        for (const tag of tags) {
          const uuid = String(tag.uuid ?? '');
          if (!uuid) continue;
          const name = String(tag.name ?? '');
          const color = String(tag.color ?? '#607D8B');
          const isDeleted = (tag.is_deleted ?? tag.isDeleted) ? 1 : 0;
          const version = parseInt(tag.version ?? 1, 10);
          const createdAt = normalizeToMs(tag.created_at ?? tag.createdAt) || now;
          const updatedAt = normalizeToMs(tag.updated_at ?? tag.updatedAt) || now;

          const existing = await DB.prepare("SELECT version, updated_at FROM pomodoro_tags WHERE uuid = ? AND user_id = ?").bind(uuid, authUserId).first();
          if (!existing) {
            batch.push(DB.prepare("INSERT INTO pomodoro_tags (uuid, user_id, name, color, is_deleted, version, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?)").bind(uuid, authUserId, name, color, isDeleted, version, createdAt, updatedAt));
          } else if (version > (existing.version || 0) || updatedAt > normalizeToMs(existing.updated_at)) {
            batch.push(DB.prepare("UPDATE pomodoro_tags SET name=?, color=?, is_deleted=?, version=?, updated_at=? WHERE uuid=? AND user_id=?").bind(name, color, isDeleted, version, updatedAt, uuid, authUserId));
          }
        }
        if (batch.length > 0) await DB.batch(batch);
        const { results } = await DB.prepare("SELECT uuid, name, color, is_deleted, version, created_at, updated_at FROM pomodoro_tags WHERE user_id = ? ORDER BY created_at ASC").bind(authUserId).all();
        return jsonResponse({ success: true, tags: results });
      }

      if (url.pathname === "/api/pomodoro/active" && request.method === "GET") {
        if (!authUserId) return errorResponse("未授权", 401);
        const deviceId = url.searchParams.get("device_id") || "";
        const fiveMinAgo = Date.now() - 5 * 60 * 1000;
        const row = await DB.prepare(`SELECT uuid, todo_uuid, start_time, planned_duration, device_id FROM pomodoro_records WHERE user_id = ? AND is_deleted = 0 AND end_time IS NULL AND start_time >= ? AND (device_id IS NULL OR device_id != ?) ORDER BY start_time DESC LIMIT 1`).bind(authUserId, fiveMinAgo, deviceId).first();
        if (!row) return jsonResponse({ active: false });
        return jsonResponse({ active: true, record: row });
      }

      if (url.pathname === "/api/pomodoro/records" && request.method === "POST") {
        if (!authUserId) return errorResponse("未授权", 401);
        const body = await request.json();
        const records = Array.isArray(body.records) ? body.records : (body.record ? [body.record] : []);
        if (records.length === 0) return errorResponse("records 为空");
        const now = Date.now();
        const batch = [];

        for (const r of records) {
          const uuid = String(r.uuid ?? '');
          if (!uuid) continue;
          const todoUuid = r.todo_uuid ? String(r.todo_uuid) : null;
          const startTime = normalizeToMs(r.start_time) || now;
          const endTime = r.end_time != null ? (normalizeToMs(r.end_time) || null) : null;
          const plannedDuration = typeof r.planned_duration === 'number' ? r.planned_duration : parseInt(r.planned_duration || 25*60, 10);
          const actualDuration = r.actual_duration != null ? parseInt(r.actual_duration, 10) : null;
          const status = ['completed','interrupted','switched'].includes(r.status) ? r.status : 'completed';
          const deviceId = r.device_id ? String(r.device_id) : null;
          const isDeleted = (r.is_deleted ?? r.isDeleted) ? 1 : 0;
          const version = parseInt(r.version ?? 1, 10);
          const createdAt = normalizeToMs(r.created_at ?? r.createdAt) || now;
          const updatedAt = normalizeToMs(r.updated_at ?? r.updatedAt) || now;
          const tagUuidsArr = Array.isArray(r.tag_uuids) ? r.tag_uuids.map(String) : [];

          const existing = await DB.prepare("SELECT version, updated_at FROM pomodoro_records WHERE uuid = ? AND user_id = ?").bind(uuid, authUserId).first();
          if (!existing) {
            batch.push(DB.prepare(`INSERT INTO pomodoro_records (uuid, user_id, todo_uuid, start_time, end_time, planned_duration, actual_duration, status, device_id, is_deleted, version, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)`).bind(uuid, authUserId, todoUuid, startTime, endTime, plannedDuration, actualDuration, status, deviceId, isDeleted, version, createdAt, updatedAt));
          } else if (version > (existing.version || 0) || updatedAt > normalizeToMs(existing.updated_at)) {
            batch.push(DB.prepare(`UPDATE pomodoro_records SET todo_uuid=?, start_time=?, end_time=?, planned_duration=?, actual_duration=?, status=?, device_id=?, is_deleted=?, version=?, updated_at=? WHERE uuid=? AND user_id=?`).bind(todoUuid, startTime, endTime, plannedDuration, actualDuration, status, deviceId, isDeleted, version, updatedAt, uuid, authUserId));
          }

          if (tagUuidsArr.length > 0) {
            const tagsKey = todoUuid || uuid;
            for (const tagUuid of tagUuidsArr) {
              batch.push(DB.prepare("INSERT OR REPLACE INTO todo_tags (todo_uuid, tag_uuid, is_deleted, updated_at) VALUES (?,?,0,?)").bind(tagsKey, tagUuid, now));
            }
          }
        }
        if (batch.length > 0) await DB.batch(batch);
        return jsonResponse({ success: true });
      }

      if (url.pathname === "/api/pomodoro/records" && request.method === "GET") {
        if (!authUserId) return errorResponse("未授权", 401);
        const fromMs = parseInt(url.searchParams.get("from") || "0", 10);
        const toMs = parseInt(url.searchParams.get("to") || String(Date.now()), 10);
        const { results } = await DB.prepare(`
          SELECT r.*, t.content AS todo_title, GROUP_CONCAT(tt.tag_uuid) AS tag_uuids_concat
          FROM pomodoro_records r LEFT JOIN todos t ON r.todo_uuid = t.uuid LEFT JOIN todo_tags tt ON COALESCE(r.todo_uuid, r.uuid) = tt.todo_uuid AND tt.is_deleted = 0
          WHERE r.user_id = ? AND r.is_deleted = 0 AND r.start_time >= ? AND r.start_time <= ? GROUP BY r.uuid ORDER BY r.start_time DESC
        `).bind(authUserId, fromMs, toMs).all();

        const enriched = results.map(r => ({
          ...r, tag_uuids: r.tag_uuids_concat ? r.tag_uuids_concat.split(',').filter(Boolean) : [], tag_uuids_concat: undefined,
        }));
        return jsonResponse(enriched);
      }

      if (url.pathname === "/api/pomodoro/settings" && request.method === "POST") {
        if (!authUserId) return errorResponse("未授权", 401);
        const { default_focus_duration, default_rest_duration, default_loop_count, timer_mode } = await request.json();
        await DB.prepare(`INSERT INTO pomodoro_settings (user_id, default_focus_duration, default_rest_duration, default_loop_count, timer_mode, updated_at) VALUES (?,?,?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET default_focus_duration = excluded.default_focus_duration, default_rest_duration  = excluded.default_rest_duration, default_loop_count = excluded.default_loop_count, timer_mode = excluded.timer_mode, updated_at = excluded.updated_at`).bind(authUserId, default_focus_duration ?? 1500, default_rest_duration ?? 300, default_loop_count ?? 4, timer_mode ?? 0, Date.now()).run();
        return jsonResponse({ success: true });
      }

      if (url.pathname === "/api/pomodoro/settings" && request.method === "GET") {
        if (!authUserId) return errorResponse("未授权", 401);
        const row = await DB.prepare("SELECT * FROM pomodoro_settings WHERE user_id = ?").bind(authUserId).first();
        return jsonResponse(row ?? { user_id: authUserId, default_focus_duration: 1500, default_rest_duration: 300, default_loop_count: 4, timer_mode: 0 });
      }

      // --------------------------
      // 🚀 模块 K: 服务器间底层安全合并 (S2S Merge Sync)
      // --------------------------
      if (url.pathname === "/api/admin/s2s_receive_merge" && request.method === "POST") {
        const adminSecret = request.headers.get("x-admin-secret");
        if (adminSecret !== (env.API_SECRET)) {
          return errorResponse("S2S 验证失败：非法访问", 401);
        }

        const body = await request.json();
        const batchStatements = [];
        let syncedRecords = 0;
        const userIdMap = {}; // 核心映射表：阿里云 user_id -> Cloudflare user_id

        // 1. 智能合并 Users 表 (依据 Email 进行精准身份对齐)
        if (body.users && body.users.length > 0) {
          for (const u of body.users) {
            const existing = await DB.prepare("SELECT id FROM users WHERE email = ?").bind(u.email).first();
            if (existing) {
              userIdMap[u.id] = existing.id;
              // 更新此用户的其他常规信息，绝不改变 ID 和 Email
              await DB.prepare(`UPDATE users SET username=?, password_hash=?, tier=?, avatar_url=?, semester_start=?, semester_end=? WHERE id=?`)
                .bind(u.username, u.password_hash, u.tier, u.avatar_url, u.semester_start, u.semester_end, existing.id).run();
              syncedRecords++;
            } else {
              // 插入全新用户，利用 RETURNING id 获取 D1 数据库自增产生的新真实 ID
              const result = await DB.prepare(`INSERT INTO users (username, email, password_hash, tier, avatar_url, semester_start, semester_end, created_at) VALUES (?,?,?,?,?,?,?,?) RETURNING id`)
                .bind(u.username, u.email, u.password_hash, u.tier, u.avatar_url, u.semester_start, u.semester_end, u.created_at).first();
              if (result && result.id) {
                userIdMap[u.id] = result.id;
                syncedRecords++;
              }
            }
          }
        }

        // 用于将外键自动转换到云端合法 ID 上的工具函数
        const getMappedUserId = (oldId) => userIdMap[oldId] || oldId;

        // 2. 合并 Todos (利用 ON CONFLICT DO UPDATE 搭配 WHERE LWW最后写入者胜)
        if (body.todos && body.todos.length > 0) {
          body.todos.forEach(t => {
            if (!t.uuid) return;
            batchStatements.push(DB.prepare(`
              INSERT INTO todos (uuid, user_id, content, is_completed, is_deleted, version, device_id, created_at, updated_at, due_date, created_date, recurrence, custom_interval_days, recurrence_end_date, remark)
              VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
              ON CONFLICT(uuid) DO UPDATE SET
                content=excluded.content, is_completed=excluded.is_completed, is_deleted=excluded.is_deleted, version=excluded.version, device_id=excluded.device_id, updated_at=excluded.updated_at, due_date=excluded.due_date, created_date=excluded.created_date, recurrence=excluded.recurrence, custom_interval_days=excluded.custom_interval_days, recurrence_end_date=excluded.recurrence_end_date, remark=excluded.remark
              WHERE excluded.updated_at > todos.updated_at OR (excluded.updated_at = todos.updated_at AND excluded.version > todos.version)
            `).bind(t.uuid, getMappedUserId(t.user_id), t.content, t.is_completed, t.is_deleted, t.version, t.device_id, t.created_at, t.updated_at, t.due_date, t.created_date, t.recurrence, t.custom_interval_days, t.recurrence_end_date, t.remark));
          });
        }

        // 3. 合并 Countdowns
        if (body.countdowns && body.countdowns.length > 0) {
          body.countdowns.forEach(c => {
            if (!c.uuid) return;
            batchStatements.push(DB.prepare(`
              INSERT INTO countdowns (uuid, user_id, title, target_time, is_deleted, version, device_id, created_at, updated_at)
              VALUES (?,?,?,?,?,?,?,?,?)
              ON CONFLICT(uuid) DO UPDATE SET
                title=excluded.title, target_time=excluded.target_time, is_deleted=excluded.is_deleted, version=excluded.version, device_id=excluded.device_id, updated_at=excluded.updated_at
              WHERE excluded.updated_at > countdowns.updated_at OR (excluded.updated_at = countdowns.updated_at AND excluded.version > countdowns.version)
            `).bind(c.uuid, getMappedUserId(c.user_id), c.title, c.target_time, c.is_deleted, c.version, c.device_id, c.created_at, c.updated_at));
          });
        }

        // 4. 合并 Time Logs
        if (body.time_logs && body.time_logs.length > 0) {
          body.time_logs.forEach(l => {
            if (!l.uuid) return;
            batchStatements.push(DB.prepare(`
              INSERT INTO time_logs (uuid, user_id, title, tag_uuids, start_time, end_time, remark, is_deleted, version, device_id, created_at, updated_at)
              VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
              ON CONFLICT(uuid) DO UPDATE SET
                title=excluded.title, tag_uuids=excluded.tag_uuids, start_time=excluded.start_time, end_time=excluded.end_time, remark=excluded.remark, is_deleted=excluded.is_deleted, version=excluded.version, device_id=excluded.device_id, updated_at=excluded.updated_at
              WHERE excluded.updated_at > time_logs.updated_at OR (excluded.updated_at = time_logs.updated_at AND excluded.version > time_logs.version)
            `).bind(l.uuid, getMappedUserId(l.user_id), l.title, l.tag_uuids, l.start_time, l.end_time, l.remark, l.is_deleted, l.version, l.device_id, l.created_at, l.updated_at));
          });
        }

        // 5. 合并 Pomodoro Tags
        if (body.pomodoro_tags && body.pomodoro_tags.length > 0) {
          body.pomodoro_tags.forEach(p => {
            if (!p.uuid) return;
            batchStatements.push(DB.prepare(`
              INSERT INTO pomodoro_tags (uuid, user_id, name, color, is_deleted, version, created_at, updated_at)
              VALUES (?,?,?,?,?,?,?,?)
              ON CONFLICT(uuid) DO UPDATE SET
                name=excluded.name, color=excluded.color, is_deleted=excluded.is_deleted, version=excluded.version, updated_at=excluded.updated_at
              WHERE excluded.updated_at > pomodoro_tags.updated_at OR (excluded.updated_at = pomodoro_tags.updated_at AND excluded.version > pomodoro_tags.version)
            `).bind(p.uuid, getMappedUserId(p.user_id), p.name, p.color, p.is_deleted, p.version, p.created_at, p.updated_at));
          });
        }

        // 6. 合并 Pomodoro Records
        if (body.pomodoro_records && body.pomodoro_records.length > 0) {
          body.pomodoro_records.forEach(p => {
            if (!p.uuid) return;
            batchStatements.push(DB.prepare(`
              INSERT INTO pomodoro_records (uuid, user_id, todo_uuid, start_time, end_time, planned_duration, actual_duration, status, device_id, is_deleted, version, created_at, updated_at)
              VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
              ON CONFLICT(uuid) DO UPDATE SET
                todo_uuid=excluded.todo_uuid, start_time=excluded.start_time, end_time=excluded.end_time, planned_duration=excluded.planned_duration, actual_duration=excluded.actual_duration, status=excluded.status, device_id=excluded.device_id, is_deleted=excluded.is_deleted, version=excluded.version, updated_at=excluded.updated_at
              WHERE excluded.updated_at > pomodoro_records.updated_at OR (excluded.updated_at = pomodoro_records.updated_at AND excluded.version > pomodoro_records.version)
            `).bind(p.uuid, getMappedUserId(p.user_id), p.todo_uuid, p.start_time, p.end_time, p.planned_duration, p.actual_duration, p.status, p.device_id, p.is_deleted, p.version, p.created_at, p.updated_at));
          });
        }

        // 7. 合并 Pomodoro Settings
        if (body.pomodoro_settings && body.pomodoro_settings.length > 0) {
          body.pomodoro_settings.forEach(p => {
            batchStatements.push(DB.prepare(`
              INSERT INTO pomodoro_settings (user_id, default_focus_duration, default_rest_duration, default_loop_count, timer_mode, updated_at)
              VALUES (?,?,?,?,?,?)
              ON CONFLICT(user_id) DO UPDATE SET
                default_focus_duration=excluded.default_focus_duration, default_rest_duration=excluded.default_rest_duration, default_loop_count=excluded.default_loop_count, timer_mode=excluded.timer_mode, updated_at=excluded.updated_at
              WHERE excluded.updated_at > pomodoro_settings.updated_at
            `).bind(getMappedUserId(p.user_id), p.default_focus_duration, p.default_rest_duration, p.default_loop_count, p.timer_mode ?? 0, p.updated_at));
          });
        }

        // 8. 合并 Tags
        if (body.todo_tags && body.todo_tags.length > 0) {
          body.todo_tags.forEach(t => {
            batchStatements.push(DB.prepare(`
              INSERT INTO todo_tags (todo_uuid, tag_uuid, is_deleted, updated_at)
              VALUES (?,?,?,?)
              ON CONFLICT(todo_uuid, tag_uuid) DO UPDATE SET
                is_deleted=excluded.is_deleted, updated_at=excluded.updated_at
              WHERE excluded.updated_at > todo_tags.updated_at
            `).bind(t.todo_uuid, t.tag_uuid, t.is_deleted, t.updated_at));
          });
        }

        // 9. 合并 Screen Time Logs (多主键复合唯一限制下的自动覆盖)
        if (body.screen_time_logs && body.screen_time_logs.length > 0) {
          body.screen_time_logs.forEach(s => {
            batchStatements.push(DB.prepare(`
              INSERT INTO screen_time_logs (user_id, device_name, record_date, app_name, duration, updated_at)
              VALUES (?,?,?,?,?,?)
              ON CONFLICT(user_id, device_name, record_date, app_name) DO UPDATE SET
                duration=excluded.duration, updated_at=excluded.updated_at
              WHERE excluded.updated_at > screen_time_logs.updated_at
            `).bind(getMappedUserId(s.user_id), s.device_name, s.record_date, s.app_name, s.duration, s.updated_at));
          });
        }

        // 10. 合并 App Name Mappings
        if (body.app_name_mappings && body.app_name_mappings.length > 0) {
          body.app_name_mappings.forEach(a => {
            batchStatements.push(DB.prepare(`
              INSERT INTO app_name_mappings (package_name, mapped_name, category)
              VALUES (?,?,?)
              ON CONFLICT(package_name) DO UPDATE SET
                mapped_name=excluded.mapped_name, category=excluded.category
            `).bind(a.package_name, a.mapped_name, a.category));
          });
        }

        // 11. 谨慎合并 Courses：检测是否存在重复的记录，不存在才插入
        if (body.courses && body.courses.length > 0) {
          for (const c of body.courses) {
             const mappedId = getMappedUserId(c.user_id);
             const existing = await DB.prepare("SELECT id FROM courses WHERE user_id=? AND semester=? AND course_name=? AND weekday=? AND start_time=?").bind(mappedId, c.semester, c.course_name, c.weekday, c.start_time).first();
             if (!existing) {
               batchStatements.push(DB.prepare(`
                 INSERT INTO courses (user_id, semester, course_name, room_name, teacher_name, start_time, end_time, weekday, week_index, lesson_type, is_deleted, created_at, updated_at)
                 VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
               `).bind(mappedId, c.semester, c.course_name, c.room_name, c.teacher_name, c.start_time, c.end_time, c.weekday, c.week_index, c.lesson_type, c.is_deleted, c.created_at, c.updated_at));
             } else if (c.updated_at) {
               batchStatements.push(DB.prepare(`
                 UPDATE courses SET room_name=?, teacher_name=?, end_time=?, week_index=?, lesson_type=?, is_deleted=?, updated_at=?
                 WHERE id=? AND ? > updated_at
               `).bind(c.room_name, c.teacher_name, c.end_time, c.week_index, c.lesson_type, c.is_deleted, c.updated_at, existing.id, c.updated_at));
             }
          }
        }

        // 12. 谨慎合并 Leaderboard：防止重复生成积分历史
        if (body.leaderboard && body.leaderboard.length > 0) {
           for (const l of body.leaderboard) {
              const mappedId = getMappedUserId(l.user_id);
              const existing = await DB.prepare("SELECT id FROM leaderboard WHERE user_id=? AND score=? AND duration=? AND played_at=?").bind(mappedId, l.score, l.duration, l.played_at).first();
              if (!existing) {
                 batchStatements.push(DB.prepare(`INSERT INTO leaderboard (user_id, username, score, duration, played_at) VALUES (?,?,?,?,?)`).bind(mappedId, l.username, l.score, l.duration, l.played_at));
              }
           }
        }

        // 13. 合并 Todo Groups
        if (body.todo_groups && body.todo_groups.length > 0) {
          body.todo_groups.forEach(g => {
            if (!g.uuid) return;
            batchStatements.push(DB.prepare(`
              INSERT INTO todo_groups (uuid, user_id, name, is_expanded, is_deleted, version, created_at, updated_at)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?)
              ON CONFLICT(user_id, uuid) DO UPDATE SET
                name=excluded.name, is_expanded=excluded.is_expanded, is_deleted=excluded.is_deleted, version=excluded.version, updated_at=excluded.updated_at
              WHERE excluded.updated_at > todo_groups.updated_at OR (excluded.updated_at = todo_groups.updated_at AND excluded.version > todo_groups.version)
            `).bind(g.uuid, getMappedUserId(g.user_id), g.name, g.is_expanded, g.is_deleted, g.version, g.created_at, g.updated_at));
          });
        }

        // 统一提交批处理，单次最多执行 100 条 (Cloudflare 限制)
        syncedRecords += batchStatements.length;
        if (batchStatements.length > 0) {
          for (let i = 0; i < batchStatements.length; i += 100) {
            await DB.batch(batchStatements.slice(i, i + 100));
          }
        }

        return jsonResponse({ success: true, synced_records: syncedRecords, message: "Smart Merge Complete" });
      }

	if (url.pathname === "/api/admin/s2s_export" && request.method === "GET") {
	  try {
		const adminSecret = request.headers.get("x-admin-secret");
		if (adminSecret !== (env.API_SECRET)) {
			return errorResponse("S2S 验证失败：非法访问", 401);
		}

		// 容错：导出前确保表存在
		await DB.prepare(`CREATE TABLE IF NOT EXISTS todo_groups (id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT, user_id INTEGER, name TEXT, is_expanded INTEGER DEFAULT 0, is_deleted INTEGER DEFAULT 0, version INTEGER DEFAULT 1, updated_at INTEGER, created_at INTEGER, UNIQUE(user_id, uuid))`).run();

		// 获取所有表的全量数据
		const payload = {
			users: (await DB.prepare("SELECT * FROM users").all()).results,
			todos: (await DB.prepare("SELECT * FROM todos").all()).results,
			countdowns: (await DB.prepare("SELECT * FROM countdowns").all()).results,
			time_logs: (await DB.prepare("SELECT * FROM time_logs").all()).results,
			courses: (await DB.prepare("SELECT * FROM courses").all()).results,
			pomodoro_tags: (await DB.prepare("SELECT * FROM pomodoro_tags").all()).results,
			pomodoro_records: (await DB.prepare("SELECT * FROM pomodoro_records").all()).results,
			pomodoro_settings: (await DB.prepare("SELECT * FROM pomodoro_settings").all()).results,
			todo_tags: (await DB.prepare("SELECT * FROM todo_tags").all()).results,
			screen_time_logs: (await DB.prepare("SELECT * FROM screen_time_logs").all()).results,
			leaderboard: (await DB.prepare("SELECT * FROM leaderboard").all()).results,
			app_name_mappings: (await DB.prepare("SELECT * FROM app_name_mappings").all()).results,
			todo_groups: (await DB.prepare("SELECT * FROM todo_groups").all()).results
		};
		return jsonResponse({ success: true, data: payload });
	  } catch (e) {
		return errorResponse(`导出失败: ${e.message}`, 500);
	  }
	}

	return errorResponse("API Endpoint Not Found", 404);

  } catch (e) {
	return errorResponse(`Server Error: ${e.message}`, 500);
  }
},
};



/**
 * 🚀 同步频率检查与防抖核心逻辑
 */
async function enforceSyncLimit(rawUserId, DB, now) {
  const userId = parseInt(rawUserId, 10);
  const today = getChinaDateStr(now);

  try {
    const userRow = await DB.prepare("SELECT tier FROM users WHERE id = ?").bind(userId).first();
    const tier = userRow ? userRow.tier : 'free';
    const limit = SYNC_LIMITS[tier] || SYNC_LIMITS.free;

    const record = await DB.prepare("SELECT * FROM sync_limits WHERE user_id = ? AND sync_date = ?").bind(userId, today).first();

    if (!record) {
      try {
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
