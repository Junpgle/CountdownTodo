# 第十一轮验收：长任务分段规划

日期：2026-10-11，北京时间。实施与本地验收交付完成；用户于2026-10-11回复“通过”，本轮验收通过。第十二轮已依照用户持续执行“排查、修复、提交”的指示开展，见[方案与验收记录](../proposals/2026-10-11-completed-todo-plan-cleanup.md)。

方案：[第十一轮完整方案](../proposals/2026-10-11-plan-split-scheduling.md)。使用说明：[长任务分段规划](../features/plan-split-scheduling.md)。

## 交付行为

整页新建规划新增“分段安排”。独立结果页最多展示5组完整方案，复杂条件放入弹窗。总时长沿用当前编辑／AI估时，失败时要求手工确认；2–6段精确合计，不保存部分结果。

采用整组仅填表单。支持逐段移动、按时间重新排序并保持草稿锚点、返回原单段、整组草稿、每段番茄设置，以及“保存全部并开始第1段”。保存使用严格批量新建，重新读取来源、检查身份和待办、事务重读占用；全部规划与oplog一起提交或一起回滚。稳定UUID避免重复创建，专注重试仅绑定首段。

草稿v2使用原本机表和容量，完整保留时段、目标UUID及共同字段；兼容v1。恢复读取当前避让／缓冲默认，时区变化须确认。草稿摘要显示段数、总量及日期范围，不把跨度说成连续占用。

## 自动验证

- 主回归运行：**42个测试文件，623项全部通过**，日志末尾 `01:51 +623: All tests passed!`。[完整日志](/tmp/plan_split_regression_final.log)。该运行早于最后一笔界面修复；不累加此前608／621项或专项测试。
- 最后一笔界面与跨时区修复后的Widget流程：**13项全部通过**，覆盖分段换序、锚点稳定性、已保存整组后的控件锁定、首段专注失败状态，以及首段偏移未变但后续日偏移改变时阻止保存和保留草稿。[最新流程日志](/tmp/plan_split_timezone_widget_latest.log)。
- 分段草稿与SQLite仓储回归：**16项全部通过**，包括旧版草稿读取与v2修订检查。[仓储日志](/tmp/plan_split_timezone_repository_latest.log)。
- 跨时区偏移签名专项：同一测试分别在 `America/Panama` 和 `America/New_York` 运行，各1项通过，覆盖首段时区偏移相同、后续日期跨DST导致偏移不同的恢复场景。[巴拿马日志](/tmp/plan_split_timezone_panama_latest.log)、[纽约日志](/tmp/plan_split_timezone_newyork_latest.log)。
- 此前专项回归：**7个相关测试文件，92项全部通过**，覆盖分段计算、整组事务、草稿、空结果返回、未确认估时、时区确认、刷新后再次校验及缓冲行为。[跟进日志](/tmp/plan_split_followup_92.log)。测试集有重合，不累加统计。
- 纽约时区专项：最终纯计算测试通过，包含重复小时的真实时间戳及向上取整。[DST日志](/tmp/plan_split_dst_final.log)。
- 最后一笔跨时区修复后的受影响源文件、测试及隔离验收入口静态分析：`No issues found!`。[最新分析日志](/tmp/plan_split_timezone_analyze_latest.log)。
- 最后一笔跨时区修复后，隔离验收Web预览与正式应用Web入口均重新构建成功，分别耗时48.1秒与46.0秒；输出在 `/tmp/countdown-plan-split-preview-tzfix` 和 `/tmp/countdown-plan-split-app-tzfix`。[预览构建日志](/tmp/plan_split_preview_tzfix.log)、[正式入口构建日志](/tmp/plan_split_app_tzfix.log)。
- `git diff --check`用于空白检查，与编译、测试和浏览器证据分别记录。

重点覆盖：90=45＋45、50短尾重分配、段间max缓冲、避让与截止、多天范围及运算上限；第2段／第2条oplog故障回滚；读后插入占用、成员切换、完成／删除／冲突；整组幂等和部分目标拒绝；v1转v2、修订、容量、载荷上限、坏日期和已保存目标识别；采用零写入、真实保存、首段专注失败重试、草稿恢复、窄屏及估时缺失／时区确认。

