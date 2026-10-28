import 'package:flutter/material.dart';

import '../../../widgets/optional_liquid_glass_surface.dart';

class FinanceGlassSegment<T> {
  final String id;
  final String label;
  final T value;

  const FinanceGlassSegment({
    required this.id,
    required this.label,
    required this.value,
  });
}

/// A compact segmented control with a frosted track and a softly tinted,
/// animated glass indicator.
class FinanceGlassSegmentSelector<T> extends StatelessWidget {
  final List<FinanceGlassSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onSelected;
  final String keyPrefix;
  final double height;

  const FinanceGlassSegmentSelector({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelected,
    required this.keyPrefix,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedIndex = segments.indexWhere(
      (segment) => segment.value == selected,
    );
    final safeIndex = selectedIndex < 0 ? 0 : selectedIndex;
    final radius = BorderRadius.circular(18);
    final body = SizedBox(
      height: height - 8,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segmentWidth = constraints.maxWidth / segments.length;
          return Stack(
            fit: StackFit.expand,
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                top: 0,
                bottom: 0,
                left: safeIndex * segmentWidth,
                width: segmentWidth,
                child: _buildSelectionGlass(context),
              ),
              Row(
                children: [
                  for (final segment in segments)
                    Expanded(
                      child: _buildSegment(
                        context,
                        segment,
                        isSelected: segment.value == selected,
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
    final isDark = colorScheme.brightness == Brightness.dark;
    return OptionalLiquidGlassPanel(
      key: ValueKey('$keyPrefix-track'),
      width: double.infinity,
      height: height,
      padding: const EdgeInsets.all(4),
      borderRadius: 18,
      tint: colorScheme.surfaceContainerHighest,
      mode: OptionalLiquidGlassPanelMode.adaptiveRepeated,
      staticMaterialOpacity: isDark ? 0.28 : 0.34,
      fallback: Container(
        width: double.infinity,
        height: height,
        padding: const EdgeInsets.all(4),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.surfaceContainerHighest.withValues(
                alpha: isDark ? 0.28 : 0.4,
              ),
              colorScheme.surface.withValues(alpha: isDark ? 0.16 : 0.24),
            ],
          ),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.22),
            width: 0.8,
          ),
        ),
        child: body,
      ),
      child: body,
    );
  }

  Widget _buildSelectionGlass(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.surface.withValues(alpha: isDark ? 0.28 : 0.64),
            colorScheme.secondaryContainer.withValues(
              alpha: isDark ? 0.32 : 0.44,
            ),
          ],
        ),
        border: Border.all(
          color: colorScheme.surface.withValues(alpha: isDark ? 0.24 : 0.82),
          width: 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: isDark ? 0.08 : 0.1),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: colorScheme.surface.withValues(alpha: isDark ? 0.22 : 0.72),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }

  Widget _buildSegment(
    BuildContext context,
    FinanceGlassSegment<T> segment, {
    required bool isSelected,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      key: ValueKey('$keyPrefix-${segment.id}'),
      button: true,
      selected: isSelected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => onSelected(segment.value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    segment.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected
                          ? colorScheme.onSecondaryContainer
                          : colorScheme.onSurfaceVariant,
                      fontSize: 14,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.check_rounded,
                    size: 15,
                    color: colorScheme.primary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
