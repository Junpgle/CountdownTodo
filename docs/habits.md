# CountdownTodo 习惯功能设计方案

**文档版本：** V1.0
**功能名称：** 习惯中心
**适用客户端：** Android、Windows、macOS、Web
**核心原则：** 复用现有待办和专注能力，仅为现有功能无法表达的习惯新增独立打卡模型。

> **实现状态（2026-08-25 核对）**：习惯中心核心能力已落地，代码位于
> `lib/features/habits/`（models / repositories / services / widgets / screens），
> 包含打卡模型与统计、睡眠作息渐进训练、提醒、快捷打卡与小组件打卡；
> 首页展示为 `habit_today_section`。本文其余部分保留原始设计背景，
> 与实现的差异以代码为准。

---

# 一、功能背景

CountdownTodo 当前已经具备：

* 循环待办；
* 番茄钟与专注记录；
* 时间日志；
* 本地 SQLite；
* 多设备增量同步；
* 系统通知；
* 首页模块化展示；
* 时间轴与个人报告；
* 桌面小组件。

当前缺少的是一个统一的“长期目标追踪层”。

用户虽然可以创建“每天早起”“每天阅读”等循环待办，但目前无法方便地查看：

* 连续坚持了多少天；
* 最近 30 天完成率；
* 每天喝了多少水；
* 每次喝水的时间；
* 实际起床时间是否符合目标；
* 每周累计运动了多久；
* 专注时长是否达到长期目标。

因此，习惯功能不应重新实现一套待办和计时器，而应将现有循环待办、专注记录和新增打卡事件统一组织成“习惯目标”。

---

# 二、产品定位

## 2.1 功能定义

习惯中心是一个长期行为目标管理与统计模块，负责：

1. 定义用户希望长期坚持的目标；
2. 从现有待办、专注记录或打卡事件中读取进度；
3. 判断当天或当周是否达标；
4. 提供提醒、连续天数和趋势统计；
5. 在首页、小组件和个人报告中展示习惯状态。

## 2.2 核心设计原则

### 原则一：不重复保存相同数据

* 完成型习惯使用循环待办作为数据源；
* 时长型习惯使用专注记录作为数据源；
* 数量型和时间点型习惯才使用独立打卡事件。

### 原则二：习惯是目标，不是另一种任务

待办强调：

> 有一件事情需要完成。

习惯强调：

> 希望某种行为长期保持在目标水平。

同一条循环待办可以被加入习惯追踪，但不需要复制出另一份任务。

### 原则三：打卡和达标必须分开

例如早起目标是 07:30 前：

* 08:10 记录起床时间，属于“已打卡”；
* 但没有达到早起目标，属于“未达标”。

连续坚持天数应以“达标”为准，而不是以“是否点过按钮”为准。

---

# 三、习惯类型

第一版支持四种核心类型。

| 类型   | 数据来源   | 典型习惯       | 达标方式         |
| ---- | ------ | ---------- | ------------ |
| 完成型  | 循环待办   | 吃维生素、整理桌面  | 本周期对应待办已完成   |
| 时长型  | 专注记录   | 阅读、学习、运动   | 本周期累计时长达到目标  |
| 数量型  | 习惯打卡记录 | 喝水、俯卧撑、背单词 | 本周期累计数量达到目标  |
| 时间点型 | 习惯打卡记录 | 早起、早睡      | 实际时间符合目标时间范围 |

---

# 四、完成型习惯

## 4.1 基本定义

完成型习惯本质上是被加入习惯追踪的循环待办。

例如：

* 每天吃维生素；
* 每晚整理桌面；
* 每周日浇花；
* 每个工作日复习课程。

CountdownTodo 当前的 `TodoItem` 已经支持每日、每周、工作日、自定义天数等重复方式，并通过 `recurrenceSeriesId` 维护循环系列，因此完成型习惯应直接绑定循环待办系列。

## 4.2 创建方式

用户在习惯中心创建完成型习惯时，系统实际创建：

1. 一条循环待办系列；
2. 一条习惯目标；
3. 习惯目标的 `sourceId` 指向待办的 `recurrenceSeriesId`。

示例：

```text
习惯名称：每天整理桌面
类型：完成型
重复：每天
提醒：22:00
数据来源：循环待办系列 7a2f...
```

