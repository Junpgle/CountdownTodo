import 'dart:convert';
import '../../models.dart';

class HfutScheduleParser {
  /// 校验传入的字符串（JSON或HTML）是否符合课表格式
  static bool isValid(String rawInput) {
    String input = _preprocessInput(rawInput);
    if (_extractData(input) != null) return true;
    if (_parseEams5TaskActivity(input) != null) return true;
    if (_parseEams5HtmlCards(input) != null) return true;
    return false;
  }

  /// 执行核心解析逻辑，将任意有效输入映射为内部的 CourseItem 列表
  static List<CourseItem> parse(String rawInput, {DateTime? semesterStart}) {
    String input = _preprocessInput(rawInput);
    List<CourseItem> initialCourses = [];

    // 1. 优先尝试使用 JSON 结构解析 (兼容原生 EAMS5 Datum 接口 和 聚在工大旧版 API)
    final data = _extractData(input);

    // 【修改点】防御性校验：确保提取到了真实数据，如果 lessonList 为空，说明 JS 抓取失败，应当向下走降级
    if (data != null && (data['lessonList'] as List?)?.isNotEmpty == true) {
      initialCourses = _parseJson(data);
    }

    if (initialCourses.isEmpty) {
      // 2. 尝试使用教务系统原生 HTML TaskActivity 解析 (兼容直接抓取官方网页)
      final eams5Courses = _parseEams5TaskActivity(input);
      if (eams5Courses != null && eams5Courses.isNotEmpty) {
        initialCourses = eams5Courses;
      } else {
        // 3. 尝试解析 EAMS5 渲染好的 HTML card-view 课表（WebView 保存的完整页面）
        final htmlCardCourses = _parseEams5HtmlCards(input);
        if (htmlCardCourses != null && htmlCardCourses.isNotEmpty) {
          initialCourses = htmlCardCourses;
        }
      }
    }

    if (initialCourses.isEmpty) return [];

    // 🚀 核心逻辑：结合开学日期补全具体日期
    List<CourseItem> finalCourses = initialCourses;
    if (semesterStart != null) {
      // 无论用户选的是哪一天，都先对齐到该周的周一
      final semesterMonday = semesterStart.subtract(Duration(days: semesterStart.weekday - 1));

      finalCourses = initialCourses.map((c) {
        if (c.date.isNotEmpty) return c;
        // 🚀 修复点1：计算日期: 该周周一 + ((周次 - 1) * 7) + (星期 - 1)
        // 以前 c.weekIndex 是0导致第一周倒退7天，现在统一 c.weekIndex 是基于1 of the week index
        final courseDate = semesterMonday.add(Duration(days: (c.weekIndex - 1) * 7 + (c.weekday - 1)));
        final dateStr = "${courseDate.year}-${courseDate.month.toString().padLeft(2, '0')}-${courseDate.day.toString().padLeft(2, '0')}";
        return CourseItem(
          courseName: c.courseName,
          teacherName: c.teacherName,
          date: dateStr,
          weekday: c.weekday,
          startTime: c.startTime,
          endTime: c.endTime,
          weekIndex: c.weekIndex,
          roomName: c.roomName,
          lessonType: c.lessonType,
        );
      }).toList();
    }

    // 统一排序
    finalCourses.sort((a, b) {
      if (a.date.isNotEmpty && b.date.isNotEmpty) {
        int dateCmp = a.date.compareTo(b.date);
        if (dateCmp != 0) return dateCmp;
      }
      int weekCmp = a.weekIndex.compareTo(b.weekIndex);
      if (weekCmp != 0) return weekCmp;
      int dayCmp = a.weekday.compareTo(b.weekday);
      if (dayCmp != 0) return dayCmp;
      return a.startTime.compareTo(b.startTime);
    });

    return finalCourses;
  }

