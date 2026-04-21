import 'dart:io';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../storage_service.dart';

// 引入不同高校的解析器
import '../course_import/parsers/hfut_parser.dart';
import '../course_import/parsers/xmu_parser.dart';
import '../course_import/parsers/xidian_parser.dart'; 
import '../course_import/parsers/zfsoft_parser.dart'; 
import '../course_import/parsers/xujc_parser.dart'; 

import '../models.dart';

// CourseItem moved to models.dart

class CourseService {
  static const String _keyCourseData = 'course_schedule_json';

  // --- 内部辅助：统一将解析后的实体类集合保存到本地 ---
  static Future<void> saveCourses(String username, List<CourseItem> courses) async {
    final prefs = await SharedPreferences.getInstance();
    // 统一转换为标准的 List<Map> JSON 字符串，极大地提升后续读取效率
    final String encodedData = jsonEncode(courses.map((c) => c.toJson()).toList());
    await prefs.setString("${_keyCourseData}_$username", encodedData);
  }

  // ================= 导入与解析逻辑 =================

  // 1. 从字符串导入课表 (合工大)
  static Future<bool> importScheduleFromJson(String username, String jsonString, {DateTime? semesterStart}) async {
    // 调用提取的 parser 进行校验
    if (!HfutScheduleParser.isValid(jsonString)) {
      return false;
    }

    try {
      List<CourseItem> parsedCourses = HfutScheduleParser.parse(jsonString, semesterStart: semesterStart);
      if (parsedCourses.isEmpty) return false;

      // 保存标准格式
      await saveCourses(username!, parsedCourses);
      return true;
    } catch (e) {
      print("解析工大课表出错: $e");
      return false;
    }
  }

  // 2. 导入厦大（本部）课表
  static Future<bool> importXmuScheduleFromHtml(String username, String htmlString, DateTime semesterStart) async {
    try {
      List<CourseItem> parsedCourses = XmuScheduleParser.parseHtml(htmlString, semesterStart);
      if (parsedCourses.isEmpty) return false;

      // 保存标准格式
      await saveCourses(username, parsedCourses);
      return true;
    } catch (e) {
      print("解析厦大课表出错: $e");
      return false;
    }
  }

  // 🚀 2.1 导入厦大嘉庚学院课表
  static Future<bool> importXujcScheduleFromHtml(String username, String htmlString, DateTime semesterStart) async {
    try {
      List<CourseItem> parsedCourses = XujcScheduleParser.parseHtml(htmlString, semesterStart);
      if (parsedCourses.isEmpty) return false;

      // 保存标准格式
      await saveCourses(username, parsedCourses);
      return true;
    } catch (e) {
      print("解析嘉庚课表出错: $e");
      return false;
    }
  }

  // 🚀 3. 新增：导入西电 ics 课表
  static Future<bool> importXidianScheduleFromIcs(String username, String icsString, DateTime semesterStart) async {
    try {
      List<CourseItem> parsedCourses = XidianScheduleParser.parseIcs(icsString, semesterStart);
      if (parsedCourses.isEmpty) return false;

      // 保存标准格式
      await saveCourses(username, parsedCourses);
      return true;
    } catch (e) {
      print("解析西电课表出错: $e");
      return false;
    }
  }

  // 4. 从文件路径导入课表 (供外部 App 唤起时调用)
  static Future<bool> importScheduleFromFile(String username, String filePath) async {
    try {
      File file = File(filePath);
      String content = await file.readAsString();
      return await importScheduleFromJson(username, content);
    } catch (e) {
      return false;
    }
  }

