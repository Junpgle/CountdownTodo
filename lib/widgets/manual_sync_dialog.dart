import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/lan_sync_service.dart';
import '../utils/app_dialogs.dart';

/// 手动同步目标通道：服务器同步或局域网同步。
enum ManualSyncTarget { server, lan }

/// User-selected data modules for a manual cloud sync pass.
class ManualSyncSelection {
  const ManualSyncSelection({
    required this.syncTodos,
    required this.syncCountdowns,
    required this.syncScreenTime,
    required this.syncPomodoro,
    required this.syncTimeLogs,
    required this.syncPlanBlocks,
    required this.syncFixedSchedules,
    required this.syncHabits,
    required this.syncFinance,
    this.target = ManualSyncTarget.server,
  });

  final bool syncTodos;
  final bool syncCountdowns;
  final bool syncScreenTime;
  final bool syncPomodoro;
  final bool syncTimeLogs;
  final bool syncPlanBlocks;
  final bool syncFixedSchedules;
  final bool syncHabits;
  final bool syncFinance;
  final ManualSyncTarget target;

  List<bool> get _allValues => [
    syncTodos,
    syncCountdowns,
    syncScreenTime,
    syncPomodoro,
    syncTimeLogs,
    syncPlanBlocks,
    syncFixedSchedules,
    syncHabits,
    syncFinance,
  ];

  int get totalCount => _allValues.length;

  int get selectedCount => _allValues.where((selected) => selected).length;

  bool get hasAnySelected => selectedCount > 0;

  bool get allSelected => selectedCount == totalCount;
}

enum _SyncModuleId {
  todos,
  countdowns,
  planBlocks,
  fixedSchedules,
  pomodoro,
  timeLogs,
  screenTime,
  habits,
  finance,
}

class _SyncModuleSpec {
  const _SyncModuleSpec({
    required this.id,
    required this.label,
    required this.icon,
  });

  final _SyncModuleId id;
  final String label;
  final IconData icon;
}

class _SyncModuleGroup {
  const _SyncModuleGroup({required this.title, required this.modules});

  final String title;
  final List<_SyncModuleSpec> modules;
}

const List<_SyncModuleGroup> _syncModuleGroups = [
  _SyncModuleGroup(
    title: '任务与日程',
    modules: [
      _SyncModuleSpec(
        id: _SyncModuleId.todos,
        label: '待办事项',
        icon: Icons.check_circle_outline_rounded,
      ),
      _SyncModuleSpec(
        id: _SyncModuleId.countdowns,
        label: '重要日倒计时',
        icon: Icons.event_available_rounded,
      ),
      _SyncModuleSpec(
        id: _SyncModuleId.planBlocks,
        label: '今日规划',
        icon: Icons.view_timeline_outlined,
      ),
      _SyncModuleSpec(
        id: _SyncModuleId.fixedSchedules,
        label: '固定日程',
        icon: Icons.calendar_month_rounded,
      ),
    ],
  ),
  _SyncModuleGroup(
    title: '专注与记录',
    modules: [
      _SyncModuleSpec(
        id: _SyncModuleId.pomodoro,
        label: '番茄钟记录',
        icon: Icons.timer_outlined,
      ),
      _SyncModuleSpec(
        id: _SyncModuleId.timeLogs,
        label: '时间日志',
        icon: Icons.history_toggle_off_rounded,
      ),
      _SyncModuleSpec(
        id: _SyncModuleId.screenTime,
        label: '屏幕使用时间',
        icon: Icons.insights_rounded,
      ),
      _SyncModuleSpec(
        id: _SyncModuleId.habits,
        label: '习惯',
        icon: Icons.track_changes_rounded,
      ),
      _SyncModuleSpec(
        id: _SyncModuleId.finance,
        label: '记账',
        icon: Icons.account_balance_wallet_outlined,
      ),
    ],
  ),
];

