part of 'home_dashboard.dart';

// ignore_for_file: annotate_overrides

typedef _DashboardTodoCandidate = ({
  TodoItem todo,
  String specialType,
  DateTime localDueDate,
  DateTime? startTime,
  bool isAllDay,
  bool isCrossDay,
  bool isDateOnly,
});

typedef _DashboardCourseBannerCandidate = ({
  CourseItem course,
  DateTime startTime,
  DateTime endTime,
});

String _formatDashboardPomodoroTimeInfo(
  int secondsRemaining, {
  required bool countUp,
}) {
  if (countUp) return '已专注 ${secondsRemaining ~/ 60}m';
  return secondsRemaining > 60
      ? '${secondsRemaining ~/ 60} 分钟'
      : formatTimerMMSS(secondsRemaining);
}

// Match the displayed minute/second boundaries without allocating strings.
bool _didDashboardPomodoroDisplayChange(
  int previousSeconds,
  int nextSeconds, {
  required bool countUp,
}) {
  if (countUp) return previousSeconds ~/ 60 != nextSeconds ~/ 60;

  final previousUsesMinutes = previousSeconds > 60;
  final nextUsesMinutes = nextSeconds > 60;
  if (previousUsesMinutes != nextUsesMinutes) return true;
  if (previousUsesMinutes) {
    return previousSeconds ~/ 60 != nextSeconds ~/ 60;
  }

  final previousDisplaySeconds = previousSeconds < 0 ? 0 : previousSeconds;
  final nextDisplaySeconds = nextSeconds < 0 ? 0 : nextSeconds;
  return previousDisplaySeconds != nextDisplaySeconds;
}

final Map<(String?, String), DateFormat> _dashboardDateFormats = {};

DateFormat _dashboardDateFormat(String pattern) {
  final locale = Intl.defaultLocale;
  return _dashboardDateFormats.putIfAbsent((
    locale,
    pattern,
  ), () => DateFormat(pattern, locale));
}

