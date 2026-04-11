import 'dart:convert';
import 'package:html/parser.dart' as parser;
import 'package:html/dom.dart';
import 'package:intl/intl.dart';
import '../../models.dart';

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

    // 2. 核心逻辑：获取页面中所有的课程节点块
    // 🚀 修复：不限表格 ID (适配 kbgrid_table_0, table1 等)，确保能抓取到所有课程
    var courseNodes = document.querySelectorAll('.timetable_con');

    // 🚀 预处理：对齐学期周一，确保日期推算不跨周
    DateTime semesterMonday = semesterStartDate.subtract(Duration(days: semesterStartDate.weekday - 1));

    for (var node in courseNodes) {
      // 获取课程名称：兼容 u 和 span 两种标题包装方式
      String? title = node.querySelector('.title')?.text.trim();
      if (title == null || title.isEmpty) continue;

      // 清洗标记
      title = title.replaceAll(RegExp(r'[★●◆]'), '').replaceAll(RegExp(r'^【.*?】'), '').trim();

      // 🚀 核心修复：根据 td 的 ID 或位置识别星期
      int weekday = 1;
      Element? tdElement;
      Element? current = node.parent;
      while (current != null) {
        if (current.localName == 'td') {
          tdElement = current;
          break;
        }
        current = current.parent;
      }

      if (tdElement != null) {
        String tdId = tdElement.id;
        // 匹配第一个数字，如 "3-1" 匹配 3 (周三)
        RegExp dayReg = RegExp(r'\d+');
        var match = dayReg.firstMatch(tdId);
        if (match != null) {
          weekday = int.tryParse(match.group(0)!) ?? 1;
        } else {
          // 兜底：如果 ID 无数字，根据 cellIndex 计算
          // 表格通常前两列是时间/节次，所以 index 2 对应周一
          Element? tr = tdElement.parent;
          if (tr != null) {
            int idx = tr.children.indexOf(tdElement);
            if (idx >= 2) {
              weekday = idx - 1;
            }
          }
        }
      }

      List<String> timeSegments = [];
      String location = '';
      String teacher = '';

      // 提取课程段落中的时间、地点、教师
      for (var p in node.querySelectorAll('p')) {
        String pText = p.text.trim();
        var tooltipNode = p.querySelector('[data-toggle="tooltip"]');
        String tooltipTitle = tooltipNode?.attributes['title']?.trim() ?? '';

        // 识别时间行：精准排除“周学时”、“总学时”
        if (tooltipTitle == '节/周' || (pText.contains('节') && pText.contains('('))) {
          timeSegments.add(pText);
        } else if (tooltipTitle == '上课地点' || (location.isEmpty && pText.contains(RegExp(r'[教楼室区]')))) {
          location = pText;
        } else if (tooltipTitle.contains('教师') || (teacher.isEmpty && pText.length >= 2 && pText.length <= 4)) {
          teacher = pText;
        }
      }

      if (timeSegments.isEmpty) continue;

      // 🚀 日志验证：打印每个课程节点收集到的原始时间段
      print('[$title] timeSegments: $timeSegments');

      for (String timeStr in timeSegments) {
        // 解析节次 (如 1-2节)
        int startJc = 1;
        int endJc = 2;
        RegExp periodExp = RegExp(r'[(\（](?:周.*?第)?(\d+)(?:-(\d+))?[节)）]');
        var pMatch = periodExp.firstMatch(timeStr);
        if (pMatch != null) {
          startJc = int.tryParse(pMatch.group(1)!) ?? startJc;
          String? endGroup = pMatch.group(2);
          endJc = (endGroup != null) ? (int.tryParse(endGroup) ?? startJc) : startJc;
        }

        // 解析周次 (确保能解析 18 周这类单独数字)
        List<int> weeks = _parseZfWeeks(timeStr);

        // 🚀 日志验证：打印解析出的最终周次列表
        print('[$title] timeStr=$timeStr weeks=$weeks');

        for (int week in weeks) {
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

    // 全局去重：防止因扫描多个表格导致的课程冲突
    final seen = <String>{};
    return courses.where((c) {
      final key = "${c.date}-${c.startTime}-${c.courseName}";
      if (seen.contains(key)) return false;
      seen.add(key);
      return true;
    }).toList();
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

  static List<int> _parseZfWeeks(String rawStr) {
    // 移除干扰项：移除包含“节”字的括号内容
    String content = rawStr.replaceAll(RegExp(r'[(\（][^)\（]*?节[^)\（]*?[)）]'), '');

    List<int> weeks = [];

    // 正则匹配所有数字组合，识别 1-16, 18 等
    RegExp weekPattern = RegExp(r'(\d+)(?:-(\d+))?(?:周)?(?:\((单|双)\))?');
    var matches = weekPattern.allMatches(content);

    for (var m in matches) {
      int start = int.parse(m.group(1)!);
      int? end = m.group(2) != null ? int.parse(m.group(2)!) : null;
      String? type = m.group(3);

      if (end != null) {
        for (int i = start; i <= end; i++) {
          if (type == '单' && i % 2 == 0) continue;
          if (type == '双' && i % 2 != 0) continue;
          weeks.add(i);
        }
      } else {
        weeks.add(start);
      }
    }

    return weeks.toSet().toList()..sort();
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