## 浏览器证据

使用本机隔离合成账号及正式组件、查询、SQLite写入；无真实账号业务数据。合成待办90分钟，10月12日16:00截止，会议08:55–15:00，前10后5分钟缓冲。

| 场景 | 实际结果与证据 |
| --- | --- |
| 连续查找 | 显示截止前无连续90分钟，[390px截图](/tmp/plan-split-evidence/01-continuous-none-390.png) |
| 分段结果 | 得到08:00–08:45、15:10–15:55，合计90分钟，[结果](/tmp/plan-split-evidence/02-split-results-390.png) |
| 条件分离 | 独立条件弹窗，取消不替换当前方案，[条件](/tmp/plan-split-evidence/03-criteria-390.png) |
| 采用 | 返回两段预览及整组保存按钮，[新建页](/tmp/plan-split-evidence/04-adopted-390.png) |
| 暂存与恢复 | 整组占1/5份；恢复两段及设置，[份数](/tmp/plan-split-evidence/05-draft-one-of-five.png)、[恢复](/tmp/plan-split-evidence/06-restored-390.png) |
| 新邻项侵入缓冲 | 新增08:49–08:55事项，保存被拒绝；可见核对栏正式规划0份、本机草稿1份，[零新增](/tmp/plan-split-evidence/07-rejected-zero-writes.png) |
| 取消邻项后重试 | 两段一起保存；可见核对栏正式规划2份、45＋45分钟、草稿0份，[保存结果](/tmp/plan-split-evidence/08-saved-two-plans.png) |

上述恢复截图是在最后修正前拍摄：验收发现恢复页仍显示单段“修改日期”，现已改为“修改分段条件”，并补上分段时区确认保护；最终回归已覆盖。最终响应式截图与构建结果见下方交付记录。

## 诊断及验证边界

预览初次加载再次出现一条 `RenderBox was not laid out` 启动焦点相关诊断及其堆栈；其后上述分段、草稿、失败和保存流程完成。该观察与第十轮一致，**没有把它标记为已修复**。最终预览每次重新加载仍复现同类启动焦点诊断；执行分段、条件、采用、草稿及保存流程后未观察到其他类型的错误。

未做原生手机实机日历、系统返回／键盘、系统通知、勿扰和多设备同步验收；纯计算及现有日历／番茄回归不替代这些证据。Web预览中手机日历读取明确关闭，原生跨天事件规则由既有回归验证。

本次按用户指示完成本地分批提交：`257b2c2d`（分段计算与事务保存）、`ab92c4c5`（分段安排界面）、`7059d697`（恢复与边界校验）、`aafda285`（已保存组保护与调整顺序）、`df527607`（跨时区草稿保护）。未推送、发布或部署。构建产物与截图放在 `/tmp`，验收入口在忽略目录 `.dart_tool`；不会因此成为发布产物。

## 复现命令

