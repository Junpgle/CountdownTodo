import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models.dart';
import '../../storage_service.dart';
import '../screens/historical_countdowns_screen.dart';
import '../widgets/home_sections.dart';
import '../utils/page_transitions.dart';

class CountdownSectionWidget extends StatefulWidget {
  final List<CountdownItem> countdowns;
  final String username;
  final bool isLight;
  final VoidCallback onDataChanged;

  const CountdownSectionWidget({
    super.key,
    required this.countdowns,
    required this.username,
    required this.isLight,
    required this.onDataChanged,
  });

  @override
  State<CountdownSectionWidget> createState() => _CountdownSectionWidgetState();
}

class _CountdownSectionWidgetState extends State<CountdownSectionWidget>
    with TickerProviderStateMixin {
  final Map<String, AnimationController> _pulseControllers = {};
  String? _selectedTeamUuid; // 🚀 选中的团队视口

  @override
  void dispose() {
    for (final controller in _pulseControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addCountdown() {
    TextEditingController titleCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    String? selectedTeamUuid = _selectedTeamUuid;

    // 获取现有团队
    final existingTeams = <String, String>{};
    for (var c in widget.countdowns) {
      if (c.teamUuid != null && c.teamName != null) {
        existingTeams[c.teamUuid!] = c.teamName!;
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("添加重要日"),
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
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2100),
                      initialDate: selectedDate,
                    );
                    if (picked != null)
                      setDialogState(() => selectedDate = picked);
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  value: selectedTeamUuid,
                  decoration: InputDecoration(
                    labelText: '关联团队 (可选)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.groups_rounded),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text("仅自己可见")),
                    ...existingTeams.keys.map((uuid) => DropdownMenuItem(
                          value: uuid,
                          child: Text("已有团队"),
                        )),
                  ],
                  onChanged: (val) => setDialogState(() => selectedTeamUuid = val),
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
                  final selectedTeamName = selectedTeamUuid != null ? existingTeams[selectedTeamUuid] : null;
                  updatedList.add(CountdownItem(
                    title: titleCtrl.text,
                    targetDate: selectedDate,
                    teamUuid: selectedTeamUuid,
                    teamName: (selectedTeamName != "关联团队" && selectedTeamName != null) ? selectedTeamName : null,
                    creatorName: widget.username,
                  ));
                  await StorageService.saveCountdowns(
                      widget.username, updatedList);
                  widget.onDataChanged();
                  if (mounted) Navigator.pop(ctx);
                }
              },
              child: const Text("添加"),
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

    return Column(
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
                    isLight: widget.isLight)),
            IconButton(
              icon: Icon(Icons.history,
                  color: useDarkUI ? Colors.white70 : Colors.grey),
              onPressed: () async {
                await Navigator.push(
                    context,
                    PageTransitions.slideHorizontal(
                        HistoricalCountdownsScreen(username: widget.username)));
                widget.onDataChanged();
              },
            ),
          ],
        ),
        if (teams.isNotEmpty) ...[
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildTeamTab("全部", null, useDarkUI),
                ...teams.map((uuid) {
                  final name = widget.countdowns.firstWhere((c) => c.teamUuid == uuid).teamName ?? "团队项目";
                  return _buildTeamTab(name, uuid, useDarkUI);
                }),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        _buildList(),
      ],
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
          color: isSelected ? theme.primary : (useDarkUI ? Colors.white10 : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : (useDarkUI ? Colors.white70 : Colors.black87),
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
      if (_selectedTeamUuid != null && item.teamUuid != _selectedTeamUuid) return false;
      return item.targetDate.difference(today).inDays >= 0;
    }).toList()
          ..sort((a, b) => a.targetDate.compareTo(b.targetDate));

    if (activeCountdowns.isEmpty) {
      return EmptyState(text: "暂无有效倒计时", isLight: widget.isLight);
    }

    return SizedBox(
      height: 120, // reduced from 140 to make cards smaller
      child: ListView.builder(
        clipBehavior: Clip.none,
        scrollDirection: Axis.horizontal,
        itemCount: activeCountdowns.length,
        itemBuilder: (context, index) {
          final item = activeCountdowns[index];
          final diff = item.targetDate.difference(today).inDays;

          final bool isUrgent = diff <= 3;

          if (isUrgent && !_pulseControllers.containsKey(item.id)) {
            final controller = AnimationController(
              duration: const Duration(milliseconds: 800),
              vsync: this,
            )..repeat(reverse: true);
            _pulseControllers[item.id] = controller;
          } else if (!isUrgent && _pulseControllers.containsKey(item.id)) {
            _pulseControllers[item.id]?.dispose();
            _pulseControllers.remove(item.id);
          }

          // 核心修复：增加系统级别的深色模式检测
          final bool isDarkTheme =
              Theme.of(context).brightness == Brightness.dark;
          final bool useDarkUI = isDarkTheme || widget.isLight;

          final bgColor = useDarkUI
              ? (isUrgent
                  ? Colors.redAccent.withAlpha((0.25 * 255).round())
                  : (widget.isLight
                      ? Colors.white.withAlpha((0.1 * 255).round())
                      : Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withAlpha((0.5 * 255).round())))
              : (isUrgent
                  ? Colors.red.shade50
                  : Theme.of(context).colorScheme.surface);

          final borderColor = useDarkUI
              ? (isUrgent
                  ? Colors.redAccent.withAlpha((0.5 * 255).round())
                  : Colors.white.withAlpha((0.15 * 255).round()))
              : (isUrgent
                  ? Colors.redAccent.withAlpha((0.3 * 255).round())
                  : Colors.black.withAlpha((0.05 * 255).round()));

          final textColor = useDarkUI
              ? Colors.white
              : Theme.of(context).colorScheme.onSurface;

          final subTextColor = useDarkUI
              ? Colors.white70
              : Theme.of(context).colorScheme.onSurfaceVariant;

          final accentColor = useDarkUI
              ? (isUrgent ? Colors.redAccent.shade100 : Colors.white)
              : (isUrgent
                  ? Colors.redAccent
                  : Theme.of(context).colorScheme.primary);

          final closeBgColor = useDarkUI
              ? Colors.white.withAlpha((0.15 * 255).round())
              : Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withAlpha((0.05 * 255).round());

          return AnimatedBuilder(
            animation:
                _pulseControllers[item.id] ?? const AlwaysStoppedAnimation(0.0),
            builder: (context, child) {
              if (!isUrgent) return child!;
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
            child: Container(
              width: 130,
              margin: const EdgeInsets.only(right: 12, bottom: 10),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderColor),
                boxShadow: useDarkUI
                    ? []
                    : [
                        BoxShadow(
                          color: Colors.black.withAlpha((0.04 * 255).round()),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
              ),
              child: Material(
                color: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.groups_rounded, 
                                size: 10, 
                                color: accentColor.withOpacity(0.6)),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                "${item.teamName ?? '团队'} · ${item.creatorName ?? '成员'}",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 8,
                                  color: subTextColor.withOpacity(0.8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const Spacer(),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            "$diff",
                            style: TextStyle(
                              fontSize: 32,
                              height: 1.0,
                              fontWeight: FontWeight.bold,
                              color: accentColor,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6.0),
                            child: Text(
                              "天",
                              style: TextStyle(
                                fontSize: 12,
                                color: subTextColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "目标日: ${DateFormat('yyyy-MM-dd').format(item.targetDate)}",
                        style: TextStyle(
                          fontSize: 10,
                          color: subTextColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
