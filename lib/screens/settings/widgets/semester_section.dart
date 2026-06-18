import 'package:flutter/material.dart';

import '../../../utils/app_time_formats.dart';
import '../../../widgets/app_settings_widgets.dart';

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
    super.key,
    this.highlightTarget,
    this.itemKeys,
    required this.semesterEnabled,
    required this.onSemesterEnabledChanged,
    required this.semesterStart,
    required this.semesterEnd,
    required this.onPickSemesterDate,
    required this.onFetchFromCloud,
  });

  Widget _buildTile({
    required BuildContext context,
    required String targetId,
    required Widget child,
  }) {
    return AppSettingsHighlightedTile(
      targetId: targetId,
      highlightTarget: highlightTarget,
      itemKeys: itemKeys,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppSettingsSection(
      title: '学期设置',
      children: [
        _buildTile(
          context: context,
          targetId: 'semester_progress',
          child: SwitchListTile(
            secondary: Icon(Icons.linear_scale, color: colorScheme.primary),
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
                : AppTimeFormats.date(semesterStart!)),
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
                : AppTimeFormats.date(semesterEnd!)),
            onTap: () => onPickSemesterDate(false),
          ),
        ),
        const AppSettingsDivider(),
        _buildTile(
          context: context,
          targetId: 'semester_sync',
          child: ListTile(
            leading: Icon(Icons.cloud_download_outlined,
                color: colorScheme.secondary),
            title: const Text('从云端同步开学/放假时间'),
            subtitle: const Text('将另一设备设置的学期日期同步到本机'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onFetchFromCloud,
          ),
        ),
      ],
    );
  }
}
