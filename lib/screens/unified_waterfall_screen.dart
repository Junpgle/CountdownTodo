import 'package:flutter/material.dart';
import '../models.dart';
import '../storage_service.dart';
import '../utils/timezone_utils.dart';

class UnifiedWaterfallScreen extends StatefulWidget {
  final String username;
  const UnifiedWaterfallScreen({super.key, required this.username});

  @override
  State<UnifiedWaterfallScreen> createState() => _UnifiedWaterfallScreenState();
}

class _UnifiedWaterfallScreenState extends State<UnifiedWaterfallScreen> {
  List<TodoItem> _allCombinedTodos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllTeamData();
  }

  Future<void> _loadAllTeamData() async {
    final todos = await StorageService.getTodos(widget.username);
    // 过滤并排序：仅显示未完成且未删除的，按更新时间/截止时间排序
    final filtered = todos.where((t) => !t.isDeleted && !t.isDone).toList();
    filtered.sort((a, b) => (b.dueDate?.millisecondsSinceEpoch ?? b.updatedAt)
        .compareTo(a.dueDate?.millisecondsSinceEpoch ?? a.updatedAt));

    if (mounted) {
      setState(() {
        _allCombinedTodos = filtered;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF2F4F7),
      appBar: AppBar(
        title: const Text('全景汇聚时间轴', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded, size: 20),
            onPressed: () {
              // TODO: 过滤团队
            },
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _allCombinedTodos.isEmpty
              ? const Center(child: Text("暂无活跃的全景任务"))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _allCombinedTodos.length,
                  itemBuilder: (context, index) {
                    return _buildWaterfallItem(_allCombinedTodos[index]);
                  },
                ),
    );
  }

  Widget _buildWaterfallItem(TodoItem todo) {
    bool isTeamTask = todo.teamUuid != null;
    Color teamColor = isTeamTask ? Colors.blue[600]! : Colors.orange[600]!;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左侧时间点与团队标识线
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: teamColor, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
              ),
              Expanded(child: Container(width: 2, color: teamColor.withOpacity(0.2))),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // 🚀 Uni-Sync 核心：团队名标签 (Team Tag)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: teamColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                        child: Text(
                          isTeamTask ? "@${todo.teamName ?? '未知团队'}" : "#个人私密",
                          style: TextStyle(fontSize: 9, color: teamColor, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        TimezoneUtils.getRelativeTime(todo.dueDate?.millisecondsSinceEpoch ?? todo.updatedAt),
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(todo.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  if (todo.remark != null && todo.remark!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(todo.remark!, style: const TextStyle(fontSize: 11, color: Colors.grey), maxLines: 2),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