/// Presents the manual sync module picker as a bottom sheet on compact screens
/// and a centered dialog on wider layouts.
Future<ManualSyncSelection?> showManualSyncOptionsDialog(
  BuildContext context, {
  required bool initialSyncFinance,
  bool isOfflineMode = false,
  int lanPeerCount = 0,
}) {
  final isCompact = MediaQuery.sizeOf(context).width < 600;
  if (isCompact) {
    return showAppModalBottomSheet<ManualSyncSelection>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => _ManualSyncOptionsContent(
        initialSyncFinance: initialSyncFinance,
        isBottomSheet: true,
        isOfflineMode: isOfflineMode,
        lanPeerCount: lanPeerCount,
      ),
    );
  }

  return showAppDialog<ManualSyncSelection>(
    context: context,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: _ManualSyncOptionsContent(
          initialSyncFinance: initialSyncFinance,
          isBottomSheet: false,
          isOfflineMode: isOfflineMode,
          lanPeerCount: lanPeerCount,
        ),
      ),
    ),
  );
}

class _ManualSyncOptionsContent extends StatefulWidget {
  const _ManualSyncOptionsContent({
    required this.initialSyncFinance,
    required this.isBottomSheet,
    required this.isOfflineMode,
    required this.lanPeerCount,
  });

  final bool initialSyncFinance;
  final bool isBottomSheet;
  final bool isOfflineMode;
  final int lanPeerCount;

  @override
  State<_ManualSyncOptionsContent> createState() =>
      _ManualSyncOptionsContentState();
}

class _ManualSyncOptionsContentState extends State<_ManualSyncOptionsContent> {
  late final Map<_SyncModuleId, bool> _selected;
  late ManualSyncTarget _target;
  late int _lanPeerCount;
  List<LanDevice> _lanPeers = const [];
  bool _isLanDevicesExpanded = false;
  bool _isScanningLan = false;
  StreamSubscription<List<LanDevice>>? _lanDevicesSub;

  bool _matchesUser(String? deviceUserId, String? currentUser) {
    if (currentUser == null || currentUser.trim().isEmpty) return true;
    if (deviceUserId == null) return false;
    return deviceUserId.trim().toLowerCase() ==
        currentUser.trim().toLowerCase();
  }

  List<LanDevice> _filterPeers(List<LanDevice> devices) {
    final currentUser = LanSyncService.instance.currentUserId;
    return devices
        .where((d) => _matchesUser(d.userId, currentUser))
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _target = widget.isOfflineMode
        ? ManualSyncTarget.lan
        : ManualSyncTarget.server;
    _lanPeers = _filterPeers(LanSyncService.instance.devices);
    _lanPeerCount = _lanPeers.isNotEmpty
        ? _lanPeers.length
        : widget.lanPeerCount;
    _lanDevicesSub = LanSyncService.instance.onDevicesChanged.listen((
      devices,
    ) {
      if (!mounted) return;
      final peers = _filterPeers(devices);
      setState(() {
        _lanPeers = peers;
        _lanPeerCount = peers.length;
      });
    });
    if (_target == ManualSyncTarget.lan && _lanPeerCount == 0) {
      unawaited(_scanLanPeers());
    }
    _selected = {
      _SyncModuleId.todos: true,
      _SyncModuleId.countdowns: true,
      _SyncModuleId.planBlocks: true,
      _SyncModuleId.fixedSchedules: true,
      _SyncModuleId.pomodoro: true,
      _SyncModuleId.timeLogs: true,
      _SyncModuleId.screenTime: true,
      _SyncModuleId.habits: true,
      _SyncModuleId.finance: widget.initialSyncFinance,
    };
  }

  @override
  void dispose() {
    unawaited(_lanDevicesSub?.cancel());
    super.dispose();
  }

