import 'package:flutter/material.dart';

import '../../../services/home_layout_service.dart';
import '../../../widgets/optional_liquid_glass_surface.dart';

class HomeLayoutSettingsPage extends StatefulWidget {
  final bool isEmbedded;

  const HomeLayoutSettingsPage({super.key, this.isEmbedded = false});

  @override
  State<HomeLayoutSettingsPage> createState() => _HomeLayoutSettingsPageState();
}

class _HomeLayoutSettingsPageState extends State<HomeLayoutSettingsPage> {
  static const _labels = <String, String>{
    'banners': '顶部横幅',
    'countdowns': '重要日 / 倒数日',
    'courses': '课程',
    'todos': '待办',
    'timeline': '时间轴',
    'pomodoro': '今日专注',
    'habits': '今日习惯',
    'screenTime': '屏幕时间',
    'math': '数学测验',
  };

  static const _icons = <String, IconData>{
    'banners': Icons.campaign_outlined,
    'countdowns': Icons.event_outlined,
    'courses': Icons.school_outlined,
    'todos': Icons.checklist_rounded,
    'timeline': Icons.timeline_rounded,
    'pomodoro': Icons.adjust_rounded,
    'habits': Icons.auto_awesome_outlined,
    'screenTime': Icons.timer_outlined,
    'math': Icons.functions,
  };

  final Map<HomeLayoutTarget, List<String>> _orders = {
    for (final target in HomeLayoutTarget.values)
      target: HomeLayoutService.defaultOrder(target),
  };
  Map<String, bool> _visibility = HomeLayoutService.defaultVisibility(
    HomeLayoutTarget.mobileHome,
    HomeLayoutTarget.mobileFocus,
  );
  int _habitDisplayLimit = HomeLayoutService.defaultHabitDisplayLimit;
  bool? _isWide;
  bool _isLoading = true;

