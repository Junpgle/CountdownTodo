# 专注结束跨端状态残留修复（2026-10-19）

## 证据与原因

本次对照检查本地 Flutter、CDT-server/debug 和 math_quiz_backend 源码，没有读取线上日志或连接生产主机，因此不能据此认定某一次线上故障的唯一原因或宣称已部署。

已在原始服务器代码的隔离副本上运行回归，复现了异步 START 查询晚于 STOP 返回后重新写入状态、旧 STOP 清除新会话、重连快照被旧 action 覆盖、迟到 RESUME 继续广播等失败场景。测试使用真实 WS 消息处理器和房间广播，数据库查询与 socket 使用可控替身。

客户端另外存在以下缺口：

- 断开连接时 `_send` 直接返回，结束消息没有重试或服务器确认。
- 后台停止路径先标为空闲，可能在发送结束消息前启动断开流程。
- 首页未处理 FINISH / CLEAR_FOCUS；服务器清除缓存后，已连接的首页仍可能保留计时。
- 消息处理包含 await，原先并发执行 START / STOP 处理可能导致界面按错误顺序更新。
- SWITCH 原先未更新服务器缓存中的 session_uuid 和任务绑定，重连可能回推旧会话。

这些缺口能解释“观察端刷新后仍收到旧状态，而重新开始并结束会覆盖残留”的现象；与具体生产故障的关联还需线上日志及多端验收确认。

## 修改范围

Flutter：`pomodoro_sync_service.dart`、`pomodoro_control_service.dart`、首页专注 mixin、工作台专注消息处理、新增 `test/pomodoro_focus_end_sync_test.dart`，以及该测试的单行 Git 忽略例外。相关文件中原有及并行任务的其他修改未回退。

服务器：修复已同步到 `CDT-server/debug/ws/index.js` 与正式代码 `CDT-server/math_quiz_backend/ws/index.js`，分别新增 `debug/ws/focusLifecycle.test.js` 和 `math_quiz_backend/ws/focusLifecycle.test.js`。正式版原有更新检查导入及其他代码保持原样。

- 结束消息使用 request_id 确认；未确认的会话结束消息在重连及心跳时补发。
- 只有服务器声明支持安全重发后才重发，兼容尚未更新的服务器。
- 按 session_uuid 清理，旧结束请求不影响新会话；兼容旧版仅携带 todo_uuid 的即时请求。
- 服务器记录近期已结束会话，阻止旧 START / RECONNECT_SYNC 重新激活；异步开始查询按生命周期失效。
- 迟到 PAUSE / RESUME / 备注和标签变更需要匹配当前状态。
- 重连快照正确使用 SYNC_FOCUS；SWITCH 更新缓存；团队兜底清理同步广播。
- 首页及工作台按序处理消息，接收 FINISH / CLEAR_FOCUS，并按会话匹配结束消息。
- 后台结束提供最多 5 秒连接保留窗口，收到确认即可休眠；超时后保持待补发消息，等待后续恢复连接。

## 验证

已执行：

```sh
# CountdownTodo 根目录
flutter test --no-pub test/pomodoro_focus_end_sync_test.dart test/services/pomodoro_completion_policy_test.dart test/services/pomodoro_record_sync_test.dart
/Users/junpgle/develop/flutter/bin/cache/dart-sdk/bin/dart analyze lib/services/pomodoro_sync_service.dart lib/services/pomodoro_control_service.dart lib/screens/home_dashboard_pomodoro.dart lib/screens/pomodoro/views/workbench_view.dart test/pomodoro_focus_end_sync_test.dart

# CDT-server 根目录
NODE_PATH=math_quiz_backend/node_modules node --test debug/ws/focusGuard.test.js debug/ws/focusLifecycle.test.js
NODE_PATH=math_quiz_backend/node_modules node --test math_quiz_backend/ws/focusGuard.test.js math_quiz_backend/ws/focusLifecycle.test.js
node --check math_quiz_backend/ws/index.js
node --check math_quiz_backend/ws/focusLifecycle.test.js
```

- Flutter：12 项通过（新增传输/结束同步测试 8 项，既有完成策略及记录同步测试 4 项）。客户端测试使用可控传输替身，没有访问线上账号。
- 开发服务器：14 项通过（生命周期 10 项、任务准入 4 项）。正式服务器：同一组 14 项通过；两个版本都覆盖跨用户团队观察端的结束广播。
- Dart 定向分析：无 error / warning；工作台原有并行修改位置有一条 `prefer_null_aware_operators` info，未扩大本次修改范围。
- 两个工作树 `git diff --check` 通过。

未执行：全量 Flutter 测试、应用构建、真实多设备/后台断网操作、生产部署及发布。Flutter 命令最初被 SDK 缓存写入权限阻止，获准扩大执行权限后实际运行通过。最终复跑曾遇到 native_assets.json 构建中间文件缺失，再次运行同一组命令后 12 项通过；未运行 flutter clean。

## 生效边界

本次交付同时更新了本地正式服务端代码，没有 commit、push、远程重启或生产部署。需要把正式代码发布并更新客户端，线上设备才会获得确认重试及界面修复。

待补发消息保存在当前客户端进程内（最多 128 个会话），退出进程后依赖既有的发起端重连空闲上报清理。服务端状态和结束记录仍在单进程内存中，结束记录保留 12 小时；本次没有引入共享存储或多实例同步。
