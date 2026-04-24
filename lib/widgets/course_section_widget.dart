import 'package:flutter/material.dart';
import '../models.dart';
import 'home_sections.dart';

import '../screens/course_screens.dart';
import '../utils/page_transitions.dart';
import 'version_history_sheet.dart';

// ─────────────────────────────────────────────
// HHMM 整数 → 时间字符串  例: 800→"8:00"  950→"9:50"
// ─────────────────────────────────────────────
String _periodToTime(int hhmm) {
  final int h = hhmm ~/ 100;
  final int m = hhmm % 100;
  return '$h:${m.toString().padLeft(2, '0')}';
}

const List<String> _weekdayNames = [
  '',
  '周一',
  '周二',
  '周三',
  '周四',
  '周五',
  '周六',
  '周日'
];

String _weekdayLabel(int weekday) =>
    (weekday >= 1 && weekday <= 7) ? _weekdayNames[weekday] : '';

String _lessonTypeLabel(String? type) {
  if (type == 'EXPERIMENT') return '实验';
  if (type == 'THEORY') return '理论';
  return type?.trim() ?? '';
}

// ─────────────────────────────────────────────
// 主组件
// ─────────────────────────────────────────────
class CourseSectionWidget extends StatelessWidget {
  final Map<String, dynamic> dashboardCourseData;
  final bool isLight;

  const CourseSectionWidget({
    super.key,
    required this.dashboardCourseData,
    required this.isLight,
  });

  void _showCourseDetail(
      BuildContext context, CourseItem course, GlobalKey cardKey) {
    final renderBox = cardKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      _showCourseDetailFallback(context, course);
      return;
    }
    final rect = renderBox.localToGlobal(Offset.zero) & renderBox.size;
    final color = Theme.of(context).colorScheme.surface;

    Navigator.push(
      context,
      ContainerTransformRoute(
        page: _CourseDetailPage(course: course),
        sourceRect: rect,
        sourceColor: color,
        sourceBorderRadius: const BorderRadius.all(Radius.circular(14)),
      ),
    );
  }

  void _showCourseDetailFallback(BuildContext context, CourseItem course) {
    final String typeLabel = _lessonTypeLabel(course.lessonType);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(children: [
                  Container(
                      width: 4,
                      height: 44,
                      decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Row(children: [
                          Expanded(
                              child: Text(course.courseName,
                                  style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSurface,
                                      height: 1.2))),
                          if (typeLabel.isNotEmpty)
                            Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                    color: colorScheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(8)),
                                child: Text(typeLabel,
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color:
                                            colorScheme.onSecondaryContainer))),
                        ]),
                        const SizedBox(height: 4),
                        Text(
                            '${_periodToTime(course.startTime)} – ${_periodToTime(course.endTime)}',
                            style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w600)),
                      ])),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(children: [
                  _DetailRow(
                      icon: Icons.location_on_outlined,
                      label: "教室",
                      value: course.roomName,
                      colorScheme: colorScheme),
                  _DetailRow(
                      icon: Icons.person_outline_rounded,
                      label: "教师",
                      value: course.teacherName,
                      colorScheme: colorScheme),
                  _DetailRow(
                      icon: Icons.calendar_today_outlined,
                      label: "日期",
                      value: '${course.date}  ${_weekdayLabel(course.weekday)}',
                      colorScheme: colorScheme),
                  _DetailRow(
                      icon: Icons.view_week_outlined,
                      label: "周次",
                      value: '第 ${course.weekIndex} 周',
                      colorScheme: colorScheme),
                ]),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                    16, 4, 16, MediaQuery.of(ctx).padding.bottom + 16),
                child: Row(children: [
                  Expanded(
                      child: FilledButton.tonal(
                          style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              minimumSize: const Size.fromHeight(44)),
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text("关闭"))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: FilledButton(
                          style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              minimumSize: const Size.fromHeight(44)),
                          onPressed: () {
                            Navigator.pop(ctx);
                            Navigator.push(
                                context,
                                PageTransitions.slideHorizontal(
                                    CourseDetailScreen(course: course)));
                          },
                          child: const Text("查看详情"))),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    List<CourseItem> courses = [];
    try {
      if (dashboardCourseData['courses'] != null &&
          dashboardCourseData['courses'] is List) {
        for (var item in dashboardCourseData['courses']) {
          if (item is CourseItem) courses.add(item);
        }
      }
    } catch (e) {
      debugPrint('解析主页课程数据失败: $e');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: dashboardCourseData['title']?.toString() ?? '课程提醒',
          icon: Icons.class_outlined,
          isLight: isLight,
        ),
        if (courses.isEmpty)
          EmptyState(
              text: dashboardCourseData['title'] == '暂无课表'
                  ? "尚未导入课表，点击上方图标开始"
                  : "近期暂无课程（今天与明天）",
              isLight: isLight)
        else
          ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: courses.length,
            itemBuilder: (context, index) {
              final course = courses[index];
              return _CourseCompactCard(
                course: course,
                isLight: isLight,
                onTap: (cardKey) => _showCourseDetail(context, course, cardKey),
              );
            },
          ),
      ],
    );
  }
}

