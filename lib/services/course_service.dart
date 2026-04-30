import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import 'package:CountDownTodo/services/database_helper.dart';
import '../services/api_service.dart';
import '../services/course_calendar_adjustment_service.dart';
import '../services/environment_service.dart';
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

  static Future<void> _ensureCoursesColumnsForWrite(dynamic db) async {
    final info = await db.rawQuery("PRAGMA table_info(courses)");
    final columns = info
        .map((row) => row['name']?.toString())
        .whereType<String>()
        .toSet();
    debugPrint("🔎 [Course] 写入前字段: ${columns.join(', ')}");

    final requiredColumns = {
      'is_deleted': 'INTEGER DEFAULT 0',
      'version': 'INTEGER DEFAULT 1',
      'updated_at': 'INTEGER DEFAULT 0',
      'created_at': 'INTEGER DEFAULT 0',
    };

    for (final entry in requiredColumns.entries) {
      if (!columns.contains(entry.key)) {
        await db.execute(
            "ALTER TABLE courses ADD COLUMN ${entry.key} ${entry.value}");
        columns.add(entry.key);
        debugPrint("✅ [Course] 已补齐字段 courses.${entry.key}");
      }
    }
  }

  static Future<void> _writeCoursesToSql(
      DatabaseHelper dbHelper, List<CourseItem> courses) async {
    final db = await dbHelper.database;
    await DatabaseHelper.ensureCourseTableSchema(db);
    await _ensureCoursesColumnsForWrite(db);
    final batch = db.batch();
    batch.delete('courses');
    for (var c in courses) {
      batch.insert('courses', {
        'uuid': c.uuid,
        'course_name': c.courseName,
        'teacher_name': c.teacherName,
        'date': c.date,
        'weekday': c.weekday,
        'start_time': c.startTime,
        'end_time': c.endTime,
        'week_index': c.weekIndex,
        'room_name': c.roomName,
        'lesson_type': c.lessonType,
        'team_uuid': c.teamUuid,
        'is_deleted': c.isDeleted ? 1 : 0,
        'version': c.version,
        'updated_at': c.updatedAt,
        'created_at': c.createdAt,
      });
    }
    await batch.commit(noResult: true);
  }

  // --- 内部辅助：统一将解析后的实体类集合保存到本地 ---
  static Future<void> saveCourses(String username, List<CourseItem> courses) async {
    // 1. 🚀 写入 SQL
    try {
      final dbHelper = DatabaseHelper.instance;
      await _writeCoursesToSql(dbHelper, courses);
      debugPrint("✅ [Course] SQL 保存成功: ${courses.length} 条");
    } catch (e) {
      debugPrint("❌ [Course] SQL 保存失败: $e");
      final errorText = e.toString();
      if (errorText.contains('no column named is_deleted') ||
          errorText.contains('no such column: is_deleted')) {
        try {
          await _writeCoursesToSql(DatabaseHelper.instance, courses);
          debugPrint("✅ [Course] SQL 兜底重试成功: ${courses.length} 条");
        } catch (retryError) {
          debugPrint("❌ [Course] SQL 兜底重试失败: $retryError");
        }
      }
    }

    // 2. SQL 已是主存储，清理旧 Prefs 备份，避免全量课程 JSON
    // 通过 shared_preferences MethodChannel 触发 Android OOM。
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("${_keyCourseData}_$username");
    await prefs.remove(_keyCourseData);
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
      await saveCourses(username, parsedCourses);
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
  static Future<List<CourseItem>> getAllCourses(
    String username, {
    bool applyCalendarAdjustments = true,
  }) async {
    Future<List<CourseItem>> applyAdjustmentsIfNeeded(
        List<CourseItem> courses) async {
      if (!applyCalendarAdjustments) return courses;
      return CourseCalendarAdjustmentService.applyToCourses(courses);
    }

    // 1. 优先从 SQL 读取
    try {
      final db = await DatabaseHelper.instance.database;
      final List<Map<String, dynamic>> maps = await db.query(
        'courses',
        where: 'IFNULL(is_deleted, 0) = 0',
        orderBy: 'date ASC, start_time ASC',
      );
      if (maps.isNotEmpty) {
        return applyAdjustmentsIfNeeded(
            maps.map((m) => CourseItem.fromJson(m)).toList());
      }
    } catch (e) {
      debugPrint("⚠️ Course SQL 读取异常: $e");
    }

    // 2. 🚀 核心迁移逻辑：如果 SQL 为空，从 Prefs 迁移
    final prefs = await SharedPreferences.getInstance();
    final legacyPrefsCourses = await _recoverCoursesFromPrefs(username, prefs);
    if (legacyPrefsCourses.isNotEmpty) {
      return applyAdjustmentsIfNeeded(legacyPrefsCourses);
    }

    final recoveredSqlCourses =
        await _recoverCoursesFromLegacySqlIfNeeded(username);
    if (recoveredSqlCourses.isNotEmpty) {
      return applyAdjustmentsIfNeeded(recoveredSqlCourses);
    }

    return [];
  }

  static Future<List<CourseItem>> _recoverCoursesFromPrefs(
      String username, SharedPreferences prefs) async {
    final scopedKey = "${_keyCourseData}_$username";
    final keys = <String>[
      scopedKey,
      _keyCourseData,
      ...prefs.getKeys().where((key) =>
          key.startsWith('${_keyCourseData}_') &&
          key != scopedKey &&
          !key.endsWith('_migrated_v2')),
    ];

    for (final key in keys.toSet()) {
      if (!prefs.containsKey(key)) continue;

      try {
        final raw = prefs.get(key);
        final courses = _parseLegacyCoursePrefsValue(raw);
        if (courses.isEmpty) continue;

        debugPrint(
            "🚀 [Course] 正在从 SharedPreferences($key) 迁移 ${courses.length} 条数据至 SQL...");
        await saveCourses(username, courses);
        await prefs.remove(key);
        await prefs.setBool("${_keyCourseData}_${username}_migrated_v2", true);
        return courses;
      } catch (e) {
        debugPrint("⚠️ [Course] 迁移 SharedPreferences($key) 失败: $e");
      }
    }

    return [];
  }

  static List<CourseItem> _parseLegacyCoursePrefsValue(Object? raw) {
    if (raw is String && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map<CourseItem>((item) =>
                CourseItem.fromJson(Map<String, dynamic>.from(item)))
            .toList();
      }
      return HfutScheduleParser.parse(raw);
    }

    if (raw is List<String> && raw.isNotEmpty) {
      final courses = <CourseItem>[];
      for (final item in raw) {
        if (item.trim().isEmpty) continue;
        final decoded = jsonDecode(item);
        if (decoded is List) {
          courses.addAll(decoded.map<CourseItem>((entry) =>
              CourseItem.fromJson(Map<String, dynamic>.from(entry))));
        } else if (decoded is Map) {
          courses.add(CourseItem.fromJson(Map<String, dynamic>.from(decoded)));
        }
      }
      return courses;
    }

    return [];
  }

  static Future<List<CourseItem>> _recoverCoursesFromLegacySqlIfNeeded(
      String username) async {
    if (kIsWeb || !(Platform.isWindows || Platform.isLinux)) return [];

    final envPrefix = EnvironmentService.isTest ? 'test_v5_' : 'v4_';
    final candidateNames = <String>{
      '${envPrefix}uni_sync_$username.db',
      'v4_uni_sync_$username.db',
      'uni_sync_$username.db',
      EnvironmentService.dbName,
      'v4_uni_sync.db',
    };

    final candidatePaths = <String>{
      for (final dbName in candidateNames)
        absolute(join('.dart_tool', 'sqflite_common_ffi', 'databases', dbName)),
      for (final dbName in candidateNames)
        absolute(join(
          'build',
          'windows',
          'x64',
          'runner',
          'Debug',
          '.dart_tool',
          'sqflite_common_ffi',
          'databases',
          dbName,
        )),
      for (final dbName in candidateNames)
        absolute(join(
          'build',
          'windows',
          'x64',
          'runner',
          'Release',
          '.dart_tool',
          'sqflite_common_ffi',
          'databases',
          dbName,
        )),
    };

    for (final legacyPath in candidatePaths) {
      final legacyFile = File(legacyPath);
      if (!await legacyFile.exists()) continue;

      Database? legacyDb;
      try {
        legacyDb = await openDatabase(legacyPath, readOnly: true);
        final tableRows = await legacyDb.query(
          'sqlite_master',
          columns: ['name'],
          where: 'type = ? AND name = ?',
          whereArgs: ['table', 'courses'],
          limit: 1,
        );
        if (tableRows.isEmpty) continue;

        final maps = await legacyDb.query(
          'courses',
          where: 'IFNULL(is_deleted, 0) = 0',
          orderBy: 'date ASC, start_time ASC',
        );
        if (maps.isEmpty) continue;

        final courses = maps.map((m) => CourseItem.fromJson(m)).toList();
        await saveCourses(username, courses);
        debugPrint(
            '✅ [Course] 已从旧 FFI 数据库恢复 ${courses.length} 条课表: $legacyPath');
        return courses;
      } catch (e) {
        debugPrint('⚠️ [Course] 旧 FFI 课表恢复失败 ($legacyPath): $e');
      } finally {
        await legacyDb?.close();
      }
    }

    return [];
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

      final futureCourses = <MapEntry<DateTime, CourseItem>>[];
      DateTime? semMonday;
      final DateTime? semStart = await StorageService.getSemesterStart();
      if (semStart != null) {
        semMonday = DateTime(semStart.year, semStart.month, semStart.day)
            .subtract(Duration(days: semStart.weekday - 1));
      }

      for (final c in courses) {
        DateTime? courseDay;
        if (c.date.isNotEmpty) {
          try {
            courseDay = DateFormat('yyyy-MM-dd').parseStrict(c.date);
          } catch (_) {
            courseDay = null;
          }
        }
        if (courseDay == null && semMonday != null && c.weekIndex > 0) {
          courseDay = semMonday.add(
            Duration(days: (c.weekIndex - 1) * 7 + c.weekday - 1),
          );
        }
        if (courseDay == null) continue;

        final normalizedDay =
            DateTime(courseDay.year, courseDay.month, courseDay.day);
        if (normalizedDay.isAfter(tomorrowNormalized)) {
          futureCourses.add(MapEntry(normalizedDay, c));
        }
      }

      if (futureCourses.isNotEmpty) {
        futureCourses.sort((a, b) {
          final dayCompare = a.key.compareTo(b.key);
          if (dayCompare != 0) return dayCompare;
          return a.value.startTime.compareTo(b.value.startTime);
        });
        final nextDay = futureCourses.first.key;
        final nextCourses = futureCourses
            .where((entry) => entry.key.isAtSameMomentAs(nextDay))
            .map((entry) => entry.value)
            .toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));
        final days = nextDay.difference(todayNormalized).inDays;
        return {'title': '${days}天后课程', 'courses': nextCourses};
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
    final courses =
        await getAllCourses(username, applyCalendarAdjustments: false);

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

  /// ?? Isolate רãα
  static List<CourseItem> _parseCourseItemsIsolate(List<Map<String, dynamic>> maps) {
    return maps.map((m) => CourseItem.fromJson(m)).toList();
  }
}
