import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import '../models.dart';
import '../storage_service.dart';

// 必须是顶级函数或静态函数，供原生后台调用
@pragma('vm:entry-point')
Future<void> widgetBackgroundCallback(Uri? uri) async {
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
            t.lastUpdated = DateTime.now();
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

  // 必须在 App 启动时调用，以注册这个后台监听器
  static Future<void> init() async {
    if (_initialized) return;
    try {
      await HomeWidget.registerBackgroundCallback(widgetBackgroundCallback);
      _initialized = true;
    } catch (e) {
      print('WidgetBackground 注册失败: $e');
    }
  }

  static Future<void> updateTodoWidget(List<TodoItem> todos) async {
    // 拿列表前 3 条（无论是否已完成）
    final displayTodos = todos.take(3).toList();

    // 清空旧数据（标题、是否完成、ID）
    for (int i = 1; i <= 3; i++) {
      await HomeWidget.saveWidgetData<String>('todo_$i', '');
      await HomeWidget.saveWidgetData<bool>('todo_${i}_done', false);
      await HomeWidget.saveWidgetData<String>('todo_${i}_id', '');
    }

    // 写入新数据
    for (int i = 0; i < displayTodos.length; i++) {
      final todo = displayTodos[i];
      await HomeWidget.saveWidgetData<String>('todo_${i + 1}', todo.title);
      await HomeWidget.saveWidgetData<bool>('todo_${i + 1}_done', todo.isDone);
      await HomeWidget.saveWidgetData<String>('todo_${i + 1}_id', todo.id);
    }

    // 触发 Android 原生刷新
    await HomeWidget.updateWidget(
      androidName: androidWidgetName,
    );
  }
}