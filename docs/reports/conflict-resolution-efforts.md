# 多端同步冲突反复出现问题排查与修复记录

## 1. 问题背景

在 CountDownTodo 的多端同步场景中，出现了一个非常明显的问题：

> 在手机端冲突中心选择“全部使用服务器”之后，待办冲突并没有真正消失。手机下一次同步后，相同或相似的冲突又会重新出现。

该问题不是单一 UI 显示问题，而是涉及多个同步入口和数据链路：

- Flutter 客户端本地数据库与 `op_logs` 同步队列；
- `aliyun_debug/server.js` 中的 Aliyun 调试服务端同步接口；
- Web 端 API 入口与 Cloudflare Zero Trust 代理；
- 旧 Cloudflare Worker 后端与 Aliyun 后端之间的数据回灌；
- 待办、倒数日、分组、番茄记录、番茄标签等多种数据对象的冲突字段处理；
- 版本冲突与时间冲突混在同一个冲突中心展示，导致用户操作语义不清。

因此，本次排查不是简单地修改一个按钮，而是围绕“为什么冲突会被重新制造、重新上传、重新下发或被错误清除”进行多轮闭环自查。

---

## 2. 总体排查思路

排查过程中主要围绕以下几个问题展开：

1. **冲突是否真的被解决了？**
   - 用户点击“使用服务器”后，本地是否仍然保留旧的未同步操作？
   - 服务端是否真的清除了冲突标记和过期冲突快照？

2. **冲突是否被别的端重新写回来了？**
   - Web 是否仍然访问旧 Cloudflare Worker？
   - Cloudflare 与 Aliyun 之间是否存在旧数据回灌？

3. **不同类型的冲突是否被混在一起处理了？**
   - `version_conflict` 是版本冲突；
   - `local_schedule_conflict` / `schedule_conflict` 是时间重叠提醒；
   - 二者不能使用同一套“使用服务器 / 保留本地”逻辑。

4. **系统有没有越权替用户做决定？**
   - 是否自动忽略时间冲突？
   - 是否自动调整任务时间？
   - 是否在强制同步时静默清除冲突？

5. **同步队列是否正确收敛？**
   - 真正阻塞同步的冲突是否应该保留 `op_logs`？
   - 非阻塞时间提醒是否不应该反复保留上传队列？

6. **服务端和客户端字段是否完整往返？**
   - 服务端标了 `has_conflict=1`，客户端是否能收到？
   - 客户端模型和本地数据库是否能保存 `conflict_data`？

---

## 3. 第一阶段：定位“使用服务器后冲突又回来”的直接原因

### 3.1 检查客户端冲突解决逻辑

首先从 Flutter 客户端入手，重点检查了：

- `lib/storage_service.dart`
- `lib/screens/conflict_inbox_screen.dart`
- `lib/widgets/conflict_alert_dialog.dart`
- `lib/services/api_service.dart`

重点搜索了以下关键词：

```text
conflict / 冲突 / sync / 同步 / resolve / useServer / has_conflict / conflict_data / op_logs
```

### 3.2 发现旧 `op_logs` 没有被清理

初步定位到一个关键问题：

> 用户选择“采用服务器版本”后，本地虽然覆盖了数据，但原先导致冲突的旧 `op_logs` 仍可能留在本机。

这样会导致下一轮同步时，手机又把旧本地版本重新上传给服务器。服务器再次看到旧版本与当前版本不一致，于是重新判定为冲突。

也就是说，用户表面上已经解决了冲突，但同步队列里还残留着“制造冲突的旧操作”。

### 3.3 修复方式

在本地冲突解决公共入口中增加队列清理逻辑：

- 解决某个 `uuid/table` 的冲突前，先清理该对象所有未同步旧 `op_logs`；
- 如果用户选择“保留本地”，再生成一条新的、干净的同步操作；
- 如果用户选择“使用服务器”，则不再留下会把旧本地版本推回服务器的队列。

涉及文件：

```text
lib/storage_service.dart
```

该修复解决的是“本地旧上传队列导致冲突复活”的问题。

---

