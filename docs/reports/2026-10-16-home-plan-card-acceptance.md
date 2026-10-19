# 第十七轮验收：首页今日规划卡片对账与快捷操作

实施日期：2026-10-15至2026-10-16。用户已批准实施；用户于2026-10-16确认连同折叠及视觉优化验收通过，并要求准备第十八轮方案。

## 交付行为

- 首页与规划中心、复盘共用真实聚合。预算排除取消／跳过，完成数按已结束规划统计；有效已结束专注先汇总秒数，忽略旧缓存达成率。
- 最多五行，优先当前时段和未来安排，为需处理项保留位置，已完成补齐。所有候选仍参与唯一投入归属，不只在展示的五行之间分配。
- 每行可动画展开，查看规划按最新UUID进入原编辑器，投入明细按当天和planId进入分页详情；漏做保留重新安排。未关联规划的专注显示准确摘要，归属问题单独进入待核对。
- 同日刷新保留行位置并禁用旧操作，错误局部重试。路由、底部标签、模块、前后台、身份、请求序号及日期共同控制刷新；只设置下一边界计时，不按秒轮询。
- 修复真实首页布局白名单遗漏planBlocks的问题，补齐设置标签和图标，保留旧排序及明确隐藏设置。高对比卡片填充改善壁纸背景上的阅读。

新读取只读业务表；旧漏做维护仍在原初始化／业务刷新边界运行，保留缓存和历史关联判定，并使用已有条件保存防止覆盖并发编辑。旧维护仍读取当天全部规划和专注，不宣称整个首页加载已经有界。新展示重试、展开和边界刷新不额外触发维护。

## 验证结果与范围

| 检查 | 本轮结果 |
| --- | --- |
| 规划、番茄及首页相关回归 | 49份797项通过；70秒，文件清单保存在本机验收目录 |
| 最终隐藏读取／界面与AI估时补充回归 | 124项通过；26秒，与797存在重复，不相加 |
| 最终可读性、首页、冲突及共享玻璃组件 | 63项通过；27秒，与前两批存在重复 |
| 纽约秋季夏令时 | 单独TZ进程1项通过，本地一天1500分钟 |
| Lord Howe半小时夏令时 | 单独TZ进程1项通过，本地一天1410分钟 |
| 静态分析 | 首批13个改动／测试／预览文件通过；最终样式与新增测试5项、首页时钟接入及预览2项分别通过 |
| 最终数据及布局复验 | 52项通过；5秒，包含100条专注的大样本，不与其他批次相加 |
| 正式lib/main.dart Web release构建 | 通过；最终68.2秒 |
| 真实HomeDashboard合成数据预览构建 | 通过；最终64.6秒，非卡片专用替代页，验收时钟固定，样本与卡片共用同一时刻 |
| 差异空白检查 | git diff --check通过；不替代功能测试 |

定向用例包括：五条上午已完成不挤掉后续安排、需处理行预留、未来已完成归类、稳定排序、缓存99999忽略、两条40秒合计80秒、未展示竞争规划、同标题不同待办、未关联零时长记录入口、取消／跳过／损坏数据、跨午夜和已删除待办标题、成员切换及迟到结果、隐藏／后台／午夜／开始结束边界、实际编辑器UUID、当日投入筛选、关闭返回、零业务写入、局部失败重试以及原维护判定。

新增展示查询返回四条聚合行及最多五条规划投影，另有固定三次表结构检查；没有按规划逐项查询。数据库内部仍执行共享归属CTE，不把返回上限等同于扫描成本或性能倍率。大样本包含100条当天规划、200条历史规划及100条当天专注；不解码全量详情。

首次试跑中的错误测试路径、测试时序及导航错误消失问题已经修正并重新通过。SQLite工厂警告来自隔离夹具。一次浏览器自动审批超时后按工具提示重试成功，没有绕过权限。

## 浏览器验收

本机地址：`http://127.0.0.1:18984/`。独立合成账号，无真实账号令牌和真实手机日历。截图中的启动公告、离线通道条属于真实首页已有界面；不作为本轮网络同步验收。