  /// 全能文本预处理器：处理 JSON 字符串外壳、MHTML 乱码、WebView 转义符
  static String _preprocessInput(String rawInput) {
    String input = rawInput.trim();

    // 1. 如果是被 WebView 导出的带引号包裹的 JSON 字符串，先尝试安全脱壳
    if (input.startsWith('"') && input.endsWith('"') && input.length > 1) {
      try {
        final decoded = jsonDecode(input);
        if (decoded is String) {
          input = decoded;
        }
      } catch (_) {}
    }

    // 2. 解码 MHTML 格式网页保存带来的 quoted-printable 乱码
    if (input.contains('=\r\n') || input.contains('=\n')) {
      input = input.replaceAll('=\r\n', '').replaceAll('=\n', '');
      input = input.replaceAll('=3D', '=');
      input = input.replaceAll('=22', '"');
      input = input.replaceAll('=27', "'");
      input = input.replaceAll('=20', ' ');
    }

    // 3. 极端情况防御：强制反转义仍带有 \\n 或 \\" 的纯文本 HTML（WebView 导出缺陷）
    if (!input.startsWith('{') && !input.startsWith('[')) {
      input = input.replaceAll(r'\n', '\n')
          .replaceAll(r'\t', '  ')
          .replaceAll(r'\"', '"')
          .replaceAll(r"\'", "'");
    }

    return input;
  }

