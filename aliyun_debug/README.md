# aliyun/ — 部署脚本与迁移工具

## 📌 目录职责

本目录包含阿里云 ECS 端的原始代码、数据库镜像以及跨云（Aliyun ↔ Cloudflare）的数据同步脚本。

---

## 📂 文件索引

| 文件 | 职责 |
|------|------|
| `server.js` | Express 后端主要逻辑 |
| `new.sql` | 数据库表结构镜像 |
| `master_sync.sh` | 主同步脚本，调度各项数据流 |
| `cron_sync_from_cf.js` | 定时任务：从 Cloudflare 拉取最新数据到阿里云 |
| `course_to_cf.js` | 工具脚本：将本地课程数据批量导入到 Cloudflare |
| `full_sync_to_cf.js` | 工具脚本：全量数据推送 |
| `aliyun.md` | 阿里云环境配置指南 |
| `cloudflare.md` | Cloudflare 接口对接文档 |

---

## 🔄 同步流程

项目通常保持两端数据对齐：
1. **主库**: Cloudflare D1
2. **备库/缓存**: Aliyun MariaDB

通过 `master_sync.sh` 脚本，运维可以直接管理数据的双向流动。

---

*最后更新：2026-04-13*
