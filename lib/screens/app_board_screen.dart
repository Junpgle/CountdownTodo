import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../storage_service.dart';
import '../services/api_service.dart';

class AppBoardScreen extends StatefulWidget {
  final String username;
  const AppBoardScreen({super.key, required this.username});

  @override
  State<AppBoardScreen> createState() => _AppBoardScreenState();
}

class _AppBoardScreenState extends State<AppBoardScreen> {
  List<TodoItem> _todos = [];
  List<TodoItem> _filteredTodos = [];
  String? _selectedTeamUuid;
  String? _selectedTeamName;
  bool _isLoading = true;
  String _viewMode = 'list'; // list, timeline, kanban

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final todos = await StorageService.getTodos(widget.username, limit: 200);

      if (mounted) {
        setState(() {
          _todos = todos.where((t) => !t.isDeleted).toList();
          _filterTodos();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading board data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filterTodos() {
    if (_selectedTeamUuid == null) {
      _filteredTodos = _todos;
    } else {
      _filteredTodos = _todos.where((t) => t.teamUuid == _selectedTeamUuid).toList();
    }
  }

  Future<void> _selectTeam() async {
    try {
      final teams = await ApiService.fetchTeams();
      final teamList = teams.map((t) => Team.fromJson(t)).toList();

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('选择查看的团队'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('全部任务'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _selectedTeamUuid = null;
                      _selectedTeamName = '全部';
                      _filterTodos();
                    });
                  },
                ),
                ...teamList.map((team) => ListTile(
                  title: Text(team.name),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _selectedTeamUuid = team.uuid;
                      _selectedTeamName = team.name;
                      _filterTodos();
                    });
                  },
                )),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error fetching teams: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 768;

    return Scaffold(
      appBar: AppBar(
        title: const Text('看板'),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Center(
              child: TextButton.icon(
                onPressed: _selectTeam,
                icon: const Icon(Icons.group, size: 16),
                label: Text(_selectedTeamName ?? '全部'),
              ),
            ),
          ),
          if (isTablet)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Center(
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'list', label: Text('列表')),
                    ButtonSegment(value: 'timeline', label: Text('时间线')),
                    ButtonSegment(value: 'kanban', label: Text('看板')),
                  ],
                  selected: {_viewMode},
                  onSelectionChanged: (value) {
                    setState(() => _viewMode = value.first);
                  },
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _filteredTodos.isEmpty
              ? Center(
                  child: Text(
                    '暂无任务',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              : isTablet
                  ? _buildTabletView()
                  : _buildMobileView(),
    );
  }

  Widget _buildMobileView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'list', label: Text('列表')),
              ButtonSegment(value: 'timeline', label: Text('时间线')),
              ButtonSegment(value: 'kanban', label: Text('看板')),
            ],
            selected: {_viewMode},
            onSelectionChanged: (value) {
              setState(() => _viewMode = value.first);
            },
          ),
        ),
        Expanded(
          child: switch (_viewMode) {
            'list' => _buildListView(),
            'timeline' => _buildTimelineView(),
            'kanban' => _buildKanbanView(),
            _ => _buildListView(),
          },
        ),
      ],
    );
  }

  Widget _buildTabletView() {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: _buildListView(),
        ),
        Expanded(
          flex: 4,
          child: _buildTimelineView(),
        ),
        Expanded(
          flex: 3,
          child: _buildKanbanView(),
        ),
      ],
    );
  }

  Widget _buildListView() {
    final sortedTodos = _filteredTodos.toList()
      ..sort((a, b) => (a.dueDate ?? DateTime(2099)).compareTo(b.dueDate ?? DateTime(2099)));

    return ListView.builder(
      padding: const EdgeInsets.all(12.0),
      itemCount: sortedTodos.length,
      itemBuilder: (context, index) {
        final todo = sortedTodos[index];
        return Card(
          child: ListTile(
            leading: Checkbox(
              value: todo.isDone,
              onChanged: (_) {},
            ),
            title: Text(
              todo.title,
              style: TextStyle(
                decoration: todo.isDone ? TextDecoration.lineThrough : null,
              ),
            ),
            subtitle: todo.dueDate != null
                ? Text(DateFormat('yyyy-MM-dd HH:mm').format(todo.dueDate!))
                : null,
            trailing: todo.isDone
                ? const Icon(Icons.check_circle, color: Colors.green)
                : const Icon(Icons.circle_outlined),
          ),
        );
      },
    );
  }

  Widget _buildTimelineView() {
    final sortedTodos = _filteredTodos
        .where((t) => t.dueDate != null)
        .toList()
      ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));

    if (sortedTodos.isEmpty) {
      return Center(
        child: Text(
          '无日期任务',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12.0),
      itemCount: sortedTodos.length,
      itemBuilder: (context, index) {
        final todo = sortedTodos[index];
        final isToday = _isToday(todo.dueDate!);

        return Card(
          color: isToday ? Colors.blue.withValues(alpha: 0.1) : null,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isToday)
                      const Chip(
                        label: Text('今天', style: TextStyle(fontSize: 11)),
                        backgroundColor: Colors.blue,
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        todo.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          decoration: todo.isDone ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.schedule, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('M月d日 HH:mm').format(todo.dueDate!),
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    if (todo.isDone) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.check, size: 14, color: Colors.green[600]),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildKanbanView() {
    final activeTodos = _filteredTodos.where((t) => !t.isDone).toList();
    final completedTodos = _filteredTodos.where((t) => t.isDone).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '进行中 (${activeTodos.length})',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Text(
                '已完成 (${completedTodos.length})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  itemCount: activeTodos.length,
                  itemBuilder: (context, index) {
                    return _buildKanbanCard(activeTodos[index], false);
                  },
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  itemCount: completedTodos.length,
                  itemBuilder: (context, index) {
                    return _buildKanbanCard(completedTodos[index], true);
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKanbanCard(TodoItem todo, bool isCompleted) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      color: isCompleted
          ? Colors.grey.withValues(alpha: 0.3)
          : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              todo.title,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 12,
                decoration: isCompleted ? TextDecoration.lineThrough : null,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (todo.dueDate != null) ...[
              const SizedBox(height: 6),
              Text(
                DateFormat('MM-dd HH:mm').format(todo.dueDate!),
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }
}
