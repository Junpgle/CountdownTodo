import 'package:flutter/material.dart';

import 'optional_liquid_glass_surface.dart';

class TodoOverdueTriageBanner extends StatelessWidget {
  final int count;
  final bool isLight;
  final VoidCallback onTap;

  const TodoOverdueTriageBanner({
    super.key,
    required this.count,
    required this.isLight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final Color warningColor = isDark
        ? Colors.redAccent.shade100
        : Colors.redAccent.shade700;

    final Color bgColor = isDark
        ? Colors.redAccent.withValues(alpha: 0.12)
        : Colors.red.shade50.withValues(alpha: 0.85);

    final Color borderColor = isDark
        ? Colors.redAccent.withValues(alpha: 0.28)
        : Colors.redAccent.withValues(alpha: 0.2);

    return OptionalLiquidGlassCard(
      key: const ValueKey('todo_overdue_triage_banner'),
      highContrast: true,
      borderRadius: 16,
      fallbackDecoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: warningColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.history_toggle_off_rounded,
                  size: 18,
                  color: warningColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '发现 $count 项待办已逾期',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: warningColor,
                      ),
                    ),
                    Text(
                      '一键顺延或排入空闲规划时段',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: warningColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: warningColor.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '快速整理',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: warningColor,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 10,
                      color: warningColor,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
