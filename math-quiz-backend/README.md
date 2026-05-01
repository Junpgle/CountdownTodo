# math-quiz-backend — Cloudflare Workers 后端

## 📌 项目概述

本项目是 CountDownTodo 的云端数据中心，基于 Cloudflare Workers 平台构建。负责用户认证、增量数据同步（Delta Sync）、API 路由管理等核心逻辑。

---

## 🏗️ 技术架构

- **运行环境**: Cloudflare Workers
- **存储引擎**: Cloudflare D1 (SQLite-based) / KV (可选)
- **部署工具**: Wrangler
- **语言**: JavaScript (ES6+)

---

## 📂 目录结构

```
math-quiz-backend/
├── src/
│   └── index.js              # 核心 API 逻辑 & 路由
├── wrangler.toml             # Cloudflare 部署配置 (D1 绑定、环境变量)
├── package.json              # 依赖管理
└── vitest.config.js          # 测试配置
```

---

## 🚀 核心 API 接口

| 端点 | 方法 | 职责 |
|------|------|------|
| `/api/register` | POST | 用户注册 |
| `/api/login` | POST | 用户登录 (返回 Bearer Token) |
| `/api/sync` | POST | **核心增量同步**: 处理 Todos, Countdowns, TimeLogs |
| `/api/screentime` | POST/GET | 屏幕时间上传与查询 |
| `/api/pomodoro/tags` | POST/GET | 番茄钟标签同步 |
| `/api/pomodoro/record`| POST/GET | 番茄钟专注记录上传 |

---

## 🛠️ 部署指南

### 环境准备

1. 安装 NodeJS
2. 登录 Cloudflare: `npx wrangler login`

### 本地开发

```bash
npm install
npx wrangler dev
```

### 部署到生产环境

```bash
npx wrangler deploy
```

---

## 🔄 同步逻辑摘要 (Delta Sync)

后端实现了 **LWW (Last Write Wins)** 增量同步策略：
1. 接收客户端上传的变更列表。
2. 对比数据库中的 `version` 和 `updatedAt`。
3. 如果客户端数据更新，则覆盖数据库；否则忽略。
4. 返回数据库中自 `lastSyncTime` 以来发生的所有变更给客户端。

---

*最后更新：2026-04-13*
