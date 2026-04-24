import 'package:intl/intl.dart';
import '../../models.dart';

class XidianScheduleParser {
  /// 传入 ICS 字符串和 本学期第一周的周一日期
  static List<CourseItem> parseIcs(String icsString, DateTime semesterStartDate) {
    List<CourseItem> courses = [];

    // ICS 文件按行分割，处理一下可能的 \r\n
    List<String> lines = icsString.replaceAll('\r', '').split('\n');

    String? summary;
    String? location;
    DateTime? dtStart;
    DateTime? dtEnd;

    // 将开学日期统一归零时分秒，以确保计算周差准确
    DateTime semStart = DateTime(semesterStartDate.year, semesterStartDate.month, semesterStartDate.day);

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      if (line == 'BEGIN:VEVENT') {
        // 新的日程开始，重置属性
        summary = null;
        location = null;
        dtStart = null;
        dtEnd = null;
      } else if (line.startsWith('SUMMARY:')) {
        summary = line.substring(8);
      } else if (line.startsWith('LOCATION:')) {
        location = line.substring(9);
      } else if (line.startsWith('DTSTART:')) {
        dtStart = _parseIcsDateTime(line.substring(8));
      } else if (line.startsWith('DTEND:')) {
        dtEnd = _parseIcsDateTime(line.substring(6));
      } else if (line == 'END:VEVENT') {
        // 日程块结束，组装 CourseItem
        if (summary != null && dtStart != null && dtEnd != null) {

          // 1. 提取课程名 (ICS中通常是 "课程名 @ 地点")
          String courseName = summary.split('@').first.trim();

          // 2. 提取地点
          String roomName = location ?? '';
          if (roomName.isEmpty || roomName.toLowerCase() == 'null') {
            // 如果 LOCATION 为空，尝试从 SUMMARY 提取
            if (summary.contains('@')) {
              roomName = summary.split('@').last.trim();
            } else {
              roomName = '未知地点';
            }
          }
          if (roomName.toLowerCase() == 'null') roomName = '未知地点';

          // 3. 将 UTC 时间转为设备本地时间 (北京时间)
          DateTime localStart = dtStart.toLocal();
          DateTime localEnd = dtEnd.toLocal();

          String dateStr = DateFormat('yyyy-MM-dd').format(localStart);
          int weekday = localStart.weekday;

          // 转换为 830 / 1005 这种格式
          int startTime = localStart.hour * 100 + localStart.minute;
          int endTime = localEnd.hour * 100 + localEnd.minute;

          // 4. 计算是第几周
          DateTime eventStartDay = DateTime(localStart.year, localStart.month, localStart.day);
          int daysDiff = eventStartDay.difference(semStart).inDays;
          int weekIndex = (daysDiff ~/ 7) + 1;

          if (weekIndex < 1) weekIndex = 1; // 容错

          courses.add(CourseItem(
            courseName: courseName,
            teacherName: '未知教师', // ics 一般不自带教师字段
            date: dateStr,
            weekday: weekday,
            startTime: startTime,
            endTime: endTime,
            weekIndex: weekIndex,
            roomName: roomName,
            lessonType: null,
          ));
        }
      }
    }

    return courses;
  }

  /// 辅助方法：解析 ICS 日期格式 (例: 20260303T003000Z)
  static DateTime? _parseIcsDateTime(String dtStr) {
    try {
      bool isUtc = dtStr.endsWith('Z');
      String cleanStr = dtStr.replaceAll('Z', '');

      if (cleanStr.length >= 15) {
        int year = int.parse(cleanStr.substring(0, 4));
        int month = int.parse(cleanStr.substring(4, 6));
        int day = int.parse(cleanStr.substring(6, 8));
        int hour = int.parse(cleanStr.substring(9, 11));
        int minute = int.parse(cleanStr.substring(11, 13));
        int second = int.parse(cleanStr.substring(13, 15));

        if (isUtc) {
          // 声明这是 UTC 时间
          return DateTime.utc(year, month, day, hour, minute, second);
        } else {
          // 如果没有Z，当成本地时间处理
          return DateTime(year, month, day, hour, minute, second);
        }
      }
    } catch (e) {
      print("ICS 日期解析错误: $e");
    }
    return null;
  }
}
