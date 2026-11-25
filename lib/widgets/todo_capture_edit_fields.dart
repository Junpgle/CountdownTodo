import 'package:flutter/material.dart';

import '../models.dart';
import '../utils/app_dialogs.dart';
import '../utils/semester_week_context.dart';
import '../utils/time_utils.dart';
import 'floating_glass_control.dart';

/// 待办全天/截止时间编辑区块（`某天内完成`开关 + 日期/截止时间选择器）。
class TodoAllDayScheduleFields extends StatelessWidget {
  final bool isAllDay;
  final DateTime createdAt;
  final DateTime? dueDate;
  final void Function(bool isAllDay, DateTime createdAt, DateTime? dueDate)
  onChanged;
  final SemesterWeekContext? semesterWeekContext;
  final String Function(DateTime date, String baseText)? formatDateLabel;
  final String Function(DateTime date, String baseText)? formatDateTimeLabel;
  final TextStyle? allDayTitleStyle;
  final Color? activeThumbColor;
  final bool showTrailingIcons;
  final DateTime Function()? defaultDeadlineTimeBuilder;

  const TodoAllDayScheduleFields({
    super.key,
    required this.isAllDay,
    required this.createdAt,
    required this.dueDate,
    required this.onChanged,
    this.semesterWeekContext,
    this.formatDateLabel,
    this.formatDateTimeLabel,
    this.allDayTitleStyle,
    this.activeThumbColor,
    this.showTrailingIcons = false,
    this.defaultDeadlineTimeBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dateText = AppTimeFormats.dateFormatter('yyyy-MM-dd')
        .format(createdAt);
    final formattedAllDayDate = formatDateLabel != null
        ? formatDateLabel!(createdAt, dateText)
        : dateText;
    final deadlineText = dueDate == null
        ? '设置截止时间（当前未安排）'
        : '${formatDateTimeLabel != null ? formatDateTimeLabel!(dueDate!, AppTimeFormats.dateFormatter('yyyy-MM-dd HH:mm').format(dueDate!)) : AppTimeFormats.dateFormatter('yyyy-MM-dd HH:mm').format(dueDate!)} 前完成';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LiquidGlassSwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('某天内完成', style: allDayTitleStyle),
          value: isAllDay,
          activeThumbColor: activeThumbColor,
          onChanged: (val) {
            final wasDateOnlyRange =
                dueDate != null &&
                TodoItem.looksLikeLegacyDateOnlyRange(createdAt, dueDate!);
            if (val) {
              final nextCreatedAt = DateTime(
                createdAt.year,
                createdAt.month,
                createdAt.day,
              );
              final nextDueDate = DateTime(
                dueDate?.year ?? nextCreatedAt.year,
                dueDate?.month ?? nextCreatedAt.month,
                dueDate?.day ?? nextCreatedAt.day,
                23,
                59,
              );
              onChanged(true, nextCreatedAt, nextDueDate);
            } else if (wasDateOnlyRange) {
              final now = DateTime.now();
              final nextCreatedAt = DateTime(
                createdAt.year,
                createdAt.month,
                createdAt.day,
                now.hour,
                now.minute,
              );
              onChanged(false, nextCreatedAt, null);
            } else {
              onChanged(false, createdAt, dueDate);
            }
          },
        ),
        if (isAllDay)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('完成日期: $formattedAllDayDate'),
            trailing: showTrailingIcons
                ? Icon(
                    Icons.edit_calendar,
                    size: 20,
                    color: colorScheme.primary,
                  )
                : null,
            onTap: () async {
              final pickedDate = await showAppDatePicker(
                context: context,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                initialDate: createdAt,
                semesterWeekContext: semesterWeekContext,
              );
              if (pickedDate != null) {
                onChanged(
                  true,
                  DateTime(pickedDate.year, pickedDate.month, pickedDate.day),
                  DateTime(
                    pickedDate.year,
                    pickedDate.month,
                    pickedDate.day,
                    23,
                    59,
                  ),
                );
              }
            },
          ),
        if (!isAllDay)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(deadlineText),
            trailing: showTrailingIcons
                ? Icon(Icons.event, size: 20, color: colorScheme.primary)
                : null,
            onTap: () async {
              final pickedDate = await showAppDatePicker(
                context: context,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                initialDate: dueDate ?? createdAt,
                semesterWeekContext: semesterWeekContext,
              );
              if (pickedDate == null || !context.mounted) return;
              final fallbackInitial = defaultDeadlineTimeBuilder != null
                  ? defaultDeadlineTimeBuilder!()
                  : DateTime.now();
              final pickedTime = await showAppTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(dueDate ?? fallbackInitial),
              );
              if (pickedTime != null) {
                onChanged(
                  false,
                  createdAt,
                  DateTime(
                    pickedDate.year,
                    pickedDate.month,
                    pickedDate.day,
                    pickedTime.hour,
                    pickedTime.minute,
                  ),
                );
              }
            },
          ),
      ],
    );
  }
}

