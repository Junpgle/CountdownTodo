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
            // 🚀 修复：采用最新的版本提升函数替换直接修改 lastUpdated
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
    // --- 提取并排序最紧急的待办 ---

    // 1. 我们只想要展示未完成且未被逻辑删除的待办
    List<TodoItem> pendingTodos = todos.where((t) => !t.isDone && !t.isDeleted).toList();

    DateTime now = DateTime.now();
    DateTime todayStart = DateTime(now.year, now.month, now.day);
    DateTime todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    // 辅助函数：判断待办是否与今天相关 (创建在今天 或 截止在今天，甚至跨越今天)
    bool isTodayRelevant(TodoItem todo) {
      // 🚀 修正：优先使用 createdDate，兼容旧数据 fallback 到 createdAt
      DateTime cDate = DateTime.fromMillisecondsSinceEpoch(todo.createdDate ?? todo.createdAt);
      if (todo.dueDate != null) {
        DateTime dueDateStart = DateTime(todo.dueDate!.year, todo.dueDate!.month, todo.dueDate!.day);
        // 🚀 修复：将 createdAt int 转为 DateTime 做比较
        if (!todayEnd.isBefore(DateTime(cDate.year, cDate.month, cDate.day)) &&
            !todayStart.isAfter(dueDateStart)) {
          return true;
        }
      } else {
        // 如果没有截止时间，只看是不是今天创建的
        if (cDate.year == now.year && cDate.month == now.month && cDate.day == now.day) {
          return true;
        }
      }
      return false;
    }

    // 2. 自定义排序逻辑
    pendingTodos.sort((a, b) {
      bool aToday = isTodayRelevant(a);
      bool bToday = isTodayRelevant(b);

      // 第一优先级：今天相关的排在前面
      if (aToday && !bToday) return -1;
      if (!aToday && bToday) return 1;

      // 如果同为今天相关，或者同不为今天相关，则继续按截止时间排序
      if (a.dueDate != null && b.dueDate != null) {
        return a.dueDate!.compareTo(b.dueDate!);
      }
      if (a.dueDate != null && b.dueDate == null) return -1;
      if (a.dueDate == null && b.dueDate != null) return 1;

      // 都没有截止日期：按创建时间 (int) 排序，数字小的（早的）在前
      return a.createdAt.compareTo(b.createdAt);
    });

    // 3. 截取前 3 条作为要在小部件显示的项
    final displayTodos = pendingTodos.take(3).toList();
    // ---------------------------------

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