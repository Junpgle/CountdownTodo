import 'dart:convert'; // 🚀 新增：用于 UTF-8 解码
import 'package:html/parser.dart' as parser;
import 'package:html/dom.dart';
import 'package:intl/intl.dart';
import 'course_service.dart'; // 引入你的 CourseItem 模型

class XmuScheduleParser {
  /// 传入 MHTML/HTML 字符串和 本学期第一周的周一日期
  static List<CourseItem> parseHtml(String htmlString, DateTime semesterStartDate) {
    List<CourseItem> courses = [];

    // 🚀 核心修复：如果是 MHTML 导出的带编码文本，先进行深度解码还原成真实 HTML
    String cleanHtml = _decodeMhtml(htmlString);

    // 解析纯净的 HTML 树
    Document document = parser.parse(cleanHtml);

    // 找到所有带有 "arrage" 类的课程节点
    var arrageNodes = document.querySelectorAll('.arrage');

    for (var node in arrageNodes) {
      // 1. 从父节点 <td> 获取节次和星期信息
      var tdNode = node.parent;
      if (tdNode == null) continue;

      // 🚀 核心修复：教务系统使用 rowspan 合并单元格时，会生成带有 display:none 的多余隐藏格子
      // 必须把隐藏的格子过滤掉，否则会抓取到重叠的课程，导致界面卡片文字堆叠发虚
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

      // 5. 因为你的 CourseItem 需要具体的 date，我们通过周次和星期推算出来
      for (int week in activeWeeks) {
        // 计算当前这节课所在的具体日期
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

  /// 🚀 底层解码方法：将 MHTML 乱码转为标准 UTF-8 HTML
  static String _decodeMhtml(String rawString) {
    // 判断是否包含 quoted-printable 特征（比如 =3D 或者 =E8）
    if (!rawString.contains('=3D') && !rawString.contains('quoted-printable') && !rawString.contains('QUOTED-PRINTABLE')) {
      return rawString; // 已经是纯 HTML，直接返回
    }

    try {
      // 1. 剥离行尾软回车延续符 (=\r\n 或 =\n)
      String cleaned = rawString.replaceAll(RegExp(r'=\r?\n'), '');

      // 2. 将 =XX 转换为真实的字节数组
      List<int> decodedBytes = [];
      int i = 0;
      while (i < cleaned.length) {
        if (cleaned[i] == '=' && i + 2 < cleaned.length) {
          String hex = cleaned.substring(i + 1, i + 3);
          int? byte = int.tryParse(hex, radix: 16);
          if (byte != null) {
            decodedBytes.add(byte);
            i += 3;
            continue;
          }
        }
        decodedBytes.add(cleaned.codeUnitAt(i));
        i++;
      }

      // 3. 将提取出的干净字节按 UTF-8 正确解码出中文
      return utf8.decode(decodedBytes, allowMalformed: true);
    } catch (e) {
      print("MHTML底层解码失败: $e");
      return rawString; // 如果解码抛出异常，返回原字符串兜底
    }
  }

  /// 辅助方法：解析 "1-15周", "2-14双周", "9-15单周" 为数组
  static List<int> _parseWeeks(String weekStr) {
    List<int> weeks = [];
    // 正则匹配，提取起始周、结束周，以及是否包含单双字眼
    RegExp regExp = RegExp(r'(\d+)-(\d+)(单|双)?周');
    var match = regExp.firstMatch(weekStr);

    if (match != null) {
      int start = int.parse(match.group(1)!);
      int end = int.parse(match.group(2)!);
      String? type = match.group(3); // '单' 或者 '双' 或者 null

      for (int i = start; i <= end; i++) {
        if (type == '单' && i % 2 == 0) continue;
        if (type == '双' && i % 2 != 0) continue;
        weeks.add(i);
      }
    }
    return weeks;
  }

  /// 辅助方法：把第几节课映射为真实时间 (依据你提供的骨架提取)
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