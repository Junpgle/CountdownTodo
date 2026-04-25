import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../services/timeline_service.dart';

class PersonalTimelineScreen extends StatefulWidget {
  final String username;
  const PersonalTimelineScreen({super.key, required this.username});

  @override
  State<PersonalTimelineScreen> createState() => _PersonalTimelineScreenState();
}

class _PersonalTimelineScreenState extends State<PersonalTimelineScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<DateTime> _dates = List.generate(7, (i) => DateTime.now().subtract(Duration(days: i)));
  
  final Map<int, List<TimelineEvent>> _eventsMap = {};
  final Map<int, TimelineSummary> _summariesMap = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _dates.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {}); // 更新侧边栏选中状态
      }
    });
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    
    // 并发加载所有 7 天的数据
    await Future.wait(_dates.asMap().entries.map((entry) async {
      final index = entry.key;
      final date = entry.value;
      
      final events = await TimelineService.instance.getEventsForDay(widget.username, date);
      final summary = await TimelineService.instance.getSummaryForDay(widget.username, date);
      
      _eventsMap[index] = events;
      _summariesMap[index] = summary;
    }));

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  String _getDateLabel(int index) {
    if (index == 0) return '今日';
    if (index == 1) return '昨日';
    final date = _dates[index];
    final now = DateTime.now();
    if (now.difference(date).inDays < 7) {
      return DateFormat('EEEE', 'zh_CN').format(date); // 星期几
    }
    return DateFormat('MM-dd').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;
    final bool isWide = size.width > 900;

    return Scaffold(
      backgroundColor: colorScheme.surface.withValues(alpha: 0.95),
      appBar: AppBar(
        title: const Text('个人足迹', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        centerTitle: !isWide,
        bottom: isWide ? null : TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 15),
          tabs: List.generate(_dates.length, (i) => Tab(text: _getDateLabel(i))),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : isWide
              ? _buildWideLayout(context)
              : TabBarView(
                  controller: _tabController,
                  children: List.generate(_dates.length, (i) {
                    final events = _eventsMap[i] ?? [];
                    return _buildTimelineList(events, '${_getDateLabel(i)}没有记录');
                  }),
                ),
    );
  }

  Widget _buildWideLayout(BuildContext context) {
    return Row(
      children: [
        // 左侧栏：日期切换
        Container(
          width: 240,
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.05))),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: _dates.length,
                  itemBuilder: (context, i) => _buildSidebarItem(i, _getDateLabel(i), _dates[i], _eventsMap[i]?.length ?? 0),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Opacity(
                  opacity: 0.5,
                  child: Icon(Icons.auto_awesome_mosaic_rounded, size: 60, color: Colors.grey.withValues(alpha: 0.2)),
                ),
              ),
            ],
          ),
        ),
        // 中间栏：时间轴
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: AnimatedBuilder(
                animation: _tabController,
                builder: (context, _) {
                  final events = _eventsMap[_tabController.index] ?? [];
                  final msg = '${_getDateLabel(_tabController.index)}还没有留下足迹哦';
                  return _buildTimelineList(events, msg);
                },
              ),
            ),
          ),
        ),
        // 右侧栏：数据统计概览
        Container(
          width: 300,
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.05))),
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: AnimatedBuilder(
              animation: _tabController,
              builder: (context, _) {
                final summary = _summariesMap[_tabController.index];
                return _buildSummaryPanel(summary);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSidebarItem(int index, String title, DateTime date, int count) {
    final bool isSelected = _tabController.index == index;
    final color = isSelected ? Theme.of(context).colorScheme.primary : Colors.grey;
    final dateSub = DateFormat('MM月dd日').format(date);

    return InkWell(
      onTap: () {
        _tabController.animateTo(index);
        setState(() {});
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(
                  color: isSelected ? Colors.black87 : Colors.grey[700], 
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 15,
                )),
                Text(dateSub, style: TextStyle(fontSize: 11, color: isSelected ? color.withValues(alpha: 0.7) : Colors.grey[500])),
              ],
            ),
            const Spacer(),
            if (count > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected ? color : color.withValues(alpha: 0.1), 
                  borderRadius: BorderRadius.circular(10)
                ),
                child: Text('$count', style: TextStyle(fontSize: 10, color: isSelected ? Colors.white : color, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryPanel(TimelineSummary? summary) {
    if (summary == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('数据概览', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        _buildStatCard('专注次数', '${summary.pomodoroCount}', Icons.local_fire_department_rounded, Colors.orange),
        _buildStatCard('待办完成', '${summary.todoCompletedCount}', Icons.check_circle_rounded, Colors.blue),
        _buildStatCard('倒计时达成', '${summary.countdownCompletedCount}', Icons.celebration_rounded, Colors.redAccent),
        _buildStatCard('搜索次数', '${summary.searchCount}', Icons.search_rounded, Colors.teal),
        const SizedBox(height: 24),
        if (summary.attendedCourses.isNotEmpty) ...[
          const Text('已上课程', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 12),
          ...summary.attendedCourses.map((c) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Icon(Icons.school_outlined, size: 14, color: Colors.indigo),
                const SizedBox(width: 8),
                Expanded(child: Text(c, style: const TextStyle(fontSize: 13))),
              ],
            ),
          )),
        ],
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineList(List<TimelineEvent> events, String emptyMsg) {
    if (events.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_toggle_off_rounded, size: 80, color: Colors.grey.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            Text(emptyMsg, style: const TextStyle(color: Colors.grey, fontSize: 16)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        itemCount: events.length,
        itemBuilder: (context, index) {
          return _buildEnhancedTimelineItem(events[index], index == events.length - 1);
        },
      ),
    );
  }

  Widget _buildEnhancedTimelineItem(TimelineEvent event, bool isLast) {
    final timeStr = DateFormat('HH:mm').format(event.timestamp);
    final color = _getEventColor(event.type);
    final icon = _getEventIcon(event.type);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 8, spreadRadius: 1)
                  ],
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [color.withValues(alpha: 0.5), Colors.grey.withValues(alpha: 0.1)],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
                border: Border.all(color: Colors.grey.withValues(alpha: 0.05)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                timeStr,
                                style: TextStyle(
                                  color: color,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              event.title,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        if (event.subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              event.subtitle!,
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                height: 1.4,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 20, color: color),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getEventColor(TimelineEventType type) {
    switch (type) {
      case TimelineEventType.pomodoroStart: return Colors.orange;
      case TimelineEventType.pomodoroEnd: return Colors.green;
      case TimelineEventType.todoCompleted: return Colors.blue;
      case TimelineEventType.todoCreated: return Colors.purple;
      case TimelineEventType.countdownCreated: return Colors.redAccent;
      case TimelineEventType.countdownCompleted: return Colors.red;
      case TimelineEventType.courseStart: return Colors.indigo;
      case TimelineEventType.courseEnd: return Colors.deepPurple;
      case TimelineEventType.searchQuery: return Colors.teal;
    }
  }

  IconData _getEventIcon(TimelineEventType type) {
    switch (type) {
      case TimelineEventType.pomodoroStart: return Icons.play_arrow_rounded;
      case TimelineEventType.pomodoroEnd: return Icons.check_circle_outline_rounded;
      case TimelineEventType.todoCompleted: return Icons.task_alt_rounded;
      case TimelineEventType.todoCreated: return Icons.add_rounded;
      case TimelineEventType.countdownCreated: return Icons.timer_outlined;
      case TimelineEventType.countdownCompleted: return Icons.celebration_rounded;
      case TimelineEventType.courseStart: return Icons.school_rounded;
      case TimelineEventType.courseEnd: return Icons.logout_rounded;
      case TimelineEventType.searchQuery: return Icons.search_rounded;
    }
  }
}
