import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SemesterSection extends StatelessWidget {
  final String? highlightTarget;
  final Map<String, GlobalKey>? itemKeys;
  final bool semesterEnabled;
  final ValueChanged<bool> onSemesterEnabledChanged;
  final DateTime? semesterStart;
  final DateTime? semesterEnd;
  final Function(bool) onPickSemesterDate;
  final VoidCallback onFetchFromCloud;

  const SemesterSection({
    Key? key,
    this.highlightTarget,
    this.itemKeys,
    required this.semesterEnabled,
    required this.onSemesterEnabledChanged,
    required this.semesterStart,
    required this.semesterEnd,
    required this.onPickSemesterDate,
    required this.onFetchFromCloud,
  }) : super(key: key);

  Widget _buildTile({
    required BuildContext context,
    required String targetId,
    required Widget child,
  }) {
    final bool isHighlighted = highlightTarget == targetId;
    return Container(
      key: itemKeys?[targetId],
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: isHighlighted
              ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: child,
      ),
    );
  }

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
              _buildTile(
                context: context,
                targetId: 'semester_progress',
                child: SwitchListTile(
                  secondary: const Icon(Icons.linear_scale),
                  title: const Text('首页学期进度条'),
                  value: semesterEnabled,
                  onChanged: onSemesterEnabledChanged,
                ),
              ),
              _buildTile(
                context: context,
                targetId: 'semester_start',
                child: ListTile(
                  contentPadding: const EdgeInsets.only(left: 56, right: 16),
                  title: const Text('开学日期'),
                  trailing: Text(semesterStart == null
                      ? "未设置"
                      : DateFormat('yyyy-MM-dd').format(semesterStart!)),
                  onTap: () => onPickSemesterDate(true),
                ),
              ),
              _buildTile(
                context: context,
                targetId: 'semester_end',
                child: ListTile(
                  contentPadding: const EdgeInsets.only(left: 56, right: 16),
                  title: const Text('放假日期'),
                  trailing: Text(semesterEnd == null
                      ? "未设置"
                      : DateFormat('yyyy-MM-dd').format(semesterEnd!)),
                  onTap: () => onPickSemesterDate(false),
                ),
              ),
              const Divider(height: 1, indent: 56),
              _buildTile(
                context: context,
                targetId: 'semester_sync',
                child: ListTile(
                  leading: const Icon(Icons.cloud_download_outlined,
                      color: Colors.teal),
                  title: const Text('从云端同步开学/放假时间'),
                  subtitle: const Text('将另一设备设置的学期日期同步到本机'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onFetchFromCloud,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
