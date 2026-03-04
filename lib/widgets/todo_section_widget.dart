import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
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
  bool _isTodoExpanded = true;
  bool _isPastTodosExpanded = false;
  bool _hasInitializedExpansion = false;

  @override
  void didUpdateWidget(TodoSectionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_hasInitializedExpansion && widget.todos.isNotEmpty) {
      _isTodoExpanded = !widget.todos.where((t) => !_isHistoricalTodo(t)).every((t) => t.isDone);
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
      DateTime c = DateTime(t.createdAt.year, t.createdAt.month, t.createdAt.day);
      return c.isBefore(today);
    }
  }

  /// 供父组件调用的公有方法：打开添加待办对话框
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
                    id: const Uuid().v4(),
                    title: titleCtrl.text,
                    recurrence: recurrence,
                    customIntervalDays: customDays,
                    recurrenceEndDate: recurrenceEndDate,
                    lastUpdated: DateTime.now(),
                    dueDate: dueDate,
                    createdAt: createdAt,
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
    DateTime createdAt = todo.createdAt;
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
                  todo.createdAt = createdAt;
                  todo.dueDate = dueDate;
                  todo.recurrence = recurrence;
                  todo.customIntervalDays = customDays;
                  todo.recurrenceEndDate = recurrenceEndDate;
                  todo.lastUpdated = DateTime.now();

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
    if (todo.dueDate != null) {
      String dueDateStr = DateFormat('MM-dd HH:mm').format(todo.dueDate!);
      String createDateStr = DateFormat('MM-dd HH:mm').format(todo.createdAt);

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
      dateStr = "开始于 ${DateFormat('MM-dd HH:mm').format(todo.createdAt)}";
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
      start = todo.createdAt;
      end = DateTime(todo.dueDate!.year, todo.dueDate!.month, todo.dueDate!.day, todo.dueDate!.hour, todo.dueDate!.minute, 59);
    } else {
      start = DateTime(todo.createdAt.year, todo.createdAt.month, todo.createdAt.day, todo.createdAt.hour, todo.createdAt.minute);
      end = DateTime(todo.createdAt.year, todo.createdAt.month, todo.createdAt.day, 23, 59, 59);
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
      key: key ?? Key(todo.id),
      background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
      onDismissed: (_) async {
        String titleToDelete = todo.title;
        List<TodoItem> updatedList = List.from(widget.todos)..removeWhere((t) => t.id == todo.id);
        await StorageService.deleteTodoGlobally(widget.username, titleToDelete);
        widget.onTodosChanged(updatedList);
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
                todo.lastUpdated = DateTime.now();
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

  Widget _buildTodoList() {
    if (widget.todos.where((t) => !_isHistoricalTodo(t)).isEmpty) return EmptyState(text: "暂无待办", isLight: widget.isLight);

    List<TodoItem> pastTodos = [];
    List<TodoItem> todayTodos = [];
    List<TodoItem> futureTodos = [];

    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);

    for (var t in widget.todos) {
      if (_isHistoricalTodo(t)) continue;

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
        todayTodos.add(t);
      }
    }

    List<Widget> sections = [];

    if (pastTodos.isNotEmpty) {
      sections.add(
          InkWell(
            onTap: () => setState(() => _isPastTodosExpanded = !_isPastTodosExpanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
              child: Row(
                children: [
                  Icon(_isPastTodosExpanded ? Icons.expand_more : Icons.chevron_right, size: 20, color: widget.isLight ? Colors.white70 : Colors.grey),
                  const SizedBox(width: 8),
                  Text("以往待办 (${pastTodos.length})", style: TextStyle(color: widget.isLight ? Colors.white70 : Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ),
          )
      );
      if (_isPastTodosExpanded) {
        sections.addAll(pastTodos.map((t) => _buildTodoItemCard(t, isPast: true, isFuture: false)));
      }
      sections.add(const SizedBox(height: 8));
    }

    if (!_isTodoExpanded) {
      sections.add(
          ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(todayTodos.every((t) => t.isDone) ? "今日待办均已完成" : "还有 ${todayTodos.where((t) => !t.isDone).length} 个今日待办未完成", style: TextStyle(color: widget.isLight ? Colors.white : null)),
              trailing: Icon(Icons.expand_more, color: widget.isLight ? Colors.white70 : null),
              onTap: () => setState(() => _isTodoExpanded = true)
          )
      );
    } else {
      if (todayTodos.isNotEmpty) {
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

              List<int> todayIndices = [];
              for (int i = 0; i < widget.todos.length; i++) {
                final t = widget.todos[i];
                if (_isHistoricalTodo(t)) continue;
                if (t.dueDate != null) {
                  DateTime d = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
                  if (!d.isBefore(today) && !d.isAfter(today)) todayIndices.add(i);
                } else {
                  todayIndices.add(i);
                }
              }

              final item = todayTodos.removeAt(oldIndex);
              todayTodos.insert(newIndex, item);

              List<TodoItem> updatedList = List.from(widget.todos);
              for (int i = 0; i < todayIndices.length; i++) {
                updatedList[todayIndices[i]] = todayTodos[i];
              }
              widget.onTodosChanged(updatedList);
            },
            children: todayTodos.asMap().entries.map((entry) {
              int index = entry.key;
              TodoItem t = entry.value;
              return ReorderableDelayedDragStartListener(
                key: Key(t.id),
                index: index,
                child: _buildTodoItemCard(t, isPast: false, isFuture: false, key: Key('dismiss_${t.id}')),
              );
            }).toList(),
          ),
        );
      } else if (futureTodos.isEmpty) {
        sections.add(Padding(padding: const EdgeInsets.all(8.0), child: Text("今日无待办", style: TextStyle(color: widget.isLight ? Colors.white70 : Colors.grey))));
      }
    }

    if (_isTodoExpanded && futureTodos.isNotEmpty) {
      sections.add(
          Padding(
            padding: const EdgeInsets.only(top: 20.0, bottom: 8.0, left: 4.0),
            child: Row(
              children: [
                Icon(Icons.calendar_month, size: 16, color: widget.isLight ? Colors.white60 : Colors.grey),
                const SizedBox(width: 6),
                Text("未来待办", style: TextStyle(color: widget.isLight ? Colors.white70 : Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
          )
      );

      double calculateProgress(TodoItem todo) {
        DateTime start;
        DateTime end;
        if (todo.dueDate != null) {
          start = todo.createdAt;
          end = DateTime(todo.dueDate!.year, todo.dueDate!.month, todo.dueDate!.day, todo.dueDate!.hour, todo.dueDate!.minute, 59);
        } else {
          start = DateTime(todo.createdAt.year, todo.createdAt.month, todo.createdAt.day, todo.createdAt.hour, todo.createdAt.minute);
          end = DateTime(todo.createdAt.year, todo.createdAt.month, todo.createdAt.day, 23, 59, 59);
        }
        bool isSameDay = start.year == end.year && start.month == end.month && start.day == end.day;
        if (isSameDay && now.isBefore(start)) return 0.0;

        int totalMinutes = end.difference(start).inMinutes;
        if (totalMinutes <= 0) return now.isBefore(start) ? 0.0 : 1.0;
        if (now.isBefore(start)) return 0.0;
        int passedMinutes = now.difference(start).inMinutes;
        return (passedMinutes / totalMinutes).clamp(0.0, 1.0);
      }

      final sortedFutureTodos = futureTodos.toList();
      sortedFutureTodos.sort((a, b) {
        double progressA = calculateProgress(a);
        double progressB = calculateProgress(b);
        int progressComparison = progressB.compareTo(progressA);
        if (progressComparison != 0) return progressComparison;
        return a.dueDate!.compareTo(b.dueDate!);
      });

      sections.addAll(sortedFutureTodos.map((t) => _buildTodoItemCard(t, isPast: false, isFuture: true)));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: sections);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: SectionHeader(title: "待办清单", icon: Icons.check_circle_outline, onAdd: showAddTodoDialog, isLight: widget.isLight)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                    icon: Icon(Icons.history, color: widget.isLight ? Colors.white70 : Colors.grey),
                    onPressed: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => HistoricalTodosScreen(username: widget.username)));
                      widget.onRefreshRequested();
                    }
                ),
                IconButton(
                    icon: Icon(_isTodoExpanded ? Icons.expand_less : Icons.expand_more, color: widget.isLight ? Colors.white70 : Colors.grey),
                    onPressed: () => setState(() => _isTodoExpanded = !_isTodoExpanded)
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