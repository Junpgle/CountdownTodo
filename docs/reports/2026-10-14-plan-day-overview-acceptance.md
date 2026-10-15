# 第十五轮验收：规划首页真实概览与明细直达

复验日期：2026-10-14（北京时间）。用户已批准本轮完整方案。实现、相关回归、静态分析、正式Web release构建及合成数据浏览器检查已完成，**技术验收通过，用户于2026-10-14确认通过并要求准备第十六轮方案**。

## 交付结果

- 规划首页顶部改为真实规划、有效专注、已结束完成、时间日志，四项与原复盘共用聚合规则。取消／跳过不进入预算；缓存不补入实际，80%投入不在展示层推断完成，未绑定规划的有效专注计入总量。
- 每项数字直达所选日期的对应分页明细，待核对标记直达问题记录；更多菜单的规划统计继承选择日期、读取服务和时钟。返回保留日期。
- 轻量概览仅读取四个聚合结果，不查询趋势、排行或完整记录列表；与完整复盘共用同一读取事务规则和SQL判定。
- 概览加载、更新和失败独立于时间轴。局部重试不调用原日历维护路径；切日期／账号／成员、离页、后台及旧响应有保护，隐藏页面停刷，过期边界最多补刷一次。
- 普通宽度四项紧凑排列；窄屏、大字体或数字过长时改为「当日概览 · 查看」，不截断数字，不增加日历滚动。
- 时间轴保留三类图例与相交区间列表，入口改名「时间轴记录」。移除旧的投入／计划比例角标；标题、时段、状态、拖选、移动、缩放及撤销保留。
- 原日历加载的漏做维护和专注完成状态转换没有改变；没有新增数据库迁移、依赖、后端接口、权限、日历写入或历史数据修改。

## 规则复核

| 场景 | 验收结果 |
| --- | --- |
| 缓存大于实际、80%投入但状态未完成 | 实际只取核实记录，完成只认已结束的真实finished状态 |
| 同一专注与两个同待办规划重叠 | 秒数总量只计一次，归属竞争列入待核对 |
| 两条40秒自由专注 | 合计80秒，显示1分20秒，未逐条截成零分钟 |
| 取消／跳过和未来规划 | 取消／跳过不计预算，未结束不计已结束分母 |
| 缺失旧实际时长、零秒、坏值或冲突 | 零秒保留；无法核实的记录待核对，不用计划时长补值 |
| 跨午夜专注与日志 | 专注完整秒数只归开始日；日志裁剪所选日交集，二者不合并成工作量 |
| 夏令时整日日志 | 纽约23／25小时、Lord Howe半小时变化日期按真实秒数计；下一日专注不混入前一日 |
| 来源与记录列表 | 课程仍在时间轴显示，但不伪造为真实规划；时间轴记录按相交区间，概览专注按开始日 |

## 测试和构建证据

Flutter命令在独立副本 `/tmp/countdown-plan-diagnostics-verification` 执行；本轮证据目录为项目忽略目录 `/Users/junpgle/StudioProjects/CountdownTodo/.dart_tool/plan_day_overview_acceptance/`。

| 检查 | 实际结果与日志 |
| --- | --- |
| 47个规划、估时、草稿、复盘和相关回归文件 | 788项整批通过，101秒；`regression-final.log` |
| 统计菜单衔接追加复验 | 66项界面、复盘、实际记录及拖动撤销通过；`navigation-final.log`。同时断言继承日期、时钟和读取服务 |
| 纽约时区专项 | 35项通过；`dst-new-york.log` |
| Lord Howe时区专项 | 35项通过；`dst-lord-howe.log` |
| 本轮不同测试总数 | 789项分批通过：整批788项后增加1项DST整日裁剪用例；重复复验与换时区不累加 |
| 概览界面专项 | 20项通过；`overview-lifecycle-final.log`，后续包含在整批及66项复验中 |
| 相关静态分析 | 四个实现文件、四个测试文件及合成预览无问题；`analyzer-final.log` |
| 只读与查询范围 | 概览常规读取三次结构检查、四次聚合查询；无排行／趋势列表，`total_changes()`不变。局部重试及取消新建零业务写入 |
| 正式Web release构建 | 成功，44.8秒；`formal-build.log`，产物 `/tmp/countdown-plan-day-overview-formal-web` |
| 隔离合成预览Web release构建 | 最终成功，30.3秒；`preview-build-final.log`，产物 `/tmp/countdown-plan-day-overview-preview-web` |
| 空白检查 | `git diff --check`通过，仅作为空白证据 |

测试覆盖快速切日、旧响应、成员切换、后台／恢复、离页迟到、被其他页面覆盖、同日期更新期间禁用旧点击、过期边界不循环查询、各指标与待核对导航、数字过长简化、失败时实际拖选新建和取消、原拖动缩放／回弹／撤销及已开始保护。

首轮失败未算作通过证据：合成日志缺少必填device_id／team_uuid；待核对期望遗漏了两项已结束但状态仍待确认的规划；旧拖动断言依赖旧60m文案，现改查真实数据库分钟数；隐藏页面更新动画未停，现随可见性暂停。修正后整批回归通过。一次最终复验因自动审批服务额度不足未执行，恢复后通过正常审批继续，无绕过审批。统计菜单继承时钟／服务及DST追加用例在整批之后单独复验通过。两份测试源后续仅有格式调整，已核对未改变测试内容并同步验证副本。

