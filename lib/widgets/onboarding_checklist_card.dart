import 'package:flutter/material.dart';

import '../services/feature_tip_service.dart';
import '../services/onboarding_checklist_service.dart';
import '../utils/app_dialogs.dart';
import '../utils/app_image_filters.dart';
import 'optional_liquid_glass_surface.dart';
import 'platform_backdrop_filter.dart';

class OnboardingChecklistCard extends StatefulWidget {
  final bool isLight;
  final bool hasTodosOrCountdowns;
  final bool hasCoursesOrSchedules;
  final bool hasPlanBlocks;
  final void Function(String taskId) onLaunchTask;
  final void Function(String taskId)? onSpotlightTask;
  final VoidCallback onOpenFeatureExplorer;

  const OnboardingChecklistCard({
    super.key,
    required this.isLight,
    required this.hasTodosOrCountdowns,
    required this.hasCoursesOrSchedules,
    required this.hasPlanBlocks,
    required this.onLaunchTask,
    this.onSpotlightTask,
    required this.onOpenFeatureExplorer,
  });

  @override
  State<OnboardingChecklistCard> createState() =>
      _OnboardingChecklistCardState();
}

class _OnboardingChecklistCardState extends State<OnboardingChecklistCard> {
  OnboardingChecklistSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _reload();
    OnboardingChecklistService.revision.addListener(_reload);
    FeatureTipService.revision.addListener(_reload);
  }

  @override
  void didUpdateWidget(covariant OnboardingChecklistCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hasTodosOrCountdowns != widget.hasTodosOrCountdowns ||
        oldWidget.hasCoursesOrSchedules != widget.hasCoursesOrSchedules ||
        oldWidget.hasPlanBlocks != widget.hasPlanBlocks) {
      _reload();
    }
  }

  @override
  void dispose() {
    OnboardingChecklistService.revision.removeListener(_reload);
    FeatureTipService.revision.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final snap = await OnboardingChecklistService.loadSnapshot(
      hasTodosOrCountdowns: widget.hasTodosOrCountdowns,
      hasCoursesOrSchedules: widget.hasCoursesOrSchedules,
      hasPlanBlocks: widget.hasPlanBlocks,
    );
    if (!mounted) return;
    setState(() {
      _snapshot = snap;
    });
  }

  Future<void> _toggleExpanded() async {
    final current = _snapshot;
    if (current == null) return;
    await OnboardingChecklistService.setExpanded(!current.isExpanded);
  }

  Future<void> _dismissCard() async {
    await OnboardingChecklistService.setDismissed(true);
    if (!mounted) return;
    AppSnackBars.showSnackBar(
      context,
      SnackBar(
        content: const Text('已隐藏探索清单，可随时在「帮助与反馈」或「功能百宝箱」中恢复显示'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            OnboardingChecklistService.setDismissed(false);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snapshot;
    if (snap == null || snap.isDismissed) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerTextColor = widget.isLight ? Colors.white : scheme.onSurface;
    final headerSubColor = widget.isLight
        ? Colors.white.withValues(alpha: 0.72)
        : scheme.onSurfaceVariant;

    final nextPendingTask = snap.tasks.cast<OnboardingTaskItem?>().firstWhere(
      (t) => t != null && !t.isCompleted,
      orElse: () => null,
    );

    final cardTextColor = widget.isLight ? Colors.white : scheme.onSurface;
    final cardSubColor = widget.isLight
        ? Colors.white.withValues(alpha: 0.74)
        : scheme.onSurfaceVariant;
    final accentColor = widget.isLight ? Colors.white : scheme.primary;

    return Padding(
      key: const ValueKey<String>('home-onboarding-checklist-card'),
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 顶部区块标题栏（与首页「待办事项」「最近专注」保持统一视觉语言） ──
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: widget.isLight
                        ? Colors.white.withValues(alpha: 0.15)
                        : scheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    snap.isAllCompleted
                        ? Icons.emoji_events_rounded
                        : Icons.explore_rounded,
                    size: 20,
                    color: widget.isLight ? Colors.white : scheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          snap.isAllCompleted ? '已解锁全部玩法' : '功能探索',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.2,
                            color: headerTextColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: widget.isLight
                              ? Colors.white.withValues(alpha: 0.2)
                              : scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${snap.completedCount}/${snap.totalCount}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: widget.isLight
                                ? Colors.white
                                : scheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // 百宝箱轻量胶囊按钮
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: const ValueKey<String>(
                      'onboarding-open-feature-explorer-btn',
                    ),
                    borderRadius: BorderRadius.circular(999),
                    onTap: widget.onOpenFeatureExplorer,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: widget.isLight
                            ? Colors.white.withValues(alpha: 0.16)
                            : scheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome_mosaic_rounded,
                            size: 13,
                            color: accentColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '百宝箱',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: accentColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // 展开/收起轻量箭头（无臃肿圆形底色）
                GestureDetector(
                  key: const ValueKey<String>('onboarding-toggle-expand-btn'),
                  onTap: _toggleExpanded,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      snap.isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 22,
                      color: headerSubColor,
                    ),
                  ),
                ),
                // 隐藏按钮（轻量无底色）
                GestureDetector(
                  key: const ValueKey<String>('onboarding-dismiss-btn'),
                  onTap: _dismissCard,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: headerSubColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),

          // ── 主体毛玻璃卡片 ──
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: PlatformBackdropFilter(
              filter: AppImageFilters.blur10,
              bypassWhenLiquidGlassEnabled: true,
              child: OptionalLiquidGlassCard(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                borderRadius: 20,
                tint: (widget.isLight ? scheme.scrim : scheme.primary)
                    .withValues(alpha: 0.14),
                isDark: widget.isLight || isDark,
                fallbackDecoration: BoxDecoration(
                  color: widget.isLight
                      ? Colors.white.withValues(alpha: 0.15)
                      : scheme.surfaceContainerHighest.withValues(alpha: 0.32),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: widget.isLight
                        ? Colors.white.withValues(alpha: 0.2)
                        : Theme.of(context).dividerColor.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 进度说明与细进度条
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            snap.isAllCompleted
                                ? '你已掌握核心功能，可随时进入「百宝箱」查看隐藏技巧'
                                : '跟着清单体验一遍，1分钟搞懂核心功能在哪里',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: cardSubColor),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${(snap.progress * 100).round()}%',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: accentColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: snap.progress,
                        minHeight: 5,
                        backgroundColor: widget.isLight
                            ? Colors.white.withValues(alpha: 0.16)
                            : scheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                      ),
                    ),
                    const SizedBox(height: 10),

                    if (snap.isExpanded) ...[
                      for (var i = 0; i < snap.tasks.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            thickness: 0.5,
                            color: widget.isLight
                                ? Colors.white.withValues(alpha: 0.12)
                                : scheme.outlineVariant.withValues(alpha: 0.45),
                          ),
                        _buildTaskRow(
                          context,
                          snap.tasks[i],
                          scheme,
                          cardTextColor: cardTextColor,
                          cardSubColor: cardSubColor,
                          accentColor: accentColor,
                        ),
                      ],
                      const SizedBox(height: 4),
                      _buildExpandFooter(
                        label: '收起引导清单',
                        icon: Icons.keyboard_arrow_up_rounded,
                        color: cardSubColor,
                      ),
                    ] else if (nextPendingTask != null) ...[
                      _buildTaskRow(
                        context,
                        nextPendingTask,
                        scheme,
                        cardTextColor: cardTextColor,
                        cardSubColor: cardSubColor,
                        accentColor: accentColor,
                        isNextSpotlight: true,
                      ),
                      Divider(
                        height: 12,
                        thickness: 0.5,
                        color: widget.isLight
                            ? Colors.white.withValues(alpha: 0.12)
                            : scheme.outlineVariant.withValues(alpha: 0.45),
                      ),
                      _buildExpandFooter(
                        label: '展开查看全部 ${snap.totalCount} 项功能引导',
                        icon: Icons.keyboard_arrow_down_rounded,
                        color: accentColor,
                      ),
                    ] else ...[
                      _buildExpandFooter(
                        label: '查看全部 ${snap.totalCount} 项已完成引导',
                        icon: Icons.keyboard_arrow_down_rounded,
                        color: accentColor,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandFooter({
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _toggleExpanded,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              const SizedBox(width: 2),
              Icon(icon, size: 16, color: color),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskRow(
    BuildContext context,
    OnboardingTaskItem task,
    ColorScheme scheme, {
    required Color cardTextColor,
    required Color cardSubColor,
    required Color accentColor,
    bool isNextSpotlight = false,
  }) {
    final done = task.isCompleted;
    final doneColor = widget.isLight
        ? const Color(0xFF69F0AE)
        : const Color(0xFF2E7D32);

    return Padding(
      key: ValueKey<String>('onboarding-task-${task.id}'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: done
                  ? doneColor.withValues(alpha: 0.14)
                  : (widget.isLight
                        ? Colors.white.withValues(alpha: 0.14)
                        : scheme.primary.withValues(alpha: 0.1)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              done ? Icons.check_rounded : task.icon,
              size: 18,
              color: done ? doneColor : accentColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isNextSpotlight) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: widget.isLight
                              ? Colors.white.withValues(alpha: 0.2)
                              : scheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '下一步',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: accentColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          decoration: done ? TextDecoration.lineThrough : null,
                          color: done
                              ? cardTextColor.withValues(alpha: 0.48)
                              : cardTextColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  task.locationHint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: cardSubColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!done && widget.onSpotlightTask != null) ...[
            Material(
              color: Colors.transparent,
              child: InkWell(
                key: ValueKey<String>('onboarding-spotlight-${task.id}'),
                borderRadius: BorderRadius.circular(8),
                onTap: () => widget.onSpotlightTask!(task.id),
                child: Tooltip(
                  message: '在首页高亮指示位置',
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: widget.isLight
                          ? Colors.white.withValues(alpha: 0.12)
                          : scheme.surfaceContainerHighest.withValues(
                              alpha: 0.65,
                            ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.my_location_rounded,
                      size: 15,
                      color: accentColor,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: ValueKey<String>('onboarding-launch-${task.id}'),
              borderRadius: BorderRadius.circular(999),
              onTap: () => widget.onLaunchTask(task.id),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: done
                      ? (widget.isLight
                            ? Colors.white.withValues(alpha: 0.1)
                            : scheme.surfaceContainerHighest.withValues(
                                alpha: 0.5,
                              ))
                      : (widget.isLight
                            ? Colors.white.withValues(alpha: 0.22)
                            : scheme.primary.withValues(alpha: 0.14)),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  done ? '再看看' : '去试试',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: done ? cardSubColor : accentColor,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
