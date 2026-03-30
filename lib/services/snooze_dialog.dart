import 'package:flutter/material.dart';

/// Predefined snooze durations in minutes
class SnoozePresets {
  SnoozePresets._();

  static const List<int> durations = [5, 10, 15, 30, 60];
  static const int minMinutes = 1;
  static const int maxMinutes = 1440; // 24 hours
}

/// Dialog for selecting snooze duration
class SnoozeDialog extends StatefulWidget {
  const SnoozeDialog({super.key});

  /// Show the snooze dialog and return the selected minutes (or null if cancelled)
  static Future<int?> show(BuildContext context) {
    return showDialog<int>(
      context: context,
      builder: (_) => const SnoozeDialog(),
    );
  }

  @override
  State<SnoozeDialog> createState() => _SnoozeDialogState();
}

class _SnoozeDialogState extends State<SnoozeDialog> {
  final _customController = TextEditingController();

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _selectMinutes(int minutes) {
    Navigator.of(context).pop(minutes);
  }

  void _submitCustom() {
    final minutes = int.tryParse(_customController.text);
    if (minutes != null &&
        minutes >= SnoozePresets.minMinutes &&
        minutes <= SnoozePresets.maxMinutes) {
      _selectMinutes(minutes);
    }
  }

  String _formatPresetLabel(int minutes) {
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      return '$hours 小时';
    }
    return '$minutes 分钟';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('稍后提醒'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: SnoozePresets.durations
                .map((m) => ActionChip(
                      label: Text(_formatPresetLabel(m)),
                      onPressed: () => _selectMinutes(m),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _customController,
            decoration: InputDecoration(
              labelText: '自定义时长（分钟）',
              border: const OutlineInputBorder(),
              hintText:
                  '输入 ${SnoozePresets.minMinutes}-${SnoozePresets.maxMinutes}',
            ),
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _submitCustom(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _submitCustom,
          child: const Text('确定'),
        ),
      ],
    );
  }
}