  /// 解析渲染 HTML 中的课程卡片
  static List<CourseItem>? _parseEams5HtmlCards(String input) {
    if (!input.contains('card-view') || !input.contains('columns weekday')) {
      return null;
    }

    final Map<int, int> topToUnit = _buildTopToUnitMap(input);
    List<CourseItem> courses = [];
    final weekdayParts = input.split(RegExp(r'class="columns weekday"'));
    if (weekdayParts.length < 2) return null;

    for (int dayIdx = 1; dayIdx < weekdayParts.length; dayIdx++) {
      int weekday = dayIdx; // 1=周一 … 7=周日
      String dayContent = weekdayParts[dayIdx];
      final cardParts = dayContent.split(RegExp(r'class="card-view common-card'));

      for (int ci = 1; ci < cardParts.length; ci++) {
        String cardRaw = cardParts[ci];
        int topPx = _extractInlineStylePx(cardRaw, 'top');
        int heightPx = _extractInlineStylePx(cardRaw, 'height');
        int startUnitFallback = topToUnit[topPx] ?? _nearestUnit(topToUnit, topPx);
        int endPx = topPx + heightPx - 50;
        int endUnitFallback = topToUnit[endPx] ?? _nearestUnit(topToUnit, endPx);
        if (endUnitFallback < startUnitFallback) endUnitFallback = startUnitFallback;

        final contentMatch = RegExp(
          r'<div class="card-content">(.*?)</div>\s*<button',
          dotAll: true,
        ).firstMatch(cardRaw);
        if (contentMatch == null) continue;

        String contentHtml = contentMatch.group(1) ?? '';
        final pMatch = RegExp(r'<p>(.*?)</p>', dotAll: true).firstMatch(contentHtml);
        if (pMatch == null) continue;
        String pContent = pMatch.group(1) ?? '';

        final brParts = pContent.split(RegExp(r'<br\s*/?>'));
        String courseName = _stripHtml(brParts[0]).trim();
        if (courseName.isEmpty) courseName = '未知课程';

        String afterBr = brParts.length >= 2 ? brParts.sublist(1).join('') : '';
        String plainAfter = afterBr.replaceAll('&nbsp;', ' ').replaceAll(RegExp(r'<[^>]+>'), '');
        String textToParse = plainAfter.trim();

        int startUnit = startUnitFallback;
        int endUnit = endUnitFallback;
        final unitRegex = RegExp(r'(?:\s+)\d+\s*[\(（]([\d,，]+)[\)）]\s*$');
        final unitMatch = unitRegex.firstMatch(textToParse);
        if (unitMatch != null) {
          final unitNums = unitMatch.group(1)!
              .split(RegExp(r'[,，]'))
              .map((s) => int.tryParse(s.trim()) ?? 0)
              .where((n) => n > 0)
              .toList()
            ..sort();
          if (unitNums.isNotEmpty) {
            startUnit = unitNums.first;
            endUnit = unitNums.last;
          }
          textToParse = textToParse.substring(0, unitMatch.start).trim();
        }

        List<String> segments = [];
        int depth = 0;
        int lastIndex = 0;
        for (int i = 0; i < textToParse.length; i++) {
          if (textToParse[i] == '(' || textToParse[i] == '（') {
            depth++;
          } else if (textToParse[i] == ')' || textToParse[i] == '）') {
            depth--;
          } else if (depth == 0 && (textToParse[i] == ',' || textToParse[i] == '，')) {
            segments.add(textToParse.substring(lastIndex, i).trim());
            lastIndex = i + 1;
          }
        }
        if (lastIndex < textToParse.length) {
          segments.add(textToParse.substring(lastIndex).trim());
        }

        int startTime = _unitToTime(startUnit, true);
        int endTime = _unitToTime(endUnit, false);

        for (String seg in segments) {
          if (seg.isEmpty) continue;
          final List<String> weekBrackets = _extractWeekBrackets(seg);
          Set<int> weekSet = {};
          for (final wb in weekBrackets) {
            weekSet.addAll(_parseWeekRange(wb));
          }

          List<int> weekList = weekSet.toList()..sort();
          if (weekList.isEmpty) {
            weekList = List.generate(19, (i) => i + 1);
          }

          String roomRaw = _removeWeekBrackets(seg)
              .replaceAll(RegExp(r'[\n\r]+'), ' ')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          String roomName = roomRaw.isNotEmpty ? roomRaw : '未知教室';

          // 🚀 核心改进：从文本片段中尝试提取教师姓名
          String teacherName = '未知教师';
          // 常见格式：(张三), [李四], {王五}, 或者空括号
          final teacherMatch = RegExp(r'[\(（]([^\d周单双]+)[\)）]').firstMatch(textToParse);
          if (teacherMatch != null) {
            teacherName = teacherMatch.group(1)!.trim();
          } else if (textToParse.contains('教师') || textToParse.contains('讲师')) {
             final tMatch = RegExp(r'(?:教师|讲师)[:：]\s*(\S+)').firstMatch(textToParse);
             if (tMatch != null) teacherName = tMatch.group(1)!;
          }

          for (int week in weekList) {
            courses.add(CourseItem(
              courseName: courseName,
              teacherName: teacherName,
              date: '',
              weekday: weekday,
              startTime: startTime,
              endTime: endTime,
              weekIndex: week,
              roomName: roomName,
              lessonType: '',
            ));
          }
        }
      }
    }
    return courses.isNotEmpty ? courses : null;
  }

  static List<String> _extractWeekBrackets(String text) {
    final results = <String>[];
    int i = 0;
    while (i < text.length) {
      if (text[i] == '(' || text[i] == '（') {
        int depth = 1;
        int j = i + 1;
        while (j < text.length && depth > 0) {
          if (text[j] == '(' || text[j] == '（') {
            depth++;
          } else if (text[j] == ')' || text[j] == '）') depth--;
          j++;
        }
        final content = text.substring(i + 1, j - 1);
        if (content.contains('周')) {
          results.add(content);
        }
        i = j;
      } else {
        i++;
      }
    }
    return results;
  }

  static String _removeWeekBrackets(String text) {
    final buf = StringBuffer();
    int i = 0;
    while (i < text.length) {
      if (text[i] == '(' || text[i] == '（') {
        int depth = 1;
        int j = i + 1;
        while (j < text.length && depth > 0) {
          if (text[j] == '(' || text[j] == '（') {
            depth++;
          } else if (text[j] == ')' || text[j] == '）') depth--;
          j++;
        }
        final content = text.substring(i + 1, j - 1);
        if (content.contains('周')) {
          i = j;
        } else {
          buf.write(text.substring(i, j));
          i = j;
        }
      } else {
        buf.write(text[i]);
        i++;
      }
    }
    return buf.toString();
  }

