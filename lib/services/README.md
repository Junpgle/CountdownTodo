# services/ — 服务层

最后更新：`2026-05-24`

## 目录定位

`lib/services/` 连接 UI、本地持久化、后端 API、平台能力、AI、同步和统计分析。大部分服务采用静态工具式接口，连续状态通过 Stream 暴露。

## 核心服务

| 文件 | 职责 |
|------|------|
| `api_service.dart` | HTTP API 客户端、后端选择、鉴权头、增量同步请求。 |
| `database_helper.dart` | SQLite 初始化、建表、迁移和表结构修复。 |
| `pomodoro_service.dart` | 番茄钟标签、记录、运行状态、SQLite 存储、云同步、规划块回写。 |
| `pomodoro_control_service.dart` | 启停番茄钟，并绑定待办/规划块。 |
| `pomodoro_sync_service.dart` | 基于 WebSocket 的跨端番茄钟感知和更新消息。 |
| `notification_service.dart` | 本地通知基础能力。 |
| `reminder_schedule_service.dart` | 待办、课程、番茄钟、规划块提醒调度。 |
| `screen_time_service.dart` | Android UsageStats 和 Windows TAI 屏幕时间采集。 |
| `course_service.dart` | 课程存储、查询和 `CourseItem` 迁移。 |
| `calendar_sync_service.dart` | 系统日历同步。 |
| `lan_sync_service.dart` | 局域网同步发现和传输。 |

## AI 服务

| 文件 | 职责 |
|------|------|
| `llm_service.dart` | LLM 配置和基础/兼容调用。 |
| `ai_chat_service.dart` | 聊天和 SSE 请求处理。 |
| `ai_action_parser.dart` | 解析 `[ACTION_START]...` 和 `[SUGGEST_START]...`。 |
| `ai_todo_action_executor.dart` | 将确认后的 AI action 写入本地待办/规划块。 |
| `ai_todo_context_builder.dart` | 构建系统提示词和应用上下文。 |
| `ai_todo_chat_launcher.dart` | 统一 AI 待办助手入口。 |
| `todo_parser_service.dart` | 自然语言待办解析。 |
| `time_estimation_service.dart` | 基于历史记录估算规划块时长。 |
| `todo_classification_service.dart` | 待办分类、番茄标签推荐。 |

## 统计和推荐

| 文件 | 职责 |
|------|------|
| `timeline_service.dart` | 时间线汇总和效率统计。 |
| `timeline_ml_service.dart` | 面向 ML 的时间线建议。 |
| `medal_recommendation_service.dart` | 勋章进度和推荐排序。 |
| `medal_bandit_service.dart` | 推荐个性化老虎机算法。 |
| `medal_feature_extractor.dart` | 勋章推荐特征提取。 |
| `suggestion_feedback_service.dart` | 建议反馈记录。 |
| `search_service.dart` | 全局搜索结果生成。 |

## 平台和集成服务

| 文件 | 职责 |
|------|------|
| `widget_service.dart` | Android 桌面小组件数据更新。 |
| `float_window_service.dart` | Windows floating window 行为。 |
| `window_service.dart` | 桌面窗口、托盘和开机启动。 |
| `system_control_service.dart` | Windows 系统媒体/控制能力。 |
| `tai_service.dart` | Windows TAI 进程活跃时间采集。 |
| `band_sync_service.dart` | 小米手环伴侣数据提供和命令桥接。 |
| `external_share_handler.dart` | 分享 Intent 处理并导入待办流程。 |
| `clipboard_service.dart` | 剪贴板集成。 |
| `splash_service.dart` | 启动页内容缓存和网络获取。 |
| `animation_config_service.dart` | 动画偏好存储。 |
| `app_deep_link_service.dart` | 应用深链处理。 |

## 同步说明

- 主增量同步由 `StorageService.syncData()` 编排，不在单独 service 文件里。
- 番茄钟标签和记录在主同步请求之后由 `PomodoroService` 单独同步。
- 主同步不能在番茄钟上传之前消费 `pomodoro_records` 或 `pomodoro_tags` 的 oplog。
- `pomodoro_last_record_recovery_upload` 用于避免恢复补传反复上传同一批记录而引发 WebSocket 同步风暴。

## 后端规则

- 新后端能力优先修改 `aliyun_debug/`。
- Cloudflare Worker 行为保留兼容。
- Web 通过 Cloudflare Zero Trust 访问 API；Windows 和 Android 可直接访问 Alibaba Cloud HTTP 服务。