## 4. 第二阶段：修复服务端过期冲突快照

### 4.1 发现 Aliyun 服务端可能保留旧 `conflict_data`

继续检查 `aliyun_debug/server.js` 后发现：

- 客户端明确传入 `has_conflict=0` 时，服务端清了冲突标记；
- 但过期的 `conflict_data` 仍可能残留；
- Web 或手机后续拉取时，仍可能拿到旧冲突详情。

这会造成用户体感上的“冲突清了又出现”。

### 4.2 修复方式

在 Aliyun 服务端同步更新待办时增加保护：

- 如果客户端明确传入 `has_conflict=0`，同时清空旧的 `conflict_data`；
- 避免旧冲突快照继续下发到其他端。

涉及文件：

```text
aliyun_debug/server.js
```

验证方式：

```bash
node --check aliyun_debug/server.js
```

服务端语法检查通过。

---

## 5. 第三阶段：排查 Web 端与旧 Cloudflare 后端回灌问题

### 5.1 发现 Web 端可能仍走旧 Cloudflare Worker

进一步对比项目规则和代码后发现：

项目规则要求：

```text
Web 端应通过 https://api-cdt.junpgle.me/ 访问 Aliyun
```

但代码中旧的 Cloudflare 地址仍然存在：

```text
https://mathquiz.junpgle.me
```

这意味着：

1. 手机端可能已经在 Aliyun 上解决了冲突；
2. Web 端如果仍访问旧 Cloudflare Worker，就会写入旧 D1 数据；
3. 后台同步脚本再把旧 Cloudflare 数据回灌到 Aliyun；
4. 手机下一次同步时，又看到被旧数据污染后的冲突。

这是一条典型的“多后端数据回流导致冲突反复”的链路。

### 5.2 修复方式

对 Web 端 API 入口进行收口：

- 增加 Web 专用 Aliyun Zero Trust 代理地址；
- `kIsWeb` 时固定走 `https://api-cdt.junpgle.me/`；
- 避免 Web 继续写旧 Cloudflare Worker；
- 将默认服务器从 `cloudflare` 调整为 `aliyun`，减少新设备误选旧后端的概率。

涉及文件：

```text
lib/services/api_service.dart
lib/screens/login_screen.dart
lib/storage_service.dart
```

---

## 6. 第四阶段：区分“版本冲突”和“时间冲突”

### 6.1 发现“全部使用服务器”对时间冲突没有语义

继续排查后发现，冲突中心里不只有版本冲突，还有本地时间冲突。

版本冲突的语义是：

```text
同一条数据，服务器版本和本地版本不同，需要选择谁覆盖谁。
```

时间冲突的语义是：

```text
两个任务、课程或番茄时间发生重叠，需要用户决定是否调整日程。
```

这两个问题完全不同。

因此，“全部使用服务器”只能合理处理版本冲突，不能自动解决时间冲突。因为即使采用服务器版本，两个任务的时间仍然可能重叠。下一次 `syncData()` 末尾的本地时间冲突扫描仍会重新打上 `local_schedule_conflict`。

这解释了一个重要现象：

> 用户看到“冲突又出现”，但它可能已经不是原来的版本冲突，而是被本地扫描重新生成的时间冲突。

### 6.2 曾短暂尝试“自动忽略”，随后主动撤回

在排查中曾尝试过一个方案：

> 批量选择后，自动忽略本次涉及的时间冲突，避免下一次同步又冒出来。

但这个方案被立即否定。

原因是：

- 时间冲突属于用户日程决策；
- 系统不能因为用户点击了“使用服务器”就替用户静默忽略时间重叠提醒；
- 自动忽略会导致用户错过真正需要处理的日程冲突。

### 6.3 最终修复方式

最终将批量操作语义改为：

- 批量“使用服务器”只处理版本冲突；
- 批量“保留本地”只处理版本冲突；
- 如果批量选择中包含时间冲突，则跳过；
- UI 提示用户：有若干项时间冲突需要单独处理；
- 只有用户进入单条时间冲突详情页，并主动选择“保留现状”时，才写入忽略关系。

涉及文件：