  static List<int> _parseWeekRange(String raw) {
    String s = raw.replaceAll('周', '').trim();
    List<int> result = [];
    final segments = s.split(RegExp(r'[,，]'));
    for (String seg in segments) {
      seg = seg.trim();
      if (seg.isEmpty) continue;
      bool onlyEven = seg.contains('双');
      bool onlyOdd = seg.contains('单');
      seg = seg.replaceAll(RegExp(r'[（(][双单][）)]'), '').trim();

      if (seg.contains('~') || seg.contains('-')) {
        final rangeParts = seg.split(RegExp(r'[~\-]'));
        if (rangeParts.length >= 2) {
          int? start = int.tryParse(rangeParts[0].trim());
          int? end = int.tryParse(rangeParts[1].trim());
          if (start != null && end != null) {
            for (int w = start; w <= end; w++) {
              if (onlyEven && w % 2 != 0) continue;
              if (onlyOdd && w % 2 == 0) continue;
              result.add(w);
            }
          }
        }
      } else {
        int? w = int.tryParse(seg);
        if (w != null) result.add(w);
      }
    }
    result = result.toSet().toList()..sort();
    return result;
  }

  static Map<int, int> _buildTopToUnitMap(String input) {
    Map<int, int> map = {};
    final unitColMatch = RegExp(
      r'class="columns unit">(.*?)</div>\s*<div class="columns weekday"',
      dotAll: true,
    ).firstMatch(input);
    if (unitColMatch == null) return _defaultTopToUnitMap();

    String unitHtml = unitColMatch.group(1) ?? '';
    int currentTop = 0;
    final divRegex = RegExp(r'<div(?:\s+class="([^"]*)")?[^>]*style="height:\s*(\d+)px[^"]*"[^>]*>');
    for (final m in divRegex.allMatches(unitHtml)) {
      String cls = m.group(1) ?? '';
      int h = int.tryParse(m.group(2) ?? '0') ?? 0;
      if (!cls.contains('rest-time')) {
        int divEnd = m.end;
        String after = unitHtml.substring(divEnd, (divEnd + 30).clamp(0, unitHtml.length));
        final spanMatch = RegExp(r'<span>(\d+)</span>').firstMatch(after);
        if (spanMatch != null) {
          int unit = int.tryParse(spanMatch.group(1) ?? '0') ?? 0;
          if (unit > 0) map[currentTop] = unit;
        }
      }
      currentTop += h;
    }
    return map.isEmpty ? _defaultTopToUnitMap() : map;
  }

  static Map<int, int> _defaultTopToUnitMap() {
    return {0: 1, 60: 2, 130: 3, 190: 4, 360: 5, 420: 6, 480: 7, 540: 8, 660: 9, 720: 10, 780: 11};
  }

  static int _extractInlineStylePx(String html, String prop) {
    final match = RegExp('$prop:\\s*(\\d+)px').firstMatch(html);
    return int.tryParse(match?.group(1) ?? '0') ?? 0;
  }

  static int _nearestUnit(Map<int, int> map, int px) {
    int bestUnit = 1;
    int bestDiff = 9999;
    map.forEach((top, unit) {
      int diff = (top - px).abs();
      if (diff < bestDiff) { bestDiff = diff; bestUnit = unit; }
    });
    return bestUnit;
  }

  static String _stripHtml(String html) {
    return html.replaceAll(RegExp(r'<[^>]+>'), '');
  }

