# 团队单天冲突本地判定计划

## 问题与方案
当前团队“单天时间冲突”原先依赖服务端冲突返回；在服务端关闭团队冲突检测后，前端不会再自动产生该类冲突。  
方案是在前端同步收敛点（`StorageService.syncData`）新增**本地团队 Todo 单天冲突检测**，直接标记 `hasConflict/conflict_data`，并把结果用于冲突中心展示，同时在团队列表/卡片展示冲突数量角标。

## Todos
1. **梳理并固定判定规则**
    - 仅处理 `teamUuid != null` 的 Todo。
    - 仅处理存在有效时间区间的 Todo（`createdDate` 或 `createdAt` 作为开始，`dueDate` 作为结束）。
    - “单天”定义：冲突双方都落在同一自然日（本地日历日），且时间区间重叠。
    - 排除已删除项；是否排除已完成项按现有团队视图习惯评估后保持一致。

2. **在 StorageService 增加本地冲突检测与标记**
    - 新增私有 helper：按 `teamUuid + yyyy-mm-dd` 分桶并做区间重叠扫描。
    - 对检测出的 Todo 设置 `hasConflict = true`，并写入 `serverVersionData/conflict_data`（存放冲突对端摘要，供冲突中心展示）。
    - 对不再冲突的团队 Todo 清理旧冲突标记，避免“脏冲突”长期残留。
    - 与现有“服务端 conflicts 补标”逻辑并存：本地结果补充团队单天冲突，不影响版本冲突处理。

3. **团队管理页增加冲突角标数据**
    - 在团队加载阶段统计每个团队当前 `hasConflict` 的 Todo 数量（本地数据源）。
    - 在 `team_management_screen.dart` 的团队卡片上新增/复用角标展示冲突数。
    - 与现有待审批数量角标并存，视觉优先级明确（避免覆盖）。

4. **冲突中心文案与展示校准**
    - 将冲突卡片标签从固定“版本争议”改为按类型显示（至少区分“时间重叠/版本争议”）。
    - 确保本地生成的冲突数据可在对比弹窗里读取到时间区间与冲突来源摘要。

5. **联调与回归**
    - 验证场景：新增冲突、冲突消失、跨团队互不影响、离线后重开仍可见、同步后不被覆盖。
    - 验证“冲突中心 + 团队列表角标”两处一致。

## 说明
- 已确认范围：仅团队 Todo；不覆盖课程/番茄记录。
- 实现位置优先放在 `StorageService`，避免在多页面重复判定逻辑。
- 保持现有数据结构，不新增后端接口或协议字段。

## 同步冲突蓝图（团队 Todo 单天冲突）

### 1. 触发层（何时判定）
- 主触发：`StorageService.syncData()` 合并完本地与服务端数据后执行一次本地冲突判定。
- 次触发：本地 Todo 变更写入后（新增/编辑/完成/删除）可复用同一 helper 做增量重算（后续可优化）。

### 2. 输入层（判定数据集）
- 数据源：当前用户本地 `allLocalTodos`（已包含本轮同步合并结果）。
- 过滤条件：
    - `teamUuid != null`
    - `isDeleted == false`
    - 存在有效时间区间：`startMs` 与 `endMs` 均有效且 `startMs < endMs`
- 时间字段映射：
    - `startMs = createdDate ?? createdAt`
    - `endMs = dueDate.millisecondsSinceEpoch`

### 3. 规则层（单天+重叠）
- 单天规则：只比较同一自然日（本地时区 `yyyy-MM-dd`）内的任务。
- 分桶键：`teamUuid + dayKey`。
- 重叠规则：区间 `[startA, endA)` 与 `[startB, endB)` 满足 `startA < endB && startB < endA` 即冲突。
- 输出：冲突任务 UUID 集合 + 每条任务的冲突对端摘要（至少含 uuid/title/start/end/team_uuid）。

### 4. 标记层（写回本地模型）
- 对命中冲突的 Todo：
    - `hasConflict = true`
    - `serverVersionData/conflict_data` 写入本地冲突摘要（字段名保持兼容现有冲突中心）。
- 对未命中冲突但历史上有冲突标记的团队 Todo：
    - 清理 `hasConflict = false`
    - 清空 `conflict_data`
- 与版本冲突并存策略：
    - 若已有版本冲突数据，保留版本冲突优先级；本地时间冲突可写入可区分的 `type: local_schedule_conflict` 元信息。

