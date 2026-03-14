import 'dart:convert';
import 'package:html/parser.dart' as parser;
import 'package:html/dom.dart';
import 'package:intl/intl.dart';
import 'course_service.dart';

class ZfSoftScheduleParser {
  /// 传入 正方系统导出的 MHTML/HTML 字符串以及学期开始日期
  /// [customTimes] 格式示例: { 1: {'start': 800, 'end': 845}, 2: {'start': 855, 'end': 940} }
  static List<CourseItem> parseHtml(
      String htmlString,
      DateTime semesterStartDate,
      {Map<int, Map<String, int>>? customTimes}
      ) {
    List<CourseItem> courses = [];

    // 1. 底层解码
    String cleanHtml = _decodeMhtml(htmlString);
    Document document = parser.parse(cleanHtml);

    // 2. 核心逻辑：获取网格视图中的课程节点
    var courseNodes = document.querySelectorAll('#table1 .timetable_con');

    // 🚀 预处理：确保从学期第一周的周一开始计算日期（彻底解决周次日期偏移问题）
    DateTime semesterMonday = semesterStartDate.subtract(Duration(days: semesterStartDate.weekday - 1));

    for (var node in courseNodes) {
      String? title = node.querySelector('.title')?.text.trim();
      if (title == null || title.isEmpty) continue;

      title = title.replaceAll(RegExp(r'[★●◆]'), '').replaceAll(RegExp(r'^【.*?】'), '').trim();

      int weekday = 1;
      Element? current = node.parent;
      while (current != null) {
        if (current.localName == 'td' && current.id.isNotEmpty) {
          var idParts = current.id.split('-');
          if (idParts.isNotEmpty) {
            weekday = int.tryParse(idParts[0]) ?? 1;
          }
          break;
        }
        current = current.parent;
      }

      // 🚀 关键修复：支持一个课程节点内存在多段不同的时间/周次信息
      List<String> timeSegments = [];
      String location = '';
      String teacher = '';

      for (var p in node.querySelectorAll('p')) {
        var tooltipNode = p.querySelector('[data-toggle="tooltip"]');
        if (tooltipNode != null) {
          String tooltipTitle = tooltipNode.attributes['title']?.trim() ?? '';
          String pText = p.text.trim();

          if (tooltipTitle == '节/周') {
            timeSegments.add(pText); // 记录所有时间段，防止被覆盖
          } else if (tooltipTitle == '上课地点') {
            location = pText;
          } else if (tooltipTitle.contains('教师')) {
            teacher = pText;
          }
        }
      }

      // 遍历该课程的所有时间段
      for (String timeStr in timeSegments) {
        // 解析节次：增加对中文括号的支持
        int startJc = 1;
        int endJc = 2;
        RegExp periodExp = RegExp(r'[(\（](?:周.*?第)?(\d+)-(\d+)[节)\）]');
        var match = periodExp.firstMatch(timeStr);
        if (match != null) {
          startJc = int.tryParse(match.group(1)!) ?? startJc;
          endJc = int.tryParse(match.group(2)!) ?? endJc;
        } else {
          RegExp singlePeriodExp = RegExp(r'[(\（](?:周.*?第)?(\d+)[节)\）]');
          var singleMatch = singlePeriodExp.firstMatch(timeStr);
          if (singleMatch != null) {
            startJc = int.tryParse(singleMatch.group(1)!) ?? startJc;
            endJc = startJc;
          }
        }

        // 解析周次
        List<int> weeks = _parseZfWeeks(timeStr);

        for (int week in weeks) {
          // 使用对齐后的周一进行计算
          DateTime courseDate = semesterMonday.add(Duration(days: (week - 1) * 7 + (weekday - 1)));
          String dateStr = DateFormat('yyyy-MM-dd').format(courseDate);

          courses.add(CourseItem(
            courseName: title,
            teacherName: teacher,
            roomName: location,
            weekday: weekday,
            weekIndex: week,
            date: dateStr,
            startTime: _getStartTime(startJc, customTimes),
            endTime: _getEndTime(endJc, customTimes),
            lessonType: null,
          ));
        }
      }
    }

    return courses;
  }