## 4.3 已有待办加入习惯

在循环待办详情页或菜单中增加：

> 加入习惯追踪

加入后，不复制待办数据，仅创建绑定关系。

## 4.4 显示位置

为了避免首页同时出现两个相同项目，提供：

```text
首页显示位置

● 仅显示在习惯模块
○ 仅显示在待办模块
○ 同时显示
```

默认规则：

* 从习惯中心新建：仅显示在习惯模块；
* 已有循环待办加入习惯：保留原有显示方式。

此设置只影响首页展示，不影响待办自身和提醒。

## 4.5 进度计算

完成型习惯根据循环待办实例计算：

```text
今日已完成：对应日期实例 isDone = true
今日未完成：对应日期实例 isDone = false
今日无计划：当天不属于循环规则
```

统计指标：

* 当前连续达标天数；
* 最长连续达标天数；
* 近 7 天完成率；
* 近 30 天完成率；
* 应完成次数；
* 实际完成次数；
* 逾期次数。

---

# 五、时长型习惯

## 5.1 基本定义

时长型习惯直接绑定现有专注标签，不新增独立计时器。

例如：

```text
习惯：每天阅读 30 分钟
绑定专注标签：阅读
目标：每天累计 30 分钟
```

用户可以从以下入口开始：

* 在习惯卡片点击“开始专注”；
* 在现有专注页面选择“阅读”标签；
* 从相关待办开始专注；
* 在专注记录中补录。

所有符合标签条件的专注记录自动计入习惯进度。

## 5.2 单标签和多标签绑定

支持绑定一个或多个专注标签。

示例：

```text
习惯：每周运动 150 分钟

绑定标签：
✓ 跑步
✓ 骑行
✓ 健身
✓ 游泳
```

本周所有已绑定标签的有效专注时长求和。

## 5.3 与待办专注的关系

一次专注记录可以同时关联：

* 一个具体待办；
* 一个专注标签。

例如：

```text
关联待办：完成课程实验报告
专注标签：学习
专注时长：40 分钟
```

该记录同时：

* 作为实验报告的投入时间；
* 计入“每天学习 2 小时”的习惯目标。

底层仍然只有一条专注记录。

## 5.4 有效时长

习惯统计应读取专注记录的有效时长：

```text
有效时长 = 结束时间 - 开始时间 - 暂停时长
```

项目数据库已保存专注暂停总时长和暂停区间，可以据此避免将暂停时间计入习惯。

建议默认只统计：

* 已正常结束的专注；
* 未被逻辑删除的记录；
* 不处于冲突状态的最终版本；
* 用户手动确认保留的补录记录。

被取消且持续时间过短的专注不计入。

## 5.5 习惯卡片操作

```text
📖 阅读
今日 22 / 30 分钟

[开始专注] [查看记录]
```

点击“开始专注”：

1. 打开现有专注页面；
2. 自动选中绑定标签；
3. 默认时长为剩余目标时长或用户设置的常用时长；
4. 用户仍可修改时长。

---

# 六、数量型习惯

## 6.1 基本定义

数量型习惯需要一天内多次增加数量，因此不能使用循环待办表达。

典型场景：

* 喝水 2000 ml；
* 俯卧撑 30 个；
* 背单词 50 个；
* 每天走 10000 步；
* 每天吃 5 份蔬菜水果。

## 6.2 打卡方式

喝水示例：

```text
💧 喝水
1250 / 2000 ml

[+200] [+250] [+500] [自定义]
```

每次操作生成独立打卡事件：

```text
08:30  +250 ml
10:45  +300 ml
13:20  +500 ml
```

当日进度为所有有效事件之和。

## 6.3 快捷数值

用户可设置最多 4 个快捷值。

默认模板：

| 习惯  | 默认快捷值                |
| --- | -------------------- |
| 喝水  | 200、250、300、500 ml   |
| 俯卧撑 | 5、10、15、20 个         |
| 背单词 | 10、20、30、50 个        |
| 步数  | 500、1000、2000、5000 步 |

## 6.4 撤销与编辑

快速打卡后显示：

> 已记录喝水 250 ml　撤销

用户可以在当日记录列表中：

* 修改数量；
* 修改时间；
* 添加备注；
* 删除记录。

删除采用逻辑删除，以支持多设备同步。