```text
lib/screens/conflict_inbox_screen.dart
lib/storage_service.dart
```

这一步明确划清了系统自动处理和用户显式决策之间的边界。

---

## 7. 第五阶段：自查批量推荐方案是否越权

### 7.1 发现批量推荐会自动调整时间

继续自查后发现，批量“推荐方案”也存在类似风险：

- 它可能自动调整时间冲突任务的时间；
- 虽然有确认弹窗，但没有逐项预览；
- 本质上仍然是在替用户做日程决策。

这和“自动忽略时间冲突”属于同一类问题。

### 7.2 修复方式

将批量推荐方案收口为：

- 只处理版本冲突；
- 时间冲突跳过；
- 提示用户必须进入单条详情查看和处理；
- 不再批量自动调整任务时间。

涉及文件：

```text
lib/screens/conflict_inbox_screen.dart
```

---

## 8. 第六阶段：修复强制全量同步绕过冲突处理的问题

### 8.1 发现 `forceFullSync/uploadAllLocal` 可能静默清冲突

继续检查同步入口后发现：

- 强制全量同步会把所有本地数据打包上传；
- 某些路径会把 `has_conflict` 置为 `0`，并删除 `conflict_data`；
- 这相当于绕过冲突中心，静默清除冲突。

这是一个更隐蔽的问题：即使 UI 不自动处理冲突，全量同步仍可能替用户清掉冲突。

### 8.2 修复方式

对全量同步和增量兜底路径进行限制：

- 未解决的版本冲突不上传；
- 文件夹、倒数日等对象如果仍有版本冲突，不被全量上传覆盖；
- 本地时间冲突只作为客户端 UI 提醒，不作为服务端版本冲突上传；
- 强制同步不能成为“静默解决冲突”的后门。

涉及文件：

```text
lib/storage_service.dart
```

---

## 9. 第七阶段：修复服务端“没传冲突字段就默认清冲突”的问题

### 9.1 发现普通同步更新默认 `has_conflict=0`

继续检查 `aliyun_debug/server.js` 后发现，服务端存在一个更底层的风险：

> 客户端没有传 `has_conflict` 时，服务端也可能按 `0` 处理。

这意味着旧客户端、Web 端或字段不完整的请求，只要进行一次普通更新，就可能把服务端已有冲突标记清掉。

这属于“隐式替用户解决冲突”。

### 9.2 修复方式

服务端逻辑调整为：

- 只有客户端明确传入 `has_conflict=0`，才允许清除冲突；
- 如果请求没有传冲突字段，则沿用服务端当前冲突状态；
- 普通同步更新不再默认清冲突；
- 明确解决冲突的接口，例如 `/api/sync/resolve_conflict`，才可以清冲突。

涉及对象包括：

- 待办；
- 倒数日；
- 分组；
- 番茄标签；
- 番茄记录。

涉及文件：

```text
aliyun_debug/server.js
```

验证方式：

```bash
node --check aliyun_debug/server.js
```

---

## 10. 第八阶段：修复服务端冲突检测后又被同轮更新覆盖的问题

### 10.1 发现番茄标签/记录冲突检测后缺少 `continue`

在服务端番茄标签和番茄记录同步逻辑中发现：

- 服务端先检测到了版本冲突；
- 已经标记 `has_conflict=1`；
- 但后续没有 `continue`；
- 同一轮代码可能继续进入更新分支，把刚刚标记的冲突又覆盖掉。

这属于“刚发现冲突，又自己抹掉”的问题。

### 10.2 修复方式

在检测到番茄标签或番茄记录版本冲突后，立即跳过后续普通更新流程。

涉及文件：

```text
aliyun_debug/server.js
```

---

## 11. 第九阶段：修复服务端时间冲突导致 `op_logs` 反复残留的问题

### 11.1 发现 `schedule_conflict` 被客户端误认为上传失败

继续自查时发现了一个更贴近“反复出现”的核心问题：