最终检查覆盖390×844手机、720×360横屏、1280×900桌面，以及320×700、1.8倍字体、深色玻璃。横屏和大字模式沿用首页纵向滚动查看，未引入内部滚动列表或时间轴滚动。窄屏指标切换为“查看今日概览”，快捷操作可换行。

真实首页合成样本：9份规划；预算4时45分、已结束完成5/6、有效专注2分40秒；旧缓存99999不进入实际值。当前和两项后续安排优先，漏做保留入口，早晨完成项仅补一行。展开、查看编辑器、投入详情、返回、故障注入与局部重试后，仍为9份规划、0条操作日志。未执行保存或开始专注。

未关联明细准确显示2项、1分钟20秒，每项40秒。首页滚动到卡片底部打开明细，返回后卡片底部、待办清单及待办行保持原位置；对应前后截图可对照。最终控制台抓取没有warn/error项；这不等于验证了真实网络／WebSocket。返回时曾出现原壁纸暂未显示的背景，因此不把壁纸或离线通道视为本轮已修复项。

| 截图 | 核对内容 |
| --- | --- |
| 01-mobile-home.png | 390手机最终卡片、真实统计、五项优先排序、壁纸文字对比 |
| 02-expanded.png | 当前规划展开后的投入摘要及两个操作 |
| 03-editor.png | 从首页进入对应规划编辑器；截图为最终填充调整前的功能检查，编辑器未改版 |
| 04-scroll-before.png／06-scroll-after.png | 同一首页滚动位置，打开明细前后对照 |
| 05-focus-detail.png | 未关联规划明细、两条40秒记录及1分钟20秒汇总 |
| 07-local-error.png／08-recovered-zero-writes.png | 仅卡片失败、重试恢复、9份规划0条操作日志 |
| 09-landscape.png／10-desktop.png | 横屏及桌面真实首页 |
| 11-dark-large-glass.png／12-dark-expanded.png | 320大字深色玻璃、概览入口及展开操作 |

![手机首页最终结果](/Users/junpgle/StudioProjects/CountdownTodo/.dart_tool/home_plan_acceptance/01-mobile-home.png)

![展开快捷操作](/Users/junpgle/StudioProjects/CountdownTodo/.dart_tool/home_plan_acceptance/02-expanded.png)

![局部重试后零新增业务日志](/Users/junpgle/StudioProjects/CountdownTodo/.dart_tool/home_plan_acceptance/08-recovered-zero-writes.png)

![大字玻璃模式操作](/Users/junpgle/StudioProjects/CountdownTodo/.dart_tool/home_plan_acceptance/12-dark-expanded.png)

## 证据与交付边界

本机忽略目录：`.dart_tool/home_plan_acceptance/`，保存日志、测试文件清单、源码SHA-256指纹、预览源码、截图及控制台记录。验证在`/tmp/countdown-home-plan-verification`副本运行，避免干扰用户正在使用的预览服务；本轮实现文件已逐项核对副本与工作区一致。

仓库存在其他并行修改（待办卡片缓存、版本清单等），没有覆盖、提交或发布它们。本轮构建基于记录的验证副本，不宣称覆盖构建之后出现的全部其他修改。

未执行全仓测试／全仓分析、原生真机、真实日历、提醒触发、真实AI模型及多设备同步验收；Web构建关闭Wasm预检，不声明Wasm已验。合成数据保留供审阅，未改动用户真实业务数据。没有commit、push、发布或部署。

用户确认通过后再准备第十八轮方案。

## 可复查命令

在验证副本内依次运行，测试与构建没有同时执行：

```sh
flutter test --no-pub $(cat regression-paths.txt)
flutter test --no-pub <最终隐藏读取、卡片及AI估时相关11份测试>
flutter test --no-pub test/widgets/plan_today_card_test.dart test/widgets/plan_conflict_review_test.dart test/widgets/optional_liquid_glass_surface_test.dart
flutter test --no-pub test/services/plan_today_card_test.dart test/services/plan_review_repository_test.dart test/services/home_plan_layout_test.dart
TZ=America/New_York flutter test --no-pub test/services/plan_today_card_test.dart --plain-name 'local day boundaries respect DST in America/New_York'
TZ=Australia/Lord_Howe flutter test --no-pub test/services/plan_today_card_test.dart --plain-name 'local day boundaries respect DST in Australia/Lord_Howe'
flutter analyze --no-pub <本轮改动及测试路径>
flutter build web --release --no-pub --no-wasm-dry-run
flutter build web --release --no-pub --no-wasm-dry-run --target home_plan_preview.dart
```

