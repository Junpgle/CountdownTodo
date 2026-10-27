import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// One homepage card in a Windows column. Its builder runs only inside the
/// visible window plus a half-viewport prefetch margin.
@immutable
class WindowsDashboardSection {
  const WindowsDashboardSection({
    required this.id,
    required this.estimatedHeight,
    required this.builder,
  });

  final String id;
  final double estimatedHeight;
  final WidgetBuilder builder;
}

/// Lazily mounts cards in the two existing independently ordered columns.
///
/// The columns remain a single scroll surface, so their current staggered
/// layout, ordering, footer, and scroll gesture behavior are preserved. Cards
/// outside the prefetch window become measured-height placeholders; their
/// descendants (including live images, animations, and render resources) are
/// disposed until the user approaches them again.
class WindowsDashboardScrollCoordinator extends StatefulWidget {
  const WindowsDashboardScrollCoordinator({
    super.key,
    required this.leftSections,
    required this.rightSections,
    required this.footer,
    required this.padding,
    required this.maxWidth,
    this.columnGap = 40,
    this.pageStorageKey = const PageStorageKey<String>(
      'windows-home-dashboard-scroll',
    ),
  });

  final List<WindowsDashboardSection> leftSections;
  final List<WindowsDashboardSection> rightSections;
  final Widget footer;
  final EdgeInsets padding;
  final double maxWidth;
  final double columnGap;
  final PageStorageKey<String> pageStorageKey;

  @override
  State<WindowsDashboardScrollCoordinator> createState() =>
      _WindowsDashboardScrollCoordinatorState();
}

class _WindowsDashboardScrollCoordinatorState
    extends State<WindowsDashboardScrollCoordinator> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, double> _measuredHeights = {};

  double _heightFor(
    WindowsDashboardSection section,
    String columnId,
    double columnWidth,
  ) =>
      _measuredHeights['$columnId:${section.id}:${columnWidth.round()}'] ??
      section.estimatedHeight;

  void _recordHeight(String id, double height) {
    if (!height.isFinite || height <= 0) return;
    _measuredHeights[id] = height;
  }

  List<Widget> _buildColumn(
    List<WindowsDashboardSection> sections, {
    required double viewportExtent,
    required double scrollOffset,
    required double leadingPadding,
    required String columnId,
    required double columnWidth,
  }) {
    var estimatedTop = leadingPadding;
    final widgets = <Widget>[];
    for (final section in sections) {
      final height = _heightFor(section, columnId, columnWidth);
      final heightKey = '$columnId:${section.id}:${columnWidth.round()}';
      final shouldInitiallyMount =
          estimatedTop + height > scrollOffset - viewportExtent * 0.5 &&
          estimatedTop < scrollOffset + viewportExtent * 1.5;
      widgets.add(
        _WindowsDashboardSectionSlot(
          key: ValueKey<String>('windows-home-section-${section.id}'),
          id: section.id,
          heightKey: heightKey,
          height: height,
          initiallyMounted: shouldInitiallyMount,
          onMeasured: _recordHeight,
          builder: section.builder,
        ),
      );
      estimatedTop += height;
    }
    return widgets;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportExtent = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;
        final scrollOffset = _scrollController.hasClients
            ? _scrollController.position.pixels
            : 0.0;
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth - widget.padding.horizontal
            : widget.maxWidth;
        final contentWidth = availableWidth
            .clamp(0.0, widget.maxWidth)
            .toDouble();
        final rowWidth = (contentWidth - widget.columnGap)
            .clamp(0.0, contentWidth)
            .toDouble();
        final leftColumnWidth = widget.rightSections.isEmpty
            ? contentWidth
            : rowWidth * 10 / 21;
        final rightColumnWidth = rowWidth * 11 / 21;
        final leftWidgets = _buildColumn(
          widget.leftSections,
          columnId: 'left',
          columnWidth: leftColumnWidth,
          viewportExtent: viewportExtent,
          scrollOffset: scrollOffset,
          leadingPadding: widget.padding.top,
        );
        final rightWidgets = _buildColumn(
          widget.rightSections,
          columnId: 'right',
          columnWidth: rightColumnWidth,
          viewportExtent: viewportExtent,
          scrollOffset: scrollOffset,
          leadingPadding: widget.padding.top,
        );

        return SingleChildScrollView(
          key: widget.pageStorageKey,
          controller: _scrollController,
          padding: widget.padding,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: widget.maxWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 10,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: leftWidgets,
                        ),
                      ),
                      if (rightWidgets.isNotEmpty) ...[
                        SizedBox(width: widget.columnGap),
                        Expanded(
                          flex: 11,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: rightWidgets,
                          ),
                        ),
                      ],
                    ],
                  ),
                  widget.footer,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WindowsDashboardSectionSlot extends StatefulWidget {
  const _WindowsDashboardSectionSlot({
    super.key,
    required this.id,
    required this.heightKey,
    required this.height,
    required this.initiallyMounted,
    required this.onMeasured,
    required this.builder,
  });

  final String id;
  final String heightKey;
  final double height;
  final bool initiallyMounted;
  final ValueChanged2<String, double> onMeasured;
  final WidgetBuilder builder;

  @override
  State<_WindowsDashboardSectionSlot> createState() =>
      _WindowsDashboardSectionSlotState();
}