- 服务端返回的 `schedule_conflict` 本质是时间重叠提醒；
- 服务端其实已经接收并保存了这次待办更新；
- 但客户端把所有 `conflicts` 都当作上传失败；
- 因此对应的 `op_logs` 被保留为未同步；
- 下一次同步又上传同一条待办；
- 服务端又返回同一个时间冲突；
- 用户就看到冲突不断冒出来。

也就是说，真正阻塞同步的是版本冲突，而时间冲突不应该阻塞同步队列。

### 11.2 修复方式

将冲突分为两类处理：

#### 阻塞同步的冲突

例如：

```text
version_conflict
```

处理方式：

- 保留 `op_logs`；
- 等待用户在冲突中心明确选择；
- 不自动上传覆盖。

#### 非阻塞提醒型冲突

例如：

```text
schedule_conflict
pomodoro 时间提醒
```

处理方式：

- 不再卡住 `op_logs`；
- 服务端已保存的数据视为同步成功；
- 但将时间冲突落到本地冲突中心，供用户单条查看和处理。

涉及文件：

```text
lib/storage_service.dart
```

---

## 12. 第十阶段：防止服务端时间冲突落地后被本地扫描清掉

### 12.1 发现本地重算可能误清服务端时间冲突

修复 `schedule_conflict` 后继续自查，又发现新的副作用：

- 服务端返回的时间冲突可能是“待办-课程”或“待办-番茄”的冲突；
- 客户端本地 `_recomputeLocalTodoScheduleConflicts()` 主要扫描“待办-待办”的重叠；
- 如果本地重算时无差别清理时间冲突，就可能把服务端检测出的“待办-课程/番茄”冲突清掉。

这会导致该出现的冲突反而消失。

### 12.2 修复方式

将时间冲突来源区分为：

```text
source=local_detector
source=server_detector
```

本地重算只清理自己生成的 `local_detector` 冲突，不再清理服务端下发的 `server_detector` 冲突。

涉及文件：

```text
lib/storage_service.dart
```

---

## 13. 第十一阶段：修复番茄记录/标签冲突被客户端吞掉的问题

### 13.1 发现客户端只看 HTTP 200

继续检查番茄钟专用同步接口时发现：

- 服务端可能检测到 `pomodoro_records` 或 `pomodoro_tags` 冲突；
- 但客户端上传接口只判断 HTTP 状态码是否为 `200`；
- 只要 HTTP 成功，就把本地同步队列当作成功；
- 这会导致服务端发现的冲突被客户端吞掉。

这与之前的问题同源：系统把“请求成功”误当成“业务同步成功”。

### 13.2 修复方式

补充番茄链路的业务成功判断：

- 服务端返回 `conflicts`；
- 客户端解析响应体；
- 只有 `conflicts` 为空，才认为上传成功；
- 如果存在冲突，不清理本地待同步状态。

涉及文件：

```text
lib/services/api_service.dart
lib/services/pomodoro_service.dart
aliyun_debug/server.js
```

### 13.3 补充单条上传入口

后续继续自查发现，批量番茄记录上传已处理，但单条上传入口仍然只看 HTTP 200。

因此继续修复：

- `uploadPomodoroRecord()` 单条上传也解析响应体；
- 只有 `conflicts` 为空才返回成功；
- 避免单条入口吞掉服务端冲突。

涉及文件：

```text
lib/services/api_service.dart
```

---

## 14. 第十二阶段：修复服务端下发冲突字段不完整的问题

### 14.1 发现服务端标了冲突，但下发不带字段

继续检查后发现：

- 服务端可以给 `pomodoro_tags` / `pomodoro_records` 标记 `has_conflict=1`；
- 但同步下发的 `server_pomodoro_tags` / `server_pomodoro_records` 没有带 `has_conflict` 和 `conflict_data`；
- 专用 GET 接口也没有完整下发这些字段；
- 客户端即使拉到了数据，也无法知道这些对象处于冲突状态。

这会导致服务端状态和客户端视图脱节。

### 14.2 修复方式

在服务端下发数据中补齐：

```text
has_conflict
conflict_data
```

涉及文件：

```text
aliyun_debug/server.js
```

### 14.3 后续仍需完成的闭环

记录结尾处仍在继续补齐客户端侧承接逻辑：