首次有一批测试因错误路径失败，路径修正后的独立日志67项通过；最终报告以上表各批的独立成功日志为依据。最后52项数据复验发生在最终构建之后，仅加强测试样本，业务实现未再更改。

## 用户反馈补充：整卡折叠（2026-10-16）

用户指出占地较大，要求支持折叠。本轮继续补齐：点标题或右侧箭头收起／展开，220ms短动画；收起仅保留一行标题栏及统计、展开入口，隐藏三项指标和五行列表。展开后仍显示原有数据与操作。首次保持原先展开，后续按账号记住上次选择；其他账号偏好不串用。点击折叠不跳转规划中心，不写规划及操作日志。

本次补充以最终折叠验证记录为准：卡片及冲突组件40项测试通过（含新增折叠高度小于100、重建恢复偏好、再次展开、标题点击、320大字和不同账号偏好隔离），未重复相加到之前797项。其他先前测试与截图仍是折叠补充前的证据。


折叠补充静态分析通过；预览构建64.9秒、正式Web入口构建72.7秒均通过。最终差异空白检查通过，源码与验证副本一致。新地址为`http://127.0.0.1:18985/`，避免旧18984预览缓存。浏览器已确认收起后只剩紧凑标题栏，下面待办清单上移；原生真机仍未测，未提交或发布。

![整卡收起后](/Users/junpgle/StudioProjects/CountdownTodo/.dart_tool/home_plan_acceptance/13-card-collapsed.png)

页面重新载入后仍显示“展开今日规划”，列表保持隐藏，浏览器折叠记忆验收通过；截图`14-collapse-restored.png`为最终重载后状态。

![重新载入仍保持折叠](/Users/junpgle/StudioProjects/CountdownTodo/.dart_tool/home_plan_acceptance/14-collapse-restored.png)

## 继续视觉优化（2026-10-16）

按用户“UI仍不好看”的反馈继续调整。收起态使用更小垂直留白（普通字体约60高），主题图标底座与细边框；展开态增加浅色指标条，用细状态线、适度字重和次要文字颜色区分信息。标题栏保留统计与折叠两个按钮，全部规划统一移到底部，减少拥挤。仍沿用账号折叠记忆、同日刷新保留位置和已有快捷操作。

本次40项卡片／冲突界面回归通过（29秒），静态分析无问题；新版预览构建65.9秒、正式Web入口构建73.5秒均通过。没有重复计入前面的797项。实际浏览器验收地址为`http://127.0.0.1:18986/`，避免旧版本缓存。

视觉改动只涉及卡片组件及功能文档；组件源码与验证副本一致，记录在`style-source-fingerprints.json`。构建期间另有并行首页banner改动，工作区首页文件多了banner工具导入；本次构建和截图不声称覆盖该并行改动，未覆盖或提交他人的修改。原生真机仍未测，无commit／push／部署。

![新版展开态](/Users/junpgle/StudioProjects/CountdownTodo/.dart_tool/home_plan_acceptance/15-style-expanded.png)

![新版收起态](/Users/junpgle/StudioProjects/CountdownTodo/.dart_tool/home_plan_acceptance/16-style-collapsed.png)

新版还检查了320×700、1.8倍字体、深色玻璃模式：沿用折叠状态，展开后使用“查看今日概览”，规划行文字可换行，未发现溢出提示。截图为`17-style-dark-large.png`；此前不同尺寸用例也包含在本次40项回归中。

![新版深色大字](/Users/junpgle/StudioProjects/CountdownTodo/.dart_tool/home_plan_acceptance/17-style-dark-large.png)
