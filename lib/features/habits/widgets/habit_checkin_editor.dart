import 'package:flutter/material.dart';

import '../models/habit_checkin.dart';
import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../services/habit_rule_resolver.dart';
import 'habit_format.dart';

/// 打卡记录编辑结果。返回副本，调用方确认后再交给仓储保存。
Future<HabitCheckIn?> showHabitCheckInEditor({
  required BuildContext context,
  required HabitGoal goal,
  required HabitGoalRuleRevision rule,
  required HabitCheckIn checkIn,
}) async {
  final valueController = TextEditingController(
    text: checkIn.value == checkIn.value.roundToDouble()
        ? checkIn.value.round().toString()
        : checkIn.value.toString(),
  );
  final noteController = TextEditingController(text: checkIn.note ?? '');
  final formKey = GlobalKey<FormState>();
  final isTimeType = goal.sourceType == HabitSourceType.timeCheckIn;

  // localOccurredAt 是按历史时区还原出的“墙上时间”，其 DateTime 标记为 UTC。
  // 转成当前设备的本地 DateTime 后，toUtc() 才会得到正确的保存时间。
  final savedWallTime = checkIn.localOccurredAt;
  var editedTime = DateTime(
    savedWallTime.year,
    savedWallTime.month,
    savedWallTime.day,
    savedWallTime.hour,
    savedWallTime.minute,
    savedWallTime.second,
    savedWallTime.millisecond,
    savedWallTime.microsecond,
  );

  try {
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isTimeType ? '编辑打卡时间' : '编辑记录'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isTimeType)
                  TextFormField(
                    controller: valueController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText:
                          '数量${rule.unit.isNotEmpty ? '（${rule.unit}）' : ''}',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    validator: (text) {
                      final value = double.tryParse(text?.trim() ?? '');
                      if (value == null || value <= 0) {
                        return '请输入大于 0 的数量';
                      }
                      return null;
                    },
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(editedTime),
                        helpText: '实际发生时间',
                      );
                      if (picked != null) {
                        setDialogState(() {
                          editedTime = DateTime(
                            editedTime.year,
                            editedTime.month,
                            editedTime.day,
                            picked.hour,
                            picked.minute,
                          );
                        });
                      }
                    },
                    icon: const Icon(Icons.schedule_rounded, size: 18),
                    label: Text(
                      '实际时间：${HabitText.timeOfDay(editedTime)}',
                    ),
                  ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteController,
                  maxLength: 50,
                  decoration: const InputDecoration(
                    labelText: '备注（可选）',
                    border: OutlineInputBorder(),
                    isDense: true,
                    counterText: '',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (!isTimeType &&
                    !(formKey.currentState?.validate() ?? false)) {
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return null;

    final edited = HabitCheckIn.fromJson(checkIn.toJson());
    if (isTimeType) {
      edited
        ..occurredAt = editedTime.toUtc().millisecondsSinceEpoch
        ..logicalDate = HabitRuleResolver.dayKey(
          HabitRuleResolver.logicalDateFor(
            editedTime,
            rule.dayBoundaryMinute,
          ),
        )
        ..timezoneOffsetMinutes = editedTime.timeZoneOffset.inMinutes;
    } else {
      edited.value = double.parse(valueController.text.trim());
    }
    edited.note =
        noteController.text.trim().isEmpty ? null : noteController.text.trim();
    return edited;
  } finally {
    valueController.dispose();
    noteController.dispose();
  }
}