- 番茄标签模型需要承接 `has_conflict/conflict_data`；
- 番茄记录模型需要承接 `has_conflict/conflict_data`；
- 本地 SQL 保存逻辑需要保留这些字段；
- 后续 UI 是否展示番茄冲突，需要进一步设计。

也就是说，服务端下发已经补齐，但客户端模型和本地落库仍需要继续闭环。

---

## 15. 验证工作

排查和修复过程中反复进行了以下验证：

### 15.1 服务端语法检查

```bash
node --check aliyun_debug/server.js
```

该检查多次通过，用于确认服务端 JavaScript 语法没有被补丁破坏。

### 15.2 Dart 格式化

```bash
dart format lib/storage_service.dart lib/screens/conflict_inbox_screen.dart lib/services/api_service.dart lib/services/pomodoro_service.dart
```

格式化过程基本完成，但多次遇到 Dart telemetry 文件权限问题，导致命令最终返回非零。该问题属于本机用户目录权限问题，不是代码格式错误。

### 15.3 Dart 静态分析

```bash
dart analyze lib/storage_service.dart lib/screens/conflict_inbox_screen.dart lib/services/api_service.dart lib/services/pomodoro_service.dart
```

分析结果没有发现本次改动引入的编译错误，主要剩余为项目既有 warning/info，以及 telemetry 权限导致的非零退出。

### 15.4 Diff 检查

```bash
git diff --check
```

用于检查补丁是否存在空白字符、格式问题等。

### 15.5 代码差异和状态检查

```bash
git diff --stat
git diff --name-only
git status --short
```

用于确认改动范围，避免误改无关文件。

---

## 16. 本次排查中涉及的主要文件

### Flutter 客户端

```text
lib/storage_service.dart
lib/screens/conflict_inbox_screen.dart
lib/services/api_service.dart
lib/screens/login_screen.dart
lib/services/pomodoro_service.dart
lib/services/database_helper.dart
lib/models.dart
```

### Aliyun 调试服务端

```text
aliyun_debug/server.js
```

### Cloudflare Worker / 后台同步相关

```text
math-quiz-backend/src/index.js
aliyun_debug/cron_sync_from_cf.js
aliyun_debug/full_sync_to_cf.js
aliyun_debug/sync_todos_to_cf.js
```

其中 Cloudflare 与回灌脚本主要用于确认是否存在旧后端污染 Aliyun 的链路。

---

## 17. 已完成的主要改进总结

### 17.1 同步队列层面

- 清理解决冲突对象的旧未同步 `op_logs`；
- “使用服务器”后不再保留旧本地上传队列；
- “保留本地”时重新生成干净的同步操作；
- 版本冲突继续阻塞同步；
- 时间提醒型冲突不再阻塞同步队列。

### 17.2 服务端冲突字段层面

- 客户端明确 `has_conflict=0` 时才清冲突；
- 没有传冲突字段时，服务端不再默认清冲突；
- 清冲突时同步清理旧 `conflict_data`；
- 倒数日、分组、番茄记录、番茄标签等对象同步逻辑也补齐类似保护。

### 17.3 Web 与多后端层面

- Web 固定走 Aliyun Zero Trust 代理；
- 避免继续写旧 Cloudflare Worker；
- 默认服务器从 Cloudflare 调整为 Aliyun；
- 降低新设备或网页登录旧后端造成数据回灌的风险。

### 17.4 UI 操作语义层面

- 批量“使用服务器”只处理版本冲突；
- 批量“保留本地”只处理版本冲突；
- 批量推荐不再自动调整时间；
- 时间冲突必须进入单条详情处理；
- 系统不再自动忽略用户的日程冲突。

### 17.5 番茄链路层面

- 服务端检测到番茄冲突后不再继续普通更新覆盖；
- 服务端返回 `conflicts`；
- 客户端上传不再只看 HTTP 200；
- 单条和批量上传都需要检查业务冲突；
- 服务端下发补齐 `has_conflict/conflict_data`。

---

## 18. 仍需继续完成的事项

根据对话记录结尾，目前仍有一些后续事项需要继续闭环：

