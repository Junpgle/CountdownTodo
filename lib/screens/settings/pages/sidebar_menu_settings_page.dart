import 'package:flutter/material.dart';

import '../../../services/sidebar_menu_service.dart';
import '../../../widgets/floating_glass_control.dart';

class SidebarMenuSettingsPage extends StatefulWidget {
  final bool isEmbedded;

  const SidebarMenuSettingsPage({
    super.key,
    this.isEmbedded = false,
  });

  @override
  State<SidebarMenuSettingsPage> createState() =>
      _SidebarMenuSettingsPageState();
}

class _SidebarMenuSettingsPageState extends State<SidebarMenuSettingsPage> {
  late List<String> _features;
  late List<String> _utilities;
  Map<String, bool> _visibility = SidebarMenuService.defaultVisibility();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pair = await SidebarMenuService.loadPair();
    final visibility = await SidebarMenuService.loadVisibility();
    if (!mounted) return;
    setState(() {
      _features = pair.features;
      _utilities = pair.utilities;
      _visibility = visibility;
      _isLoading = false;
    });
  }

  Future<void> _reset() async {
    await SidebarMenuService.reset();
    await _load();
  }

  Future<void> _saveOrder() {
    return SidebarMenuService.savePair(
      features: _features,
      utilities: _utilities,
    );
  }

  Future<void> _setVisibility(String key, bool visible) async {
    final next = Map<String, bool>.from(_visibility)..[key] = visible;
    setState(() => _visibility = next);
    await SidebarMenuService.saveVisibility(next);
  }

  Future<void> _reorder(
    SidebarMenuTarget target,
    int oldIndex,
    int newIndex,
  ) async {
    final order = target == SidebarMenuTarget.features ? _features : _utilities;
    final next = List<String>.from(order);
    final item = next.removeAt(oldIndex);
    next.insert(newIndex, item);
    setState(() {
      if (target == SidebarMenuTarget.features) {
        _features = next;
      } else {
        _utilities = next;
      }
    });
    await _saveOrder();
  }

  Future<void> _move(
    SidebarMenuTarget source,
    String key,
  ) async {
    final sourceOrder = source == SidebarMenuTarget.features
        ? List<String>.from(_features)
        : List<String>.from(_utilities);
    final destinationOrder = source == SidebarMenuTarget.features
        ? List<String>.from(_utilities)
        : List<String>.from(_features);
    if (!sourceOrder.remove(key)) return;
    destinationOrder.add(key);
    setState(() {
      if (source == SidebarMenuTarget.features) {
        _features = sourceOrder;
        _utilities = destinationOrder;
      } else {
        _utilities = sourceOrder;
        _features = destinationOrder;
      }
    });
    await _saveOrder();
  }

  String _targetLabel(SidebarMenuTarget target) {
    return target == SidebarMenuTarget.features ? '功能入口' : '工具入口';
  }

  Widget _buildGroup(
    BuildContext context,
    SidebarMenuTarget target,
    List<String> order,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final otherTarget = target == SidebarMenuTarget.features
        ? SidebarMenuTarget.utilities
        : SidebarMenuTarget.features;
    final visibleCount = order.where((key) => _visibility[key] ?? true).length;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  target == SidebarMenuTarget.features
                      ? Icons.widgets_outlined
                      : Icons.build_outlined,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Text(
                  _targetLabel(target),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Text(
                  '$visibleCount 个显示 / ${order.length} 个入口',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '拖动排序，或移到${_targetLabel(otherTarget)}。隐藏后仍可在此恢复。',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const Divider(height: 20),
            ReorderableListView.builder(
              key: ValueKey('sidebar-list-$target'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: order.length,
              onReorderItem: (oldIndex, newIndex) =>
                  _reorder(target, oldIndex, newIndex),
              itemBuilder: (context, index) {
                final key = order[index];
                final definition = SidebarMenuService.definition(key);
                final isVisible = _visibility[key] ?? true;
                return ListTile(
                  key: ValueKey('sidebar-$target-$key'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(definition.icon, color: colorScheme.primary),
                  title: Text(
                    definition.title,
                    style: isVisible
                        ? null
                        : TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  subtitle: Text(
                    isVisible ? '第 ${index + 1} 位' : '已隐藏 · 第 ${index + 1} 位',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: isVisible ? '隐藏入口' : '显示入口',
                        onPressed: () => _setVisibility(key, !isVisible),
                        icon: Icon(
                          isVisible
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: '移到${_targetLabel(otherTarget)}',
                        child: IconButton(
                          tooltip: '移到${_targetLabel(otherTarget)}',
                          onPressed: () => _move(target, key),
                          icon: Icon(
                            target == SidebarMenuTarget.features
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
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              widget.isEmbedded
                  ? 16
                  : floatingGlassSettingsContentTopInset(context, extra: 16),
              16,
              32,
            ),
            children: [
              Text(
                '自定义首页侧边栏的入口显示状态和顺序。设置中心始终保留，方便随时恢复其他入口。',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              _buildGroup(context, SidebarMenuTarget.features, _features),
              const SizedBox(height: 16),
              _buildGroup(context, SidebarMenuTarget.utilities, _utilities),
            ],
          );

    return Scaffold(
      extendBodyBehindAppBar: !widget.isEmbedded,
      appBar: widget.isEmbedded
          ? null
          : FloatingGlassAppBar(
              flexibleSpace: const FloatingGlassTopBarBackground(),
              title: const Text('侧边栏菜单'),
              actions: [_buildResetButton()],
            ),
      body: floatingGlassSettingsBody(
        context,
        standalone: !widget.isEmbedded,
        child: widget.isEmbedded
            ? Column(
                children: [
                  _buildEmbeddedHeader(context),
                  Expanded(child: content),
                ],
              )
            : content,
      ),
    );
  }

  Widget _buildEmbeddedHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
        child: Row(
          children: [
            IconButton(
              tooltip: '返回系统与外观',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            Text(
              '侧边栏菜单',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            _buildResetButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildResetButton() {
    return TextButton.icon(
      onPressed: _isLoading ? null : _reset,
      icon: const Icon(Icons.restore_outlined),
      label: const Text('恢复默认'),
    );
  }
}
