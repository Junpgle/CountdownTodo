import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/course_service.dart';

// --- 二级界面：按周查看课表 (网格视图) ---
class WeeklyCourseScreen extends StatefulWidget {
  const WeeklyCourseScreen({Key? key}) : super(key: key);

  @override
  State<WeeklyCourseScreen> createState() => _WeeklyCourseScreenState();
}

class _WeeklyCourseScreenState extends State<WeeklyCourseScreen> {
  int _currentWeek = 1;
  List<int> _availableWeeks = [];
  List<CourseItem> _weekCourses = [];
  bool _isLoading = true;
  DateTime? _semesterMonday;

  // 网格尺寸常量设置
  final double timeColumnWidth = 45.0; // 左侧时间栏宽度
  final double cellHeight = 65.0;      // 每个节次的高度
  final double breakHeight = 24.0;     // 午休/晚休分割线高度

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final weeks = await CourseService.getAvailableWeeks();
    if (weeks.isNotEmpty) {
      _availableWeeks = weeks;

      // 解析出学期的第一周星期一的日期，用于计算任何一周的日历日期
      final allCourses = await CourseService.getAllCourses();
      if (allCourses.isNotEmpty) {
        allCourses.sort((a, b) => a.weekIndex.compareTo(b.weekIndex));
        final firstCourse = allCourses.first;
        DateTime firstCourseDate = DateFormat('yyyy-MM-dd').parse(firstCourse.date);
        DateTime firstMonday = firstCourseDate.subtract(Duration(days: firstCourse.weekday - 1));
        _semesterMonday = firstMonday.subtract(Duration(days: (firstCourse.weekIndex - 1) * 7));

        // 自动定位到当前自然周
        DateTime now = DateTime.now();
        int daysDiff = now.difference(_semesterMonday!).inDays;
        int currentRealWeek = (daysDiff ~/ 7) + 1;
        if (_availableWeeks.contains(currentRealWeek)) {
          _currentWeek = currentRealWeek;
        } else {
          _currentWeek = _availableWeeks.first;
        }
      }

      _weekCourses = await CourseService.getCoursesByWeek(_currentWeek);
    }
    setState(() => _isLoading = false);
  }

  void _changeWeek(int delta) {
    int newWeek = _currentWeek + delta;
    if (_availableWeeks.contains(newWeek)) {
      setState(() {
        _currentWeek = newWeek;
        _isLoading = true;
      });
      CourseService.getCoursesByWeek(_currentWeek).then((courses) {
        setState(() {
          _weekCourses = courses;
          _isLoading = false;
        });
      });
    }
  }

  // 获取当前周的周一日期
  DateTime? _getMondayOfCurrentWeek() {
    if (_semesterMonday != null) {
      return _semesterMonday!.add(Duration(days: (_currentWeek - 1) * 7));
    }
    return null;
  }

  // 节次到时间的文本映射
  String _getPeriodTime(int period) {
    switch (period) {
      case 1: return '08:00\n08:50';
      case 2: return '09:00\n09:50';
      case 3: return '10:10\n11:00';
      case 4: return '11:10\n12:00';
      case 5: return '14:00\n14:50';
      case 6: return '15:00\n15:50';
      case 7: return '16:00\n16:50';
      case 8: return '17:00\n17:50';
      case 9: return '19:00\n19:50';
      case 10: return '20:00\n20:50';
      case 11: return '21:00\n21:50';
      default: return '';
    }
  }

  // 根据课程的开始时间计算所在的起始节次
  int getStartPeriod(int startTime) {
    if (startTime <= 800) return 1;
    if (startTime <= 900) return 2;
    if (startTime <= 1010) return 3;
    if (startTime <= 1110) return 4;
    if (startTime <= 1400) return 5;
    if (startTime <= 1500) return 6;
    if (startTime <= 1600) return 7;
    if (startTime <= 1700) return 8;
    if (startTime <= 1900) return 9;
    if (startTime <= 2000) return 10;
    return 11;
  }

  // 根据课程的结束时间计算所在的结束节次
  int getEndPeriod(int endTime) {
    if (endTime <= 850) return 1;
    if (endTime <= 950) return 2;
    if (endTime <= 1100) return 3;
    if (endTime <= 1200) return 4;
    if (endTime <= 1450) return 5;
    if (endTime <= 1550) return 6;
    if (endTime <= 1650) return 7;
    if (endTime <= 1750) return 8;
    if (endTime <= 1950) return 9;
    if (endTime <= 2050) return 10;
    return 11;
  }

  // 计算某个节次在 Y 轴上的顶部偏移量 (考虑到午休和晚休的高度)
  double getTopOffset(int p) {
    if (p <= 4) {
      return (p - 1) * cellHeight;
    } else if (p <= 8) {
      return 4 * cellHeight + breakHeight + (p - 5) * cellHeight;
    } else {
      return 8 * cellHeight + 2 * breakHeight + (p - 9) * cellHeight;
    }
  }

  // 计算某个节次在 Y 轴上的底部偏移量
  double getBottomOffset(int p) {
    return getTopOffset(p) + cellHeight;
  }

  // 根据课程名称生成固定的卡片颜色
  Color _getCourseColor(String courseName) {
    final List<Color> colors = [
      Colors.blueAccent.shade200,
      Colors.orangeAccent.shade200,
      Colors.purpleAccent.shade200,
      Colors.teal.shade300,
      Colors.pinkAccent.shade200,
      Colors.indigoAccent.shade200,
      Colors.green.shade400,
      Colors.deepOrange.shade300,
    ];
    int hash = courseName.hashCode;
    return colors[hash % colors.length];
  }

  // 构建顶部的日期星期标头
  Widget _buildHeader(DateTime? monday) {
    DateTime now = DateTime.now();
    String todayStr = DateFormat('yyyy-MM-dd').format(now);
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: EdgeInsets.only(left: timeColumnWidth, top: 8, bottom: 8),
      child: Row(
        children: List.generate(7, (index) {
          DateTime? currentDate;
          String dateStr = '';
          bool isToday = false;

          if (monday != null) {
            currentDate = monday.add(Duration(days: index));
            dateStr = DateFormat('M/dd').format(currentDate);
            isToday = DateFormat('yyyy-MM-dd').format(currentDate) == todayStr;
          }

          List<String> weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

          return Expanded(
            child: Column(
              children: [
                Text(
                  weekdays[index],
                  style: TextStyle(
                    color: isToday ? Colors.blue : (isDark ? Colors.white70 : Colors.black87),
                    fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                if (dateStr.isNotEmpty)
                  Text(
                    dateStr,
                    style: TextStyle(
                      color: isToday ? Colors.blue : Colors.grey,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // 构建课表网格和课程块
  Widget _buildGrid(double cellWidth) {
    List<Widget> children = [];
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color lineColor = isDark ? Colors.white10 : Colors.black12;
    Color breakColor = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03);
    Color textColor = isDark ? Colors.white70 : Colors.black87;

    double currentY = 0;

    // 1. 绘制水平的网格线、左侧时间列以及休息分割带
    for (int i = 1; i <= 11; i++) {
      // 水平网格线
      children.add(
          Positioned(
            top: currentY,
            left: 0,
            right: 0,
            height: cellHeight,
            child: Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: lineColor, width: 0.5)),
              ),
            ),
          )
      );

      // 左侧时间文字
      children.add(
          Positioned(
            top: currentY,
            left: 0,
            width: timeColumnWidth,
            height: cellHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$i', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textColor)),
                const SizedBox(height: 2),
                Text(_getPeriodTime(i), style: const TextStyle(fontSize: 9, color: Colors.grey), textAlign: TextAlign.center),
              ],
            ),
          )
      );

      currentY += cellHeight;

      if (i == 4) {
        // 午休区块
        children.add(
            Positioned(
              top: currentY,
              left: 0,
              right: 0,
              height: breakHeight,
              child: Container(
                color: breakColor,
                alignment: Alignment.center,
                child: const Text('午休', style: TextStyle(fontSize: 11, color: Colors.grey)),
              ),
            )
        );
        currentY += breakHeight;
      } else if (i == 8) {
        // 晚休区块
        children.add(
            Positioned(
              top: currentY,
              left: 0,
              right: 0,
              height: breakHeight,
              child: Container(
                color: breakColor,
                alignment: Alignment.center,
                child: const Text('晚休', style: TextStyle(fontSize: 11, color: Colors.grey)),
              ),
            )
        );
        currentY += breakHeight;
      }
    }

    // 2. 绘制垂直网格线
    for (int i = 0; i <= 7; i++) {
      children.add(
          Positioned(
            top: 0,
            bottom: 0,
            left: timeColumnWidth + i * cellWidth,
            width: 0.5,
            child: Container(color: lineColor),
          )
      );
    }

    // 3. 将课程块覆盖到网格上
    for (var course in _weekCourses) {
      int startPeriod = getStartPeriod(course.startTime);
      int endPeriod = getEndPeriod(course.endTime);

      double top = getTopOffset(startPeriod);
      double height = getBottomOffset(endPeriod) - top;
      double left = timeColumnWidth + (course.weekday - 1) * cellWidth;

      Color bgColor = _getCourseColor(course.courseName);

      children.add(
          Positioned(
            top: top + 1,
            left: left + 1,
            width: cellWidth - 2,
            height: height - 2,
            child: GestureDetector(
              onTap: () {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => CourseDetailScreen(course: course),
                ));
              },
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: bgColor.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      course.courseName,
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, height: 1.2),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Text(
                      '@${course.roomName}',
                      style: const TextStyle(color: Colors.white, fontSize: 9, height: 1.1),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          )
      );
    }

    return Stack(
      children: children,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios, size: 16),
              onPressed: _availableWeeks.contains(_currentWeek - 1) ? () => _changeWeek(-1) : null,
            ),
            const SizedBox(width: 8),
            Text('第 $_currentWeek 周', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.arrow_forward_ios, size: 16),
              onPressed: _availableWeeks.contains(_currentWeek + 1) ? () => _changeWeek(1) : null,
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          _buildHeader(_getMondayOfCurrentWeek()),
          Divider(height: 1, thickness: 0.5, color: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.black12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                double cellWidth = (constraints.maxWidth - timeColumnWidth) / 7;
                return SingleChildScrollView(
                  child: SizedBox(
                    // 计算总高度以保证可以垂直滚动：11节课 + 2次休息区
                    height: 11 * cellHeight + 2 * breakHeight,
                    child: _buildGrid(cellWidth),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// --- 三级界面：课程详情保持原状 ---
class CourseDetailScreen extends StatelessWidget {
  final CourseItem course;
  const CourseDetailScreen({Key? key, required this.course}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('课程详情')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.class_, size: 80, color: Colors.blueAccent),
          const SizedBox(height: 16),
          Text(course.courseName, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 32),
          _buildDetailRow(Icons.person, '授课教师', course.teacherName),
          const Divider(),
          _buildDetailRow(Icons.location_on, '上课地点', course.roomName),
          const Divider(),
          _buildDetailRow(Icons.calendar_today, '日期', '${course.date} (第${course.weekIndex}周 周${course.weekday})'),
          const Divider(),
          _buildDetailRow(Icons.access_time, '时间', '${course.formattedStartTime} - ${course.formattedEndTime}'),
          if (course.lessonType != null) ...[
            const Divider(),
            _buildDetailRow(Icons.category, '课程类型', course.lessonType == 'EXPERIMENT' ? '实验课' : '理论/实践'),
          ]
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey),
          const SizedBox(width: 16),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 16)),
          const Spacer(),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}