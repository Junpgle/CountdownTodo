# 第一轮验收：全局搜索范围筛选

日期：2026-10-07。用户已回复“同意第一轮”。状态：开发与本地验收完成；用户于 2026-10-07 回复“没问题”，已通过本轮验收。

## 交付结果

统一搜索增加 13 个单选范围（含“全部”），常用入口为全部、待办、日程、记账、专注与时间，其余在“更多”菜单。切换范围保留关键词，清空保留范围，重新打开恢复全部。专属范围空输入只显示提示；无结果时可以保留关键词“搜索全部”。每组初始三条、展开更多和原有详情目的页继续使用。

查询在启动本地来源适配器前选择范围，复合来源也分别选择；最终结果和远端缓存再按类型过滤。界面请求序号同时保护关键词、范围及输入防抖期间的状态，覆盖 A → B → A、清空和乱序返回。范围切换、详情返回、预热刷新、重试不会重复记录同一次查询的历史。

远端账号隔离、预热和五分钟缓存行为沿用原逻辑；本轮不声称减少远端请求。无数据库结构、服务端接口或原生权限变更；未使用个人账本、日记、真实账号或外部 AI 服务进行验收。

## 验收对照

| 批准的场景 | 证据与结论 |
| --- | --- |
| 多模块命中后仅搜记账 | 存储集成测试与 widget 测试通过；浏览器“午餐”查询只显示账单 |
| 日程复合范围 | 集成测试同一天命中课程、固定日程、规划块，且不混入其他类型 |
| 类型及子类型覆盖 | 所有业务结果类型仅归属一个专属范围；12 个专属范围来源调用断言通过；合成习惯打卡、挑战任务、记账分类/贷款/分期验证通过。远端模板/团队消息仅验证映射与代码过滤，未连真实服务器取数 |
| 空输入、无结果、重新打开 | widget 测试通过；浏览器确认无结果提示与“搜索全部”保留关键词 |
| 来源调度 | 记账仅调用 finance；全部调用原有 18 个本地逻辑来源；专属空输入调用零来源 |
| 异步快速切换 | 控制完成顺序的测试覆盖 A → B → A、输入防抖旧请求、加载期间清空、预热刷新和失败重试 |
| 日期、中文、多词、备注 | 合成存储测试通过；既有月预算日期测试通过，未扩展日期语法 |
| 打开与返回 | 原导航测试、容器转场测试通过；实际浏览器详情打开与返回后“午餐／记账”保留 |
| 显示与主题 | widget 测试验证 320×640 / 字体1.6 / 键盘260、720×360 / 字体1.4 / 键盘130、1280×900 / 字体2.0；长记账结果无布局异常。浏览器 390×844 和默认宽屏、深浅色人工检查通过 |
| 查询量与耗时 | 隔离临时数据库合成测量通过，数值见下表；不是实际用户设备性能保证 |

## 测量

使用临时数据库和模拟偏好，待办、日记、时间日志、账单各 200 条（四个主要来源共 800 条，另有少量辅助记录）。关键词为“午餐”；全部与记账交替运行，每种先运行一次，再记录六次样本的中位数。计时包含本次查询处理，不包含真实网络请求。

| 指标 | 全部 | 记账 |
| --- | --- | --- |
| 本地逻辑来源适配器调用数 | 18 | 1 |
| 本轮测试环境查询耗时中位数 | 26.1905 ms | 4.551 ms |
| 计入统计的查询次数 | 6 | 6 |

一个适配器可能执行多条 SQL；因此 18 → 1 不表示 SQL 条数或网络请求次数。耗时受测试机器、缓存、数据结构影响，只报告本次观测，不承诺真机加速比例。

## 验收发现并修复

- 横屏加键盘曾挤压内容产生约 14px 的布局溢出。剩余高度不足时改用可滚动的内容区域，骨架屏也能滚动；包含长结果的三组尺寸测试通过。
- 默认懒加载转场完成后，浮点计算可能得到 `0.9999999999999999`，原先 `fadeIn < 1.0` 会持续屏蔽详情点击，导致无法点返回。本轮沿用同一转场已有的容差判断，只调整一处 `IgnorePointer` 条件。先添加测试确认旧实现失败，修复后测试通过；最新浏览器构建也实际验证返回成功。这是验收“详情打开与返回”发现的直接阻碍。

## 执行的检查

相关套件 **48 项全部通过**：

```bash
flutter test --no-pub test/services/search_scope_test.dart test/widgets/global_search_overlay_test.dart test/services/global_search_extra_service_test.dart test/services/search_navigation_test.dart test/utils/page_transitions_test.dart --reporter expanded
```

