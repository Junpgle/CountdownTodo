import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SemesterSection extends StatelessWidget {
  final bool semesterEnabled;
  final ValueChanged<bool> onSemesterEnabledChanged;
  final DateTime? semesterStart;
  final DateTime? semesterEnd;
  final Function(bool) onPickSemesterDate;
  final VoidCallback onFetchFromCloud;

  const SemesterSection({
    Key? key,
    required this.semesterEnabled,
    required this.onSemesterEnabledChanged,
    required this.semesterStart,
    required this.semesterEnd,
    required this.onPickSemesterDate,
    required this.onFetchFromCloud,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 8.0, bottom: 8.0, top: 16.0),
          child: Text('学期设置',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey)),
        ),
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.linear_scale),
                title: const Text('首页学期进度条'),
                value: semesterEnabled,
                onChanged: onSemesterEnabledChanged,
              ),
              ListTile(
                contentPadding: const EdgeInsets.only(left: 56, right: 16),
                title: const Text('开学日期'),
                trailing: Text(semesterStart == null
                    ? "未设置"
                    : DateFormat('yyyy-MM-dd').format(semesterStart!)),
                onTap: () => onPickSemesterDate(true),
              ),
              ListTile(
                contentPadding: const EdgeInsets.only(left: 56, right: 16),
                title: const Text('放假日期'),
                trailing: Text(semesterEnd == null
                    ? "未设置"
                    : DateFormat('yyyy-MM-dd').format(semesterEnd!)),
                onTap: () => onPickSemesterDate(false),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading:
                    const Icon(Icons.cloud_download_outlined, color: Colors.teal),
                title: const Text('从云端同步开学/放假时间'),
                subtitle: const Text('将另一设备设置的学期日期同步到本机'),
                trailing: const Icon(Icons.chevron_right),
                onTap: onFetchFromCloud,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
