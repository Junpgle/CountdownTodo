part of 'course_screens.dart';

// --- Detail Screens ---

class CourseDetailScreen extends StatelessWidget {
  final CourseItem course;
  const CourseDetailScreen({super.key, required this.course});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppDetailScreen(
      appBarTitle: '课程详情',
      icon: Icons.class_,
      title: course.courseName,
      color: colorScheme.secondary,
      sections: [
        AppDetailSection(
          title: '课程信息',
          children: [
            AppDetailWideCard(
                icon: Icons.person, title: '授课教师', value: course.teacherName),
            AppDetailWideCard(
                icon: Icons.location_on, title: '上课地点', value: course.roomName),
            AppDetailWideCard(
              icon: Icons.calendar_today,
              title: '日期',
              value:
                  '${course.date} (第${course.weekIndex}周 周${course.weekday})',
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: AppDetailInfoCard(
                      icon: Icons.play_arrow_rounded,
                      title: '开始时间',
                      value: course.formattedStartTime,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward_rounded,
                        color: colorScheme.onSurfaceVariant, size: 20),
                  ),
                  Expanded(
                    child: AppDetailInfoCard(
                      icon: Icons.stop_rounded,
                      title: '结束时间',
                      value: course.formattedEndTime,
                    ),
                  ),
                ],
              ),
            ),
            if (course.lessonType != null && course.lessonType!.isNotEmpty)
              AppDetailWideCard(
                icon: Icons.category,
                title: '类型/备注',
                value: course.lessonType == 'EXPERIMENT'
                    ? '实验课'
                    : (course.lessonType == 'THEORY'
                        ? '理论课'
                        : course.lessonType!),
              ),
          ],
        ),
      ],
    );
  }
}

class TodoDetailScreen extends StatefulWidget {
  final TodoItem todo;
  const TodoDetailScreen({super.key, required this.todo});

  @override
  State<TodoDetailScreen> createState() => _TodoDetailScreenState();
}

class _TodoDetailScreenState extends State<TodoDetailScreen> {
  List<PomodoroRecord> _focusRecords = [];
  bool _loadingRecords = true;

  @override
  void initState() {
    super.initState();
    _loadFocusRecords();
  }

  Future<void> _loadFocusRecords() async {
    final records = await PomodoroService.getRecordsByTodoUuid(widget.todo.id);
    if (mounted) {
      setState(() {
        _focusRecords = records;
        _loadingRecords = false;
      });
    }
  }

  String _getRecurrenceText() {
    final todo = widget.todo;
    switch (todo.recurrence) {
      case RecurrenceType.none:
        return '不重复';
      case RecurrenceType.daily:
        return '每天';
      case RecurrenceType.weekly:
        return '每周';
      case RecurrenceType.monthly:
        return '每月';
      case RecurrenceType.yearly:
        return '每年';
      case RecurrenceType.weekdays:
        return '工作日';
      case RecurrenceType.customDays:
        return '每 ${todo.customIntervalDays} 天';
    }
  }

