import 'package:flutter/material.dart';

import '../utils/app_dialogs.dart';

/// The two intervals belong to the task being planned, not to stored events.
class PlanBufferControls extends StatelessWidget {
  const PlanBufferControls({
    super.key,
    required this.before,
    required this.after,
    required this.enabled,
    required this.onChanged,
  });
  final int before, after;
  final bool enabled;
  final void Function(int before, int after) onChanged;

  Future<void> _pick(BuildContext context, bool leading, int value) async {
    if (value != -1) {
      onChanged(leading ? value : before, leading ? after : value);
      return;
    }
    final controller = TextEditingController(
      text: '${leading ? before : after}',
    );
    String? error;
    ModalRoute<dynamic>? route;
    final result = await showAppDialog<int>(
      context: context,
      builder: (c) {
        route = ModalRoute.of(c);
        return StatefulBuilder(
          builder: (c, setState) => AlertDialog(
            title: Text(leading ? '开始前留空' : '结束后留空'),
            content: TextField(
              key: const ValueKey('plan-buffer-custom-input'),
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '分钟（0–120）',
                errorText: error,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('取消'),
              ),
              FilledButton(
                key: const ValueKey('plan-buffer-custom-confirm'),
                onPressed: () {
                  final number = int.tryParse(controller.text.trim());
                  if (number == null || number < 0 || number > 120) {
                    setState(() => error = '请输入0–120的整数');
                    return;
                  }
                  Navigator.pop(c, number);
                },
                child: const Text('确定'),
              ),
            ],
          ),
        );
      },
    );
    await route?.completed;
    controller.dispose();
    // The route no longer owns its TextField.
    if (!context.mounted) return;
    if (result != null) {
      onChanged(leading ? result : before, leading ? after : result);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('安排衔接（可选）'),
      const SizedBox(height: 8),
      LayoutBuilder(
        builder: (context, constraints) {
          Widget field(bool leading) {
            final value = leading ? before : after;
            final values = {0, 5, 10, 15, 30, value}.toList()..sort();
            return InputDecorator(
              decoration: InputDecoration(
                labelText: leading ? '开始前留空' : '结束后留空',
                border: const OutlineInputBorder(),
              ),
              child: DropdownButton<int>(
                key: ValueKey('plan-buffer-${leading ? 'before' : 'after'}'),
                value: value,
                isExpanded: true,
                isDense: true,
                underline: const SizedBox.shrink(),
                items: [
                  for (final number in values)
                    DropdownMenuItem(
                      value: number,
                      child: Text(number == 0 ? '不留空' : '$number 分钟'),
                    ),
                  const DropdownMenuItem(value: -1, child: Text('自定义…')),
                ],
                onChanged: !enabled
                    ? null
                    : (number) {
                        if (number != null) _pick(context, leading, number);
                      },
              ),
            );
          }

          final wide =
              constraints.maxWidth >= 290 &&
              MediaQuery.textScalerOf(context).scale(14) < 23;
          return wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: field(true)),
                    const SizedBox(width: 12),
                    Expanded(child: field(false)),
                  ],
                )
              : Column(
                  children: [
                    field(true),
                    const SizedBox(height: 12),
                    field(false),
                  ],
                );
        },
      ),
      const SizedBox(height: 6),
      Text('与课程、日程和其他规划保持间隔。', style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}
