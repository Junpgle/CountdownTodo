import 'dart:convert';
import 'package:html/parser.dart' as parser;
import 'package:html/dom.dart';
import 'package:intl/intl.dart';
import 'course_service.dart';

class XmuScheduleParser {
  /// 传入 MHTML/HTML 字符串和 本学期第一周的周一日期
  static List<CourseItem> parseHtml(String htmlString, DateTime semesterStartDate) {
    List<CourseItem> courses = [];

    // 🚀 核心修复：执行绝对安全的底层解码，确保绝不破坏 HTML 标签和现有中文字符
    String cleanHtml = _decodeMhtml(htmlString);

    // 解析纯净的 HTML 树
    Document document = parser.parse(cleanHtml);

    // 增加类名容错适配：防止教务系统更新更改类名 (.arrage -> .arrange)
    var arrageNodes = document.querySelectorAll('.arrage, .arrange');

    for (var node in arrageNodes) {
      // 1. 从父节点 <td> 获取节次和星期信息
      var tdNode = node.parent;
      if (tdNode == null) continue;

      String? styleAttr = tdNode.attributes['style'];
      if (styleAttr != null && styleAttr.replaceAll(' ', '').contains('display:none')) {
        continue;
      }

      int startJc = int.tryParse(tdNode.attributes['jc'] ?? '1') ?? 1;
      int weekday = int.tryParse(tdNode.attributes['xq'] ?? '1') ?? 1;
      int rowSpan = int.tryParse(tdNode.attributes['rowspan'] ?? '1') ?? 1;
      int endJc = startJc + rowSpan - 1; // 计算结束节次

      // 2. 从内部的 div 提取具体信息
      var innerDivs = node.querySelectorAll('div');
      if (innerDivs.length < 3) continue; // 容错：防止遇到空节点

      String weekStr = innerDivs[0].text.trim();       // e.g. "1-15周", "2-14双周"
      String courseName = innerDivs[1].text.trim();    // e.g. "计量经济学(01)"
      String teacherName = innerDivs[2].text.trim();   // e.g. "康嫱"
      String roomName = innerDivs.length > 3 ? innerDivs[3].text.trim() : '未知教室';

      // 提取调课/本研标签 (如果有的话)
      String? lessonType;
      var typeNode = node.querySelector('.bybs');
      if (typeNode != null) {
        lessonType = typeNode.text.trim();
      }

      // 3. 转换上课周序为 List<int>
      List<int> activeWeeks = _parseWeeks(weekStr);

      // 4. 将节次映射为具体的时分戳 (例如 第1节 -> 800)
      List<int> times = _mapJcToTime(startJc, endJc);

      // 5. 因为 CourseItem 需要具体的 date，通过周次和星期推算出来
      for (int week in activeWeeks) {
        DateTime classDate = semesterStartDate
            .add(Duration(days: (week - 1) * 7)) // 加上周的偏移
            .add(Duration(days: weekday - 1));   // 加上星期的偏移

        String dateStr = DateFormat('yyyy-MM-dd').format(classDate);

        courses.add(CourseItem(
          courseName: courseName,
          teacherName: teacherName,
          date: dateStr,
          weekday: weekday,
          startTime: times[0],
          endTime: times[1],
          weekIndex: week,
          roomName: roomName,
          lessonType: lessonType,
        ));
      }
    }

    return courses;
  }

  /// 🚀 底层安全解码方法：将 MHTML 乱码转为标准 UTF-8 HTML，且绝不破坏现有的中文字符
  static String _decodeMhtml(String rawString) {
    if (!rawString.contains('quoted-printable') && !rawString.contains('QUOTED-PRINTABLE') && !rawString.contains('=3D')) {
      return rawString;
    }

    try {
      // 1. 剥离行尾软回车延续符
      String cleaned = rawString.replaceAll(RegExp(r'=\r?\n'), '');

      // 2. 安全解码：只转换 =XX 为字节，保留原本正常的字符（防止破坏已存在的中文）
      List<int> bytes = [];
      int i = 0;
      while (i < cleaned.length) {
        int code = cleaned.codeUnitAt(i);
        if (code == 61 && i + 2 < cleaned.length) { // 61 is '='
          String hex = cleaned.substring(i + 1, i + 3);
          int? byte = int.tryParse(hex, radix: 16);
          if (byte != null) {
            bytes.add(byte);
            i += 3;
            continue;
          }
        }

        // 🚀 核心防御：如果是 ASCII 字符直接存入；如果是中文字符(>127)，必须先转换为 UTF-8 字节流再拼入
        if (code <= 127) {
          bytes.add(code);
        } else {
          bytes.addAll(utf8.encode(String.fromCharCode(code)));
        }
        i++;
      }

      return utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      print("MHTML底层解码失败: $e");
      return rawString;
    }
  }

  /// 辅助方法：解析 "1-15周", "2-14双周", "9-15单周" 为数组
  static List<int> _parseWeeks(String weekStr) {
    List<int> weeks = [];
    RegExp regExp = RegExp(r'(\d+)-(\d+)(单|双)?周');
    var match = regExp.firstMatch(weekStr);

    if (match != null) {
      int start = int.parse(match.group(1)!);
      int end = int.parse(match.group(2)!);
      String? type = match.group(3);

      for (int i = start; i <= end; i++) {
        if (type == '单' && i % 2 == 0) continue;
        if (type == '双' && i % 2 != 0) continue;
        weeks.add(i);
      }
    }
    return weeks;
  }

  /// 辅助方法：把第几节课映射为真实时间
  static List<int> _mapJcToTime(int startJc, int endJc) {
    // 开始时间映射表
    const Map<int, int> startTimes = {
      1: 800, 2: 855, 3: 1010, 4: 1105,
      5: 1430, 6: 1525, 7: 1640, 8: 1735,
      9: 1910, 10: 2005, 11: 2100
    };
    // 结束时间映射表
    const Map<int, int> endTimes = {
      1: 845, 2: 940, 3: 1055, 4: 1150,
      5: 1515, 6: 1610, 7: 1725, 8: 1820,
      9: 1955, 10: 2050, 11: 2145
    };

    int st = startTimes[startJc] ?? 800;
    int et = endTimes[endJc] ?? 940;
    return [st, et];
  }
}