  static List<CourseItem>? _parseEams5TaskActivity(String input) {
    final parts = input.split(RegExp(r'new\s+TaskActivity\s*\('));
    if (parts.length < 2) return null;

    List<CourseItem> courses = [];
    for (int i = 1; i < parts.length; i++) {
      String prevPart = parts[i - 1];
      String currentPart = parts[i];
      String teacherName = '未知教师';
      List<String> names = [];
      final pushRegex = RegExp(r'''actTeacherName\.push\(\s*(?:"([^"]+)"|'([^']+)')\s*\)''');
      final pushMatches = pushRegex.allMatches(prevPart);
      for (var m in pushMatches) {
        String? n = m.group(1) ?? m.group(2);
        if (n != null && n.isNotEmpty && !names.contains(n)) names.add(n);
      }
      if (names.isEmpty) {
        int teacherIdx = prevPart.lastIndexOf(RegExp(r'teachers\s*='));
        if (teacherIdx != -1) {
          String teacherBlock = prevPart.substring(teacherIdx);
          final nameRegex = RegExp(r'''name\s*:\s*(?:"([^"]+)"|'([^']+)')''');
          final nameMatches = nameRegex.allMatches(teacherBlock);
          for (var m in nameMatches) {
            String? n = m.group(1) ?? m.group(2);
            if (n != null && n.isNotEmpty && !names.contains(n)) names.add(n);
          }
        }
      }
      if (names.isNotEmpty) {
        teacherName = names.join(',');
      } else {
        // 🚀 进一步尝试：匹配 `teachers : [ { id:..., name:"XXX" } ]` 或类似结构
        final teachersArrayRegex = RegExp(r'''teachers\s*:\s*\[\s*\{\s*[^}]*name\s*:\s*(?:"([^"]+)"|'([^']+)')''');
        final teachersMatch = teachersArrayRegex.firstMatch(prevPart);
        if (teachersMatch != null) {
          teacherName = teachersMatch.group(1) ?? teachersMatch.group(2) ?? '未知教师';
        }
      }

      int endArgsIdx = currentPart.indexOf(');');
      if (endArgsIdx == -1) continue;

      String argsStr = currentPart.substring(0, endArgsIdx);
      List<String> args = _extractArgs(argsStr);
      int weekIdx = args.indexWhere((s) => s.length >= 20 && s.contains(RegExp(r'^[01]+$')));
      if (weekIdx == -1) continue;

      String validWeeks = args[weekIdx];
      String roomName = weekIdx >= 1 ? args[weekIdx - 1] : '未知教室';
      String courseName = weekIdx >= 3 ? args[weekIdx - 3] : '未知课程';

      if (roomName == 'null' || roomName.isEmpty || roomName.contains('.join')) roomName = '未知教室';
      if (courseName == 'null' || courseName.isEmpty || courseName.contains('.join')) courseName = '未知课程';
      if (teacherName == '未知教师' && weekIdx >= 5) {
        String fallbackTeacher = args[weekIdx - 5];
        if (fallbackTeacher != 'null' && fallbackTeacher.isNotEmpty && !fallbackTeacher.contains('.join')) teacherName = fallbackTeacher;
      }
      courseName = courseName.replaceFirst(RegExp(r'^\(.*?\)\s*'), '').trim();
      if (courseName.isEmpty && weekIdx >= 3) courseName = args[weekIdx - 3];

      String assignmentsStr = currentPart.substring(endArgsIdx);
      final roomRegex = RegExp(r'''room\s*=\s*\{[^}]*name\s*:\s*(?:"([^"]+)"|'([^']+)')''');
      final roomMatch = roomRegex.firstMatch(assignmentsStr);
      if (roomMatch != null) {
        String parsedRoom = roomMatch.group(1) ?? roomMatch.group(2) ?? '';
        if (parsedRoom.isNotEmpty && parsedRoom != 'null') roomName = parsedRoom;
      }

      final activityRegex = RegExp(r'activities\s*\[(\d+)\]\s*\[(\d+)\]');
      final actMatches = activityRegex.allMatches(assignmentsStr);
      Map<int, List<int>> dayToUnits = {};
      for (var m in actMatches) {
        int day = int.tryParse(m.group(1) ?? '') ?? 0;
        int unit = int.tryParse(m.group(2) ?? '') ?? 0;
        if (day > 0 && unit > 0) dayToUnits.putIfAbsent(day, () => []).add(unit);
      }

      for (var entry in dayToUnits.entries) {
        int weekday = entry.key == 0 || entry.key == 7 ? 7 : entry.key;
        List<int> units = entry.value..sort();
        for (int w = 1; w < validWeeks.length; w++) {
          if (validWeeks[w] == '1') {
            courses.add(CourseItem(
              courseName: courseName, teacherName: teacherName, date: '',
              weekday: weekday, startTime: _unitToTime(units.first, true),
              endTime: _unitToTime(units.last, false), weekIndex: w,
              roomName: roomName, lessonType: '',
            ));
          }
        }
      }
    }
    return courses.isNotEmpty ? courses : null;
  }

