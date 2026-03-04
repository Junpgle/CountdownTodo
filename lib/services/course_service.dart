import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

// 引入刚才提取出来的解析器
import 'hfut_schedule_parser.dart';

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

  // 1. 从字符串导入课表 (基础逻辑)
  static Future<bool> importScheduleFromJson(String jsonString) async {
    // 调用提取的 parser 进行校验
    if (!HfutScheduleParser.isValid(jsonString)) {
      return false;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyCourseData, jsonString);
      return true;
    } catch (e) {
      return false;
    }
  }

  // 2. 从文件路径导入课表 (供外部 App 唤起时调用)
  static Future<bool> importScheduleFromFile(String filePath) async {
    try {
      File file = File(filePath);
      String jsonString = await file.readAsString();
      return await importScheduleFromJson(jsonString);
    } catch (e) {
      return false;
    }
  }

  // 3. 获取所有解析后的课程对象
  static Future<List<CourseItem>> getAllCourses() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyCourseData);
    if (jsonStr == null || jsonStr.isEmpty) return [];

    // 直接委托给 Parser 进行解析，业务层不再堆积 JSON 提取逻辑
    return HfutScheduleParser.parse(jsonStr);
  }

  // 4. 获取主页今日/明日需要显示的课程
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

  // 5. 按周获取课程
  static Future<List<CourseItem>> getCoursesByWeek(int weekIndex) async {
    final courses = await getAllCourses();
    return courses.where((c) => c.weekIndex == weekIndex).toList();
  }

  // 6. 获取包含课程的所有周数列表
  static Future<List<int>> getAvailableWeeks() async {
    final courses = await getAllCourses();
    final weeks = courses.map((c) => c.weekIndex).toSet().toList();
    weeks.sort();
    return weeks;
  }
}