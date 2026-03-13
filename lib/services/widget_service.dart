import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import '../models.dart';
import '../storage_service.dart';

// 必须是顶级函数或静态函数，供原生后台调用
@pragma('vm:entry-point')
Future<void> widgetBackgroundCallback(Uri? uri) async {
  // 🚀 桌面端拦截
  if (!Platform.isAndroid && !Platform.isIOS) return;

  if (uri != null && uri.scheme == 'todowidget' && uri.host == 'markdone') {
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;

    if (id != null) {
      // 1. 获取当前登录用户
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString(StorageService.KEY_CURRENT_USER) ?? '';

      if (username.isNotEmpty) {
        // 2. 从本地读取所有待办
        List<TodoItem> todos = await StorageService.getTodos(username);
        bool changed = false;

        // 3. 找到目标任务并翻转状态
        for (var t in todos) {
          if (t.id == id) {
            t.isDone = !t.isDone;
            t.markAsChanged();
            changed = true;
            break;
          }
        }

        // 4. 如果修改成功，重新排序并保存，最后刷新小部件
        if (changed) {
          todos.sort((a, b) => a.isDone == b.isDone ? 0 : (a.isDone ? 1 : -1));
          await StorageService.saveTodos(username, todos);
          await WidgetService.updateTodoWidget(todos);
        }
      }
    }
  }
}

class WidgetService {
  static const String androidWidgetName = 'TodoWidgetProvider';
  static bool _initialized = false;

  static const int maxWidgetItems = 8; // 最大渲染数量

  static Future<void> init() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    if (_initialized) return;
    try {
      await HomeWidget.registerBackgroundCallback(widgetBackgroundCallback);
      _initialized = true;
    } catch (e) {
      print('WidgetBackground 注册失败: $e');
    }
  }

  // 🚀 智能日期推断文本
  static String _getDueDateLabel(DateTime? dueDate) {
    if (dueDate == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final diffDays = dueDay.difference(today).inDays;

    if (diffDays < 0) {
      return '已逾期';
    } else if (diffDays == 0) {
      return '今天 ${dueDate.hour.toString().padLeft(2, '0')}:${dueDate.minute.toString().padLeft(2, '0')}';
    } else if (diffDays == 1) {
      return '明天';
    } else {
      return '$diffDays天后';
    }
  }

  static Future<void> updateTodoWidget(List<TodoItem> todos) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    // 1. 我们只想要展示未完成且未被逻辑删除的待办
    List<TodoItem> pendingTodos = todos.where((t) => !t.isDone && !t.isDeleted).toList();

    // 2. 🚀 完全采用主页的轻重缓急分组逻辑：以往(逾期) -> 今日 -> 未来
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);

    List<TodoItem> pastTodos = [];
    List<TodoItem> todayTodos = [];
    List<TodoItem> futureTodos = [];

    for (final t in pendingTodos) {
      if (t.dueDate != null) {
        DateTime d = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
        if (d.isBefore(today)) {
          pastTodos.add(t);
        } else if (d.isAfter(today)) {
          futureTodos.add(t);
        } else {
          todayTodos.add(t);
        }
      } else {
        // 与主页保持一致，没有明确截止时间的统一放在“今日待办”
        todayTodos.add(t);
      }
    }

    // 组内排序规则：优先按截止时间排序(最紧急的在前)，如果没有截止时间则按创建时间排
    int startMs(TodoItem t) => t.createdDate ?? t.createdAt;

    int compareUrgency(TodoItem a, TodoItem b) {
      // 都有明确时间的，早的排在前面
      if (a.dueDate != null && b.dueDate != null) {
        return a.dueDate!.compareTo(b.dueDate!);
      }
      // 有明确时间的比没有时间的排在前面（更有压迫感）
      if (a.dueDate != null && b.dueDate == null) return -1;
      if (a.dueDate == null && b.dueDate != null) return 1;
      // 都没有时间，按创建先后排
      return startMs(a).compareTo(startMs(b));
    }

    pastTodos.sort(compareUrgency);
    todayTodos.sort(compareUrgency);
    futureTodos.sort(compareUrgency);

    // 3. 严格拼接：逾期最前，今日次之，未来最后
    final displayTodos = [...pastTodos, ...todayTodos, ...futureTodos].take(maxWidgetItems).toList();

    // 清空旧数据
    for (int i = 1; i <= maxWidgetItems; i++) {
      await HomeWidget.saveWidgetData<String>('todo_$i', '');
      await HomeWidget.saveWidgetData<bool>('todo_${i}_done', false);
      await HomeWidget.saveWidgetData<String>('todo_${i}_id', '');
      await HomeWidget.saveWidgetData<String>('todo_${i}_due', '');
    }

    // 写入新数据
    for (int i = 0; i < displayTodos.length; i++) {
      final todo = displayTodos[i];
      await HomeWidget.saveWidgetData<String>('todo_${i + 1}', todo.title);
      await HomeWidget.saveWidgetData<bool>('todo_${i + 1}_done', todo.isDone);
      await HomeWidget.saveWidgetData<String>('todo_${i + 1}_id', todo.id);
      await HomeWidget.saveWidgetData<String>('todo_${i + 1}_due', _getDueDateLabel(todo.dueDate));
    }

    // 触发 Android 原生刷新
    await HomeWidget.updateWidget(
      androidName: androidWidgetName,
    );
  }
}