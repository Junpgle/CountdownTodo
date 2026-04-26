import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../storage_service.dart';
import 'course_service.dart';
import 'pomodoro_service.dart';

@pragma('vm:entry-point')
Future<void> widgetBackgroundCallback(Uri? uri) async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  if (uri != null && uri.scheme == 'todowidget' && uri.host == 'markdone') {
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    if (id != null) {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString(StorageService.KEY_CURRENT_USER) ?? '';
      if (username.isNotEmpty) {
        List<TodoItem> todos = await StorageService.getTodos(username);
        bool changed = false;
        for (var t in todos) {
          if (t.id == id) {
            t.isDone = !t.isDone;
            t.markAsChanged();
            changed = true;
            break;
          }
        }
        if (changed) {
          todos.sort((a, b) => a.isDone == b.isDone ? 0 : (a.isDone ? 1 : -1));
          await StorageService.saveTodos(username, todos);
          await WidgetService.updateAllWidgetData(username, todos);
        }
      }
    }
  }
}

class WidgetService {
  static const String androidWidgetName = 'TodoWidgetProvider';
  static bool _initialized = false;
  static bool _widgetUpdateDisabled = false;
  static const int maxWidgetItems = 8;
  static Timer? _periodicTimer;

  static Future<void> dispose() async {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  static Future<void> init() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (_initialized) return;
    try {
      await HomeWidget.registerInteractivityCallback(widgetBackgroundCallback);
      _initialized = true;
    } catch (e) {
      print('WidgetBackground 注册失败: $e');
    }

    // 启动 15 分钟一次的周期刷新（确保在应用运行期间定期更新 widget，减少能耗）
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(minutes: 15), (timer) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final username = prefs.getString(StorageService.KEY_CURRENT_USER) ?? '';
        if (username.isEmpty) return;
        final todos = await StorageService.getTodos(username);
        await WidgetService.updateAllWidgetData(username, todos);
      } catch (e) {
        print('Widget periodic refresh error: $e');
      }
    });

    // 立即触发一次更新
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString(StorageService.KEY_CURRENT_USER) ?? '';
      if (username.isNotEmpty) {
        final todos = await StorageService.getTodos(username);
        await updateAllWidgetData(username, todos);
      }
    } catch (e) {
      print('Widget initial update error: $e');
    }
  }

  static String _getDueDateLabel(DateTime? dueDate) {
    if (dueDate == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final diffDays = dueDay.difference(today).inDays;
    if (diffDays < 0) {
      return '已逾期';
    } else if (diffDays == 0)
      return '今天 ${dueDate.hour.toString().padLeft(2, '0')}:${dueDate.minute.toString().padLeft(2, '0')}';
    else if (diffDays == 1)
      return '明天';
    else
      return '$diffDays天后';
  }

  static Future<void> updateAllWidgetData(
      String username, List<TodoItem> todos) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (_widgetUpdateDisabled) return;
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);

    final results = await Future.wait([
      Future.value(todos),
      CourseService.getAllCourses(username),
      StorageService.getCountdowns(username),
      StorageService.getTimeLogs(username),
      PomodoroService.getTodayRecords(),
      PomodoroService.getTags(),
    ]);

    final List<TodoItem> allTodos = results[0] as List<TodoItem>;
    final List<CourseItem> allCourses = results[1] as List<CourseItem>;
    final List<CountdownItem> countdownsRaw = results[2] as List<CountdownItem>;
    final List<TimeLogItem> tlogsRaw = results[3] as List<TimeLogItem>;
    final List<PomodoroRecord> pomsRaw = results[4] as List<PomodoroRecord>;
    final List<PomodoroTag> allTags = results[5] as List<PomodoroTag>;

    // 🛡️ OOM 修复：在主线程对数据做预过滤和字段裁剪，只把轻量 Map 传给 compute()
    // 避免将全量 Dart 对象列表序列化后跨 Isolate 边界导致内存溢出（数据用久后可达 100MB+）

    // 1. 待办：只保留未完成未删除的条目，且只取 Isolate 实际用到的字段
    final List<Map<String, dynamic>> slimTodos = allTodos
        .where((t) => !t.isDone && !t.isDeleted)
        .map((t) => {
              'title': t.title,
              'isDone': t.isDone,
              'id': t.id,
              'dueDate': t.dueDate?.millisecondsSinceEpoch,
              'createdDate': t.createdDate,
              'createdAt': t.createdAt,
            })
        .toList();

    // 2. 课程：只保留未来 14 天内的
    final DateTime courseLimit = now.add(const Duration(days: 14));
    final List<Map<String, dynamic>> slimCourses = allCourses
        .where((c) {
          try {
            final cDate = DateFormat('yyyy-MM-dd').parse(c.date);
            final cEnd = cDate.add(Duration(
                hours: c.endTime ~/ 100, minutes: c.endTime % 100));
            return cEnd.isAfter(now) && cDate.isBefore(courseLimit);
          } catch (_) {
            return false;
          }
        })
        .map((c) => {
              'date': c.date,
              'courseName': c.courseName,
              'startTime': c.startTime,
              'endTime': c.endTime,
              'roomName': c.roomName,
              'formattedStartTime': c.formattedStartTime,
              'formattedEndTime': c.formattedEndTime,
            })
        .toList();

    // 3. 倒数日：只保留未删除且未过期的
    final List<Map<String, dynamic>> slimCountdowns = countdownsRaw
        .where((c) =>
            !c.isDeleted &&
            c.targetDate.difference(today).inDays >= 0)
        .map((c) => {
              'title': c.title,
              'targetDateMs': c.targetDate.millisecondsSinceEpoch,
            })
        .toList();

    // 4. 时间日志：只保留今日未删除的条目，且只取 Isolate 用到的字段
    final Map<String, String> tagNameByUuid = {
      for (var t in allTags) t.uuid: t.name
    };
    final List<Map<String, dynamic>> slimTimeLogs = tlogsRaw
        .where((l) {
          if (l.isDeleted) return false;
          final d = DateTime.fromMillisecondsSinceEpoch(l.startTime,
                  isUtc: true)
              .toLocal();
          return d.year == today.year &&
              d.month == today.month &&
              d.day == today.day;
        })
        .map((l) => {
              'title': l.title,
              'startTime': l.startTime,
              'endTime': l.endTime,
              'tagNames': l.tagUuids
                  .map((u) => tagNameByUuid[u] ?? u)
                  .toList(),
            })
        .toList();

    // 5. 番茄钟：只保留今日未删除的条目
    final List<Map<String, dynamic>> slimPoms = pomsRaw
        .where((p) {
          if (p.isDeleted) return false;
          final d = DateTime.fromMillisecondsSinceEpoch(p.startTime,
                  isUtc: true)
              .toLocal();
          return d.year == today.year &&
              d.month == today.month &&
              d.day == today.day;
        })
        .map((p) => {
              'todoTitle': p.todoTitle,
              'startTime': p.startTime,
              'endTime': p.endTime,
              'actualDuration': p.actualDuration,
              'plannedDuration': p.plannedDuration,
              'tagNames': p.tagUuids
                  .map((u) => tagNameByUuid[u] ?? u)
                  .toList(),
            })
        .toList();

    // 只传轻量的 primitive Map 给 Isolate，彻底避免大对象序列化
    final Map<String, dynamic> rawInput = {
      'now': now.millisecondsSinceEpoch,
      'todos': slimTodos,
      'courses': slimCourses,
      'countdowns': slimCountdowns,
      'timelogs': slimTimeLogs,
      'poms': slimPoms,
    };

    final Map<String, dynamic> widgetData =
        await compute(_prepareWidgetDataIsolate, rawInput);

    // 批量写入结果
    final List<Future<void>> widgetWrites = [];
    widgetData.forEach((key, value) {
      widgetWrites.add(HomeWidget.saveWidgetData(key, value));
    });

    await Future.wait(widgetWrites);
    try {
      await HomeWidget.updateWidget(androidName: androidWidgetName);
    } catch (e) {
      final message = e.toString();
      if (Platform.isAndroid &&
          (message.contains('TodoWidgetProvider') ||
              message.contains('ClassNotFoundException'))) {
        _widgetUpdateDisabled = true;
        debugPrint(
            '⚠️ [WidgetService] Android Widget provider unavailable in current build; disable further widget updates.');
        return;
      }
      debugPrint('⚠️ [WidgetService] Android Widget update suppressed: $e');
    }
  }

  /// Isolate 内部逻辑：处理所有 Widget 展现逻辑
  /// 注意：入参均为轻量 Map（primitive），不含 Dart 模型类对象
  static Map<String, dynamic> _prepareWidgetDataIsolate(Map<String, dynamic> input) {
    final now = DateTime.fromMillisecondsSinceEpoch(input['now'] as int);
    final today = DateTime(now.year, now.month, now.day);
    final List<Map<String, dynamic>> allTodos =
        (input['todos'] as List).cast<Map<String, dynamic>>();
    final List<Map<String, dynamic>> allCourses =
        (input['courses'] as List).cast<Map<String, dynamic>>();
    final List<Map<String, dynamic>> countdownsRaw =
        (input['countdowns'] as List).cast<Map<String, dynamic>>();
    final List<Map<String, dynamic>> tlogsRaw =
        (input['timelogs'] as List).cast<Map<String, dynamic>>();
    final List<Map<String, dynamic>> pomsRaw =
        (input['poms'] as List).cast<Map<String, dynamic>>();

    final Map<String, dynamic> resultData = {};

    // 1. 待办事项处理（主线程已过滤掉 isDone/isDeleted，这里直接分组排序）
    final List<Map<String, dynamic>> pastTodos = [];
    final List<Map<String, dynamic>> todayTodos = [];
    final List<Map<String, dynamic>> futureTodos = [];
    for (final t in allTodos) {
      final dueDateMs = t['dueDate'] as int?;
      if (dueDateMs != null) {
        final d = DateTime.fromMillisecondsSinceEpoch(dueDateMs);
        final dDay = DateTime(d.year, d.month, d.day);
        if (dDay.isBefore(today)) {
          pastTodos.add(t);
        } else if (dDay.isAfter(today)) {
          futureTodos.add(t);
        } else {
          todayTodos.add(t);
        }
      } else {
        todayTodos.add(t);
      }
    }
    int startMs(Map<String, dynamic> t) =>
        (t['createdDate'] as int?) ?? (t['createdAt'] as int? ?? 0);
    int compareUrgency(Map<String, dynamic> a, Map<String, dynamic> b) {
      final aMs = a['dueDate'] as int?;
      final bMs = b['dueDate'] as int?;
      if (aMs != null && bMs != null) return aMs.compareTo(bMs);
      if (aMs != null && bMs == null) return -1;
      if (aMs == null && bMs != null) return 1;
      return startMs(a).compareTo(startMs(b));
    }
    pastTodos.sort(compareUrgency);
    todayTodos.sort(compareUrgency);
    futureTodos.sort(compareUrgency);
    final displayTodos =
        [...pastTodos, ...todayTodos, ...futureTodos].take(maxWidgetItems).toList();

    for (int i = 1; i <= maxWidgetItems; i++) {
      resultData['todo_$i'] = '';
      resultData['todo_${i}_done'] = false;
      resultData['todo_${i}_id'] = '';
      resultData['todo_${i}_due'] = '';
    }
    for (int i = 0; i < displayTodos.length; i++) {
      final todo = displayTodos[i];
      final dueDateMs = todo['dueDate'] as int?;
      String title = todo['title'] as String? ?? '';
      DateTime? dueDate;
      if (dueDateMs != null) dueDate = DateTime.fromMillisecondsSinceEpoch(dueDateMs);
      final isDueToday = dueDate == null ||
          !DateTime(dueDate.year, dueDate.month, dueDate.day).isAfter(today);
      if (isDueToday) title = '<b>$title</b>';
      resultData['todo_${i + 1}'] = title;
      resultData['todo_${i + 1}_done'] = todo['isDone'] as bool? ?? false;
      resultData['todo_${i + 1}_id'] = todo['id'] as String? ?? '';
      resultData['todo_${i + 1}_due'] = _getDueDateLabelFromMs(dueDateMs);
    }

    // 2. 课程处理（主线程已过滤为未来 14 天内）
    String urgentCourseId = '';
    for (int i = 1; i <= maxWidgetItems; i++) {
      resultData['course_date_$i'] = '';
      resultData['course_name_$i'] = '';
      resultData['course_time_$i'] = '';
      resultData['course_room_$i'] = '';
      resultData['course_id_$i'] = '';
    }
    try {
      final df = DateFormat('yyyy-MM-dd');
      final sortedCourses = List<Map<String, dynamic>>.from(allCourses)
        ..sort((a, b) {
          final dateCmp = (a['date'] as String).compareTo(b['date'] as String);
          if (dateCmp != 0) return dateCmp;
          return (a['startTime'] as int).compareTo(b['startTime'] as int);
        });
      final displayCourses = sortedCourses.take(maxWidgetItems).toList();
      for (int i = 0; i < displayCourses.length; i++) {
        final course = displayCourses[i];
        final courseDate = df.parse(course['date'] as String);
        final diffDays =
            DateTime(courseDate.year, courseDate.month, courseDate.day)
                .difference(today)
                .inDays;
        final String dayLabel = diffDays == 0
            ? '今天'
            : (diffDays == 1 ? '明天' : (diffDays == 2 ? '后天' : '$diffDays天后'));
        String fullDateHeader = '$dayLabel | ${courseDate.month}月${courseDate.day}日';
        String cName = course['courseName'] as String? ?? '';
        if (diffDays == 0) {
          fullDateHeader = '<b>$fullDateHeader</b>';
          cName = '<b>$cName</b>';
        }
        final startTime = course['startTime'] as int;
        final cId = '${course['courseName']}_${course['date']}_$startTime';
        resultData['course_date_${i + 1}'] = fullDateHeader;
        resultData['course_name_${i + 1}'] = cName;
        resultData['course_time_${i + 1}'] =
            '${course['formattedStartTime']} - ${course['formattedEndTime']}';
        resultData['course_room_${i + 1}'] = '@${course['roomName']}';
        resultData['course_id_${i + 1}'] = cId;
        if (urgentCourseId.isEmpty) {
          final cStart = courseDate.add(
              Duration(hours: startTime ~/ 100, minutes: startTime % 100));
          if (cStart.isAfter(now) && cStart.difference(now).inMinutes <= 30) {
            urgentCourseId = cId;
          }
        }
      }
    } catch (_) {}
    resultData['urgent_course_id'] = urgentCourseId;

    // 3. 倒数日（主线程已过滤未过期）
    final sortedCountdowns = List<Map<String, dynamic>>.from(countdownsRaw)
      ..sort((a, b) =>
          (a['targetDateMs'] as int).compareTo(b['targetDateMs'] as int));
    for (int i = 1; i <= maxWidgetItems; i++) {
      resultData['cd_title_$i'] = '';
      resultData['cd_days_$i'] = '';
    }
    for (int i = 0; i < sortedCountdowns.length && i < maxWidgetItems; i++) {
      final cd = sortedCountdowns[i];
      final targetDate =
          DateTime.fromMillisecondsSinceEpoch(cd['targetDateMs'] as int);
      final diff =
          DateTime(targetDate.year, targetDate.month, targetDate.day)
              .difference(today)
              .inDays;
      final title = cd['title'] as String? ?? '';
      resultData['cd_title_${i + 1}'] = diff == 0 ? '<b>$title</b>' : title;
      resultData['cd_days_${i + 1}'] = diff == 0 ? '就在今天' : '还有 $diff 天';
    }

    // 4. 专注日志统计（主线程已过滤为今日数据，tagNames 已展开为字符串列表）
    try {
      final List<Map<String, dynamic>> merged = [];
      for (final l in tlogsRaw) {
        final start = l['startTime'] as int;
        final end = l['endTime'] as int? ?? 0;
        if (end <= start) continue;
        merged.add({
          'title': ((l['title'] as String? ?? '').isNotEmpty) ? l['title'] : '专注任务',
          'start': start,
          'minutes': (end - start) ~/ 60000,
          'tagNames': (l['tagNames'] as List<dynamic>?) ?? [],
        });
      }
      for (final p in pomsRaw) {
        final start = p['startTime'] as int;
        final end = p['endTime'] as int? ??
            (start +
                ((p['actualDuration'] as int?) ??
                        (p['plannedDuration'] as int? ?? 0)) *
                    1000);
        if (end <= start) continue;
        merged.add({
          'title': (p['todoTitle'] as String?) ?? '专注任务',
          'start': start,
          'minutes': (end - start) ~/ 60000,
          'tagNames': (p['tagNames'] as List<dynamic>?) ?? [],
        });
      }
      merged.sort((a, b) => (b['start'] as int).compareTo(a['start'] as int));
      final totalMins =
          merged.fold<int>(0, (s, e) => s + (e['minutes'] as int));
      resultData['tl_total'] = '今日总专注: $totalMins 分钟';

      final Map<String, double> tagMinutes = {};
      for (final entry in merged) {
        final mins = (entry['minutes'] as int).toDouble();
        final tagNames = entry['tagNames'] as List<dynamic>;
        if (tagNames.isEmpty) {
          tagMinutes['未分类'] = (tagMinutes['未分类'] ?? 0) + mins;
        } else {
          final per = mins / tagNames.length;
          for (final name in tagNames) {
            final key = name as String;
            tagMinutes[key] = (tagMinutes[key] ?? 0) + per;
          }
        }
      }
      final tagEntries = tagMinutes.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (int i = 1; i <= maxWidgetItems; i++) {
        resultData['tl_tag_name_$i'] = '';
        resultData['tl_tag_mins_$i'] = '';
        resultData['tl_title_$i'] = '';
        resultData['tl_time_$i'] = '';
      }
      resultData['tl_tag_count'] = '${tagEntries.length}';
      for (int i = 0; i < tagEntries.length && i < maxWidgetItems; i++) {
        resultData['tl_tag_name_${i + 1}'] = tagEntries[i].key;
        resultData['tl_tag_mins_${i + 1}'] = '${tagEntries[i].value.round()}分';
      }
      for (int i = 0; i < merged.length && i < maxWidgetItems; i++) {
        resultData['tl_title_${i + 1}'] = merged[i]['title'];
        resultData['tl_time_${i + 1}'] = '${merged[i]['minutes']}分钟';
      }
    } catch (_) {}

    // 5. 专注状态判断
    resultData['widget_mode'] = urgentCourseId.isNotEmpty ? 'course' : 'todo';
    return resultData;
  }

  /// 根据 dueDate 毫秒时间戳生成显示标签
  static String _getDueDateLabelFromMs(int? dueDateMs) {
    if (dueDateMs == null) return '';
    return _getDueDateLabel(DateTime.fromMillisecondsSinceEpoch(dueDateMs));
  }


  static Future<void> updateTodoWidget(List<TodoItem> todos) async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString(StorageService.KEY_CURRENT_USER) ?? '';
    await updateAllWidgetData(username, todos);
  }
}
