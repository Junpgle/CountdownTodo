# 管理类页面公共组件

统一入口：`lib/widgets/management_page.dart`。适用于列表管理、归档、回收站、消息列表等页面。颜色跟随 Material 3 `ColorScheme`，不依赖记账、习惯、团队等业务模块。

## 组件职责

| 组件 | 用途 |
| --- | --- |
| `ManagementPage` | 可滚动页面主体、桌面限宽、安全区、拖动收键盘；放在 `Scaffold.body` 或 `Expanded` 中 |
| `ManagementIntro` | 图标、标题和说明 |
| `ManagementSearchField` | 搜索输入、清空按钮；监听外部 controller 更新 |
| `ManagementFilterBar<T>` | 受控单选筛选，值可用 enum、bool 或 String |
| `ManagementCard` | 统一卡片背景、边框、圆角、内外边距；内容由调用方提供 |
| `ManagementActionBar` | 按钮自动换行；默认右对齐，支持左对齐和两端分布 |
| `ManagementEmptyState` | 空列表或无搜索结果提示 |
| `ManagementLoadError` | 加载失败与重试；`inline: true` 用于保留列表的部分加载失败提示 |

## 最小用法

下面的成员属于页面的 State：`_searchController`、`_archived`、`_reload`、`_restore`，数据加载与筛选也由页面完成。

```dart
import 'package:countdown_todo/widgets/management_page.dart';

ManagementPage(
  maxWidth: 900,
  children: [
    const ManagementIntro(
      icon: Icons.inventory_2_outlined,
      title: '我的记录',
      description: '查找和整理已有记录。',
    ),
    ManagementSearchField(
      controller: _searchController,
      hintText: '搜索名称',
      onChanged: (_) => setState(() {}),
    ),
    const SizedBox(height: 16),
    ManagementFilterBar<bool>(
      value: _archived,
      options: const [
        ManagementFilterOption(value: false, label: '使用中'),
        ManagementFilterOption(value: true, label: '已归档'),
      ],
      onChanged: (value) => setState(() => _archived = value),
    ),
    const SizedBox(height: 16),
    ManagementCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('记录名称'),
          const SizedBox(height: 12),
          ManagementActionBar(children: [
            FilledButton.tonalIcon(
              onPressed: _restore,
              icon: const Icon(Icons.restore_rounded),
              label: const Text('恢复'),
            ),
          ]),
        ],
      ),
    ),
  ],
)
```

加载失败时用 `ManagementLoadError(title: '加载失败', description: '请稍后重试。', onRetry: _reload)` 替换内容，或使用 `inline: true` 保留已加载的数据。正在提交的按钮将 `onPressed` 设为 `null`，忙碌状态与异常处理由页面负责。

## 复用边界

- controller 由页面创建和释放；组件不释放外部 controller。用户输入与清空会调用 `onChanged`，外部修改 controller 不会额外触发业务查询。
- 筛选组件不保存选择状态，不过滤数据；传入新的 `value` 才更新选中项，`onChanged: null` 可禁用操作。
- 不把 API、数据库、数据模型、删除确认、导航、权限或排序规则放入公共 UI。
- 卡片内长文本放入 `Expanded` 或列布局；按钮用操作区换行，不固定卡片高度。
- `ManagementCard(padding: EdgeInsets.zero, clipBehavior: Clip.antiAlias)` 可包裹 `ExpansionTile`。需要选中或待处理高亮时，传入来自当前 `ColorScheme` 的 `backgroundColor` / `borderColor`。
- 页面主体需要有界高度；不要把 `ManagementPage` 再嵌入 `SingleChildScrollView`。大量数据需要分页时仍由页面控制，不由组件自动加载。
- 专有的玻璃表面、颜色选择器、金额表单和图表仍留在相应模块，不强行套入公共卡片。

已有接入示例：专注标签、待办文件夹、习惯归档、待办历史、历史倒计时、团队消息中心。

验证入口：`test/widgets/management_components_test.dart`；页面回归：`management_pages_test.dart` 和 `history_and_messages_ui_test.dart`。
