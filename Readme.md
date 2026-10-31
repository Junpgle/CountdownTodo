# CountDownTodo / Uni-Sync

<img src="assets/icon/app_icon.png" alt="CountDownTodo" width="128" height="128">

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)
![Client: Flutter](https://img.shields.io/badge/Client-Flutter-02569B?logo=flutter&logoColor=white)
![Backend: Node.js/Express](https://img.shields.io/badge/Backend-Node.js%20%2F%20Express-339933?logo=nodedotjs&logoColor=white)
![Database: SQLite](https://img.shields.io/badge/Database-SQLite-003B57?logo=sqlite&logoColor=white)
![Android: Supported](https://img.shields.io/badge/Android-Supported-3DDC84?logo=android&logoColor=white)
![Desktop: Windows/macOS](https://img.shields.io/badge/Desktop-Windows%20%2F%20macOS-0078D4)
![Web: Beta](https://img.shields.io/badge/Web-Beta-4285F4?logo=googlechrome&logoColor=white)
[![Release](https://img.shields.io/github/v/release/Junpgle/CountdownTodo?label=Release)](https://github.com/Junpgle/CountdownTodo/releases/latest)

CountDownTodo 是一个基于 Flutter 的跨平台效率工具，覆盖待办规划、倒数日、番茄钟、时间日志、课程表、屏幕时间复盘、团队协同和多端同步。

Countdown Todo is a Flutter productivity app combining todos, recurring todo series, habit tracking, countdowns, courses, focus sessions, plan blocks, collaboration, statistics, calendar integration and AI-assisted actions.

当前应用版本：`7.22.8`
文档更新时间：`2026-10-31`

## 支持平台

- **Android**：通知、桌面小组件（含“循环待办”）、HyperOS/HyperIsland 集成、屏幕使用时间统计、小米手环通信。
- **Windows**：桌面客户端，以及独立的灵动岛/悬浮窗 host（`lib/windows_island/`，Windows-only）。
- **macOS**：菜单栏（可关闭）、WidgetKit 小组件（含“循环待办”）、开机自启、深度链接、原生灵动岛/状态显示。
- **Web**：Flutter Web 客户端（Beta），通过 Cloudflare Zero Trust 访问 API；另有 React 网页介绍站 `webpage/web/`。
- 配套项目：React 介绍页 `webpage/web/`、小米手环伴侣应用 `CountDownTodo-band/`。

## 高阶功能使用教程
【腾讯文档】[CountDownTodo 高阶使用教程](https://docs.qq.com/aio/DRmZzZHBsdkVBdENi)

## 主要功能

- **待办管理**：分组、提醒、循环待办（习惯另有独立打卡模型）、固定日程（独立 `fixed_schedules` 模型，支持与待办双向关联、改期影响复核与准备时间推荐）、未安排时间待办语义、版本历史、冲突处理、回收站、AI 辅助操作。
- **规划块**：把已有待办安排到具体时间段，支持日视图创建、拖动改期、边缘调整、番茄钟绑定和统计，可写入系统日历与小时级动态分轨展示。
- **番茄钟**：标签、暂停详情、运行状态持久化、规划块绑定、记录统计、WebSocket 跨端感知、云同步、专注备注、年度记录分析与专注习惯联动。
- **习惯中心**：独立打卡模型（`lib/features/habits/`），连续天数与完成率统计、睡眠作息渐进训练、快捷打卡与小组件打卡、长按防误触与延迟盖章保护、专注习惯联动与容量规划接入。
- **个人记账**：离线优先的支出、收入、退款记录，账单日历视图、分类账本精准筛选、月度累计结余趋势穿透分析、未来固定及手工收支一览、月度总预算与分类预算、预算提醒、周期账单、快捷模板、CSV/JSON 备份和回收站恢复（`lib/features/finance/`）。
- **时间日志和时间线**：合并补录记录与番茄钟记录做效率分析；个人时间轴支持天/周/月/年维度，支持课程与固定日程只读占位映射。
- **课程表**：导入与解析（`lib/course_import/`）、共存模式、多学期切换、周/月视图、调休。
- **本地私密日记**：仅存本地的图文日记，支持回收站软删除、原时间恢复与物理附件彻底清理（`lib/features/journal/`）。
- **30 天挑战**：30 件小事清单挑战，支持独立打卡、专注联动、云端模板目录和分享口令（`lib/features/thirty_day_challenge/`）。
- **功能百宝箱与探索中心**：分类功能知识库、新特性引导（v7.22）、功能直达与使用探索进度打卡（`lib/screens/help/`）。
- **动画与流畅度量化监控**：实时帧率与渲染达标率监测、GPU/CPU 渲染压力等级动态评估、特效负荷细项分析与性能监控悬浮窗。
- **全局搜索与设置搜索**：全局搜索覆盖待办、日程、记账、日记、规划块、习惯打卡、挑战、AI 对话和团队资料，并支持功能直达；设置首页支持全配置项模糊搜索。
- **数据备份与恢复**：JSON 备份支持按数据域选择导出与恢复（待办/日程、课程、专注、习惯、挑战、记账等独立选择），支持恢复前复核与分域导入结果回执。
- **团队协同**：团队管理、公告、消息中心、冲突收件箱、甘特图/热力图看板、共享链接查看。
- **AI 助手**：LLM 配置（含 NVIDIA NIM）、智能上下文注入、待办建议与操作、待确认记账草案及账单查询/修改/删除、图片识别待办和勋章 ML 推荐。
- **视觉与体验**：首页预设壁纸直出与 Bing 每日壁纸本地缓存与重试、液态玻璃（Liquid Glass）视觉效果（可选开关、模式与滤镜缓存）、全局动态取色、屏幕使用时间统计、首页侧栏自定义与板块间距自适应。
- **本地 MCP 待办服务**：`mcp-server/` 提供 Node.js stdio MCP Server，供 Claude、VS Code、Cursor 等 Host 查询和操作本地待办，写入 `op_logs` 由 Uni-Sync 机制同步。

## 当前架构

- 主 Flutter 应用位于 `lib/`，平台壳位于 `android/`、`windows/`、`macos/`、`ios/`、`linux/`、`web/`。
- 高容量业务数据以 SQLite 为主存储（当前 schema v60）；`SharedPreferences` 保留设置、登录态、同步水位线、小缓存和兼容迁移。
- 主同步入口为 `StorageService.syncData()`，负责待办、分组、倒数日、时间日志、规划块、屏幕时间 payload 和能力门控的个人记账切片；番茄钟同步由 `PomodoroService` 单独处理（标签、记录、oplog 保护、漏传恢复水位线）。
- 后端同时保留 Alibaba Cloud 和 Cloudflare Worker。新后端能力优先修改 `CDT-server/debug/`（外部 checkout 的研发树）；`math-quiz-backend/` 保留兼容行为。
- Web 通过 Cloudflare Zero Trust 访问 `https://api-cdt.junpgle.me/`；Windows/Android 可直接访问 Alibaba Cloud HTTP 服务。
- WebSocket 用于番茄钟跨端感知和协同同步信号。
- Windows island / floating-window 是 Windows-only 逻辑，必须保持平台守卫，Android 不应导入或初始化。

## 仓库结构

```text
CountdownTodo/
├── lib/                    Flutter 主应用代码
│   ├── course_import/       课程导入处理器、解析器和 UI
│   ├── models/              AI action、聊天消息、勋章 ML 等扩展模型
│   ├── features/            自包含功能模块（习惯、私密日记、30 天挑战、个人记账）
│   ├── screens/             页面层和功能页面
│   ├── services/            API、同步、数据库、番茄钟、AI、课程、时间线、通知、平台服务
│   │   └── storage/         StorageService 拆分的职责模块
│   ├── theme/               主题扩展（含液态玻璃主题应用）
│   ├── widgets/             可复用 UI 组件和首页区块
│   └── windows_island/      Windows-only 灵动岛/悬浮窗实现
├── mcp-server/              本地 MCP 待办服务（Node.js）
├── math-quiz-backend/       Cloudflare Worker 后端，保留兼容
├── CountDownTodo-band/      小米手环伴侣应用
├── webpage/web/             React 网页介绍站
├── docs/                    项目文档，按主题归档
├── android/ windows/ macos/ ios/ linux/ web/  平台壳
├── assets/ splash/ wallpaper/                 资源目录
├── scripts/                 构建和运行脚本
└── test/                    Flutter 测试
```

详见 [文档目录](docs/README.md)、[项目架构](docs/PROJECT_ARCHITECTURE.md) 和 [贡献指南](CONTRIBUTING.md)。

## 常用开发命令

在仓库根目录运行 Flutter 命令：

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d <device>
dart format lib test
```

仓库脚本：

```bash
./scripts/build_macos.sh
./scripts/sync_macos_version.sh
./scripts/deploy_web_beta.sh

# 构建并归集 Android、macOS、Web 发布产物
./scripts/release_all.sh
```

产物会放在 `build/release-assets/v<版本>/`，其中包含 macOS ZIP、三个 Android APK 和 arm64-v8a 差分包，可直接全选上传。Web 会通过 `deploy_web_beta.sh` 构建并发布。

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

MCP 待办服务：

```bash
cd mcp-server
npm install
COUNTDOWN_TODO_DATABASE="/absolute/path/uni_sync_<username>.db" npm run check
npm run lint
npm test
```

## 文档入口

- [文档目录](docs/README.md)
- [项目架构](docs/PROJECT_ARCHITECTURE.md)
- [待办与日程语义](docs/features/todo-semantics.md)
- [规划块说明](docs/features/plan-blocks.md)
- [习惯中心设计](docs/habits.md)
- [AI 待办助手](docs/ai/todo-agent.md)
- [冲突与同步逻辑](docs/sync/conflict-logic.md)
- [勋章推荐](docs/features/medal-recommendation.md)
- [全局搜索](docs/features/global-search.md)
- [macOS 支持](docs/features/mac-support.md)
- [人机验证](docs/features/captcha-verification.md)
- [版本管理修复报告](docs/reports/version-management-fix.md)
- [冲突修复排查报告](docs/reports/conflict-resolution-efforts.md)
- [lib 总览](lib/README.md)
- [services 总览](lib/services/README.md)
- [screens 总览](lib/screens/README.md)
- [widgets 总览](lib/widgets/README.md)
- [Windows 灵动岛总览](lib/windows_island/README.md)
- [MCP 服务说明](mcp-server/README.md)

## 关键规则

- 新后端能力优先修改 `CDT-server/debug/`；不要修改生产代码 `CDT-server/math_quiz_backend/`，除非任务明确要求。
- 保留 Cloudflare Worker 兼容路径，除非任务明确要求迁移或删除。
- Windows island / floating-window 逻辑必须保持 Windows-only。
- 不要提交 secrets、签名密钥、凭据、keystore、证书或私有部署配置；只使用开发后端配置。
