import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import '../storage_service.dart';
import '../screens/historical_todos_screen.dart';
import 'home_sections.dart';

class TodoSectionWidget extends StatefulWidget {
  final List<TodoItem> todos;
  final String username;
  final bool isLight;
  final Function(List<TodoItem>) onTodosChanged;
  final VoidCallback onRefreshRequested;

  const TodoSectionWidget({
    super.key,
    required this.todos,
    required this.username,
    required this.isLight,
    required this.onTodosChanged,
    required this.onRefreshRequested,
  });

  @override
  State<TodoSectionWidget> createState() => TodoSectionWidgetState();
}

class TodoSectionWidgetState extends State<TodoSectionWidget> {
  /// 整个待办清单区块是否展开（顶部三角控制）
  bool _isWholeListExpanded = true;
  /// 今日待办子区块是否展开（自动折叠后可手动重新展开）
  bool _isTodayExpanded = true;
  /// 今日是否被用户手动展开（覆盖自动折叠）
  bool _isTodayManuallyExpanded = false;
  bool _isPastTodosExpanded = false;
  bool _isFutureExpanded = true;
  bool _hasInitializedExpansion = false;

  final Map<String, Key> _todoKeys = {};

  Key _getTodoKey(String idPrefix, String todoId) {
    String mapKey = '${idPrefix}_$todoId';
    _todoKeys.putIfAbsent(mapKey, () => UniqueKey());
    return _todoKeys[mapKey]!;
  }