  // 🚀 5. 新增：导入正方教务系统课表
  static Future<bool> importZfSoftScheduleFromHtml(
      String username,
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
      await saveCourses(username, parsedCourses);
      return true;
    } catch (e) {
      print("解析正方教务课表出错: $e");
      return false;
    }
  }

  // ================= 提取与业务逻辑 =================

  // 4. 获取所有解析后的课程对象
  static Future<List<CourseItem>> getAllCourses(String username) async {
    final prefs = await SharedPreferences.getInstance();
    String? data = prefs.getString("${_keyCourseData}_$username");

    // 🚀 核心修复：无缝向上兼容（仅执行一次迁移，防止多账号共用该全局数据）
    if ((data == null || data.isEmpty) && username.isNotEmpty) {
      final String legacyKey = _keyCourseData;
      final String markerKey = "${legacyKey}_${username}_migrated";
      
      if (!(prefs.getBool(markerKey) ?? false)) {
        final String? legacyData = prefs.getString(legacyKey);
        if (legacyData != null && legacyData.isNotEmpty) {
          print("🚚 [Isolation] Migrating legacy course data to user scoped key: $username");
          await prefs.setString("${_keyCourseData}_$username", legacyData);
          data = legacyData;
          // 标记已迁移，防止下一个切换进来的账号再次非法“继承”这批数据
          await prefs.setBool(markerKey, true);
        }
      }
    }

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
  static Future<Map<String, dynamic>> getDashboardCourses(String username) async {
    try {
      final courses = await getAllCourses(username);
      if (courses.isEmpty) return {'title': '暂无课表', 'courses': <CourseItem>[]};

      DateTime now = DateTime.now();
      DateTime todayNormalized = DateTime(now.year, now.month, now.day);
      String todayStr = DateFormat('yyyy-MM-dd').format(now);
      int currentHHMM = now.hour * 100 + now.minute;

      // 1. 尝试按日期精确筛选今天的课程
      List<CourseItem> todayCourses = courses.where((c) => c.date == todayStr).toList();

      // 🚀 核心改进：如果没有按日期找到，尝试按“当前周次+星期”回退计算（支持动态修改开学日期的情况）
      if (todayCourses.isEmpty) {
        final DateTime? semStart = await StorageService.getSemesterStart();
        if (semStart != null) {
          final DateTime semMonday = DateTime(semStart.year, semStart.month, semStart.day)
              .subtract(Duration(days: semStart.weekday - 1));
          int todayWeek = todayNormalized.difference(semMonday).inDays ~/ 7 + 1;
          int todayWeekday = todayNormalized.weekday;
          todayCourses = courses.where((c) => c.weekIndex == todayWeek && c.weekday == todayWeekday).toList();
        }
      }

      // 如果今天有课，且“还没全部上完”，则展示今天的课程
      if (todayCourses.isNotEmpty) {
        todayCourses.sort((a, b) => a.startTime.compareTo(b.startTime));
        bool allFinished = todayCourses.every((c) => c.endTime <= currentHHMM);
        if (!allFinished) {
          return {'title': '今日课程', 'courses': todayCourses};
        }
      }

      // 2. 今天的课没排，或者“今天的课都上完了”，找明天的
      DateTime tomorrow = now.add(const Duration(days: 1));
      DateTime tomorrowNormalized = DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
      String tomorrowStr = DateFormat('yyyy-MM-dd').format(tomorrow);
      List<CourseItem> tomorrowCourses = courses.where((c) => c.date == tomorrowStr).toList();

      // 🚀 明天也同样支持回退计算
      if (tomorrowCourses.isEmpty) {
        final DateTime? semStart = await StorageService.getSemesterStart();
        if (semStart != null) {
          final DateTime semMonday = DateTime(semStart.year, semStart.month, semStart.day)
              .subtract(Duration(days: semStart.weekday - 1));
          int tomorrowWeek = tomorrowNormalized.difference(semMonday).inDays ~/ 7 + 1;
          int tomorrowWeekday = tomorrowNormalized.weekday;
          tomorrowCourses = courses.where((c) => c.weekIndex == tomorrowWeek && c.weekday == tomorrowWeekday).toList();
        }
      }

      if (tomorrowCourses.isNotEmpty) {
        tomorrowCourses.sort((a, b) => a.startTime.compareTo(b.startTime));
        return {'title': '明日课程', 'courses': tomorrowCourses};
      }

      return {'title': '最近无课', 'courses': <CourseItem>[]};
    } catch (e) {
      print("获取主页课程时发生崩溃: $e");
      return {'title': '最近无课', 'courses': <CourseItem>[]};
    }
  }

  // 6. 按周获取课程
  static Future<List<CourseItem>> getCoursesByWeek(String username, int weekIndex) async {
    final courses = await getAllCourses(username);
    return courses.where((c) => c.weekIndex == weekIndex).toList();
  }

  // 7. 获取包含课程的所有周数列表
  static Future<List<int>> getAvailableWeeks(String username) async {
    final courses = await getAllCourses(username);
    final weeks = courses.map((c) => c.weekIndex).toSet().toList();
    weeks.sort();
    return weeks;
  }

  // ================= 云端同步逻辑 =================

  // 8. 上传本地课表到云端
  static Future<Map<String, dynamic>> syncCoursesToCloud(String username, int userId) async {
    final courses = await getAllCourses(username);

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