  static int _getStartTime(int jc, Map<int, Map<String, int>>? customTimes) {
    if (customTimes != null && customTimes.containsKey(jc)) {
      return customTimes[jc]!['start'] ?? 800;
    }
    const defaultTimes = {
      1: 800, 2: 855, 3: 1010, 4: 1105, 5: 1400,
      6: 1455, 7: 1605, 8: 1700, 9: 1900, 10: 1955, 11: 2050, 12: 2145
    };
    return defaultTimes[jc] ?? 800;
  }

  static int _getEndTime(int jc, Map<int, Map<String, int>>? customTimes) {
    if (customTimes != null && customTimes.containsKey(jc)) {
      return customTimes[jc]!['end'] ?? 940;
    }
    const defaultTimes = {
      1: 845, 2: 940, 3: 1055, 4: 1150, 5: 1445,
      6: 1540, 7: 1650, 8: 1745, 9: 1945, 10: 2040, 11: 2135, 12: 2230
    };
    return defaultTimes[jc] ?? 940;
  }

  /// 🚀 增强版周次解析：支持空格、中英文逗号分隔符，支持中文括号
  static List<int> _parseZfWeeks(String rawStr) {
    // 移除括号内的节次信息，同时兼容中英文括号
    String weekPart = rawStr.replaceAll(RegExp(r'[(\（](?:周.*?第)?\d+(?:-\d+)?[节)\）]'), '');
    weekPart = weekPart.replaceAll('周', '');

    List<int> weeks = [];
    if (weekPart.isEmpty) return weeks;

    // 🚀 重点修复：同时支持空格、英文逗号、中文逗号作为分隔符
    List<String> parts = weekPart.split(RegExp(r'[,，\s]+'));

    for (String p in parts) {
      if (p.trim().isEmpty) continue;

      bool isOdd = p.contains('单');
      bool isEven = p.contains('双');

      String numPart = p.replaceAll(RegExp(r'[^\d\-]'), '');
      if (numPart.isEmpty) continue;

      if (numPart.contains('-')) {
        var bounds = numPart.split('-');
        if (bounds.length == 2) {
          int start = int.tryParse(bounds[0]) ?? 0;
          int end = int.tryParse(bounds[1]) ?? 0;
          if (start > 0 && end >= start) {
            for (int i = start; i <= end; i++) {
              if (isOdd && i % 2 == 0) continue;
              if (isEven && i % 2 != 0) continue;
              weeks.add(i);
            }
          }
        }
      } else {
        int? w = int.tryParse(numPart);
        if (w != null) weeks.add(w);
      }
    }
    var uniqueWeeks = weeks.toSet().toList();
    uniqueWeeks.sort();
    return uniqueWeeks;
  }

  static String _decodeMhtml(String rawString) {
    if (!rawString.contains('=\n') && !rawString.contains('=\r\n')) {
      return rawString;
    }
    try {
      String cleaned = rawString.replaceAll('=\r\n', '').replaceAll('=\n', '');
      List<int> bytes = [];
      int i = 0;
      while (i < cleaned.length) {
        if (cleaned[i] == '=' && i + 2 < cleaned.length) {
          String hex = cleaned.substring(i + 1, i + 3);
          int? code = int.tryParse(hex, radix: 16);
          if (code != null) {
            bytes.add(code);
            i += 3;
            continue;
          }
        }
        int code = cleaned.codeUnitAt(i);
        if (code <= 127) {
          bytes.add(code);
        } else {
          bytes.addAll(utf8.encode(String.fromCharCode(code)));
        }
        i++;
      }
      return utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      return rawString;
    }
  }
}