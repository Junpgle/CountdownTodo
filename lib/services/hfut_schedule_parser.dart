import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as hp;
import 'package:html/dom.dart' as dom;
import 'course_service.dart';

class HfutScheduleParser {
  /// 校验传入的字符串（JSON或HTML）是否符合课表格式
  static bool isValid(String rawInput) {
    String input = _decodeMhtml(rawInput.trim());
    
    // 🚀 调试采样：打印开头内容辅助诊断抓取到了什么
    debugPrint('[HfutParser] Validating input (Length: ${input.length})');
    if (input.length > 500) {
      debugPrint('[HfutParser] Header Snippet: ${input.substring(0, 300).replaceAll('\n', ' ')}');
    }

    if (_extractData(input) != null) {
      debugPrint('[HfutParser] Input identified as JuZai JSON format');
      return true;
    }
    if (_parseEams5TaskActivity(input) != null) {
      debugPrint('[HfutParser] Input identified as EAMS5 HTML format');
      return true;
    }
    
    // 3. 🚀 新增：DOM 表格探测
    if (input.contains('card-view') && input.contains('weekday')) {
      debugPrint('[HfutParser] Input identified as Rendered Table format');
      return true;
    }
    
    // 增加对通用 EAMS 关键词的检查
    if (input.contains('TaskActivity') || input.contains('lessonList') || input.contains('courseTable')) {
       debugPrint('[HfutParser] Keyword match found. Capturing context...');
       _logKeywordContext(input, 'TaskActivity');
       _logKeywordContext(input, 'lessonList');
       _logKeywordContext(input, 'courseTable');
    }

    debugPrint('[HfutParser] Input did not match any known HFUT format markers');
    return false;
  }

  static void _logKeywordContext(String input, String keyword) {
    int idx = input.indexOf(keyword);
    if (idx != -1) {
      int start = (idx - 50).clamp(0, input.length);
      int end = (idx + 300).clamp(0, input.length);
      debugPrint('[HfutParser] Context for "$keyword": ${input.substring(start, end).replaceAll('\n', ' ')}');
    }
  }

  /// 执行核心解析逻辑，将任意有效输入映射为内部的 CourseItem 列表
  static List<CourseItem> parse(String rawInput) {
    String input = _decodeMhtml(rawInput.trim());

    // 1. 优先尝试使用聚在工大 JSON 结构解析 (兼容旧版 API)
    final data = _extractData(input);
    if (data != null) {
      return _parseJuZaiJson(data);
    }

    // 2. 尝试使用教务系统原生 HTML TaskActivity 解析 (兼容直接抓取官方网页)
    final eams5Courses = _parseEams5TaskActivity(input);
    if (eams5Courses != null && eams5Courses.isNotEmpty) {
      return _sortCourses(eams5Courses);
    }

    // 3. 🚀 尝试 DOM 表格解析 (针对已经渲染成文字的网页)
    final tableCourses = _parseTableHtml(input);
    if (tableCourses != null && tableCourses.isNotEmpty) {
      return _sortCourses(tableCourses);
    }

    return [];
  }

  static List<CourseItem> _sortCourses(List<CourseItem> list) {
    list.sort((a, b) {
      int weekCmp = a.weekIndex.compareTo(b.weekIndex);
      if (weekCmp != 0) return weekCmp;
      int dayCmp = a.weekday.compareTo(b.weekday);
      if (dayCmp != 0) return dayCmp;
      return a.startTime.compareTo(b.startTime);
    });
    return list;
  }