---

# 七、时间点型习惯

## 7.1 基本定义

时间点型习惯记录某件行为的实际发生时间，并判断其是否满足目标。

典型场景：

* 07:30 前起床；
* 23:30 前上床；
* 12:30 前吃午饭；
* 18:00 后不喝咖啡；
* 每天固定时间测量体重。

## 7.2 早起示例

目标：

```text
每天 07:30 前起床
```

用户在 07:18 打卡：

```text
今日起床：07:18
比目标早 12 分钟
状态：已达标
```

用户在 08:05 打卡：

```text
今日起床：08:05
比目标晚 35 分钟
状态：已记录，未达标
```

## 7.3 早睡语义

第一版使用：

> 上床时间
> 准备睡觉时间

不使用“入睡时间”，因为没有健康设备数据时，应用无法判断用户真实入睡时间。

## 7.4 补录时间

用户晚上或第二天可以补录：

```text
实际起床时间：07:20
记录时间：09:10
```

习惯达标判断使用实际发生时间，而不是打卡按钮点击时间。

---

# 八、日期归属规则

## 8.1 逻辑日期

对于早睡等跨午夜习惯，不能直接使用自然日。

每个习惯可设置一个日期分界时间：

```text
dayBoundaryMinute
```

默认值：

| 习惯   | 日期分界  |
| ---- | ----- |
| 普通习惯 | 00:00 |
| 早睡   | 04:00 |
| 夜班习惯 | 用户自定义 |

逻辑日期计算：

```text
逻辑日期 = 实际本地时间减去日期分界时长后的日期
```

早睡习惯日期分界为 04:00 时：

```text
7 月 31 日 23:30 → 7 月 31 日
8 月 1 日 00:40 → 7 月 31 日
8 月 1 日 04:20 → 8 月 1 日
```

## 8.2 时区处理

打卡记录保存：

* UTC 时间；
* 当时的时区偏移；
* 已计算出的逻辑日期。

用户旅行或切换时区后，历史打卡不应自动移动到其他日期。

---

# 九、目标周期

支持以下周期：

```text
每天
每周
指定星期
每月
自定义周期
```

## 9.1 每日目标

示例：

* 每天喝水 2000 ml；
* 每天阅读 30 分钟；
* 每天 07:30 前起床。

## 9.2 每周累计目标

示例：

* 每周运动 150 分钟；
* 每周阅读 5 小时；
* 每周完成 3 次健身。

## 9.3 指定星期

示例：

* 周一至周五早起；
* 周一、周三、周五运动；
* 每周日整理房间。

非计划日：

* 不算达标；
* 不算未达标；
* 不增加连续；
* 不打断连续。

---

# 十、目标规则版本

用户可能修改目标：

```text
7 月：每天喝水 2000 ml
8 月：每天喝水 2500 ml
```

如果直接覆盖目标，历史统计会被新规则重新计算。

因此应保存目标规则版本：

```text
HabitGoal
└── HabitGoalRuleRevision
    ├── 2026-07-01 至 2026-07-31：2000 ml
    └── 2026-08-01 起：2500 ml
```

历史数据始终按照当时生效的目标判断。

修改目标时提供：

```text
新目标从何时生效？

● 从今天开始
○ 从下一个周期开始
○ 修改全部历史目标
```

默认选择“从今天开始”。

---

# 十一、页面设计

# 11.1 首页「今日习惯」

CountdownTodo 首页目前通过可配置的左右区域和可见性设置管理课程、待办、倒数日、屏幕时间、专注等模块，因此习惯应作为新的 `habits` 首页模块接入。

建议默认位置：

```text
课程
待办
今日习惯
专注
倒数日
```

卡片顶部：

```text
今日习惯                         3/5 达标
```

卡片内容：

```text
💧 喝水       1250/2000 ml       +250
🌅 早起       07:18              已达标
📖 阅读       22/30 分钟          开始
💪 俯卧撑     20/30 个            +10
🧹 整理桌面   未完成              完成
```

首页最多显示 5 个，底部提供：

> 查看全部习惯

# 11.2 习惯中心

侧边栏增加：

> 习惯中心

与现有的个人报告、时间日志和规划中心并列。

习惯中心包含三个标签。

## 今日

展示当前周期需要执行的习惯。

