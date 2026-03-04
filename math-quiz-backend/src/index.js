/**
 * Math Quiz App Backend - Cloudflare Worker
 * 功能：用户认证、排行榜、待办事项(LWW同步)、倒计时(LWW同步)、屏幕时间同步(含分类映射)、修改密码、同步频率限制
 */

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
      // === 0. 关键环境检查 ===
      if (!env.math_quiz_db) {
        throw new Error(`数据库绑定失败！代码中找不到 env.math_quiz_db。请确保 wrangler.toml 中配置了 [[d1_databases]] binding = "math_quiz_db"`);
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
            const now = Date.now();
            if (now - createdTime > 15 * 60 * 1000) return errorResponse("验证码已过期，请重新获取");

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
        return jsonResponse({ success: true, user: { id: user.id, username: user.username, email: user.email, avatar_url: user.avatar_url } });
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

      // --------------------------
      // 模块 B: 排行榜 (Leaderboard)
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
      // 模块 C: 待办事项 (支持软删除与新属性)
      // --------------------------

      if (url.pathname === "/api/todos" && request.method === "GET") {
        const userId = url.searchParams.get("user_id");

        // 🚀 拦截检查
        const limitError = await enforceSyncLimit(userId, DB);
        if (limitError) return errorResponse(limitError, 429);

        const { results } = await DB.prepare("SELECT * FROM todos WHERE user_id = ? ORDER BY created_at DESC").bind(userId).all();
        return jsonResponse(results);
      }

      if (url.pathname === "/api/todos" && request.method === "POST") {
        const { user_id, content, is_completed, client_updated_at, due_date, created_date } = await request.json();

        // 🚀 拦截检查
        const limitError = await enforceSyncLimit(user_id, DB);
        if (limitError) return errorResponse(limitError, 429);

        const timestamp = client_updated_at || Date.now();
        const completedVal = is_completed ? 1 : 0;

        const existing = await DB.prepare("SELECT * FROM todos WHERE user_id = ? AND content = ?").bind(user_id, content).first();

        if (existing) {
         const existingTime = parseInt(existing.updated_at) || 0;
         if (timestamp > existingTime) {
           await DB.prepare("UPDATE todos SET is_completed = ?, updated_at = ?, is_deleted = 0, due_date = ?, created_date = ? WHERE id = ?")
            .bind(completedVal, timestamp, due_date || null, created_date || null, existing.id).run();
         }
        } else {
         await DB.prepare("INSERT INTO todos (user_id, content, is_completed, updated_at, is_deleted, due_date, created_date) VALUES (?, ?, ?, ?, 0, ?, ?)")
           .bind(user_id, content, completedVal, timestamp, due_date || null, created_date || null).run();
        }
        return jsonResponse({ success: true });
      }

      if (url.pathname === "/api/todos/toggle" && request.method === "POST") {
        const { id, is_completed } = await request.json();
        await DB.prepare("UPDATE todos SET is_completed = ?, updated_at = ? WHERE id = ?")
         .bind(is_completed ? 1 : 0, Date.now(), id).run();
        return jsonResponse({ success: true });
      }

      if (url.pathname === "/api/todos" && request.method === "DELETE") {
        const { id } = await request.json();
        await DB.prepare("UPDATE todos SET is_deleted = 1, updated_at = ? WHERE id = ?")
         .bind(Date.now(), id).run();
        return jsonResponse({ success: true });
      }

      // --------------------------
      // 模块 D: 倒计时 (LWW 同步逻辑)
      // --------------------------

      if (url.pathname === "/api/countdowns" && request.method === "GET") {
        const userId = url.searchParams.get("user_id");

        // 🚀 拦截检查
        const limitError = await enforceSyncLimit(userId, DB);
        if (limitError) return errorResponse(limitError, 429);

        const { results } = await DB.prepare("SELECT * FROM countdowns WHERE user_id = ?").bind(userId).all();
        return jsonResponse(results);
      }

      if (url.pathname === "/api/countdowns" && request.method === "POST") {
        const { user_id, title, target_time, client_updated_at } = await request.json();

        // 🚀 拦截检查
        const limitError = await enforceSyncLimit(user_id, DB);
        if (limitError) return errorResponse(limitError, 429);

        const timestamp = client_updated_at || Date.now();

        const existing = await DB.prepare("SELECT * FROM countdowns WHERE user_id = ? AND title = ?").bind(user_id, title).first();

        if (existing) {
          const existingTime = parseInt(existing.updated_at) || 0;
          if (timestamp > existingTime) {
            await DB.prepare("UPDATE countdowns SET target_time = ?, updated_at = ?, is_deleted = 0 WHERE id = ?")
              .bind(target_time, timestamp, existing.id).run();
            return jsonResponse({ success: true, updated: true });
          } else {
            return jsonResponse({ success: true, updated: false });
          }
        } else {
          await DB.prepare("INSERT INTO countdowns (user_id, title, target_time, updated_at, is_deleted) VALUES (?, ?, ?, ?, 0)")
            .bind(user_id, title, target_time, timestamp).run();
          return jsonResponse({ success: true, updated: true });
        }
      }

      if (url.pathname === "/api/countdowns" && request.method === "DELETE") {
        const { id, client_updated_at } = await request.json();
        const timestamp = client_updated_at || Date.now();
        await DB.prepare("UPDATE countdowns SET is_deleted = 1, updated_at = ? WHERE id = ?")
          .bind(timestamp, id).run();
        return jsonResponse({ success: true });
      }


      // --------------------------
      // 模块 E: 屏幕使用时间 (Screen Time)
      // --------------------------

      if (url.pathname === "/api/screen_time" && request.method === "POST") {
        const body = await request.json();
        let { user_id, device_name, record_date, apps } = body;

        if (!user_id || !device_name || !record_date || !Array.isArray(apps)) {
          return errorResponse("缺少必要参数或格式错误 (需包含 user_id, device_name, record_date, apps[])");
        }

        // 🚀 拦截检查
        const limitError = await enforceSyncLimit(user_id, DB);
        if (limitError) return errorResponse(limitError, 429);

        device_name = device_name.trim();

        try {
          const statements = apps.map(app => {
           return DB.prepare(`
             INSERT INTO screen_time_logs (user_id, device_name, record_date, app_name, duration)
             VALUES (?, ?, ?, ?, ?)
             ON CONFLICT(user_id, device_name, record_date, app_name)
             DO UPDATE SET
              duration = excluded.duration,
              updated_at = CURRENT_TIMESTAMP
           `).bind(user_id, device_name, record_date, app.app_name, app.duration);
          });

          await DB.batch(statements);

          return jsonResponse({
           success: true,
           received_device: device_name,
           message: `已同步来自设备 [${device_name}] 的 ${apps.length} 条记录`
          });
        } catch (e) {
          return errorResponse("数据库更新失败: " + e.message, 500);
        }
      }

      if (url.pathname === "/api/screen_time" && request.method === "GET") {
        const userId = url.searchParams.get("user_id");
        const date = url.searchParams.get("date");
        if (!userId || !date) return errorResponse("缺少参数 user_id 或 date");

        // 🚀 拦截检查
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
            DB.prepare("DELETE FROM screen_time_logs"),
            DB.prepare("DELETE FROM countdowns"),
            DB.prepare("DELETE FROM todos"),
            DB.prepare("DELETE FROM leaderboard"),
            DB.prepare("DELETE FROM pending_registrations"),
            DB.prepare("DELETE FROM users"),
            DB.prepare("DELETE FROM sqlite_sequence WHERE name IN ('users', 'todos', 'countdowns', 'leaderboard', 'screen_time_logs')")
          ]);
          return jsonResponse({ success: true, message: "数据库已完全重置" });
        } catch (e) {
          return errorResponse("重置失败: " + e.message, 500);
        }
      }

      // 默认 404
      return errorResponse("API Endpoint Not Found", 404);

    } catch (e) {
      return errorResponse(`Server Error: ${e.message}`, 500);
    }
  },
};

