# 第六轮：预计用时校准与依据展示验收

日期：2026-10-10（北京时间）。用户已回复“同意”批准[第六轮方案](../proposals/2026-10-09-time-estimation-calibration.md)，交付后回复“确认通过”。状态：实现及用户验收通过；第七轮另提方案。

## 交付结果

- 新建待办和规划编辑共用紧凑的“预计专注用时 · 历史参考程度 ⓘ”。取消估时置信百分比，点击后才显示只读依据：实际参与的任务数、最多三组标题、累计专注概况与不足原因。
- 以当前账号的具体已完成待办 UUID 为样本，累计其有效实际专注秒数。同名任务、重复任务各期分别保留；三轮实际25分钟形成一个75分钟样本。未执行规划、计划番茄时长、规划实际缓存、未关联时间日志不冒充已完成任务投入。
- 明确处理0值、缺失、异常、未结束、未来、删除、同步冲突及矛盾归属。有关联的非删除坏记录使任务不完整；有明确0值不回退计划值。跨日实际记录完整累计，不二次扣除暂停。
- SQL先完整聚合任务、再最多取500个近期有效样本，并批量解析精确标签集合；同一事务快照、读取前后复核账号。不逐任务读取，不改通用统计兼容口径。
- 相似／分类有效层采用近期加权中位数，缺失层不按0参与。样本少或差异大时降低历史影响；较充分参考至少需要五个近期、强相似且稳定的样本，久远相似任务不能借近期同组任务升级为较充分。
- 保留新增页500ms防抖，增加标题、分组、账号、日程切换、清空和销毁保护；估时返回后先复核账号再读取分类建议。规划保留草稿版本及采用候选保护。估时不自动增加番茄轮数，不改用户已选时段或已编辑设置。
- 主页编辑待办进入整页规划仍先估时，再展示两个推荐；自定义寻找、默认五个候选及避让记忆沿用。依据打开／关闭只展示本次快照，不再次估时、不自动保存。

这里的时间是已记录的专注投入，不包含休息或未记录工作，也不表示当前任务剩余时间。回归通过不代表已经评测真实任务的预测准确率。

## 自动验证

28个相关测试文件共 **383项通过**。新增估时相关66项：算法17项、SQLite读取29项、共用依据界面13项、正式入口7项。覆盖原有第三轮恢复、第四轮冲突与改期、第五轮拖动与撤销、空闲推荐、避让、实际记录和日历流程。最终保持新增页原有登录语义后，正式入口及原新增页 **11项再次通过**。

实施前先运行四项回归，全部实际失败：单轮替代整任务、同名任务丢失、未执行规划污染、无匹配层以零拉低估时。修复后均通过。日志：`/tmp/time_estimation_baseline.log`、`/tmp/time_estimation_first_tests.log`。

| 验收项 | 实际证据 |
| --- | --- |
| 累计与归属 | 多轮累计、同名独立、重复系列独立、直接绑定／有效规划回退、孤立记录、映射／删除规划、矛盾归属两边不完整、缓存不重复累计 |
| 数据质量 | 0、null、负数、小数、文本、无穷、NaN、超过墙钟、未来、未结束、倒置区间、冲突、删除、未完成、空标题与跨午夜；null等旧兼容值使用单独可空测试表，正常用例使用生产迁移后的隔离数据库 |
| 算法 | 50／60／65中位数60、三轮25累计75、未执行规划不影响、缺失层归一化、精确标签、离群值、0至6个样本参考等级、久远／弱相似／未来样本、英文标准化、只展示实际使用的有界快照 |
| 查询边界 | 700条番茄先汇总成一项任务；超过500个任务只取完整500样本；标签批量关联；读取前／事务中切账号拒绝旧数据；读取失败与无历史／记录不完整区分 |
| 只读 | 读取前后六张业务表逐字段一致；正式新增与规划入口打开／关闭依据不写oplog或规划，不再次查询候选；历史快照集合不可修改 |
| 异步与草稿 | 500ms防抖、迟到旧标题、分组、日程、清空、销毁、账号切换及前台恢复；规划既有手动时长、番茄配置、已选候选、失效和失败保护回归 |
| 布局 | 320×640／390×844／720×360／1280×900，1.6／2.0字体，键盘、普通浅色和玻璃深色；无溢出，关闭入口可点击。正式规划页已有布局回归亦通过 |

完整聚焦回归命令：

```sh
flutter test --no-pub \
  test/services/time_estimation_service_test.dart \
  test/services/time_estimation_repository_test.dart \
  test/widgets/time_estimation_hint_test.dart \
  test/widgets/time_estimation_flow_test.dart \
  test/services/plan_drag_service_test.dart \
  test/widgets/plan_drag_undo_test.dart \
  test/services/plan_conflict_review_service_test.dart \
  test/widgets/plan_conflict_review_test.dart \
  test/services/missed_plan_recovery_service_test.dart \
  test/widgets/missed_plan_recovery_flow_test.dart \
  test/services/plan_availability_service_test.dart \
  test/services/plan_availability_repository_test.dart \
  test/services/plan_availability_preferences_test.dart \
  test/services/plan_execution_repository_test.dart \
  test/services/device_calendar_read_service_test.dart \
  test/services/device_calendar_refresh_test.dart \
  test/widgets/plan_availability_panel_test.dart \
  test/widgets/plan_block_editor_sheet_test.dart \
  test/widgets/todo_edit_plan_entry_test.dart \
  test/widgets/plan_execution_view_test.dart \
  test/widgets/device_calendar_event_detail_screen_test.dart \
  test/widgets/course_month_view_device_calendar_test.dart \
  test/widgets/device_calendar_home_schedule_test.dart \
  test/services/schedule_conflict_service_test.dart \
  test/services/calendar_sync_service_test.dart \
  test/models/todo_time_semantics_test.dart \
  test/widgets/app_dialogs_test.dart \
  test/widgets/add_todo_screen_test.dart --reporter expanded
```