```bash
/Users/junpgle/develop/flutter/bin/flutter test --no-pub $(cat /tmp/plan_buffer_regression_files.txt) test/services/plan_split_service_test.dart test/services/plan_split_repository_test.dart test/widgets/plan_split_flow_test.dart --reporter expanded
TZ=America/New_York /Users/junpgle/develop/flutter/bin/flutter test --no-pub test/services/plan_split_service_test.dart --reporter expanded
TZ=America/Panama /Users/junpgle/develop/flutter/bin/flutter test --no-pub test/services/plan_split_service_test.dart --plain-name 'restored split detects timezone drift after its first segment' --reporter expanded
TZ=America/New_York /Users/junpgle/develop/flutter/bin/flutter test --no-pub test/services/plan_split_service_test.dart --plain-name 'restored split detects timezone drift after its first segment' --reporter expanded
TZ=America/Panama /Users/junpgle/develop/flutter/bin/flutter test --no-pub test/services/plan_split_repository_test.dart --reporter expanded
TZ=America/Panama /Users/junpgle/develop/flutter/bin/flutter test --no-pub test/widgets/plan_split_flow_test.dart --reporter expanded
/Users/junpgle/develop/flutter/bin/cache/dart-sdk/bin/dart analyze lib/models/plan_split.dart lib/services/plan_split_service.dart lib/services/plan_editor_draft_repository.dart lib/services/plan_availability_repository.dart lib/services/plan_availability_service.dart lib/screens/plan_split_screen.dart lib/screens/plan_editor_drafts_screen.dart lib/widgets/plan_block_editor_sheet.dart lib/widgets/plan_availability_panel.dart lib/storage_service.dart lib/storage_service_contract.dart lib/storage_service_fixed.dart test/services/plan_split_service_test.dart test/services/plan_split_repository_test.dart test/widgets/plan_split_flow_test.dart .dart_tool/plan_split_preview.dart
/Users/junpgle/develop/flutter/bin/flutter build web --no-pub --target .dart_tool/plan_split_preview.dart --output /tmp/countdown-plan-split-preview-tzfix --pwa-strategy=none --no-web-resources-cdn
/Users/junpgle/develop/flutter/bin/flutter build web --no-pub --output /tmp/countdown-plan-split-app-tzfix --pwa-strategy=none --no-web-resources-cdn
git -c core.fsmonitor=false --no-pager diff --no-ext-diff --check
```

未运行全仓所有无关模块测试和全仓静态分析；本轮使用上述42文件相关回归和列明路径分析。所有结论以对应日志及截图为边界；用户现已确认通过，后续工作见第十二轮记录。


## 最终交付记录

- 发现恢复草稿只比较第一段开始时的偏移：夏令时切换后，后续日期可能静默移动一小时；同时“保留草稿”可绕过确认。现保存整个查询范围各日零点及所有分段起止偏移，正式保存和再次保留草稿都要求确认。纽约／巴拿马专项、16项仓储回归、13项Widget流程均通过。
- 最后一笔跨时区修复后的隔离预览与正式应用入口构建成功，分别48.1秒、46.0秒；受影响路径分析无问题。42文件623项主回归在最后界面修复前通过，未将其表述为最新补丁后的全量回归。
- [桌面1280×900结果](/tmp/plan-split-evidence/09-results-desktop-1280.png)、[桌面条件](/tmp/plan-split-evidence/10-criteria-desktop-1280.png)。截图确认来自实际 `innerWidth=1280`、`innerHeight=900`。
- [320×844、1.8倍字体、深色玻璃设置下的结果](/tmp/plan-split-evidence/11-results-dark-320-scale18.png)、[条件弹窗](/tmp/plan-split-evidence/12-criteria-dark-320-scale18.png)、[采用按钮](/tmp/plan-split-evidence/13-result-actions-dark-320.png)。确认实际视口320×844，条件可提交、采用可返回编辑器。
- 浏览器发现大字体双列设置截短关键标签，已改为大字体单列；[最终单列可读性截图](/tmp/plan-split-evidence/15-readable-settings-dark-320.png)。普通字体仍保持并排。
- 移动第二段到原第一段之前的Widget流程已通过：总量仍90分钟、每段45分钟、原草稿目标锚点和UUID列表保持稳定，返回单段会询问放弃已调整内容。
- 已保存整组在专注失败后锁定表单，提供“完成／重试开始第1段”，不会把已提交分段当作未保存内容再修改；最终13项Widget专项已复验通过，[专项日志](/tmp/plan_split_final_guard_widgets.log)。
- [本轮源文件校验清单](/tmp/plan-split-evidence/source-sha256.txt)。未把此前构建或回归项数重复累计。

最终[390×844方案截图](/tmp/plan-split-evidence/16-final-results-390.png)，[隔离交互预览](http://127.0.0.1:8969/)。临时响应式视口已恢复默认；预览保持在可审阅的完整方案页，未保存额外正式规划。