分组：

* 清晨；
* 白天；
* 晚间；
* 全天；
* 本周目标。

支持快速打卡和开始专注。

## 日历

使用月历展示每天状态：

| 状态   | 显示      |
| ---- | ------- |
| 达标   | 实心主题色   |
| 部分完成 | 浅色      |
| 未达标  | 错误色低透明度 |
| 非计划日 | 空白      |
| 跳过   | 灰色标记    |
| 未来日期 | 不显示状态   |

所有颜色从 Material 3 `ColorScheme` 获取，不直接写死普通颜色，以符合当前项目 UI 规范。

## 分析

展示：

* 当前连续达标；
* 最长连续达标；
* 近 7 天完成率；
* 近 30 天完成率；
* 本周进度；
* 月度趋势；
* 平均数量；
* 平均时长；
* 平均起床时间；
* 准时率；
* 最容易中断的星期。

---

# 十二、新建习惯流程

## 第一步：选择模板

推荐模板：

```text
每日喝水
早起
早睡
俯卧撑
每日阅读
每周运动
每日学习
冥想
吃维生素
整理桌面
自定义
```

## 第二步：选择类型

```text
完成一次
累计数量
累计时长
记录时间
```

模板会自动选择推荐类型。

## 第三步：设置目标

根据类型显示不同选项。

### 完成型

```text
重复规则
提醒时间
首页显示位置
```

### 时长型

```text
目标时长
统计周期
绑定专注标签
开始专注时的默认时长
```

### 数量型

```text
目标数量
单位
快捷增加值
```

### 时间点型

```text
目标时间
目标是“之前”还是“之后”
允许范围
日期分界时间
```

## 第四步：设置提醒

```text
固定提醒
进度提醒
临近结束提醒
当日汇总提醒
```

---

# 十三、数据模型

建议新增三类核心实体。

# 13.1 HabitGoal

表示习惯的身份、来源和展示设置。

```dart
enum HabitSourceType {
  recurringTodo,
  pomodoroTag,
  quantityCheckIn,
  timeCheckIn,
  durationCheckIn,
}
```

其中 `durationCheckIn` 使用独立打卡事件累计秒数，睡眠时长习惯可由早睡与早起时间点自动配对生成，用户编辑后保留手动修正。

建议字段：

```text
uuid
name
icon
source_type
source_ids
current_rule_uuid

display_mode
default_focus_minutes
sort_order
is_archived
is_deleted

version
device_id
created_at
updated_at

has_conflict
conflict_data
```

说明：

* `source_ids` 使用 JSON 数组（服务端原样存储字符串，客户端负责解析）；
* 完成型保存一个 `recurrenceSeriesId`；
* 时长型可保存多个 `PomodoroTag UUID`；
* 数量型和时间点型可以为空；
* `default_focus_minutes`（V37 新增）：时长型点击「开始专注」时的默认专注时长（分钟），为空时使用专注设置默认值。

# 13.2 HabitGoalRuleRevision

表示某个时间段内有效的目标规则。

```text
uuid
habit_uuid

effective_from_date
effective_to_date

period_type
weekdays_mask
target_value
unit

target_time_minute
time_comparison
time_tolerance_minutes

day_boundary_minute
quick_values_json

reminder_policy_json

is_deleted
version
device_id
created_at
updated_at

has_conflict
conflict_data
```

与 `HabitGoal` 一样遵循同步模型：`version` 并发控制、`device_id` 溯源、逻辑删除，以及 `has_conflict`/`conflict_data` 冲突快照（V38 起支持，两台设备同时修改同一规则版本时进入冲突收件箱）。

# 13.3 HabitCheckIn

只用于数量型和时间点型。

```text
uuid
habit_uuid
rule_revision_uuid

occurred_at
logical_date
timezone_offset_minutes

value
note
source
dedupe_key

is_deleted
version
device_id
created_at
updated_at
```

`source`：

```text
manual
notification
widget
import
health
wearable
```

---

# 十四、本地数据库

当前 SQLite 架构版本为 35，因此习惯模块首次落库建议升级至 **V36**。

新增表：

```sql
CREATE TABLE habit_goals (...);
CREATE TABLE habit_goal_rule_revisions (...);
CREATE TABLE habit_checkins (...);
```