  /// 专门用于提取合工大官方 EAMS5 教务系统 HTML 中的课表脚本
  static List<CourseItem>? _parseEams5TaskActivity(String input) {
    // 🚀 核心改进：使用更强力的正则寻找 TaskActivity 调用，允许更多字符干扰
    final regex = RegExp(r'TaskActivity\s*\((.*?)\);', dotAll: true);
    final matches = regex.allMatches(input);
    if (matches.isEmpty) {
       debugPrint('[HfutParser] No TaskActivity(...) matches found');
       return null;
    }
    debugPrint('[HfutParser] Found ${matches.length} matches for TaskActivity');

    List<CourseItem> courses = [];
    for (var match in matches) {
      String argsStr = match.group(1) ?? '';
      // 提取被引号包裹的字符串参数 (兼容双引号和单引号)
      final strRegex = RegExp(r'"([^"\\]*(?:\\.[^"\\]*)*)"' + '|' + r"'([^\'\\]*(?:\\.[^\'\\]*)*)'");
          final strMatches = strRegex.allMatches(argsStr);
      List<String> args = [];
      for (var strMatch in strMatches) {
        args.add(strMatch.group(1) ?? strMatch.group(2) ?? '');
      }

      // 寻找特征值：一串长度超过20，全由0和1组成的字符串（代表有效周次）
      int weekIdx = args.indexWhere((s) => s.length >= 20 && s.contains(RegExp(r'^[01]+$')));
      if (weekIdx != -1 && weekIdx + 3 < args.length) {
        debugPrint('[HfutParser] Successfully extracted arguments for a course at index $weekIdx');
        String validWeeks = args[weekIdx];
        int weekday = int.tryParse(args[weekIdx + 1]) ?? 1;
        int startUnit = int.tryParse(args[weekIdx + 2]) ?? 1;
        int endUnit = int.tryParse(args[weekIdx + 3]) ?? 1;

        // 根据 EAMS5 参数规范相对定位提取课程信息，抗干扰能力极强
        String roomName = weekIdx >= 1 ? args[weekIdx - 1] : '未知教室';
        String courseName = weekIdx >= 3 ? args[weekIdx - 3] : '未知课程';
        String teacherName = weekIdx >= 5 ? args[weekIdx - 5] : '未知教师';

        // 兼容周日
        if (weekday == 0 || weekday == 7) weekday = 7;

        // 遍历有效周次字符串，拆解为每一周的独立课程卡片
        for (int i = 0; i < validWeeks.length; i++) {
          if (validWeeks[i] == '1') {
            courses.add(CourseItem(
              courseName: courseName,
              teacherName: teacherName,
              date: '', // EAMS5 TaskActivity 无法提取准确年月日日期，留空让 UI 基于周次渲染
              weekday: weekday,
              startTime: _unitToTime(startUnit, true),
              endTime: _unitToTime(endUnit, false),
              weekIndex: i, // 通常 0 代表教学第 0 周，1 代表第 1 周
              roomName: roomName,
              lessonType: '',
            ));
          }
        }
      }
    }

    return courses.isNotEmpty ? courses : null;
  }

  /// MHTML / Quoted-Printable 解码器
  /// 修复从网页/邮件格式保存导致 HTML 源码断行、符号被转义的问题
  static String _decodeMhtml(String input) {
    if (input.contains('=\r\n') || input.contains('=\n')) {
      String res = input.replaceAll('=\r\n', '').replaceAll('=\n', '');
      res = res.replaceAll('=3D', '=');
      res = res.replaceAll('=22', '"');
      res = res.replaceAll('=27', "'");
      res = res.replaceAll('=20', ' ');
      return res;
    }
    return input;
  }

  /// 旧版本格式 JSON 解析器
  static List<CourseItem> _parseJuZaiJson(Map<String, dynamic> data) {
    final lessonList = data['lessonList'] as List? ?? [];
    final scheduleList = data['scheduleList'] as List? ?? [];

    Map<int, dynamic> lessonMap = {
      for (var item in lessonList) if (item['id'] != null) item['id']: item
    };

    List<CourseItem> courses = [];
    for (var schedule in scheduleList) {
      final lessonId = schedule['lessonId'];
      final lessonInfo = lessonMap[lessonId];

      if (lessonInfo != null) {
        String roomName = '未知教室';
        if (schedule['room'] != null) {
          roomName = schedule['room']['nameZh'] ?? schedule['room']['name'] ?? '未知教室';
        }

        courses.add(CourseItem(
          courseName: lessonInfo['courseName']?.toString().trim() ?? '未知课程',
          teacherName: schedule['personName'] ?? '未知教师',
          date: schedule['date'] ?? '',
          weekday: schedule['weekday'] ?? 1,
          startTime: _tryInt(schedule['startTime']) ?? 0,
          endTime: _tryInt(schedule['endTime']) ?? 0,
          weekIndex: schedule['weekIndex'] ?? 0,
          roomName: roomName,
          lessonType: schedule['lessonType'] ?? '',
        ));
      }
    }

    courses.sort((a, b) {
      int dateCmp = a.date.compareTo(b.date);
      if (dateCmp != 0) return dateCmp;
      return a.startTime.compareTo(b.startTime);
    });

    return courses;
  }