  @override
  void didUpdateWidget(TodoSectionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_hasInitializedExpansion && widget.todos.isNotEmpty) {
      _isTodayExpanded = !widget.todos.where((t) => !_isHistoricalTodo(t)).every((t) => t.isDone);
      _hasInitializedExpansion = true;
    }
  }

  bool _isHistoricalTodo(TodoItem t) {
    if (!t.isDone) return false;
    DateTime today = DateTime.now();
    today = DateTime(today.year, today.month, today.day);
    if (t.dueDate != null) {
      DateTime d = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
      return d.isBefore(today);
    } else {
      // 🚀 修正：优先使用 createdDate，兼容旧数据 fallback 到 createdAt
      DateTime cDate = DateTime.fromMillisecondsSinceEpoch(t.createdDate ?? t.createdAt);
      DateTime c = DateTime(cDate.year, cDate.month, cDate.day);
      return c.isBefore(today);
    }
  }

  void showAddTodoDialog() {
    TextEditingController titleCtrl = TextEditingController();
    DateTime createdAt = DateTime.now();
    DateTime? dueDate;
    RecurrenceType recurrence = RecurrenceType.none;
    TextEditingController customDaysCtrl = TextEditingController();
    int? customDays;
    DateTime? recurrenceEndDate;
    bool isAllDay = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("添加待办"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: "待办内容")),
                const SizedBox(height: 10),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("全天事件", style: TextStyle(fontSize: 15)),
                  value: isAllDay,
                  onChanged: (val) {
                    setDialogState(() {
                      isAllDay = val;
                      if (isAllDay) {
                        createdAt = DateTime(createdAt.year, createdAt.month, createdAt.day, 0, 0);
                        if (dueDate != null) {
                          dueDate = DateTime(dueDate!.year, dueDate!.month, dueDate!.day, 23, 59);
                        } else {
                          dueDate = DateTime(createdAt.year, createdAt.month, createdAt.day, 23, 59);
                        }
                      }
                    });
                  },
                ),

                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text("开始时间: ${DateFormat(isAllDay ? 'yyyy-MM-dd' : 'yyyy-MM-dd HH:mm').format(createdAt)}"),
                  trailing: const Icon(Icons.edit_calendar, size: 20),
                  onTap: () async {
                    final pickedDate = await showDatePicker(
                        context: context, firstDate: DateTime(2000), lastDate: DateTime(2100), initialDate: createdAt);
                    if (pickedDate != null) {
                      if (isAllDay) {
                        setDialogState(() => createdAt = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, 0, 0));
                      } else {
                        if (!context.mounted) return;
                        final pickedTime = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(createdAt));
                        if (pickedTime != null) {
                          setDialogState(() => createdAt = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute));
                        }
                      }
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(dueDate == null ? "设置截止时间 (可选)" : "截止时间: ${DateFormat(isAllDay ? 'yyyy-MM-dd' : 'yyyy-MM-dd HH:mm').format(dueDate!)}"),
                  trailing: const Icon(Icons.event, size: 20),
                  onTap: () async {
                    final pickedDate = await showDatePicker(
                        context: context, firstDate: DateTime(2000), lastDate: DateTime(2100), initialDate: dueDate ?? createdAt);
                    if (pickedDate != null) {
                      if (isAllDay) {
                        setDialogState(() => dueDate = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, 23, 59));
                      } else {
                        if (!context.mounted) return;
                        final pickedTime = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(dueDate ?? DateTime.now()));
                        if (pickedTime != null) {
                          setDialogState(() => dueDate = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute));
                        }
                      }
                    }
                  },
                ),
                const Divider(),
                DropdownButtonFormField<RecurrenceType>(
                  value: recurrence, decoration: const InputDecoration(labelText: "循环设置 (可选)"),
                  items: const [
                    DropdownMenuItem(value: RecurrenceType.none, child: Text("不重复")),
                    DropdownMenuItem(value: RecurrenceType.daily, child: Text("每天重复")),
                    DropdownMenuItem(value: RecurrenceType.customDays, child: Text("隔几天重复")),
                  ],
                  onChanged: (val) => setDialogState(() => recurrence = val!),
                ),
                if (recurrence == RecurrenceType.customDays)
                  TextField(controller: customDaysCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "间隔天数"), onChanged: (val) => customDays = int.tryParse(val)),
                if (recurrence != RecurrenceType.none)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(recurrenceEndDate == null ? "循环截止日期 (可选)" : "循环结束: ${DateFormat('yyyy-MM-dd').format(recurrenceEndDate!)}"),
                    trailing: const Icon(Icons.event_busy, size: 20),
                    onTap: () async {
                      final picked = await showDatePicker(
                          context: context, firstDate: DateTime.now(), lastDate: DateTime(2100), initialDate: DateTime.now().add(const Duration(days: 30)));
                      if (picked != null) setDialogState(() => recurrenceEndDate = picked);
                    },
                  )
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
            FilledButton(
              onPressed: () {
                if (titleCtrl.text.isNotEmpty) {
                  final newTodo = TodoItem(
                    title: titleCtrl.text,
                    recurrence: recurrence,
                    customIntervalDays: customDays,
                    recurrenceEndDate: recurrenceEndDate,
                    dueDate: dueDate,
                    createdDate: createdAt.millisecondsSinceEpoch, // 🚀 修正：业务开始时间
                  );
                  List<TodoItem> updatedList = List.from(widget.todos)..insert(0, newTodo);
                  widget.onTodosChanged(updatedList);
                  if (mounted) Navigator.pop(ctx);
                }
              },
              child: const Text("添加"),
            )
          ],
        ),
      ),
    );
  }

  void _editTodo(TodoItem todo) {
    TextEditingController titleCtrl = TextEditingController(text: todo.title);
    // 🚀 修正：优先使用 createdDate，兼容旧数据 fallback 到 createdAt
    DateTime createdAt = DateTime.fromMillisecondsSinceEpoch(todo.createdDate ?? todo.createdAt);
    DateTime? dueDate = todo.dueDate;
    RecurrenceType recurrence = todo.recurrence;
    int? customDays = todo.customIntervalDays;
    TextEditingController customDaysCtrl = TextEditingController(text: customDays?.toString() ?? "");
    DateTime? recurrenceEndDate = todo.recurrenceEndDate;

    bool isAllDay = dueDate != null && createdAt.hour == 0 && createdAt.minute == 0 && dueDate!.hour == 23 && dueDate!.minute == 59;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("编辑待办"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: "待办内容")),
                const SizedBox(height: 10),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("全天事件", style: TextStyle(fontSize: 15)),
                  value: isAllDay,
                  onChanged: (val) {
                    setDialogState(() {
                      isAllDay = val;
                      if (isAllDay) {
                        createdAt = DateTime(createdAt.year, createdAt.month, createdAt.day, 0, 0);
                        if (dueDate != null) {
                          dueDate = DateTime(dueDate!.year, dueDate!.month, dueDate!.day, 23, 59);
                        } else {
                          dueDate = DateTime(createdAt.year, createdAt.month, createdAt.day, 23, 59);
                        }
                      }
                    });
                  },
                ),

                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text("开始时间: ${DateFormat(isAllDay ? 'yyyy-MM-dd' : 'yyyy-MM-dd HH:mm').format(createdAt)}"),
                  trailing: const Icon(Icons.edit_calendar, size: 20),
                  onTap: () async {
                    final pickedDate = await showDatePicker(
                        context: context, firstDate: DateTime(2000), lastDate: DateTime(2100), initialDate: createdAt);
                    if (pickedDate != null) {
                      if (isAllDay) {
                        setDialogState(() => createdAt = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, 0, 0));
                      } else {
                        if (!context.mounted) return;
                        final pickedTime = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(createdAt));
                        if (pickedTime != null) {
                          setDialogState(() => createdAt = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute));
                        }
                      }
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(dueDate == null ? "设置截止时间 (可选)" : "截止时间: ${DateFormat(isAllDay ? 'yyyy-MM-dd' : 'yyyy-MM-dd HH:mm').format(dueDate!)}"),
                  trailing: const Icon(Icons.event, size: 20),
                  onTap: () async {
                    final pickedDate = await showDatePicker(
                        context: context, firstDate: DateTime(2000), lastDate: DateTime(2100), initialDate: dueDate ?? createdAt);
                    if (pickedDate != null) {
                      if (isAllDay) {
                        setDialogState(() => dueDate = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, 23, 59));
                      } else {
                        if (!context.mounted) return;
                        final pickedTime = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(dueDate ?? DateTime.now()));
                        if (pickedTime != null) {
                          setDialogState(() => dueDate = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute));
                        }
                      }
                    }
                  },
                ),
                const Divider(),
                DropdownButtonFormField<RecurrenceType>(
                  value: recurrence, decoration: const InputDecoration(labelText: "循环设置 (可选)"),
                  items: const [
                    DropdownMenuItem(value: RecurrenceType.none, child: Text("不重复")),
                    DropdownMenuItem(value: RecurrenceType.daily, child: Text("每天重复")),
                    DropdownMenuItem(value: RecurrenceType.customDays, child: Text("隔几天重复")),
                  ],
                  onChanged: (val) => setDialogState(() => recurrence = val!),
                ),
                if (recurrence == RecurrenceType.customDays)
                  TextField(controller: customDaysCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "间隔天数"), onChanged: (val) => customDays = int.tryParse(val)),
                if (recurrence != RecurrenceType.none)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(recurrenceEndDate == null ? "循环截止日期 (可选)" : "循环结束: ${DateFormat('yyyy-MM-dd').format(recurrenceEndDate!)}"),
                    trailing: const Icon(Icons.event_busy, size: 20),
                    onTap: () async {
                      final picked = await showDatePicker(
                          context: context, firstDate: DateTime.now(), lastDate: DateTime(2100), initialDate: recurrenceEndDate ?? DateTime.now().add(const Duration(days: 30)));
                      if (picked != null) setDialogState(() => recurrenceEndDate = picked);
                    },
                  )
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
            FilledButton(
              onPressed: () {
                if (titleCtrl.text.isNotEmpty) {
                  todo.title = titleCtrl.text;
                  todo.createdDate = createdAt.millisecondsSinceEpoch; // 🚀 修正：更新业务开始时间
                  todo.dueDate = dueDate;
                  todo.recurrence = recurrence;
                  todo.customIntervalDays = customDays;
                  todo.recurrenceEndDate = recurrenceEndDate;
                  todo.markAsChanged();

                  List<TodoItem> updatedList = List.from(widget.todos);
                  widget.onTodosChanged(updatedList);
                  if (mounted) Navigator.pop(ctx);
                }
              },
              child: const Text("保存"),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildTodoItemCard(TodoItem todo, {required bool isPast, required bool isFuture, Key? key}) {
    Color cardColor = todo.isDone
        ? Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3)
        : Theme.of(context).colorScheme.surface.withOpacity(isPast || isFuture ? 0.5 : 0.95);

    Color titleColor = todo.isDone
        ? Theme.of(context).colorScheme.onSurface.withOpacity(0.4)
        : (isPast || isFuture ? Theme.of(context).colorScheme.onSurface.withOpacity(0.6) : Theme.of(context).colorScheme.onSurface);

    Widget titleWidget = Text(
      todo.title,
      style: TextStyle(
        decoration: todo.isDone ? TextDecoration.lineThrough : null,
        color: titleColor,
        fontSize: isPast || isFuture ? 14 : 16,
        fontWeight: isPast || isFuture ? FontWeight.normal : FontWeight.w500,
      ),
    );

    String dateStr = "";
    // 🚀 修正：优先使用 createdDate，兼容旧数据 fallback 到 createdAt
    DateTime cDate = DateTime.fromMillisecondsSinceEpoch(todo.createdDate ?? todo.createdAt);
    if (todo.dueDate != null) {
      String dueDateStr = DateFormat('MM-dd HH:mm').format(todo.dueDate!);
      String createDateStr = DateFormat('MM-dd HH:mm').format(cDate);

      if (isFuture) {
        DateTime now = DateTime.now();
        DateTime today = DateTime(now.year, now.month, now.day);
        DateTime target = DateTime(todo.dueDate!.year, todo.dueDate!.month, todo.dueDate!.day);
        int days = target.difference(today).inDays;
        dateStr = "$createDateStr 至 $dueDateStr ($days天后截止)";
      } else if (isPast) {
        dateStr = "$createDateStr 至 $dueDateStr (已逾期)";
      } else {
        dateStr = "$createDateStr 至 $dueDateStr (今天截止)";
      }
    } else {
      dateStr = "开始于 ${DateFormat('MM-dd HH:mm').format(cDate)}";
    }

    Color subColor = todo.isDone
        ? Theme.of(context).colorScheme.onSurface.withOpacity(0.4)
        : (isPast ? Colors.redAccent.shade400 : Theme.of(context).colorScheme.onSurface.withOpacity(0.5));

    Widget dateText = Text(dateStr, style: TextStyle(fontSize: 12, color: subColor));

    double progress = 0.0;
    DateTime start;
    DateTime end;
    DateTime now = DateTime.now();

    if (todo.dueDate != null) {
      start = cDate;
      end = DateTime(todo.dueDate!.year, todo.dueDate!.month, todo.dueDate!.day, todo.dueDate!.hour, todo.dueDate!.minute, 59);
    } else {
      start = DateTime(cDate.year, cDate.month, cDate.day, cDate.hour, cDate.minute);
      end = DateTime(cDate.year, cDate.month, cDate.day, 23, 59, 59);
    }

    bool isSameDay = start.year == end.year && start.month == end.month && start.day == end.day;

    if (isSameDay && now.isBefore(start)) {
      progress = 0.0;
    } else {
      int totalMinutes = end.difference(start).inMinutes;
      if (totalMinutes <= 0) totalMinutes = 1;
      if (now.isBefore(start)) {
        progress = 0.0;
      } else {
        int passedMinutes = now.difference(start).inMinutes;
        progress = (passedMinutes / totalMinutes).clamp(0.0, 1.0);
      }
    }

    Widget subtitleWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 2),
        dateText,
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 5,
                  backgroundColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(
                      todo.isDone ? Theme.of(context).colorScheme.onSurface.withOpacity(0.2) : Theme.of(context).colorScheme.primary
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text("${(progress * 100).toInt()}%", style: TextStyle(fontSize: 11, color: subColor, fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );

    return Dismissible(
      key: key ?? _getTodoKey('dismiss', todo.id),
      background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
      onDismissed: (_) async {
        _todoKeys.remove('drag_${todo.id}');
        _todoKeys.remove('dismiss_${todo.id}');

        try {
          // 1️⃣ 先调用全局删除（服务器 + 本地）
          await StorageService.deleteTodoGlobally(widget.username, todo.id);

          // 2️⃣ UI更新
          List<TodoItem> updatedList =
          List.from(widget.todos)..removeWhere((t) => t.id == todo.id);

          widget.onTodosChanged(updatedList);

          // 3️⃣ 写入回收站（仅用于UI恢复）
          final prefs = await SharedPreferences.getInstance();
          final String key = 'deleted_todos_${widget.username}';

          List<TodoItem> deleted = [];
          String? str = prefs.getString(key);

          if (str != null) {
            deleted = (jsonDecode(str) as Iterable)
                .map((e) => TodoItem.fromJson(e))
                .toList();
          }

          deleted.insert(0, todo);

          await prefs.setString(
            key,
            jsonEncode(deleted.map((e) => e.toJson()).toList()),
          );
        } catch (e) {
          debugPrint("删除失败: $e");
        }
      },
      child: Card(
        elevation: 0,
        color: cardColor,
        margin: const EdgeInsets.only(bottom: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          dense: isPast || isFuture,
          onTap: () => _editTodo(todo),
          leading: Checkbox(
              value: todo.isDone,
              onChanged: (val) {
                todo.isDone = val!;
                todo.markAsChanged();
                List<TodoItem> updatedList = List.from(widget.todos);
                updatedList.sort((a, b) => a.isDone == b.isDone ? 0 : (a.isDone ? 1 : -1));
                widget.onTodosChanged(updatedList);
              }
          ),
          title: titleWidget,
          subtitle: subtitleWidget,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // 计算一条待办的进度值（0.0 ~ 1.0）
  // ─────────────────────────────────────────────
  double _calcProgress(TodoItem todo, DateTime now) {
    final DateTime cDate = DateTime.fromMillisecondsSinceEpoch(todo.createdDate ?? todo.createdAt);
    final DateTime start = cDate;
    final DateTime end = todo.dueDate != null
        ? DateTime(todo.dueDate!.year, todo.dueDate!.month, todo.dueDate!.day, todo.dueDate!.hour, todo.dueDate!.minute, 59)
        : DateTime(cDate.year, cDate.month, cDate.day, 23, 59, 59);

    if (now.isBefore(start)) return 0.0;
    final int totalMinutes = end.difference(start).inMinutes;
    if (totalMinutes <= 0) return 1.0;
    return (now.difference(start).inMinutes / totalMinutes).clamp(0.0, 1.0);
  }

  // ─────────────────────────────────────────────
  // 当日待办排序：
  //   未完成 → 进度高的优先；进度相同 → 持续时间短的优先
  //   已完成 → 排在未完成之后
  // ─────────────────────────────────────────────
  List<TodoItem> _sortTodayTodos(List<TodoItem> list, DateTime now) {
    int durationMinutes(TodoItem t) {
      final DateTime cDate = DateTime.fromMillisecondsSinceEpoch(t.createdDate ?? t.createdAt);
      final DateTime end = t.dueDate != null
          ? DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day, t.dueDate!.hour, t.dueDate!.minute, 59)
          : DateTime(cDate.year, cDate.month, cDate.day, 23, 59, 59);
      final int mins = end.difference(cDate).inMinutes;
      return mins <= 0 ? 1 : mins;
    }

    final undone = list.where((t) => !t.isDone).toList()
      ..sort((a, b) {
        final double pa = _calcProgress(a, now);
        final double pb = _calcProgress(b, now);
        // 进度更高的排前面（降序）
        final int cmp = pb.compareTo(pa);
        if (cmp != 0) return cmp;
        // 进度相同：持续时间短的排前面（升序）
        return durationMinutes(a).compareTo(durationMinutes(b));
      });

    final done = list.where((t) => t.isDone).toList();
    return [...undone, ...done];
  }

  // ─────────────────────────────────────────────
  // 未来待办排序：
  //   未完成 → 进度高的优先；进度相同 → 截止日期近的优先
  //   已完成 → 排在未完成之后
  // ─────────────────────────────────────────────
  List<TodoItem> _sortFutureTodos(List<TodoItem> list, DateTime now) {
    final undone = list.where((t) => !t.isDone).toList()
      ..sort((a, b) {
        final double pa = _calcProgress(a, now);
        final double pb = _calcProgress(b, now);
        final int cmp = pb.compareTo(pa);
        if (cmp != 0) return cmp;
        // 进度相同：截止时间近的排前面（升序）
        final DateTime da = a.dueDate ?? DateTime(9999);
        final DateTime db = b.dueDate ?? DateTime(9999);
        return da.compareTo(db);
      });

    final done = list.where((t) => t.isDone).toList();
    return [...undone, ...done];
  }

  Widget _buildTodoList() {
    final Iterable<TodoItem> activeTodos =
        widget.todos.where((t) => !t.isDeleted && !_isHistoricalTodo(t));

    if (activeTodos.isEmpty) {
      return EmptyState(text: "暂无待办", isLight: widget.isLight);
    }

    // ── 整体折叠：只显示一行摘要 ──
    if (!_isWholeListExpanded) {
      final int undoneCount = activeTodos.where((t) => !t.isDone).length;
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          undoneCount == 0 ? "🎉 所有待办均已完成" : "还有 $undoneCount 个待办未完成",
          style: TextStyle(color: widget.isLight ? Colors.white : null),
        ),
        trailing: Icon(Icons.expand_more, color: widget.isLight ? Colors.white70 : null),
        onTap: () => setState(() => _isWholeListExpanded = true),
      );
    }

    List<TodoItem> pastTodos = [];
    List<TodoItem> todayTodos = [];
    List<TodoItem> futureTodos = [];

    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);

    for (final t in widget.todos) {
      if (_isHistoricalTodo(t)) continue;
      if (t.isDeleted) continue;

      if (t.dueDate != null) {
        final DateTime d = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
        if (d.isBefore(today)) {
          pastTodos.add(t);
        } else if (d.isAfter(today)) {
          futureTodos.add(t);
        } else {
          todayTodos.add(t);
        }
      } else {
        todayTodos.add(t);
      }
    }

    // 当日全部完成 → 自动折叠今日区块（除非用户手动展开）
    final bool allTodayDone = todayTodos.isNotEmpty && todayTodos.every((t) => t.isDone);
    // 今日区块是否实际展开：手动控制优先，否则遵循自动折叠
    final bool showTodayItems = _isTodayManuallyExpanded || (!allTodayDone && _isTodayExpanded);

    // 排序
    final List<TodoItem> sortedTodayTodos = _sortTodayTodos(todayTodos, now);
    final List<TodoItem> sortedFutureTodos = _sortFutureTodos(futureTodos, now);

    final List<Widget> sections = [];

    // ── 以往待办（逾期）──
    if (pastTodos.isNotEmpty) {
      sections.add(
        InkWell(
          onTap: () => setState(() => _isPastTodosExpanded = !_isPastTodosExpanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
            child: Row(
              children: [
                Icon(_isPastTodosExpanded ? Icons.expand_more : Icons.chevron_right,
                    size: 20, color: widget.isLight ? Colors.white70 : Colors.grey),
                const SizedBox(width: 8),
                Text("以往待办 (${pastTodos.length})",
                    style: TextStyle(
                        color: widget.isLight ? Colors.white70 : Colors.grey,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ],
            ),
          ),
        ),
      );
      if (_isPastTodosExpanded) {
        sections.addAll(pastTodos.map(
            (t) => _buildTodoItemCard(t, isPast: true, isFuture: false, key: _getTodoKey('dismiss', t.id))));
      }
      sections.add(const SizedBox(height: 8));
    }

    // ── 今日待办区块 ──
    if (!showTodayItems && todayTodos.isNotEmpty) {
      // 折叠行（自动折叠 或 手动折叠）→ 点击可手动展开
      sections.add(
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            allTodayDone
                ? "🎉 今日待办均已完成"
                : "还有 ${todayTodos.where((t) => !t.isDone).length} 个今日待办未完成",
            style: TextStyle(color: widget.isLight ? Colors.white : null),
          ),
          trailing: Icon(Icons.expand_more, color: widget.isLight ? Colors.white70 : null),
          onTap: () => setState(() {
            _isTodayManuallyExpanded = true;
            _isTodayExpanded = true;
          }),
        ),
      );
    } else if (showTodayItems) {
      // 展开状态：显示收起按钮 + 列表
      if (todayTodos.isNotEmpty) {
        // 今日区块标题行（可点击收起）
        sections.add(
          InkWell(
            onTap: () => setState(() {
              _isTodayExpanded = false;
              _isTodayManuallyExpanded = false;
            }),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
              child: Row(
                children: [
                  Icon(Icons.expand_more,
                      size: 18, color: widget.isLight ? Colors.white60 : Colors.grey),
                  const SizedBox(width: 6),
                  Text(
                    "今日待办 (${todayTodos.where((t) => t.isDone).length}/${todayTodos.length})",
                    style: TextStyle(
                        color: widget.isLight ? Colors.white60 : Colors.grey,
                        fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        );

        sections.add(
          ReorderableListView(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            proxyDecorator: (Widget child, int index, Animation<double> animation) {
              return Material(
                color: Colors.transparent,
                elevation: 6 * animation.value,
                shadowColor: Colors.black.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
                child: child,
              );
            },
            onReorder: (oldIndex, newIndex) {
              if (newIndex > oldIndex) newIndex -= 1;

              final List<int> todayIndices = [];
              for (int i = 0; i < widget.todos.length; i++) {
                final t = widget.todos[i];
                if (_isHistoricalTodo(t) || t.isDeleted) continue;
                if (t.dueDate != null) {
                  final DateTime d = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
                  if (!d.isBefore(today) && !d.isAfter(today)) todayIndices.add(i);
                } else {
                  todayIndices.add(i);
                }
              }

              final List<TodoItem> reordered = List.from(sortedTodayTodos);
              final item = reordered.removeAt(oldIndex);
              reordered.insert(newIndex, item);

              final List<TodoItem> updatedList = List.from(widget.todos);
              for (int i = 0; i < todayIndices.length && i < reordered.length; i++) {
                updatedList[todayIndices[i]] = reordered[i];
              }
              widget.onTodosChanged(updatedList);
            },
            children: sortedTodayTodos.asMap().entries.map((entry) {
              final int index = entry.key;
              final TodoItem t = entry.value;
              return ReorderableDelayedDragStartListener(
                key: _getTodoKey('drag', t.id),
                index: index,
                child: _buildTodoItemCard(t, isPast: false, isFuture: false,
                    key: _getTodoKey('dismiss', t.id)),
              );
            }).toList(),
          ),
        );
      } else if (futureTodos.isEmpty) {
        sections.add(Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text("今日无待办",
                style: TextStyle(color: widget.isLight ? Colors.white70 : Colors.grey))));
      }
    }

    // ── 未来待办区块（可折叠）──
    if (sortedFutureTodos.isNotEmpty) {
      final int futureUndone = sortedFutureTodos.where((t) => !t.isDone).length;
      sections.add(
        InkWell(
          onTap: () => setState(() => _isFutureExpanded = !_isFutureExpanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.only(top: 20.0, bottom: 8.0, left: 4.0),
            child: Row(
              children: [
                Icon(
                  _isFutureExpanded ? Icons.expand_more : Icons.chevron_right,
                  size: 18,
                  color: widget.isLight ? Colors.white60 : Colors.grey,
                ),
                const SizedBox(width: 6),
                Icon(Icons.calendar_month,
                    size: 16, color: widget.isLight ? Colors.white60 : Colors.grey),
                const SizedBox(width: 6),
                Text(
                  "未来待办",
                  style: TextStyle(
                      color: widget.isLight ? Colors.white70 : Colors.grey,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
                const SizedBox(width: 6),
                Text(
                  "($futureUndone 未完成)",
                  style: TextStyle(
                      color: widget.isLight ? Colors.white38 : Colors.grey.shade400,
                      fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );
      if (_isFutureExpanded) {
        sections.addAll(sortedFutureTodos.map((t) =>
            _buildTodoItemCard(t, isPast: false, isFuture: true, key: _getTodoKey('dismiss', t.id))));
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: sections);
  }

  @override
  Widget build(BuildContext context) {
    final int undoneCount = widget.todos
        .where((t) => !t.isDeleted && !_isHistoricalTodo(t) && !t.isDone)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: SectionHeader(
                title: "待办清单",
                icon: Icons.check_circle_outline,
                onAdd: showAddTodoDialog,
                isLight: widget.isLight,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 未完成数量徽章（整体折叠时显示）
                if (!_isWholeListExpanded && undoneCount > 0)
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: widget.isLight
                          ? Colors.white.withOpacity(0.25)
                          : Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "$undoneCount 未完成",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: widget.isLight
                            ? Colors.white
                            : Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                IconButton(
                  icon: Icon(Icons.history,
                      color: widget.isLight ? Colors.white70 : Colors.grey),
                  onPressed: () async {
                    await Navigator.push(context,
                        MaterialPageRoute(builder: (_) => HistoricalTodosScreen(username: widget.username)));
                    widget.onRefreshRequested();
                  },
                ),
                // 整体折叠/展开
                IconButton(
                  icon: Icon(
                    _isWholeListExpanded ? Icons.expand_less : Icons.expand_more,
                    color: widget.isLight ? Colors.white70 : Colors.grey,
                  ),
                  onPressed: () => setState(() => _isWholeListExpanded = !_isWholeListExpanded),
                ),
              ],
            ),
          ],
        ),
        _buildTodoList(),
      ],
    );
  }
}