建议索引：

```sql
CREATE INDEX idx_habit_goals_active
ON habit_goals(is_deleted, is_archived, sort_order);

CREATE INDEX idx_habit_rules_effective
ON habit_goal_rule_revisions(habit_uuid, effective_from_date);

CREATE INDEX idx_habit_checkins_day
ON habit_checkins(habit_uuid, logical_date, is_deleted);

CREATE INDEX idx_habit_checkins_updated
ON habit_checkins(updated_at);

CREATE UNIQUE INDEX idx_habit_checkins_dedupe
ON habit_checkins(dedupe_key)
WHERE dedupe_key IS NOT NULL;
```

`database_schema_history.dart` 增加：

```text
V36 习惯追踪

- 新增习惯目标表；
- 新增习惯规则版本表；
- 新增数量型和时间点型打卡记录表；
- 增加习惯日期与同步索引。
```

---

# 十五、代码结构

建议使用独立 Feature 目录。

```text
lib/
  features/
    habits/
      models/
        habit_goal.dart
        habit_goal_rule.dart
        habit_checkin.dart
        habit_progress.dart

      screens/
        habit_center_screen.dart
        habit_edit_screen.dart
        habit_detail_screen.dart
        habit_history_screen.dart

      widgets/
        habit_today_section.dart
        habit_card.dart
        habit_quick_checkin_sheet.dart
        habit_calendar.dart
        habit_analysis_panel.dart

      services/
        habit_progress_calculator.dart
        habit_rule_resolver.dart
        habit_streak_service.dart
        habit_reminder_service.dart
        habit_source_resolver.dart

      repositories/
        habit_repository.dart

  services/
    storage/
      habit_storage.dart
```

当前 `StorageService` 是主要数据编排门面，并正在逐步拆分具体职责，因此习惯 SQL 和业务查询应放在独立 `HabitStorage` 和 `HabitRepository` 中，`StorageService` 只保留兼容门面。

门面方法：

```dart
getHabitGoals()
saveHabitGoals()

getHabitRules()
saveHabitRules()

getHabitCheckIns()
saveHabitCheckIns()
```

---

# 十六、统一进度计算

新增：

```text
HabitProgressCalculator
```

入口：

```dart
Future<HabitProgress> calculate({
  required HabitGoal habit,
  required DateTime period,
});
```

根据 `sourceType` 分派。

## 完成型

读取：

```text
TodoItem
recurrenceSeriesId
isDone
isDeleted
dueDate
createdDate
```

## 时长型

读取：

```text
PomodoroRecord
tagId
startTime
endTime
pauseDuration
isDeleted
```

## 数量型

读取：

```text
HabitCheckIn.value
```

累计求和。

## 时间点型

读取当天有效记录，按规则判断：

```text
实际时间 <= 目标时间
实际时间 >= 目标时间
实际时间落在目标区间内
```

返回：

```text
currentValue
targetValue
completionRatio
hasRecord
goalMet
onTime
firstRecordAt
lastRecordAt
```

---

# 十七、连续达标规则

## 每日习惯

* 计划日达标：连续天数加一；
* 计划日未达标：连续中断；
* 非计划日：不增加，也不中断；
* 未来日期：不参与；
* 跳过：默认不增加，也不中断。

## 每周习惯

显示：

```text
连续 4 周达标
```

而不是按天计算。

## 当天尚未结束

当天尚未到目标结束时间时，不应提前判定失败。

例如：

* 每天喝水 2000 ml；
* 当前 14:00；
* 只喝了 1000 ml。

状态是：

> 进行中

而不是：

> 未达标

当天结束后才进入未达标统计。

---

# 十八、提醒设计

## 18.1 完成型提醒

直接复用循环待办现有提醒，不再重复注册习惯通知。

## 18.2 时长型提醒

习惯模块只负责目标提醒，例如：

> 今天还需阅读 20 分钟，点击开始专注。

点击后进入现有专注页面，并自动选择标签。

专注结束通知继续由原有专注功能负责。

## 18.3 数量型提醒

支持：

### 固定提醒

```text
10:00 记得喝水
14:00 今日已喝 800/2000 ml
18:00 还差 700 ml
```

### 进度提醒

根据当前完成比例动态生成：

> 今日俯卧撑 20/30 个，还差 10 个。

