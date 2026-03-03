import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class CourseItem {
  final String courseName;
  final String teacherName;
  final String date; // yyyy-MM-dd
  final int weekday;
  final int startTime;
  final int endTime;
  final int weekIndex;
  final String roomName;
  final String? lessonType;

  CourseItem({
    required this.courseName,
    required this.teacherName,
    required this.date,
    required this.weekday,
    required this.startTime,
    required this.endTime,
    required this.weekIndex,
    required this.roomName,
    this.lessonType,
  });

  // 格式化时间，如 800 -> 08:00
  String get formattedStartTime => '${(startTime ~/ 100).toString().padLeft(2, '0')}:${(startTime % 100).toString().padLeft(2, '0')}';
  String get formattedEndTime => '${(endTime ~/ 100).toString().padLeft(2, '0')}:${(endTime % 100).toString().padLeft(2, '0')}';
}

class CourseService {
  static const String _keyCourseData = 'course_schedule_json';

  // 导入并保存JSON
  static Future<bool> importScheduleFromJson(String jsonString) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyCourseData, jsonString);
      return true;
    } catch (e) {
      return false;
    }
  }

  // 获取所有解析后的课程
  static Future<List<CourseItem>> getAllCourses() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyCourseData);
    if (jsonStr == null || jsonStr.isEmpty) return [];

    try {
      final data = jsonDecode(jsonStr);
      final result = data['result'];
      if (result == null) return [];

      final lessonList = result['lessonList'] as List;
      final scheduleList = result['scheduleList'] as List;

      // 建立 lessonId 到 lesson 详情的映射，方便快速查找课程名
      Map<int, dynamic> lessonMap = {
        for (var item in lessonList) item['id']: item
      };

      List<CourseItem> courses = [];
      for (var schedule in scheduleList) {
        final lessonId = schedule['lessonId'];
        final lessonInfo = lessonMap[lessonId];

        if (lessonInfo != null) {
          courses.add(CourseItem(
            courseName: lessonInfo['courseName']?.toString().trim() ?? '未知课程',
            teacherName: schedule['personName'] ?? '未知教师',
            date: schedule['date'],
            weekday: schedule['weekday'],
            startTime: schedule['startTime'],
            endTime: schedule['endTime'],
            weekIndex: schedule['weekIndex'],
            roomName: schedule['room']['nameZh'] ?? '未知教室',
            lessonType: schedule['lessonType'],
          ));
        }
      }

      // 按日期和开始时间排序
      courses.sort((a, b) {
        int dateCmp = a.date.compareTo(b.date);
        if (dateCmp != 0) return dateCmp;
        return a.startTime.compareTo(b.startTime);
      });

      return courses;
    } catch (e) {
      return [];
    }
  }

  // 获取主页显示的课程（今天或明天）
  static Future<Map<String, dynamic>> getDashboardCourses() async {
    final courses = await getAllCourses();
    if (courses.isEmpty) return {'title': '暂无课表', 'courses': <CourseItem>[]};

    DateTime now = DateTime.now();
    String todayStr = DateFormat('yyyy-MM-dd').format(now);

    // 筛选今天的课程
    List<CourseItem> todayCourses = courses.where((c) => c.date == todayStr).toList();

    if (todayCourses.isNotEmpty) {
      // 检查今天课程是否已全部结束
      int currentTotalMinutes = now.hour * 60 + now.minute;
      bool allFinished = true;
      for (var c in todayCourses) {
        int endMinutes = (c.endTime ~/ 100) * 60 + (c.endTime % 100);
        if (currentTotalMinutes <= endMinutes) {
          allFinished = false;
          break;
        }
      }

      if (!allFinished) {
        return {'title': '今日课程', 'courses': todayCourses};
      }
    }

    // 今天的课没排或者已经上完了，找明天的
    DateTime tomorrow = now.add(const Duration(days: 1));
    String tomorrowStr = DateFormat('yyyy-MM-dd').format(tomorrow);
    List<CourseItem> tomorrowCourses = courses.where((c) => c.date == tomorrowStr).toList();

    if (tomorrowCourses.isNotEmpty) {
      return {'title': '明日课程', 'courses': tomorrowCourses};
    }

    return {'title': '近期无课', 'courses': <CourseItem>[]};
  }

  // 获取指定周的课程
  static Future<List<CourseItem>> getCoursesByWeek(int weekIndex) async {
    final courses = await getAllCourses();
    return courses.where((c) => c.weekIndex == weekIndex).toList();
  }

  // 获取所有周数（用于二级界面切换）
  static Future<List<int>> getAvailableWeeks() async {
    final courses = await getAllCourses();
    final weeks = courses.map((c) => c.weekIndex).toSet().toList();
    weeks.sort();
    return weeks;
  }
}