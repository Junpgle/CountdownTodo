/**
 * Math Quiz App Backend - Cloudflare Worker
 * 功能：用户认证、排行榜、待办事项(LWW同步)、倒计时(LWW同步)、屏幕时间同步(含分类映射)
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
      // 模块 C: 待办事项 (支持软删除)
      // --------------------------

      if (url.pathname === "/api/todos" && request.method === "GET") {
        const userId = url.searchParams.get("user_id");
        // 去掉 is_deleted = 0 过滤，允许前端同步删除标记
        const { results } = await DB.prepare("SELECT * FROM todos WHERE user_id = ? ORDER BY created_at DESC").bind(userId).all();
        return jsonResponse(results);
      }

      if (url.pathname === "/api/todos" && request.method === "POST") {
        const { user_id, content, client_updated_at } = await request.json();
        const timestamp = client_updated_at || Date.now();
        await DB.prepare(`
          INSERT INTO todos (user_id, content, is_completed, updated_at, is_deleted)
          VALUES (?, ?, 0, ?, 0)
          ON CONFLICT(user_id, content) DO UPDATE SET
            is_deleted = 0,
            updated_at = excluded.updated_at
          WHERE excluded.updated_at > todos.updated_at
        `).bind(user_id, content, timestamp).run();
        return jsonResponse({ success: true });
      }

      if (url.pathname === "/api/todos/toggle" && request.method === "POST") {
        const { id, is_completed } = await request.json();
        await DB.prepare("UPDATE todos SET is_completed = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?").bind(is_completed ? 1 : 0, id).run();
        return jsonResponse({ success: true });
      }

      if (url.pathname === "/api/todos" && request.method === "DELETE") {
        const { id } = await request.json();
        await DB.prepare("UPDATE todos SET is_deleted = 1, updated_at = CURRENT_TIMESTAMP WHERE id = ?").bind(id).run();
        return jsonResponse({ success: true });
      }

      // --------------------------
      // 模块 D: 倒计时 (LWW 同步逻辑)
      // --------------------------

      if (url.pathname === "/api/countdowns" && request.method === "GET") {
        const userId = url.searchParams.get("user_id");
        // 去掉 is_deleted = 0 过滤，允许前端同步删除标记
        const { results } = await DB.prepare("SELECT * FROM countdowns WHERE user_id = ?").bind(userId).all();
        return jsonResponse(results);
      }

      if (url.pathname === "/api/countdowns" && request.method === "POST") {
        const { user_id, title, target_time, client_updated_at } = await request.json();
        const timestamp = client_updated_at || Date.now();

        // UPSERT 逻辑：只有当客户端提供的时间戳大于云端时才更新
        const info = await DB.prepare(`
          INSERT INTO countdowns (user_id, title, target_time, updated_at, is_deleted)
          VALUES (?, ?, ?, ?, 0)
          ON CONFLICT(user_id, title) DO UPDATE SET
            target_time = excluded.target_time,
            updated_at = excluded.updated_at,
            is_deleted = 0
          WHERE excluded.updated_at > countdowns.updated_at
        `).bind(user_id, title, target_time, timestamp).run();

        return jsonResponse({ success: true, updated: info.meta.changes > 0 });
      }

      if (url.pathname === "/api/countdowns" && request.method === "DELETE") {
        const { id, client_updated_at } = await request.json();
        const timestamp = client_updated_at || Date.now();
        await DB.prepare("UPDATE countdowns SET is_deleted = 1, updated_at = ? WHERE id = ?").bind(timestamp, id).run();
        return jsonResponse({ success: true });
      }


      // --------------------------
      // 模块 E: 屏幕使用时间 (Screen Time)
      // --------------------------

      // [POST] 上报某设备在某一天的屏幕时间
      if (url.pathname === "/api/screen_time" && request.method === "POST") {
        const body = await request.json();
        let { user_id, device_name, record_date, apps } = body;

        // 基础校验
        if (!user_id || !device_name || !record_date || !Array.isArray(apps)) {
          return errorResponse("缺少必要参数或格式错误 (需包含 user_id, device_name, record_date, apps[])");
        }

        // 数据清洗：去除前后空格
        device_name = device_name.trim();

        try {
          // 使用 D1 Batch 批量处理以提高性能 (SQLite UPSERT 语法)
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

      // [GET] 获取今日汇总数据
      if (url.pathname === "/api/screen_time" && request.method === "GET") {
        const userId = url.searchParams.get("user_id");
        const date = url.searchParams.get("date");
        if (!userId || !date) return errorResponse("缺少参数 user_id 或 date");

        // 核心修改：关联 app_name_mappings 表，并同时拉取 category（分类）字段
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

      // [GET] 获取全局应用分类映射表 (供客户端每7天缓存一次)
      if (url.pathname === "/api/mappings" && request.method === "GET") {
        const { results } = await DB.prepare(`SELECT package_name, mapped_name, category FROM app_name_mappings`).all();
        return jsonResponse(results);
      }

      // --------------------------
      // 模块 F: 调试与维护 (Debug)
      // --------------------------

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

async function hashPassword(password) {
  const msgUint8 = new TextEncoder().encode(password);
  const hashBuffer = await crypto.subtle.digest("SHA-256", msgUint8);
  return Array.from(new Uint8Array(hashBuffer)).map(b => b.toString(16).padStart(2, "0")).join("");
}
