import 'package:flutter/material.dart';
import '../models.dart';
import '../storage_service.dart';
import '../utils/timezone_utils.dart';
import '../widgets/team_heatmap_widget.dart';
import '../widgets/team_gantt_widget.dart';

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

  /// 🚀 防止非法 UTF-16 代理对导致 Flutter ParagraphBuilder 崩溃
  String _safeStr(String? s) {
    if (s == null) return '';
    return s.replaceAll(RegExp(r'[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(^|[^\uD800-\uDBFF])[\uDC00-\uDFFF]'), '');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF2F4F7),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverAppBar(
                  floating: true,
                  pinned: true,
                  expandedHeight: 60,
                  backgroundColor: isDark ? const Color(0xFF0F0F0F).withOpacity(0.9) : Colors.white.withOpacity(0.9),
                  title: const Text('全景汇聚看板', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  centerTitle: false,
                  actions: [
                    IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _loadAllTeamData),
                  ],
                ),
                
                // 🚀 看板功能区 (热力图 & 甘特图)
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 8))],
                    ),
                    child: Column(
                      children: [
                        TeamHeatmapWidget(todos: _allCombinedTodos),
                        const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(indent: 16, endIndent: 16)),
                        TeamGanttWidget(todos: _allCombinedTodos),
                      ],
                    ),
                  ),
                ),

                // 数据指标行
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        _buildStatChip(context, "活跃任务", "${_allCombinedTodos.length}", Colors.blue),
                        const SizedBox(width: 8),
                        _buildStatChip(context, "团队关联", "${_allCombinedTodos.where((t)=>t.teamUuid!=null).length}", Colors.purple),
                      ],
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 12)),

                // 任务流
                _allCombinedTodos.isEmpty
                    ? const SliverFillRemaining(child: Center(child: Text("暂无活跃的全景任务")))
                    : SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => _buildWaterfallItem(_allCombinedTodos[index]),
                            childCount: _allCombinedTodos.length,
                          ),
                        ),
                      ),
                const SliverToBoxAdapter(child: SizedBox(height: 50)),
              ],
            ),
    );
  }

  Widget _buildStatChip(BuildContext context, String label, String value, Color color) {
    return Expanded(
      child: Container(
        constraints: const BoxConstraints(minHeight: 80),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_safeStr(label), style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(_safeStr(value), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ),
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
                          isTeamTask ? "@${_safeStr(todo.teamName ?? '未知团队')}" : "#个人私密",
                          style: TextStyle(fontSize: 9, color: teamColor, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _safeStr(TimezoneUtils.getRelativeTime(todo.dueDate?.millisecondsSinceEpoch ?? todo.updatedAt)),
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(_safeStr(todo.title), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  if (todo.remark != null && todo.remark!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(_safeStr(todo.remark!), style: const TextStyle(fontSize: 11, color: Colors.grey), maxLines: 2),
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