日志：`/tmp/time_estimation_full_tests.log`（383项）、`/tmp/time_estimation_final_entry_tests.log`（11项）。测试中使用隔离SQLite、合成数据、模拟平台桥；原新增页未初始化数据库的测试继续走其既有兼容回退，不能据此声称验证了真实个人数据。

相关10个源码／测试文件静态分析无问题：

```sh
flutter analyze --no-pub \
  lib/services/time_estimation_repository.dart \
  lib/services/time_estimation_service.dart \
  lib/widgets/time_estimation_hint.dart \
  lib/screens/add_todo_screen.dart \
  lib/widgets/plan_block_editor_sheet.dart \
  test/services/time_estimation_service_test.dart \
  test/services/time_estimation_repository_test.dart \
  test/widgets/time_estimation_hint_test.dart \
  test/widgets/time_estimation_flow_test.dart \
  test/widgets/plan_block_editor_sheet_test.dart
```

日志：`/tmp/time_estimation_final_analyze.log`。7个独立服务／组件／新测试文件格式检查零变化，旧大型页面只格式化本轮相关区域；`git diff --check`通过。

### 验收复核补充

复核发现：父组件直接修改同一 `TodoItem` 对象的标题或分类，再重建规划编辑器时，`oldWidget` 与新组件持有同一对象，旧估时可能不失效。为标题、分类分别新增正式界面测试，两项先实际失败（`/tmp/time_estimation_refresh_baseline.log`），随后以独立的不可变标题／分类快照比较刷新输入，清除旧估时与推荐身份，保留已填时段，不重新填草稿或写业务数据。

补充修复后4个正式界面回归文件 **73项通过**（包括两项新增测试）：`time_estimation_flow_test.dart`、`plan_block_editor_sheet_test.dart`、`todo_edit_plan_entry_test.dart`、`plan_availability_panel_test.dart`。日志：`/tmp/time_estimation_refresh_tests.log`。相关2个源码／测试文件静态检查无问题，日志：`/tmp/time_estimation_refresh_analyze.log`。本段为此前383项完整聚焦回归之后的追加验证，未将不同批次测试合并声称一次完整运行。

## 浏览器视觉与实际操作

在独立localhost端口8958、合成账号 `synthetic-estimation-20261010` 中运行正式 `AddTodoScreen`、`PlanBlockEditorSheet`、估时服务及Web SQLite。种子数据为六个同名已完成待办，各有三轮25分钟实际专注；待规划项目仍未完成。仅候选占用加载使用合成空安排，手机日历明确停用；没有读取个人日历。预览自身的现有团队请求指向本机无服务端口，不调用远程估时或大模型。

实际操作：

1. 桌面1280×900进入正式规划页，显示75分钟和“历史参考较充分”；首个候选08:00–09:15，另一个09:15–10:30。番茄轮数保持“按规划时长”。
2. 点击依据，显示实际参考六个完成任务、75分钟累计概况、非剩余时间说明；关闭后草稿和候选保留。
3. 手机390×844进入正式新增页，输入“复习高数”，500ms后得到相同估时；信息按钮可点击，弹层内容和关闭入口完整可达。关闭后标题保留，实际截止仍为未安排。
4. 手机宽度再次进入正式规划页，统一估时行、两个推荐及其他设置布局正常；最终源码重新构建后复核。

本地截图：

- [桌面规划页](/tmp/time-estimation-evidence/desktop-plan.png)
- [桌面依据](/tmp/time-estimation-evidence/desktop-evidence.png)
- [手机新增页](/tmp/time-estimation-evidence/mobile-add.png)
- [手机依据](/tmp/time-estimation-evidence/mobile-evidence.png)
- [手机规划页](/tmp/time-estimation-evidence/mobile-plan.png)

预览构建命令：

```sh
flutter build web --no-pub \
  --target .dart_tool/time_estimation_preview.dart \
  --output /tmp/countdown-time-estimation-preview
```

日志：`/tmp/time_estimation_final_web_build.log`。入口在忽略目录，仅用于验收；构建为临时预览，不是发布包或部署。

## 交付边界

未新增依赖、字段、迁移、服务器接口、系统权限或远程AI调用；未重写历史记录、专注统计、同步及日历写入规则。工作树中其他AI导航、版本弹层、对话框等并行改动保留，未暂存、提交、推送或部署。

未执行全仓 `flutter analyze`／全套 `flutter test`、Android／iOS／macOS／Windows实机、真实账号同步及个人数据长期估时评测。普通／玻璃和大字体结论来自上述Widget测试；浏览器截图验证普通主题下正式页面，不能替代原生渲染、软键盘、系统权限和设备日历的实机验收。

用户已确认第六轮通过，第七轮仍采用“完整方案 → 批准 → 实施 → 验收”的流程。
