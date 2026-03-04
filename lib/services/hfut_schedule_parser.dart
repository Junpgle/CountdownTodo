import 'dart:convert';
import 'course_service.dart';

class HfutScheduleParser {
  /// 校验传入的 JSON 字符串是否符合聚在工大的课表格式
  static bool isValid(String jsonString) {
    try {
      final data = jsonDecode(jsonString);
      return data['result'] != null && data['result']['lessonList'] != null;
    } catch (e) {
      return false;
    }
  }

  /// 执行核心解析逻辑，将 JSON 映射为内部的 CourseItem 列表
  static List<CourseItem> parse(String jsonString) {
    try {
      final data = jsonDecode(jsonString);
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

      // 按日期和开始时间进行全局排序
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
}