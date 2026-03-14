import 'dart:io';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';

// 引入不同高校的解析器
import 'hfut_schedule_parser.dart';
import 'xmu_schedule_parser.dart';
import 'xidian_schedule_parser.dart'; // 🚀 1. 新增西电解析器引入
import 'zfsoft_schedule_parser.dart'; // 🚀 新增：引入正方教务系统解析器

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

  // 用于统一序列化存储
  Map<String, dynamic> toJson() {
    return {
      'courseName': courseName,
      'teacherName': teacherName,
      'date': date,
      'weekday': weekday,
      'startTime': startTime,
      'endTime': endTime,
      'weekIndex': weekIndex,
      'roomName': roomName,
      'lessonType': lessonType,
    };
  }

  // 用于从统一存储中反序列化
  factory CourseItem.fromJson(Map<String, dynamic> json) {
    return CourseItem(
      courseName: json['courseName'] ?? '未知课程',
      teacherName: json['teacherName'] ?? '未知教师',
      date: json['date'] ?? '',
      weekday: json['weekday'] ?? 1,
      startTime: json['startTime'] ?? 0,
      endTime: json['endTime'] ?? 0,
      weekIndex: json['weekIndex'] ?? 1,
      roomName: json['roomName'] ?? '未知地点',
      lessonType: json['lessonType'],
    );
  }
}

class CourseService {
  static const String _keyCourseData = 'course_schedule_json';

  // --- 内部辅助：统一将解析后的实体类集合保存到本地 ---
  static Future<void> saveCourses(List<CourseItem> courses) async {
    final prefs = await SharedPreferences.getInstance();
    // 统一转换为标准的 List<Map> JSON 字符串，极大地提升后续读取效率
    final String encodedData = jsonEncode(courses.map((c) => c.toJson()).toList());
    await prefs.setString(_keyCourseData, encodedData);
  }

  // ================= 导入与解析逻辑 =================

  // 1. 从字符串导入课表 (合工大)
  static Future<bool> importScheduleFromJson(String jsonString) async {
    // 调用提取的 parser 进行校验
    if (!HfutScheduleParser.isValid(jsonString)) {
      return false;
    }

    try {
      List<CourseItem> parsedCourses = HfutScheduleParser.parse(jsonString);
      if (parsedCourses.isEmpty) return false;

      // 保存标准格式
      await saveCourses(parsedCourses);
      return true;
    } catch (e) {
      print("解析工大课表出错: $e");
      return false;
    }
  }

  // 2. 导入厦大（正方教务系统）课表
  static Future<bool> importXmuScheduleFromHtml(String htmlString, DateTime semesterStart) async {
    try {
      List<CourseItem> parsedCourses = XmuScheduleParser.parseHtml(htmlString, semesterStart);
      if (parsedCourses.isEmpty) return false;

      // 保存标准格式
      await saveCourses(parsedCourses);
      return true;
    } catch (e) {
      print("解析厦大课表出错: $e");
      return false;
    }
  }

  // 🚀 3. 新增：导入西电 ics 课表
  static Future<bool> importXidianScheduleFromIcs(String icsString, DateTime semesterStart) async {
    try {
      List<CourseItem> parsedCourses = XidianScheduleParser.parseIcs(icsString, semesterStart);
      if (parsedCourses.isEmpty) return false;

      // 保存标准格式
      await saveCourses(parsedCourses);
      return true;
    } catch (e) {
      print("解析西电课表出错: $e");
      return false;
    }
  }

  // 4. 从文件路径导入课表 (供外部 App 唤起时调用，主要用于处理早期工大 JSON 文件)
  static Future<bool> importScheduleFromFile(String filePath) async {
    try {
      File file = File(filePath);
      String content = await file.readAsString();
      return await importScheduleFromJson(content);
    } catch (e) {
      return false;
    }
  }