1. **番茄模型字段承接**
   - `PomodoroTag` 需要完整承接 `has_conflict/conflict_data`；
   - `PomodoroRecord` 需要完整承接 `has_conflict/conflict_data`。

2. **本地 SQL 落库字段补齐**
   - 番茄标签和记录保存到本地数据库时，需要保留冲突字段；
   - 避免服务端下发的冲突状态在本地落库时丢失。

3. **番茄冲突 UI 设计**
   - 当前重点是”不吞冲突、不误清队列”；
   - 是否在冲突中心展示番茄冲突，还需要进一步设计。

4. **Aliyun 调试服务端部署确认**
   - `aliyun_debug/server.js` 在记录中显示可能不是 Git 跟踪文件；
   - 需要确保本地修改确实部署到对应 Aliyun 调试环境；
   - 否则本地修复不会影响真实服务。

5. **真实多端回归测试**
   - 手机端解决版本冲突；
   - Web 端同步；
   - 再次手机同步；
   - 检查是否仍出现旧版本冲突；
   - 检查时间冲突是否只作为明确的日程提醒出现，而不是反复上传制造。

6. **第十三阶段修复的回归测试**
   - 验证 `keep_local` 后同步不再被服务端过期冲突状态覆盖；
   - 验证 `accept_server` 在网络断开时能正确创建 oplog 兜底；
   - 验证批量 `keep_local` 后自动触发同步；
   - 验证版本冲突解决后不会被日程冲突扫描重新标记；
   - 验证 `countdowns` 阿里云版本冲突判断缺少 `updated_at` 检查的边界情况（chongtu.md 中记录的已知问题）。

---

## 19. 本次排查形成的经验

### 19.1 冲突不能只看 UI，要看数据闭环

冲突是否真正解决，不能只看冲突中心有没有消失，还要检查：

- 本地数据是否更新；
- 旧 `op_logs` 是否清理；
- 服务端冲突字段是否清理；
- 其他端是否会回灌旧数据；
- 下一次同步是否会重新上传旧操作。

### 19.2 版本冲突和时间冲突必须分开

版本冲突可以选择：

```text
使用服务器 / 保留本地
```

时间冲突不能这样处理。时间冲突是日程安排问题，必须由用户明确决定。

### 19.3 不允许系统静默替用户做决策

以下行为都被视为高风险：

- 自动忽略时间冲突；
- 批量自动调整任务时间；
- 强制同步时静默清冲突；
- 客户端没传冲突字段时服务端默认清冲突；
- HTTP 200 就认为业务同步成功。

### 19.4 同步成功不等于 HTTP 成功

一个请求返回 `200`，只能说明网络请求成功，不代表业务同步成功。

必须继续检查：

```text
success
conflicts
version_conflict
schedule_conflict
```

否则服务端已经发现的冲突会被客户端吞掉。

### 19.5 多后端架构必须保证单一写入口

如果手机写 Aliyun，Web 写 Cloudflare，再通过后台脚本互相同步，就很容易产生旧数据回灌。

因此 Web 必须统一走 Aliyun 代理，避免旧 Cloudflare Worker 继续参与写入。

### 19.6 合并条件中的标记字段不能触发整体覆盖

LWW 合并的核心是 `version` 和 `updatedAt`。如果把辅助标记字段（如 `hasConflict`）加入主合并条件，就会在标记不同但内容相同时触发不必要的整体覆盖。

正确做法是：标记字段的分歧在主合并之外单独处理，只更新标记本身，不覆盖内容。

### 19.7 API 调用失败必须有兜底机制

`catch (_) {}` 加上丢弃返回值，等于把"通知服务端"变成了纯运气依赖。如果服务端是唯一的冲突清除通道，就必须在 API 失败时创建本地 oplog 兜底，让下次同步重新推送。

同时，`ApiService` 返回 `{'success': false}` 而不是抛异常的设计，要求调用方必须检查返回值。`catch (_) {}` 在这种设计下是死代码，不能替代错误检查。

---

## 20. 第十三阶段：修复同步合并逻辑导致冲突解决被覆盖的问题