class _CourseDetailPage extends StatefulWidget {
  final CourseItem course;
  const _CourseDetailPage({required this.course});
  @override
  State<_CourseDetailPage> createState() => _CourseDetailPageState();
}

class _CourseDetailPageState extends State<_CourseDetailPage> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final String typeLabel = _lessonTypeLabel(widget.course.lessonType);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.course.courseName),
        centerTitle: true,
        actions: [
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                PageTransitions.slideHorizontal(
                    CourseDetailScreen(course: widget.course)),
              );
            },
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('详情'),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withOpacity(0.45),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text(widget.course.courseName,
                                  style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSurface,
                                      height: 1.2))),
                          if (typeLabel.isNotEmpty)
                            Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                    color: colorScheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(8)),
                                child: Text(typeLabel,
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color:
                                            colorScheme.onSecondaryContainer))),
                        ]),
                        const SizedBox(height: 4),
                        Text(
                            '${_periodToTime(widget.course.startTime)} – ${_periodToTime(widget.course.endTime)}',
                            style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w600)),
                      ]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _DetailRow(
              icon: Icons.location_on_outlined,
              label: "教室",
              value: widget.course.roomName,
              colorScheme: colorScheme),
          _DetailRow(
              icon: Icons.person_outline_rounded,
              label: "教师",
              value: widget.course.teacherName,
              colorScheme: colorScheme),
          _DetailRow(
              icon: Icons.calendar_today_outlined,
              label: "日期",
              value:
                  '${widget.course.date}  ${_weekdayLabel(widget.course.weekday)}',
              colorScheme: colorScheme),
          _DetailRow(
              icon: Icons.view_week_outlined,
              label: "周次",
              value: '第 ${widget.course.weekIndex} 周',
              colorScheme: colorScheme),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 紧凑卡片（与待办风格对齐）
// ─────────────────────────────────────────────
class _CourseCompactCard extends StatefulWidget {
  final CourseItem course;
  final bool isLight;
  final Function(GlobalKey cardKey) onTap;

  const _CourseCompactCard({
    required this.course,
    required this.isLight,
    required this.onTap,
  });

  @override
  State<_CourseCompactCard> createState() => _CourseCompactCardState();
}

class _CourseCompactCardState extends State<_CourseCompactCard> {
  late final GlobalKey _cardKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final String typeLabel = _lessonTypeLabel(widget.course.lessonType);

    return Container(
      key: _cardKey,
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: colorScheme.surface.withOpacity(widget.isLight ? 0.97 : 0.75),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outline.withOpacity(widget.isLight ? 0.06 : 0.12),
          width: 1,
        ),
        boxShadow: widget.isLight
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                )
              ]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => widget.onTap(_cardKey),
          onLongPress: () => VersionHistorySheet.show(context, widget.course.uuid, 'courses', widget.course.courseName),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                // 左侧竖条
                Container(
                  width: 3,
                  height: 36,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // 时间列
                SizedBox(
                  width: 50,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _periodToTime(widget.course.startTime),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                          height: 1.2,
                        ),
                      ),
                      Text(
                        _periodToTime(widget.course.endTime),
                        style: TextStyle(
                          fontSize: 10.5,
                          color: colorScheme.primary.withOpacity(0.55),
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // 课程名 + 地点教师
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.course.courseName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                                height: 1.2,
                              ),
                            ),
                          ),
                          if (typeLabel.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: colorScheme.secondaryContainer
                                    .withOpacity(0.8),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                typeLabel,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.location_on_rounded,
                              size: 11,
                              color: colorScheme.onSurface.withOpacity(0.4)),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              '${widget.course.roomName}  ·  ${widget.course.teacherName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurface.withOpacity(0.45),
                                height: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded,
                    size: 16, color: colorScheme.onSurface.withOpacity(0.25)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 详情行
// ─────────────────────────────────────────────
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ColorScheme colorScheme;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: colorScheme.onSurface.withOpacity(0.45)),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurface.withOpacity(0.5),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface.withOpacity(0.85),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
