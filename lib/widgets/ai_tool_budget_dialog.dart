import 'package:flutter/material.dart';

import '../models/ai_tool_budget.dart';
import '../utils/app_dialogs.dart';

/// Opens a Material 3 dialog for customizing per-turn AI tool-calling budgets.
Future<AiToolBudget?> showAiToolBudgetDialog(
  BuildContext context, {
  required AiToolBudget initialBudget,
}) {
  return showAppDialog<AiToolBudget>(
    context: context,
    builder: (dialogContext) =>
        _AiToolBudgetDialog(initialBudget: initialBudget.normalized()),
  );
}

class _AiToolBudgetDialog extends StatefulWidget {
  const _AiToolBudgetDialog({required this.initialBudget});

  final AiToolBudget initialBudget;

  @override
  State<_AiToolBudgetDialog> createState() => _AiToolBudgetDialogState();
}

class _AiToolBudgetDialogState extends State<_AiToolBudgetDialog> {
  late AiToolBudget _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialBudget;
  }

  Widget _buildLimitRow({
    required BuildContext context,
    required String title,
    required String valueLabel,
    required int? currentValue,
    required int defaultValue,
    required int min,
    required int max,
    required int divisions,
    required ValueChanged<int?> onChanged,
    int Function(double)? snapValue,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isUnlimited = currentValue == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                valueLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: const Text('不限'),
              selected: isUnlimited,
              visualDensity: VisualDensity.compact,
              onSelected: (unlimited) {
                onChanged(unlimited ? null : defaultValue);
              },
            ),
          ],
        ),
        if (!isUnlimited)
          Slider(
            value: currentValue.toDouble().clamp(
              min.toDouble(),
              max.toDouble(),
            ),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: divisions,
            onChanged: (next) {
              final resolved = snapValue != null
                  ? snapValue(next)
                  : next.round();
              onChanged(resolved);
            },
          )
        else
          const SizedBox(height: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activePreset = _draft.matchingPreset;
    return AlertDialog(
      title: const Text('单轮工具调用预算'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in AiToolBudgetPreset.values)
                    ChoiceChip(
                      label: Text(preset.label),
                      selected: activePreset == preset,
                      onSelected: (_) {
                        setState(() {
                          _draft = AiToolBudget.forPreset(preset);
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _buildLimitRow(
                context: context,
                title: '最大查询轮数',
                valueLabel: _draft.maxQueryRounds == null
                    ? '不限'
                    : '${_draft.maxQueryRounds} 轮',
                currentValue: _draft.maxQueryRounds,
                defaultValue: AiToolBudget.standard.maxQueryRounds!,
                min: AiToolBudget.minQueryRounds,
                max: AiToolBudget.maxQueryRoundsSliderMax,
                divisions:
                    AiToolBudget.maxQueryRoundsSliderMax -
                    AiToolBudget.minQueryRounds,
                onChanged: (next) {
                  setState(() {
                    _draft = _draft.copyWith(maxQueryRounds: next);
                  });
                },
              ),
              _buildLimitRow(
                context: context,
                title: '最大调用次数',
                valueLabel: _draft.maxCalls == null
                    ? '不限'
                    : '${_draft.maxCalls} 次',
                currentValue: _draft.maxCalls,
                defaultValue: AiToolBudget.standard.maxCalls!,
                min: AiToolBudget.minCalls,
                max: AiToolBudget.maxCallsSliderMax,
                divisions:
                    AiToolBudget.maxCallsSliderMax - AiToolBudget.minCalls,
                onChanged: (next) {
                  setState(() {
                    _draft = _draft.copyWith(maxCalls: next);
                  });
                },
              ),
              _buildLimitRow(
                context: context,
                title: '单轮数据字符上限',
                valueLabel: _draft.maxTurnChars == null
                    ? '不限'
                    : '${_draft.formattedChars} 字符',
                currentValue: _draft.maxTurnChars,
                defaultValue: AiToolBudget.standard.maxTurnChars!,
                min: AiToolBudget.minTurnChars,
                max: AiToolBudget.maxTurnCharsSliderMax,
                divisions:
                    (AiToolBudget.maxTurnCharsSliderMax -
                        AiToolBudget.minTurnChars) ~/
                    4000,
                snapValue: (next) => ((next / 4000).round() * 4000).clamp(
                  AiToolBudget.minTurnChars,
                  AiToolBudget.maxTurnCharsSliderMax,
                ),
                onChanged: (next) {
                  setState(() {
                    _draft = _draft.copyWith(maxTurnChars: next);
                  });
                },
              ),
              const SizedBox(height: 4),
              Text(
                '选择「不限」时不对单轮工具调用轮数、次数或回传数据总量设上限；请注意上下文长度与 Token 消耗。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            setState(() {
              _draft = AiToolBudget.standard;
            });
          },
          child: const Text('恢复默认'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_draft.normalized()),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