  Future<void> _scanLanPeers() async {
    if (_isScanningLan) return;
    setState(() => _isScanningLan = true);
    try {
      await LanSyncService.instance.scanForPeersOnce();
      if (!mounted) return;
      final peers = _filterPeers(LanSyncService.instance.devices);
      setState(() {
        _lanPeers = peers;
        _lanPeerCount = peers.length;
      });
    } finally {
      if (mounted) {
        setState(() => _isScanningLan = false);
      }
    }
  }

  int get _selectedCount => _selected.values.where((v) => v).length;

  int get _totalCount => _selected.length;

  bool get _allSelected => _selectedCount == _totalCount;

  void _toggleModule(_SyncModuleId id) {
    HapticFeedback.selectionClick();
    setState(() {
      _selected[id] = !(_selected[id] ?? false);
    });
  }

  void _toggleAll() {
    HapticFeedback.selectionClick();
    final target = !_allSelected;
    setState(() {
      for (final key in _selected.keys) {
        _selected[key] = target;
      }
    });
  }

  ManualSyncSelection _buildSelection() {
    return ManualSyncSelection(
      syncTodos: _selected[_SyncModuleId.todos] ?? false,
      syncCountdowns: _selected[_SyncModuleId.countdowns] ?? false,
      syncScreenTime: _selected[_SyncModuleId.screenTime] ?? false,
      syncPomodoro: _selected[_SyncModuleId.pomodoro] ?? false,
      syncTimeLogs: _selected[_SyncModuleId.timeLogs] ?? false,
      syncPlanBlocks: _selected[_SyncModuleId.planBlocks] ?? false,
      syncFixedSchedules: _selected[_SyncModuleId.fixedSchedules] ?? false,
      syncHabits: _selected[_SyncModuleId.habits] ?? false,
      syncFinance: _selected[_SyncModuleId.finance] ?? false,
      target: _target,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final padding = widget.isBottomSheet
        ? const EdgeInsets.fromLTRB(20, 4, 20, 20)
        : const EdgeInsets.fromLTRB(24, 22, 24, 20);

    return SingleChildScrollView(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(theme, colorScheme),
          const SizedBox(height: 12),
          _buildChannelSelector(theme, colorScheme),
          const SizedBox(height: 16),
          for (int i = 0; i < _syncModuleGroups.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            _buildGroup(theme, colorScheme, _syncModuleGroups[i]),
          ],
          const SizedBox(height: 20),
          _buildActions(colorScheme),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, ColorScheme colorScheme) {
    final isLan = _target == ManualSyncTarget.lan;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            isLan ? Icons.wifi_tethering_rounded : Icons.cloud_sync_rounded,
            color: colorScheme.onPrimaryContainer,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '手动同步',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                isLan
                    ? '当前通道：局域网同步${_lanPeerCount > 0 ? "（已发现 $_lanPeerCount 台）" : "（未发现设备）"}'
                    : '当前通道：服务器同步 • 已选 $_selectedCount / $_totalCount 项模块',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: _toggleAll,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(_allSelected ? '取消全选' : '全选'),
        ),
      ],
    );
  }

  Widget _buildChannelSelector(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<ManualSyncTarget>(
          segments: [
            ButtonSegment<ManualSyncTarget>(
              value: ManualSyncTarget.server,
              enabled: !widget.isOfflineMode,
              icon: const Icon(Icons.cloud_sync_rounded, size: 18),
              label: const Text('服务器同步'),
            ),
            ButtonSegment<ManualSyncTarget>(
              value: ManualSyncTarget.lan,
              icon: const Icon(Icons.wifi_tethering_rounded, size: 18),
              label: Text(
                _lanPeerCount > 0 ? '局域网同步 ($_lanPeerCount)' : '局域网同步',
              ),
            ),
          ],
          selected: {_target},
          onSelectionChanged: (values) {
            if (values.isEmpty) return;
            HapticFeedback.selectionClick();
            final next = values.first;
            setState(() => _target = next);
            if (next == ManualSyncTarget.lan && _lanPeerCount == 0) {
              unawaited(_scanLanPeers());
            }
          },
        ),
        if (_target == ManualSyncTarget.lan && _lanPeers.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildLanDevicesCollapsible(theme, colorScheme),
        ] else if (_target == ManualSyncTarget.lan && _lanPeerCount == 0) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  _isScanningLan
                      ? '正在搜索同 Wi-Fi 同账号设备...'
                      : '暂未发现局域网设备，发现设备后才可点击同步',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _isScanningLan ? null : _scanLanPeers,
                icon: _isScanningLan
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 16),
                label: Text(_isScanningLan ? '搜索中' : '重新扫描'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ],
        if (widget.isOfflineMode) ...[
          const SizedBox(height: 6),
          Text(
            '离线模式已开启，服务器同步已禁用，仅可进行局域网同步',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLanDevicesCollapsible(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _isLanDevicesExpanded = !_isLanDevicesExpanded);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.devices_rounded,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '同步设备 (${_lanPeers.length} 台)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _isScanningLan ? null : _scanLanPeers,
                    tooltip: '重新扫描',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    icon: _isScanningLan
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.refresh_rounded,
                            size: 16,
                            color: colorScheme.onSurfaceVariant,
                          ),
                  ),
                  Icon(
                    _isLanDevicesExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_isLanDevicesExpanded) ...[
            Divider(
              height: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              child: Column(
                children: [
                  for (final device in _lanPeers)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 7,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              device.deviceName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${device.ip}:${device.port}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGroup(
    ThemeData theme,
    ColorScheme colorScheme,
    _SyncModuleGroup group,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            group.title,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 8.0;
            final halfWidth = (constraints.maxWidth - spacing) / 2;
            final modules = group.modules;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (int i = 0; i < modules.length; i++)
                  SizedBox(
                    // If a group has an odd count, let the final tile span
                    // full width so the grid stays balanced without a gap.
                    width: (modules.length.isOdd && i == modules.length - 1)
                        ? constraints.maxWidth
                        : halfWidth,
                    child: _buildModuleTile(theme, colorScheme, modules[i]),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildModuleTile(
    ThemeData theme,
    ColorScheme colorScheme,
    _SyncModuleSpec spec,
  ) {
    final isSelected = _selected[spec.id] ?? false;
    final borderColor = isSelected
        ? colorScheme.primary.withValues(alpha: 0.5)
        : colorScheme.outlineVariant.withValues(alpha: 0.45);
    final backgroundColor = isSelected
        ? colorScheme.primaryContainer.withValues(alpha: 0.55)
        : colorScheme.surfaceContainerLow;
    final foregroundColor = isSelected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;
    final iconColor = isSelected
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _toggleModule(spec.id),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: isSelected ? 1.2 : 1),
          ),
          child: Row(
            children: [
              Icon(spec.icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  spec.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 13.5,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: foregroundColor,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                isSelected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 18,
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.outline.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActions(ColorScheme colorScheme) {
    final count = _selectedCount;
    final isLanWaitingPeer =
        _target == ManualSyncTarget.lan && _lanPeerCount == 0;
    final canSync = count > 0 && !isLanWaitingPeer;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('取消'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            onPressed: canSync
                ? () => Navigator.pop(context, _buildSelection())
                : null,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: Icon(
              _target == ManualSyncTarget.lan
                  ? Icons.wifi_tethering_rounded
                  : Icons.cloud_sync_rounded,
              size: 18,
            ),
            label: Text(
              count <= 0
                  ? '请选择模块'
                  : isLanWaitingPeer
                  ? (_isScanningLan ? '正在搜索局域网设备...' : '未发现局域网设备')
                  : (_target == ManualSyncTarget.lan
                        ? '局域网同步 ($count)'
                        : '服务器同步 ($count)'),
            ),
          ),
        ),
      ],
    );
  }
}