  // 🚀 5. 新增：导入正方教务系统课表
  static Future<bool> importZfSoftScheduleFromHtml(
      String htmlString,
      DateTime semesterStart,
      {Map<int, Map<String, int>>? customTimes} // 🚀 适配：接收用户自定义的作息表
      ) async {
    try {
      // 调用解析器，并传入可能的自定义时间配置
      List<CourseItem> parsedCourses = ZfSoftScheduleParser.parseHtml(
        htmlString,
        semesterStart,
        customTimes: customTimes,
      );
      if (parsedCourses.isEmpty) return false;

      // 保存到本地存储
      await saveCourses(parsedCourses);
      return true;
    } catch (e) {
      print("解析正方教务课表出错: $e");
      return false;
    }
  }

  // ================= 提取与业务逻辑 =================

  // 4. 获取所有解析后的课程对象
  static Future<List<CourseItem>> getAllCourses() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_keyCourseData);
    if (data == null || data.isEmpty) return [];

    try {
      final decoded = jsonDecode(data);

      if (decoded is List) {
        // 🚀 核心修复：必须显式声明泛型 <CourseItem> 并在 fromJson 前对 Map 强转
        return decoded.map<CourseItem>((item) => CourseItem.fromJson(Map<String, dynamic>.from(item))).toList();
      } else {
        // 无缝兼容旧数据
        return HfutScheduleParser.parse(data);
      }
    } catch (e) {
      print("读取所有课表时发生崩溃: $e");
      try {
        return HfutScheduleParser.parse(data);
      } catch (e2) {
        return [];
      }
    }
  }

  // 5. 获取主页今日/明日需要显示的课程
  static Future<Map<String, dynamic>> getDashboardCourses() async {
    try {
      final courses = await getAllCourses();
      if (courses.isEmpty) return {'title': '暂无课表', 'courses': <CourseItem>[]};

      DateTime now = DateTime.now();
      String todayStr = DateFormat('yyyy-MM-dd').format(now);

      // 筛选今天的课程
      List<CourseItem> todayCourses = courses.where((c) => c.date == todayStr).toList();

      if (todayCourses.isNotEmpty) {
        todayCourses.sort((a, b) => a.startTime.compareTo(b.startTime));
        return {'title': '今日课程', 'courses': todayCourses};
      }

      // 今天的课没排，找明天的
      DateTime tomorrow = now.add(const Duration(days: 1));
      String tomorrowStr = DateFormat('yyyy-MM-dd').format(tomorrow);
      List<CourseItem> tomorrowCourses = courses.where((c) => c.date == tomorrowStr).toList();

      if (tomorrowCourses.isNotEmpty) {
        tomorrowCourses.sort((a, b) => a.startTime.compareTo(b.startTime));
        return {'title': '明日课程', 'courses': tomorrowCourses};
      }

      return {'title': '近期无课', 'courses': <CourseItem>[]};
    } catch (e) {
      print("获取主页课程时发生崩溃: $e");
      return {'title': '近期无课', 'courses': <CourseItem>[]};
    }
  }

  // 6. 按周获取课程
  static Future<List<CourseItem>> getCoursesByWeek(int weekIndex) async {
    final courses = await getAllCourses();
    return courses.where((c) => c.weekIndex == weekIndex).toList();
  }

  // 7. 获取包含课程的所有周数列表
  static Future<List<int>> getAvailableWeeks() async {
    final courses = await getAllCourses();
    final weeks = courses.map((c) => c.weekIndex).toSet().toList();
    weeks.sort();
    return weeks;
  }

  // ================= 云端同步逻辑 =================

  // 8. 上传本地课表到云端
  static Future<Map<String, dynamic>> syncCoursesToCloud(int userId) async {
    final courses = await getAllCourses();

    // 转换为后端需要的结构
    final courseMaps = courses.map((c) => {
      'course_name': c.courseName,
      'room_name': c.roomName,
      'teacher_name': c.teacherName,
      'start_time': c.startTime,
      'end_time': c.endTime,
      'weekday': c.weekday,
      'week_index': c.weekIndex,
      'lesson_type': c.lessonType ?? '',
      'date': c.date,
    }).toList();

    return await ApiService.uploadCourses(
      userId: userId,
      courses: courseMaps,
    );
  }
}