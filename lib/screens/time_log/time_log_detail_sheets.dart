part of '../time_log_screen.dart';

extension _TimeLogDetailSheetsExt on _TimeLogScreenState {
  // ── 共用弹窗容器 ─────────────────────────────────────
  Widget _sheet(Color borderColor, Widget child) => OptionalLiquidGlassSheet(
    topRadius: 20,
    padding: EdgeInsets.fromLTRB(
      20,
      20,
      20,
      MediaQuery.paddingOf(context).bottom + 20,
    ),
    fallbackDecoration: BoxDecoration(
      color: _TC.card(context),
      border: Border(top: BorderSide(color: borderColor, width: 1.5)),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
    ),
    child: child,
  );

  void _showPomodoroDetail(PomodoroRecord pom) {
    final colorScheme = Theme.of(context).colorScheme;
    final tag = pom.tagUuids.isNotEmpty
        ? _tags.cast<PomodoroTag?>().firstWhere(
            (t) => t?.uuid == pom.tagUuids.first,
            orElse: () => null,
          )
        : null;
    final tc = tag != null ? hexColor(tag.color) : colorScheme.cdtFocus;
    final endMs = pom.endTime ?? (pom.startTime + pom.effectiveDuration * 1000);
    final dur = pom.effectiveDuration ~/ 60;
    final s = DateTime.fromMillisecondsSinceEpoch(pom.startTime);
    final e = DateTime.fromMillisecondsSinceEpoch(endMs);
    showAppModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _sheet(
        tc.withValues(alpha: 0.4),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _glow(tc),
                const SizedBox(width: 10),
                Text(
                  '专注记录',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _TC.text(context),
                  ),
                ),
                const Spacer(),
                _pill('${dur}min', tc),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: _TC.textHint(context),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            if (tag != null) ...[
              const SizedBox(height: 10),
              _tagRow(tag.name, tc),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _InfoCard(
                    label: '开始',
                    value: AppTimeFormats.clock(s),
                    sub: AppTimeFormats.monthDaySlash(s),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InfoCard(
                    label: '结束',
                    value: AppTimeFormats.clock(e),
                    sub: AppTimeFormats.monthDaySlash(e),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InfoCard(
                    label: '时长',
                    value: '${dur}min',
                    sub: (pom.isCompleted == true) ? '✓ 完成' : '手动停止',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showTimeLogDetail(TimeLogItem log) {
    final tag = log.tagUuids.isNotEmpty
        ? _tags.cast<PomodoroTag?>().firstWhere(
            (t) => t?.uuid == log.tagUuids.first,
            orElse: () => null,
          )
        : null;
    final c = tag != null
        ? hexColor(tag.color)
        : Theme.of(context).colorScheme.cdtInfo;
    final dur = (log.endTime - log.startTime) ~/ 60000;
    final s = DateTime.fromMillisecondsSinceEpoch(log.startTime);
    final e = DateTime.fromMillisecondsSinceEpoch(log.endTime);
    showAppModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _sheet(
        c.withValues(alpha: 0.4),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _glow(c),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    log.title.isNotEmpty ? log.title : (tag?.name ?? '补录记录'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _TC.text(context),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _pill('${dur}min', c),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: _TC.textHint(context),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            if (tag != null) ...[
              const SizedBox(height: 10),
              _tagRow(tag.name, c),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _InfoCard(
                    label: '开始',
                    value: AppTimeFormats.clock(s),
                    sub: AppTimeFormats.monthDaySlash(s),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InfoCard(
                    label: '结束',
                    value: AppTimeFormats.clock(e),
                    sub: AppTimeFormats.monthDaySlash(e),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InfoCard(
                    label: '时长',
                    value: '${dur}min',
                    sub: '手动补录',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _editTimeLog(log);
                    },
                    icon: const Icon(Icons.edit_note, size: 18),
                    label: const Text(
                      '编辑记录',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _TC.text(context),
                      side: BorderSide(color: _TC.divider(context)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _deleteLog(log.id);
                    },
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text(
                      '删除记录',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.error
                            .withValues(alpha: 0.4),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAggregatedScheduleSheet(
    List<TimeLogMappedSchedule> schedules,
    DateTime date,
  ) {
    if (schedules.isEmpty) return;
    if (schedules.length == 1) {
      _showScheduleDetail(schedules.first);
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = schedules.first;
    final primaryColor = primary.isCourse
        ? (isDark ? const Color(0xFF64B5F6) : const Color(0xFF1E88E5))
        : (isDark ? const Color(0xFFFFB74D) : const Color(0xFFFB8C00));
    final dateStr = AppTimeFormats.monthDaySlash(date);
    final weekdayStr = AppTimeFormats.weekdayZh(date.weekday);

    showAppModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _sheet(
        primaryColor.withValues(alpha: 0.4),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _glow(primaryColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$dateStr $weekdayStr · 重叠日程 (${schedules.length}项)',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: _TC.text(context),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: _TC.textHint(context),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: schedules.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (ctx, index) {
                  final schedule = schedules[index];
                  final isCourse = schedule.isCourse;
                  final c = isCourse
                      ? (isDark
                            ? const Color(0xFF64B5F6)
                            : const Color(0xFF1E88E5))
                      : (isDark
                            ? const Color(0xFFFFB74D)
                            : const Color(0xFFFB8C00));
                  final s = DateTime.fromMillisecondsSinceEpoch(
                    schedule.startTime,
                  );
                  final e = DateTime.fromMillisecondsSinceEpoch(
                    schedule.endTime,
                  );
                  final dur = (schedule.endTime - schedule.startTime) ~/ 60000;

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showScheduleDetail(schedule);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: c.withValues(alpha: isDark ? 0.12 : 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border(
                            left: BorderSide(color: c, width: 3.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          schedule.title,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: _TC.text(context),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _pill(isCourse ? '课程' : '日程', c),
                                      const SizedBox(width: 4),
                                      _pill('${dur}min', c),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Text(
                                        AppTimeFormats.range(s, e),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: _TC.textSub(context),
                                        ),
                                      ),
                                      if (schedule.subtitle != null &&
                                          schedule.subtitle!.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            schedule.subtitle!,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: _TC.textHint(context),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: _TC.textHint(context),
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
        ),
      ),
    );
  }

  void _showScheduleDetail(TimeLogMappedSchedule schedule) {
    final isCourse = schedule.isCourse;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isCourse
        ? (isDark ? const Color(0xFF64B5F6) : const Color(0xFF1E88E5))
        : (isDark ? const Color(0xFFFFB74D) : const Color(0xFFFB8C00));
    final dur = (schedule.endTime - schedule.startTime) ~/ 60000;
    final s = DateTime.fromMillisecondsSinceEpoch(schedule.startTime);
    final e = DateTime.fromMillisecondsSinceEpoch(schedule.endTime);

    showAppModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _sheet(
        c.withValues(alpha: 0.4),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _glow(c),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    schedule.title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _TC.text(context),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _pill(isCourse ? '课程' : '日程', c),
                const SizedBox(width: 6),
                _pill('${dur}min', c),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: _TC.textHint(context),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            if (schedule.subtitle != null && schedule.subtitle!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    isCourse ? Icons.place_outlined : Icons.info_outline,
                    size: 14,
                    color: _TC.textSub(context),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      schedule.subtitle!,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: _TC.textSub(context),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _InfoCard(
                    label: '开始',
                    value: AppTimeFormats.clock(s),
                    sub: AppTimeFormats.monthDaySlash(s),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InfoCard(
                    label: '结束',
                    value: AppTimeFormats.clock(e),
                    sub: AppTimeFormats.monthDaySlash(e),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InfoCard(label: '时长', value: '$dur', sub: '分钟'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _glow(Color c) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      color: c,
      shape: BoxShape.circle,
      boxShadow: [BoxShadow(color: c, blurRadius: 6)],
    ),
  );

  Widget _pill(String t, Color c) => AppMetricChip(label: t, color: c);

  Widget _tagRow(String name, Color c) => Row(
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      ),
      const SizedBox(width: 8),
      Text(
        name,
        style: TextStyle(fontSize: 13, color: c, fontWeight: FontWeight.w600),
      ),
    ],
  );

  void _showTagDetail(PomodoroTag tag) {
    showAppModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TagDetailSheet(
        tag: tag,
        logs: _allLogs,
        pomodoros: _allPomodoros,
        onDelete: (id) {
          Navigator.pop(context);
          _deleteLog(id);
        },
      ),
    );
  }

  void _showTagManager() async {
    final updated = await PageTransitions.pushFromRect<List<PomodoroTag>>(
      context: context,
      page: UnifiedTagManagerScreen(
        allTags: _allTags,
        showSelection: false,
        showArchive: true,
        onChanged: (tags, selected) async {
          await PomodoroService.saveTags(tags);
          _mutateState(() {
            _allTags = tags;
            _tags = tags.where((t) => !t.isArchived).toList();
          });
        },
      ),
      sourceKey: timeLogTagKey,
      sourceBorderRadius: BorderRadius.circular(_timeLogActionChipRadius),
      placeholderIcon: Icons.label_outline,
    );
    if (updated != null) {
      await PomodoroService.saveTags(updated);
      _mutateState(() {
        _allTags = updated;
        _tags = updated.where((t) => !t.isArchived).toList();
      });
    }
  }

  // 🚀 时间日志骨架屏
  Widget _buildSkeleton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark
        ? Colors.white10
        : Colors.black.withValues(alpha: 0.05);

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemExtent: 72.0,
      itemCount: 8,
      itemBuilder: (context, index) => Container(
        height: 60,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
