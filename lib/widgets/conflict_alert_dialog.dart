import 'package:flutter/material.dart';
import '../models.dart';
import 'package:intl/intl.dart';

class ConflictAlertDialog extends StatelessWidget {
  final List<ConflictInfo> conflicts;

  const ConflictAlertDialog({Key? key, required this.conflicts}) : super(key: key);

  static void show(BuildContext context, List<ConflictInfo> conflicts) {
    if (conflicts.isEmpty) return;
    showDialog(
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
          Text('发现日程冲突'),
        ],
      ),
      content: Container(
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
                Text('您的安排与团队其他日程重叠了：', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                _buildConflictDetail('您的安排', c.item),
                SizedBox(height: 4),
                _buildConflictDetail('已有日程', c.conflictWith),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('我知道了'),
        ),
      ],
    );
  }

  Widget _buildConflictDetail(String label, Map<String, dynamic> data) {
    final title = data['content'] ?? data['title'] ?? data['course_name'] ?? '未命名';
    final start = data['start_time'] ?? data['startTime'];
    final end = data['end_time'] ?? data['endTime'];
    
    String timeStr = '时间未知';
    if (start != null && end != null) {
      final startTime = DateTime.fromMillisecondsSinceEpoch(start is String ? int.parse(start) : start, isUtc: true).toLocal();
      final endTime = DateTime.fromMillisecondsSinceEpoch(end is String ? int.parse(end) : end, isUtc: true).toLocal();
      timeStr = '${DateFormat('MM-dd HH:mm').format(startTime)} ~ ${DateFormat('HH:mm').format(endTime)}';
    }

    return Container(
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
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
