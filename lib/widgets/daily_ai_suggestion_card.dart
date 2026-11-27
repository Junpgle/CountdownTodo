import 'package:flutter/material.dart';

import '../models.dart';
import '../services/daily_ai_suggestion_service.dart';
import 'ai_water_border.dart';
import 'floating_glass_control.dart';
import 'optional_liquid_glass_surface.dart';

class DailyAiSuggestionCard extends StatelessWidget {
  final DailyAiSuggestionSnapshot snapshot;
  final bool isLight;
  final List<TodoItem> todos;
  final VoidCallback onRefresh;
  final ValueChanged<bool> onToggleExpanded;
  final VoidCallback onDismiss;
  final VoidCallback onOpenModelConfig;
  final ValueChanged<TodoItem> onOpenTodo;
  final ValueChanged<String> onOpenAiChat;
  final VoidCallback onAskAiOnce;
  final VoidCallback onEnableDaily;
  final VoidCallback onKeepManualSection;
  final VoidCallback onDeclinePrompt;

  const DailyAiSuggestionCard({
    super.key,
    required this.snapshot,
    required this.isLight,
    required this.todos,
    required this.onRefresh,
    required this.onToggleExpanded,
    required this.onDismiss,
    required this.onOpenModelConfig,
    required this.onOpenTodo,
    required this.onOpenAiChat,
    required this.onAskAiOnce,
    required this.onEnableDaily,
    required this.onKeepManualSection,
    required this.onDeclinePrompt,
  });

  TodoItem? _findMatchedTodo(String? todoId) {
    if (todoId == null || todoId.isEmpty) return null;
    for (final todo in todos) {
      if (!todo.isDeleted && todo.id == todoId) return todo;
    }
    return null;
  }

  Color _priorityColor(
    DailyAiSuggestionPriority priority,
    ColorScheme scheme,
    bool isDark,
  ) {
    return switch (priority) {
      DailyAiSuggestionPriority.high =>
        isDark ? const Color(0xFFFF8A80) : scheme.error,
      DailyAiSuggestionPriority.medium => scheme.primary,
      DailyAiSuggestionPriority.low => scheme.tertiary,
    };
  }