达到目标后取消当天剩余提醒。

## 18.4 时间点型提醒

早睡示例：

```text
23:00 距离目标上床时间还有 30 分钟
23:25 早睡目标即将到达
```

## 18.5 通知 ID

当前提醒调度已经使用待办、课程、特殊待办、规划块和固定日程的 ID 区间，固定日程区间最高使用到 41999。

建议预留：

```text
42001～49999：习惯目标提醒
```

ID 不使用列表下标，而使用：

```text
habitUuid + reminderSlot + logicalDate
```

生成稳定哈希。

---

# 十九、多设备同步

习惯目标和打卡需要接入现有 `/api/sync` 增量同步。

当前服务端同步协议会分别读取待办、倒数日、时间日志、规划块、固定日程等实体，因此习惯需要作为新的实体集合接入。

请求增加：

```json
{
  "habit_goals_changes": [],
  "habit_goal_rules_changes": [],
  "habit_checkins_changes": []
}
```

响应增加：

```json
{
  "server_habit_goals": [],
  "server_habit_goal_rules": [],
  "server_habit_checkins": [],
  "sync_capabilities": {
    "habits": 1
  }
}
```

## 19.1 目标冲突

`HabitGoal` 和 `HabitGoalRuleRevision` 使用现有的：

* UUID；
* version；
* updatedAt；
* deviceId；
* 逻辑删除；
* 冲突快照。

两台设备同时修改目标或同一规则版本时（version 相同且内容不同），服务端写入
`has_conflict=1` + `conflict_data` 快照并进入冲突收件箱；本地合并时时间路径
排除冲突项，避免冲突快照覆盖本地更新的内容。

冲突收件箱支持习惯目标与规则：

* 展示项：`habit_goals`、`habit_goal_rule_revisions`（有 `has_conflict` 且未删除）；
* 解析：`/api/sync/resolve_conflict` 支持两表（`keep_local` 写入本地内容并清除标记、
  `accept_server` 提升版本并清除标记，冲突快照经 `compactSnapshot` 完整落盘）；
* 本地解析：`StorageService.resolveConflictLocally` 支持两表，`keep_local` 生成
  oplog 回传，`accept_server` 下次同步拉取服务器版本。

## 19.2 打卡合并

打卡记录使用事件合并，不能按整日进度覆盖。

例如：

```text
手机：喝水 +250 ml
电脑：喝水 +300 ml
```

同步后必须得到：

```text
550 ml
```

不能由最后上传的设备覆盖。

合并原则：

* 不同 UUID 的打卡全部保留；
* 同一 UUID 按版本更新（严格 LWW）；
* 删除使用墓碑；
* `dedupeKey` 防止通知按钮重复提交；
* 每日进度不参与同步，由客户端重新计算。

打卡不做冲突快照（事件模型天然可合并，冲突概率低且覆盖会丢数据）。

## 19.3 协议约定

* 习惯数据不设专属 CRUD 路由，统一走 `/api/sync` 增量同步
  （`habit_goals_changes` / `habit_goal_rules_changes` / `habit_checkins_changes`）；
* `source_ids`、`quick_values_json`、`reminder_policy_json` 等服务端原样存储
  并原样返回 JSON 字符串，由客户端解析，保证协议自洽；
* 首次与声明 `habits=1` 的服务端握手前，客户端全量携带本地习惯数据
  （`habit_full_sync`），避免旧版本未写 oplog 的数据漏传。

---

# 二十、小组件设计

当前 `WidgetSnapshot` 已传递倒数日、待办、课程、专注和循环待办等内容，习惯可以作为新字段加入，并为旧数据提供默认空列表。

新增：

```dart
class WidgetHabitItem {
  String habitId;
  String title;
  String icon;

  String sourceType;
  double currentValue;
  double targetValue;
  String unit;

  bool goalMet;
  List<double> quickValues;
}
```

第一阶段：

* 只展示今日习惯进度；
* 点击打开应用。

第二阶段：

* Android/macOS 支持快捷打卡；
* 喝水可直接 `+250 ml`；
* 完成型可直接完成；
* 时长型可直接开始专注。

---

# 二十一、时间轴和个人报告

## 21.1 时间轴

新增事件：

```text
habitCreated
habitGoalReached
habitStreakMilestone
habitRuleChanged
```