mixin _HomeDashboardBannerMixin on _HomeDashboardStateBase {
  List<TodoItem>? _dashboardTodoCandidateSource;
  int? _dashboardTodoCandidateRevision;
  int? _dashboardTodoCandidateTimeZoneOffsetSeconds;
  String? _dashboardTodoCandidateTimeZoneName;
  List<_DashboardTodoCandidate> _dashboardTodoCandidateCache = const [];
  List<TodoItem>? _dashboardBannerTodoSource;
  int? _dashboardBannerTodoRevision;
  DateTime? _dashboardBannerTodoDay;
  int? _dashboardBannerTodoTimeZoneOffsetSeconds;
  String? _dashboardBannerTodoTimeZoneName;
  List<_DashboardTodoCandidate> _dashboardBannerTodoCache = const [];
  Map<String, dynamic>? _dashboardBannerCourseSource;
  int? _dashboardBannerCourseRevision;
  DateTime? _dashboardBannerCourseDay;
  int? _dashboardBannerCourseTimeZoneOffsetSeconds;
  String? _dashboardBannerCourseTimeZoneName;
  List<_DashboardCourseBannerCandidate> _dashboardBannerCourseCache = const [];
  Map<String, dynamic>? _upcomingCourseDataSource;
  List<CourseItem>? _upcomingCourseCache;
  DateTime? _upcomingCourseCacheDate;
  DateTime? _upcomingCourseRefreshAt;
  String? _upcomingCourseCacheUsername;
  int? _upcomingCourseCacheRevision;

  List<_DashboardTodoCandidate> _dashboardTodoCandidatesForCurrentRevision(
    DateTime now,
  ) {
    final source = _todos;
    final revision = _todoDataRevision;
    final timeZoneOffsetSeconds = now.timeZoneOffset.inSeconds;
    final timeZoneName = now.timeZoneName;
    if (identical(source, _dashboardTodoCandidateSource) &&
        revision == _dashboardTodoCandidateRevision &&
        timeZoneOffsetSeconds == _dashboardTodoCandidateTimeZoneOffsetSeconds &&
        timeZoneName == _dashboardTodoCandidateTimeZoneName) {
      return _dashboardTodoCandidateCache;
    }

    final candidates = <_DashboardTodoCandidate>[];
    for (final todo in source) {
      final dueDate = todo.dueDate;
      if (todo.isDone || dueDate == null) continue;
      final specialType = ItemSemanticsService.specialTodoTypeForTitle(
        todo.title,
      );
      final localDueDate = dueDate.toLocal();
      final startTime = specialType == 'default'
          ? DateTime.fromMillisecondsSinceEpoch(
              todo.createdDate ?? todo.createdAt,
            ).toLocal()
          : null;
      candidates.add((
        todo: todo,
        specialType: specialType,
        localDueDate: localDueDate,
        startTime: startTime,
        isAllDay:
            startTime != null &&
            startTime.hour == 0 &&
            startTime.minute == 0 &&
            localDueDate.hour == 23 &&
            localDueDate.minute == 59,
        isCrossDay:
            startTime != null &&
            (startTime.year != localDueDate.year ||
                startTime.month != localDueDate.month ||
                startTime.day != localDueDate.day),
        isDateOnly: specialType == 'default' && todo.isDateOnly,
      ));
    }

    _dashboardTodoCandidateSource = source;
    _dashboardTodoCandidateRevision = revision;
    _dashboardTodoCandidateTimeZoneOffsetSeconds = timeZoneOffsetSeconds;
    _dashboardTodoCandidateTimeZoneName = timeZoneName;
    return _dashboardTodoCandidateCache = candidates;
  }

  List<_DashboardTodoCandidate> _dashboardBannerTodoCandidatesForDay(
    DateTime now,
  ) {
    final today = DateUtils.dateOnly(now);
    final timeZoneOffsetSeconds = now.timeZoneOffset.inSeconds;
    final timeZoneName = now.timeZoneName;
    if (identical(_dashboardBannerTodoSource, _todos) &&
        _dashboardBannerTodoRevision == _todoDataRevision &&
        _dashboardBannerTodoDay == today &&
        timeZoneOffsetSeconds == _dashboardBannerTodoTimeZoneOffsetSeconds &&
        timeZoneName == _dashboardBannerTodoTimeZoneName) {
      return _dashboardBannerTodoCache;
    }

    final candidates = <_DashboardTodoCandidate>[];
    for (final candidate in _dashboardTodoCandidatesForCurrentRevision(now)) {
      if (!AppTimeFormats.isSameDay(candidate.localDueDate, today)) continue;
      if (candidate.specialType == 'default' &&
          (candidate.isAllDay || candidate.isCrossDay)) {
        continue;
      }
      candidates.add(candidate);
    }

    _dashboardBannerTodoSource = _todos;
    _dashboardBannerTodoRevision = _todoDataRevision;
    _dashboardBannerTodoDay = today;
    _dashboardBannerTodoTimeZoneOffsetSeconds = timeZoneOffsetSeconds;
    _dashboardBannerTodoTimeZoneName = timeZoneName;
    return _dashboardBannerTodoCache = candidates;
  }

  List<_DashboardCourseBannerCandidate> _dashboardBannerCoursesForDay(
    DateTime now,
  ) {
    final today = DateUtils.dateOnly(now);
    final timeZoneOffsetSeconds = now.timeZoneOffset.inSeconds;
    final timeZoneName = now.timeZoneName;
    if (identical(_dashboardBannerCourseSource, _dashboardCourseData) &&
        _dashboardBannerCourseRevision == _dashboardCourseDataRefreshRevision &&
        _dashboardBannerCourseDay == today &&
        timeZoneOffsetSeconds == _dashboardBannerCourseTimeZoneOffsetSeconds &&
        timeZoneName == _dashboardBannerCourseTimeZoneName) {
      return _dashboardBannerCourseCache;
    }

    final candidates = <_DashboardCourseBannerCandidate>[];
    final courses =
        (_dashboardCourseData['courses'] as List?)?.cast<CourseItem>() ?? [];
    for (final course in courses) {
      final startTime = _resolveCourseStartTime(course, now);
      if (startTime == null) continue;

      final endTime = DateTime(
        startTime.year,
        startTime.month,
        startTime.day,
        course.endTime ~/ 100,
        course.endTime % 100,
      );
      final startsToday = DateUtils.isSameDay(startTime, today);
      final continuesIntoToday =
          startTime.isBefore(today) && endTime.isAfter(today);
      if (!startsToday && !continuesIntoToday) continue;

      candidates.add((course: course, startTime: startTime, endTime: endTime));
    }

    _dashboardBannerCourseSource = _dashboardCourseData;
    _dashboardBannerCourseRevision = _dashboardCourseDataRefreshRevision;
    _dashboardBannerCourseDay = today;
    _dashboardBannerCourseTimeZoneOffsetSeconds = timeZoneOffsetSeconds;
    _dashboardBannerCourseTimeZoneName = timeZoneName;
    return _dashboardBannerCourseCache = candidates;
  }

  Future<List<CourseItem>> _coursesForUpcomingNotifications(
    DateTime now,
  ) async {
    final today = DateUtils.dateOnly(now);
    final cachedCourses = _upcomingCourseCache;
    final refreshAt = _upcomingCourseRefreshAt;
    if (cachedCourses != null &&
        _upcomingCourseCacheDate == today &&
        _upcomingCourseCacheUsername == widget.username &&
        _upcomingCourseCacheRevision == _dashboardCourseDataRefreshRevision &&
        identical(_upcomingCourseDataSource, _dashboardCourseData) &&
        (refreshAt == null || now.isBefore(refreshAt))) {
      return cachedCourses;
    }

    final source = _dashboardCourseData;
    final revision = _dashboardCourseDataRefreshRevision;
    final dashboardData = await CourseService.getDashboardCourses(
      widget.username,
    );
    final courses =
        (dashboardData['courses'] as List?)?.cast<CourseItem>() ?? [];

    _upcomingCourseDataSource = source;
    _upcomingCourseCache = courses;
    _upcomingCourseCacheDate = today;
    _upcomingCourseCacheUsername = widget.username;
    _upcomingCourseCacheRevision = revision;
    _upcomingCourseRefreshAt = _nextUpcomingCourseRefreshAt(
      dashboardData['title']?.toString(),
      courses,
      now,
    );
    return courses;
  }

  DateTime _nextUpcomingCourseRefreshAt(
    String? title,
    List<CourseItem> courses,
    DateTime now,
  ) {
    final nextDay = DateTime(now.year, now.month, now.day + 1);
    if (title != '今日课程') return nextDay;

    DateTime? lastCourseEnd;
    for (final course in courses) {
      final day = _resolveCourseDay(course, now);
      if (day.year != now.year ||
          day.month != now.month ||
          day.day != now.day) {
        continue;
      }
      final end = _resolveCourseTimeOnDay(course, day, course.endTime);
      if (end != null &&
          (lastCourseEnd == null || end.isAfter(lastCourseEnd))) {
        lastCourseEnd = end;
      }
    }

    return lastCourseEnd != null && lastCourseEnd.isAfter(now)
        ? lastCourseEnd
        : nextDay;
  }

  Widget _buildChallengeParticipationBanner(bool isLight) {
    final scheme = Theme.of(context).colorScheme;
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final banner = _buildBannerCard(
      HomeBannerEvent(
        type: 'challenge',
        title: _thirtyDayChallengeTitle,
        label: '正在参与挑战',
        timeInfo:
            '$_thirtyDayChallengeCompletedCount/$_thirtyDayChallengeTaskCount',
        baseColor: scheme.tertiary,
        icon: '🧭',
        priority: -1,
        onTap: () async {
          await Navigator.of(context, rootNavigator: true).push(
            PageTransitions.slideHorizontal(const ChallengeCenterScreen()),
          );
          if (mounted) {
            _loadThirtyDayChallengeStatus();
          }
        },
      ),
      isLight,
    );
    final positionedBanner = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: banner,
    );

    final topBanner = isLandscape
        ? SizedBox(
            width: MediaQuery.sizeOf(context).width * 0.5,
            child: positionedBanner,
          )
        : SizedBox(width: double.infinity, child: positionedBanner);

    return Align(alignment: Alignment.centerLeft, child: topBanner);
  }

  Widget _buildPendingTodoConfirmCard(bool isLight) {
    if (_pendingTodoConfirm == null) return const SizedBox.shrink();

    final imagePath = _pendingTodoConfirm!['imagePath'] as String?;
    final results = _pendingTodoConfirm!['results'] as List<dynamic>?;
    final status = _pendingTodoConfirm!['status'] as String? ?? 'success';
    final todoCount = results?.length ?? 0;
    final currentAttempt = _pendingTodoConfirm!['currentAttempt'] as int? ?? 1;
    final maxAttempts = _pendingTodoConfirm!['maxAttempts'] as int? ?? 1;
    final errorMsg = _pendingTodoConfirm!['errorMsg'] as String?;

    // 处理中或重试中状态
    final isProcessing = status == 'processing' || status == 'retrying';
    // 失败状态
    final isFailed = status == 'failed';
    // 成功状态
    final isSuccess = status == 'success';

    // 成功状态但没有结果，不显示卡片
    if (isSuccess && todoCount == 0) return const SizedBox.shrink();

    // 根据状态确定图标、标题、副标题
    IconData statusIcon;
    Color iconColor;
    String title;
    String subtitle;

    if (isProcessing) {
      statusIcon = Icons.hourglass_top;
      iconColor = Colors.orange;
      title = 'AI识别中...';
      subtitle = '第$currentAttempt/$maxAttempts次尝试，点击查看 AI 输出与进度';
    } else if (isFailed) {
      statusIcon = Icons.error_outline;
      iconColor = Colors.red;
      title = 'AI识别失败';
      subtitle = errorMsg != null && errorMsg.length > 30
          ? '${errorMsg.substring(0, 30)}...'
          : (errorMsg ?? '点击查看 AI 输出，可选择重试');
    } else {
      statusIcon = Icons.check_circle_outline;
      iconColor = Colors.green;
      title = 'AI识别完成';
      subtitle = '发现 $todoCount 个事项，点击查看 AI 输出与建议';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: AiWaterRippleBorder(
        isLight: isLight,
        child: Material(
          color: isLight ? Colors.white : Colors.grey[900],
          borderRadius: BorderRadius.circular(16),
          elevation: 2,
          child: InkWell(
            onTap: _openPendingRecognitionChat,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // 图片缩略图或状态图标
                  if (isProcessing)
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.orange,
                        ),
                      ),
                    )
                  else if (localImageExists(imagePath))
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: localImageWidget(
                        imagePath!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                      ),
                    )
                  else
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(statusIcon, color: iconColor),
                    ),
                  const SizedBox(width: 12),
                  // 文字信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isLight ? Colors.black87 : Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 13,
                            color: isFailed
                                ? Colors.red[400]
                                : Colors.grey[600],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // 右侧操作按钮
                  if (isProcessing)
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: Colors.grey[400],
                    )
                  else if (isFailed)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 忽略按钮
                        GestureDetector(
                          onTap: _ignorePendingTodoRecognition,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '忽略',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 重试按钮
                        GestureDetector(
                          onTap: _retryPendingTodoRecognition,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              '重试',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.red,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    TextButton(
                      onPressed: _openPendingTodoConfirm,
                      child: const Text('去确认'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 重试图片识别
  Future<void> _retryPendingTodoRecognition() async {
    // 更新状态为重试中
    setState(() {
      _pendingTodoConfirm = {...?_pendingTodoConfirm, 'status': 'retrying'};
    });

    await ExternalShareHandler.retryTodoRecognition(
      onTodoRecognized: (results, imagePath) {
        if (!mounted) return;
        // 刷新待确认数据
        _checkPendingTodoConfirm().then((_) {
          // 如果识别成功且有结果，打开确认页面
          if (results.isNotEmpty) {
            _openPendingTodoConfirm();
          }
        });
      },
      onFinanceRecognized: (drafts, imagePath) async {
        await _openRecognizedFinanceDrafts(drafts);
      },
    );

    // 重试完成后刷新首页状态（无论成功或失败）
    if (mounted) {
      await _checkPendingTodoConfirm();
    }
  }

  /// 忽略图片识别失败
  Future<void> _ignorePendingTodoRecognition() async {
    // 清除待确认数据
    setState(() {
      _pendingTodoConfirm = null;
    });
    await ExternalShareHandler.clearPendingTodoConfirm();
    // 取消通知
    await NotificationService.cancelTodoRecognizeNotification();
  }

  /// 首页顶部的智能通用 Banner (整合专注、课程、待办)
  Widget _buildUniversalBanner(bool isLight) {
    final hasLocalPomodoro = _localPomodoro != null;
    final hasActivePlanBlock =
        hasLocalPomodoro &&
        _planBlocks.any(
          (block) =>
              !block.isDeleted && block.status == TodoPlanStatus.focusing,
        );
    final events = _collectBannerEvents(hasActivePlanBlock: hasActivePlanBlock);
    final showPomodoro = hasLocalPomodoro || _remotePomodoro != null;
    if (events.isEmpty && !showPomodoro) return const SizedBox.shrink();

    return HomeDashboardBannerLayout(
      bannerKey: _focusBannerKey,
      pomodoroRevision: _pomodoroDisplayTickNotifier,
      showPomodoro: showPomodoro,
      pomodoroChild: showPomodoro
          ? _buildPomodoroBannerCard(
              isLight,
              hasActivePlanBlock: hasActivePlanBlock,
            )
          : null,
      pomodoroBuilder: (_) => _buildPomodoroBannerCard(
        isLight,
        hasActivePlanBlock: hasActivePlanBlock,
      ),
      banners: events.map((event) => _buildBannerCard(event, isLight)).toList(),
    );
  }

  Widget _buildPomodoroBannerCard(
    bool isLight, {
    required bool hasActivePlanBlock,
  }) {
    final localPomodoro = _localPomodoro;
    if (localPomodoro != null) {
      final isCountUp = localPomodoro.mode == TimerMode.countUp;
      final remaining = _localPomodoroRemaining;
      final baseColor = const Color(0xFF4F46E5);
      return _buildBannerCard(
        HomeBannerEvent(
          type: 'pomodoro',
          title: localPomodoro.todoTitle ?? '无标题专注',
          label: '⚡ 正在专注 (本机)',
          timeInfo: _formatDashboardPomodoroTimeInfo(
            remaining,
            countUp: isCountUp,
          ),
          baseColor: baseColor,
          icon: '🍅',
          priority: 0,
          onTap: () async {
            await PageTransitions.pushFromRect(
              context: context,
              page: PomodoroScreen(username: widget.username),
              sourceKey: _focusBannerKey,
            );
          },
        ),
        isLight,
        trailingWidget: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _pomodoroDisplayTickNotifier,
            builder: (context, _) {
              final currentPomodoro = _localPomodoro;
              if (currentPomodoro == null) return const SizedBox.shrink();

              final nowMs = DateTime.now().millisecondsSinceEpoch;
              final isCountUp = currentPomodoro.mode == TimerMode.countUp;
              final rem = isCountUp
                  ? ((nowMs - currentPomodoro.sessionStartMs) / 1000).floor()
                  : ((currentPomodoro.targetEndMs - nowMs) / 1000).ceil();
              final showStopBtn =
                  hasActivePlanBlock && !isCountUp && rem > 0 && rem <= 1800;

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatDashboardPomodoroTimeInfo(rem, countUp: isCountUp),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isLight ? Colors.white : baseColor,
                    ),
                  ),
                  if (showStopBtn) ...[
                    const SizedBox(width: 8),
                    _buildPomodoroStopButton(isLight, baseColor),
                  ],
                ],
              );
            },
          ),
        ),
      );
    }

    final remotePomodoro = _remotePomodoro;
    if (remotePomodoro == null) return const SizedBox.shrink();

    final deviceLabel =
        remotePomodoro.sourceDevice
            ?.replaceFirst('flutter_', '')
            .substring(0, 8) ??
        '其他设备';
    final isCountUp = remotePomodoro.mode == 1;

    final baseColor = const Color(0xFFFF6B6B);
    return _buildBannerCard(
      HomeBannerEvent(
        type: 'pomodoro',
        title: remotePomodoro.todoTitle ?? '其他设备专注',
        label: '📱 $deviceLabel 正在专注',
        timeInfo: _formatDashboardPomodoroTimeInfo(
          _remotePomodoroRemaining,
          countUp: isCountUp,
        ),
        baseColor: baseColor,
        icon: '🍅',
        priority: 1,
        onTap: () => PageTransitions.pushFromRect(
          context: context,
          page: PomodoroScreen(username: widget.username),
          sourceKey: _focusBannerKey,
        ),
      ),
      isLight,
      trailingWidget: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _pomodoroDisplayTickNotifier,
          builder: (context, _) => Text(
            _formatDashboardPomodoroTimeInfo(
              _remotePomodoroRemaining,
              countUp: isCountUp,
            ),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isLight ? Colors.white : baseColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBannerCard(
    HomeBannerEvent event,
    bool isLight, {
    Widget? trailingWidget,
  }) {
    final baseColor = event.baseColor;
    return GestureDetector(
      onTap: event.onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: baseColor.withValues(alpha: isLight ? 0.85 : 0.15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: baseColor.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Text(event.icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    event.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isLight
                          ? Colors.white.withValues(alpha: 0.9)
                          : baseColor,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          event.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isLight ? Colors.white : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (event.isTeam)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: isLight
                                ? Colors.white.withValues(alpha: 0.2)
                                : baseColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isLight
                                  ? Colors.white38
                                  : baseColor.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            '团队',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: isLight ? Colors.white : baseColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (event.subtitle != null && event.subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          Icon(
                            event.type == 'course'
                                ? Icons.location_on_outlined
                                : event.type == 'special_todo'
                                ? Icons.confirmation_number_outlined
                                : Icons.sticky_note_2_outlined,
                            size: 11,
                            color: isLight ? Colors.white70 : Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              event.subtitle!,
                              style: TextStyle(
                                fontSize: 11,
                                color: isLight
                                    ? Colors.white70
                                    : Colors.grey[600],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            trailingWidget ??
                Text(
                  event.timeInfo,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isLight ? Colors.white : baseColor,
                  ),
                ),
            if (event.actionLabel != null && trailingWidget == null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: event.onAction,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isLight
                        ? Colors.white.withValues(alpha: 0.25)
                        : baseColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (event.actionIcon != null) ...[
                        Icon(
                          event.actionIcon,
                          size: 14,
                          color: isLight ? Colors.white : baseColor,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        event.actionLabel!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isLight ? Colors.white : baseColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              color: isLight ? Colors.white70 : baseColor,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPomodoroStopButton(bool isLight, Color baseColor) {
    return GestureDetector(
      onTap: _stopPlanBlockPomodoro,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isLight
              ? Colors.white.withValues(alpha: 0.25)
              : baseColor.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.stop_rounded,
              size: 14,
              color: isLight ? Colors.white : baseColor,
            ),
            const SizedBox(width: 4),
            Text(
              '关闭',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isLight ? Colors.white : baseColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<HomeBannerEvent> _collectBannerEvents({
    required bool hasActivePlanBlock,
  }) {
    final List<HomeBannerEvent> events = [];
    final now = DateTime.now();

    // 1.5 规划块 (无本地/远端番茄钟运行时展示，支持一键开始/重新开始)
    // 仅在开始前 30 分钟内、进行中、或专注中断时提醒
    if (_localPomodoro == null && _remotePomodoro == null) {
      final nowMs = now.millisecondsSinceEpoch;
      const lookAheadMs = 30 * 60 * 1000;
      final activeBlock = _planBlocks.where((b) {
        if (b.isDeleted) return false;
        if (!_isPlanBlockStartable(b.status)) return false;
        if (nowMs > b.endTime) return false;
        if (b.status == TodoPlanStatus.focusing) return true;
        return nowMs >= b.startTime - lookAheadMs;
      }).firstOrNull;
      if (activeBlock != null) {
        final title = activeBlock.titleSnapshot?.isNotEmpty == true
            ? activeBlock.titleSnapshot!
            : '规划任务';
        final isInterrupted = activeBlock.status == TodoPlanStatus.focusing;
        final remainMin = ((activeBlock.endTime - nowMs) / 60000).ceil();
        final timeText = isInterrupted
            ? (remainMin > 0 ? '剩 ${remainMin}m' : '已超时')
            : (nowMs < activeBlock.startTime
                  ? _planBlockStartText(activeBlock.startTime, nowMs)
                  : (remainMin > 0 ? '剩 ${remainMin}m' : '进行中'));

        events.add(
          HomeBannerEvent(
            type: 'plan_block',
            title: title,
            label: isInterrupted ? '⏱ 专注中断' : '📋 规划待专注',
            timeInfo: timeText,
            baseColor: isInterrupted
                ? Colors.deepOrange
                : const Color(0xFF7C4DFF),
            icon: '📋',
            priority: 1,
            actionLabel: '打开番茄钟',
            actionIcon: Icons.play_arrow_rounded,
            onTap: () async {
              await Navigator.of(context).push(
                PageTransitions.material(
                  builder: (_) => TodoPlanScreen(
                    username: widget.username,
                    initialDate: DateTime.now(),
                  ),
                ),
              );
              _scheduleRevision.value++;
              _timelineRevision.value++;
              _loadAllData(
                domains: const {
                  DataRefreshDomain.todos,
                  DataRefreshDomain.planBlocks,
                  DataRefreshDomain.fixedSchedules,
                },
              );
            },
            onAction: () =>
                _startPlanBlockFocus(activeBlock, sourceKey: _focusBannerKey),
          ),
        );
      }
    }

    // 2. 课程
    for (final candidate in _dashboardBannerCoursesForDay(now)) {
      final course = candidate.course;
      final startTime = candidate.startTime;
      final endTime = candidate.endTime;

      final diffStart = startTime.difference(now).inMinutes;
      final isOngoing = now.isAfter(startTime) && now.isBefore(endTime);

      if (isOngoing) {
        final remaining = endTime.difference(now).inMinutes;
        events.add(
          HomeBannerEvent(
            type: 'course',
            title: course.courseName,
            subtitle: course.roomName,
            label: '📖 正在进行的课程',
            timeInfo: '剩 ${remaining}m',
            baseColor: Colors.teal,
            icon: '🏫',
            priority: 2,
            isTeam: course.teamUuid != null,
            onTap: () => Navigator.push(
              context,
              PageTransitions.slideHorizontal(
                CourseDetailScreen(course: course),
              ),
            ),
          ),
        );
      } else if (diffStart >= 0 && diffStart <= 20) {
        events.add(
          HomeBannerEvent(
            type: 'course',
            title: course.courseName,
            subtitle: course.roomName,
            label: '🔔 即将开始的课程',
            timeInfo: '${diffStart}m 后开始',
            baseColor: Colors.cyan,
            icon: '🏫',
            priority: 4,
            isTeam: course.teamUuid != null,
            onTap: () => Navigator.push(
              context,
              PageTransitions.slideHorizontal(
                CourseDetailScreen(course: course),
              ),
            ),
          ),
        );
      }
    }

    // 3. 待办候选项只遍历一次；先分桶再按原顺序加入事件。
    final specialTodoEvents = <HomeBannerEvent>[];
    final regularTodoEvents = <HomeBannerEvent>[];
    for (final candidate in _dashboardBannerTodoCandidatesForDay(now)) {
      final todo = candidate.todo;
      if (todo.isDeleted) continue;
      final specialType = candidate.specialType;
      if (specialType != 'default') {
        specialTodoEvents.add(
          HomeBannerEvent(
            type: 'special_todo',
            title: todo.title,
            subtitle: todo.remark,
            label: _specialTodoBannerLabel(specialType),
            timeInfo: _specialTodoBannerTimeInfo(todo, now),
            baseColor: _specialTodoBannerColor(specialType),
            icon: _specialTodoBannerIcon(specialType),
            priority: 2,
            isTeam: todo.teamUuid != null,
            onTap: () => _openTodoEditor(todo),
          ),
        );
        continue;
      }

      final startTime = candidate.startTime!;
      final endTime = candidate.localDueDate;

      final diffStart = startTime.difference(now).inMinutes;
      final isOngoing = now.isAfter(startTime) && now.isBefore(endTime);

      if (isOngoing) {
        final remaining = endTime.difference(now).inMinutes;
        regularTodoEvents.add(
          HomeBannerEvent(
            type: 'todo',
            title: todo.title,
            subtitle: todo.remark,
            label: '📌 正在进行的任务',
            timeInfo: '剩 ${remaining}m',
            baseColor: Colors.amber[700]!,
            icon: '📝',
            priority: 3,
            isTeam: todo.teamUuid != null,
            onTap: () => _openTodoEditor(todo),
          ),
        );
      } else if (diffStart >= 0 && diffStart <= 30) {
        regularTodoEvents.add(
          HomeBannerEvent(
            type: 'todo',
            title: todo.title,
            subtitle: todo.remark,
            label: '⏰ 即将开始的任务',
            timeInfo: '${diffStart}m 后开始',
            baseColor: Colors.orange,
            icon: '📝',
            priority: 5,
            isTeam: todo.teamUuid != null,
            onTap: () => _openTodoEditor(todo),
          ),
        );
      }
    }
    events
      ..addAll(specialTodoEvents)
      ..addAll(regularTodoEvents);

    // 排序: 优先级数值越小越靠前
    events.sort((a, b) => a.priority.compareTo(b.priority));
    return events;
  }

  void _openTodoEditor(TodoItem todo) {
    Navigator.push(
      context,
      PageTransitions.material(
        builder: (_) => TodoEditScreen(
          todo: todo,
          todos: _todos,
          onTodosChanged: _handleTodosChanged,
          onEditorSave: _handleTodoEditorSave,
          onEditorGroupsSave: _handleTodoEditorGroupsSave,
          todoGroups: _todoGroups,
          onGroupsChanged: (newGroups) async {
            final allGroups = await StorageService.getTodoGroups(
              widget.username,
            );
            for (var g in newGroups) {
              int idx = allGroups.indexWhere((x) => x.id == g.id);
              if (idx != -1) {
                allGroups[idx] = g;
              } else {
                allGroups.add(g);
              }
            }
            await StorageService.saveTodoGroups(widget.username, allGroups);
            if (!mounted) return;
            setState(() {
              _todoGroups = newGroups;
              _todoDataRevision++;
            });
            _loadAllData(domains: const {DataRefreshDomain.todoGroups});
          },
          username: widget.username,
        ),
      ),
    );
  }

  String _specialTodoBannerLabel(String specialType) {
    switch (specialType) {
      case 'delivery':
        return '📦 取件待办';
      case 'cafe':
      case 'food':
        return '🥡 取餐待办';
      case 'restaurant':
        return '🍽️ 餐饮待办';
      default:
        return '📌 特殊待办';
    }
  }

  String _specialTodoBannerIcon(String specialType) {
    switch (specialType) {
      case 'delivery':
        return '📦';
      case 'cafe':
        return '☕';
      case 'food':
        return '🥡';
      case 'restaurant':
        return '🍽️';
      default:
        return '📌';
    }
  }

  Color _specialTodoBannerColor(String specialType) {
    switch (specialType) {
      case 'delivery':
        return const Color(0xFFFF8A65);
      case 'cafe':
        return const Color(0xFF8D6E63);
      case 'food':
        return const Color(0xFFFF7043);
      case 'restaurant':
        return const Color(0xFFFFB74D);
      default:
        return Colors.amber[700]!;
    }
  }

  String _specialTodoBannerTimeInfo(TodoItem todo, DateTime now) {
    final dueDate = todo.dueDate?.toLocal();
    if (dueDate == null) return '今日';

    if (todo.isOverdueAt(now)) return '待处理';
    if (todo.isDateOnly) return '今日';
    return _dashboardDateFormat('HH:mm').format(dueDate);
  }

  // === 业务与辅助逻辑 ===
  DateTime? _resolveCourseStartTime(CourseItem course, DateTime now) {
    final day = _resolveCourseDay(course, now);
    return _resolveCourseTimeOnDay(course, day, course.startTime);
  }

  DateTime _resolveCourseDay(CourseItem course, DateTime now) {
    final dateText = course.date.trim();

    DateTime? day;
    if (dateText.isNotEmpty) {
      // Prefer strict date parsing, then allow DateTime-compatible fallback.
      try {
        day = _dashboardDateFormat('yyyy-MM-dd').parseStrict(dateText);
      } catch (_) {
        day = DateTime.tryParse(dateText);
      }
    }

    // Fallback for legacy records without date: infer the day from weekday.
    return day ??
        DateUtils.dateOnly(now)
            .add(Duration(days: course.weekday - now.weekday));
  }

  DateTime? _resolveCourseTimeOnDay(CourseItem course, DateTime day, int time) {
    final int hour = time ~/ 100;
    final int minute = time % 100;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;

    return DateTime(day.year, day.month, day.day, hour, minute);
  }

  Future<void> _checkUpcomingEvents() async {
    if (_isCheckingUpcomingEvents) {
      _upcomingEventsCheckPending = true;
      return;
    }
    _isCheckingUpcomingEvents = true;
    try {
      do {
        _upcomingEventsCheckPending = false;
        await _performUpcomingEventsCheck();
      } while (mounted && _upcomingEventsCheckPending);
    } finally {
      _isCheckingUpcomingEvents = false;
    }
  }

  Future<void> _performUpcomingEventsCheck() async {
    DateTime now = DateTime.now();
    final persistDesktopShownState =
        AppPlatform.isWindows || AppPlatform.isMacOS;
    final desktopShownStateKey =
        'desktop_live_notification_shown_${widget.username}';
    final desktopPrefs = persistDesktopShownState
        ? await SharedPreferences.getInstance()
        : null;
    final desktopShownKeys =
        desktopPrefs?.getStringList(desktopShownStateKey)?.toSet() ??
        <String>{};

    Future<void> markDesktopNotificationShown(String key) async {
      if (desktopPrefs == null || !desktopShownKeys.add(key)) return;
      while (desktopShownKeys.length > 200) {
        desktopShownKeys.remove(desktopShownKeys.first);
      }
      await desktopPrefs.setStringList(
        desktopShownStateKey,
        desktopShownKeys.toList(),
      );
    }

    // 🚀 核心优化：取消一开始就将上一轮通知全量物理注销的逻辑
    // 改为记录上一轮的活跃 ID，本轮计算结束后做差集物理注销
    final previousTodoIds = Set<int>.from(_activeTodoNotifIds);
    final newTodoNotifIds = <int>{};

    // ── 获取已注册闹钟，构建课程去重集合 ──
    try {
      final scheduled = await NotificationService.getScheduledReminders();
      _coursesWithScheduledAlarms.clear();
      _todosWithScheduledAlarms.clear();
      for (final r in scheduled) {
        if (r['type'] == 'course' && r['courseName'] != null) {
          _coursesWithScheduledAlarms.add(r['courseName'] as String);
        }
        if ((r['type'] == 'upcoming_todo' || r['type'] == 'special_todo') &&
            r['todoId'] != null) {
          _todosWithScheduledAlarms.add(r['todoId'].toString());
        }
      }
    } catch (_) {}

    // ── 课程通知 ────────────────────────────────────────────────
    const int courseNotificationId = 12347;

    final courses = await _coursesForUpcomingNotifications(now);

    bool hasUpcomingCourse = false;
    String? activeCourseKey;
    for (var course in courses) {
      try {
        final courseDay = _resolveCourseDay(course, now);
        final courseTime = _resolveCourseTimeOnDay(
          course,
          courseDay,
          course.startTime,
        );
        final courseEndTime = _resolveCourseTimeOnDay(
          course,
          courseDay,
          course.endTime,
        );
        if (courseTime == null || courseEndTime == null) continue;

        // 显示窗口：自上课前 20 分钟起，直到下课结束
        final isInsideWindow =
            now.isAfter(courseTime.subtract(const Duration(minutes: 20))) &&
            now.isBefore(courseEndTime);
        if (isInsideWindow) {
          // 已有定时闹钟的课程不再弹实时活动通知
          if (_coursesWithScheduledAlarms.contains(course.courseName)) {
            hasUpcomingCourse = true;
            break;
          }
          activeCourseKey =
              '${courseTime.millisecondsSinceEpoch}:${course.courseName}';
          final desktopEventKey = 'course:$activeCourseKey';
          if (_activeCourseNotificationKey != activeCourseKey &&
              !desktopShownKeys.contains(desktopEventKey)) {
            await NotificationService.showCourseLiveActivity(
              courseName: course.courseName,
              room: course.roomName,
              timeStr:
                  '${course.formattedStartTime} - ${course.formattedEndTime}',
              teacher: course.teacherName,
            );
            await markDesktopNotificationShown(desktopEventKey);
          }
          hasUpcomingCourse = true;
          break;
        }
      } catch (e) {
        // debugPrint(
        //     "检查课程通知失败: $e (course=${course.courseName}, date='${course.date}', start=${course.startTime})");
      }
    }

    // 没有课程在窗口内，仅取消课程通知（不影响待办等其他通知）
    if (!hasUpcomingCourse || activeCourseKey == null) {
      await NotificationService.cancelSpecialTodoNotification(
        courseNotificationId,
      );
    }
    _activeCourseNotificationKey = activeCourseKey;

    // ── 待办提醒 ────────────────────────────────────────────────
    final specialTodosToday = <TodoItem>[];
    final upcomingRegularTodos = <TodoItem>[];
    final allDayTodos = <TodoItem>[];
    for (final candidate in _dashboardTodoCandidatesForCurrentRevision(now)) {
      final todo = candidate.todo;
      final dueDate = todo.dueDate;
      if (todo.isDone || dueDate == null) continue;

      final todoType = candidate.specialType;
      final isSpecialTodo = todoType != 'default';
      final localDueDate = candidate.localDueDate;
      final isDueToday = AppTimeFormats.isSameDay(localDueDate, now);

      if (!todo.isDeleted) {
        if (isSpecialTodo && isDueToday) {
          specialTodosToday.add(todo);
        } else if (!isSpecialTodo &&
            TodoNotificationPolicy.isInsideLiveWindowForLocalDueDate(
              localDueDate: localDueDate,
              isDateOnly: candidate.isDateOnly,
              now: now,
            )) {
          upcomingRegularTodos.add(todo);
        }
      }

      // Preserve the existing all-day summary behavior for deleted todos.
      if (!isSpecialTodo &&
          isDueToday &&
          localDueDate.hour == 23 &&
          localDueDate.minute == 59) {
        final startDate = candidate.startTime!;
        if (startDate.hour == 0 && startDate.minute == 0) {
          allDayTodos.add(todo);
        }
      }
    }

    // 1. 特殊待办 (快递/外卖等): 今天所有的都显示

    for (final todo in specialTodosToday) {
      final int notifId = todo.id.hashCode;
      final desktopEventKey =
          'todo:${todo.id}:${todo.dueDate!.millisecondsSinceEpoch}';
      // A scheduled reminder is only the later alarm (usually five minutes
      // before the deadline). Today's pickup still needs to appear on the
      // island as soon as it is added, and stay active until completed.
      var notificationIsActive =
          previousTodoIds.contains(notifId) ||
          desktopShownKeys.contains(desktopEventKey);
      if (!notificationIsActive) {
        notificationIsActive =
            await NotificationService.showUpcomingTodoNotification(todo);
        if (notificationIsActive) {
          await markDesktopNotificationShown(desktopEventKey);
        }
      }
      if (notificationIsActive) newTodoNotifIds.add(notifId);
    }

    // 2. 普通待办 (非全天): 在时间段内（提前 30 分钟直到截止时间）均显示为活动状态
    for (final todo in upcomingRegularTodos) {
      final int notifId = todo.id.hashCode;
      final desktopEventKey =
          'todo:${todo.id}:${todo.dueDate!.millisecondsSinceEpoch}';
      if (!_todosWithScheduledAlarms.contains(todo.id)) {
        newTodoNotifIds.add(notifId);
        // A desktop `show` call raises a new banner. Only raise it when the item
        // enters the active set; the minute poll should not repeatedly pop it.
        if (!previousTodoIds.contains(notifId) &&
            !desktopShownKeys.contains(desktopEventKey)) {
          await NotificationService.showUpcomingTodoNotification(todo);
          await markDesktopNotificationShown(desktopEventKey);
        }
      }
    }

    // 3. 全天待办汇总
    NotificationService.updateTodoNotification(allDayTodos);

    // 🚀 4. 差集物理取消不再需要的通知
    final idsToCancel = previousTodoIds.difference(newTodoNotifIds);
    for (final id in idsToCancel) {
      await NotificationService.cancelSpecialTodoNotification(id);
    }

    // 🚀 5. 更新当前的活跃集合
    _activeTodoNotifIds.clear();
    _activeTodoNotifIds.addAll(newTodoNotifIds);
  }
}