  List<HomeLayoutTarget> get _visibleTargets => _isWide == true
      ? const [HomeLayoutTarget.wideLeft, HomeLayoutTarget.wideRight]
      : const [HomeLayoutTarget.mobileHome, HomeLayoutTarget.mobileFocus];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isWide = MediaQuery.of(context).size.width >= 768;
    if (_isWide == isWide) return;
    _isWide = isWide;
    _loadOrders(isWide);
  }

  Future<void> _loadOrders(bool isWide) async {
    setState(() => _isLoading = true);
    final targets = isWide
        ? const [HomeLayoutTarget.wideLeft, HomeLayoutTarget.wideRight]
        : const [HomeLayoutTarget.mobileHome, HomeLayoutTarget.mobileFocus];
    final pair = await HomeLayoutService.loadPair(targets[0], targets[1]);
    final visibility =
        await HomeLayoutService.loadVisibility(targets[0], targets[1]);
    final habitDisplayLimit = await HomeLayoutService.loadHabitDisplayLimit();
    if (!mounted || _isWide != isWide) return;
    setState(() {
      _orders[targets[0]] = pair.first;
      _orders[targets[1]] = pair.second;
      _visibility = visibility;
      _habitDisplayLimit = habitDisplayLimit;
      _isLoading = false;
    });
  }

  Future<void> _resetDeviceLayouts() async {
    final targets = _visibleTargets;
    final first = HomeLayoutService.defaultOrder(targets[0]);
    final second = HomeLayoutService.defaultOrder(targets[1]);
    final visibility =
        HomeLayoutService.defaultVisibility(targets[0], targets[1]);
    const habitDisplayLimit = HomeLayoutService.defaultHabitDisplayLimit;
    setState(() {
      _orders[targets[0]] = first;
      _orders[targets[1]] = second;
      _visibility = visibility;
      _habitDisplayLimit = habitDisplayLimit;
    });
    await Future.wait([
      HomeLayoutService.savePair(
        firstTarget: targets[0],
        secondTarget: targets[1],
        firstOrder: first,
        secondOrder: second,
      ),
      HomeLayoutService.saveVisibility(
        firstTarget: targets[0],
        secondTarget: targets[1],
        visibility: visibility,
      ),
      HomeLayoutService.saveHabitDisplayLimit(habitDisplayLimit),
    ]);
  }

  Future<void> _setHabitDisplayLimit(int limit) async {
    setState(() => _habitDisplayLimit = limit);
    await HomeLayoutService.saveHabitDisplayLimit(limit);
  }

  Future<void> _setVisibility(String key, bool visible) async {
    final nextVisibility = Map<String, bool>.from(_visibility)..[key] = visible;
    setState(() => _visibility = nextVisibility);
    final targets = _visibleTargets;
    await HomeLayoutService.saveVisibility(
      firstTarget: targets[0],
      secondTarget: targets[1],
      visibility: nextVisibility,
    );
  }

  Future<void> _reorder(
    HomeLayoutTarget target,
    int oldIndex,
    int newIndex,
  ) async {
    final order = List<String>.from(_orders[target]!);
    final item = order.removeAt(oldIndex);
    order.insert(newIndex, item);
    setState(() => _orders[target] = order);
    await _saveVisiblePair();
  }

  Future<void> _moveTo(
    HomeLayoutTarget source,
    HomeLayoutTarget destination,
    String key,
  ) async {
    final sourceOrder = List<String>.from(_orders[source]!);
    final destinationOrder = List<String>.from(_orders[destination]!);
    if (!sourceOrder.remove(key)) return;
    destinationOrder.add(key);
    setState(() {
      _orders[source] = sourceOrder;
      _orders[destination] = destinationOrder;
    });
    await _saveVisiblePair();
  }

  Future<void> _saveVisiblePair() {
    final targets = _visibleTargets;
    return HomeLayoutService.savePair(
      firstTarget: targets[0],
      secondTarget: targets[1],
      firstOrder: _orders[targets[0]]!,
      secondOrder: _orders[targets[1]]!,
    );
  }

  String _groupLabel(HomeLayoutTarget target) {
    switch (target) {
      case HomeLayoutTarget.mobileHome:
        return '首页';
      case HomeLayoutTarget.mobileFocus:
        return '专注';
      case HomeLayoutTarget.wideLeft:
        return '左栏';
      case HomeLayoutTarget.wideRight:
        return '右栏';
    }
  }

  IconData _groupIcon(HomeLayoutTarget target) {
    switch (target) {
      case HomeLayoutTarget.mobileHome:
        return Icons.home_outlined;
      case HomeLayoutTarget.mobileFocus:
        return Icons.adjust_rounded;
      case HomeLayoutTarget.wideLeft:
      case HomeLayoutTarget.wideRight:
        return Icons.view_column_outlined;
    }
  }

  Widget _buildGroup(
    BuildContext context,
    HomeLayoutTarget target,
    HomeLayoutTarget otherTarget,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final order = _orders[target]!;
    final visibleCount = order.where((key) => _visibility[key] ?? true).length;
    final isMovingToNextGroup =
        _visibleTargets.indexOf(otherTarget) > _visibleTargets.indexOf(target);

    return OptionalLiquidGlassCard(
      key: ValueKey('layout-group-$target'),
      borderRadius: 12,
      highContrast: true,
      clipBehavior: Clip.antiAlias,
      fallbackDecoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_groupIcon(target), color: colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  _groupLabel(target),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                // 窄容器下允许计数文本省略，杜绝头部行横向溢出。
                Flexible(
                  child: Text(
                    '$visibleCount 个显示 / ${order.length} 个组件',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '拖动排序，或使用箭头移到${_groupLabel(otherTarget)}',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const Divider(height: 20),
            if (order.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    '暂无组件，可从${_groupLabel(otherTarget)}移入',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ),
              )
            else
              ReorderableListView.builder(
                key: ValueKey('layout-list-$target'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: order.length,
                onReorderItem: (oldIndex, newIndex) =>
                    _reorder(target, oldIndex, newIndex),
                itemBuilder: (context, index) {
                  final key = order[index];
                  final isVisible = _visibility[key] ?? true;
                  return Material(
                    key: ValueKey('$target-$key'),
                    type: MaterialType.transparency,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_icons[key], color: colorScheme.primary),
                      title: Text(
                        _labels[key] ?? key,
                        style: isVisible
                            ? null
                            : TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                      subtitle: Text(
                        isVisible
                            ? '第 ${index + 1} 位'
                            : '已隐藏 · 第 ${index + 1} 位',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: isVisible ? '隐藏组件' : '显示组件',
                            onPressed: () => _setVisibility(key, !isVisible),
                            icon: Icon(
                              isVisible
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                          Semantics(
                            button: true,
                            label: '移到${_groupLabel(otherTarget)}',
                            child: IconButton(
                              onPressed: () =>
                                  _moveTo(target, otherTarget, key),
                              icon: Icon(
                                isMovingToNextGroup
                                    ? Icons.arrow_forward_rounded
                                    : Icons.arrow_back_rounded,
                              ),
                            ),
                          ),
                          ReorderableDelayedDragStartListener(
                            index: index,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Icon(Icons.drag_handle),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHabitDisplayLimitSetting(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return OptionalLiquidGlassCard(
      borderRadius: 12,
      highContrast: true,
      fallbackDecoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          leading: Icon(Icons.format_list_numbered_rounded,
              color: colorScheme.primary),
          title: const Text('首页展示习惯数量'),
          subtitle: const Text('首页默认展示 3 个，可按需要调整为 1–5 个'),
          trailing: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _habitDisplayLimit,
              items: [
                for (var count = HomeLayoutService.minHabitDisplayLimit;
                    count <= HomeLayoutService.maxHabitDisplayLimit;
                    count++)
                  DropdownMenuItem(
                    value: count,
                    child: Text('$count 个'),
                  ),
              ],
              onChanged: (value) {
                if (value != null && value != _habitDisplayLimit) {
                  _setHabitDisplayLimit(value);
                }
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = _isWide == true;
    final targets = _visibleTargets;

    return Scaffold(
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              title: const Text('首页布局'),
              actions: [_buildResetButton()],
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                if (widget.isEmbedded)
                  Align(
                    alignment: Alignment.centerRight,
                    child: _buildResetButton(),
                  ),
                Text(
                  isWide
                      ? '当前为宽屏设备，仅显示宽屏布局。组件可在左右栏之间迁移。'
                      : '当前为手机端，仅显示手机布局。组件可在首页和专注之间迁移。',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                _buildHabitDisplayLimitSetting(context),
                const SizedBox(height: 16),
                if (isWide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                          child: _buildGroup(context, targets[0], targets[1])),
                      const SizedBox(width: 16),
                      Expanded(
                          child: _buildGroup(context, targets[1], targets[0])),
                    ],
                  )
                else ...[
                  _buildGroup(context, targets[0], targets[1]),
                  const SizedBox(height: 16),
                  _buildGroup(context, targets[1], targets[0]),
                ],
              ],
            ),
    );
  }

  Widget _buildResetButton() {
    return TextButton.icon(
      onPressed: _isLoading ? null : _resetDeviceLayouts,
      icon: const Icon(Icons.restore_outlined),
      label: const Text('恢复默认'),
    );
  }
}
