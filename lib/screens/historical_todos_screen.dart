import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../storage_service.dart';

class HistoricalTodosScreen extends StatefulWidget {
  final String username;
  const HistoricalTodosScreen({Key? key, required this.username})
      : super(key: key);

  @override
  State<HistoricalTodosScreen> createState() => _HistoricalTodosScreenState();
}

class _HistoricalTodosScreenState extends State<HistoricalTodosScreen>
    with SingleTickerProviderStateMixin {
  List<TodoItem> _history = [];
  List<TodoItem> _deletedTodos = [];
  List<TodoItem> _orphanTodos = [];
  bool _isLoading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool _isHistorical(TodoItem t) {
    if (!t.isDone) return false;
    DateTime today = DateTime.now();
    today = DateTime(today.year, today.month, today.day);

    if (t.dueDate != null) {
      DateTime d = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
      return d.isBefore(today);
    } else {
      DateTime cDate = DateTime.fromMillisecondsSinceEpoch(
              t.createdDate ?? t.createdAt,
              isUtc: true)
          .toLocal();
      DateTime c = DateTime(cDate.year, cDate.month, cDate.day);
      return c.isBefore(today);
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final allTodos = await StorageService.getTodos(widget.username, includeDeleted: true);
    final groups = await StorageService.getTodoGroups(widget.username, includeDeleted: true);
    final activeGroupIds = groups.where((g) => !g.isDeleted).map((g) => g.id).toSet();

    setState(() {
      // 1. 历史记录：已完成、日期在今天之前、未被逻辑删除
      _history = allTodos.where((t) => _isHistorical(t) && !t.isDeleted).toList();
      _history.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      // 2. 回收站：逻辑删除的数据
      _deletedTodos = allTodos.where((t) => t.isDeleted).toList();
      _deletedTodos.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      // 3. 孤儿待办：未删除、未完成，且符合以下任一可见性异常条件的：
      //   - 带有无效的 groupId (空字符串，或者 ID 不在活跃群组中)
      //   - 或者：由于某些元数据异常导致可能在主页隐藏的（作为兜底）
      _orphanTodos = allTodos.where((t) {
        if (t.isDeleted || t.isDone) return false;
        
        // 情况 A: 带有空字符串 groupId (会导致在旧版本 UI 中消失)
        if (t.groupId != null && t.groupId!.isEmpty) return true;
        
        // 情况 B: 带有 groupId 但对应的组找不到或已删除
        if (t.groupId != null && !activeGroupIds.contains(t.groupId)) return true;
        
        return false;
      }).toList();
      _orphanTodos.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      debugPrint("🔍 数据扫描完成: 历史=${_history.length}, 回收站=${_deletedTodos.length}, 孤儿=${_orphanTodos.length}");
      _isLoading = false;
    });
  }

  Future<void> _deleteItem(TodoItem item) async {
    try {
      await StorageService.deleteTodoGlobally(widget.username, item.id);
      final allTodos = await StorageService.getTodos(widget.username);
      final index = allTodos.indexWhere((t) => t.id == item.id);
      if (index != -1) {
        allTodos[index].isDeleted = true;
        allTodos[index].markAsChanged();
        await StorageService.saveTodos(widget.username, allTodos, sync: true);
      }
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已移至回收站')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除失败，请稍后再试')),
        );
      }
    }
  }

  Future<void> _uncheckItem(TodoItem item) async {
    final allTodos = await StorageService.getTodos(widget.username);
    int idx = allTodos.indexWhere((t) => t.id == item.id);
    if (idx != -1) {
      allTodos[idx].isDone = false;
      allTodos[idx].markAsChanged();
      await StorageService.saveTodos(widget.username, allTodos, sync: true);
    }
    _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('待办已取消完成，并退回主页清单')));
    }
  }

  Future<void> _restoreDeletedItem(TodoItem item) async {
    final allTodos = await StorageService.getTodos(widget.username);
    int idx = allTodos.indexWhere((t) => t.id == item.id);
    if (idx != -1) {
      allTodos[idx].isDeleted = false;
      allTodos[idx].markAsChanged();
      await StorageService.saveTodos(widget.username, allTodos, sync: true);
    }
    _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('待办已成功恢复')));
    }
  }

  Future<void> _permanentlyDeleteItem(TodoItem item) async {
    final allTodos = await StorageService.getTodos(widget.username);
    allTodos.removeWhere((t) => t.id == item.id);
    await StorageService.saveTodos(widget.username, allTodos, sync: false);
    _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已彻底删除')));
    }
  }

  Future<void> _fixOrphan(TodoItem item) async {
    final allTodos = await StorageService.getTodos(widget.username);
    int idx = allTodos.indexWhere((t) => t.id == item.id);
    if (idx != -1) {
      allTodos[idx].groupId = null; // 解绑无效的分组，让它回到首页主列表
      allTodos[idx].markAsChanged();
      await StorageService.saveTodos(widget.username, allTodos, sync: true);
    }
    _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已修复！待办已回到首页清单')));
    }
  }

  Future<void> _clearRecycleBin() async {
    bool confirm = await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
                  title: const Text("清空回收站"),
                  content: const Text("确定要彻底清空回收站吗？清空后将无法恢复。"),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("取消")),
                    FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text("清空")),
                  ],
                )) ??
        false;

    if (confirm) {
      final allTodos = await StorageService.getTodos(widget.username);
      allTodos.removeWhere((t) => t.isDeleted);
      await StorageService.saveTodos(widget.username, allTodos, sync: false);
      _loadData();
    }
  }

  // --- UI 构建方法 ---

  Map<String, List<TodoItem>> _groupByDate(List<TodoItem> items) {
    Map<String, List<TodoItem>> groups = {};
    for (var item in items) {
      final date = DateTime.fromMillisecondsSinceEpoch(item.updatedAt, isUtc: true).toLocal();
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      groups.putIfAbsent(dateStr, () => []).add(item);
    }
    return groups;
  }

  Widget _buildGroupedTodoList({
    required List<TodoItem> items,
    required Widget Function(TodoItem) itemBuilder,
    String emptyText = "暂无内容",
    Widget? header,
  }) {
    if (items.isEmpty) {
      return Center(child: Text(emptyText, style: const TextStyle(color: Colors.grey)));
    }

    final grouped = _groupByDate(items);
    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: (header != null ? 1 : 0) + sortedDates.fold(0, (sum, date) => sum + 1 + grouped[date]!.length),
      itemBuilder: (context, index) {
        if (header != null && index == 0) return header;
        
        int currentIndex = header != null ? index - 1 : index;
        for (var date in sortedDates) {
          if (currentIndex == 0) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    date,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            );
          }
          currentIndex--;
          if (currentIndex < grouped[date]!.length) {
            return itemBuilder(grouped[date]![currentIndex]);
          }
          currentIndex -= grouped[date]!.length;
        }
        return const SizedBox.shrink();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('待办深度清理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: '重新扫描',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: '历史记录'),
            Tab(text: '回收站'),
            Tab(text: '孤儿待办'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // 1. 历史待办
                _buildGroupedTodoList(
                  items: _history,
                  emptyText: "没有历史待办",
                  itemBuilder: (todo) => Card(
                    elevation: 0,
                    color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Checkbox(
                        value: todo.isDone,
                        onChanged: (val) => _uncheckItem(todo),
                      ),
                      title: Text(
                        todo.title,
                        style: TextStyle(
                          decoration: TextDecoration.lineThrough,
                          color: colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                      subtitle: Text(
                        "完成于: ${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(todo.updatedAt, isUtc: true).toLocal())}",
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                        onPressed: () => _deleteItem(todo),
                      ),
                    ),
                  ),
                ),

                // 2. 回收站
                _buildGroupedTodoList(
                  items: _deletedTodos,
                  emptyText: "回收站空空如也",
                  header: Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("共 ${_deletedTodos.length} 条已删除记录", style: const TextStyle(color: Colors.grey, fontSize: 13)),
                        TextButton.icon(
                          onPressed: _clearRecycleBin,
                          icon: const Icon(Icons.delete_sweep, size: 18, color: Colors.redAccent),
                          label: const Text("清空全部", style: TextStyle(color: Colors.redAccent)),
                        )
                      ],
                    ),
                  ),
                  itemBuilder: (todo) => Card(
                    elevation: 0,
                    color: colorScheme.errorContainer.withOpacity(0.2),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(todo.title, style: TextStyle(color: colorScheme.onSurface)),
                      subtitle: Text(
                        "删除于: ${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(todo.updatedAt, isUtc: true).toLocal())}",
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: "恢复",
                            icon: const Icon(Icons.restore, color: Colors.green, size: 20),
                            onPressed: () => _restoreDeletedItem(todo),
                          ),
                          IconButton(
                            tooltip: "彻底删除",
                            icon: const Icon(Icons.close, color: Colors.redAccent, size: 20),
                            onPressed: () => _permanentlyDeleteItem(todo),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // 3. 孤儿待办
                _buildGroupedTodoList(
                  items: _orphanTodos,
                  emptyText: "这里没有迷路的待办",
                  header: Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange, size: 20),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "这些待办所属的分类文件夹已被删除或找不到了，导致它们无法在主页正常显示。点击修复可取消分类回归。 ",
                            style: TextStyle(fontSize: 12, color: Colors.orange),
                          ),
                        ),
                      ],
                    ),
                  ),
                  itemBuilder: (todo) => Card(
                    elevation: 0,
                    color: Colors.orange.withOpacity(0.05),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(todo.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("所属无效ID: ${todo.groupId}", style: const TextStyle(fontSize: 10)),
                      trailing: FilledButton.icon(
                        onPressed: () => _fixOrphan(todo),
                        icon: const Icon(Icons.auto_fix_high, size: 16),
                        label: const Text("一键归队", style: TextStyle(fontSize: 12)),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          backgroundColor: Colors.orange,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
