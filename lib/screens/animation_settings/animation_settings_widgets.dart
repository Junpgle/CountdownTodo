part of '../animation_settings_page.dart';

extension _AnimationSettingsWidgets on _AnimationSettingsPageState {
  Widget _buildSpeedPresetChip({
    required AnimationSpeedPreset preset,
    required String title,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _speedPreset == preset;
    return ChoiceChip(
      label: Text('$title ${preset.duration}ms'),
      selected: selected,
      showCheckmark: false,
      onSelected: (value) {
        if (value) _applySpeedPreset(preset);
      },
      selectedColor: colorScheme.primaryContainer,
      backgroundColor: colorScheme.surfaceContainerHighest,
      side: BorderSide(
        color: selected ? colorScheme.primary : colorScheme.outlineVariant,
        width: selected ? 1.5 : 1,
      ),
      labelStyle: TextStyle(
        color: selected
            ? colorScheme.onPrimaryContainer
            : colorScheme.onSurfaceVariant,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }

  Widget _buildPresetGrid({
    required bool isDesktop,
    required bool isWide,
    required bool isCompact,
  }) {
    return GridView.count(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      // 三种策略始终并排，便于快速对比和切换；窄屏使用更紧凑的卡片
      // 排版，避免把性能选项推到很深的位置。
      crossAxisCount: 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: isDesktop ? 2.35 : (isWide ? 1.45 : 0.78),
      children: [
        _buildPresetCard(
          compact: isCompact,
          preset: AnimationPreset.performance,
          title: '极致流畅',
          subtitle: '快速动画，优先稳定帧率，关闭液态玻璃',
          icon: Icons.speed_rounded,
        ),
        _buildPresetCard(
          compact: isCompact,
          preset: AnimationPreset.balanced,
          title: '均衡模式',
          subtitle: '均衡动画，保留主要过渡，液态玻璃标准档',
          icon: Icons.tune_rounded,
        ),
        _buildPresetCard(
          compact: isCompact,
          preset: AnimationPreset.expressive,
          title: '完整动效',
          subtitle: '优雅动画，开启模糊与液态玻璃增强档',
          icon: Icons.auto_awesome_rounded,
        ),
      ],
    );
  }

  Widget _buildPresetCard({
    required bool compact,
    required AnimationPreset preset,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _preset == preset;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _applyPreset(preset),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: selected ? 2 : 0,
        color: selected
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 14,
            vertical: compact ? 8 : 10,
          ),
          child: compact
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 22,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            icon,
                            size: 22,
                            color: selected
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                          if (selected)
                            Align(
                              alignment: Alignment.centerRight,
                              child: Icon(
                                Icons.check_circle_rounded,
                                size: 17,
                                color: colorScheme.primary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Flexible(
                      child: Text(
                        subtitle,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 9,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Icon(
                      icon,
                      color: selected
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (selected)
                      Icon(
                        Icons.check_circle_rounded,
                        color: colorScheme.primary,
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildToggleCard({
    required bool isDesktop,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool>? onChanged,
    Key? switchKey,
    Key? cardKey,
  }) {
    return SettingsToggleCard(
      key: cardKey,
      isDesktop: isDesktop,
      title: title,
      subtitle: subtitle,
      icon: icon,
      value: value,
      onChanged: onChanged,
      switchKey: switchKey,
      mobileUseSpacer: true,
    );
  }

  String _effectSubtitle({
    required String normal,
    required bool preferredEnabled,
  }) {
    if (!_powerSaveModeEnabled) return normal;
    return preferredEnabled ? '省电模式下已暂停，退出后自动恢复' : '已关闭，退出省电后保持关闭';
  }

  String _getTransparencyLevelTag(int value) {
    if (value == 0) return '纯色遮蔽';
    if (value <= 35) return '浓郁磨砂';
    if (value <= 65) return '经典平衡';
    if (value <= 90) return '轻透薄雾';
    return '全透水晶';
  }

  String _getTransparencyDescription(int value) {
    if (value == 0) {
      return '底色完全不透明，遮蔽背景内容，文字与图标对比度最高';
    }
    if (value <= 35) {
      return '深色调浓郁磨砂，仅隐约透出背景轮廓与主色';
    }
    if (value <= 65) {
      return '原版经典毛玻璃质感，透光度与界面可读性达到最佳平衡';
    }
    if (value <= 90) {
      return '轻盈通透的薄雾玻璃，更明显地透出壁纸与底层丰富细节';
    }
    return '接近纯粹透明的水晶质感，底层色彩完全透出';
  }

  Widget _buildTransparencyPreviewBox({
    required bool isDark,
    required ColorScheme colorScheme,
    required bool isEnabled,
  }) {
    final config = LiquidGlassEffectConfiguration(
      enabled: isEnabled,
      mode: _liquidGlassMode,
      transparencyPercent: _liquidGlassTransparency,
      scrimCoveragePercent: _liquidGlassScrimCoverage,
      blurSigma: _liquidGlassBlur,
    );
    final fillOpacity = isEnabled
        ? liquidGlassBackerOpacity(isDark ? 0.65 : 0.78, config)
        : (isDark ? 0.70 : 0.85);
    final blurSigma = isEnabled ? _liquidGlassBlur : 0.0;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      height: 104,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? const [
                        Color(0xFF1E2640),
                        Color(0xFF3B1E48),
                        Color(0xFF1E3830),
                      ]
                    : const [
                        Color(0xFFE0E7FF),
                        Color(0xFFFCE7F3),
                        Color(0xFFDCFCE7),
                      ],
              ),
            ),
          ),
          Positioned(
            left: 20,
            top: 14,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [Color(0xFFFF5252), Color(0xFFFF7A00)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF5252).withValues(alpha: 0.4),
                    blurRadius: 16,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 36,
            bottom: 8,
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [Color(0xFF2979FF), Color(0xFF00E5FF)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2979FF).withValues(alpha: 0.4),
                    blurRadius: 18,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 24,
            bottom: 12,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black).withValues(
                      alpha: 0.08,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '底层色彩与内容',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              height: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter.grouped(
                  filter: AppImageFilters.quantizedBlur(blurSigma),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: (isDark ? Colors.black : Colors.white).withValues(
                        alpha: fillOpacity,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: (isDark ? Colors.white : Colors.black)
                            .withValues(alpha: isDark ? 0.18 : 0.10),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.auto_awesome,
                            size: 16,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '毛玻璃卡片实时透光',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isEnabled
                                    ? '遮蔽 $_liquidGlassScrimCoverage% · 透光 $_liquidGlassTransparency% · 模糊 ${_liquidGlassBlur.round()}px'
                                    : 'Liquid Glass 未启用',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '$_liquidGlassTransparency%',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStylePresetPills({
    required ColorScheme colorScheme,
    required bool isDark,
    required bool isEnabled,
  }) {
    final presets = [
      (name: '舒适清透', desc: '默认', scrim: 70, trans: 35, blur: 3.0),
      (name: '轻透水晶', desc: '通透', scrim: 45, trans: 75, blur: 20.0),
      (name: '深层磨砂', desc: '质感', scrim: 75, trans: 40, blur: 25.0),
      (name: '高对比度', desc: '清晰', scrim: 90, trans: 20, blur: 12.0),
      (name: '微光微磨', desc: '轻柔', scrim: 55, trans: 65, blur: 8.0),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: presets.map((item) {
          final isSelected =
              _liquidGlassScrimCoverage == item.scrim &&
              _liquidGlassTransparency == item.trans &&
              (_liquidGlassBlur - item.blur).abs() < 0.5;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.5),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: !isEnabled
                      ? null
                      : () {
                          _updateLiquidGlassAdjustments(
                            scrimCoverage: item.scrim,
                            transparency: item.trans,
                            blur: item.blur,
                          );
                        },
                  borderRadius: BorderRadius.circular(8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colorScheme.primary.withValues(
                              alpha: isDark ? 0.25 : 0.12,
                            )
                          : (isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.black.withValues(alpha: 0.03)),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? colorScheme.primary
                            : colorScheme.outlineVariant.withValues(
                                alpha: 0.25,
                              ),
                        width: isSelected ? 1.4 : 0.8,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.name,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w600,
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          item.desc,
                          style: TextStyle(
                            fontSize: 9.5,
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSliderQuickChips({
    required ColorScheme colorScheme,
    required bool isDark,
    required bool isEnabled,
    required List<({String label, VoidCallback onTap, bool isSelected})> items,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Row(
        children: items.map((item) {
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: isEnabled ? item.onTap : null,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: item.isSelected
                          ? colorScheme.primary.withValues(
                              alpha: isDark ? 0.24 : 0.12,
                            )
                          : (isDark
                                ? Colors.white.withValues(alpha: 0.04)
                                : Colors.black.withValues(alpha: 0.03)),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: item.isSelected
                            ? colorScheme.primary
                            : colorScheme.outlineVariant.withValues(alpha: 0.2),
                        width: item.isSelected ? 1.2 : 0.8,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: item.isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: item.isSelected
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