  @override
  Widget build(BuildContext context) {
    final todo = widget.todo;
    final colorScheme = Theme.of(context).colorScheme;

    DateTime startTime = DateTime.fromMillisecondsSinceEpoch(
            todo.createdDate ?? todo.createdAt,
            isUtc: true)
        .toLocal();

    DateTime? endTime = todo.dueDate;

    String startTimeStr = todo.isAllDay
        ? '${AppTimeFormats.date(startTime)} (全天)'
        : AppTimeFormats.fullDateTime(startTime);

    String endTimeStr = endTime == null
        ? '无截止时间'
        : (todo.isAllDay
            ? '${AppTimeFormats.date(endTime)} (全天)'
            : AppTimeFormats.fullDateTime(endTime));

    double progress = 0.0;
    if (todo.isDone) {
      progress = 1.0;
    } else if (endTime != null) {
      final now = DateTime.now();
      final total = endTime.difference(startTime).inSeconds;
      if (total > 0) {
        final passed = now.difference(startTime).inSeconds;
        progress = (passed / total).clamp(0.0, 1.0);
      }
    }

    return AppDetailScreen(
      appBarTitle: '任务详情',
      backgroundColor: colorScheme.surface,
      icon: todo.isDone ? Icons.check_circle_rounded : Icons.pending_rounded,
      title: todo.title,
      titleSize: 22,
      titleDecoration: todo.isDone ? TextDecoration.lineThrough : null,
      titleColor: todo.isDone ? colorScheme.cdtDisabled : null,
      color: todo.isDone ? colorScheme.cdtSuccess : colorScheme.cdtWarning,
      iconSize: 64,
      progress: progress,
      progressColor: todo.isDone ? colorScheme.cdtSuccess : colorScheme.primary,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      scrollPhysics: const BouncingScrollPhysics(),
      leftSections: [
        if (todo.teamUuid != null)
          AppDetailSection(title: "协作信息", children: [
            AppDetailWideCard(
                icon: Icons.group_rounded,
                title: "所属团队",
                value: todo.teamName ?? "未知团队"),
            AppDetailWideCard(
                icon: Icons.person_rounded,
                title: "创建者",
                value: todo.creatorName ?? "未知用户"),
            AppDetailWideCard(
                icon: Icons.handshake_rounded,
                title: "协作模式",
                value: todo.collabType == 1 ? "每个人独立完成" : "所有人共同协作"),
          ]),
        if (todo.remark != null && todo.remark!.isNotEmpty)
          AppDetailSection(title: "备注详情", children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                todo.remark!,
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurface,
                  height: 1.5,
                ),
              ),
            ),
          ]),
      ],
      sections: [
        AppDetailSection(title: "基本信息", children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: AppDetailInfoCard(
                    icon: Icons.flag_rounded,
                    title: "当前状态",
                    value: todo.isDone ? "已完成" : "进行中",
                    valueColor: todo.isDone
                        ? colorScheme.cdtSuccess
                        : colorScheme.cdtWarning,
                  ),
                ),
                if (todo.recurrence != RecurrenceType.none ||
                    (todo.reminderMinutes != null &&
                        todo.reminderMinutes! > 0)) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppDetailInfoCard(
                      icon: todo.recurrence != RecurrenceType.none
                          ? Icons.repeat_rounded
                          : Icons.notifications_active_rounded,
                      title: todo.recurrence != RecurrenceType.none
                          ? "重复周期"
                          : "提醒设置",
                      value: todo.recurrence != RecurrenceType.none
                          ? _getRecurrenceText()
                          : "提前 ${todo.reminderMinutes} 分钟",
                    ),
                  ),
                ] else ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppDetailInfoCard(
                      icon: Icons.event_available_rounded,
                      title: "一次性任务",
                      value: "不重复",
                    ),
                  ),
                ]
              ],
            ),
          ),
          if (todo.recurrence != RecurrenceType.none &&
              (todo.reminderMinutes != null && todo.reminderMinutes! > 0))
            AppDetailWideCard(
                icon: Icons.notifications_active_rounded,
                title: "提醒设置",
                value: "提前 ${todo.reminderMinutes} 分钟"),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: AppDetailInfoCard(
                      icon: Icons.schedule_rounded,
                      title: "开始时间",
                      value: startTimeStr),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward_rounded,
                      color: colorScheme.onSurfaceVariant, size: 20),
                ),
                Expanded(
                  child: AppDetailInfoCard(
                    icon: Icons.event_busy_rounded,
                    title: "截止时间",
                    value: endTimeStr,
                    valueColor: (endTime != null &&
                            !todo.isDone &&
                            endTime.isBefore(DateTime.now()))
                        ? colorScheme.error
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ]),
        if (todo.originalText != null && todo.originalText!.isNotEmpty)
          AppDetailSection(title: "原始识别文本", children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                todo.originalText!,
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ]),
        if (todo.imagePath != null && todo.imagePath!.isNotEmpty)
          AppDetailSection(title: "附件图片", children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: localImageWidget(todo.imagePath!),
              ),
            ),
          ]),
        AppDetailSection(title: "系统信息", children: [
          AppDetailWideCard(
              icon: Icons.update_rounded,
              title: "最近更新",
              value: AppTimeFormats.format(
                  DateTime.fromMillisecondsSinceEpoch(todo.updatedAt,
                          isUtc: true)
                      .toLocal(),
                  'yyyy-MM-dd HH:mm:ss')),
          AppDetailWideCard(
              icon: Icons.fingerprint_rounded,
              title: "任务 ID",
              value: todo.id.length > 8
                  ? "${todo.id.substring(0, 8)}..."
                  : todo.id,
              onTap: () {
                Clipboard.setData(ClipboardData(text: todo.id));
                AppSnackBars.success(context, "ID 已复制到剪贴板");
              }),
        ]),
        if (!_loadingRecords && _focusRecords.isNotEmpty) ...[
          Builder(builder: (context) {
            int maxFocusDuration = 1;
            int totalDurationSeconds = 0;
            int completedCount = 0;
            if (_focusRecords.isNotEmpty) {
              for (var r in _focusRecords) {
                totalDurationSeconds += r.effectiveDuration;
                if (r.isCompleted) completedCount++;
                int durationMin = r.effectiveDuration ~/ 60;
                if (durationMin > maxFocusDuration) {
                  maxFocusDuration = durationMin;
                }
              }
            }
            int totalDurationMin = totalDurationSeconds ~/ 60;
            int avgDurationMin = _focusRecords.isNotEmpty
                ? totalDurationMin ~/ _focusRecords.length
                : 0;

            return AppDetailSection(
                title: "专注记录分布 (${_focusRecords.length})",
                children: [
                  Row(
                    children: [
                      _buildStatCard(
                          "总时长", "$totalDurationMin 分钟", colorScheme.primary),
                      const SizedBox(width: 10),
                      _buildStatCard(
                          "平均单次", "$avgDurationMin 分钟", colorScheme.secondary),
                      const SizedBox(width: 10),
                      _buildStatCard(
                          "成功次数", "$completedCount 次", colorScheme.cdtSuccess),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ..._focusRecords.take(20).map(
                      (r) => _buildFocusRecordVisualized(r, maxFocusDuration)),
                  if (_focusRecords.length > 20)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '仅显示最近 20 条',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ]);
          }),
        ]
      ],
    );
  }

  Widget _buildStatCard(String title, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(title,
                style: TextStyle(
                    fontSize: 11, color: color.withValues(alpha: 0.8))),
          ],
        ),
      ),
    );
  }

  Widget _buildFocusRecordVisualized(PomodoroRecord r, int maxDuration) {
    final colorScheme = Theme.of(context).colorScheme;
    final startLocal =
        DateTime.fromMillisecondsSinceEpoch(r.startTime, isUtc: true).toLocal();
    final durationMin = r.effectiveDuration ~/ 60;

    final safeMax = maxDuration > 0 ? maxDuration : 1;
    final ratio = (durationMin / safeMax).clamp(0.05, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            PageTransitions.material(
              builder: (_) => PomodoroDetailScreen(
                record: r,
                tags: [],
              ),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppTimeFormats.compactDateTime(startLocal),
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '$durationMin 分钟',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color:
                        r.isCompleted ? colorScheme.primary : colorScheme.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LayoutBuilder(builder: (context, constraints) {
              return Stack(
                children: [
                  Container(
                    height: 10,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    height: 10,
                    width: constraints.maxWidth * ratio,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: r.isCompleted
                            ? [
                                colorScheme.primary.withValues(alpha: 0.6),
                                colorScheme.primary
                              ]
                            : [
                                colorScheme.error.withValues(alpha: 0.6),
                                colorScheme.error
                              ],
                      ),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ],
              );
            }),
            if (r.note != null && r.note!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                r.note!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class TimeLogDetailScreen extends StatelessWidget {
  final TimeLogItem log;
  final List<PomodoroTag> tags;
  const TimeLogDetailScreen({super.key, required this.log, required this.tags});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    DateTime start =
        DateTime.fromMillisecondsSinceEpoch(log.startTime, isUtc: true)
            .toLocal();
    DateTime end =
        DateTime.fromMillisecondsSinceEpoch(log.endTime, isUtc: true).toLocal();
    int durationMin = (log.endTime - log.startTime) ~/ 60000;

    Color logColor = colorScheme.primary;
    String tagInfo = '无标签';
    if (log.tagUuids.isNotEmpty) {
      final tag = tags.cast<PomodoroTag?>().firstWhere(
          (t) => log.tagUuids.contains(t?.uuid),
          orElse: () => null);
      if (tag != null) {
        logColor = AppColorUtils.hexToColor(
          tag.color,
          fallback: colorScheme.primary,
        );
        tagInfo = tag.name;
      }
    }

    return AppDetailScreen(
      appBarTitle: '时间日志详情',
      icon: Icons.edit_calendar,
      title: log.title.isNotEmpty ? log.title : '时间日志',
      color: logColor,
      sections: [
        AppDetailSection(
          title: '记录信息',
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: AppDetailInfoCard(
                      icon: Icons.label,
                      title: '标签',
                      value: tagInfo,
                      valueColor: tagInfo != '无标签' ? colorScheme.primary : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppDetailInfoCard(
                      icon: Icons.access_time,
                      title: '时长',
                      value: '$durationMin 分钟',
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: AppDetailInfoCard(
                      icon: Icons.play_arrow_rounded,
                      title: '开始时间',
                      value: AppTimeFormats.compactDateTime(start),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward_rounded,
                        color: colorScheme.onSurfaceVariant, size: 20),
                  ),
                  Expanded(
                    child: AppDetailInfoCard(
                      icon: Icons.stop_rounded,
                      title: '结束时间',
                      value: AppTimeFormats.compactDateTime(end),
                    ),
                  ),
                ],
              ),
            ),
            if (log.remark != null && log.remark!.isNotEmpty)
              AppDetailWideCard(
                icon: Icons.note_rounded,
                title: '备注',
                value: log.remark!,
                maxLines: 10,
              ),
            AppDetailWideCard(
              icon: Icons.update,
              title: '最近更新',
              value: AppTimeFormats.fullDateTime(
                DateTime.fromMillisecondsSinceEpoch(log.updatedAt, isUtc: true)
                    .toLocal(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class PomodoroDetailScreen extends StatelessWidget {
  final PomodoroRecord record;
  final List<PomodoroTag> tags;
  const PomodoroDetailScreen(
      {super.key, required this.record, required this.tags});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    DateTime start =
        DateTime.fromMillisecondsSinceEpoch(record.startTime, isUtc: true)
            .toLocal();
    int endMs =
        record.endTime ?? (record.startTime + record.effectiveDuration * 1000);
    DateTime end =
        DateTime.fromMillisecondsSinceEpoch(endMs, isUtc: true).toLocal();
    Color pomColor = colorScheme.cdtFocus;
    String tagInfo = '无标签';
    if (record.tagUuids.isNotEmpty) {
      final tag = tags.cast<PomodoroTag?>().firstWhere(
          (t) => record.tagUuids.contains(t?.uuid),
          orElse: () => null);
      if (tag != null) {
        pomColor = AppColorUtils.hexToColor(
          tag.color,
          fallback: colorScheme.cdtFocus,
        );
        tagInfo = tag.name;
      }
    }

    String statusText = record.isCompleted ? '已完成' : '已中断';

    final pauseIntervals = record.pauseIntervals ?? [];
    final intervalPauseSeconds = pauseIntervals.fold<int>(
      0,
      (sum, interval) => sum + interval.durationSeconds,
    );
    final storedPauseSeconds = record.totalPauseSeconds ?? 0;
    final totalPauseSeconds = storedPauseSeconds > intervalPauseSeconds
        ? storedPauseSeconds
        : intervalPauseSeconds;
    final totalElapsedSeconds =
        _elapsedSeconds(record, endMs, totalPauseSeconds);
    final focusSeconds =
        _focusSeconds(record, totalElapsedSeconds, totalPauseSeconds);
    final hasPauseData = totalPauseSeconds > 0 || pauseIntervals.isNotEmpty;

    return AppDetailScreen(
      appBarTitle: '番茄钟详情',
      icon: Icons.local_fire_department,
      title: '专注记录',
      color: pomColor,
      sections: [
        AppDetailSection(
          title: '专注信息',
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Builder(
                      builder: (cardCtx) => AppDetailInfoCard(
                        icon: Icons.label,
                        title: '标签',
                        value: tagInfo,
                        valueColor:
                            tagInfo != '无标签' ? colorScheme.primary : null,
                        onTap: tagInfo != '无标签'
                            ? () {
                                final tag = tags
                                    .cast<PomodoroTag?>()
                                    .firstWhere(
                                        (t) =>
                                            record.tagUuids.contains(t?.uuid),
                                        orElse: () => null);
                                if (tag != null) {
                                  final renderBox =
                                      cardCtx.findRenderObject() as RenderBox?;
                                  if (renderBox != null) {
                                    final rect =
                                        renderBox.localToGlobal(Offset.zero) &
                                            renderBox.size;
                                    Navigator.push(
                                      context,
                                      ContainerTransformRoute(
                                        page: PomodoroTagDetailScreen(tag: tag),
                                        sourceRect: rect,
                                        sourceColor:
                                            colorScheme.surfaceContainer,
                                        sourceBorderRadius:
                                            const BorderRadius.all(
                                                Radius.circular(16)),
                                      ),
                                    );
                                  } else {
                                    Navigator.push(
                                      context,
                                      PageTransitions.slideHorizontal(
                                        PomodoroTagDetailScreen(tag: tag),
                                      ),
                                    );
                                  }
                                }
                              }
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppDetailInfoCard(
                      icon: Icons.info_outline,
                      title: '状态',
                      value: statusText,
                      valueColor: record.isCompleted
                          ? colorScheme.cdtSuccess
                          : colorScheme.cdtWarning,
                    ),
                  ),
                ],
              ),
            ),
            if (record.todoTitle != null && record.todoTitle!.isNotEmpty)
              Builder(
                builder: (cardCtx) => AppDetailWideCard(
                  icon: Icons.task_alt,
                  title: '关联待办',
                  value: record.todoTitle!,
                  isLink: true,
                  onTap: () async {
                    final username = await StorageService.getLoginSession();
                    if (username == null) return;
                    if (!context.mounted) return;

                    final allTodos = await StorageService.getTodos(username);
                    final todo = allTodos
                        .where((t) => t.id == record.todoUuid)
                        .firstOrNull;

                    if (todo != null && context.mounted) {
                      final renderBox =
                          cardCtx.findRenderObject() as RenderBox?;
                      if (renderBox != null) {
                        final rect = renderBox.localToGlobal(Offset.zero) &
                            renderBox.size;
                        Navigator.push(
                          context,
                          ContainerTransformRoute(
                            page: TodoDetailScreen(todo: todo),
                            sourceRect: rect,
                            sourceColor: colorScheme.surfaceContainer,
                            sourceBorderRadius:
                                const BorderRadius.all(Radius.circular(16)),
                          ),
                        );
                      } else {
                        Navigator.push(
                          context,
                          PageTransitions.slideHorizontal(
                              TodoDetailScreen(todo: todo)),
                        );
                      }
                    } else if (context.mounted) {
                      AppSnackBars.error(context, "无法找到该待办任务");
                    }
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: AppDetailInfoCard(
                      icon: Icons.play_arrow_rounded,
                      title: '开始时间',
                      value: AppTimeFormats.compactDateTime(start),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward_rounded,
                        color: colorScheme.onSurfaceVariant, size: 20),
                  ),
                  Expanded(
                    child: AppDetailInfoCard(
                      icon: Icons.stop_rounded,
                      title: '结束时间',
                      value: AppTimeFormats.compactDateTime(end),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: AppDetailInfoCard(
                      icon: Icons.timer_outlined,
                      title: '专注时长',
                      value: formatDurationChinese(focusSeconds),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppDetailInfoCard(
                      icon: Icons.access_time_rounded,
                      title: '总耗时',
                      value: formatDurationChinese(totalElapsedSeconds),
                    ),
                  ),
                ],
              ),
            ),
            if (record.note != null && record.note!.isNotEmpty)
              AppDetailWideCard(
                icon: Icons.note_rounded,
                title: '备注',
                value: record.note!,
                maxLines: 10,
              ),
            AppDetailWideCard(
              icon: Icons.update,
              title: '最近更新',
              value: AppTimeFormats.fullDateTime(
                DateTime.fromMillisecondsSinceEpoch(record.updatedAt,
                        isUtc: true)
                    .toLocal(),
              ),
            ),
          ],
        ),
        if (hasPauseData)
          AppDetailSection(
            title: '暂停记录',
            children: [
              AppDetailWideCard(
                icon: Icons.pause_circle_outline,
                title: '总暂停时长',
                value: formatDurationChinese(totalPauseSeconds),
                valueColor: colorScheme.cdtWarning,
              ),
              if (pauseIntervals.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...pauseIntervals.asMap().entries.map((entry) {
                  final index = entry.key + 1;
                  final interval = entry.value;
                  return _buildPauseIntervalRow(
                      context, index, interval, colorScheme);
                }),
              ],
            ],
          ),
      ],
    );
  }

  int _elapsedSeconds(
    PomodoroRecord record,
    int endMs,
    int totalPauseSeconds,
  ) {
    final elapsedSeconds = ((endMs - record.startTime) / 1000).round();
    final actualDuration = record.actualDuration;
    if (record.plannedDuration == 0 &&
        actualDuration != null &&
        totalPauseSeconds > 0) {
      final logicalElapsed = actualDuration + totalPauseSeconds;
      return logicalElapsed > elapsedSeconds
          ? _clampDurationSeconds(logicalElapsed)
          : _clampDurationSeconds(elapsedSeconds);
    }
    return _clampDurationSeconds(elapsedSeconds);
  }

  int _focusSeconds(
    PomodoroRecord record,
    int totalElapsedSeconds,
    int totalPauseSeconds,
  ) {
    if (totalPauseSeconds <= 0) {
      return _clampDurationSeconds(record.effectiveDuration);
    }
    return _clampDurationSeconds(totalElapsedSeconds - totalPauseSeconds);
  }

  int _clampDurationSeconds(int seconds) => seconds.clamp(0, 24 * 3600).toInt();

  Widget _buildPauseIntervalRow(BuildContext context, int index,
      PauseInterval interval, ColorScheme colorScheme) {
    final startLocal =
        DateTime.fromMillisecondsSinceEpoch(interval.startMs).toLocal();
    final endLocal = interval.endMs != null
        ? DateTime.fromMillisecondsSinceEpoch(interval.endMs!).toLocal()
        : null;
    final durationSec = interval.durationSeconds;
    final isOngoing = interval.isOngoing;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isOngoing
                  ? colorScheme.error.withValues(alpha: 0.15)
                  : colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$index',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isOngoing
                    ? colorScheme.error
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${AppTimeFormats.format(startLocal, 'yyyy-MM-dd HH:mm:ss')}${endLocal != null ? ' - ${DateFormat('HH:mm:ss').format(endLocal)}' : ''}',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurface,
                  ),
                ),
                if (isOngoing)
                  Text(
                    '暂停中...',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.error,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isOngoing
                  ? colorScheme.error.withValues(alpha: 0.1)
                  : colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              formatDurationChinese(durationSec),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isOngoing
                    ? colorScheme.error
                    : colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PomodoroTagDetailScreen extends StatefulWidget {
  final PomodoroTag tag;
  const PomodoroTagDetailScreen({super.key, required this.tag});

  @override
  State<PomodoroTagDetailScreen> createState() =>
      _PomodoroTagDetailScreenState();
}

class _PomodoroTagDetailScreenState extends State<PomodoroTagDetailScreen> {
  List<PomodoroRecord> _tagRecords = [];
  bool _loadingRecords = true;

  @override
  void initState() {
    super.initState();
    _loadTagRecords();
  }

  Future<void> _loadTagRecords() async {
    final allRecords = await PomodoroService.getRecords();
    if (mounted) {
      setState(() {
        _tagRecords = allRecords
            .where((r) => r.tagUuids.contains(widget.tag.uuid))
            .toList();
        // 按照开始时间倒序排列
        _tagRecords.sort((a, b) => b.startTime.compareTo(a.startTime));
        _loadingRecords = false;
      });
    }
  }

  Widget _buildStatCard(String title, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(title,
                style: TextStyle(
                    fontSize: 11, color: color.withValues(alpha: 0.8))),
          ],
        ),
      ),
    );
  }

  Widget _buildFocusRecordVisualized(PomodoroRecord r, int maxDuration) {
    final colorScheme = Theme.of(context).colorScheme;
    final startLocal =
        DateTime.fromMillisecondsSinceEpoch(r.startTime, isUtc: true).toLocal();
    final durationMin = r.effectiveDuration ~/ 60;

    final safeMax = maxDuration > 0 ? maxDuration : 1;
    final ratio = (durationMin / safeMax).clamp(0.05, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            PageTransitions.material(
              builder: (_) => PomodoroDetailScreen(
                record: r,
                tags: [widget.tag],
              ),
            ),
          ).then((_) {
            _loadTagRecords();
          });
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppTimeFormats.compactDateTime(startLocal),
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '$durationMin 分钟',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color:
                        r.isCompleted ? colorScheme.primary : colorScheme.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LayoutBuilder(builder: (context, constraints) {
              return Stack(
                children: [
                  Container(
                    height: 10,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    height: 10,
                    width: constraints.maxWidth * ratio,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: r.isCompleted
                            ? [
                                colorScheme.primary.withValues(alpha: 0.6),
                                colorScheme.primary
                              ]
                            : [
                                colorScheme.error.withValues(alpha: 0.6),
                                colorScheme.error
                              ],
                      ),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ],
              );
            }),
            if (r.note != null && r.note!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                r.note!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tagColor = AppColorUtils.hexToColor(
      widget.tag.color,
      fallback: colorScheme.primary,
    );

    int totalDurationSeconds = 0;
    int completedCount = 0;
    int maxFocusDuration = 1;
    if (_tagRecords.isNotEmpty) {
      for (var r in _tagRecords) {
        totalDurationSeconds += r.effectiveDuration;
        if (r.isCompleted) completedCount++;
        int durationMin = r.effectiveDuration ~/ 60;
        if (durationMin > maxFocusDuration) maxFocusDuration = durationMin;
      }
    }
    int totalDurationMin = totalDurationSeconds ~/ 60;
    int avgDurationMin =
        _tagRecords.isNotEmpty ? totalDurationMin ~/ _tagRecords.length : 0;

    return AppDetailScreen(
      appBarTitle: '标签详情',
      icon: Icons.label,
      title: widget.tag.name,
      color: tagColor,
      progress: _tagRecords.isNotEmpty
          ? (completedCount / _tagRecords.length).clamp(0.0, 1.0)
          : 0,
      progressColor: tagColor,
      headerSubtitle: "总计 ${_tagRecords.length} 次专注",
      sections: [
        if (!_loadingRecords && _tagRecords.isNotEmpty)
          AppDetailSection(title: "统计概览", children: [
            Row(
              children: [
                _buildStatCard("总时长", "$totalDurationMin 分钟", tagColor),
                const SizedBox(width: 10),
                _buildStatCard(
                    "平均单次", "$avgDurationMin 分钟", colorScheme.secondary),
                const SizedBox(width: 10),
                _buildStatCard(
                    "成功次数", "$completedCount 次", colorScheme.cdtSuccess),
              ],
            ),
          ]),
        if (!_loadingRecords && _tagRecords.isNotEmpty)
          AppDetailSection(title: "专注记录分布", children: [
            ..._tagRecords
                .take(50)
                .map((r) => _buildFocusRecordVisualized(r, maxFocusDuration)),
            if (_tagRecords.length > 50)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '仅显示最近 50 条',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ]),
        if (!_loadingRecords && _tagRecords.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24.0),
            child: Center(
              child: Text(
                '暂无相关专注记录',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
      ],
    );
  }
}
