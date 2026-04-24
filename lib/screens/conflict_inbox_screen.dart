import 'package:flutter/material.dart';
import '../models.dart';
import '../storage_service.dart';
import 'package:intl/intl.dart';

class ConflictInboxScreen extends StatefulWidget {
  final String username;
  const ConflictInboxScreen({super.key, required this.username});

  @override
  State<ConflictInboxScreen> createState() => _ConflictInboxScreenState();
}

class _ConflictInboxScreenState extends State<ConflictInboxScreen> {
  List<dynamic> _conflictItems = []; // 可以包含 TodoItem, CountdownItem, TodoGroup
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConflicts();
  }

  Future<void> _loadConflicts() async {
    setState(() => _isLoading = true);
    final todos = await StorageService.getTodos(widget.username, includeDeleted: true);
    final groups = await StorageService.getTodoGroups(widget.username, includeDeleted: true);
    final countdowns = await StorageService.getCountdowns(widget.username);

    final List<dynamic> items = [];
    items.addAll(todos.where((t) => t.hasConflict));
    items.addAll(groups.where((g) => g.hasConflict));
    items.addAll(countdowns.where((c) => c.hasConflict));

    // 按更新时间倒序
    items.sort((a, b) {
      int timeA = (a is TodoItem) ? a.updatedAt : (a is TodoGroup ? a.updatedAt : (a as CountdownItem).updatedAt);
      int timeB = (b is TodoItem) ? b.updatedAt : (b is TodoGroup ? b.updatedAt : (b as CountdownItem).updatedAt);
      return timeB.compareTo(timeA);
    });

    if (mounted) {
      setState(() {
        _conflictItems = items;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('数据冲突对齐中心', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, size: 20),
            onPressed: _showConflictHelp,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: _loadConflicts,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _conflictItems.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _conflictItems.length,
                  itemBuilder: (context, index) {
                    return _buildConflictCard(_conflictItems[index]);
                  },
                ),
    );
  }

  void _showConflictHelp() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("什么是数据冲突？", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildHelpItem(Icons.devices_rounded, "多端编辑争议", "当你在不同设备上同时修改同一个任务，且系统无法判定哪个版本更新时，会标记为冲突。"),
            _buildHelpItem(Icons.history_rounded, "版本回退", "如果你的本地版本低于云端，但你强行进行了覆盖，系统会保留云端备份并提示争议。"),
            _buildHelpItem(Icons.sync_problem_rounded, "逻辑冲突", "如多个人同时预约了同一个时间段的日程，系统会标记该日程存在冲突。"),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("知道了"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpItem(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                Text(desc, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.verified_user_rounded, size: 80, color: Colors.green.withOpacity(0.2)),
          const SizedBox(height: 16),
          const Text("所有数据已完全对齐", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          const Text("目前没有任何待解决的同步冲突", style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildConflictCard(dynamic item) {
    String title = "";
    String subtitle = "";
    String typeLabel = "版本争议";
    int timestamp = 0;
    IconData icon = Icons.help_outline;

    if (item is TodoItem) {
      title = item.title;
      subtitle = item.remark ?? "待办任务";
      timestamp = item.updatedAt;
      icon = Icons.check_circle_outline;
    } else if (item is TodoGroup) {
      title = item.name;
      subtitle = "分组/文件夹";
      timestamp = item.updatedAt;
      icon = Icons.folder_open;
    } else if (item is CountdownItem) {
      title = item.title;
      subtitle = "倒计时项";
      timestamp = item.updatedAt;
      icon = Icons.event;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => _resolveConflict(item),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.amber.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 12, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(typeLabel, style: const TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    DateFormat('MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(timestamp)),
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.blue.withOpacity(0.1),
                    child: Icon(icon, size: 18, color: Colors.blue),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _resolveConflict(item),
                    icon: const Icon(Icons.compare_arrows_rounded, size: 16),
                    label: const Text("对比并解决", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  void _resolveConflict(dynamic item) {
    // 🚀 后续可扩展 Diff 视图
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("正在加载服务器版本数据..."), duration: Duration(seconds: 1)),
    );
  }
}
