part of '../animation_settings_page.dart';

extension _AnimationSettingsView on _AnimationSettingsPageState {
  Widget _buildSettingsScaffold(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final powerSaveModeEnabled = _powerSaveModeEnabled;
    final effectiveAnimationsEnabled =
        _animationsEnabled && !powerSaveModeEnabled;
    final effectiveScreenRadiusEnabled =
        _screenRadiusEnabled && !powerSaveModeEnabled;
    final effectivePredictiveBackEnabled =
        _predictiveBackEnabled && !powerSaveModeEnabled;
    final effectiveMotionBlurEnabled =
        _motionBlurEnabled && !powerSaveModeEnabled;
    final effectiveLayerBlurEnabled =
        _layerBlurEnabled && !powerSaveModeEnabled;
    final effectiveLiquidGlassEnabled =
        _liquidGlassEnabled && !powerSaveModeEnabled;
    return Scaffold(
      extendBodyBehindAppBar: !widget.isEmbedded,
      appBar: widget.isEmbedded
          ? null
          : FloatingGlassAppBar(
              flexibleSpace: const FloatingGlassTopBarBackground(),
              title: const Text('动画设置'),
              centerTitle: true,
            ),
      body: floatingGlassSettingsBody(
        context,
        standalone: !widget.isEmbedded,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 800;
            final isWide = constraints.maxWidth > 600;
            final isCompact = constraints.maxWidth <= 600;
            final content = ListView(
              controller: _scrollController,
              padding: EdgeInsets.fromLTRB(
                isDesktop ? 24 : 16,
                widget.isEmbedded
                    ? (isDesktop ? 20 : 16)
                    : floatingGlassSettingsContentTopInset(context),
                isDesktop ? 24 : 16,
                isDesktop ? 32 : 16,
              ),
              children: [
                AnimationPerformanceMetricCard(
                  animationsEnabled: effectiveAnimationsEnabled,
                  motionBlurEnabled: effectiveMotionBlurEnabled,
                  layerBlurEnabled: effectiveLayerBlurEnabled,
                  liquidGlassEnabled: effectiveLiquidGlassEnabled,
                  liquidGlassMode: _liquidGlassMode,
                  liquidGlassBlur: _liquidGlassBlur,
                  liquidGlassTransparency: _liquidGlassTransparency,
                  screenRadiusEnabled: effectiveScreenRadiusEnabled,
                  lazyLoadEnabled: _lazyLoadEnabled,
                  powerSaveModeEnabled: powerSaveModeEnabled,
                  isDesktop: isDesktop,
                ),
                SizedBox(height: isDesktop ? 20 : 16),
                if ((AppPlatform.isAndroid ||
                        AppPlatform.isMacOS ||
                        widget.powerSaveModeOverride != null) &&
                    powerSaveModeEnabled) ...[
                  Card(
                    elevation: 0,
                    color: colorScheme.primaryContainer.withValues(alpha: 0.72),
                    child: ListTile(
                      leading: Icon(
                        Icons.battery_saver_rounded,
                        color: colorScheme.onPrimaryContainer,
                      ),
                      title: const Text('应用省电模式'),
                      subtitle: Text(
                        AppPlatform.isMacOS
                            ? '已跟随 macOS 低电量模式自动开启：暂停装饰动画和玻璃特效，并降低后台探测频率。'
                            : '已跟随系统省电模式自动开启：暂停装饰动画和玻璃特效，并降低传感器与后台探测频率。',
                      ),
                      trailing: Text(
                        '已开启',
                        style: TextStyle(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: isDesktop ? 20 : 16),
                ],
                Padding(
                  padding: const EdgeInsets.only(left: 8.0, bottom: 8.0),
                  child: Text(
                    '性能预设',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                _buildPresetGrid(
                  isDesktop: isDesktop,
                  isWide: isWide,
                  isCompact: isCompact,
                ),
                SizedBox(height: isDesktop ? 28 : 24),
                Padding(
                  padding: const EdgeInsets.only(left: 8.0, bottom: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '核心特效开关',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (powerSaveModeEnabled) ...[
                        const SizedBox(height: 4),
                        Text(
                          '当前显示省电模式下的实际状态；退出后自动恢复原有偏好。懒加载优化继续启用以减少无效渲染。',
                          key: const ValueKey<String>(
                            'animation-settings-power-save-effective-note',
                          ),
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.35,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                GridView.count(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: isWide ? 3 : 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: isDesktop ? 2.45 : 1.3,
                  children: [
                    _buildToggleCard(
                      isDesktop: isDesktop,
                      title: '启用页面动画',
                      subtitle: _effectSubtitle(
                        normal: '开启/关闭过渡动画',
                        preferredEnabled: _animationsEnabled,
                      ),
                      icon: Icons.animation,
                      value: effectiveAnimationsEnabled,
                      switchKey: const ValueKey<String>(
                        'animation-settings-page-animation-switch',
                      ),
                      onChanged: powerSaveModeEnabled
                          ? null
                          : (val) {
                              _mutateState(() => _animationsEnabled = val);
                              _update(enabled: val);
                            },
                    ),
                    _buildToggleCard(
                      isDesktop: isDesktop,
                      title: '懒加载优化',
                      subtitle: powerSaveModeEnabled
                          ? '省电模式下继续启用，减少无效渲染'
                          : '动画进行中再渲染内容',
                      icon: Icons.hourglass_empty,
                      value: _lazyLoadEnabled,
                      switchKey: const ValueKey<String>(
                        'animation-settings-lazy-load-switch',
                      ),
                      onChanged: (val) {
                        _mutateState(() => _lazyLoadEnabled = val);
                        _update(lazyLoad: val);
                      },
                    ),
                    _buildToggleCard(
                      isDesktop: isDesktop,
                      title: '屏幕圆角适配',
                      subtitle: _effectSubtitle(
                        normal: '动画过程中适配屏幕圆角',
                        preferredEnabled: _screenRadiusEnabled,
                      ),
                      icon: Icons.rounded_corner,
                      value: effectiveScreenRadiusEnabled,
                      switchKey: const ValueKey<String>(
                        'animation-settings-screen-radius-switch',
                      ),
                      onChanged: powerSaveModeEnabled
                          ? null
                          : (val) {
                              _mutateState(() => _screenRadiusEnabled = val);
                              _update(screenRadius: val);
                            },
                    ),
                    if (!AppPlatform.isWeb)
                      _buildToggleCard(
                        isDesktop: isDesktop,
                        title: '预测性返回',
                        subtitle: _effectSubtitle(
                          normal: 'Android 14+ 返回手势',
                          preferredEnabled: _predictiveBackEnabled,
                        ),
                        icon: Icons.swipe_left,
                        value: effectivePredictiveBackEnabled,
                        switchKey: const ValueKey<String>(
                          'animation-settings-predictive-back-switch',
                        ),
                        onChanged: powerSaveModeEnabled
                            ? null
                            : (val) {
                                _mutateState(
                                  () => _predictiveBackEnabled = val,
                                );
                                _update(predictiveBack: val);
                              },
                      ),
                    _buildToggleCard(
                      isDesktop: isDesktop,
                      title: '运动模糊',
                      subtitle: _effectSubtitle(
                        normal: '滑动动态模糊 (影响性能)',
                        preferredEnabled: _motionBlurEnabled,
                      ),
                      icon: Icons.blur_linear,
                      value: effectiveMotionBlurEnabled,
                      switchKey: const ValueKey<String>(
                        'animation-settings-motion-blur-switch',
                      ),
                      onChanged: powerSaveModeEnabled
                          ? null
                          : (val) {
                              _mutateState(() => _motionBlurEnabled = val);
                              _update(motionBlur: val);
                            },
                    ),
                    _buildToggleCard(
                      isDesktop: isDesktop,
                      title: '层级模糊',
                      subtitle: _effectSubtitle(
                        normal: '背景页面模糊 (影响性能)',
                        preferredEnabled: _layerBlurEnabled,
                      ),
                      icon: Icons.blur_on,
                      value: effectiveLayerBlurEnabled,
                      switchKey: const ValueKey<String>(
                        'animation-settings-layer-blur-switch',
                      ),
                      onChanged: powerSaveModeEnabled
                          ? null
                          : (val) {
                              _mutateState(() => _layerBlurEnabled = val);
                              _update(layerBlur: val);
                            },
                    ),
                    _buildToggleCard(
                      isDesktop: isDesktop,
                      title: 'Liquid Glass',
                      cardKey: _glassKey,
                      subtitle: _effectSubtitle(
                        normal: '全应用玻璃材质、折射与半透明层次 (可选)',
                        preferredEnabled: _liquidGlassEnabled,
                      ),
                      icon: Icons.water_drop_rounded,
                      value: effectiveLiquidGlassEnabled,
                      switchKey: const ValueKey<String>(
                        'animation-settings-liquid-glass-switch',
                      ),
                      onChanged:
                          powerSaveModeEnabled || _liquidGlassMutationPending
                          ? null
                          : _setLiquidGlassEnabled,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: effectiveLiquidGlassEnabled ? 1 : 0.58,
                  child: Card(
                    color: _highlightTarget != null
                        ? colorScheme.primaryContainer
                        : null,
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.tune_rounded,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Liquid Glass 模式',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (AppPlatform.isWindows)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Chip(
                                avatar: const Icon(Icons.speed_rounded),
                                label: const Text('标准模式'),
                              ),
                            )
                          else
                            SizedBox(
                              width: double.infinity,
                              child: SegmentedButton<LiquidGlassEffectMode>(
                                segments: const [
                                  ButtonSegment(
                                    value: LiquidGlassEffectMode.standard,
                                    icon: Icon(Icons.speed_rounded),
                                    label: Text('标准'),
                                  ),
                                  ButtonSegment(
                                    value: LiquidGlassEffectMode.enhanced,
                                    icon: Icon(Icons.auto_awesome_rounded),
                                    label: Text('增强'),
                                  ),
                                ],
                                selected: {_liquidGlassMode},
                                onSelectionChanged:
                                    !effectiveLiquidGlassEnabled ||
                                        _liquidGlassMutationPending
                                    ? null
                                    : (selection) =>
                                          _setLiquidGlassMode(selection.first),
                              ),
                            ),
                          const SizedBox(height: 10),
                          Text(
                            _liquidGlassModeDescription,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 18),
                          if (effectiveLiquidGlassEnabled ||
                              widget.initialTarget ==
                                  'liquid_glass_transparency') ...[
                            _buildTransparencyPreviewBox(
                              isDark: isDark,
                              colorScheme: colorScheme,
                              isEnabled: true,
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(
                                  Icons.auto_fix_high_rounded,
                                  size: 15,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  '风格预设',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            _buildStylePresetPills(
                              colorScheme: colorScheme,
                              isDark: isDark,
                              isEnabled: true,
                            ),
                            const SizedBox(height: 12),
                            const Divider(height: 1),
                            const SizedBox(height: 12),

                            // --- 调整项 1: 底色遮蔽率 ---
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.format_color_fill_rounded,
                                      size: 17,
                                      color: colorScheme.primary,
                                    ),
                                    const SizedBox(width: 6),
                                    const Text(
                                      '底色遮蔽率',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  '$_liquidGlassScrimCoverage%',
                                  style: TextStyle(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '控制玻璃底色浓度；数值越高越能遮挡壁纸杂色，保证文字对比与清晰度',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            LiquidGlassSlider(
                              key: const ValueKey<String>(
                                'animation-settings-liquid-glass-scrim-coverage',
                              ),
                              value: _liquidGlassScrimCoverage.toDouble(),
                              min: 0,
                              max: 100,
                              divisions: 20,
                              label: '$_liquidGlassScrimCoverage%',
                              onChanged: !effectiveLiquidGlassEnabled
                                  ? null
                                  : (val) => _updateLiquidGlassAdjustments(
                                      scrimCoverage: val.round(),
                                    ),
                            ),
                            _buildSliderQuickChips(
                              colorScheme: colorScheme,
                              isDark: isDark,
                              isEnabled: effectiveLiquidGlassEnabled,
                              items: [
                                (
                                  label: '30% 薄透',
                                  onTap: () => _updateLiquidGlassAdjustments(
                                    scrimCoverage: 30,
                                  ),
                                  isSelected: _liquidGlassScrimCoverage == 30,
                                ),
                                (
                                  label: '50% 柔和',
                                  onTap: () => _updateLiquidGlassAdjustments(
                                    scrimCoverage: 50,
                                  ),
                                  isSelected: _liquidGlassScrimCoverage == 50,
                                ),
                                (
                                  label: '70% 默认',
                                  onTap: () => _updateLiquidGlassAdjustments(
                                    scrimCoverage: 70,
                                  ),
                                  isSelected: _liquidGlassScrimCoverage == 70,
                                ),
                                (
                                  label: '90% 浓郁',
                                  onTap: () => _updateLiquidGlassAdjustments(
                                    scrimCoverage: 90,
                                  ),
                                  isSelected: _liquidGlassScrimCoverage == 90,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // --- 调整项 2: 透光度 ---
                            Row(
                              key: _transparencyKey,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.opacity_rounded,
                                      size: 17,
                                      color: colorScheme.primary,
                                    ),
                                    const SizedBox(width: 6),
                                    const Text(
                                      '玻璃底色透明度',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        _getTransparencyLevelTag(
                                          _liquidGlassTransparency,
                                        ),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  '$_liquidGlassTransparency%',
                                  style: TextStyle(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _getTransparencyDescription(
                                _liquidGlassTransparency,
                              ),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            LiquidGlassSlider(
                              key: const ValueKey<String>(
                                'animation-settings-liquid-glass-transparency',
                              ),
                              value: _liquidGlassTransparency.toDouble(),
                              min: 0,
                              max: 100,
                              divisions: 20,
                              label: '$_liquidGlassTransparency%',
                              onChanged: !effectiveLiquidGlassEnabled
                                  ? null
                                  : (val) => _updateLiquidGlassAdjustments(
                                      transparency: val.round(),
                                    ),
                            ),
                            _buildSliderQuickChips(
                              colorScheme: colorScheme,
                              isDark: isDark,
                              isEnabled: effectiveLiquidGlassEnabled,
                              items: [
                                (
                                  label: '0% 纯色',
                                  onTap: () => _updateLiquidGlassAdjustments(
                                    transparency: 0,
                                  ),
                                  isSelected: _liquidGlassTransparency == 0,
                                ),
                                (
                                  label: '35% 默认',
                                  onTap: () => _updateLiquidGlassAdjustments(
                                    transparency: 35,
                                  ),
                                  isSelected: _liquidGlassTransparency == 35,
                                ),
                                (
                                  label: '50% 平衡',
                                  onTap: () => _updateLiquidGlassAdjustments(
                                    transparency: 50,
                                  ),
                                  isSelected: _liquidGlassTransparency == 50,
                                ),
                                (
                                  label: '75% 轻透',
                                  onTap: () => _updateLiquidGlassAdjustments(
                                    transparency: 75,
                                  ),
                                  isSelected: _liquidGlassTransparency == 75,
                                ),
                                (
                                  label: '100% 全透',
                                  onTap: () => _updateLiquidGlassAdjustments(
                                    transparency: 100,
                                  ),
                                  isSelected: _liquidGlassTransparency == 100,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // --- 调整项 3: 模糊程度 ---
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.blur_on_rounded,
                                      size: 18,
                                      color: colorScheme.primary,
                                    ),
                                    const SizedBox(width: 6),
                                    const Text(
                                      '模糊程度',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  '${_liquidGlassBlur.round()}px',
                                  style: TextStyle(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '控制卡片背后的高斯磨砂柔化半径；数值越大磨砂越柔和朦胧',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            LiquidGlassSlider(
                              key: const ValueKey<String>(
                                'animation-settings-liquid-glass-blur',
                              ),
                              value: _liquidGlassBlur,
                              min: 0,
                              max: 30,
                              divisions: 30,
                              label: '${_liquidGlassBlur.round()}px',
                              onChanged: !effectiveLiquidGlassEnabled
                                  ? null
                                  : (val) => _updateLiquidGlassAdjustments(
                                      blur: val,
                                    ),
                            ),
                            _buildSliderQuickChips(
                              colorScheme: colorScheme,
                              isDark: isDark,
                              isEnabled: effectiveLiquidGlassEnabled,
                              items: [
                                (
                                  label: '0px 无模糊',
                                  onTap: () =>
                                      _updateLiquidGlassAdjustments(blur: 0),
                                  isSelected: _liquidGlassBlur == 0,
                                ),
                                (
                                  label: '3px 默认',
                                  onTap: () =>
                                      _updateLiquidGlassAdjustments(blur: 3),
                                  isSelected: _liquidGlassBlur == 3,
                                ),
                                (
                                  label: '8px 轻度',
                                  onTap: () =>
                                      _updateLiquidGlassAdjustments(blur: 8),
                                  isSelected: _liquidGlassBlur == 8,
                                ),
                                (
                                  label: '16px 标准',
                                  onTap: () =>
                                      _updateLiquidGlassAdjustments(blur: 16),
                                  isSelected: _liquidGlassBlur == 16,
                                ),
                                (
                                  label: '24px 深度磨砂',
                                  onTap: () =>
                                      _updateLiquidGlassAdjustments(blur: 24),
                                  isSelected: _liquidGlassBlur == 24,
                                ),
                              ],
                            ),

                            // --- 实时应用与保存操作区 ---
                            ValueListenableBuilder<bool>(
                              valueListenable: LiquidGlassEffectService
                                  .hasUnsavedChangesListenable,
                              builder: (context, hasUnsaved, _) {
                                if (!effectiveLiquidGlassEnabled) {
                                  return const SizedBox.shrink();
                                }
                                return Container(
                                  margin: const EdgeInsets.only(top: 14),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: hasUnsaved
                                        ? colorScheme.primaryContainer
                                              .withValues(alpha: 0.28)
                                        : colorScheme.surfaceContainerHighest
                                              .withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: hasUnsaved
                                          ? colorScheme.primary.withValues(
                                              alpha: 0.3,
                                            )
                                          : colorScheme.outlineVariant
                                                .withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            hasUnsaved
                                                ? Icons.auto_awesome_rounded
                                                : Icons
                                                      .check_circle_outline_rounded,
                                            size: 18,
                                            color: hasUnsaved
                                                ? colorScheme.primary
                                                : colorScheme.onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              hasUnsaved
                                                  ? '效果已在全应用各界面实时生效'
                                                  : '当前玻璃效果已保存',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                                color: colorScheme.onSurface,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        hasUnsaved
                                            ? '可在主页与其他界面查看实际壁纸和卡片效果，满意后再保存；不满意可随时还原。'
                                            : '微调滑块或预设可实时应用预览，满意后可点击保存。',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          TextButton.icon(
                                            key: const ValueKey(
                                              'animation-settings-liquid-glass-reset-button',
                                            ),
                                            icon: const Icon(
                                              Icons.refresh_rounded,
                                              size: 16,
                                            ),
                                            label: const Text(
                                              '恢复默认',
                                              style: TextStyle(fontSize: 12),
                                            ),
                                            onPressed:
                                                !effectiveLiquidGlassEnabled
                                                ? null
                                                : () {
                                                    LiquidGlassEffectService.resetToDefaults();
                                                    final config =
                                                        LiquidGlassEffectService
                                                            .preferredConfiguration;
                                                    _mutateState(() {
                                                      _liquidGlassScrimCoverage =
                                                          config
                                                              .scrimCoveragePercent;
                                                      _liquidGlassTransparency =
                                                          config
                                                              .transparencyPercent;
                                                      _liquidGlassBlur =
                                                          config.blurSigma;
                                                    });
                                                  },
                                          ),
                                          const SizedBox(width: 6),
                                          OutlinedButton.icon(
                                            key: const ValueKey(
                                              'animation-settings-liquid-glass-float-button',
                                            ),
                                            icon: const Icon(
                                              Icons.open_in_browser_rounded,
                                              size: 16,
                                            ),
                                            label: const Text(
                                              '悬浮调节',
                                              style: TextStyle(fontSize: 12),
                                            ),
                                            onPressed:
                                                !effectiveLiquidGlassEnabled
                                                ? null
                                                : () {
                                                    LiquidGlassEffectService.startLivePreview(
                                                      expand: true,
                                                    );
                                                    Navigator.of(context)
                                                        .maybePop();
                                                  },
                                          ),
                                          if (hasUnsaved) ...[
                                            const SizedBox(width: 6),
                                            OutlinedButton.icon(
                                              key: const ValueKey(
                                                'animation-settings-liquid-glass-revert-button',
                                              ),
                                              icon: const Icon(
                                                Icons.undo_rounded,
                                                size: 16,
                                              ),
                                              label: const Text(
                                                '还原',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                              onPressed:
                                                  !effectiveLiquidGlassEnabled
                                                  ? null
                                                  : () {
                                                      LiquidGlassEffectService.revertAdjustments();
                                                      final config =
                                                          LiquidGlassEffectService
                                                              .persistedConfiguration;
                                                      _mutateState(() {
                                                        _liquidGlassScrimCoverage =
                                                            config
                                                                .scrimCoveragePercent;
                                                        _liquidGlassTransparency =
                                                            config
                                                                .transparencyPercent;
                                                        _liquidGlassBlur =
                                                            config.blurSigma;
                                                      });
                                                      AppSnackBars.showSnackBar(
                                                        context,
                                                        const SnackBar(
                                                          content: Text(
                                                            '已还原上次保存的玻璃设置',
                                                          ),
                                                        ),
                                                      );
                                                    },
                                            ),
                                            const SizedBox(width: 8),
                                            FilledButton.icon(
                                              key: const ValueKey(
                                                'animation-settings-liquid-glass-save-button',
                                              ),
                                              icon: const Icon(
                                                Icons.check_rounded,
                                                size: 16,
                                              ),
                                              label: const Text(
                                                '保存效果',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                              onPressed:
                                                  !effectiveLiquidGlassEnabled
                                                  ? null
                                                  : () =>
                                                        _saveLiquidGlassAdjustments(),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                          if (!effectiveLiquidGlassEnabled) ...[
                            const SizedBox(height: 6),
                            Text(
                              powerSaveModeEnabled && _liquidGlassEnabled
                                  ? '省电模式下已暂停；退出后恢复${_liquidGlassMode == LiquidGlassEffectMode.standard ? '标准' : '增强'}模式'
                                  : '开启 Liquid Glass 后可切换模式',
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.outline,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    left: 8.0,
                    bottom: 8.0,
                    top: 32.0,
                  ),
                  child: Text(
                    '参数微调',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  '动画时长',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  '${_animationDuration}ms',
                                  style: TextStyle(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            LiquidGlassSlider(
                              value: _animationDuration.toDouble(),
                              min: 150,
                              max: 600,
                              divisions: 9,
                              label: '${_animationDuration}ms',
                              onChanged: (val) {
                                _mutateState(
                                  () => _animationDuration = val.round(),
                                );
                                _update(duration: val.round());
                              },
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '快',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  '慢',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              '动画速度预设',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildSpeedPresetChip(
                                  preset: AnimationSpeedPreset.elegant,
                                  title: '优雅',
                                ),
                                _buildSpeedPresetChip(
                                  preset: AnimationSpeedPreset.balanced,
                                  title: '均衡',
                                ),
                                _buildSpeedPresetChip(
                                  preset: AnimationSpeedPreset.fast,
                                  title: '快速',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  '层级深度',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  '$_pageLayerDepth%',
                                  style: TextStyle(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '控制背景页缩小、压暗和层级模糊强度',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            LiquidGlassSlider(
                              value: _pageLayerDepth.toDouble(),
                              min: 0,
                              max: 100,
                              divisions: 10,
                              label: '$_pageLayerDepth%',
                              onChanged: (val) {
                                final next = val.round();
                                _mutateState(() => _pageLayerDepth = next);
                                _update(pageLayerDepth: next);
                              },
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '轻',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  '强',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  '元素展开内容显现',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  '$_containerContentStart%',
                                  style: TextStyle(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '控制从卡片、按钮展开页面时内容出现的早晚',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            LiquidGlassSlider(
                              value: _containerContentStart.toDouble(),
                              min: 0,
                              max: 60,
                              divisions: 12,
                              label: '$_containerContentStart%',
                              onChanged: (val) {
                                final next = val.round();
                                _mutateState(
                                  () => _containerContentStart = next,
                                );
                                _update(containerContentStart: next);
                              },
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '早',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  '晚',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: isDesktop ? 24 : 40),
              ],
            );

            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isDesktop ? 1440 : constraints.maxWidth,
                ),
                child: content,
              ),
            );
          },
        ),
      ),
    );
  }
}
