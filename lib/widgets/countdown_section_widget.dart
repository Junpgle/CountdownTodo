import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui';
import 'package:intl/intl.dart';
import 'package:CountDownTodo/models.dart';
import 'package:CountDownTodo/storage_service.dart';
import 'package:CountDownTodo/services/api_service.dart';
import 'package:CountDownTodo/screens/historical_countdowns_screen.dart';
import 'package:CountDownTodo/screens/app_board_screen.dart';
import '../services/pomodoro_sync_service.dart';
import '../widgets/home_sections.dart';
import '../utils/page_transitions.dart';
import 'version_history_sheet.dart';

class CountdownSectionWidget extends StatefulWidget {
  final List<CountdownItem> countdowns;
  final String username;
  final bool isLight;
  final VoidCallback onDataChanged;
  final Key? addKey; // 🚀 新增 addKey 用于高亮引导
  final Key? historyKey; // 🚀 新增 historyKey 用于高亮引导

  const CountdownSectionWidget({
    super.key,
    required this.countdowns,
    required this.username,
    required this.isLight,
    required this.onDataChanged,
    this.addKey,
    this.historyKey,
  });

  @override
  State<CountdownSectionWidget> createState() => _CountdownSectionWidgetState();
}

class _CountdownSectionWidgetState extends State<CountdownSectionWidget>
    with TickerProviderStateMixin {
  final Map<String, AnimationController> _pulseControllers = {};
  String? _selectedTeamUuid; // 🚀 选中的团队视口

  static const _holidayKeywords = [
    '假期',
    '放假',
    '休假',
    '春节',
    '国庆',
    '五一',
    '端午',
    '中秋',
    '元旦',
    '清明',
    '新年',
    '圣诞',
    'holiday',
    'vacation',
    'break',
  ];

  bool _isHolidayKeyword(String title) {
    final lower = title.toLowerCase();
    return _holidayKeywords.any((kw) => lower.contains(kw));
  }

  // 🚀 桌面端滑动优化：增加控制器
  late final ScrollController _listScrollController = ScrollController();
  late final ScrollController _tabsScrollController = ScrollController();

  @override
  void dispose() {
    _listScrollController.dispose();
    _tabsScrollController.dispose();
    for (final controller in _pulseControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addCountdown() => _showCountdownDialog();

  void _editCountdown(CountdownItem item) => _showCountdownDialog(item: item);

  Future<void> _showCountdownDialog({CountdownItem? item}) async {
    final bool isEditing = item != null;
    final teamData = await ApiService.fetchTeams();
    final teams = teamData.map((t) => Team.fromJson(t)).toList();

    TextEditingController titleCtrl = TextEditingController(text: item?.title);
    DateTime selectedDate =
        item?.targetDate ?? DateTime.now().add(const Duration(days: 1));
    String? selectedTeamUuid = item?.teamUuid ?? _selectedTeamUuid;
    String? selectedTeamName = item?.teamName;
    if (!isEditing && selectedTeamUuid != null && selectedTeamName == null) {
      selectedTeamName =
          teams.where((t) => t.uuid == selectedTeamUuid).firstOrNull?.name;
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEditing ? "编辑重要日" : "添加重要日"),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: "事项名称",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                  title: Text(
                    "目标日期: ${DateFormat('yyyy-MM-dd').format(selectedDate)}",
                    style: const TextStyle(fontSize: 14),
                  ),
                  trailing: const Icon(Icons.calendar_today, size: 20),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: isEditing ? DateTime(2000) : DateTime.now(),
                      lastDate: DateTime(2100),
                      initialDate: selectedDate,
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  initialValue: selectedTeamUuid,
                  decoration: InputDecoration(
                    labelText: '关联团队 (可选)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.groups_rounded),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text("仅自己可见")),
                    ...teams.map((t) => DropdownMenuItem(
                          value: t.uuid,
                          child: Text(t.name),
                        )),
                  ],
                  onChanged: (val) {
                    setDialogState(() {
                      selectedTeamUuid = val;
                      selectedTeamName = val != null
                          ? teams.where((t) => t.uuid == val).firstOrNull?.name
                          : null;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("取消"),
            ),
            FilledButton(
              onPressed: () async {
                if (titleCtrl.text.isNotEmpty) {
                  List<CountdownItem> updatedList =
                      List.from(widget.countdowns);
                  if (isEditing) {
                    final idx = updatedList.indexWhere((c) => c.id == item!.id);
                    if (idx != -1) {
                      updatedList[idx] = CountdownItem(
                        id: item.id,
                        title: titleCtrl.text,
                        targetDate: selectedDate,
                        isDeleted: item.isDeleted,
                        isCompleted: item.isCompleted,
                        version: item.version,
                        teamUuid: selectedTeamUuid,
                        teamName: selectedTeamName,
                        creatorId: item.creatorId,
                        creatorName: item.creatorName,
                        createdAt: item.createdAt,
                        updatedAt: DateTime.now().millisecondsSinceEpoch,
                        hasConflict: item.hasConflict,
                        conflictData: item.conflictData,
                      );
                      updatedList[idx].markAsChanged();
                    }
                  } else {
                    updatedList.add(CountdownItem(
                      title: titleCtrl.text,
                      targetDate: selectedDate,
                      teamUuid: selectedTeamUuid,
                      teamName: selectedTeamName,
                      creatorName: widget.username,
                    ));
                  }
                  await StorageService.saveCountdowns(
                      widget.username, updatedList);
                  final syncUuid =
                      isEditing ? item!.teamUuid : selectedTeamUuid;
                  if (syncUuid != null) {
                    PomodoroSyncService.instance.sendTeamUpdateSignal(syncUuid);
                  }
                  widget.onDataChanged();
                  if (mounted) Navigator.pop(ctx);
                }
              },
              child: Text(isEditing ? "保存" : "添加"),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteCountdown(CountdownItem itemToDelete) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("删除倒计时"),
        content: const Text("确定要删除这条倒计时吗？"),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("取消"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () async {
              await StorageService.deleteCountdownGlobally(
                  widget.username, itemToDelete.id);
              widget.onDataChanged();
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text("删除"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 修复：头部图标也根据深色模式动态调整
    final bool isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final bool useDarkUI = isDarkTheme || widget.isLight;

    // 🚀 提取动态团队列表
    final teams = <String>{};
    for (var c in widget.countdowns) {
      if (c.teamUuid != null) teams.add(c.teamUuid!);
    }

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                  child: SectionHeader(
                      title: "重要日",
                      icon: Icons.timer,
                      onAdd: _addCountdown,
                      addKey: widget.addKey, // 🚀 传递 addKey
                      isLight: widget.isLight)),
              if (MediaQuery.of(context).size.width >= 600)
                IconButton(
                  icon: Icon(Icons.dashboard_rounded,
                      color: useDarkUI ? Colors.white70 : Colors.grey),
                  tooltip: '看板',
                  onPressed: () async {
                    await Navigator.push(
                        context,
                        PageTransitions.slideHorizontal(
                            AppBoardScreen(username: widget.username)));
                    widget.onDataChanged();
                  },
                ),
              SizedBox(
                key: widget.historyKey,
                child: IconButton(
                  icon: Icon(Icons.history,
                      color: useDarkUI ? Colors.white70 : Colors.grey),
                  onPressed: () async {
                    await Navigator.push(
                        context,
                        PageTransitions.slideHorizontal(
                            HistoricalCountdownsScreen(
                                username: widget.username)));
                    widget.onDataChanged();
                  },
                ),
              ),
            ],
          ),
          if (teams.isNotEmpty) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              controller: _tabsScrollController,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildTeamTab("全部", null, useDarkUI),
                  ...teams.map((uuid) {
                    final name = widget.countdowns
                            .firstWhere((c) => c.teamUuid == uuid)
                            .teamName ??
                        "团队项目";
                    return _buildTeamTab(name, uuid, useDarkUI);
                  }),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          _buildList(),
        ],
      ),
    );
  }

  Widget _buildTeamTab(String label, String? uuid, bool useDarkUI) {
    bool isSelected = _selectedTeamUuid == uuid;
    final theme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => setState(() => _selectedTeamUuid = uuid),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.primary
              : (useDarkUI ? Colors.white10 : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected
                ? Colors.white
                : (useDarkUI ? Colors.white70 : Colors.black87),
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final List<CountdownItem> activeCountdowns =
        widget.countdowns.where((item) {
      if (_selectedTeamUuid != null && item.teamUuid != _selectedTeamUuid) {
        return false;
      }
      return item.targetDate.difference(today).inDays >= 0;
    }).toList()
          ..sort((a, b) => a.targetDate.compareTo(b.targetDate));

    // 清理已删除倒计时项的 pulse controller，防止内存泄漏
    final currentIds = activeCountdowns.map((c) => c.id).toSet();
    _pulseControllers.keys
        .where((id) => !currentIds.contains(id))
        .toList()
        .forEach((id) {
      _pulseControllers[id]?.dispose();
      _pulseControllers.remove(id);
    });

    if (activeCountdowns.isEmpty) {
      return EmptyState(text: "暂无有效倒计时", isLight: widget.isLight);
    }

    return SizedBox(
      height: 130, // 🚀 适度增加总高度，防止小屏幕溢出
      child: ClipRect(
        clipper: _HorizontalClipper(),
        child: ListView.builder(
          scrollCacheExtent: ScrollCacheExtent.pixels(1000), controller: _listScrollController,
          padding: const EdgeInsets.only(right: 12),
          clipBehavior: Clip.none,
          scrollDirection: Axis.horizontal,
          itemCount: activeCountdowns.length,
          itemBuilder: (context, index) {
              final item = activeCountdowns[index];
              final diff = item.targetDate.difference(today).inDays;

              final bool isUrgent = diff <= 3;
              final bool isHoliday = _isHolidayKeyword(item.title);

              if (isUrgent &&
                  !isHoliday &&
                  !_pulseControllers.containsKey(item.id)) {
                final controller = AnimationController(
                  duration: const Duration(milliseconds: 800),
                  vsync: this,
                )..repeat(reverse: true);
                _pulseControllers[item.id] = controller;
              } else if ((!isUrgent || isHoliday) &&
                  _pulseControllers.containsKey(item.id)) {
                _pulseControllers[item.id]?.dispose();
                _pulseControllers.remove(item.id);
              }

              // 核心修复：增加系统级别的深色模式检测
              final bool isDarkTheme =
                  Theme.of(context).brightness == Brightness.dark;
              final bool useDarkUI = isDarkTheme || widget.isLight;

              final Color bgColor = useDarkUI
                  ? (isUrgent && isHoliday
                      ? Colors.greenAccent.withAlpha((0.18 * 255).round())
                      : isUrgent
                          ? Colors.redAccent.withAlpha((0.25 * 255).round())
                          : (widget.isLight
                              ? Colors.white.withAlpha((0.1 * 255).round())
                              : Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withAlpha((0.5 * 255).round())))
                  : (isUrgent && isHoliday
                      ? Colors.green.shade50
                      : isUrgent
                          ? Colors.red.shade50
                          : Theme.of(context).colorScheme.surface);

              final borderColor = useDarkUI
                  ? (isUrgent && isHoliday
                      ? Colors.greenAccent.withAlpha((0.5 * 255).round())
                      : isUrgent
                          ? Colors.redAccent.withAlpha((0.5 * 255).round())
                          : Colors.white.withAlpha((0.15 * 255).round()))
                  : (isUrgent && isHoliday
                      ? Colors.green.withAlpha((0.3 * 255).round())
                      : isUrgent
                          ? Colors.redAccent.withAlpha((0.3 * 255).round())
                          : Colors.black.withAlpha((0.05 * 255).round()));

              final textColor = useDarkUI
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurface;

              final subTextColor = useDarkUI
                  ? Colors.white70
                  : Theme.of(context).colorScheme.onSurfaceVariant;

              final accentColor = useDarkUI
                  ? (isUrgent && isHoliday
                      ? Colors.greenAccent.shade100
                      : isUrgent
                          ? Colors.redAccent.shade100
                          : Colors.white)
                  : (isUrgent && isHoliday
                      ? Colors.green
                      : isUrgent
                          ? Colors.redAccent
                          : Theme.of(context).colorScheme.primary);

              final closeBgColor = useDarkUI
                  ? Colors.white.withAlpha((0.15 * 255).round())
                  : Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withAlpha((0.05 * 255).round());

              return RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _pulseControllers[item.id] ??
                      const AlwaysStoppedAnimation(0.0),
                  builder: (context, child) {
                    if (!isUrgent || isHoliday) return child!;
                    final pulse = _pulseControllers[item.id]?.value ?? 0.0;
                    final glowOpacity = 0.3 + (pulse * 0.4);
                    final glowSpread = 4.0 + (pulse * 8.0);
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.redAccent.withAlpha(
                              (glowOpacity * 255).round(),
                            ),
                            blurRadius: glowSpread,
                            spreadRadius: glowSpread * 0.3,
                          ),
                        ],
                      ),
                      child: child,
                    );
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        width: 130,
                        margin: const EdgeInsets.only(right: 12, bottom: 8),
                        // 🚀 微调边距
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: borderColor),
                          boxShadow: useDarkUI
                              ? []
                              : [
                                  BoxShadow(
                                    color: Colors.black
                                        .withAlpha((0.04 * 255).round()),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  )
                                ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => _editCountdown(item),
                            onLongPress: () => VersionHistorySheet.show(
                                context, item.id, 'countdowns', item.title),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: textColor,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                            height: 1.2,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      InkWell(
                                        onTap: () => _deleteCountdown(item),
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: closeBgColor,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            Icons.close,
                                            size: 12,
                                            color: subTextColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (item.teamUuid != null) ...[
                                    const SizedBox(height: 2), // 🚀 紧凑化
                                    Row(
                                      children: [
                                        Icon(Icons.groups_rounded,
                                            size: 10,
                                            color: accentColor.withValues(
                                                alpha: 0.6)),
                                        const SizedBox(width: 3),
                                        Expanded(
                                          child: Text(
                                            "${item.teamName ?? '团队'} · ${item.creatorName ?? '成员'}",
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 8,
                                              color: subTextColor.withValues(
                                                  alpha: 0.8),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ] else ...[
                                    const SizedBox(height: 12),
                                    // 填补未绑定团队时的空白，保持与其他卡片高度一致 (2 + 10)
                                  ],
                                  const SizedBox(height: 6),
                                  // 🚀 取代 Spacer()，提供稳定间距
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        "$diff",
                                        style: TextStyle(
                                          fontSize: 28, // 🚀 稍微缩小，防止垂直挤压
                                          height: 1.0,
                                          fontWeight: FontWeight.bold,
                                          color: accentColor,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 4.0),
                                        child: Text(
                                          "天",
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: subTextColor,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  // 🚀 紧凑化
                                  Text(
                                    "目标日: ${DateFormat('yyyy-MM-dd').format(item.targetDate)}",
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: subTextColor,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        )
    );
  }
}

class _HorizontalClipper extends CustomClipper<Rect> {
  @override
  Rect getClip(Size size) {
    // 允许上下溢出 50 像素（为了保留红色发光阴影），但左右严格裁剪（防止溢出到右侧日程列）
    return Rect.fromLTRB(0, -50, size.width, size.height + 50);
  }

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}

