# 第十四轮验收：无可用时段诊断与跨日查找

日期：2026-10-13。用户已批准完整方案。功能逻辑验收已完成。根据用户追加意见，正在优化新建规划、查找说明和跨日结果三处 UI；以本报告后续补充的新版截图与复验结果作为最终交付。

## 交付内容

- 查询成功但无足够长的连续时段时，主编辑页增加最长片段、碎片总分钟和「查看原因与其他日期」入口；错误、损坏规则或失效任务不会伪装成空闲统计。
- 独立说明页显示当前条件、来源覆盖、最多三个最长片段及按需展开的计算明细。短片段仅供参考，不可采用，也不把碎片总量当作完整分段方案。
- 计算明细按窗口、当前时刻及截止、周规则、避让、真实占用并集、缓冲与整分钟裁剪的顺序显示剩余分钟。重叠只扣一次；推荐和说明共用同一套区间计算。
- 主动点击后查找原选日期下一日起的最多7个本地自然日，受截止限制。最多五个完整连续候选，优先覆盖不同日期，再补入较早候选。逐日沿用时长、窗口、周规则、避让、缓冲、日历模式和被改期规划UUID。
- 原日期诊断与后续候选共用一次批量来源读取；读取包括原日期、后续搜索日期及边界缓冲，候选仍仅来自后续最多7天。不会逐日全量读取或后台预查。
- 采用先检查最新时段、偏好及任务，之后回填原编辑器的日期和时间；备注、番茄和提醒保留。查看、取消及采用均不写正式规划，显式保存继续走原事务复核。
- 新结果与错误自动滚到可见位置，避免窄屏点击后看不到反馈。主编辑页保持两个候选、自定义默认五个，全天时间轴和拖动保持原行为。
- 支持从说明页返回原条件或进入已有分段安排，包含嵌套自定义弹窗的返回衔接。一次性豁免沿用本次选择，不改写全局设置。
- 账号、独立协作成员、条件、请求序号、父草稿版本、前台恢复与数据刷新使旧结果失效。数据刷新后重新查出的候选，按真实输入和草稿版本复核后可以正常返回，不把单纯请求序号变化当作草稿变更。日历覆盖不可静默降级，截止在读取或采用期间变化会被复核拦截。
- 草稿只保留最终采用的普通单段查询和时间，沿用原规则指纹与恢复复核，不缓存7天来源快照。不新增依赖、数据库迁移、后端接口或系统权限。

## 测试证据

在独立副本 `/tmp/countdown-plan-diagnostics-verification` 运行，避免共享工作区其他构建干扰测试资源。相关源文件与测试SHA-256留存在证据目录，并核对与工作区一致。

| 检查 | 当前结果 |
| --- | --- |
| 46个规划、估时及相关测试文件 | 762项不同测试分批通过：先760项整批通过，顶部对齐修正38项通过，刷新采用修正117项通过（含2项新增）；重复项不累加 |
| 旧推荐算法等价性 | 固定种子300组日程比较候选起止和顺序，包含重叠、避让、周规则和非对称缓冲 |
| 诊断与跨日专项 | 片段45＋45／需75、精确长度、秒级边界、截止、周规则状态、合并统计、跨月跨年、最多五个及日期分散 |
| SQLite与日历模拟 | 一次范围读取、边界缓冲、跨天手机日历排除、显式应用内模式、截止变化、完成状态、新占用、账号、规则变化及一次正式保存 |
| Widget正式流程 | 手机／横屏／桌面、大字体深色、取消、失败、旧响应、成员切换、覆盖变化、嵌套自定义、分段入口、四类编辑器采用、真实保存保留备注 |
| 纽约时区实跑 | `TZ=America/New_York` 46项通过，含自然周与缺失／重复边界 |
| Lord Howe时区实跑 | `TZ=Australia/Lord_Howe` 23项通过，验证半小时夏令时与真实持续分钟；重复实跑不累加总测试数 |
| 相关静态分析 | 7个实现文件与3个专项测试文件无问题；验收预览单独分析无问题 |
| 空白检查 | `git diff --check`通过，仅作为空白证据 |
| 正式Web release构建 | 最终成功，38.7秒，日志`formal-web-build-final.log` |
| 隔离验收预览Web release构建 | 最终成功，26.6秒，日志`preview-web-build-final.log` |
| 保存字段复核 | 正式编辑器SQLite测试再次通过，保存行保留备注、番茄时长和提前提醒；不重复累加总数 |

过程中的失败没有算作通过证据：初次Widget测试修正了懒加载结果断言、滚动后的点击时机和测试SQLite初始化位置；随后专项通过。第一批大回归747项通过、1项失败，原因是新增纽约冬令时测试在本地时区硬编码169小时；现按实际时区偏移计算期望，并在纽约时区实跑，最终整批通过。此前一次命令因自动审批服务额度不足未执行，恢复后通过正常审批继续，没有绕过检查。

主要执行命令如下，Flutter命令在上述隔离副本执行，日志重定向省略。相关静态分析在工作区执行，完整7个实现文件及3个专项文件清单见`analyzer-final.log`首行；保存字段增补断言后单独分析新测试文件也无问题。