  /// 🚀 核心新增：基于 DOM 结构的表格解析逻辑
  static List<CourseItem>? _parseTableHtml(String html) {
    List<CourseItem> courses = [];
    try {
      dom.Document document = hp.parse(html);

      // 提取学期起始日期以计算每节课的正确日期
      DateTime semesterStartDate = DateTime(2026, 3, 2); // 兜底默认值
      dom.Element? startDateSpan = document.querySelector('#startDate');
      if (startDateSpan != null) {
        semesterStartDate = DateTime.parse(startDateSpan.text.trim());
        debugPrint('[HfutParser] Detected Semester Start: $semesterStartDate');
      }

      List<dom.Element> columns = document.querySelectorAll('div.columns.weekday');
      debugPrint('[HfutParser] Found ${columns.length} weekday columns');

      for (int dayIdx = 0; dayIdx < columns.length; dayIdx++) {
        dom.Element dayColumn = columns[dayIdx];
        List<dom.Element> cards = dayColumn.querySelectorAll('div.card-view');
        
        for (dom.Element card in cards) {
          dom.Element? content = card.querySelector('.card-content');
          if (content == null) continue;

          dom.Element? pTag = content.querySelector('p');
          if (pTag == null) continue;

          String pText = pTag.innerHtml.replaceAll('<br>', '\n');
          List<String> lines = pText.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
          
          if (lines.length < 2) continue;

          String name = lines[0]; // 编译原理
          String info = lines[1]; // 敬亭学堂420 (7~16周) 1 (1,2)

          // 提取周次: (7~16周)
          RegExp weekRegex = RegExp(r'\((\d+)~(\d+)周\)');
          var weekMatch = weekRegex.firstMatch(info);
          int startWeek = 1;
          int endWeek = 1;
          if (weekMatch != null) {
            startWeek = int.parse(weekMatch.group(1)!);
            endWeek = int.parse(weekMatch.group(2)!);
          } else {
            // 尝试匹配单周 "(4周)"
            RegExp singleWeekRegex = RegExp(r'\((\d+)周\)');
            var singleMatch = singleWeekRegex.firstMatch(info);
            if (singleMatch != null) {
              startWeek = endWeek = int.parse(singleMatch.group(1)!);
            }
          }

          // 提取节次: (1,2)
          RegExp sectionRegex = RegExp(r'\((\d+),(\d+)\)');
          var sectionMatch = sectionRegex.firstMatch(info);
          int startSection = 1;
          int endSection = 2;
          if (sectionMatch != null) {
            startSection = int.parse(sectionMatch.group(1)!);
            endSection = int.parse(sectionMatch.group(2)!);
          }

          // 提取地点: 可能是 lines[1] 的开头部分
          String location = info.split('(')[0].trim();

          for (int w = startWeek; w <= endWeek; w++) {
            // 计算具体日期
            DateTime courseDate = semesterStartDate.add(Duration(days: (w - 1) * 7 + dayIdx));
            String dateStr = "${courseDate.year}-${courseDate.month.toString().padLeft(2, '0')}-${courseDate.day.toString().padLeft(2, '0')}";

            courses.add(CourseItem(
              courseName: name,
              roomName: location,
              teacherName: "教师",
              weekday: dayIdx + 1,
              startTime: (startSection + 7) * 100, // 合工大第1节从8:00开始, A00格式
              endTime: (endSection + 8) * 100,
              weekIndex: w,
              date: dateStr,
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('[HfutParser] DOM Parse Error: $e');
    }
    return courses;
  }

  /// 增强版数据提取逻辑：地毯式搜索所有可能的 JSON 结构
  static Map<String, dynamic>? _extractData(String input) {
    // 1. 标准 JSON 探测
    if (input.startsWith('{') || input.startsWith('[')) {
      try {
        final data = jsonDecode(input);
        if (data is Map) {
          if (data['result'] != null && data['result']['lessonList'] != null) return {'lessonList': data['result']['lessonList'], 'scheduleList': data['result']['scheduleList'] ?? []};
          if (data['lessonList'] != null) return {'lessonList': data['lessonList'], 'scheduleList': data['scheduleList'] ?? []};
        }
      } catch (_) {}
    }

    // 2. 🚀 暴力正则探测：在 31 万字 HTML 中寻找任何包含关键特征的 JSON 块
    debugPrint('[HfutParser] Performing greedy JSON extraction...');
    final greedyRegex = RegExp(r'(\{[\s\S]*?"lessonList"[\s\S]*?\})', dotAll: true);
    final matches = greedyRegex.allMatches(input);
    
    for (var match in matches) {
      try {
        String candidate = match.group(1)!;
        // 尝试平衡大括号，防止正则抓得太长
        candidate = _balanceBraces(candidate);
        final data = jsonDecode(candidate);
        if (data is Map && (data['lessonList'] != null || (data['result'] != null && data['result']['lessonList'] != null))) {
          debugPrint('[HfutParser] Greedy search SUCCESS!');
          final result = data['result'] ?? data;
          return {
            'lessonList': result['lessonList'],
            'scheduleList': result['scheduleList'] ?? [],
          };
        }
      } catch (_) {}
    }

    return null;
  }

  static String _balanceBraces(String input) {
    int depth = 0;
    for (int i = 0; i < input.length; i++) {
      if (input[i] == '{') depth++;
      else if (input[i] == '}') {
        depth--;
        if (depth == 0) return input.substring(0, i + 1);
      }
    }
    return input;
  }

  static String? _extractArray(String input, String key) {
    final regex = RegExp('("$key"|$key)\\s*[:=]\\s*\\[');
    final match = regex.firstMatch(input);
    if (match == null) return null;

    int start = match.end - 1;
    int depth = 0;
    bool inString = false;
    bool inEscape = false;
    String quoteChar = '';

    for (int i = start; i < input.length; i++) {
      String char = input[i];
      if (inEscape) { inEscape = false; continue; }
      if (char == '\\') { inEscape = true; continue; }
      if (inString) {
        if (char == quoteChar) inString = false;
        continue;
      }
      if (char == '"' || char == "'") {
        inString = true;
        quoteChar = char;
        continue;
      }
      if (char == '[') depth++;
      if (char == ']') {
        depth--;
        if (depth == 0) return input.substring(start, i + 1);
      }
    }
    return null;
  }

  /// 辅助方法：将合工大的“课节”(如第1节、第3节) 转为内部的时间整数 (如 800, 1400)
  static int _unitToTime(int unit, bool isStart) {
    // 映射合工大上课作息时间 (格式为 100 * 小时 + 分钟)
    Map<int, int> startTimes = {
      1: 800, 2: 850, 3: 1005, 4: 1055,
      5: 1400, 6: 1450, 7: 1600, 8: 1650,
      9: 1900, 10: 1950, 11: 2040
    };
    Map<int, int> endTimes = {
      1: 845, 2: 935, 3: 1050, 4: 1140,
      5: 1445, 6: 1535, 7: 1645, 8: 1735,
      9: 1945, 10: 2035, 11: 2125
    };

    if (isStart) {
      return startTimes[unit] ?? (unit * 100);
    } else {
      return endTimes[unit] ?? (unit * 100 + 45);
    }
  }

  static int? _tryInt(dynamic val) {
    if (val == null) return null;
    if (val is int) return val;
    return int.tryParse(val.toString());
  }
}