不建议每次喝水都写入主时间轴，否则信息过多。

默认只记录：

* 当天首次打卡；
* 当天达标；
* 连续 7、30、100 天；
* 目标修改。

具体喝水记录保留在习惯详情页。

## 21.2 个人报告

增加：

* 本周习惯完成率；
* 本月最稳定习惯；
* 最容易中断的习惯；
* 平均起床时间；
* 平均上床时间；
* 专注习惯达标率；
* 喝水或运动趋势；
* 连续坚持里程碑。

---

# 二十二、第一版功能范围

## 必须完成

* 完成型习惯绑定循环待办；
* 时长型习惯绑定专注标签；
* 数量型习惯多次打卡；
* 时间点型习惯记录实际时间；
* 今日习惯模块；
* 习惯中心；
* 连续天数；
* 近 7 天、30 天完成率；
* 固定提醒；
* 目标规则版本；
* 本地数据库；
* 多设备同步。

## 暂缓

* 团队监督；
* 好友排行榜；
* 习惯社区；
* HealthKit；
* Health Connect；
* 自动读取手表睡眠；
* 自动同步步数；
* AI 自动调整目标；
* 成就商城；
* 复杂负向习惯追踪。

---

# 二十三、开发阶段拆分

## PR 1：基础模型和数据库

* HabitGoal；
* HabitGoalRuleRevision；
* HabitCheckIn；
* SQLite V36；
* Repository；
* 规则解析测试。

## PR 2：进度计算

* 完成型读取循环待办；
* 时长型读取专注标签；
* 数量型累计；
* 时间点型判断；
* 连续达标；
* 周期统计。

## PR 3：基础界面

* 习惯中心；
* 新建习惯；
* 今日习惯卡片；
* 快速打卡；
* 习惯详情；
* 首页模块配置。

## PR 4：提醒

* HabitReminderService；
* 数量型提醒；
* 时间点型提醒；
* 时长目标提醒；
* 达标后取消提醒；
* 通知跳转。

## PR 5：云同步

* 客户端同步 Payload；
* CDT-server debug 数据表；
* `/api/sync` 支持；
* 事件合并；
* 冲突处理；
* WebSocket 刷新。

## PR 6：系统整合

* 个人报告；
* 时间轴；
* 小组件；
* 通知快捷操作；
* AI 助手上下文。

---

# 二十四、验收标准

## 完成型

* 循环待办完成后习惯立即达标；
* 在习惯页面完成后待办同步完成；
* 不生成重复待办；
* 非计划日不影响连续天数。

## 时长型

* 对应标签的专注时长正确累计；
* 暂停时间不计入；
* 多标签累计正确；
* 与具体待办关联的专注不会重复统计；
* 跨设备专注记录同步后进度一致。

## 数量型

* 多次打卡正确求和；
* 可撤销、编辑和删除；
* 两台设备分别打卡后正确合并；
* 达标后剩余提醒被取消。

## 时间点型

* 实际时间和记录时间分开；
* 凌晨早睡记录正确归入前一天；
* 补录时间正确；
* 打卡但未准时不会错误增加连续达标。

## 目标修改

* 修改目标不会改变历史完成率；
* 新规则从指定日期生效；
* 多设备目标冲突可识别。

---

# 二十五、最终架构结论

习惯中心不是一套新的待办系统，也不是一套新的计时系统。

其底层结构应为：

```text
HabitGoal
├── recurringTodo
│   └── 使用现有循环待办实例判断完成
│
├── pomodoroTag
│   └── 使用现有专注记录累计时长
│
├── quantityCheckIn
│   └── 使用新增打卡事件累计数量
│
└── timeCheckIn
    └── 使用新增打卡事件记录实际时间
```

这样可以最大限度复用 CountdownTodo 已有功能，同时补齐现有系统无法表达的数量累计、实际时间追踪、目标统计和连续坚持能力。

第一版真正新增的核心能力只有：

1. 习惯目标聚合；
2. 目标规则版本；
3. 数量和时间点打卡事件；
4. 统一进度计算；
5. 习惯视图与统计；
6. 习惯提醒与同步。

该方案避免重复建设，并能与当前待办、专注、时间轴、个人报告和小组件形成统一的数据体系。
