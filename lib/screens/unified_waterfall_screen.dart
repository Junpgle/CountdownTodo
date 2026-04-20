import 'dart:ui';
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
  int _viewDays = 30; // 默认月视图
  DateTime _lastScaleTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadAllTeamData();
    StorageService.dataRefreshNotifier.addListener(_loadAllTeamData);
  }

  @override
  void dispose() {
    StorageService.dataRefreshNotifier.removeListener(_loadAllTeamData);
    super.dispose();
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

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (DateTime.now().difference(_lastScaleTime).inMilliseconds < 300) return;

    final scale = details.scale;
    if (scale > 1.3 && _viewDays > 7) {
      // 放大 -> 显示更少天数
      setState(() {
        _viewDays = _viewDays == 30 ? 14 : 7;
        _lastScaleTime = DateTime.now();
      });
    } else if (scale < 0.7 && _viewDays < 30) {
      // 缩小 -> 显示更多天数
      setState(() {
        _viewDays = _viewDays == 7 ? 14 : 30;
        _lastScaleTime = DateTime.now();
      });
    }
  }

  void _showTodoDetails(TodoItem todo) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.only(left: 24, right: 24, bottom: 40, top: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, -5),
            )
          ],
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部拖拽指示器
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.assignment_outlined, color: Colors.blueAccent),
                  ),
                  const SizedBox(width: 12),
                  const Text("任务明细", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    style: IconButton.styleFrom(backgroundColor: Colors.grey.withOpacity(0.1)),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(todo.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, height: 1.3)),
              const SizedBox(height: 20),

              if (todo.remark != null && todo.remark!.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.withOpacity(0.1)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.notes_rounded, size: 18, color: Colors.grey.shade500),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          todo.remark!,
                          style: TextStyle(fontSize: 14, color: isDark ? Colors.grey.shade400 : Colors.grey.shade700, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),

              Row(
                children: [
                  Expanded(child: _buildDetailCard(Icons.calendar_month_rounded, "截止日期", todo.dueDate != null ? TimezoneUtils.getRelativeTime(todo.dueDate!.millisecondsSinceEpoch) : "未设置", Colors.orange)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildDetailCard(Icons.groups_rounded, "所属团队", todo.teamName ?? "个人任务", Colors.purple)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailCard(IconData icon, String label, String value, MaterialColor color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color.shade400),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  /// 🚀 防止非法 UTF-16 代理对导致 Flutter ParagraphBuilder 崩溃
  String _safeStr(String? s) {
    if (s == null) return '';
    return s.replaceAll(RegExp(r'[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(^|[^\uD800-\uDBFF])[\uDC00-\uDFFF]'), '');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF7F8FA);

    return Scaffold(
      backgroundColor: bgColor,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : GestureDetector(
        onScaleUpdate: _handleScaleUpdate,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            SliverAppBar(
              floating: true,
              pinned: true,
              expandedHeight: 60,
              elevation: 0,
              backgroundColor: isDark ? Colors.black.withOpacity(0.65) : Colors.white.withOpacity(0.65),
              flexibleSpace: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(color: Colors.transparent),
                ),
              ),
              title: const Text('全景汇聚看板', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              centerTitle: false,
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: '刷新数据',
                    onPressed: _loadAllTeamData,
                  ),
                ),
              ],
            ),

            // 🚀 看板功能区 (热力图 & 甘特图)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: isDark ? Colors.white10 : Colors.transparent),
                  boxShadow: [
                    BoxShadow(
                      color: isDark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.04),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    )
                  ],
                ),
                child: Column(
                  children: [
                    TeamHeatmapWidget(todos: _allCombinedTodos, viewDays: _viewDays == 30 ? 35 : _viewDays),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey.withOpacity(0.1)),
                    ),
                    TeamGanttWidget(
                      todos: _allCombinedTodos,
                      viewDays: _viewDays,
                      onTodoTap: _showTodoDetails,
                    ),
                  ],
                ),
              ),
            ),

            // 数据指标行
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(child: _buildStatChip(context, "活跃任务", "${_allCombinedTodos.length}", Colors.blue, Icons.flash_on_rounded)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildStatChip(context, "团队关联", "${_allCombinedTodos.where((t) => t.teamUuid != null).length}", Colors.purple, Icons.hub_rounded)),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 16)),

            // 任务流
            _allCombinedTodos.isEmpty
                ? SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.task_alt_rounded, size: 64, color: Colors.grey.withOpacity(0.3)),
                    const SizedBox(height: 16),
                    Text("暂无活跃的全景任务", style: TextStyle(fontSize: 16, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            )
                : SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildWaterfallItem(_allCombinedTodos[index], isLast: index == _allCombinedTodos.length - 1),
                  childCount: _allCombinedTodos.length,
                ),
              ),
            ),

            // 底部留白
            SliverToBoxAdapter(
              child: SizedBox(height: MediaQuery.of(context).padding.bottom + 50),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(BuildContext context, String label, String value, MaterialColor color, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(isDark ? 0.2 : 0.08), color.withOpacity(isDark ? 0.05 : 0.02)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(isDark ? 0.3 : 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color.shade400),
              const SizedBox(width: 6),
              Text(_safeStr(label), style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          Text(_safeStr(value), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildWaterfallItem(TodoItem todo, {required bool isLast}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    bool isTeamTask = todo.teamUuid != null;
    Color teamColor = isTeamTask ? Colors.blue.shade500 : Colors.orange.shade500;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左侧时间点与团队标识线
          SizedBox(
            width: 24,
            child: Column(
              children: [
                const SizedBox(height: 24), // 对齐卡片视觉中心
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: teamColor, width: 3),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: teamColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 右侧卡片内容
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isDark ? Colors.white10 : Colors.transparent),
                boxShadow: [
                  BoxShadow(
                    color: isDark ? Colors.black.withOpacity(0.2) : Colors.black.withOpacity(0.03),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // 🚀 优化的标签样式
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: teamColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(isTeamTask ? Icons.group_rounded : Icons.person_rounded, size: 10, color: teamColor),
                            const SizedBox(width: 4),
                            Text(
                              isTeamTask ? _safeStr(todo.teamName ?? '未知团队') : "个人私密",
                              style: TextStyle(fontSize: 10, color: teamColor, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Icon(Icons.schedule_rounded, size: 12, color: Colors.grey.shade400),
                          const SizedBox(width: 4),
                          Text(
                            _safeStr(TimezoneUtils.getRelativeTime(todo.dueDate?.millisecondsSinceEpoch ?? todo.updatedAt)),
                            style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(_safeStr(todo.title), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.3)),
                  if (todo.remark != null && todo.remark!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _safeStr(todo.remark!),
                        style: TextStyle(fontSize: 13, color: isDark ? Colors.grey.shade500 : Colors.grey.shade600, height: 1.4),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
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