# Cloudflare Turnstile 人机验证

实现版本：v4.16
最后更新：2026-06-14

## 概述

登录和注册流程集成 Cloudflare Turnstile 人机验证。Turnstile 是 Cloudflare 提供的无感验证替代方案，用户无需手动点击验证框即可完成验证。

## 架构

```
┌─────────────────┐     Turnstile Token      ┌──────────────────┐
│  客户端 (Flutter) │  ──────────────────────>  │  后端 (Express)   │
│  TurnstileWidget │                          │  /api/auth/login  │
│  (WebView)       │  <──────────────────────  │  /api/auth/register│
│                  │     Session Token         │                  │
└────────┬────────┘                          └────────┬─────────┘
         │                                            │
         │  WebView 加载                               │  POST 验证
         │  /turnstile 页面                            │  challenges.cloudflare.com
         │                                            │
         ▼                                            ▼
┌─────────────────┐                          ┌──────────────────┐
│  assets/turnstile │                        │  Cloudflare API   │
│  /turnstile.html  │                        │  /turnstile/v0/   │
└─────────────────┘                          │  siteverify       │
                                             └──────────────────┘
```

## 客户端集成

### Flutter 端

- 组件：`lib/widgets/turnstile_verification_widget.dart`
- 使用 `WebView` 加载后端 `/turnstile` 页面（`assets/turnstile/turnstile.html`）
- 通过 `TurnstileChannel` JS bridge 通信：
  - `pageLoaded` — 页面就绪
  - `rendered` — Turnstile 渲染完成
  - `success` — 验证成功，携带 token
  - `expired` — token 过期
  - `error` — 验证出错
- 15 秒加载超时（覆盖页面加载 + 脚本加载 + Turnstile 渲染，不包含用户交互时间）
- 支持深色模式切换、禁用状态、自定义高度

### Web 端

- 组件：`webpage/web/src/components/TurnstileWidget.tsx`
- 直接加载 Turnstile JS API（`https://challenges.cloudflare.com/turnstile/v0/api.js`），不使用 WebView
- 通过 `useImperativeHandle` 暴露 `reset()` 方法
- 处理 React StrictMode 重复挂载

### 支持的 action

- `login` — 登录验证（高度 130px）
- `register` — 注册验证（高度 150px）

## 环境配置

通过 `EnvironmentService` 管理：

| 参数 | 环境变量 | 默认值 | 说明 |
|------|----------|--------|------|
| 生产 Site Key | `TURNSTILE_SITE_KEY` | `0x4AAAAAADkYYUiQdEWVhVYh` | 生产环境 key |
| 测试 Site Key | `TURNSTILE_TEST_SITE_KEY` | `1x00000000000000000000AA` | Cloudflare 官方测试 key |
| 验证页面 URL | `TURNSTILE_VERIFY_PAGE_URL` | `""`（自动拼接） | 自定义后端验证页面地址 |

- Debug 包（包名以 `.debug` 结尾）自动使用测试 key
- 验证页面 URL 默认取当前后端地址 + `/turnstile`；可显式配置覆盖

## 后端验证

后端收到 `turnstile_token` 后，POST 到 Cloudflare 验证接口：

```
POST https://challenges.cloudflare.com/turnstile/v0/siteverify
Body: secret=<SECRET_KEY>&response=<turnstile_token>
```

验证通过后继续执行登录/注册逻辑；失败则返回验证错误。

## 邮箱验证码注册/找回密码

与 Turnstile 配合使用的邮箱验证流程：

### 注册流程（两步）

1. **填写表单 + 人机验证**：用户填写邮箱、用户名、密码，完成 Turnstile 验证，点击"获取验证码"
2. **输入验证码**：6 位邮箱验证码输入界面，验证通过后自动完成注册

### 找回密码流程（三步）

1. **输入邮箱 + 人机验证**：填写注册邮箱，完成 Turnstile 验证
2. **输入验证码**：6 位邮箱验证码
3. **设置新密码**：输入新密码并确认

### API 端点

| 功能 | 端点 |
|------|------|
| 注册 | `POST /api/auth/register` |
| 登录 | `POST /api/auth/login` |
| 找回密码 | `POST /api/auth/forgot_password` |
| 重置密码 | `POST /api/auth/reset_password` |

### 状态重置

- 验证失败或 token 过期时，Turnstile 组件自动重置
- 退出登录或登录失败后清除 `_turnstileToken`，强制下次重新验证
- 通过递增 `_turnstileKey` 强制重新创建 WebView 组件

## 兼容期

- 过渡期内服务端同时接受含 token 和不含 token 的请求
- 过渡期后缺少 token 的请求将被拒绝
- 客户端 Token 过期时自动重置 Turnstile 组件，重新验证

## Cloudflare 服务器停用

- Cloudflare Worker 后端已于 **2026-06-01** 停用
- 登录页自动检测：若用户选择 Cloudflare 服务器，弹出停用提示并强制切换到 Alibaba Cloud
- Web 端服务器选择器中的 Cloudflare 按钮已禁用，标注"已停用"
- Web 端 API 默认使用 Alibaba Cloud

## 相关文件

- `lib/widgets/turnstile_verification_widget.dart` — Flutter 端 Turnstile WebView 组件
- `lib/services/environment_service.dart` — 环境配置和 key 选择
- `lib/screens/login_screen.dart` — 登录/注册页面集成
- `assets/turnstile/turnstile.html` — Turnstile 渲染页面
- `webpage/web/src/components/TurnstileWidget.tsx` — Web 端 Turnstile 组件
- `webpage/web/src/pages/AuthScreen.tsx` — Web 端登录/注册页面
