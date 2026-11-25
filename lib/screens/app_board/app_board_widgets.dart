part of '../app_board_screen.dart';

class GlassCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? headerExtra;
  final String? className;

  const GlassCard({
    super.key,
    required this.title,
    required this.child,
    this.headerExtra,
    this.className,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              ?headerExtra,
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );

    return OptionalLiquidGlassPanel(
      mode: OptionalLiquidGlassPanelMode.adaptiveRepeated,
      isDark: true,
      clipBehavior: Clip.antiAlias,
      borderRadius: 40,
      fallback: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        clipBehavior: Clip.antiAlias,
        child: content,
      ),
      child: content,
    );
  }
}

class AnimatedBackground extends StatefulWidget {
  const AnimatedBackground({super.key});

  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );
    PowerSaveModeService.enabledListenable.addListener(_syncAnimation);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (AndroidEnergyPolicy.shouldRunDecorativeMotion) {
      if (!_controller.isAnimating) {
        _controller.repeat(
          reverse: true,
          count: AndroidEnergyPolicy.decorativeRepeatCount(androidCount: 2),
        );
      }
    } else {
      _controller
        ..stop()
        ..reset();
    }
  }

  @override
  void dispose() {
    PowerSaveModeService.enabledListenable.removeListener(_syncAnimation);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _AnimatedBackgroundPainter(
          animation: _controller,
          primaryColor: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _AnimatedBackgroundPainter extends CustomPainter {
  final Animation<double> animation;
  final Color primaryColor;
  static final Paint _paint = Paint()..isAntiAlias = true;

  _AnimatedBackgroundPainter({
    required this.animation,
    required this.primaryColor,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final value = animation.value;
    _paint.color = primaryColor.withValues(alpha: 0.05 + (0.05 * value));
    canvas.drawCircle(
      Offset(100 + (30 * value), 100 + (50 * value)),
      200,
      _paint,
    );

    _paint.color = Colors.indigo.withValues(alpha: 0.05 + (0.03 * value));
    canvas.drawCircle(
      Offset(size.width - 125 + (20 * value), size.height - 125 + (40 * value)),
      175,
      _paint,
    );
  }

  @override
  bool shouldRepaint(covariant _AnimatedBackgroundPainter oldDelegate) =>
      oldDelegate.animation != animation ||
      oldDelegate.primaryColor != primaryColor;
}

class TodayHourlyTimeline extends StatelessWidget {
  final List<TodoItem> todos;
  final List<CourseItem> courses;
  final DateTime? semesterStart;
  final int currentWeek;
  final double? itemHeight;
  final Function(TodoItem) onTaskClick;

  const TodayHourlyTimeline({
    super.key,
    required this.todos,
    required this.courses,
    this.semesterStart,
    required this.currentWeek,
    this.itemHeight,
    required this.onTaskClick,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    final coursesByHour = List<List<CourseItem>?>.filled(24, null);
    for (final course in courses) {
      if (course.weekday != now.weekday ||
          (course.weekIndex != 0 && course.weekIndex != currentWeek)) {
        continue;
      }
      final hour = course.startTime ~/ 100;
      if (hour >= 0 && hour < coursesByHour.length) {
        final hourCourses = coursesByHour[hour] ??= <CourseItem>[];
        hourCourses.add(course);
      }
    }

    final tasksByHour = List<List<TodoItem>?>.filled(24, null);
    for (final todo in todos) {
      final dueDate = todo.dueDate;
      if (dueDate == null || !DateUtils.isSameDay(dueDate, todayStart)) {
        continue;
      }
      final hourTasks = tasksByHour[dueDate.hour] ??= <TodoItem>[];
      hourTasks.add(todo);
    }

    return ListView.builder(
      physics: itemHeight != null
          ? const NeverScrollableScrollPhysics()
          : const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemExtent: itemHeight ?? 60.0,
      itemCount: 24,
      itemBuilder: (context, hour) {
        final isCurrent = now.hour == hour;
        final hCourses = coursesByHour[hour] ?? const <CourseItem>[];
        final hTasks = tasksByHour[hour] ?? const <TodoItem>[];

        return RepaintBoundary(
          key: ValueKey<int>(hour),
          child: Container(
            height: itemHeight ?? 60,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.02)),
              ),
              color: isCurrent
                  ? Theme.of(context).colorScheme.primary
                        .withValues(alpha: 0.05)
                  : null,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 30,
                  child: Text(
                    hour.toString().padLeft(2, '0'),
                    style: TextStyle(
                      color: isCurrent
                          ? Theme.of(context).colorScheme.secondary
                          : Colors.white.withValues(alpha: 0.1),
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      fontFeatures: [const FontFeature.tabularFigures()],
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ...hCourses.map(
                          (c) => Container(
                            margin: const EdgeInsets.only(right: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.indigo.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Colors.indigo.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Text(
                              c.courseName,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        ...hTasks.map(
                          (t) => GestureDetector(
                            onTap: () => onTaskClick(t),
                            child: Container(
                              margin: const EdgeInsets.only(right: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    (t.isDone
                                            ? emerald
                                            : Theme.of(context)
                                                  .colorScheme
                                                  .primary)
                                        .withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color:
                                      (t.isDone
                                              ? emerald
                                              : Theme.of(context)
                                                    .colorScheme
                                                    .primary)
                                          .withValues(alpha: 0.1),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 3,
                                    height: 3,
                                    decoration: BoxDecoration(
                                      color: t.isDone
                                          ? emeraldAccent
                                          : Theme.of(context)
                                                .colorScheme
                                                .secondary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    t.title,
                                    style: TextStyle(
                                      color: t.isDone
                                          ? Colors.white30
                                          : Colors.white,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      decoration: t.isDone
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class MissionControl extends StatelessWidget {
  final List<TodoItem> todos;
  final String activeTab;
  final Function(String) onTabChanged;
  final Function(TodoItem) onTaskClick;
  final DateTime Function() clock;

  const MissionControl({
    super.key,
    required this.todos,
    required this.activeTab,
    required this.onTabChanged,
    required this.onTaskClick,
    this.clock = DateTime.now,
  });

  @override
  Widget build(BuildContext context) {
    final showCompleted = activeTab != 'active';
    final displayTasks = <TodoItem>[];
    for (final todo in todos) {
      if (todo.isDone == showCompleted) displayTasks.add(todo);
    }
    final now = clock();
    final dueTimeFormat = AppTimeFormats.dateFormatter('HH:mm');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _buildTab(
                  'active',
                  '活跃任务',
                  Theme.of(context).colorScheme.primary,
                ),
                _buildTab('completed', '历史记录', emerald),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            findItemIndexCallback: (Key key) {
              if (key is ValueKey<String>) {
                final id = key.value;
                final idx = displayTasks.indexWhere((t) => t.id == id);
                return idx != -1 ? idx : null;
              }
              return null;
            },
            itemCount: displayTasks.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final task = displayTasks[index];
              final isOverdue = task.isOverdueAt(now) && !task.isDone;

              return RepaintBoundary(
                key: ValueKey<String>(task.id),
                child: InkWell(
                  onTap: () => onTaskClick(task),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isOverdue
                          ? Colors.red.withValues(alpha: 0.05)
                          : Colors.white.withValues(alpha: 0.02),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isOverdue
                            ? Colors.red.withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: activeTab == 'active'
                                ? Theme.of(context).colorScheme.secondary
                                : emeraldAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                task.title,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  decoration: task.isDone
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${task.creatorName ?? "用户"} · ${task.dueDate != null ? dueTimeFormat.format(task.dueDate!) : "无时间"}',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTab(String tab, String label, Color activeColor) {
    bool isSelected = activeTab == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTabChanged(tab),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.3),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white24,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class TaskDetailModal extends StatelessWidget {
  final TodoItem task;
  final VoidCallback onClose;

  const TaskDetailModal({super.key, required this.task, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final double sheetWidth = math.min(
      600,
      MediaQuery.sizeOf(context).width * 0.9,
    );
    final sheetConstraints = BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.8,
    );
    final sheet = Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 6,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Theme.of(context).colorScheme.primary, Colors.indigo],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(32),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color:
                            (task.teamUuid != null
                                    ? Theme.of(context).colorScheme.primary
                                    : emerald)
                                .withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color:
                              (task.teamUuid != null
                                      ? Theme.of(context).colorScheme.primary
                                      : emerald)
                                  .withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        task.teamName ?? '个人空间',
                        style: TextStyle(
                          color: task.teamUuid != null
                              ? Theme.of(context).colorScheme.secondary
                              : emeraldAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white24),
                      onPressed: onClose,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  task.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 32),
                _buildInfoRow(
                  Icons.access_time,
                  '开始时间',
                  AppTimeFormats.dateFormatter(
                    'yyyy-MM-dd HH:mm',
                  ).format(DateTime.fromMillisecondsSinceEpoch(task.createdAt)),
                ),
                _buildInfoRow(
                  Icons.calendar_today,
                  '截止时间',
                  task.dueDate != null
                      ? AppTimeFormats.dateFormatter('yyyy-MM-dd HH:mm')
                            .format(task.dueDate!)
                      : '无截止日期',
                ),
                _buildInfoRow(
                  Icons.person_outline,
                  '创建者',
                  task.creatorName ?? '我',
                ),
                const SizedBox(height: 24),
                const Text(
                  '备注与详情',
                  style: TextStyle(
                    color: Colors.white24,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                  child: Text(
                    task.remark ?? '暂无详细备注说明。',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    return GestureDetector(
      onTap: onClose,
      child: Container(
        color: Colors.black.withValues(alpha: 0.8),
        child: Center(
          child: GestureDetector(
            onTap: () {}, // Prevent closing when clicking modal
            child: ConstrainedBox(
              constraints: sheetConstraints,
              child: OptionalLiquidGlassPanel(
                mode: OptionalLiquidGlassPanelMode.adaptiveRepeated,
                isDark: true,
                highContrast: true,
                clipBehavior: Clip.antiAlias,
                borderRadius: 32,
                width: sheetWidth,
                fallback: Container(
                  width: sheetWidth,
                  constraints: sheetConstraints,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: sheet,
                ),
                child: sheet,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, color: Colors.white24, size: 16),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white24,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
