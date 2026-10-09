import 'package:flutter/material.dart';

import '../models/ai_context_mode.dart';

class AiContextModeSelector extends StatelessWidget {
  const AiContextModeSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final AiContextMode value;
  final ValueChanged<AiContextMode>? onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('上下文获取方式'),
      const SizedBox(height: 8),
      SegmentedButton<AiContextMode>(
        segments: const [
          ButtonSegment(
            value: AiContextMode.functionCalling,
            label: Text('工具查询'),
            icon: Icon(Icons.manage_search_rounded),
          ),
          ButtonSegment(
            value: AiContextMode.smartContextInjection,
            label: Text('智能注入'),
            icon: Icon(Icons.auto_awesome_rounded),
          ),
        ],
        selected: {value},
        onSelectionChanged: onChanged == null
            ? null
            : (selection) => onChanged!(selection.single),
      ),
      const SizedBox(height: 8),
      Text(
        value.description,
        style: TextStyle(
          fontSize: 12,
          height: 1.4,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}