/**
 * 🚀 新增：核心同步频率检查逻辑 (带有 10 秒聚合机制)
 */
async function enforceSyncLimit(userId, DB) {
  if (!userId) return null; // 未登录时不限制

  const today = new Date().toISOString().split('T')[0];
  const now = Date.now();
  const MAX_SYNCS = 100; // 每天最大同步次数，你可以自行修改

  try {
    const record = await DB.prepare("SELECT * FROM sync_limits WHERE user_id = ?").bind(userId).first();

    // 如果今天没有记录，初始化为 1
    if (!record || record.sync_date !== today) {
      await DB.prepare("INSERT OR REPLACE INTO sync_limits (user_id, sync_date, sync_count, last_sync_time) VALUES (?, ?, ?, ?)")
        .bind(userId, today, 1, now).run();
      return null;
    }

    const lastSyncTime = parseInt(record.last_sync_time) || 0;

    // 💡 智能聚合：如果距离上一个接口调用不到 10 秒，算作“同一批次”同步，不扣除次数！
    // 这样就不会因为 App 一次性发起 3 个请求（待办、倒计时、屏幕时间）而扣 3 次了。
    if (now - lastSyncTime < 10000) {
      await DB.prepare("UPDATE sync_limits SET last_sync_time = ? WHERE user_id = ?").bind(now, userId).run();
      return null;
    }

    // 检查是否超过上限
    if (record.sync_count >= MAX_SYNCS) {
      return `今日同步次数已达上限 (${MAX_SYNCS}次)，为保护服务器资源，请明天再试。`;
    }

    // 正常增加计数
    await DB.prepare("UPDATE sync_limits SET sync_count = sync_count + 1, last_sync_time = ? WHERE user_id = ?")
      .bind(now, userId).run();

    return null; // 允许通过

  } catch (e) {
    // 防御性编程：如果你还没在数据库里建 sync_limits 表，捕捉到错误直接放行，不影响主流程！
    if (e.message.includes("no such table")) return null;
    console.error("Sync limit logic error:", e);
    return null;
  }
}

async function hashPassword(password) {
  const msgUint8 = new TextEncoder().encode(password);
  const hashBuffer = await crypto.subtle.digest("SHA-256", msgUint8);
  return Array.from(new Uint8Array(hashBuffer)).map(b => b.toString(16).padStart(2, "0")).join("");
}
