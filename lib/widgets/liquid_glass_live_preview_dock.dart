import 'package:flutter/material.dart';

import '../services/liquid_glass_effect_service.dart';
import '../utils/app_dialogs.dart';
import '../utils/navigator_utils.dart';
import 'floating_glass_control.dart';

/// Floating live-preview dock shown across home dashboard and other screens
/// while the user is actively adjusting Liquid Glass effects.
///
/// Supports directly expanding the 3 core adjustment parameters (scrim coverage,
/// transparency, blur) in-place on ANY screen without navigating back to
/// the animation settings page.
class LiquidGlassLivePreviewDock extends StatelessWidget {
  const LiquidGlassLivePreviewDock({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: LiquidGlassEffectService.hasUnsavedChangesListenable,
      builder: (context, hasUnsaved, _) {
        return ValueListenableBuilder<bool>(
          valueListenable:
              LiquidGlassEffectService.isLivePreviewForcedListenable,
          builder: (context, isForced, _) {
            return ValueListenableBuilder<bool>(
              valueListenable:
                  LiquidGlassEffectService.isSettingsPageActiveListenable,
              builder: (context, isSettingsActive, _) {
                final visible = (hasUnsaved || isForced) && !isSettingsActive;
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  transitionBuilder: (child, animation) {
                    return SlideTransition(
                      position:
                          Tween<Offset>(
                            begin: const Offset(0, 0.4),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                      child: FadeTransition(opacity: animation, child: child),
                    );
                  },
                  child: visible
                      ? const _DockContent(
                          key: ValueKey('liquid-glass-live-dock'),
                        )
                      : const SizedBox.shrink(),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _DockContent extends StatelessWidget {
  const _DockContent({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ValueListenableBuilder<bool>(
      valueListenable:
          LiquidGlassEffectService.isFloatingPanelExpandedListenable,
      builder: (context, isExpanded, _) {
        return ValueListenableBuilder<LiquidGlassEffectConfiguration>(
          valueListenable: LiquidGlassEffectService.configurationListenable,
          builder: (context, config, _) {
            return SafeArea(
              top: false,
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.fromLTRB(12, 0, 12, isExpanded ? 24 : 96),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: 480,
                        maxHeight: MediaQuery.of(context).size.height * 0.72,
                      ),
                      decoration: BoxDecoration(
                        color: (isDark ? const Color(0xFF1E222B) : Colors.white)
                            .withValues(alpha: isDark ? 0.94 : 0.96),
                        borderRadius: BorderRadius.circular(
                          isExpanded ? 24 : 20,
                        ),
                        border: Border.all(
                          color: colorScheme.primary.withValues(alpha: 0.35),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.45 : 0.18,
                            ),
                            blurRadius: isExpanded ? 24 : 20,
                            offset: Offset(0, isExpanded ? 10 : 8),
                          ),
                        ],
                      ),
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.bottomCenter,
                        child: isExpanded
                            ? _buildExpandedPanel(
                                context: context,
                                colorScheme: colorScheme,
                                isDark: isDark,
                                config: config,
                              )
                            : _buildCompactPill(
                                context: context,
                                colorScheme: colorScheme,
                                isDark: isDark,
                                config: config,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCompactPill({
    required BuildContext context,
    required ColorScheme colorScheme,
    required bool isDark,
    required LiquidGlassEffectConfiguration config,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: LiquidGlassEffectService.toggleFloatingPanel,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        size: 17,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '效果实时预览中',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4.5,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '未保存',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '遮蔽 ${config.scrimCoveragePercent}% · 透光 ${config.transparencyPercent}% · 模糊 ${config.blurSigma.round()}px',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          OutlinedButton(
            key: const ValueKey('liquid-glass-dock-revert-button'),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: BorderSide(
                color: colorScheme.outline.withValues(alpha: 0.4),
              ),
            ),
            onPressed: () {
              LiquidGlassEffectService.revertAdjustments();
              final navContext = appNavigatorKey.currentContext ?? context;
              AppSnackBars.showSnackBar(
                navContext,
                const SnackBar(
                  content: Text('已还原上次保存的玻璃设置'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text('还原', style: TextStyle(fontSize: 11.5)),
          ),
          const SizedBox(width: 5),
          FilledButton(
            key: const ValueKey('liquid-glass-dock-save-button'),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () async {
              await LiquidGlassEffectService.saveAdjustments();
              final navContext = appNavigatorKey.currentContext ?? context;
              if (navContext.mounted) {
                AppSnackBars.showSnackBar(
                  navContext,
                  const SnackBar(
                    content: Text('已保存 Liquid Glass 效果设置'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            child: const Text('保存', style: TextStyle(fontSize: 11.5)),
          ),
          const SizedBox(width: 2),
          Semantics(
            label: '展开参数调节',
            button: true,
            child: IconButton(
              key: const ValueKey('liquid-glass-dock-tune-button'),
              icon: const Icon(Icons.tune_rounded, size: 19),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: const EdgeInsets.all(4),
              onPressed: LiquidGlassEffectService.toggleFloatingPanel,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedPanel({
    required BuildContext context,
    required ColorScheme colorScheme,
    required bool isDark,
    required LiquidGlassEffectConfiguration config,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 10, 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: LiquidGlassEffectService.collapseFloatingPanel,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 6),
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.tune_rounded,
                      size: 16,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '液态玻璃实时调节',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4.5,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '即时生效',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.restart_alt_rounded, size: 14),
                    label: const Text('恢复默认', style: TextStyle(fontSize: 11)),
                    onPressed: LiquidGlassEffectService.resetToDefaults,
                  ),
                  const SizedBox(width: 2),
                  Semantics(
                    label: '收起调节面板',
                    button: true,
                    child: IconButton(
                      key: const ValueKey('liquid-glass-dock-collapse-button'),
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 22,
                      ),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onPressed: LiquidGlassEffectService.collapseFloatingPanel,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Sliders scroll body (compact layout: sliders only without bulky preset chips)
        Flexible(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. 底色遮蔽率
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.format_color_fill_rounded,
                          size: 15,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          '底色遮蔽率',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${config.scrimCoveragePercent}%',
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
                LiquidGlassSlider(
                  key: const ValueKey('live-dock-liquid-glass-scrim-slider'),
                  value: config.scrimCoveragePercent.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label: '${config.scrimCoveragePercent}%',
                  onChanged: (val) =>
                      LiquidGlassEffectService.previewAdjustments(
                        scrimCoveragePercent: val.round(),
                      ),
                ),
                const SizedBox(height: 2),

                // 2. 透光度
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.opacity_rounded,
                          size: 15,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          '透光度',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${config.transparencyPercent}%',
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
                LiquidGlassSlider(
                  key: const ValueKey(
                    'live-dock-liquid-glass-transparency-slider',
                  ),
                  value: config.transparencyPercent.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label: '${config.transparencyPercent}%',
                  onChanged: (val) =>
                      LiquidGlassEffectService.previewAdjustments(
                        transparencyPercent: val.round(),
                      ),
                ),
                const SizedBox(height: 2),

                // 3. 模糊程度
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.blur_on_rounded,
                          size: 15,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          '模糊程度',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${config.blurSigma.round()}px',
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
                LiquidGlassSlider(
                  key: const ValueKey('live-dock-liquid-glass-blur-slider'),
                  value: config.blurSigma,
                  min: 0,
                  max: 30,
                  divisions: 30,
                  label: '${config.blurSigma.round()}px',
                  onChanged: (val) =>
                      LiquidGlassEffectService.previewAdjustments(
                        blurSigma: val,
                      ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
