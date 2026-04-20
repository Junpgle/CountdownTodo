import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';

class TeamGanttWidget extends StatelessWidget {
  final List<TodoItem> todos;
  final int viewDays;
  final Function(TodoItem)? onTodoTap;
  
  const TeamGanttWidget({super.key, required this.todos, this.viewDays = 30, this.onTodoTap});

  @override
  Widget build(BuildContext context) {
    final datedTodos = todos.where((t) => t.dueDate != null && !t.isDone).toList();
    if (datedTodos.isEmpty) {
      return const Center(child: Text("暂无带排期的活跃任务", style: TextStyle(fontSize: 10, color: Colors.grey)));
    }

    // 确定时间跨度
    final now = DateTime.now();
    final timelineStart = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 2));
    final timelineEnd = timelineStart.add(Duration(days: viewDays));
    final totalDays = timelineEnd.difference(timelineStart).inDays;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("任务线性排期 (${viewDays == 30 ? '月视图' : viewDays == 14 ? '双周' : '周视图'})", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
              Text("${datedTodos.length} 活跃", style: const TextStyle(fontSize: 9, color: Colors.grey)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            width: 800, // 固定宽度以支持横向偏移
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. 时间轴刻度
                Row(
                  children: List.generate(totalDays, (i) {
                    final date = timelineStart.add(Duration(days: i));
                    final isToday = date.day == now.day && date.month == now.month;
                    return Container(
                      width: 800 / totalDays,
                      alignment: Alignment.center,
                      child: Text(
                        isToday ? "今天" : DateFormat('dd').format(date),
                        style: TextStyle(fontSize: 9, color: isToday ? Colors.blue : Colors.grey[400], fontWeight: isToday ? FontWeight.bold : null),
                      ),
                    );
                  }),
                ),
                const Divider(height: 12),
                // 2. 任务条
                ...datedTodos.take(6).map((todo) {
                  final start = DateTime.fromMillisecondsSinceEpoch(todo.createdDate ?? todo.createdAt).toLocal();
                  final end = todo.dueDate!;
                  
                  // 计算偏移与长度 (相对于 timelineStart)
                  double startPos = start.difference(timelineStart).inMinutes / (totalDays * 24 * 60).toDouble();
                  double duration = end.difference(start).inMinutes / (totalDays * 24 * 60).toDouble();
                  
                  startPos = startPos.clamp(0.0, 1.0);
                  if (startPos + duration > 1.0) duration = 1.0 - startPos;
                  if (duration < 0.05) duration = 0.05; // 最小可见宽度

                  final color = todo.teamUuid != null ? Colors.blueAccent : Colors.orangeAccent;

                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: Stack(
                      children: [
                        Container(height: 14, width: double.infinity, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.05), borderRadius: BorderRadius.circular(4))),
                        Positioned(
                          left: 800 * startPos,
                          width: 800 * duration,
                          child: GestureDetector(
                            onTap: () => onTodoTap?.call(todo),
                            child: Container(
                              height: 14,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [color.withOpacity(0.8), color]),
                                borderRadius: BorderRadius.circular(4),
                                boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 4)]
                              ),
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(left: 4),
                              child: Text(_safeStr(todo.title), style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _safeStr(String? s) {
    if (s == null) return '';
    return s.replaceAll(RegExp(r'[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(^|[^\uD800-\uDBFF])[\uDC00-\uDFFF]'), '');
  }
}