typedef ValueChanged2<A, B> = void Function(A first, B second);

class _WindowsDashboardSectionSlotState
    extends State<_WindowsDashboardSectionSlot> {
  final GlobalKey _measureKey = GlobalKey();
  ScrollPosition? _position;
  late bool _mountedSection;
  late double _height;

  @override
  void initState() {
    super.initState();
    _height = widget.height;
    _mountedSection = widget.initiallyMounted;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextPosition = Scrollable.of(context).position;
    if (identical(_position, nextPosition)) return;
    _position?.removeListener(_updateRetention);
    _position = nextPosition;
    _position!.addListener(_updateRetention);
    _scheduleRetentionCheck();
  }

  @override
  void didUpdateWidget(covariant _WindowsDashboardSectionSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.height != widget.height) {
      _height = widget.height;
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_updateRetention);
    super.dispose();
  }

  void _scheduleRetentionCheck() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateRetention();
    });
  }

  RenderBox? get _renderBox {
    final object = _measureKey.currentContext?.findRenderObject();
    return object is RenderBox && object.attached ? object : null;
  }

  double? _sectionTop(RenderBox box) {
    try {
      return RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset;
    } catch (_) {
      return null;
    }
  }

  void _updateRetention() {
    final position = _position;
    final box = _renderBox;
    if (position == null || box == null || !position.hasViewportDimension) {
      return;
    }
    final top = _sectionTop(box);
    if (top == null) return;
    final margin = position.viewportDimension * 0.5;
    final shouldMount =
        top + box.size.height > position.pixels - margin &&
        top < position.pixels + position.viewportDimension + margin;
    if (shouldMount == _mountedSection) return;
    setState(() => _mountedSection = shouldMount);
  }

  void _handleMeasured(Size size) {
    if (!mounted || (size.height - _height).abs() < 0.5) return;
    final oldHeight = _height;
    _height = size.height;
    widget.onMeasured(widget.heightKey, size.height);

    final position = _position;
    final box = _renderBox;
    if (position == null || box == null || !position.hasContentDimensions) {
      return;
    }
    final top = _sectionTop(box);
    if (top == null || top >= position.pixels) return;

    // If a section above the current viewport changed height while mounting,
    // move the scroll offset by the same delta to keep the visible anchor still.
    final target = (position.pixels + size.height - oldHeight)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((target - position.pixels).abs() >= 0.5) position.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    if (!_mountedSection) {
      return SizedBox(key: _measureKey, height: _height);
    }
    return _DashboardSectionSizeReporter(
      key: _measureKey,
      onChange: _handleMeasured,
      child: Builder(builder: widget.builder),
    );
  }
}

class _DashboardSectionSizeReporter extends SingleChildRenderObjectWidget {
  const _DashboardSectionSizeReporter({
    super.key,
    required this.onChange,
    required super.child,
  });

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderDashboardSectionSizeReporter(onChange);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderDashboardSectionSizeReporter renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class _RenderDashboardSectionSizeReporter extends RenderProxyBox {
  _RenderDashboardSectionSizeReporter(this.onChange);

  ValueChanged<Size> onChange;
  Size? _lastReportedSize;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _lastReportedSize) return;
    _lastReportedSize = size;
    final measuredSize = size;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      onChange(measuredSize);
    });
  }
}
