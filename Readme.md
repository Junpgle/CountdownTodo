# CountDownTodo / Uni-Sync

CountDownTodo 是一个基于 Flutter 的跨平台效率工具，覆盖待办规划、倒数日、番茄钟、时间日志、课程表、屏幕时间复盘、团队协同和多端同步。

当前应用版本：`4.12.18`
文档更新时间：`2026-05-24`

## 当前架构

- 主 Flutter 应用位于 `lib/`，平台壳位于 `android/`、`windows/`、`macos/`、`ios/`、`linux/`、`web/`。
- 高容量业务数据以 SQLite 为主存储；`SharedPreferences` 保留设置、登录态、同步水位线、小缓存和兼容迁移。
- 主同步入口为 `StorageService.syncData()`，负责待办、分组、倒数日、时间日志、规划块和屏幕时间 payload。
- 番茄钟同步由 `PomodoroService` 单独处理，包含标签、记录、oplog 保护和漏传恢复水位线。
- 后端同时保留 Alibaba Cloud 和 Cloudflare Worker。新后端能力优先修改 `aliyun_debug/`；`math-quiz-backend/` 保留兼容行为。
- Web 通过 Cloudflare Zero Trust 访问 `https://api-cdt.junpgle.me/`；Windows/Android 可直接访问 Alibaba Cloud HTTP 服务。
- WebSocket 用于番茄钟跨端感知和协同同步信号。
- Windows island / floating-window 是 Windows-only 逻辑，必须保持平台守卫，Android 不应导入或初始化。

## 主要功能

- 待办管理：分组、提醒、循环、版本历史、冲突处理、AI 辅助操作。
- 规划块：把已有待办安排到具体时间段，支持日视图创建、拖动改期、边缘调整、番茄钟绑定和统计。
- 番茄钟：标签、运行状态持久化、规划块绑定、记录统计、WebSocket 跨端感知、云同步。
- 时间日志和时间线：合并补录记录与番茄钟记录做效率分析。
- 课程导入和课程表：解析器位于 `lib/course_import/`。
- 团队协同：团队管理、公告、消息中心、冲突收件箱和同步状态展示。
- 全局搜索、勋章推荐、个人时间线、应用看板、Android 小组件、Windows 灵动岛。
- 小米手环伴侣应用位于 `CountDownTodo-band/`。

## 仓库结构

```text
math_quiz_app/
├── lib/                    Flutter 主应用代码
│   ├── course_import/       课程导入处理器、解析器和 UI
│   ├── models/              AI action、聊天消息、勋章 ML 等扩展模型
│   ├── screens/             页面层和功能页面
│   ├── services/            API、同步、数据库、番茄钟、AI、课程、时间线、通知、平台服务
│   ├── widgets/             可复用 UI 组件和首页区块
│   └── windows_island/      Windows-only 灵动岛/悬浮窗实现
├── aliyun_debug/            Alibaba Cloud 调试后端，新后端能力优先修改这里
├── math-quiz-backend/       Cloudflare Worker 后端，保留兼容
├── CountDownTodo-band/      小米手环伴侣应用
├── docs/                    项目文档，按主题归档
├── android/ windows/ macos/ ios/ linux/ web/  平台壳
├── assets/ splash/ wallpaper/                 资源目录
├── scripts/                 构建和运行脚本
└── test/                    Flutter 测试
```

## 常用开发命令

在仓库根目录运行 Flutter 命令：

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d windows
flutter run -d <device>
.\scripts\run.ps1 -- -d windows
.\scripts\build.ps1 -Android
.\scripts\build.ps1 -Windows
.\scripts\build.ps1 -All
```

Cloudflare Worker 后端：

```bash
cd math-quiz-backend
npm install
npm run dev
npm test
```

手环应用：

```bash
cd CountDownTodo-band
npm run start
npm run build
npm run lint
```

## 文档入口

- [文档目录](docs/README.md)
- [项目架构](docs/PROJECT_ARCHITECTURE.md)
- [规划块说明](docs/features/plan-blocks.md)
- [AI 待办助手](docs/ai/todo-agent.md)
- [冲突与同步逻辑](docs/sync/conflict-logic.md)
- [勋章推荐](docs/features/medal-recommendation.md)
- [版本管理修复报告](docs/reports/version-management-fix.md)
- [冲突修复排查报告](docs/reports/conflict-resolution-efforts.md)
- [lib 总览](lib/README.md)
- [services 总览](lib/services/README.md)
- [screens 总览](lib/screens/README.md)
- [widgets 总览](lib/widgets/README.md)
- [Windows 灵动岛总览](lib/windows_island/README.md)

## 关键规则

- 新后端能力优先修改 `aliyun_debug/`。
- 不要修改 `aliyun_release/`，除非任务明确要求。
- 保留 Cloudflare 兼容行为，除非任务明确要求迁移或删除。
- Windows island / floating-window 逻辑必须保持 Windows-only。
- 不要提交新的 secrets、签名密钥、凭据、keystore、证书或私有部署配置。