### 5. 展示层（两处对齐）
- 冲突中心（`conflict_inbox_screen.dart`）：
    - 标签按类型显示：`时间重叠` / `版本争议`
    - 详情卡可展示本地冲突时间段与冲突对象标题
- 团队管理（`team_management_screen.dart`）：
    - 统计每个团队 `hasConflict == true` 的 Todo 数量
    - 卡片显示冲突角标（与待审批角标并存，不互相覆盖）

### 6. 一致性层（避免脏状态）
- 每轮同步后统一重算并覆写团队 Todo 冲突标记，避免旧冲突残留。
- 仅按本地已知数据判定（离线可用），不依赖服务端 `conflicts`。
- 服务端返回的版本冲突仍按现有链路消费，不回退兼容。

### 7. 验证层（完成标准）
- 任务 A/B 同团队同日重叠：两条都标记冲突，冲突中心可见，团队卡片角标+2。
- 调整时间后不重叠：两条冲突标记被清理，角标归零。
- 不同团队同日重叠：互不影响。
- 跨天任务：按“单天冲突”策略不纳入本期判定（后续可扩展）。

## 全量冲突蓝图（统一视角）

### A. 冲突类型矩阵
1. **逻辑冲突（local_schedule_conflict）**
    - 含义：团队内同日时间区间重叠（本地可判定）。
    - 触发点：本地数据合并后重算。
    - 数据来源：本地 Todo 集合。
2. **多端编辑争议（version_conflict）**
    - 含义：同一条目在多设备并发编辑，客户端版本不占优且内容不一致。
    - 触发点：同步响应中的 `conflicts` 或服务端 `has_conflict`。
    - 数据来源：服务端返回 `conflict_with` + 本地条目。
3. **版本回退链路（rollback_conflict_flow）**
    - 含义：用户选择“保留本地/采用服务器”后，需要清理冲突标记并推进版本。
    - 触发点：冲突中心解决动作。
    - 数据来源：本地条目 + 服务器版本快照（若可用）。

### B. 统一状态机
- `clean`：无冲突。
- `conflict_logic`：仅逻辑冲突。
- `conflict_version`：仅版本冲突。
- `conflict_mixed`：逻辑+版本同时存在（展示优先级：版本争议 > 逻辑冲突）。
- `resolving`：用户正在执行保留本地/采用服务器。
- `resolved_pending_sync`：本地已解决，待下轮同步对齐服务端状态。

### C. 数据契约（前端内部）
- 继续复用 `hasConflict + conflict_data(serverVersionData)`，但在 `conflict_data` 增加可区分字段：
    - `conflict_kind`: `logic` | `version`
    - `conflict_type`: `local_schedule_conflict` | `version_conflict`
    - `source`: `local_detector` | `server_sync`
    - `conflict_with`: 对端摘要（uuid/title/time/version 等）
- 这样不改数据库结构即可在 UI 层精准分流与展示。

### D. 管线分层
1. **Detect（检测）**
    - 本地检测器负责逻辑冲突。
    - 服务端返回负责版本冲突。
2. **Normalize（标准化）**
    - 两类冲突归一为统一内部结构（同一字段集）。
3. **Mark（落标）**
    - 写回 `hasConflict/conflict_data`；并清理失效冲突。
4. **Present（展示）**
    - 冲突中心按 `conflict_kind` 展示标签与卡片文案。
    - 团队列表角标统计 `hasConflict`，可附加类型分布（后续）。
5. **Resolve（解决）**
    - 逻辑冲突：以时间调整后自动消除为主，保留手动清理入口。
    - 版本冲突：保留本地/采用服务器，执行版本推进与清标。

### E. 处理优先级
- 先保留并展示版本冲突（防止数据丢失），再补充逻辑冲突提示。
- 若同条目存在混合冲突，冲突中心主标签显示“版本争议（含时间重叠）”。

### F. 回归口径
- 逻辑冲突闭环：创建重叠 -> 标记 -> 调整时间 -> 自动清除。
- 多端争议闭环：设备 A/B 交叉修改 -> 进冲突中心 -> 选择策略 -> 双端对齐。
- 回退闭环：执行回退后不出现“已解决条目再次幽灵复活”。

最终目标:
智能冲突检测与提醒：通过算法自动检测日程时间冲突，实时推送提醒，并提供智能调整建议，优化日程安排合理性。​
数据可视化与分析：将日程数据以图表形式呈现，如任务进度甘特图、时间占用热力图，帮助用户直观把握时间分配情况，辅助决策。