### 20.1 发现 `hasConflict != local.hasConflict` 合并条件盲目覆盖本地

深入分析同步合并逻辑后发现，`storage_service.dart` 中的合并条件存在一个致命缺陷：

```dart
if (sItem.isDeleted ||
    sItem.version > local.version ||
    sItem.updatedAt > local.updatedAt ||
    sItem.hasConflict != local.hasConflict) {  // ← 问题在这
  allLocalTodos[idx] = sItem;  // 整个本地项被服务端版本覆盖
```

该条件的本意是：当服务端清除冲突（从另一端解决）时，客户端能同步接收清除状态。但它的反面效果是：

1. 用户在本地解决冲突（`hasConflict = false`）；
2. 服务端 `resolve_conflict` API 调用还未执行完或静默失败；
3. 触发同步，服务端返回 `has_conflict = 1`（过期状态）；
4. `true != false` 成立，整个本地项（包括用户刚做的修改）被服务端旧数据覆盖。

同样的问题存在于 `TodoGroup`（3355 行）和 `CountdownItem`（3385 行）的合并逻辑中。

### 20.2 修复方式

从主合并条件中移除 `hasConflict != local.hasConflict`，改为在合并之后单独处理冲突标记分歧：

- **服务端有冲突、本地无冲突**（用户本地已解决但服务端未跟上）：只同步冲突元数据（`hasConflict`、`serverVersionData`），不覆盖内容。
- **本地有冲突、服务端无冲突**（从另一端解决）：清除本地冲突标记和冲突数据。

涉及文件：

```text
lib/storage_service.dart
```

涉及行：todos 合并（3317-3349）、groups 合并（3352-3382）、countdowns 合并（3382-3416）。

### 20.3 发现 `accept_server` 无 oplog 兜底导致解决状态丢失

`accept_server` 解决路径调用 `resolveConflictLocally(createOplog: false, touchUpdatedAt: false)`，唯一的救命稻草是 `ApiService.resolveConflict` API 调用。但该调用被 `catch (_) {}` 静默吞掉异常，且调用方丢弃了返回值。

`ApiService.resolveConflict` 内部有 try-catch，永远不会抛出异常，而是返回 `{'success': false}`。但调用方完全忽略了返回值。

如果 API 调用失败：
- 没有 oplog 兜底推送；
- `updatedAt` 未更新，下次同步不会上传该条目；
- 服务端保持 `has_conflict = 1`；
- 下次同步时 BUG 20.1 的合并条件把冲突拉回来。

### 20.4 修复方式

在 `_acceptServer` 和 `_batchAcceptServer` 中检查 `ApiService.resolveConflict` 的返回值。如果失败，再次调用 `resolveConflictLocally` 并设置 `createOplog: true, touchUpdatedAt: true` 作为兜底。

二次调用是安全的，因为 `resolveConflictLocally` 在创建 oplog 前会先删除同目标的未同步 oplog（4649-4653 行），不会产生重复。

涉及文件：

```text
lib/screens/conflict_inbox_screen.dart
```

涉及行：`_acceptServer`（3884-3912）、`_batchAcceptServer`（2127-2155）。

### 20.5 发现 `conflicts` 数组后处理无条件重写冲突标记

同步响应的 `conflicts` 数组在主合并之后处理（3502-3518 行），对 `version_conflict` 类型无条件设置 `todo.hasConflict = true`。即使用户刚通过 `keep_local` 解决了冲突（版本已提升、`hasConflict` 已清除），服务端在处理本轮上传时仍可能检测到日程重叠并返回 `schedule_conflict`，导致冲突标记被重新写入。

### 20.6 修复方式

在重新标记 `version_conflict` 之前，检查本地项是否已解决：如果 `!todo.hasConflict` 或 `todo.version > serverConflictVer`，跳过重新标记。

涉及文件：

```text
lib/storage_service.dart
```

涉及行：todos（3545-3560）、countdowns（3561-3575）、groups（3576-3590）。

### 20.7 发现批量 `keep_local` 不触发同步