/// 待办重复规则与循环截止日期选择区块。
class TodoRecurrencePickerFields extends StatelessWidget {
  final RecurrenceType recurrence;
  final TextEditingController customDaysController;
  final DateTime? recurrenceEndDate;
  final ValueChanged<RecurrenceType> onRecurrenceChanged;
  final ValueChanged<int?> onCustomDaysChanged;
  final ValueChanged<DateTime?> onRecurrenceEndDateChanged;
  final bool showPrefixIcon;
  final SemesterWeekContext? semesterWeekContext;
  final String endDatePrefix;
  final String Function(DateTime date, String baseText)? formatEndDateLabel;
  final DateTime Function()? initialEndDateBuilder;
  final Color? trailingIconColor;

  const TodoRecurrencePickerFields({
    super.key,
    required this.recurrence,
    required this.customDaysController,
    required this.recurrenceEndDate,
    required this.onRecurrenceChanged,
    required this.onCustomDaysChanged,
    required this.onRecurrenceEndDateChanged,
    this.showPrefixIcon = false,
    this.semesterWeekContext,
    this.endDatePrefix = '重复结束: ',
    this.formatEndDateLabel,
    this.initialEndDateBuilder,
    this.trailingIconColor,
  });

  @override
  Widget build(BuildContext context) {
    final endDateText = recurrenceEndDate == null
        ? '重复结束日期 (可选)'
        : '$endDatePrefix${formatEndDateLabel != null ? formatEndDateLabel!(recurrenceEndDate!, AppTimeFormats.dateFormatter('yyyy-MM-dd').format(recurrenceEndDate!)) : AppTimeFormats.dateFormatter('yyyy-MM-dd').format(recurrenceEndDate!)}';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<RecurrenceType>(
          initialValue: recurrence,
          decoration: InputDecoration(
            labelText: '重复 (可选)',
            prefixIcon: showPrefixIcon
                ? const Icon(Icons.replay_rounded)
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          items: const [
            DropdownMenuItem(value: RecurrenceType.none, child: Text('不重复')),
            DropdownMenuItem(value: RecurrenceType.daily, child: Text('每天重复')),
            DropdownMenuItem(value: RecurrenceType.weekly, child: Text('每周重复')),
            DropdownMenuItem(
              value: RecurrenceType.monthly,
              child: Text('每月重复'),
            ),
            DropdownMenuItem(value: RecurrenceType.yearly, child: Text('每年重复')),
            DropdownMenuItem(
              value: RecurrenceType.weekdays,
              child: Text('工作日'),
            ),
            DropdownMenuItem(
              value: RecurrenceType.customDays,
              child: Text('间隔几天'),
            ),
          ],
          onChanged: (val) {
            if (val != null) onRecurrenceChanged(val);
          },
        ),
        if (recurrence == RecurrenceType.customDays)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TextField(
              controller: customDaysController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '间隔天数',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (val) => onCustomDaysChanged(int.tryParse(val)),
            ),
          ),
        if (recurrence != RecurrenceType.none)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(endDateText),
            trailing: Icon(
              Icons.event_busy,
              size: 20,
              color: trailingIconColor,
            ),
            onTap: () async {
              final picked = await showAppDatePicker(
                context: context,
                initialDate:
                    recurrenceEndDate ??
                    (initialEndDateBuilder != null
                        ? initialEndDateBuilder!()
                        : DateTime.now()),
                firstDate: DateTime.now(),
                lastDate: DateTime(2100),
                semesterWeekContext: semesterWeekContext,
              );
              if (picked != null) {
                onRecurrenceEndDateChanged(picked);
              }
            },
          ),
      ],
    );
  }
}

/// 待办提醒提前量下拉框。
class TodoReminderLeadTimeDropdown extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const TodoReminderLeadTimeDropdown({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: '温馨提醒 (提前量)',
        prefixIcon: const Icon(Icons.notifications_active_outlined),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: const [
        DropdownMenuItem(value: 0, child: Text('准时提醒')),
        DropdownMenuItem(value: 5, child: Text('提前 5 分钟')),
        DropdownMenuItem(value: 10, child: Text('提前 10 分钟')),
        DropdownMenuItem(value: 15, child: Text('提前 15 分钟')),
        DropdownMenuItem(value: 30, child: Text('提前 30 分钟')),
        DropdownMenuItem(value: 45, child: Text('提前 45 分钟')),
        DropdownMenuItem(value: 60, child: Text('提前 1 小时')),
        DropdownMenuItem(value: 120, child: Text('提前 2 小时')),
        DropdownMenuItem(value: 1440, child: Text('提前 1 天')),
      ],
      onChanged: (val) {
        if (val != null) onChanged(val);
      },
    );
  }
}