主要命令如下（日志重定向省略）：

```bash
/Users/junpgle/develop/flutter/bin/flutter test --no-pub $(cat /Users/junpgle/StudioProjects/CountdownTodo/.dart_tool/plan_day_overview_acceptance/regression-files.txt) --reporter expanded
/Users/junpgle/develop/flutter/bin/flutter test --no-pub test/widgets/plan_day_overview_test.dart test/widgets/plan_review_screen_test.dart test/widgets/plan_execution_view_test.dart test/widgets/plan_drag_undo_test.dart --reporter expanded
TZ=America/New_York /Users/junpgle/develop/flutter/bin/flutter test --no-pub test/services/plan_review_repository_test.dart --reporter expanded
TZ=Australia/Lord_Howe /Users/junpgle/develop/flutter/bin/flutter test --no-pub test/services/plan_review_repository_test.dart --reporter expanded
/Users/junpgle/develop/flutter/bin/cache/dart-sdk/bin/dart analyze lib/services/plan_review_repository.dart lib/widgets/plan_day_overview.dart lib/screens/todo_plan_screen.dart lib/widgets/plan_execution_view.dart test/services/plan_review_repository_test.dart test/widgets/plan_day_overview_test.dart test/widgets/plan_execution_view_test.dart test/widgets/plan_drag_undo_test.dart .dart_tool/plan_day_overview_preview.dart
/Users/junpgle/develop/flutter/bin/flutter build web --release --no-pub --no-wasm-dry-run --no-web-resources-cdn --output /tmp/countdown-plan-day-overview-formal-web
/Users/junpgle/develop/flutter/bin/flutter build web --release --no-pub --no-wasm-dry-run --no-web-resources-cdn -t .dart_tool/plan_day_overview_preview.dart --output /tmp/countdown-plan-day-overview-preview-web
git -c core.fsmonitor=false diff --check
```

## 浏览器验收

使用独立合成账号与SQLite，冻结样本日期2026-10-13、时钟13:00，复用真实页面与仓库，不访问真实用户业务数据。样本含已完成、48分钟投入仍待完成、未来和取消的四份规划，一节课程，48分钟专注与两条40秒自由专注，以及30分钟日志和跨午夜日志。

1. 390×844普通字体：首页为真实规划3小时、有效专注49分20秒、已结束完成1/2、日志40分钟。取消规划和原99999秒累计缓存没有污染数字。
2. 点击有效专注进入同日三条记录；48分钟＋40秒＋40秒与总量对账。日志明细为30分钟＋当天裁剪10分钟，与40分钟对账。
3. 从更多菜单打开完整复盘，日期仍为10月13日，四项数字完全一致。待核对标记打开一项已结束但状态仍待确认的规划，未擅自完成它。
4. 注入一次概览读取失败，仅顶部出现局部错误；时间轴仍可操作并打开新建页，取消未新增规划。单独点击重试后恢复四项数字。
5. 320×700、1.8倍字体、深色玻璃：首页改为概览入口，进入复盘仍为原日期；没有横向溢出，00—23小时仍在一屏。720×360横屏及1280×900桌面检查也完成，短横屏时间轴较密集，沿用原一屏布局。
6. 切到10月14日空样本后，正确显示零值和暂无已结束规划，不沿用13日数字；切回恢复正确指标。查看和取消后合成数据库仍四份规划、零操作记录。
7. 最终来源18982控制台错误／警告为零，记录在`browser-console.json`的`finalLogs`。初次来源18981的预览初始化错误另存于过程日志：合成脚本应使用`toDbJson`处理旧SQLite非空字段，已修正；不把初次白屏当作通过。

截图共11张。临时浏览器尺寸已恢复，独立验收标签页保留。四个实现、四个相关测试及预览共9文件已核对与验证副本一致，指纹留存于`source-sha256.json`。

## 验收范围与限制

本轮没有运行全仓Flutter测试／全仓分析、原生Android／iOS／macOS真机、真实手机日历、多设备同步或Wasm验收。Web与模拟数据库证据不替代这些检查。新概览读取只读，但原规划页加载仍有已有漏做状态维护，不能将整个页面宣称为零写入。

本次未执行提交、推送、发布或部署；共享工作区其他任务的编辑与提交不属于本次操作。用户已确认第十五轮通过，接下来仅准备第十六轮方案，批准后实施。

## 最终界面

![手机概览与全天时间轴](/Users/junpgle/StudioProjects/CountdownTodo/.dart_tool/plan_day_overview_acceptance/01-mobile-overview.png)

![同日完整复盘对账](/Users/junpgle/StudioProjects/CountdownTodo/.dart_tool/plan_day_overview_acceptance/04-review-comparison.png)

![局部读取故障](/Users/junpgle/StudioProjects/CountdownTodo/.dart_tool/plan_day_overview_acceptance/06-local-error.png)

![深色大字体简化入口](/Users/junpgle/StudioProjects/CountdownTodo/.dart_tool/plan_day_overview_acceptance/08-dark-large-font.png)

![桌面概览](/Users/junpgle/StudioProjects/CountdownTodo/.dart_tool/plan_day_overview_acceptance/10-desktop.png)