本轮 8 个源文件/测试文件的分析 **No issues found**：

```bash
flutter analyze --no-pub lib/models/search_scope.dart lib/services/search_service.dart lib/services/global_search_extra_service.dart lib/widgets/global_search_overlay.dart lib/utils/page_transitions.dart test/services/search_scope_test.dart test/widgets/global_search_overlay_test.dart test/support/search_scope_fixture.dart
```

已对新增文件和修改的方法执行 Dart 格式化；旧文件未修改的方法保持原排版。`git diff --check` 通过。使用已有依赖，未运行 `flutter pub get`。

浏览器预览通过以下本地调试命令编译运行，使用实际 `GlobalSearchOverlay`、导航和转场，查询适配器注入合成结果，预热回调不联网：

```bash
flutter run --no-pub -d web-server --web-hostname 127.0.0.1 --web-port 8943 --target .dart_tool/search_scope_preview.dart
```

预览入口处于被忽略的 `.dart_tool/`，不是产品新入口。合成记账记录进入通用详情页，不将该预览称为真实账单原生详情或完整应用集成验收。原导航测试另行检查真实目的页的选择逻辑。

**未执行／未验证**：全仓库 analyze 与全量测试、Android/iOS/Windows/macOS 原生构建和真机运行、真机键盘／原生玻璃效果、真实账号远端接口及完整应用业务数据路径、发布构建。现有自动化与浏览器验收没有发现待修复问题，但上述平台仍需运行验证。

## 改动范围

- 新增 `lib/models/search_scope.dart`。
- 修改 `lib/services/search_service.dart`、`lib/services/global_search_extra_service.dart`、`lib/widgets/global_search_overlay.dart`。
- 修改 `lib/utils/page_transitions.dart` 的一处点击拦截判断，原因见上文。
- 新增 `test/services/search_scope_test.dart`、`test/widgets/global_search_overlay_test.dart`、`test/support/search_scope_fixture.dart`。
- `.gitignore` 增加这三个测试文件的明确白名单，沿用仓库测试忽略规则。
- 更新搜索功能文档、批准方案状态，并新增本验收报告。

首页、待办、AI、财务等既有工作未被本轮回退或纳入交付；工作区期间其他任务仍可能变动。本轮未执行暂存、commit、push、部署或发布。

## 截图与日志

截图为实际搜索组件的合成数据预览。测试日志与截图保存于本地验收目录，链接仅用于当前工作环境：

- [48项测试完整日志](/Users/junpgle/.codex/visualizations/2026/10/07/01a1159f-0bbb-7b42-a276-742283415ffd/search-scope/tests.log)
- [静态分析日志](/Users/junpgle/.codex/visualizations/2026/10/07/01a1159f-0bbb-7b42-a276-742283415ffd/search-scope/analyze.log)
- [默认转场修复前失败证据](/Users/junpgle/.codex/visualizations/2026/10/07/01a1159f-0bbb-7b42-a276-742283415ffd/search-scope/lazy-return-before.log)
- [默认转场修复后通过证据](/Users/junpgle/.codex/visualizations/2026/10/07/01a1159f-0bbb-7b42-a276-742283415ffd/search-scope/lazy-return-after.log)

### 390px浅色记账筛选

![390px浅色记账筛选](/Users/junpgle/.codex/visualizations/2026/10/07/01a1159f-0bbb-7b42-a276-742283415ffd/search-scope/finance-mobile.jpg)

### 390px深色记账筛选

![390px深色记账筛选](/Users/junpgle/.codex/visualizations/2026/10/07/01a1159f-0bbb-7b42-a276-742283415ffd/search-scope/finance-mobile-dark.jpg)

### AI对话范围无结果与搜索全部

![AI对话范围无结果与搜索全部](/Users/junpgle/.codex/visualizations/2026/10/07/01a1159f-0bbb-7b42-a276-742283415ffd/search-scope/no-results-mobile.jpg)

### 默认宽屏记账筛选

![默认宽屏记账筛选](/Users/junpgle/.codex/visualizations/2026/10/07/01a1159f-0bbb-7b42-a276-742283415ffd/search-scope/finance-desktop-dark.jpg)

### 合成记录详情

![合成记录详情](/Users/junpgle/.codex/visualizations/2026/10/07/01a1159f-0bbb-7b42-a276-742283415ffd/search-scope/detail-mobile.jpg)

## 下一步

用户已确认本轮没有问题，进入下一轮项目调研并提交完整方案；下一轮实施仍等待单独批准。本轮批准不包含 commit、推送或发布。
