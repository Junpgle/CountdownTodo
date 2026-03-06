/**
 * Math Quiz App Backend - Cloudflare Worker
 * 终极版：LWW 时间戳与 ISO 字符串兼容 + 基于 ID 的精准状态与内容同步
 */

const SYNC_LIMITS = {
  free: 500,
  pro: 2000,
  admin: 99999
};

// 🚀 全能时间解析器：兼容处理老版本数字时间戳和新版本 ISO 字符串
function getTimeMs(t) {
  if (!t) return 0;
  // 如果已经是数字
  if (typeof t === 'number') return t;
  // 如果是字符串
  if (typeof t === 'string') {
    // 纯数字构成的字符串 (老版本的时间戳遗留)
    if (/^\d+$/.test(t)) return parseInt(t, 10);
    // 标准的 ISO8601 时间字符串
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
      "Access-Control-Allow-Headers": "Content-Type, x-user-id",
    };

    if (request.method === "OPTIONS") {
      return new Response("OK", { headers: corsHeaders });
    }

    const jsonResponse = (data, status = 200) => {
      return new Response(JSON.stringify(data), {
        status: status,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    };

    const errorResponse = (msg, status = 400) => {
      return jsonResponse({ error: msg }, status);
    };

    try {
      if (!env.math_quiz_db) {
        throw new Error(`数据库绑定失败！`);
      }
      const DB = env.math_quiz_db;

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
        return jsonResponse({ success: true, user: { id: user.id, username: user.username, email: user.email, avatar_url: user.avatar_url, tier: user.tier } });
      }

      if (url.pathname === "/api/auth/change_password" && request.method === "POST") {
        const { user_id, old_password, new_password } = await request.json();
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
        const userId = url.searchParams.get("user_id");
        if (!userId) return errorResponse("缺少 user_id");

        const userRow = await DB.prepare("SELECT tier FROM users WHERE id = ?").bind(userId).first();
        const tier = userRow ? userRow.tier : 'free';
        const sync_limit = SYNC_LIMITS[tier] || SYNC_LIMITS.free;

        const today = new Date().toISOString().split('T')[0];
        const record = await DB.prepare("SELECT sync_count FROM sync_limits WHERE user_id = ? AND sync_date = ?").bind(userId, today).first();
        const sync_count = record ? record.sync_count : 0;

        return jsonResponse({ success: true, tier: tier, sync_count: sync_count, sync_limit: sync_limit });
      }

      // --------------------------
      // 模块 B: 排行榜
      // --------------------------
      if (url.pathname === "/api/leaderboard" && request.method === "GET") {
        const { results } = await DB.prepare("SELECT username, score, duration, played_at FROM leaderboard ORDER BY score DESC, duration ASC LIMIT 50").all();
        return jsonResponse(results);
      }

      if (url.pathname === "/api/leaderboard" && request.method === "POST") {
        const { user_id, username, score, duration } = await request.json();
        await DB.prepare("INSERT INTO leaderboard (user_id, username, score, duration) VALUES (?, ?, ?, ?)")
          .bind(user_id, username, score, duration).run();
        return jsonResponse({ success: true });
      }

      // --------------------------
      // 模块 C: 待办事项 (Todos)
      // --------------------------
      if (url.pathname === "/api/todos" && request.method === "GET") {
        const userId = url.searchParams.get("user_id");
        const limitError = await enforceSyncLimit(userId, DB);
        if (limitError) return errorResponse(limitError, 429);

        const { results } = await DB.prepare("SELECT * FROM todos WHERE user_id = ? ORDER BY created_at DESC").bind(userId).all();
        return jsonResponse(results.map(t => ({ ...t, client_updated_at: t.updated_at })));
      }

      if (url.pathname === "/api/todos" && request.method === "POST") {
        const { id, user_id, content, is_completed, client_updated_at, updated_at, due_date, created_date } = await request.json();
        const limitError = await enforceSyncLimit(user_id, DB);
        if (limitError) return errorResponse(limitError, 429);

        const rawTime = client_updated_at || updated_at || new Date().toISOString();
        const incomingTime = getTimeMs(rawTime);
        const completedVal = is_completed ? 1 : 0;

        // 🚀 双向兼容查询：优先查 ID，没有再查内容（兼容老数据）
        let existing = null;
        if (id) existing = await DB.prepare("SELECT * FROM todos WHERE id = ?").bind(id).first();
        if (!existing && content) existing = await DB.prepare("SELECT * FROM todos WHERE user_id = ? AND content = ?").bind(user_id, content).first();

        if (existing) {
         const existingTime = getTimeMs(existing.updated_at);
         if (incomingTime > existingTime) {
           const existingDueDate = existing.due_date || null;
           const newDueDate = due_date || null;
           const stateChanged =
             existing.content !== content || // 允许修改待办文字
             existing.is_completed !== completedVal ||
             existing.is_deleted !== 0 ||
             existingDueDate !== newDueDate;

           if (stateChanged) {
             await DB.prepare("UPDATE todos SET content = ?, is_completed = ?, updated_at = ?, is_deleted = 0, due_date = ?, created_date = ? WHERE id = ?")
              .bind(content, completedVal, rawTime, newDueDate, created_date || null, existing.id).run();
           }
         }
        } else {
         // 不强制绑定 ID（留空让 DB 自动分配），防止 SQLite ID 类型冲突
         await DB.prepare("INSERT INTO todos (user_id, content, is_completed, updated_at, is_deleted, due_date, created_date) VALUES (?, ?, ?, ?, 0, ?, ?)")
           .bind(user_id, content, completedVal, rawTime, due_date || null, created_date || null).run();
        }
        return jsonResponse({ success: true });
      }

      if (url.pathname === "/api/todos/toggle" && request.method === "POST") {
        const { id, is_completed, client_updated_at, updated_at } = await request.json();
        const rawTime = client_updated_at || updated_at || new Date().toISOString();
        const incomingTime = getTimeMs(rawTime);

        const existing = await DB.prepare("SELECT * FROM todos WHERE id = ?").bind(id).first();
        if (existing) {
          if (incomingTime > getTimeMs(existing.updated_at)) {
            await DB.prepare("UPDATE todos SET is_completed = ?, updated_at = ? WHERE id = ?")
             .bind(is_completed ? 1 : 0, rawTime, id).run();
          }
        }
        return jsonResponse({ success: true });
      }

      if (url.pathname === "/api/todos" && request.method === "DELETE") {
        const { id, client_updated_at, updated_at } = await request.json();
        const rawTime = client_updated_at || updated_at || new Date().toISOString();
        const incomingTime = getTimeMs(rawTime);

        const existing = await DB.prepare("SELECT * FROM todos WHERE id = ?").bind(id).first();
        if (existing) {
          if (incomingTime > getTimeMs(existing.updated_at)) {
            await DB.prepare("UPDATE todos SET is_deleted = 1, updated_at = ? WHERE id = ?")
             .bind(rawTime, id).run();
          }
        }
        return jsonResponse({ success: true });
      }

      // --------------------------
      // 模块 D: 倒计时 (Countdowns)
      // --------------------------
      if (url.pathname === "/api/countdowns" && request.method === "GET") {
        const userId = url.searchParams.get("user_id");
        const limitError = await enforceSyncLimit(userId, DB);
        if (limitError) return errorResponse(limitError, 429);

        const { results } = await DB.prepare("SELECT * FROM countdowns WHERE user_id = ?").bind(userId).all();
        return jsonResponse(results.map(c => ({ ...c, client_updated_at: c.updated_at })));
      }

      if (url.pathname === "/api/countdowns" && request.method === "POST") {
        const { id, user_id, title, target_time, client_updated_at, updated_at } = await request.json();
        const limitError = await enforceSyncLimit(user_id, DB);
        if (limitError) return errorResponse(limitError, 429);

        const rawTime = client_updated_at || updated_at || new Date().toISOString();
        const incomingTime = getTimeMs(rawTime);

        let existing = null;
        if (id) existing = await DB.prepare("SELECT * FROM countdowns WHERE id = ?").bind(id).first();
        if (!existing && title) existing = await DB.prepare("SELECT * FROM countdowns WHERE user_id = ? AND title = ?").bind(user_id, title).first();

        if (existing) {
          const existingTime = getTimeMs(existing.updated_at);
          if (incomingTime > existingTime) {
            const stateChanged = existing.title !== title || existing.target_time !== target_time || existing.is_deleted !== 0;
            if (stateChanged) {
              await DB.prepare("UPDATE countdowns SET title = ?, target_time = ?, updated_at = ?, is_deleted = 0 WHERE id = ?")
                .bind(title, target_time, rawTime, existing.id).run();
              return jsonResponse({ success: true, updated: true });
            } else {
              return jsonResponse({ success: true, updated: false });
            }
          }
        } else {
          await DB.prepare("INSERT INTO countdowns (user_id, title, target_time, updated_at, is_deleted) VALUES (?, ?, ?, ?, 0)")
            .bind(user_id, title, target_time, rawTime).run();
          return jsonResponse({ success: true, updated: true });
        }
      }

      if (url.pathname === "/api/countdowns" && request.method === "DELETE") {
        const { id, client_updated_at, updated_at } = await request.json();
        const rawTime = client_updated_at || updated_at || new Date().toISOString();

        const existing = await DB.prepare("SELECT * FROM countdowns WHERE id = ?").bind(id).first();
        if (existing) {
          if (getTimeMs(rawTime) > getTimeMs(existing.updated_at)) {
            await DB.prepare("UPDATE countdowns SET is_deleted = 1, updated_at = ? WHERE id = ?")
              .bind(rawTime, id).run();
          }
        }
        return jsonResponse({ success: true });
      }

      // --------------------------
      // 模块 E: 屏幕使用时间 (Screen Time)
      // --------------------------
      if (url.pathname === "/api/screen_time" && request.method === "POST") {
        const body = await request.json();
        let { user_id, device_name, record_date, apps } = body;

        if (!user_id || !device_name || !record_date || !Array.isArray(apps)) return errorResponse("参数错误");

        const limitError = await enforceSyncLimit(user_id, DB);
        if (limitError) return errorResponse(limitError, 429);

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
        const userId = url.searchParams.get("user_id");
        const date = url.searchParams.get("date");
        if (!userId || !date) return errorResponse("缺少参数");

        const limitError = await enforceSyncLimit(userId, DB);
        if (limitError) return errorResponse(limitError, 429);

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
      // 模块 F: 映射与调试
      // --------------------------
      if (url.pathname === "/api/mappings" && request.method === "GET") {
        const { results } = await DB.prepare(`SELECT package_name, mapped_name, category FROM app_name_mappings`).all();
        return jsonResponse(results);
      }

      if (url.pathname === "/api/debug/reset_database" && request.method === "POST") {
        try {
          await DB.batch([
            DB.prepare("DELETE FROM courses"),
            DB.prepare("DELETE FROM screen_time_logs"),
            DB.prepare("DELETE FROM countdowns"),
            DB.prepare("DELETE FROM todos"),
            DB.prepare("DELETE FROM leaderboard"),
            DB.prepare("DELETE FROM pending_registrations"),
            DB.prepare("DELETE FROM users"),
            DB.prepare("DELETE FROM sqlite_sequence WHERE name IN ('users', 'todos', 'countdowns', 'leaderboard', 'screen_time_logs', 'courses')")
          ]);
          return jsonResponse({ success: true, message: "数据库已完全重置" });
        } catch (e) {
          return errorResponse("重置失败", 500);
        }
      }

      // --------------------------
      // 🚀 模块 G: 全局聚合同步 (Sync All)
      // --------------------------
      if (url.pathname === "/api/sync_all" && request.method === "GET") {
        const userId = url.searchParams.get("user_id");
        if (!userId) return errorResponse("缺少 user_id");

        const limitError = await enforceSyncLimit(userId, DB);
        if (limitError) return errorResponse(limitError, 429);

        const todosRes = await DB.prepare("SELECT * FROM todos WHERE user_id = ? ORDER BY created_at DESC").bind(userId).all();
        const countdownsRes = await DB.prepare("SELECT * FROM countdowns WHERE user_id = ?").bind(userId).all();

        const userRow = await DB.prepare("SELECT tier FROM users WHERE id = ?").bind(userId).first();
        const tier = userRow ? userRow.tier : 'free';
        const sync_limit = SYNC_LIMITS[tier] || SYNC_LIMITS.free;

        const today = new Date().toISOString().split('T')[0];
        const record = await DB.prepare("SELECT sync_count FROM sync_limits WHERE user_id = ? AND sync_date = ?").bind(userId, today).first();
        const sync_count = record ? record.sync_count : 0;

        return jsonResponse({
          success: true,
          tier: tier,
          sync_count: sync_count,
          sync_limit: sync_limit,
          data: {
            todos: todosRes.results.map(t => ({ ...t, client_updated_at: t.updated_at })),
            countdowns: countdownsRes.results.map(c => ({ ...c, client_updated_at: c.updated_at }))
          }
        });
      }

      if (url.pathname === "/api/sync_all" && request.method === "POST") {
        const { user_id, todos, countdowns, screen_time } = await request.json();
        if (!user_id) return errorResponse("缺少 user_id");

        const limitError = await enforceSyncLimit(user_id, DB);
        if (limitError) return errorResponse(limitError, 429);

        // 1. 批量处理 Todos 🛡️（完美支持基于 ID 合并及改名）
        if (Array.isArray(todos)) {
          for (const t of todos) {
            const rawTime = t.client_updated_at || t.updated_at || new Date().toISOString();
            const incomingTime = getTimeMs(rawTime);

            const completedVal = t.is_completed ? 1 : 0;
            const deletedVal = t.is_deleted ? 1 : 0;
            const newDueDate = t.due_date || null;

            let existing = null;
            if (t.id) existing = await DB.prepare("SELECT * FROM todos WHERE id = ?").bind(t.id).first();
            if (!existing && t.content) existing = await DB.prepare("SELECT * FROM todos WHERE user_id = ? AND content = ?").bind(user_id, t.content).first();

            if (existing) {
              const existingTime = getTimeMs(existing.updated_at);
              if (incomingTime > existingTime) {
                const existingDueDate = existing.due_date || null;
                const stateChanged =
                  existing.content !== t.content ||
                  existing.is_completed !== completedVal ||
                  existing.is_deleted !== deletedVal ||
                  existingDueDate !== newDueDate;

                if (stateChanged) {
                  await DB.prepare("UPDATE todos SET content = ?, is_completed = ?, updated_at = ?, is_deleted = ?, due_date = ?, created_date = ? WHERE id = ?")
                    .bind(t.content, completedVal, rawTime, deletedVal, newDueDate, t.created_date || null, existing.id).run();
                }
              }
            } else {
              await DB.prepare("INSERT INTO todos (user_id, content, is_completed, updated_at, is_deleted, due_date, created_date) VALUES (?, ?, ?, ?, ?, ?, ?)")
                .bind(user_id, t.content, completedVal, rawTime, deletedVal, newDueDate, t.created_date || null).run();
            }
          }
        }

        // 2. 批量处理 Countdowns 🛡️
        if (Array.isArray(countdowns)) {
          for (const c of countdowns) {
            const rawTime = c.client_updated_at || c.updated_at || new Date().toISOString();
            const incomingTime = getTimeMs(rawTime);
            const deletedVal = c.is_deleted ? 1 : 0;

            let existing = null;
            if (c.id) existing = await DB.prepare("SELECT * FROM countdowns WHERE id = ?").bind(c.id).first();
            if (!existing && c.title) existing = await DB.prepare("SELECT * FROM countdowns WHERE user_id = ? AND title = ?").bind(user_id, c.title).first();

            if (existing) {
              const existingTime = getTimeMs(existing.updated_at);
              if (incomingTime > existingTime) {
                const stateChanged = existing.title !== c.title || existing.target_time !== c.target_time || existing.is_deleted !== deletedVal;
                if (stateChanged) {
                  await DB.prepare("UPDATE countdowns SET title = ?, target_time = ?, updated_at = ?, is_deleted = ? WHERE id = ?")
                    .bind(c.title, c.target_time, rawTime, deletedVal, existing.id).run();
                }
              }
            } else {
              await DB.prepare("INSERT INTO countdowns (user_id, title, target_time, updated_at, is_deleted) VALUES (?, ?, ?, ?, ?)")
                .bind(user_id, c.title, c.target_time, rawTime, deletedVal).run();
            }
          }
        }

        // 3. 批量处理 Screen Time
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

        const userRow = await DB.prepare("SELECT tier FROM users WHERE id = ?").bind(user_id).first();
        const tier = userRow ? userRow.tier : 'free';
        const sync_limit = SYNC_LIMITS[tier] || SYNC_LIMITS.free;

        const today = new Date().toISOString().split('T')[0];
        const record = await DB.prepare("SELECT sync_count FROM sync_limits WHERE user_id = ? AND sync_date = ?").bind(user_id, today).first();
        const sync_count = record ? record.sync_count : 1;

        const todosRes = await DB.prepare("SELECT * FROM todos WHERE user_id = ? ORDER BY created_at DESC").bind(user_id).all();
        const countdownsRes = await DB.prepare("SELECT * FROM countdowns WHERE user_id = ?").bind(user_id).all();

        return jsonResponse({
          success: true,
          message: "聚合同步完成",
          tier: tier,
          sync_count: sync_count,
          sync_limit: sync_limit,
          data: {
            todos: todosRes.results.map(t => ({ ...t, client_updated_at: t.updated_at })),
            countdowns: countdownsRes.results.map(c => ({ ...c, client_updated_at: c.updated_at }))
          }
        });
      }

      // --------------------------
      // 模块 H: 课程表 (Courses)
      // --------------------------
      if (url.pathname === "/api/courses" && request.method === "GET") {
        const userId = url.searchParams.get("user_id");
        const semester = url.searchParams.get("semester") || "default";
        if (!userId) return errorResponse("缺少 user_id");

        const { results } = await DB.prepare(`
          SELECT * FROM courses WHERE user_id = ? AND semester = ? AND is_deleted = 0 ORDER BY week_index, weekday, start_time
        `).bind(userId, semester).all();
        return jsonResponse(results);
      }

      if (url.pathname === "/api/courses" && request.method === "POST") {
        const { user_id, courses, semester = "default" } = await request.json();
        if (!user_id || !Array.isArray(courses)) return errorResponse("参数错误");

        const limitError = await enforceSyncLimit(user_id, DB);
        if (limitError) return errorResponse(limitError, 429);

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
 * 🚀 核心同步频率检查逻辑 (带有 10 秒聚合机制 & 分级限制)
 */
async function enforceSyncLimit(userId, DB) {
  if (!userId) return null;
  const today = new Date().toISOString().split('T')[0];
  const now = Date.now();

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
    if (now - lastSyncTime < 10000) {
      await DB.prepare("UPDATE sync_limits SET last_sync_time = ? WHERE user_id = ?").bind(now, userId).run();
      return null;
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