  static List<String> _extractArgs(String argsStr) {
    List<String> args = [];
    StringBuffer currentArg = StringBuffer();
    bool inQuote = false;
    String quoteChar = '';
    for (int i = 0; i < argsStr.length; i++) {
      String char = argsStr[i];
      if (char == '\\' && inQuote) { i++; if (i < argsStr.length) currentArg.write(argsStr[i]); continue; }
      if (!inQuote && (char == '"' || char == "'")) { inQuote = true; quoteChar = char; continue; }
      if (inQuote && char == quoteChar) { inQuote = false; continue; }
      if (!inQuote && char == ',') { args.add(currentArg.toString().trim()); currentArg.clear(); continue; }
      currentArg.write(char);
    }
    if (currentArg.isNotEmpty) args.add(currentArg.toString().trim());
    return args;
  }

  /// 通用 JSON 结构解析 (兼容原生 EAMS5 与聚在工大结构)
  static List<CourseItem> _parseJson(Map<String, dynamic> data) {
    final lessonList = data['lessonList'] as List? ?? [];
    final scheduleList = data['scheduleList'] as List? ?? [];
    
    print('[HfutParser] Parsing JSON: ${lessonList.length} lessons, ${scheduleList.length} schedules');

    // 【修改点】使用 String 作为 Key，防止 `int` 和 `String` 的隐式类型崩溃异常
    Map<String, dynamic> lessonMap = {};
    Map<String, String> teacherMap = {};

    for (var item in lessonList) {
      if (item['id'] != null) {
        String lessonId = item['id'].toString();
        lessonMap[lessonId] = item;

        // 核心：从 EAMS5 原生结构的 teacherAssignmentList 提取教师名称
        List<String> teachers = [];
        final assignments = item['teacherAssignmentList'] as List?;
        if (assignments != null) {
          for (var assign in assignments) {
            if (assign['name'] != null) {
              teachers.add(assign['name'].toString().trim());
            }
          }
        }
        if (teachers.isNotEmpty) {
          teacherMap[lessonId] = teachers.join(', ');
          print('[HfutParser] Lesson $lessonId teachers found: ${teacherMap[lessonId]}');
        } else {
          print('[HfutParser] Lesson $lessonId NO teachers in teacherAssignmentList');
          // Try another fallback for teacher name inside lesson item
          if (item['teacherNames'] != null) {
            teacherMap[lessonId] = item['teacherNames'].toString();
            print('[HfutParser] Using fallback teacherNames: ${teacherMap[lessonId]}');
          } else if (item['teachers'] != null && item['teachers'] is List) {
            String names = (item['teachers'] as List).map((t) => t['name']?.toString() ?? '').where((n) => n.isNotEmpty).join(', ');
            if (names.isNotEmpty) {
              teacherMap[lessonId] = names;
              print('[HfutParser] Using fallback teachers list: $names');
            }
          }
        }
      }
    }

    List<CourseItem> courses = [];
    for (var schedule in scheduleList) {
      String? lessonId;
      // 【修改点】兼容不同版本的 schedule 结构取 id (防空指针)
      if (schedule['lessonId'] != null) {
        lessonId = schedule['lessonId'].toString();
      } else if (schedule['lesson'] != null && schedule['lesson']['id'] != null) {
        lessonId = schedule['lesson']['id'].toString();
      }

      if (lessonId != null) {
        final lessonInfo = lessonMap[lessonId];
        if (lessonInfo != null) {
          String roomName = schedule['room'] != null ? (schedule['room']['nameZh'] ?? schedule['room']['name'] ?? '未知教室') : '未知教室';

          // 优先使用聚在结构的 schedule['personName']，如果为空，则使用刚才提取的 teacherMap 原生数据
          String teacherName = schedule['personName']?.toString() ?? teacherMap[lessonId] ?? '未知教师';
          if (teacherName == '未知教师' || teacherName.isEmpty) {
            print('[HfutParser] Warning: Missing teacher for schedule of lesson $lessonId');
          }
          if (teacherName.isEmpty || teacherName == 'null') teacherName = '未知教师';

          courses.add(CourseItem(
            courseName: lessonInfo['courseName']?.toString().trim() ?? '未知课程',
            teacherName: teacherName,
            date: schedule['date']?.toString() ?? '',
            weekday: (schedule['weekday'] as num?)?.toInt() ?? 1,
            startTime: (schedule['startTime'] as num?)?.toInt() ?? 0,
            endTime: (schedule['endTime'] as num?)?.toInt() ?? 0,
            weekIndex: (schedule['weekIndex'] as num?)?.toInt() ?? 1,
            roomName: roomName,
            lessonType: schedule['lessonType']?.toString() ?? '',
          ));
        }
      }
    }

    courses.sort((a, b) {
      int dateCmp = a.date.compareTo(b.date);
      return dateCmp != 0 ? dateCmp : a.startTime.compareTo(b.startTime);
    });

    return courses;
  }

