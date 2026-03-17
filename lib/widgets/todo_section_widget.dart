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
  bool _isWholeListExpanded = true;
  bool _isTodayExpanded = true;
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
      _isTodayExpanded =
      !widget.todos.where((t) => !_isHistoricalTodo(t)).every((t) => t.isDone);
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
      DateTime cDate =
      DateTime.fromMillisecondsSinceEpoch(t.createdDate ?? t.createdAt, isUtc: true)
          .toLocal();
      DateTime c = DateTime(cDate.year, cDate.month, cDate.day);
      return c.isBefore(today);
    }
  }

  void showAddTodoDialog() {
    TextEditingController titleCtrl = TextEditingController();
    TextEditingController remarkCtrl = TextEditingController();
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: titleCtrl,
                    decoration: InputDecoration(
                        labelText: "待办内容",
                        border:
                        OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
                const SizedBox(height: 12),
                TextField(
                  controller: remarkCtrl,
                  decoration: InputDecoration(
                      labelText: "备注 (可选)",
                      hintText: "添加备注...",
                      border:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                  maxLines: 3,
                  minLines: 1,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("全天事件",
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  value: isAllDay,
                  activeColor: Theme.of(context).colorScheme.primary,
                  onChanged: (val) {
                    setDialogState(() {
                      isAllDay = val;
                      if (isAllDay) {
                        createdAt = DateTime(
                            createdAt.year, createdAt.month, createdAt.day, 0, 0);
                        if (dueDate != null) {
                          dueDate = DateTime(
                              dueDate!.year, dueDate!.month, dueDate!.day, 23, 59);
                        } else {
                          dueDate = DateTime(
                              createdAt.year, createdAt.month, createdAt.day, 23, 59);
                        }
                      }
                    });
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                      "开始时间: ${DateFormat(isAllDay ? 'yyyy-MM-dd' : 'yyyy-MM-dd HH:mm').format(createdAt)}"),
                  trailing: Icon(Icons.edit_calendar,
                      size: 20, color: Theme.of(context).colorScheme.primary),
                  onTap: () async {
                    final pickedDate = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDate: createdAt);
                    if (pickedDate != null) {
                      if (isAllDay) {
                        setDialogState(() => createdAt = DateTime(
                            pickedDate.year, pickedDate.month, pickedDate.day, 0, 0));
                      } else {
                        if (!context.mounted) return;
                        final pickedTime = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(createdAt));
                        if (pickedTime != null) {
                          setDialogState(() => createdAt = DateTime(pickedDate.year,
                              pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute));
                        }
                      }
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(dueDate == null
                      ? "设置截止时间 (可选)"
                      : "截止时间: ${DateFormat(isAllDay ? 'yyyy-MM-dd' : 'yyyy-MM-dd HH:mm').format(dueDate!)}"),
                  trailing: Icon(Icons.event,
                      size: 20, color: Theme.of(context).colorScheme.primary),
                  onTap: () async {
                    final pickedDate = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDate: dueDate ?? createdAt);
                    if (pickedDate != null) {
                      if (isAllDay) {
                        setDialogState(() => dueDate = DateTime(
                            pickedDate.year, pickedDate.month, pickedDate.day, 23, 59));
                      } else {
                        if (!context.mounted) return;
                        final pickedTime = await showTimePicker(
                            context: context,
                            initialTime:
                            TimeOfDay.fromDateTime(dueDate ?? DateTime.now()));
                        if (pickedTime != null) {
                          setDialogState(() => dueDate = DateTime(pickedDate.year,
                              pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute));
                        }
                      }
                    }
                  },
                ),
                const Divider(),
                DropdownButtonFormField<RecurrenceType>(
                  value: recurrence,
                  decoration: InputDecoration(
                      labelText: "循环设置 (可选)",
                      border:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                  items: const [
                    DropdownMenuItem(value: RecurrenceType.none, child: Text("不重复")),
                    DropdownMenuItem(
                        value: RecurrenceType.daily, child: Text("每天重复")),
                    DropdownMenuItem(
                        value: RecurrenceType.customDays, child: Text("隔几天重复")),
                  ],
                  onChanged: (val) => setDialogState(() => recurrence = val!),
                ),
                if (recurrence == RecurrenceType.customDays)
                  Padding(
                    padding: const EdgeInsets.only(top: 12.0),
                    child: TextField(
                        controller: customDaysCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                            labelText: "间隔天数",
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12))),
                        onChanged: (val) => customDays = int.tryParse(val)),
                  ),
                if (recurrence != RecurrenceType.none)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(recurrenceEndDate == null
                        ? "循环截止日期 (可选)"
                        : "循环结束: ${DateFormat('yyyy-MM-dd').format(recurrenceEndDate!)}"),
                    trailing: Icon(Icons.event_busy,
                        size: 20, color: Theme.of(context).colorScheme.primary),
                    onTap: () async {
                      final picked = await showDatePicker(
                          context: context,
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2100),
                          initialDate: DateTime.now().add(const Duration(days: 30)));
                      if (picked != null)
                        setDialogState(() => recurrenceEndDate = picked);
                    },
                  )
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
            FilledButton(
              style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: () {
                if (titleCtrl.text.isNotEmpty) {
                  final newTodo = TodoItem(
                    title: titleCtrl.text,
                    recurrence: recurrence,
                    customIntervalDays: customDays,
                    recurrenceEndDate: recurrenceEndDate,
                    dueDate: dueDate,
                    createdDate: createdAt.millisecondsSinceEpoch,
                    remark: remarkCtrl.text.trim().isEmpty
                        ? null
                        : remarkCtrl.text.trim(),
                  );
                  List<TodoItem> updatedList = List.from(widget.todos)
                    ..insert(0, newTodo);
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
    TextEditingController remarkCtrl =
    TextEditingController(text: todo.remark ?? '');
    DateTime createdDate =
    DateTime.fromMillisecondsSinceEpoch(todo.createdDate ?? todo.createdAt,
        isUtc: true)
        .toLocal();
    DateTime? dueDate = todo.dueDate;
    RecurrenceType recurrence = todo.recurrence;
    int? customDays = todo.customIntervalDays;
    TextEditingController customDaysCtrl =
    TextEditingController(text: customDays?.toString() ?? "");
    DateTime? recurrenceEndDate = todo.recurrenceEndDate;

    bool isAllDay = dueDate != null &&
        createdDate.hour == 0 &&
        createdDate.minute == 0 &&
        dueDate!.hour == 23 &&
        dueDate!.minute == 59;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("编辑待办"),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: titleCtrl,
                    decoration: InputDecoration(
                        labelText: "待办内容",
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)))),
                const SizedBox(height: 12),
                TextField(
                  controller: remarkCtrl,
                  decoration: InputDecoration(
                      labelText: "备注 (可选)",
                      hintText: "添加备注...",
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12))),
                  maxLines: 3,
                  minLines: 1,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("全天事件",
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  value: isAllDay,
                  activeColor: Theme.of(context).colorScheme.primary,
                  onChanged: (val) {
                    setDialogState(() {
                      isAllDay = val;
                      if (isAllDay) {
                        createdDate = DateTime(createdDate.year, createdDate.month,
                            createdDate.day, 0, 0);
                        if (dueDate != null) {
                          dueDate = DateTime(
                              dueDate!.year, dueDate!.month, dueDate!.day, 23, 59);
                        } else {
                          dueDate = DateTime(createdDate.year, createdDate.month,
                              createdDate.day, 23, 59);
                        }
                      }
                    });
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                      "开始时间: ${DateFormat(isAllDay ? 'yyyy-MM-dd' : 'yyyy-MM-dd HH:mm').format(createdDate)}"),
                  trailing: Icon(Icons.edit_calendar,
                      size: 20, color: Theme.of(context).colorScheme.primary),
                  onTap: () async {
                    final pickedDate = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDate: createdDate);
                    if (pickedDate != null) {
                      if (isAllDay) {
                        setDialogState(() => createdDate = DateTime(pickedDate.year,
                            pickedDate.month, pickedDate.day, 0, 0));
                      } else {
                        if (!context.mounted) return;
                        final pickedTime = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(createdDate));
                        if (pickedTime != null) {
                          setDialogState(() => createdDate = DateTime(pickedDate.year,
                              pickedDate.month, pickedDate.day, pickedTime.hour,
                              pickedTime.minute));
                        }
                      }
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(dueDate == null
                      ? "设置截止时间 (可选)"
                      : "截止时间: ${DateFormat(isAllDay ? 'yyyy-MM-dd' : 'yyyy-MM-dd HH:mm').format(dueDate!)}"),
                  trailing: Icon(Icons.event,
                      size: 20, color: Theme.of(context).colorScheme.primary),
                  onTap: () async {
                    final pickedDate = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDate: dueDate ?? createdDate);
                    if (pickedDate != null) {
                      if (isAllDay) {
                        setDialogState(() => dueDate = DateTime(
                            pickedDate.year, pickedDate.month, pickedDate.day, 23, 59));
                      } else {
                        if (!context.mounted) return;
                        final pickedTime = await showTimePicker(
                            context: context,
                            initialTime:
                            TimeOfDay.fromDateTime(dueDate ?? DateTime.now()));
                        if (pickedTime != null) {
                          setDialogState(() => dueDate = DateTime(pickedDate.year,
                              pickedDate.month, pickedDate.day, pickedTime.hour,
                              pickedTime.minute));
                        }
                      }
                    }
                  },
                ),
                const Divider(),
                DropdownButtonFormField<RecurrenceType>(
                  value: recurrence,
                  decoration: InputDecoration(
                      labelText: "循环设置 (可选)",
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12))),
                  items: const [
                    DropdownMenuItem(value: RecurrenceType.none, child: Text("不重复")),
                    DropdownMenuItem(
                        value: RecurrenceType.daily, child: Text("每天重复")),
                    DropdownMenuItem(
                        value: RecurrenceType.customDays, child: Text("隔几天重复")),
                  ],
                  onChanged: (val) => setDialogState(() => recurrence = val!),
                ),
                if (recurrence == RecurrenceType.customDays)
                  Padding(
                    padding: const EdgeInsets.only(top: 12.0),
                    child: TextField(
                        controller: customDaysCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                            labelText: "间隔天数",
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12))),
                        onChanged: (val) => customDays = int.tryParse(val)),
                  ),
                if (recurrence != RecurrenceType.none)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(recurrenceEndDate == null
                        ? "循环截止日期 (可选)"
                        : "循环结束: ${DateFormat('yyyy-MM-dd').format(recurrenceEndDate!)}"),
                    trailing: Icon(Icons.event_busy,
                        size: 20, color: Theme.of(context).colorScheme.primary),
                    onTap: () async {
                      final picked = await showDatePicker(
                          context: context,
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2100),
                          initialDate: recurrenceEndDate ??
                              DateTime.now().add(const Duration(days: 30)));
                      if (picked != null)
                        setDialogState(() => recurrenceEndDate = picked);
                    },
                  )
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
            FilledButton(
              style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: () {
                if (titleCtrl.text.isNotEmpty) {
                  todo.title = titleCtrl.text;
                  todo.createdDate = createdDate.millisecondsSinceEpoch;
                  todo.dueDate = dueDate;
                  todo.recurrence = recurrence;
                  todo.customIntervalDays = customDays;
                  todo.recurrenceEndDate = recurrenceEndDate;
                  todo.remark =
                  remarkCtrl.text.trim().isEmpty ? null : remarkCtrl.text.trim();
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

  // ─────────────────────────────────────────────
  // 时间标签构建（单行，信息完整）
  // ─────────────────────────────────────────────
  String _buildTimeLabel(TodoItem todo, DateTime cDate, bool isPast,
      bool isFuture, DateTime now) {
    final bool isAllDay = todo.dueDate != null &&
        cDate.hour == 0 &&
        cDate.minute == 0 &&
        todo.dueDate!.hour == 23 &&
        todo.dueDate!.minute == 59;

    final String startStr = isAllDay
        ? DateFormat('MM/dd').format(cDate)
        : DateFormat('MM/dd HH:mm').format(cDate);

    if (todo.dueDate != null) {
      final String dueStr = isAllDay
          ? DateFormat('MM/dd').format(todo.dueDate!)
          : DateFormat('MM/dd HH:mm').format(todo.dueDate!);
      return "$startStr → $dueStr";
    } else {
      return "开始 $startStr";
    }
  }

  // ─────────────────────────────────────────────
  // 🎨 紧凑卡片：重新设计，更小更精致
  // ─────────────────────────────────────────────
  Widget _buildTodoItemCard(TodoItem todo,
      {required bool isPast, required bool isFuture, Key? key}) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool isLight = widget.isLight;

    // ── 颜色层 ──
    final Color cardBg = todo.isDone
        ? colorScheme.surfaceContainerHighest.withOpacity(isLight ? 0.25 : 0.08)
        : colorScheme.surface.withOpacity(
        isPast
            ? (isLight ? 0.9 : 0.45)
            : isFuture
            ? (isLight ? 0.85 : 0.35)
            : (isLight ? 0.97 : 0.75));

    final Color titleColor = todo.isDone
        ? colorScheme.onSurface.withOpacity(0.35)
        : (isPast || isFuture
        ? colorScheme.onSurface.withOpacity(0.65)
        : colorScheme.onSurface);

    // ── 进度计算 ──
    DateTime cDate =
    DateTime.fromMillisecondsSinceEpoch(todo.createdDate ?? todo.createdAt,
        isUtc: true)
        .toLocal();
    final DateTime now = DateTime.now();
    double progress = 0.0;
    {
      DateTime start = cDate;
      DateTime end = todo.dueDate != null
          ? DateTime(todo.dueDate!.year, todo.dueDate!.month, todo.dueDate!.day,
          todo.dueDate!.hour, todo.dueDate!.minute, 59)
          : DateTime(cDate.year, cDate.month, cDate.day, 23, 59, 59);
      int totalMinutes = end.difference(start).inMinutes;
      if (totalMinutes <= 0) totalMinutes = 1;
      if (now.isAfter(start)) {
        progress = (now.difference(start).inMinutes / totalMinutes).clamp(0.0, 1.0);
      }
    }

    // ── 时间徽章文本 ──
    String badge = "";
    Color badgeColor = colorScheme.primary;
    Color badgeBg = colorScheme.primaryContainer.withOpacity(0.6);

    if (todo.dueDate != null) {
      final DateTime d =
      DateTime(todo.dueDate!.year, todo.dueDate!.month, todo.dueDate!.day);
      final DateTime today = DateTime(now.year, now.month, now.day);
      if (isPast) {
        badge = "已逾期";
        badgeColor = Colors.redAccent.shade200;
        badgeBg = Colors.redAccent.withOpacity(0.12);
      } else if (isFuture) {
        int days = d.difference(today).inDays;
        badge = "$days天后";
        badgeColor = colorScheme.secondary;
        badgeBg = colorScheme.secondaryContainer.withOpacity(0.5);
      } else {
        badge = "今天截止";
        badgeColor = Colors.orange.shade700;
        badgeBg = Colors.orange.withOpacity(0.12);
      }
    } else {
      badge = DateFormat('MM/dd').format(cDate);
      badgeColor = colorScheme.onSurface.withOpacity(0.45);
      badgeBg = colorScheme.onSurface.withOpacity(0.06);
    }

    // ── 循环图标 ──
    Widget? recurrenceIcon;
    if (todo.recurrence != RecurrenceType.none) {
      recurrenceIcon = Icon(Icons.repeat_rounded,
          size: 11, color: colorScheme.primary.withOpacity(0.6));
    }

    return Dismissible(
      key: key ?? _getTodoKey('dismiss', todo.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: Colors.redAccent.shade400,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline_rounded,
            color: Colors.white, size: 22),
      ),
      onDismissed: (_) async {
        _todoKeys.remove('drag_${todo.id}');
        _todoKeys.remove('dismiss_${todo.id}');
        try {
          await StorageService.deleteTodoGlobally(widget.username, todo.id);
          List<TodoItem> updatedList = List.from(widget.todos)
            ..removeWhere((t) => t.id == todo.id);
          widget.onTodosChanged(updatedList);

          final prefs = await SharedPreferences.getInstance();
          final String cacheKey = 'deleted_todos_${widget.username}';
          List<TodoItem> deleted = [];
          String? str = prefs.getString(cacheKey);
          if (str != null) {
            deleted = (jsonDecode(str) as Iterable)
                .map((e) => TodoItem.fromJson(e))
                .toList();
          }
          deleted.insert(0, todo);
          await prefs.setString(
              cacheKey, jsonEncode(deleted.map((e) => e.toJson()).toList()));
        } catch (e) {
          debugPrint("删除失败: $e");
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isPast && !todo.isDone
                ? Colors.redAccent.withOpacity(0.25)
                : colorScheme.outline.withOpacity(isLight ? 0.06 : 0.12),
            width: 1,
          ),
          boxShadow: (!todo.isDone && isLight)
              ? [
            BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ]
              : [],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _editTodo(todo),
            child: Padding(
              // ✨ 核心：更小的内边距
              padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── 复选框 ──
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6)),
                      activeColor: colorScheme.primary,
                      value: todo.isDone,
                      onChanged: (val) {
                        todo.isDone = val!;
                        todo.markAsChanged();
                        List<TodoItem> updatedList = List.from(widget.todos);
                        updatedList.sort((a, b) =>
                        a.isDone == b.isDone ? 0 : (a.isDone ? 1 : -1));
                        widget.onTodosChanged(updatedList);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),

                  // ── 主内容区 ──
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 标题行
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                todo.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  decoration: todo.isDone
                                      ? TextDecoration.lineThrough
                                      : null,
                                  decorationColor:
                                  colorScheme.onSurface.withOpacity(0.3),
                                  color: titleColor,
                                  fontSize: 14.5,
                                  fontWeight: todo.isDone || isPast || isFuture
                                      ? FontWeight.w500
                                      : FontWeight.w600,
                                  height: 1.2,
                                ),
                              ),
                            ),
                            if (recurrenceIcon != null) ...[
                              const SizedBox(width: 4),
                              recurrenceIcon,
                            ],
                            const SizedBox(width: 6),
                            // 时间徽章
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: todo.isDone
                                    ? colorScheme.onSurface.withOpacity(0.06)
                                    : badgeBg,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                badge,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: todo.isDone
                                      ? colorScheme.onSurface.withOpacity(0.3)
                                      : badgeColor,
                                ),
                              ),
                            ),
                          ],
                        ),

                        // ── 时间信息行 ──
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(
                              Icons.schedule_rounded,
                              size: 11,
                              color: colorScheme.onSurface.withOpacity(
                                  todo.isDone ? 0.25 : (isPast ? 0.55 : 0.4)),
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                _buildTimeLabel(todo, cDate, isPast, isFuture, now),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onSurface.withOpacity(
                                      todo.isDone
                                          ? 0.25
                                          : isPast
                                          ? 0.6
                                          : 0.45),
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),

                        // 备注（可选，单行截断）
                        if (todo.remark != null &&
                            todo.remark!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            todo.remark!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurface.withOpacity(
                                  todo.isDone ? 0.22 : 0.4),
                              height: 1.2,
                            ),
                          ),
                        ],

                        // 进度条（仅未完成项显示）
                        if (!todo.isDone) ...[
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 3,
                              backgroundColor:
                              colorScheme.onSurface.withOpacity(0.07),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                isPast
                                    ? Colors.redAccent.shade200
                                    : colorScheme.primary.withOpacity(0.75),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // 排序
  // ─────────────────────────────────────────────
  List<TodoItem> _sortTodayTodos(List<TodoItem> list, DateTime now) {
    int startMs(TodoItem t) => t.createdDate ?? t.createdAt;
    final undone = list.where((t) => !t.isDone).toList()
      ..sort((a, b) => startMs(a).compareTo(startMs(b)));
    final done = list.where((t) => t.isDone).toList()
      ..sort((a, b) => startMs(a).compareTo(startMs(b)));
    return [...undone, ...done];
  }

  List<TodoItem> _sortFutureTodos(List<TodoItem> list, DateTime now) {
    int startMs(TodoItem t) => t.createdDate ?? t.createdAt;
    final undone = list.where((t) => !t.isDone).toList()
      ..sort((a, b) => startMs(a).compareTo(startMs(b)));
    final done = list.where((t) => t.isDone).toList()
      ..sort((a, b) => startMs(a).compareTo(startMs(b)));
    return [...undone, ...done];
  }

  // ─────────────────────────────────────────────
  // 分组标签（替代原来大段 InkWell 标题）
  // ─────────────────────────────────────────────
  Widget _buildGroupLabel({
    required String text,
    required bool expanded,
    required VoidCallback onTap,
    Color? color,
    IconData? icon,
  }) {
    // 💡 修复：确保文字颜色识别系统深色模式或自定义背景图片
    final bool isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final bool useDarkUI = isDarkTheme || widget.isLight;

    // 根据背景智能反色，深色环境用亮白色，浅色环境用半透黑色
    final c = color ?? (useDarkUI ? Colors.white70 : Theme.of(context).colorScheme.onSurface.withOpacity(0.5));

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4, left: 2),
        child: Row(
          children: [
            Icon(expanded ? Icons.keyboard_arrow_down_rounded : Icons.chevron_right_rounded,
                size: 16, color: c),
            if (icon != null) ...[
              const SizedBox(width: 4),
              Icon(icon, size: 13, color: c),
            ],
            const SizedBox(width: 4),
            Text(text,
                style: TextStyle(
                    color: c, fontSize: 12, fontWeight: FontWeight.w700,
                    letterSpacing: 0.3)),
          ],
        ),
      ),
    );
  }

  Widget _buildTodoList() {
    final bool isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final bool useDarkUI = isDarkTheme || widget.isLight;

    final Iterable<TodoItem> activeTodos =
    widget.todos.where((t) => !t.isDeleted && !_isHistoricalTodo(t));

    if (activeTodos.isEmpty) {
      return EmptyState(text: "暂无待办，去添加一个吧", isLight: widget.isLight);
    }

    // 整体折叠
    if (!_isWholeListExpanded) {
      final int undoneCount = activeTodos.where((t) => !t.isDone).length;
      return GestureDetector(
        onTap: () => setState(() => _isWholeListExpanded = true),
        child: Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: useDarkUI
                ? Colors.white.withOpacity(0.1)
                : Theme.of(context)
                .colorScheme
                .surfaceVariant
                .withOpacity(0.3),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(Icons.checklist_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  undoneCount == 0
                      ? "🎉 所有待办均已完成"
                      : "还有 $undoneCount 个待办未完成",
                  style: TextStyle(
                      color: useDarkUI ? Colors.white : null,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5),
                ),
              ),
              Icon(Icons.expand_more,
                  size: 18,
                  color: useDarkUI ? Colors.white60 : Colors.grey),
            ],
          ),
        ),
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
        final DateTime d =
        DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
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

    final bool allTodayDone =
        todayTodos.isNotEmpty && todayTodos.every((t) => t.isDone);
    final bool showTodayItems =
        _isTodayManuallyExpanded || (!allTodayDone && _isTodayExpanded);

    final List<TodoItem> sortedTodayTodos = _sortTodayTodos(todayTodos, now);
    final List<TodoItem> sortedFutureTodos = _sortFutureTodos(futureTodos, now);

    final List<Widget> sections = [];

    // ── 以往待办（逾期）──
    if (pastTodos.isNotEmpty) {
      sections.add(_buildGroupLabel(
        text: "逾期 · ${pastTodos.length}",
        expanded: _isPastTodosExpanded,
        color: Colors.redAccent.shade200,
        onTap: () => setState(() => _isPastTodosExpanded = !_isPastTodosExpanded),
      ));
      if (_isPastTodosExpanded) {
        sections.addAll(pastTodos.map((t) => _buildTodoItemCard(t,
            isPast: true, isFuture: false, key: _getTodoKey('dismiss', t.id))));
      }
    }

    // ── 今日待办 ──
    if (!showTodayItems && todayTodos.isNotEmpty) {
      sections.add(
        GestureDetector(
          onTap: () => setState(() {
            _isTodayManuallyExpanded = true;
            _isTodayExpanded = true;
          }),
          child: Container(
            margin: const EdgeInsets.only(top: 6, bottom: 6),
            padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: useDarkUI
                  ? Colors.white.withOpacity(0.1)
                  : Theme.of(context)
                  .colorScheme
                  .surfaceVariant
                  .withOpacity(0.3),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Text("🎉", style: TextStyle(fontSize: 15)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    allTodayDone
                        ? "今日待办均已完成"
                        : "还有 ${todayTodos.where((t) => !t.isDone).length} 个今日待办",
                    style: TextStyle(
                        color: useDarkUI ? Colors.white : null,
                        fontWeight: FontWeight.w600,
                        fontSize: 13),
                  ),
                ),
                Icon(Icons.expand_more,
                    size: 16,
                    color: useDarkUI ? Colors.white60 : Colors.grey),
              ],
            ),
          ),
        ),
      );
    } else if (showTodayItems) {
      if (todayTodos.isNotEmpty) {
        sections.add(_buildGroupLabel(
          text:
          "今日 · ${todayTodos.where((t) => t.isDone).length}/${todayTodos.length} 已完成",
          expanded: true,
          onTap: () => setState(() {
            _isTodayExpanded = false;
            _isTodayManuallyExpanded = false;
          }),
        ));

        sections.add(
          ReorderableListView(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            proxyDecorator:
                (Widget child, int index, Animation<double> animation) {
              return Material(
                color: Colors.transparent,
                elevation: 8 * animation.value,
                shadowColor: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(14),
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
                  final DateTime d = DateTime(
                      t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
                  if (!d.isBefore(today) && !d.isAfter(today)) {
                    todayIndices.add(i);
                  }
                } else {
                  todayIndices.add(i);
                }
              }
              final List<TodoItem> reordered = List.from(sortedTodayTodos);
              final item = reordered.removeAt(oldIndex);
              reordered.insert(newIndex, item);
              final List<TodoItem> updatedList = List.from(widget.todos);
              for (int i = 0;
              i < todayIndices.length && i < reordered.length;
              i++) {
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
                child: _buildTodoItemCard(t,
                    isPast: false,
                    isFuture: false,
                    key: _getTodoKey('dismiss', t.id)),
              );
            }).toList(),
          ),
        );
      } else if (futureTodos.isEmpty) {
        sections.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4),
            child: Text("今日无待办",
                style: TextStyle(
                    fontSize: 12.5,
                    color: useDarkUI ? Colors.white60 : Colors.grey))));
      }
    }

    // ── 未来待办 ──
    if (sortedFutureTodos.isNotEmpty) {
      final int futureUndone = sortedFutureTodos.where((t) => !t.isDone).length;
      sections.add(_buildGroupLabel(
        text: "将来 · $futureUndone 未完成",
        expanded: _isFutureExpanded,
        icon: Icons.calendar_month_rounded,
        onTap: () =>
            setState(() => _isFutureExpanded = !_isFutureExpanded),
      ));
      if (_isFutureExpanded) {
        sections.addAll(sortedFutureTodos.map((t) => _buildTodoItemCard(t,
            isPast: false,
            isFuture: true,
            key: _getTodoKey('dismiss', t.id))));
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: sections);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final bool useDarkUI = isDarkTheme || widget.isLight;

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
                isLight: widget.isLight, // SectionHeader自带了很好的适应逻辑
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_isWholeListExpanded && undoneCount > 0)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: useDarkUI
                          ? Colors.white.withOpacity(0.2)
                          : Theme.of(context)
                          .colorScheme
                          .primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      "$undoneCount 未完成",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: useDarkUI
                            ? Colors.white
                            : Theme.of(context)
                            .colorScheme
                            .onPrimaryContainer,
                      ),
                    ),
                  ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.history,
                      size: 20,
                      color: useDarkUI ? Colors.white70 : Colors.grey),
                  onPressed: () async {
                    await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => HistoricalTodosScreen(
                                username: widget.username)));
                    widget.onRefreshRequested();
                  },
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    _isWholeListExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 20,
                    color: useDarkUI ? Colors.white70 : Colors.grey,
                  ),
                  onPressed: () =>
                      setState(() => _isWholeListExpanded = !_isWholeListExpanded),
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