`_batchApplyRecommendedExecute` 处理完后只调用 `_loadConflicts()` 刷新 UI，不触发 `syncData()`。oplog 条目留在本地，直到下次手动或自动同步。在这个窗口期内，如果发生自动同步，服务端的过期冲突状态会通过合并逻辑覆盖本地解决。

相比之下，单条 `_keepLocalAndQueueSync` 正确调用了 `Future.microtask(() => StorageService.syncData(...))`。

### 20.8 修复方式

在批量循环结束后、UI 刷新前，添加 `Future.microtask(() => StorageService.syncData(widget.username))`。

涉及文件：

```text
lib/screens/conflict_inbox_screen.dart
```

涉及行：`_batchApplyRecommendedExecute`（2339-2341）。

### 20.9 发现日程冲突重算可能重新标记已解决的版本冲突

`_recomputeLocalTodoScheduleConflicts` 在合并后运行（3611 行），扫描所有待办的时间重叠。如果一个项刚解决了版本冲突（`serverVersionData` 被清空），`_hasVersionConflict(null)` 返回 `false`，日程冲突扫描器会自由地将其标记为日程冲突（如果时间仍然重叠）。

这会让用户感觉"冲突又回来了"——虽然类型从版本冲突变成了日程冲突。

### 20.10 修复方式

在合并前快照有冲突的项 ID 集合 `preMergeConflictIds`，合并后计算 `recentlyResolvedIds`（冲突被清除的项），作为 `skipIds` 参数传入 `_recomputeLocalTodoScheduleConflicts`。在扫描循环中，跳过 `skipIds` 中的项，避免重新标记刚解决的冲突。

涉及文件：

```text
lib/storage_service.dart
```

涉及行：快照（3281-3284）、计算（3613-3621）、函数签名（3671）、跳过逻辑（3776-3779）。

### 20.11 补充 `keep_local` API 调用的错误日志

所有 `keep_local` 路径的 `ApiService.resolveConflict` 调用都使用 `catch (_) {}` 静默吞掉异常。虽然 `keep_local` 有 oplog 兜底（版本已提升），但静默吞错使问题排查不可能。

### 20.12 修复方式

将 `catch (_) {}` 替换为 `catch (e) { debugPrint('...'); }`，确保失败时有日志输出。

涉及文件：

```text
lib/screens/conflict_inbox_screen.dart
```

涉及行：`_keepLocalAndQueueSync`（413）、`_batchApplyRecommendedExecute`（2331）、`_keepLocal`（3855）。

---

## 21. 总结

这次为解决”冲突反复出现”所做的努力，已经从最初的待办版本冲突，逐步扩展到了整个多端同步系统的冲突闭环：

- 修复了本地旧 `op_logs` 反复上传的问题；
- 修复了服务端旧 `conflict_data` 残留的问题；
- 修复了 Web 可能继续写旧 Cloudflare 后端的问题；
- 区分了版本冲突和时间冲突；
- 撤回了不合理的自动忽略时间冲突方案；
- 收紧了批量操作和推荐方案的用户授权边界；
- 修复了强制全量同步绕过冲突处理的问题；
- 修复了服务端普通同步默认清冲突的问题；
- 修复了番茄记录/标签冲突被吞掉的问题；
- 补齐了部分服务端下发冲突字段；
- 修复了同步合并 `hasConflict !=` 条件盲目覆盖本地解决的问题；
- 修复了 `accept_server` 无 oplog 兜底导致解决状态丢失的问题；
- 修复了 `conflicts` 数组后处理无条件重写已解决冲突的问题；
- 修复了批量 `keep_local` 不触发同步导致服务端过期状态覆盖的问题；
- 修复了日程冲突重算可能重新标记已解决版本冲突的问题；
- 补充了 `keep_local` API 调用的错误日志。

整体上，本次排查的核心成果不是单点修复，而是建立了一个更清晰的原则：

> 版本冲突必须由明确的版本选择解决；时间冲突必须由用户明确处理；同步流程不能静默清除、忽略或吞掉任何仍需要用户决策的冲突。

这也是后续继续完善 CountDownTodo 多端同步系统时应当坚持的边界。

