import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/countdown_todo_tutorial_links.dart';
import 'optional_liquid_glass_surface.dart';

class AdvancedAiTutorialCard extends StatelessWidget {
  const AdvancedAiTutorialCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return OptionalLiquidGlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      highContrast: true,
      fallbackDecoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AI 助手进阶指南',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '打开 CountDownTodo 高阶使用教程中的 AI 专题，继续了解进阶用法。',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openTutorial(context),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('打开 AI 高阶教程'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openTutorial(BuildContext context) async {
    try {
      final launched = await launchUrl(
        CountdownTodoTutorialLinks.aiAssistantAdvanced,
        mode: LaunchMode.externalApplication,
      );
      if (launched || !context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法打开教程链接，请稍后重试。')));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('打开教程失败，请检查网络后重试。')));
    }
  }
}
