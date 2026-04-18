团队协作功能实施计划
核心目标
构建一个支持多用户实时协同的日程管理系统，包含团队管理、邀请机制、智能冲突检测及实时数据广播。

进度总览 (Status: ✅ 已完成)
后端扩展: 团队 API、数据隔离、WebSocket 广播、冲突检测算法。
数据模型: 支持 team_uuid 的协作模型扩展。
UI/UX:
团队管理页面 (TeamManagementScreen)
冲突报警弹窗 (ConflictAlertDialog)
智能团队选择器 (AddTodoScreen)
同步链路: 支持团队域的数据聚合与实时更新。
详细任务拆解
1. 后端 (Node.js + SQLite)
   数据库 Schema 迁移：
   新增 teams 表 (id, uuid, name, creator_id, created_at)。
   新增 team_members 表 (team_id, user_id, role, joined_at)。
   为 todos, todo_groups 等表增加 team_uuid 字段。
   团队管理 API：实现团队创建、加入、成员列表查询。
   双模式邀请系统：
   直接邀请：通过 Email 直接添加成员。
   邀请码：生成 6 位唯一码，支持加入团队。
   WebSocket 广播升级：
   支持按 userId 和 teamUuid 订阅房间。
   实现数据的实时团队广播。
   智能冲突检测：实现时间重叠检查，并在 /api/sync 中返回冲突项。
2. 前端 (Flutter)
   API Service 扩展：封装团队管理相关 HTTP 请求。
   团队管理页面 (TeamManagementScreen)：
   采用玻璃拟态、动态色彩头像设计。
   支持团队创建、邀请码分享、成员添加。
   冲突警报系统：
   统一的 ConflictAlertDialog 组件。
   自动触发逻辑：同步返回冲突数据时，首页弹出通知。
   协作数据录入：
   AddTodoScreen 集成团队选择下拉框。
   技术亮点
   实时性：利用 WebSocket 房间机制，团队成员编辑日程后，所有在线成员立即同步。
   冲突预防：后端在处理增量同步时自动嗅探时间轴重叠，显著降低多人协作中的混乱。
   审美优先：遵循 Rich Aesthetics 原则，提供丝滑的动效与现代感 UI。