  String _priorityLabel(DailyAiSuggestionPriority priority) {
    return switch (priority) {
      DailyAiSuggestionPriority.high => '优先',
      DailyAiSuggestionPriority.medium => '建议',
      DailyAiSuggestionPriority.low => '顺便',
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!snapshot.shouldShowOnDashboard) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final useLightHeader = isDark || isLight;
    final headerTextColor = useLightHeader ? Colors.white : scheme.onSurface;
    final headerIconColor = useLightHeader ? Colors.white70 : scheme.primary;

    final suggestion = snapshot.suggestion;
    final isExpanded = suggestion?.isExpanded ?? true;

    return Padding(
      key: const ValueKey<String>('home-daily-ai-suggestion-card'),
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: useLightHeader
                        ? Colors.white.withValues(alpha: 0.15)
                        : scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: 20,
                    color: useLightHeader ? Colors.white : scheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '今日 AI 建议',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: headerTextColor,
                  ),
                ),
                if (suggestion != null && suggestion.items.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: useLightHeader
                          ? Colors.white.withValues(alpha: 0.2)
                          : scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${suggestion.items.length} 项',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: useLightHeader
                            ? Colors.white
                            : scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (snapshot.isLoading)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: useLightHeader ? Colors.white : scheme.primary,
                      ),
                    ),
                  ),
                if (suggestion != null)
                  IconButton(
                    key: const ValueKey<String>(
                      'daily-ai-suggestion-expand-btn',
                    ),
                    constraints: const BoxConstraints.tightFor(
                      width: floatingGlassStandardControlSize,
                      height: floatingGlassStandardControlSize,
                    ),
                    visualDensity: VisualDensity.standard,
                    style: floatingGlassPlainIconButtonStyle(),
                    tooltip: isExpanded ? '收起今日 AI 建议' : '展开今日 AI 建议',
                    onPressed: () => onToggleExpanded(!isExpanded),
                    icon: Icon(
                      isExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 20,
                      color: headerIconColor,
                    ),
                  ),
                IconButton(
                  key: const ValueKey<String>(
                    'daily-ai-suggestion-dismiss-btn',
                  ),
                  constraints: const BoxConstraints.tightFor(
                    width: floatingGlassStandardControlSize,
                    height: floatingGlassStandardControlSize,
                  ),
                  visualDensity: VisualDensity.standard,
                  style: floatingGlassPlainIconButtonStyle(),
                  tooltip: '前往今日 AI 建议设置',
                  onPressed: onDismiss,
                  icon: Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: headerIconColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          AiWaterRippleBorder(
            isLight: isLight,
            visibleOnlyWhenInViewport: true,
            borderRadius: BorderRadius.circular(24),
            child: OptionalLiquidGlassCard(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              borderRadius: 24,
              tint: scheme.primary.withValues(alpha: 0.08),
              isDark: isDark,
              fallbackDecoration: BoxDecoration(
                color: isLight
                    ? (isDark
                          ? scheme.surfaceContainerLow.withValues(alpha: 0.78)
                          : scheme.surface.withValues(alpha: 0.9))
                    : scheme.surfaceContainerHighest.withValues(
                        alpha: isDark ? 0.35 : 0.45,
                      ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isLight
                      ? (isDark
                            ? Colors.white.withValues(alpha: 0.15)
                            : Colors.white.withValues(alpha: 0.6))
                      : scheme.outlineVariant.withValues(
                          alpha: isDark ? 0.25 : 0.4,
                        ),
                ),
              ),
              child: _buildBody(
                context,
                scheme: scheme,
                isDark: isDark,
                suggestion: suggestion,
                isExpanded: isExpanded,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required ColorScheme scheme,
    required bool isDark,
    required DailyAiSuggestion? suggestion,
    required bool isExpanded,
  }) {
    final textColor = scheme.onSurface;
    final subTextColor = scheme.onSurfaceVariant;
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : scheme.outlineVariant.withValues(alpha: 0.35);

    if (snapshot.showFirstOpenPrompt) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '不知道做什么？问问AI',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '已检测到你已配置 AI 模型，可根据今日待办、日程与倒数日为你梳理今天的行动重点。',
            style: TextStyle(fontSize: 12.5, height: 1.45, color: subTextColor),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonalIcon(
                key: const ValueKey<String>('daily-ai-prompt-ask-once-btn'),
                onPressed: onAskAiOnce,
                icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                label: const Text('问问AI'),
              ),
              FilledButton(
                key: const ValueKey<String>('daily-ai-prompt-enable-daily-btn'),
                onPressed: onEnableDaily,
                child: const Text('以后每天打开都提供建议'),
              ),
              OutlinedButton(
                key: const ValueKey<String>('daily-ai-prompt-keep-manual-btn'),
                onPressed: onKeepManualSection,
                child: const Text('保留板块，手动生成'),
              ),
              TextButton(
                key: const ValueKey<String>('daily-ai-prompt-decline-btn'),
                onPressed: onDeclinePrompt,
                style: TextButton.styleFrom(foregroundColor: subTextColor),
                child: const Text('我不需要'),
              ),
            ],
          ),
        ],
      );
    }

    if (snapshot.showManualGenerateCard) {
      return Row(
        children: [
          Expanded(
            child: Text(
              '今日尚未生成建议，点击按钮随时为你梳理今日重点。',
              style: TextStyle(fontSize: 13, height: 1.45, color: subTextColor),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.tonalIcon(
            key: const ValueKey<String>('daily-ai-manual-generate-btn'),
            onPressed: onAskAiOnce,
            icon: const Icon(Icons.auto_awesome_rounded, size: 16),
            label: const Text('生成今日建议'),
          ),
        ],
      );
    }

    if (snapshot.needsModelConfig) {
      return Row(
        children: [
          Expanded(
            child: Text(
              '已开启每日 AI 建议，请先配置 AI 模型与 API Key。',
              style: TextStyle(fontSize: 13, color: subTextColor, height: 1.4),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: onOpenModelConfig,
            child: const Text('去配置'),
          ),
        ],
      );
    }

    if (snapshot.isLoading && suggestion == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'AI 正在结合今日待办、日程与倒数日生成建议...',
                style: TextStyle(fontSize: 13, color: subTextColor),
              ),
            ),
          ],
        ),
      );
    }

    if (snapshot.errorMessage != null && suggestion == null) {
      return Row(
        children: [
          Expanded(
            child: Text(
              '生成今日建议失败：${snapshot.errorMessage}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: scheme.error),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onRefresh, child: const Text('重试')),
        ],
      );
    }

    if (suggestion == null) return const SizedBox.shrink();

    if (!isExpanded) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onToggleExpanded(true),
        child: Text(
          suggestion.summary.isNotEmpty
              ? suggestion.summary
              : '点击展开今日 ${suggestion.items.length} 条 AI 建议',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: subTextColor),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (snapshot.errorMessage != null)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.errorContainer.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '重新生成失败：${snapshot.errorMessage}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onErrorContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: snapshot.isLoading ? null : onRefresh,
                  child: Text(
                    '重试',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (suggestion.summary.isNotEmpty)
          Text(
            suggestion.summary,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
          ),
        if (suggestion.items.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, thickness: 0.8, color: dividerColor),
          ),
          for (var i = 0; i < suggestion.items.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _buildSuggestionItemRow(
              context,
              index: i,
              item: suggestion.items[i],
              scheme: scheme,
              isDark: isDark,
              textColor: textColor,
              subTextColor: subTextColor,
            ),
          ],
        ],
        const SizedBox(height: 12),
        Divider(height: 1, thickness: 0.8, color: dividerColor),
        const SizedBox(height: 10),
        Row(
          children: [
            GestureDetector(
              key: const ValueKey<String>(
                'daily-ai-suggestion-footer-refresh-btn',
              ),
              behavior: HitTestBehavior.opaque,
              onTap: snapshot.isLoading ? null : onRefresh,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded, size: 14, color: subTextColor),
                    const SizedBox(width: 4),
                    Text(
                      snapshot.isLoading ? '生成中...' : '重新生成',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: subTextColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                final prompt = StringBuffer('基于今天的 AI 建议帮我进一步细化今日安排：\n');
                if (suggestion.summary.isNotEmpty) {
                  prompt.writeln(suggestion.summary);
                }
                for (final item in suggestion.items) {
                  prompt.writeln(
                    '- ${item.title}${item.reason.isNotEmpty ? '（${item.reason}）' : ''}',
                  );
                }
                onOpenAiChat(prompt.toString().trim());
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '和 AI 细聊今日安排 →',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSuggestionItemRow(
    BuildContext context, {
    required int index,
    required DailyAiSuggestionItem item,
    required ColorScheme scheme,
    required bool isDark,
    required Color textColor,
    required Color subTextColor,
  }) {
    final matchedTodo = _findMatchedTodo(item.todoId);
    final isTodoDone = matchedTodo?.isDone ?? false;
    final badgeColor = _priorityColor(item.priority, scheme, isDark);

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: matchedTodo != null ? () => onOpenTodo(matchedTodo) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: badgeColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            decoration: isTodoDone
                                ? TextDecoration.lineThrough
                                : null,
                            color: isTodoDone ? subTextColor : textColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(
                            alpha: isDark ? 0.2 : 0.12,
                          ),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          _priorityLabel(item.priority),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: badgeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (item.reason.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.reason,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: subTextColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (matchedTodo != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  isTodoDone
                      ? Icons.check_circle_rounded
                      : Icons.chevron_right_rounded,
                  size: 18,
                  color: isTodoDone ? scheme.primary : subTextColor,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
