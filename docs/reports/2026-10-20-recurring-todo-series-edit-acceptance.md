# 第25轮验收报告：重复待办整个系列编辑与历史保护

状态：**实现与代码验收完成，待用户验收**

## 交付内容

- 在重复待办管理入口增加“编辑整个系列”，并在编辑页和保存确认中列出历史、今天、未来、已完成及已跳过期次数量。
- 整系列编辑只应用标题、备注、日期/时间、分类、提醒和协作信息；保持各期 UUID、系列归属、完成/跳过状态及其同步标记，也保持重复频率、间隔和结束规则。日期变更按同一时间偏移应用到现存期次，并按日历日移动系列结束日期。
- 保存前由本地事务同时校验系列成员集合和每个期次的完整基线。编辑期间新增、删除或修改任一成员时，拒绝整批写入并要求重新打开。
- 已有规划块、时间日志、专注记录及系统日历事件不随待办日期变化。
- AI `update_todo` 只有在用户明确要求整个系列时才能提议 series 范围；执行前显示期次摘要并二次确认。完成、跳过和删除仍不支持 series。
- 同步复用现有逐待办记录与 oplog，不新增 schema、服务端或 Worker 变更。

## 验证结果

- **系列相关定向测试**：运行 86 项，85 项通过。覆盖成员范围与计数、事务基线与成员集合保护、AI 明确范围解析和执行、单期状态保留、编辑器二次确认与退出保护、三种屏幕截图。
- **失败测试 1 项**：`AI fixed schedule alignment planning context injects fixed schedules as hard constraints` 断言“明天10点开项目会议”应自动注入 `create_schedule`。该测试在本轮代码临时替换为仓库 HEAD 版本后仍以相同断言失败；本轮没有改动固定日程显式动作识别逻辑。
- **另一次 AI 规划集成测试**：`规划文字假成功补发工具请求，显示4张真实操作并只在点击后保存` 在 `history.last.todoActions` 处失败。将 AI 解析、执行、提示和动作 UI 文件暂时恢复到 HEAD 后同样失败；底层原因不属于本轮系列编辑，本轮没有修改其失败行为。为保持当前新增的可选并发保护参数可编译，仅更新了该测试回调签名。
- **静态分析**：本轮全部 Dart 改动路径 `dart analyze` 通过，无问题。全项目 Flutter analyzer 无错误；报告了 6 条 info 级提示，均位于本轮之外已有工作区改动的 `workbench_view.dart`、`system_control_service_io.dart` 和 `island_ui.dart`。
- **Web 构建**：`flutter_tools.dart build web --release --no-pub` 成功。
- **视觉检查**：3 项真实 `TodoEditScreen` Widget 渲染截图测试通过，使用合成的历史、当前、未来期次；没有使用或修改个人账户数据。当前未执行真实浏览器登录后保存流程、原生设备验证或跨设备服务器同步验证。
- **代码差异**：本轮未改动数据库 schema、服务端、Cloudflare Worker、部署配置或版本号。

## 界面证据

截图由 Flutter WidgetTester 渲染实际 `TodoEditScreen`，配合本机 CJK 字体和合成数据生成，并作为视觉回归基线保存。

### 窄屏编辑器

![窄屏：系列期次、完成率和逐期完成/跳过状态](../../test/widgets/goldens/todo_recurrence_series_edit_phone.png)

### 桌面日期变更确认

![桌面：日期偏移确认和保留历史记录说明](../../test/widgets/goldens/todo_recurrence_series_edit_date_review_desktop.png)

### 深色与大字

![深色大字：窄屏系列编辑摘要](../../test/widgets/goldens/todo_recurrence_series_edit_dark_large_text.png)

## 环境与流程说明

当前会话没有切换或核验模型名称及思考强度的能力，因此不能声称规划使用 GPT‑6.1 sol／中、实现使用 GPT‑6 luna／Max；实际使用的是当前会话分配的模型。完整 `flutter test`、真实浏览器端到端流程、原生设备和多设备同步均未执行。

本报告及截图随第25轮本地 commit 提交，不推送、不部署、不发布。