  static Map<String, dynamic>? _extractData(String input) {
    try {
      final data = jsonDecode(input);
      if (data is Map) {
        if (data['result'] != null && data['result']['lessonList'] != null) return {'lessonList': data['result']['lessonList'], 'scheduleList': data['result']['scheduleList'] ?? []};
        if (data['lessonList'] != null) return {'lessonList': data['lessonList'], 'scheduleList': data['scheduleList'] ?? []};
      }
    } catch (_) {}
    try {
      final lessonListStr = _extractArray(input, 'lessonList');
      final scheduleListStr = _extractArray(input, 'scheduleList');
      if (lessonListStr != null && scheduleListStr != null) return {'lessonList': jsonDecode(lessonListStr), 'scheduleList': jsonDecode(scheduleListStr)};
    } catch (_) {}
    return null;
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
      if (inString) { if (char == quoteChar) inString = false; continue; }
      if (char == '"' || char == "'") { inString = true; quoteChar = char; continue; }
      if (char == '[') depth++;
      if (char == ']') { depth--; if (depth == 0) return input.substring(start, i + 1); }
    }
    return null;
  }

  static int _unitToTime(int unit, bool isStart) {
    Map<int, int> startTimes = {1: 800, 2: 900, 3: 1010, 4: 1110, 5: 1400, 6: 1500, 7: 1600, 8: 1700, 9: 1900, 10: 2000, 11: 2100};
    Map<int, int> endTimes = {1: 850, 2: 950, 3: 1100, 4: 1200, 5: 1450, 6: 1550, 7: 1650, 8: 1750, 9: 1950, 10: 2050, 11: 2130};
    return isStart ? (startTimes[unit] ?? 0) : (endTimes[unit] ?? 0);
  }
}