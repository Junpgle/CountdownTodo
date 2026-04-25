import 'package:flutter/material.dart';
import '../models.dart';
import 'package:intl/intl.dart';

class ConflictAlertDialog extends StatelessWidget {
  final List<ConflictInfo> conflicts;

  const ConflictAlertDialog({super.key, required this.conflicts});

  /// Returns true if user chose to navigate to conflict center.
  static Future<bool?> show(BuildContext context, List<ConflictInfo> conflicts) {
    if (conflicts.isEmpty) return Future.value(null);
    return showDialog<bool>(
      context: context,
      builder: (context) => ConflictAlertDialog(conflicts: conflicts),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange),
          SizedBox(width: 10),
          Text('发现数据冲突'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: conflicts.length,
          separatorBuilder: (_, __) => Divider(),
          itemBuilder: (context, index) {
            final c = conflicts[index];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.type == 'schedule_conflict' ? '检测到日程时间重叠：' : '检测到版本冲突：',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                _buildConflictDetail('您的版本', c.item),
                if (c.conflictWith.isNotEmpty) ...[
                  SizedBox(height: 4),
                  _buildConflictDetail(
                    c.type == 'schedule_conflict' ? '冲突日程' : '服务器版本',
                    c.conflictWith,
                  ),
                ],
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('稍后处理'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: Icon(Icons.compare_arrows_rounded, size: 18),
          label: Text('进入冲突中心'),
        ),
      ],
    );
  }

  Widget _buildConflictDetail(String label, Map<String, dynamic> data) {
    final title = data['content'] ?? data['title'] ?? data['courseName'] ?? data['course_name'] ?? '未命名';
    final start = data['start_time'] ?? data['startTime'] ?? data['created_date'] ?? data['createdDate'];
    final end = data['end_time'] ?? data['endTime'] ?? data['due_date'] ?? data['dueDate'];

    String timeStr = '时间未知';
    if (start != null && end != null) {
      final startTime = DateTime.fromMillisecondsSinceEpoch(
          start is String ? int.parse(start) : (start is int ? start : 0),
          isUtc: true).toLocal();
      final endTime = DateTime.fromMillisecondsSinceEpoch(
          end is String ? int.parse(end) : (end is int ? end : 0),
          isUtc: true).toLocal();

      final startNum = int.tryParse(start.toString()) ?? 0;
      final endNum = int.tryParse(end.toString()) ?? 0;

      if (startTime.year == 1970 && startNum < 2400) {
        final startHH = startNum ~/ 100;
        final startMM = startNum % 100;
        final endHH = endNum ~/ 100;
        final endMM = endNum % 100;
        timeStr = '${startHH.toString().padLeft(2,'0')}:${startMM.toString().padLeft(2,'0')} ~ ${endHH.toString().padLeft(2,'0')}:${endMM.toString().padLeft(2,'0')}';
      } else {
        timeStr = '${DateFormat('MM-dd HH:mm').format(startTime)} ~ ${DateFormat('HH:mm').format(endTime)}';
      }
    }

    return Container(
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: $title', style: TextStyle(fontSize: 13)),
          Text(timeStr, style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}
