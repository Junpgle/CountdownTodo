part of '../floating_glass_control.dart';

/// A switch that uses the shared Liquid Glass interaction when the optional
/// effect is enabled and keeps the native Material switch as its fallback.
///
/// The active track is resolved from the current [ColorScheme], so the control
/// follows dynamic colors and app theme changes instead of a platform-fixed
/// blue or green.
class LiquidGlassSwitch extends StatelessWidget {
  const LiquidGlassSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.activeThumbColor,
    this.activeTrackColor,
    this.inactiveThumbColor,
    this.inactiveTrackColor,
    this.thumbColor,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.width = liquidGlassSwitchWidth,
    this.height = liquidGlassSwitchHeight,
    this.materialTapTargetSize,
    this.enableHaptics = true,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// The Liquid Glass active tint. [activeThumbColor] is retained for source
  /// compatibility with existing Material switch callsites.
  final Color? activeColor;
  final Color? activeThumbColor;
  final Color? activeTrackColor;
  final Color? inactiveThumbColor;
  final Color? inactiveTrackColor;
  final Color? thumbColor;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? semanticLabel;
  final double width;
  final double height;
  final MaterialTapTargetSize? materialTapTargetSize;
  final bool enableHaptics;

  Color _resolveActiveColor(ColorScheme colorScheme) {
    return liquidGlassSwitchActiveColorFor(
      colorScheme,
      activeColor: activeColor,
      activeTrackColor: activeTrackColor,
      activeThumbColor: activeThumbColor,
    );
  }

  Color _resolveInactiveColor(ColorScheme colorScheme) {
    if (inactiveTrackColor != null) return inactiveTrackColor!;
    final dark = colorScheme.brightness == Brightness.dark;
    final base = dark
        ? colorScheme.surfaceContainerHighest
        : colorScheme.surfaceContainerLow;
    return Color.alphaBlend(
      colorScheme.onSurface.withValues(alpha: dark ? 0.24 : 0.14),
      base,
    );
  }

  Color _resolveThumbColor(ColorScheme colorScheme) {
    return thumbColor ??
        (colorScheme.brightness == Brightness.dark
            ? colorScheme.surfaceContainerHigh
            : colorScheme.surface);
  }

