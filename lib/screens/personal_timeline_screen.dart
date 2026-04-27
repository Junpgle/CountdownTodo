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
  late List<DateTime> _dates;
  
  final Map<int, List<TimelineEvent>> _eventsMap = {};
  final Map<int, TimelineSummary> _summariesMap = {};
  bool _isLoading = true;
  
  List<DateTime> _generateDates() {
    // 生成过去7天，但确保都是"整日期"（不含时间部分）
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return List.generate(7, (i) => today.subtract(Duration(days: i)));
  }

  @override
  void initState() {
    super.initState();
    _dates = _generateDates();
    _tabController = TabController(length: _dates.length, vsync: this);
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
                child: AnimatedBuilder(
                  animation: _tabController,
                  builder: (context, _) => ListView.builder(
                    itemCount: _dates.length,
                    itemBuilder: (context, i) => _buildSidebarItem(i, _getDateLabel(i), _dates[i], _eventsMap[i]?.length ?? 0),
                  ),
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
                  final dateLabel = _getDateLabel(_tabController.index);
                  final msg = '$dateLabel还没有留下足迹哦';
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          dateLabel,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(child: _buildTimelineList(events, msg)),
                    ],
                  );
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
    final textColor = Theme.of(context).colorScheme.onSurface;

    return InkWell(
      onTap: () => _tabController.animateTo(index),
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
                  color: isSelected ? textColor : Colors.grey[700], 
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
    if (summary == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 40, color: Colors.grey.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text('暂无数据', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
          ],
        ),
      );
    }

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

    final processed = _processEventsForHierarchy(events);

    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        itemCount: processed.length,
        itemBuilder: (context, index) {
          return _buildHierarchicalItem(processed[index], index == processed.length - 1);
        },
      ),
    );
  }

  List<_ProcessedEvent> _processEventsForHierarchy(List<TimelineEvent> events) {
    if (events.isEmpty) return [];

    // 1. 恢复倒序排列（最新优先）
    final sorted = List<TimelineEvent>.from(events)..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    // 2. 预扫描：在倒序序列中，End 事件会先出现，找到有匹配 Start 的 End
    final Map<String, bool> hasStart = {};
    final Map<String, int> endSeen = {};
    for (int i = 0; i < sorted.length; i++) {
       final eid = _getEntityId(sorted[i].id);
       if (_isEndEvent(sorted[i].type)) {
         endSeen[eid] = i;
       } else if (_isStartEvent(sorted[i].type)) {
         if (endSeen.containsKey(eid)) hasStart[eid] = true;
       }
    }

    final List<_ProcessedEvent> result = [];
    final List<String> stack = [];
    
    for (int i = 0; i < sorted.length; i++) {
      final e = sorted[i];
      final eid = _getEntityId(e.id);
      
      // 在倒序视图中：
      // End 事件是“区间的顶部”（isIntervalTop）
      // Start 事件是“区间的底部”（isIntervalBottom）
      final bool isIntervalTop = _isEndEvent(e.type) && (hasStart[eid] ?? false);
      final bool isIntervalBottom = _isStartEvent(e.type) && stack.contains(eid);
      
      if (isIntervalBottom) {
        // 遇到 Start（底部），从栈中移除，线只到点为止
        final level = stack.indexOf(eid);
        final active = List.generate(stack.length, (idx) => idx).toSet();
        active.remove(level); 
        
        result.add(_ProcessedEvent(e, level, active, false, true));
        stack.remove(eid);
      } else if (isIntervalTop) {
        // 遇到 End（顶部），入栈，线从此开始向下
        final level = stack.length;
        final active = List.generate(stack.length, (idx) => idx).toSet();
        result.add(_ProcessedEvent(e, level, active, true, false));
        stack.add(eid);
      } else {
        // 普通点事件
        final level = stack.length;
        final active = List.generate(stack.length, (idx) => idx).toSet();
        result.add(_ProcessedEvent(e, level, active, false, false));
      }
    }
    return result;
  }

  String _getEntityId(String eventId) {
    final parts = eventId.split('_');
    if (parts.length >= 3) return parts[2];
    return eventId;
  }

  bool _isStartEvent(TimelineEventType type) {
    return type == TimelineEventType.pomodoroStart ||
           type == TimelineEventType.courseStart ||
           type == TimelineEventType.todoCreated ||
           type == TimelineEventType.countdownCreated;
  }

  bool _isEndEvent(TimelineEventType type) {
    return type == TimelineEventType.pomodoroEnd ||
           type == TimelineEventType.courseEnd ||
           type == TimelineEventType.todoCompleted ||
           type == TimelineEventType.countdownCompleted;
  }

  Widget _buildHierarchicalItem(_ProcessedEvent pe, bool isLast) {
    final event = pe.event;
    final timeStr = DateFormat('HH:mm').format(event.timestamp);
    final color = _getEventColor(pe.event.type);
    final icon = _getEventIcon(pe.event.type);
    
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 渲染层级线
          ...List.generate(pe.level + 1, (i) {
            final bool isCurrentLevel = i == pe.level;
            final bool hasActiveLine = pe.activeLevels.contains(i);
            
            return SizedBox(
              width: 24,
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  // 垂直背景线
                  if (hasActiveLine)
                    Container(
                      width: 2,
                      color: Colors.grey.withValues(alpha: 0.15),
                    ),
                  
                  // 当前层级的特殊处理
                  if (isCurrentLevel) ...[
                    // 如果是结束点，线只到一半
                    if (pe.isEnd)
                      Positioned(
                        top: 0,
                        bottom: 16, // 到达点的位置
                        child: Container(width: 2, color: Colors.grey.withValues(alpha: 0.15)),
                      ),
                    // 如果是开始点，线从点开始向下
                    if (pe.isStart)
                      Positioned(
                        top: 16,
                        bottom: 0,
                        child: Container(width: 2, color: color.withValues(alpha: 0.3)),
                      ),
                    
                    // 节点圆点
                    Positioned(
                      top: 12,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 4)
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
          
          const SizedBox(width: 8),
          
          // 内容卡片
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
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
                            Text(
                              timeStr,
                              style: TextStyle(
                                color: color.withValues(alpha: 0.6),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                event.title,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (event.subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              event.subtitle!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(icon, size: 16, color: color.withValues(alpha: 0.5)),
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
      case TimelineEventType.todoCreated: return Colors.purple;
      case TimelineEventType.todoEdited: return Colors.amber;
      case TimelineEventType.todoCompleted: return Colors.blue;
      case TimelineEventType.countdownCreated: return Colors.redAccent;
      case TimelineEventType.countdownEdited: return Colors.deepOrange;
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
      case TimelineEventType.todoCreated: return Icons.add_rounded;
      case TimelineEventType.todoEdited: return Icons.edit_rounded;
      case TimelineEventType.todoCompleted: return Icons.task_alt_rounded;
      case TimelineEventType.countdownCreated: return Icons.timer_outlined;
      case TimelineEventType.countdownEdited: return Icons.edit_note_rounded;
      case TimelineEventType.countdownCompleted: return Icons.celebration_rounded;
      case TimelineEventType.courseStart: return Icons.school_rounded;
      case TimelineEventType.courseEnd: return Icons.logout_rounded;
      case TimelineEventType.searchQuery: return Icons.search_rounded;
    }
  }
}

class _ProcessedEvent {
  final TimelineEvent event;
  final int level;
  final Set<int> activeLevels;
  final bool isStart;
  final bool isEnd;

  _ProcessedEvent(this.event, this.level, this.activeLevels, this.isStart, this.isEnd);
}
