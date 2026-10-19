import 'package:flutter/material.dart';

import '../models.dart';
import '../utils/page_transitions.dart';
import '../utils/time_utils.dart';
import '../widgets/app_detail_widgets.dart';
import '../widgets/floating_glass_control.dart';
import 'fixed_schedule_editor_screen.dart';

class FixedScheduleDetailScreen extends StatelessWidget {
  const FixedScheduleDetailScreen({
    super.key,
    required this.username,
    required this.item,
  });

  final String username;
  final FixedScheduleItem item;

  DateTime? get _start {
    final value = item.startTime;
    return value == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(value).toLocal();
  }

  DateTime? get _end {
    final value = item.endTime;
    return value == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(value).toLocal();
  }

  String _timeLabel(String? startLabel, String? endLabel) {
    if (startLabel == null) return '时间待定';
    if (endLabel == null) return '$startLabel · 结束待定';
    return '$startLabel - $endLabel';
  }

  String _phaseLabel(DateTime now) => switch (item.phaseAt(now)) {
        FixedSchedulePhase.timeTbd => '时间待定',
        FixedSchedulePhase.upcoming => '即将开始',
        FixedSchedulePhase.ongoing => '进行中',
        FixedSchedulePhase.ended => '已结束',
        FixedSchedulePhase.cancelled => '已取消',
      };

  String _recurrenceLabel() => switch (item.recurrence) {
        RecurrenceType.none => '不重复',
        RecurrenceType.daily => '每天重复',
        RecurrenceType.weekdays => '工作日重复',
        RecurrenceType.weekly => '每周重复',
        RecurrenceType.monthly => '每月重复',
        RecurrenceType.yearly => '每年重复',
        RecurrenceType.customDays => '每 ${item.customIntervalDays ?? 1} 天重复',
      };

  String _reminderLabel(int minutes) {
    if (minutes == 0) return '开始时';
    if (minutes % 1440 == 0) return '提前 ${minutes ~/ 1440} 天';
    if (minutes % 60 == 0) return '提前 ${minutes ~/ 60} 小时';
    return '提前 $minutes 分钟';
  }

  String get _reminderSummary {
    if (item.reminderMinutes.isEmpty) return '不提醒';
    final values = item.reminderMinutes
        .where((minutes) => minutes >= 0)
        .map(_reminderLabel)
        .toList();
    return values.isEmpty ? '不提醒' : values.join('、');
  }

  Future<void> _openEditor(BuildContext context) async {
    final result = await Navigator.of(context).push<FixedScheduleItem>(
      PageTransitions.material(
        builder: (_) => FixedScheduleEditorScreen(
          username: username,
          item: item,
        ),
      ),
    );
    if (!context.mounted || result == null) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final phase = _phaseLabel(DateTime.now());
    final date = DateTime.tryParse(item.date)?.toLocal();
    final dateLabel = date == null
        ? item.date
        : AppTimeFormats.format(date, 'yyyy年M月d日');
    final start = _start;
    final end = _end;
    final startTimeLabel = start == null ? null : AppTimeFormats.clock(start);
    final endTimeLabel = end == null ? null : AppTimeFormats.clock(end);
    final timeLabel = _timeLabel(startTimeLabel, endTimeLabel);

    return AppDetailScreen(
      appBarTitle: '固定日程详情',
      backgroundColor: colors.surface,
      icon: Icons.event_available_rounded,
      iconSize: 64,
      titleSize: 22,
      title: item.title,
      headerSubtitle: '$dateLabel · $timeLabel',
      color: colors.primary,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      scrollPhysics: const BouncingScrollPhysics(),
      appBarActions: [
        IconButton(
          style: floatingGlassPlainIconButtonStyle(),
          onPressed: () => _openEditor(context),
          icon: const Icon(Icons.edit_outlined),
          tooltip: '编辑固定日程',
        ),
      ],
      sections: [
        AppDetailSection(
          title: '日程信息',
          children: [
            AppDetailWideCard(
              icon: Icons.calendar_today_rounded,
              title: '日期',
              value: dateLabel,
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: AppDetailInfoCard(
                      icon: Icons.play_arrow_rounded,
                      title: '开始时间',
                      value: startTimeLabel ?? '待定',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      color: colors.onSurfaceVariant,
                      size: 20,
                    ),
                  ),
                  Expanded(
                    child: AppDetailInfoCard(
                      icon: Icons.stop_rounded,
                      title: '结束时间',
                      value: endTimeLabel ?? '待定',
                    ),
                  ),
                ],
              ),
            ),
            if (item.location?.trim().isNotEmpty == true)
              AppDetailWideCard(
                icon: Icons.location_on_rounded,
                title: '地点',
                value: item.location!.trim(),
              ),
          ],
        ),
        AppDetailSection(
          title: '状态与提醒',
          children: [
            Row(
              children: [
                Expanded(
                  child: AppDetailInfoCard(
                    icon: Icons.flag_rounded,
                    title: '状态',
                    value: phase,
                    valueColor:
                        phase == '进行中' ? colors.primary : colors.onSurface,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppDetailInfoCard(
                    icon: Icons.repeat_rounded,
                    title: '重复',
                    value: _recurrenceLabel(),
                  ),
                ),
              ],
            ),
            AppDetailWideCard(
              icon: Icons.notifications_active_rounded,
              title: '提醒',
              value: _reminderSummary,
            ),
          ],
        ),
        if (item.teamUuid?.trim().isNotEmpty == true)
          AppDetailSection(
            title: '协作信息',
            children: [
              AppDetailWideCard(
                icon: Icons.group_rounded,
                title: '团队日程',
                value: item.teamUuid!.trim(),
              ),
            ],
          ),
        if (item.remark?.trim().isNotEmpty == true)
          AppDetailSection(
            title: '备注详情',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  item.remark!.trim(),
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.onSurface,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