  Widget _buildNativeSwitch() {
    return Switch(
      value: value,
      onChanged: onChanged,
      activeThumbColor: activeThumbColor ?? activeColor,
      activeTrackColor: activeTrackColor,
      inactiveThumbColor: inactiveThumbColor,
      inactiveTrackColor: inactiveTrackColor,
      focusNode: focusNode,
      autofocus: autofocus,
      materialTapTargetSize: materialTapTargetSize,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LiquidGlassEffectConfiguration>(
      valueListenable: LiquidGlassEffectService.configurationListenable,
      builder: (context, configuration, _) {
        final colorScheme = Theme.of(context).colorScheme;
        if (!configuration.enabled) {
          return _buildNativeSwitch();
        }

        final activeTrack = _resolveActiveColor(colorScheme);
        final inactiveTrack = _resolveInactiveColor(colorScheme);
        final requestedQuality = liquidGlassQualityForMode(configuration.mode);
        return _OptimisticGlassSwitch(
          value: value,
          onChanged: onChanged,
          activeColor: activeTrack,
          inactiveColor: inactiveTrack,
          thumbColor: _resolveThumbColor(colorScheme),
          width: width,
          height: height,
          quality: GlassThemeHelpers.resolveQuality(
            context,
            widgetQuality: requestedQuality,
          ),
          enableHaptics: enableHaptics,
          focusNode: focusNode,
          autofocus: autofocus,
          semanticLabel: semanticLabel,
        );
      },
    );
  }
}

/// Resolves an enabled switch tint without falling back to a platform colour.
@visibleForTesting
Color liquidGlassSwitchActiveColorFor(
  ColorScheme colorScheme, {
  Color? activeColor,
  Color? activeTrackColor,
  Color? activeThumbColor,
}) {
  return activeColor ??
      activeTrackColor ??
      activeThumbColor ??
      colorScheme.primary;
}

/// Keeps the package's native Liquid Glass switch renderer while applying the
/// requested state optimistically. This is important for settings whose
/// callbacks persist asynchronously: the track and lens move immediately and
/// never fall back to a stale grey state while storage is still completing.
class _OptimisticGlassSwitch extends StatefulWidget {
  const _OptimisticGlassSwitch({
    required this.value,
    required this.onChanged,
    required this.activeColor,
    required this.inactiveColor,
    required this.thumbColor,
    required this.width,
    required this.height,
    required this.quality,
    required this.enableHaptics,
    required this.focusNode,
    required this.autofocus,
    required this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color activeColor;
  final Color inactiveColor;
  final Color thumbColor;
  final double width;
  final double height;
  final GlassQuality quality;
  final bool enableHaptics;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? semanticLabel;

  @override
  State<_OptimisticGlassSwitch> createState() => _OptimisticGlassSwitchState();
}

class _OptimisticGlassSwitchState extends State<_OptimisticGlassSwitch> {
  late bool _visualValue;

  @override
  void initState() {
    super.initState();
    _visualValue = widget.value;
  }

  @override
  void didUpdateWidget(_OptimisticGlassSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value || widget.onChanged == null) {
      _visualValue = widget.value;
    }
  }

  void _handleChanged(bool value) {
    if (widget.onChanged == null) return;
    setState(() => _visualValue = value);
    widget.onChanged!(value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onChanged != null;
    final glassSwitch = GlassSwitch(
      value: _visualValue,
      onChanged: enabled ? _handleChanged : (_) {},
      activeColor: widget.activeColor,
      inactiveColor: widget.inactiveColor,
      thumbColor: widget.thumbColor,
      width: widget.width,
      height: widget.height,
      quality: widget.quality,
      enableHaptics: widget.enableHaptics,
      focusNode: enabled ? widget.focusNode : null,
      autofocus: enabled && widget.autofocus,
      semanticLabel: widget.semanticLabel,
    );

    // Glass cards normally ask nested controls to avoid a second refraction
    // layer. A switch thumb is a deliberately independent moving lens, so it
    // must reopen the renderer here; otherwise the interaction collapses into
    // a flat grey capsule inside nested glass settings cards.
    final renderedSwitch = InheritedLiquidGlass(
      settings: const LiquidGlassSettings(),
      quality: widget.quality,
      avoidsRefraction: false,
      child: glassSwitch,
    );

    if (enabled) return renderedSwitch;

    return Semantics(
      label: widget.semanticLabel ?? 'Switch',
      button: true,
      enabled: false,
      toggled: _visualValue,
      child: ExcludeSemantics(
        child: IgnorePointer(
          child: Opacity(opacity: 0.58, child: renderedSwitch),
        ),
      ),
    );
  }
}

/// Uses the package slider while Liquid Glass is enabled and keeps Material's
/// standard slider as the preference-off fallback.
class LiquidGlassSlider extends StatelessWidget {
  const LiquidGlassSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.label,
    this.activeColor,
    this.inactiveColor,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final Color? activeColor;
  final Color? inactiveColor;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LiquidGlassEffectConfiguration>(
      valueListenable: LiquidGlassEffectService.configurationListenable,
      builder: (context, configuration, _) {
        final colorScheme = Theme.of(context).colorScheme;
        if (!configuration.enabled) {
          return Slider(
            value: value,
            onChanged: onChanged,
            onChangeStart: onChangeStart,
            onChangeEnd: onChangeEnd,
            min: min,
            max: max,
            divisions: divisions,
            label: label,
            activeColor: activeColor,
            inactiveColor: inactiveColor,
          );
        }

        final isDark = colorScheme.brightness == Brightness.dark;
        final enhanced = configuration.mode == LiquidGlassEffectMode.enhanced;
        final backdropScope = OptionalLiquidGlassBackdropScope.maybeOf(context);
        final shouldBlurSlider =
            enhanced &&
            (backdropScope == null || !backdropScope.isSolidBackground);
        final settings = LiquidGlassSettings(
          bodyMode: GlassBodyMode.clear,
          glassColor: colorScheme.primary.withValues(
            alpha: isDark ? 0.14 : 0.11,
          ),
          thickness: enhanced ? 22 : 18,
          blur: shouldBlurSlider ? 14 : 0,
          chromaticAberration: enhanced ? 0.006 : 0.003,
          lightIntensity: isDark ? 0.56 : 0.62,
          ambientStrength: isDark ? 0.12 : 0.14,
          backerColor: colorScheme.surface.withValues(
            alpha: liquidGlassBackerOpacity(
              isDark ? (enhanced ? 0.56 : 0.5) : (enhanced ? 0.64 : 0.58),
              configuration,
            ),
          ),
        );
        final quality = GlassThemeHelpers.resolveQuality(
          context,
          widgetQuality: liquidGlassQualityForMode(configuration.mode),
        );
        final slider = GlassSlider(
          value: value,
          onChanged: onChanged,
          onChangeStart: onChangeStart,
          onChangeEnd: onChangeEnd,
          min: min,
          max: max,
          divisions: divisions,
          label: label,
          activeColor: activeColor ?? colorScheme.primary,
          inactiveColor:
              inactiveColor ??
              colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
          thumbColor: colorScheme.surface,
          settings: settings,
          useOwnLayer: true,
          quality: quality,
        );

        // Sliders animate the thumb independently from the surrounding panel.
        // Reopen the package renderer when a settings card provides an outer
        // glass layer, matching the existing switch treatment.
        return InheritedLiquidGlass(
          settings: settings,
          quality: quality,
          avoidsRefraction: false,
          child: slider,
        );
      },
    );
  }
}

/// A switch list tile that keeps the familiar Material layout while exposing
/// the same draggable glass switch used by standalone controls.
class LiquidGlassSwitchListTile extends StatelessWidget {
  const LiquidGlassSwitchListTile({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.activeThumbColor,
    this.activeTrackColor,
    this.inactiveThumbColor,
    this.inactiveTrackColor,
    this.thumbColor,
    this.materialTapTargetSize,
    this.focusNode,
    this.statesController,
    this.onFocusChange,
    this.autofocus = false,
    this.tileColor,
    this.title,
    this.subtitle,
    this.isThreeLine,
    this.dense,
    this.contentPadding,
    this.secondary,
    this.selected = false,
    this.controlAffinity,
    this.shape,
    this.selectedTileColor,
    this.visualDensity,
    this.enableFeedback,
    this.horizontalTitleGap,
    this.minVerticalPadding,
    this.minLeadingWidth,
    this.minTileHeight,
    this.hoverColor,
    this.internalAddSemanticForOnTap = false,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;
  final Color? activeThumbColor;
  final Color? activeTrackColor;
  final Color? inactiveThumbColor;
  final Color? inactiveTrackColor;
  final WidgetStateProperty<Color?>? thumbColor;
  final MaterialTapTargetSize? materialTapTargetSize;
  final FocusNode? focusNode;
  final WidgetStatesController? statesController;
  final ValueChanged<bool>? onFocusChange;
  final bool autofocus;
  final Color? tileColor;
  final Widget? title;
  final Widget? subtitle;
  final bool? isThreeLine;
  final bool? dense;
  final EdgeInsetsGeometry? contentPadding;
  final Widget? secondary;
  final bool selected;
  final ListTileControlAffinity? controlAffinity;
  final ShapeBorder? shape;
  final Color? selectedTileColor;
  final VisualDensity? visualDensity;
  final bool? enableFeedback;
  final double? horizontalTitleGap;
  final double? minVerticalPadding;
  final double? minLeadingWidth;
  final double? minTileHeight;
  final Color? hoverColor;
  final bool internalAddSemanticForOnTap;
  final String? semanticLabel;

  bool _usesLeadingControl(BuildContext context) {
    final affinity =
        controlAffinity ?? ListTileTheme.of(context).controlAffinity;
    // Settings controls consistently live on the trailing edge. Flutter's
    // platform affinity puts switches on the leading edge on macOS/iOS, which
    // is surprising in this app because the row's leading slot already carries
    // its descriptive icon.
    return affinity == ListTileControlAffinity.leading;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedStates = <WidgetState>{if (value) WidgetState.selected};
    final activeTint =
        activeTrackColor ??
        activeThumbColor ??
        activeColor ??
        colorScheme.primary;
    final resolvedThumb = thumbColor?.resolve(selectedStates);
    final switchControl = SizedBox(
      width: liquidGlassSwitchWidth,
      height: liquidGlassSwitchHeight,
      child: ExcludeFocus(
        child: ExcludeSemantics(
          child: LiquidGlassSwitch(
            value: value,
            onChanged: onChanged,
            activeColor: activeTint,
            activeTrackColor: activeTrackColor,
            inactiveThumbColor: inactiveThumbColor,
            inactiveTrackColor: inactiveTrackColor,
            thumbColor: resolvedThumb,
            materialTapTargetSize: materialTapTargetSize,
          ),
        ),
      ),
    );
    final leadingControl = _usesLeadingControl(context);
    final effectiveActiveColor = activeThumbColor ?? activeColor ?? activeTint;

    final tile = ListTile(
      leading: leadingControl ? switchControl : secondary,
      title: title,
      subtitle: subtitle,
      trailing: leadingControl ? secondary : switchControl,
      isThreeLine: isThreeLine,
      dense: dense,
      contentPadding: contentPadding,
      enabled: onChanged != null,
      selected: selected,
      selectedColor: effectiveActiveColor,
      selectedTileColor: selectedTileColor,
      autofocus: autofocus,
      shape: shape,
      tileColor: tileColor,
      visualDensity: visualDensity,
      focusNode: focusNode,
      statesController: statesController,
      onFocusChange: onFocusChange,
      enableFeedback: enableFeedback,
      horizontalTitleGap: horizontalTitleGap,
      minVerticalPadding: minVerticalPadding,
      minLeadingWidth: minLeadingWidth,
      minTileHeight: minTileHeight,
      hoverColor: hoverColor,
      internalAddSemanticForOnTap: internalAddSemanticForOnTap,
    );

    // Keep the row-toggle hit target away from the switch. A parent tap
    // recognizer spanning the trailing control competes with its horizontal
    // drag recognizer and can make a drag look like a grey/failed click.
    final rowToggle = Positioned(
      left: leadingControl ? liquidGlassSwitchWidth + 12.0 : 0.0,
      right: leadingControl ? 0.0 : liquidGlassSwitchWidth + 12.0,
      top: 0.0,
      bottom: 0.0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged != null ? () => onChanged!(!value) : null,
        child: const SizedBox.expand(),
      ),
    );

    return MergeSemantics(
      child: Semantics(
        container: true,
        button: onChanged != null,
        enabled: onChanged != null,
        toggled: value,
        label: semanticLabel,
        child: Stack(children: [tile, rowToggle]),
      ),
    );
  }
}
