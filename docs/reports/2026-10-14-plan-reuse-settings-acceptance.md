# 第十六轮验收：照此新建规划

实施与界面验收：2026-10-14；最终复核：2026-10-15（北京时间）。用户已批准[完整方案](../proposals/2026-10-14-plan-reuse-settings.md)。**实现与技术验收通过，等待用户确认。**

## 交付行为

- 真实手动／AI规划的「更多操作」新增「照此新建」，读取最新已保存设置，进入整页新建。正在读取／保存或有未保存修改时不会重复打开或带入不确定内容。
- 沿用起止间隔的实际整分钟时长、备注、单轮番茄、轮数及提醒。历史规划默认今天，未来规划保留本地日期；两个新推荐直接可见，第一项自动填入，其他时段由现有自定义弹窗选择。
- 原待办按具体UUID和当前成员重新读取；完成、删除或冲突时选择留空，不能自动换成同名任务或另一重复期次。切换待办继续沿用配置和时长，估时作为参考，不能覆盖沿用时间。
- 新规划使用独立UUID、planned／manual状态、零实际投入和空专注／日历绑定。原规划参与既有占用规则，不通过excludeBlockId排除它。
- 已有有效安排时明确确认追加；保存前重读占用并在事务内检查身份、待办、截止及已有安排。无推荐时的手动参考时段也不能绕过检查。保存失败保留表单和目标UUID；不确定提交用相同UUID核对，矛盾目标不覆盖。
- 初次带入但未触摸也提供退出保护。可以主动暂存为reuse来源的本机草稿，恢复不依赖原规划继续存在，旧推荐／追加确认重新检查。旧来源恢复保持原行为。
- 继续沿用并排番茄／轮数／提醒、整页新建、现有缓冲／避让／周规则、跨日和分段。不新增模板库、依赖、迁移、权限或后端接口。全天规划时间轴继续在一屏内显示。

## 实现位置

| 文件 | 内容 |
| --- | --- |
| `lib/services/plan_reuse_repository.dart` | 独立不可变设置载荷、轻量原始行读取与严格校验、精确待办投影、目标UUID核对 |
| `lib/widgets/plan_block_editor_sheet.dart` | 真实菜单、整页复用、时长防覆盖、首次退出保护、追加确认、手动／推荐保存守卫 |
| `lib/services/plan_editor_draft_repository.dart` | 增加reuse来源白名单，兼容旧草稿 |
| `lib/screens/plan_editor_drafts_screen.dart` | 草稿详情说明来源 |
| 三份复用服务／组件测试、`.gitignore`及功能文档 | 新入口、字段隔离、异常、竞态、草稿及布局回归 |

仅使用白名单设置，不把原TodoPlanBlock作为新建block传入。非法原始时间、枚举、配置、同步冲突、映射／日历来源均拒绝复用，避免fromJson默认值掩盖坏数据；旧schema缺少可选冲突列可读，缺少必需配置列明确失败。

## 自动验证

验证副本位于`/tmp/countdown-plan-reuse-verification`。共享工作区存在并行修改，本轮仅同步相关文件；交付时7份实现／测试文件及预览源码指纹均与验证副本一致。其他并行功能不在本轮验收结论范围。

| 检查 | 实际结果 |
| --- | --- |
| 50份规划／估时／番茄绑定／AI规划相关测试 | **832项全部通过**，192秒；包含拖动、撤销、可用时间、缓冲、周规则、跨日、分段、清理、复盘与旧草稿 |
| 最终草稿来源处理后复验6份测试 | **102项全部通过**，30秒；不与832重复相加 |
| 追加实际重复点击读取中菜单后的复验 | **18项全部通过**，6秒；同一目标不重复打开，离页迟到不导航 |
| 10月15日共享弹层／玻璃更新后追加4份组件回归 | **53项全部通过**，6秒；含真实复用入口、保存、退出、草稿及基础组件；4份实现再次静态分析通过 |
| 4份实现、3份测试及合成预览静态分析 | **No issues found**；末次测试补充又单独分析通过 |
| 正式`lib/main.dart` Web release构建 | **通过**，136.5秒 |
| 合成预览 Web release构建 | **通过**，100.7秒；使用真实功能组件和保存服务 |
| `git diff --check` | **通过** |

832为50份相关测试本次运行结果；后续复验和共享组件补充按批次独立报告，不相加为一个总数，未用第十五轮结果代替。测试中的SQLite默认工厂提示来自隔离夹具，不是业务失败。

10月15日再次核对，本轮7份实现／测试及预览源码未发生变化。共享弹层、玻璃组件和日志组件有其他并行更新，已在验证副本同步并补充上述53项回归；原正式构建和截图仍对应10月14日记录的副本，不声明它们覆盖后续全部并行修改。

覆盖的重点包括：源带巨大缓存、旧专注ID和日历ID；具体UUID与成员完成覆盖；无效／删除源、原始坏状态和配置、旧schema；未完成选择留空；AI迟到不覆盖60分钟；源修改／删除不污染已带入设置；本机草稿恢复和固定目标UUID；保存失败同UUID重试；无推荐参考时段占用保护；追加期间待办完成、成员切换、已有安排版本变化；同一读取中菜单项不可重复执行及离页迟到结果；320／390手机、横屏、桌面、1.8倍字体。

