/**
 * Math Quiz App Backend - Cloudflare Worker
 * 包含：用户认证(含邮件验证)、排行榜、待办事项、倒计时管理
 */

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // === 1. CORS 设置 ===
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
      // 修正：这里检查 env.math_quiz_db 而不是 env.DB
      if (!env.math_quiz_db) {
        throw new Error(`数据库绑定失败！代码中找不到 env.math_quiz_db。请确保 wrangler.toml 中配置了 [[d1_databases]] binding = "math_quiz_db"。当前可用变量: ${Object.keys(env).join(', ')}`);
      }

      // 为了简化代码，我们将 env.math_quiz_db 赋值给局部变量 DB
      const DB = env.math_quiz_db;

      // === 2. 路由分发 ===

      // --------------------------
      // 模块 A: 用户认证 (Auth)
      // --------------------------

      // [POST] 注册接口 (整合了发送验证码和验证逻辑)
      // 场景 1: 请求带 code -> 验证验证码并创建账户
      // 场景 2: 请求无 code -> 发送验证码邮件
      if (url.pathname === "/api/auth/register" && request.method === "POST") {
        const body = await request.json();
        const { email, code } = body;

        // === 场景 1: 验证验证码 (完成注册) ===
        if (code) {
            if (!email) return errorResponse("验证需提供邮箱");

            // 1. 查找待验证记录
            const pending = await DB.prepare("SELECT * FROM pending_registrations WHERE email = ?").bind(email).first();

            if (!pending) return errorResponse("验证请求不存在或已过期，请重新注册");

            // 2. 校验验证码 (确保转为字符串比较)
            if (pending.code !== code.toString()) return errorResponse("验证码错误");

            // 3. 校验是否过期 (15 分钟)
            const createdTime = new Date(pending.created_at).getTime();
            const now = Date.now();
            if (now - createdTime > 15 * 60 * 1000) {
               return errorResponse("验证码已过期，请重新获取");
            }

            // 4. 迁移到正式用户表
            try {
              await DB.prepare(
                "INSERT INTO users (username, email, password_hash) VALUES (?, ?, ?)"
              ).bind(pending.username, pending.email, pending.password_hash).run();

              // 5. 删除临时记录
              await DB.prepare("DELETE FROM pending_registrations WHERE email = ?").bind(email).run();

              return jsonResponse({ success: true, message: "注册成功，请登录" });
            } catch (e) {
              // 防止并发情况下重复插入
              if (e.message && e.message.includes("UNIQUE")) {
                 return errorResponse("该邮箱已完成注册，请直接登录");
              }
              throw e;
            }
        }

        // === 场景 2: 申请注册 (发送验证码) ===
        // 如果没有 code，则视为申请注册，需要 username, email, password
        const { username, password } = body;

        if (!username || !email || !password) return errorResponse("缺少必要字段");

        // 检查 API Key 配置
        if (!env.RESEND_API_KEY) {
          return errorResponse("服务端未配置邮件服务 (RESEND_API_KEY is missing)", 500);
        }

        // 1. 检查是否已存在于正式用户表
        const existing = await DB.prepare("SELECT id FROM users WHERE email = ?").bind(email).first();
        if (existing) return errorResponse("该邮箱已被注册，请直接登录");

        // 2. 生成 6 位随机验证码
        const newCode = Math.floor(100000 + Math.random() * 900000).toString();

        // 3. 密码加密
        const passwordHash = await hashPassword(password);

        // 4. 存入临时表 (pending_registrations)
        await DB.prepare(
          "INSERT OR REPLACE INTO pending_registrations (email, username, password_hash, code) VALUES (?, ?, ?, ?)"
        ).bind(email, username, passwordHash, newCode).run();

        // 5. 调用 Resend API 发送邮件
        const resendResponse = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${env.RESEND_API_KEY}`,
            "Content-Type": "application/json"
          },
          body: JSON.stringify({
            from: "Math Quiz <Math&Quiz@junpgle.me>", // 请按需修改发件人
            to: email,
            subject: "验证您的账号 - Math Quiz",
            html: `
              <div style="font-family: sans-serif; padding: 20px;">
                <h2>欢迎注册 Math Quiz!</h2>
                <p>您的验证码是：</p>
                <p style="font-size: 32px; font-weight: bold; letter-spacing: 5px; color: #4F46E5;">${newCode}</p>
                <p>该验证码将在 15 分钟后失效。</p>
              </div>
            `
          })
        });

        if (!resendResponse.ok) {
          const errText = await resendResponse.text();
          console.error("Resend API Error:", errText);
          return errorResponse("验证邮件发送失败，请检查邮箱是否正确");
        }

        return jsonResponse({
          success: true,
          message: "验证码已发送",
          require_verify: true
        });
      }

      // [POST] 登录
      if (url.pathname === "/api/auth/login" && request.method === "POST") {
        const { email, password } = await request.json();

        const user = await DB.prepare("SELECT * FROM users WHERE email = ?").bind(email).first();

        if (!user) return errorResponse("用户不存在", 404);

        const inputHash = await hashPassword(password);
        if (inputHash !== user.password_hash) {
          return errorResponse("密码错误", 401);
        }

        return jsonResponse({
          success: true,
          user: {
            id: user.id,
            username: user.username,
            email: user.email,
            avatar_url: user.avatar_url
          }
        });
      }

      // --------------------------
      // 模块 B: 排行榜 (Leaderboard)
      // --------------------------

      if (url.pathname === "/api/leaderboard" && request.method === "GET") {
        const { results } = await DB.prepare(
          `SELECT username, score, duration, played_at
           FROM leaderboard
           ORDER BY score DESC, duration ASC
           LIMIT 50`
        ).all();
        return jsonResponse(results);
      }

      if (url.pathname === "/api/score" && request.method === "POST") {
        const { user_id, username, score, duration } = await request.json();
        if (!user_id) return errorResponse("未登录");

        await DB.prepare(
          "INSERT INTO leaderboard (user_id, username, score, duration) VALUES (?, ?, ?, ?)"
        ).bind(user_id, username, score, duration).run();

        return jsonResponse({ success: true });
      }

      // --------------------------
      // 模块 C: 待办事项 (Todos)
      // --------------------------

      if (url.pathname === "/api/todos" && request.method === "GET") {
        const userId = url.searchParams.get("user_id");
        if (!userId) return errorResponse("缺少 user_id");

        const { results } = await DB.prepare(
          "SELECT * FROM todos WHERE user_id = ? ORDER BY created_at DESC"
        ).bind(userId).all();

        return jsonResponse(results);
      }

      if (url.pathname === "/api/todos" && request.method === "POST") {
        const { user_id, content } = await request.json();
        if (!user_id || !content) return errorResponse("缺少参数");

        await DB.prepare(
          "INSERT INTO todos (user_id, content, is_completed) VALUES (?, ?, 0)"
        ).bind(user_id, content).run();

        return jsonResponse({ success: true });
      }

      if (url.pathname === "/api/todos/toggle" && request.method === "POST") {
        const { id, is_completed } = await request.json();
        await DB.prepare(
          "UPDATE todos SET is_completed = ? WHERE id = ?"
        ).bind(is_completed ? 1 : 0, id).run();
        return jsonResponse({ success: true });
      }

      if (url.pathname === "/api/todos" && request.method === "DELETE") {
        const { id } = await request.json();
        await DB.prepare("DELETE FROM todos WHERE id = ?").bind(id).run();
        return jsonResponse({ success: true });
      }

      // --------------------------
      // 模块 D: 倒计时 (Countdowns)
      // --------------------------

      if (url.pathname === "/api/countdowns" && request.method === "GET") {
        const userId = url.searchParams.get("user_id");
        if (!userId) return errorResponse("缺少 user_id");
        const { results } = await DB.prepare(
          "SELECT * FROM countdowns WHERE user_id = ? ORDER BY target_time ASC"
        ).bind(userId).all();
        return jsonResponse(results);
      }

      if (url.pathname === "/api/countdowns" && request.method === "POST") {
        const { user_id, title, target_time } = await request.json();
        await DB.prepare(
          "INSERT INTO countdowns (user_id, title, target_time) VALUES (?, ?, ?)"
        ).bind(user_id, title, target_time).run();
        return jsonResponse({ success: true });
      }

      if (url.pathname === "/api/countdowns" && request.method === "DELETE") {
        const { id } = await request.json();
        await DB.prepare("DELETE FROM countdowns WHERE id = ?").bind(id).run();
        return jsonResponse({ success: true });
      }

      return errorResponse("API Endpoint Not Found", 404);

    } catch (e) {
      return errorResponse(`Server Error: ${e.message}`, 500);
    }
  },
};

async function hashPassword(password) {
  const myText = new TextEncoder().encode(password);
  const myDigest = await crypto.subtle.digest({ name: 'SHA-256' }, myText);
  const hashArray = Array.from(new Uint8Array(myDigest));
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
}