```bash
/Users/junpgle/develop/flutter/bin/flutter test --no-pub $(cat /Users/junpgle/StudioProjects/CountdownTodo/.dart_tool/plan_diagnostics_acceptance/regression-files.txt) --reporter expanded
/Users/junpgle/develop/flutter/bin/flutter test --no-pub test/widgets/plan_availability_explanation_test.dart test/widgets/plan_availability_panel_test.dart test/widgets/plan_availability_buffers_test.dart test/widgets/plan_editor_drafts_test.dart test/widgets/plan_split_flow_test.dart test/widgets/plan_weekly_availability_test.dart --reporter expanded
/Users/junpgle/develop/flutter/bin/flutter test --no-pub test/widgets/plan_availability_explanation_test.dart --plain-name 'real editor fills next day, retains remark and saves exactly once' --reporter expanded
TZ=America/New_York /Users/junpgle/develop/flutter/bin/flutter test --no-pub test/services/plan_availability_diagnostics_test.dart test/services/plan_continuous_range_repository_test.dart test/services/plan_availability_repository_test.dart --reporter expanded
TZ=Australia/Lord_Howe /Users/junpgle/develop/flutter/bin/flutter test --no-pub test/services/plan_availability_diagnostics_test.dart test/services/plan_continuous_range_repository_test.dart --reporter expanded
/Users/junpgle/develop/flutter/bin/flutter build web --release --no-pub --no-wasm-dry-run --no-web-resources-cdn --output /tmp/countdown-plan-diagnostics-formal-web
/Users/junpgle/develop/flutter/bin/flutter build web --release --no-pub --no-wasm-dry-run --no-web-resources-cdn -t .dart_tool/plan_diagnostics_preview.dart --output /tmp/countdown-plan-diagnostics-preview-web
git -c core.fsmonitor=false diff --check
```

## 验收范围对应

1. 短片段参考与精确时长：纯计算测试、说明页与正式编辑器测试。
2. 重叠、缓冲、阶段统计及旧候选等价：纯计算测试及既有缓冲／分段回归。
3. 结束、截止、周规则各空态、规则损坏和读取失败：结构化原因测试、仓库与Widget测试。
4. 自然日、跨年、时区、秒级边界：定向计算／仓库测试和两个时区实跑。
5. 七天范围、截止裁剪、候选数量与排序：连续范围计算和SQLite测试。
6. 边界占用、跨天手机日历、未知来源与降级：现有来源回归、本轮日历模拟与覆盖保护。
7. 批量来源调用次数与完成结果：仓库调用次数断言，说明页按主动点击查询。
8. 首页待办、待规划、冲突改期、漏做恢复：正式编辑器Widget采用流程，单段真实SQLite保存；取消零写入。
9. 旧结果、成员切换与离页迟到：Widget测试、异步请求序号、父组件真实输入及草稿版本复核，已有连击保存回归。
10. 新占用、截止与规则变化、完成／失效、专注：本轮读与采用测试、原保存及专注守卫回归。
11. 单段、分段、缓冲、周规则、草稿、拖动和撤销：本轮46文件整批回归。
12. 响应式与实际可见效果：Widget覆盖手机／横屏／桌面；浏览器实际检查390×844、320×700且1.8倍字体深色玻璃、1280×900桌面，保存截图。横屏仅有Widget证据。

## 浏览器验收

预览使用独立合成账号、合成会议和冻结时钟，复用真实页面、查询仓库和SQLite保存，不访问真实账号业务数据。

首次手机预览已验证：所选10月13日有09:00–09:45和11:15–12:00两个45分钟片段，需连续75分钟，主页面显示最长45／总90，说明页片段仅供参考。点击后续7天后返回10月14日至20日五个75分钟候选，覆盖14／15／16／19／20日，周末不推荐被正确跳过。采用14日09:00–10:15后，原编辑器显示14日、75分钟和已选用；保存后合成数据库计数为规划1份、oplog1条、10/14 09:00。

截图检查发现短说明内容垂直居中、顶部留白过多，已改为顶部对齐，并补充手机／横屏／桌面内容起点断言。38项相关界面回归通过。后续还复现了数据刷新使父页过度拒绝新候选的问题，已用真实输入签名替代父页返回处的请求序号比较，并新增「刷新后新候选可采用」和「草稿变化仍拒绝」两项回归，117项相关界面检查通过。

最终构建在新的本地来源18976复验，排除旧Service Worker缓存。说明页已顶部对齐；跨日采用后，备注「跨日采用仍保留备注」、45分钟单轮番茄和提前10分钟提醒保留。显式保存后仍为正式规划1份、oplog1条、10/14 09:00。随后在深色大字体界面重新查询，14日候选变为10:15–11:30，正确避开刚保存的09:00–10:15。大字体操作按钮换行、计算明细可读，桌面Tab能移动焦点；最终控制台无错误或警告。浏览器临时尺寸已恢复。

## 证据及限制

日志、测试清单、源文件指纹和15张浏览器截图位于项目忽略目录 `.dart_tool/plan_diagnostics_acceptance/`；验收预览代码也位于忽略目录。最终相关文件与验证副本一致。正式构建位于`/tmp/countdown-plan-diagnostics-formal-web`，合成预览位于`/tmp/countdown-plan-diagnostics-preview-web`。

未进行原生Android／iOS／macOS真机、真实手机日历授权、多设备同步及Wasm验证；模拟日历与Web流程不能替代这些证据。未推送或发布。

## 最终界面证据

![手机说明页](/Users/junpgle/StudioProjects/CountdownTodo/.dart_tool/plan_diagnostics_acceptance/06-final-mobile-explanation.png)

![后续七天五个完整候选](/Users/junpgle/StudioProjects/CountdownTodo/.dart_tool/plan_diagnostics_acceptance/07-final-five-candidates.png)

![跨日后保留备注和设置](/Users/junpgle/StudioProjects/CountdownTodo/.dart_tool/plan_diagnostics_acceptance/08-final-retained-fields.png)

![深色大字体操作](/Users/junpgle/StudioProjects/CountdownTodo/.dart_tool/plan_diagnostics_acceptance/11-dark-large-font-actions.png)

![桌面说明页](/Users/junpgle/StudioProjects/CountdownTodo/.dart_tool/plan_diagnostics_acceptance/14-desktop-explanation.png)
