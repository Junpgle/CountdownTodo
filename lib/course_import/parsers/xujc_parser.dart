import 'package:html/parser.dart' as parser;
import 'package:html/dom.dart';
import 'package:intl/intl.dart';
import '../../models.dart';

class XujcScheduleParser {
  /// 嘉庚学院作息时间表映射
  static const Map<int, List<int>> timeMap = {
    1: [800, 845],    // 第1节
    2: [855, 940],    // 第2节
    3: [1000, 1045],  // 第3节
    4: [1055, 1140],  // 第4节
    5: [1230, 1315],  // 午1
    6: [1325, 1410],  // 午2
    7: [1430, 1515],  // 第5节
    8: [1525, 1610],  // 第6节
    9: [1630, 1715],  // 第7节
    10: [1725, 1810], // 第8节
    11: [1930, 2015], // 第9节
    12: [2025, 2110], // 第10节
    13: [2120, 2205], // 第11节
  };

  static List<CourseItem> parseHtml(String htmlString, DateTime semesterStartDate) {
    List<CourseItem> courses = [];
    Document document = parser.parse(htmlString);

    // 嘉庚学院课表通常在 class="data small solid" 的 table 中
    Element? table = document.querySelector('table.solid');
    if (table == null) return [];

    List<Element> rows = table.querySelectorAll('tbody tr');
    
    // 建立一个 13(节次) x 7(星期) 的占用矩阵，用于处理 rowspan
    List<List<int>> rowspanMatrix = List.generate(14, (_) => List.filled(8, 0));

    for (int rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      Element row = rows[rowIndex];
      List<Element> cells = row.querySelectorAll('td');
      if (cells.isEmpty) continue;

      int currentPeriod = rowIndex + 1; // 对应第几节/行
      int cellOffset = 1; // 跳过第一列（节次列）

      for (int weekday = 1; weekday <= 7; weekday++) {
        // 如果当前格子被之前的 rowspan 占用了，跳过
        if (rowspanMatrix[currentPeriod][weekday] > 0) {
          continue;
        }

        if (cellOffset >= cells.length) break;
        Element cell = cells[cellOffset++];

        String text = cell.text.trim();
        if (text.isEmpty || text == '\u00a0' || text == '&nbsp;') continue;

        int rowSpan = int.tryParse(cell.attributes['rowspan'] ?? '1') ?? 1;
        // 标记占用
        for (int i = 0; i < rowSpan; i++) {
          if (currentPeriod + i < 14) {
            rowspanMatrix[currentPeriod + i][weekday] = 1;
          }
        }

        // 解析课程详情
        // 结构通常是: 课程名<br>教师<br>地点<br>周次1<br>周次2...
        // cell.innerHtml 中包含 <br>，可以据此分割
        List<String> parts = cell.innerHtml.split(RegExp(r'<br/?>')).map((s) => s.replaceAll(RegExp(r'<[^>]*>'), '').trim()).toList();
        
        if (parts.length < 4) continue;

        String courseName = parts[0];
        String teacherName = parts[1];
        String roomName = parts[2];
        
        // 剩下的部分可能是多条周次规则
        for (int i = 3; i < parts.length; i++) {
          String rule = parts[i];
          if (rule.isEmpty) continue;

          List<int> activeWeeks = _parseWeekRule(rule);
          if (activeWeeks.isEmpty) continue;

          // 计算时间
          int startJc = currentPeriod;
          int endJc = currentPeriod + rowSpan - 1;
          
          int startTime = timeMap[startJc]?[0] ?? 800;
          int endTime = timeMap[endJc]?[1] ?? (timeMap[startJc]?[1] ?? 845);

          for (int week in activeWeeks) {
            DateTime classDate = semesterStartDate
                .add(Duration(days: (week - 1) * 7))
                .add(Duration(days: weekday - 1));

            String dateStr = DateFormat('yyyy-MM-dd').format(classDate);

            courses.add(CourseItem(
              courseName: courseName,
              teacherName: teacherName,
              date: dateStr,
              weekday: weekday,
              startTime: startTime,
              endTime: endTime,
              weekIndex: week,
              roomName: roomName,
            ));
          }
        }
      }
    }

    return courses;
  }

  static List<int> _parseWeekRule(String rule) {
    List<int> weeks = [];
    // 匹配格式: "1-15周(每周)", "3-3周(单周)", "6-8周(双周)", "4-4周(双周)(李霁)"
    // 或者是 "13-14周(每周)"
    RegExp regExp = RegExp(r"(\d+)-(\d+)周\((每周|单周|双周)\)");
    var matches = regExp.allMatches(rule);
    
    for (var match in matches) {
      int start = int.parse(match.group(1)!);
      int end = int.parse(match.group(2)!);
      String type = match.group(3)!;
      for (int i = start; i <= end; i++) {
        if (type == '单周' && i % 2 == 0) continue;
        if (type == '双周' && i % 2 != 0) continue;
        weeks.add(i);
      }
    }

    // 兜底：如果没匹配到带括弧的，尝试匹配纯数字区间 e.g. "1-15周"
    if (weeks.isEmpty) {
      RegExp simpleExp = RegExp(r"(\d+)-(\d+)周");
      var match = simpleExp.firstMatch(rule);
      if (match != null) {
        int start = int.parse(match.group(1)!);
        int end = int.parse(match.group(2)!);
        for (int i = start; i <= end; i++) {
          weeks.add(i);
        }
      }
    }

    return weeks;
  }
}
