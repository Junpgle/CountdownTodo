# Uni-Sync 实施任务清单 (Implementation RoadMap)

本清单基于 **Uni-Sync V4.0 设计蓝图** 拆解，旨在指导开发流程。

---

## 🏗️ 阶段 1：后端数据确定性基座 (Status: ✅ 已完成)
- [x] **数据库 schema 升级 (SQLite)**
  - [x] 新增 `audit_logs` 表：支持 `before_data(JSON)`, `after_data(JSON)`, `op_type` 字段。
  - [x] 新增 `team_join_requests` 表：支持申请-审批流状态管理。
- [x] **审计系统开发**
  - [x] 编写全局 `withAudit` 钩子：在 `INSERT/UPDATE/DELETE` 时自动捕获快照。
  - [x] 实现增量合并算法 (Diff Engine)：处理字段级差量提取。
- [x] **防御体系集成**
  - [x] 开发 `Request-Approve` 接口：管理员审批逻辑及权限校验。
  - [x] 实现 `Adaptive-Blocking` 中间件：基于速率监控的自动封禁逻辑。
  - [x] 实现 `PoW-Validator`：针对回滚/大规模写入请求的 CPU 计算验证。

---

## ⚡ 阶段 2：全端强同步引擎 (Status: ✅ 已完成)
- [x] **客户端离线逻辑 (Flutter)**
  - [x] 实现本地 `Oplog` 表：记录离线期间的操作序列。
  - [x] 集成 `SQLite FTS`：构建全量本地搜索索引。
- [x] **Smart Merge 冲突处理器**
  - [x] 实现 **冲突挂起标记 (Conflict Flag)** 逻辑：将争议项置为待裁决状态。
  - [x] 开发详情页 **Version Diff 对比组件**：展示冲突字段并提供手动选定。
- [x] **多时区渲染核心**
  - [x] 统一后端存储为 UTC。
  - [x] 实现前端 `DateTimeTransformer`：根据定位动态偏移时区并美化显示。

---

## 📱 阶段 3：极致感官 UI 组件 (Status: ✅ 已完成)
- [x] **Sync-Status-Banner (核心状态栏)**
  - [x] 接入 **链路自诊断 (Path Discovery)**：支持网络/CF隧道/后端状态嗅探。
  - [x] 实现多级动画反馈（离线红/同步绿/异常黄）。
- [x] **Sticky-Banner (置顶公告位)**
  - [x] 实现团队公告的强制展示逻辑。
  - [x] 开发“我已阅读”确认回调及管理端统计接口。
- [x] **Conflict-Inbox (冲突收件箱)**
  - [x] 建立统一的待处理冲突聚合页。

---

## 🎨 阶段 4：可视化与大局观 (Status: ✅ 已完成)
- [x] **Unified-Waterfall 视图开发**
  - [x] 开发跨团队全景汇聚流布局。
  - [x] 实现 **Team Tag (团队名标签)** 视觉标识。
- [x] **只读分析看板 (Gantt & Heatmap)**
  - [x] 集成 `fl_chart` 或自定义 Canvas 绘制热力负荷图。
  - [x] 开发甘特图组件（仅限 Read-only 展示模式）。

---

## 🚀 阶段 5：感官美学与架构固化 (Status: ✅ 已完成)
- [x] **Motion-Guide 协议实现**
  - [x] 接入 `Lottie` 或 `Flutter Animations` 实现 **字段脉冲 (Pulse)**。
  - [x] 实现 **冲突微震 (Shake)** 与 **回滚翻页 (Flip)** 交互。
- [x] **架构鲁棒性增强**
  - [x] 解决 Windows 平台 `databaseFactory` 初始化时序问题。
  - [x] 强制增量迁移：从 `SharedPreferences` 到 `SQL` 的平滑过渡。

---

## 🛠️ 持续优化与问题修复 (Post-V4.0 Maintenance)

- [x] **同步一致性修复**
  - [x] 修复待办状态 (`is_completed`) 手机端更新后无法持久化至后端的 Bug。
  - [x] 修复应用内完成特殊待办时，通知栏待办未自动清除的问题。
  - [x] 优化网络不稳定时的异步处理机制，支持待办点击连续提交。
  - [x] 强化 Delta Sync 引擎：采用 LWW (Last Write Wins) 策略解决并发冲突。
- [x] **协同工作流增强**
  - [x] 开发“快捷入队”分享功能：支持将分享码生成文本复制并自动识别申请。
  - [x] Web 端同步支持：完成 `TeamManagementView` 状态同步与 409 冲突重刷逻辑。
- [x] **设备适配增强**
  - [x] 手表端：实现版本更新自动检查机制。
- [x] **可视化看板升级**
  - [x] 引入 smooth cubic Bezier 曲线绘制专注统计图表，支持渐变填充。
- [x] **系统可用性**
  - [x] 全局搜索系统支持“日期语义”搜索（如：搜索“今天”）。
  - [x] 优化手机端 `HomeAppBar` 布局，支持手机/平板自适应网格。

---

## 📝 待办清单 (Backlog)
- [ ] 自动化清理机制：针对长期不使用的团队数据执行本地脱敏存档。
- [ ] 澎湃OS (HyperOS) 3.0 实时活动通知更深层适配。
- [ ] 离线状态下大规模数据的预取与预渲染优化。

---
*Uni-Sync Implementation Roadmap - Updated 2026.04.24*