最初验证副本漏了两份pubspec声明的更新资源，Flutter未启动测试；补齐后重跑。首批新组件测试的默认平台还原、返回按钮定位和弹窗／路由等待不完整，已修正并完整复验；失败批次没有作为通过证据。SDK缓存写入首次受沙箱限制，随后按已批准测试范围正常提升权限运行，没有绕过审批。

可复查的命令和证据：

```text
flutter test --no-pub $(cat regression-paths.txt)
flutter test --no-pub <6份最终草稿与复用测试>
flutter test --no-pub test/widgets/plan_reuse_acceptance_test.dart
dart analyze <4份实现、3份测试及预览源码>
flutter build web --release --no-pub --no-wasm-dry-run --output /tmp/countdown-plan-reuse-formal-web
flutter build web --release --no-pub --no-wasm-dry-run --target plan_reuse_preview.dart --output /tmp/countdown-plan-reuse-preview-web
git -c core.fsmonitor=false diff --check
```

完整50文件清单、测试／构建日志、源码指纹和控制台记录保存在`.dart_tool/plan_reuse_acceptance/`，属于本机忽略的验证产物，不作为发布文件提交。

## 浏览器实际流程

使用本机隔离预览`http://127.0.0.1:18983/`、独立合成账号与数据库，控制规划时钟为10月14日08:00。预览工具按钮打开与规划时间轴共用的真实编辑器；浏览器通过实际菜单进入新建，没有用程序代替点击或模拟保存。原生手机日历明确未计入。

1. 源是10月13日09:00–10:00的已完成AI规划，planned_minutes故意设777、实际缓存99999，并带旧专注ID／日历ID；当天已有14:00–15:00的普通规划。初始2份规划、0条操作，当日真实规划1小时。
2. 从「更多操作→照此新建」进入新页：时长实际为60分钟、日期10月14日，两个推荐08:00–09:00与09:00–10:00，首项已选用。备注、25分钟番茄、2轮、提前10分钟均带入。
3. 点击第二项，开始／结束同步为09:00–10:00；手机设置仍三列并排。点击保存出现已有安排确认，明确原安排保留。
4. 确认追加后返回原编辑器，再关闭回到日历。仅增加1份规划及1条保存操作；原来源行完整比对未变化，新块为planned／manual、零实际投入、空旧绑定。当天概览变为2小时，时间轴同时显示09:00–10:00和14:00–15:00。
5. 再照此新建时，新推荐已排除刚保存的09:00–10:00，显示08:00–09:00及10:00–11:00。尚未触摸也在返回时弹出继续编辑／放弃／保留草稿。仅做布局检查后放弃，最终仍为3份规划、1条操作。
6. 实际检查390×844浅色、1280×900桌面、720×360横屏，以及320×700深色玻璃＋1.8倍字体。普通布局三项配置并排，大字体改为单列，字段和保存操作可达；新建页沿用表单滚动，全天时间轴未增加滚动。临时视口已恢复。
7. 浏览器捕获的警告／错误记录为0。浏览器暂存恢复、无结果诊断、跨日／分段及真实专注启动没有逐项实操；它们的相关自动回归与本轮草稿测试通过，不能把这部分描述成浏览器实测。

## 验证边界与交付状态

没有运行全仓测试／全仓分析、原生真机、真实手机日历、真实提醒触发、真实AI模型或跨设备同步验收。Web构建关闭Wasm预检，本轮不声明Wasm支持已验证。合成账号数据保留用于审阅；用户真实业务数据未作为测试材料读取或改动。

本次未执行提交、推送、发布或部署。用户确认本轮无问题后，再准备第十七轮方案。

## 界面证据

![沿用设置后整页新建](/Users/junpgle/StudioProjects/CountdownTodo/.dart_tool/plan_reuse_acceptance/02-mobile-reuse.png)

![换用第二个时段与并排设置](/Users/junpgle/StudioProjects/CountdownTodo/.dart_tool/plan_reuse_acceptance/03-options.png)

![追加确认](/Users/junpgle/StudioProjects/CountdownTodo/.dart_tool/plan_reuse_acceptance/04-append-confirmation.png)

![保存后的时间轴与数据隔离计数](/Users/junpgle/StudioProjects/CountdownTodo/.dart_tool/plan_reuse_acceptance/05-saved-timeline.png)

![首次带入退出保护](/Users/junpgle/StudioProjects/CountdownTodo/.dart_tool/plan_reuse_acceptance/06-exit-protection.png)

![桌面整页布局](/Users/junpgle/StudioProjects/CountdownTodo/.dart_tool/plan_reuse_acceptance/07-desktop.png)

![横屏并排配置](/Users/junpgle/StudioProjects/CountdownTodo/.dart_tool/plan_reuse_acceptance/08-landscape.png)

![深色大字体](/Users/junpgle/StudioProjects/CountdownTodo/.dart_tool/plan_reuse_acceptance/09-dark-large-font.png)

![深色大字体设置可达](/Users/junpgle/StudioProjects/CountdownTodo/.dart_tool/plan_reuse_acceptance/10-dark-options.png)
