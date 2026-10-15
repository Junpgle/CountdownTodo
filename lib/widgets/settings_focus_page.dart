import 'dart:async';

import 'package:flutter/material.dart';

/// Reveals a catalogued label without tapping a control or changing a setting.
/// Works with eager, lazy, nested and asynchronously loaded settings pages.
class SettingsFocusPage extends StatefulWidget {
  const SettingsFocusPage({
    super.key,
    required this.child,
    required this.labels,
    this.fallbackLabels = const [],
    this.unavailableHint = '该选项可能需要先选择相应模式，或满足设备、登录条件后才会显示。',
  });

  final Widget child;
  final List<String> labels;
  final List<String> fallbackLabels;
  final String unavailableHint;

  @override
  State<SettingsFocusPage> createState() => _SettingsFocusPageState();
}

class _SettingsFocusPageState extends State<SettingsFocusPage> {
  final _contentKey = GlobalKey();
  final _stackKey = GlobalKey();
  final _visitedScrollPositions = <ScrollPosition, double>{};
  Timer? _retry;
  Timer? _highlightTimer;
  Rect? _highlight;
  bool _showHint = false;
  bool _stopped = false;
  int _attempts = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  @override
  void dispose() {
    _retry?.cancel();
    _highlightTimer?.cancel();
    super.dispose();
  }

  void _later() {
    if (!mounted || _stopped) return;
    _retry?.cancel();
    _retry = Timer(const Duration(milliseconds: 80), _scan);
  }

  Future<void> _scan() async {
    if (!mounted || _stopped || widget.labels.isEmpty) return;
    final root = _contentKey.currentContext as Element?;
    if (root == null) return _later();
    final route = ModalRoute.of(context);
    if (route != null &&
        (!route.isCurrent ||
            route.offstage ||
            (route.animation != null &&
                route.animation!.status != AnimationStatus.completed))) {
      return _later();
    }
    final labels = _attempts < 35
        ? widget.labels
        : [...widget.labels, ...widget.fallbackLabels];
    Element? match;
    var bestRank = labels.length;
    final scrollables = <ScrollableState>[];
    void visit(Element element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        final state = element.state as ScrollableState;
        if (axisDirectionToAxis(state.axisDirection) == Axis.vertical) {
          scrollables.add(state);
        }
      }
      final widget = element.widget;
      final text = widget is Text
          ? widget.data ?? widget.textSpan?.toPlainText()
          : widget is Tooltip
          ? widget.message
          : null;
      final rank = text == null
          ? -1
          : labels.indexWhere(
              (label) =>
                  text == label ||
                  (label.endsWith(':') && text.startsWith(label)),
            );
      if (rank >= 0 && rank < bestRank) {
        final box = element.findRenderObject();
        if (box is RenderBox &&
            box.attached &&
            box.hasSize &&
            !box.size.isEmpty) {
          // A Stepper or Offstage pane may contain a second, hidden label.
          var offstage = false;
          element.visitAncestorElements((ancestor) {
            if (ancestor.widget case Offstage(offstage: true)) offstage = true;
            return !offstage;
          });
          if (!offstage) {
            match = element;
            bestRank = rank;
          }
        }
      }
      element.visitChildren(visit);
    }

    root.visitChildren(visit);
    _attempts++;
    final target = match;
    if (target != null && target.mounted) {
      _stopped = true;
      await Scrollable.ensureVisible(
        target,
        alignment: 0.3,
        duration: const Duration(milliseconds: 300),
      );
      if (!mounted || !target.mounted) return;
      final box = target.findRenderObject();
      final stack = _stackKey.currentContext?.findRenderObject();
      if (box is RenderBox &&
          stack is RenderBox &&
          box.attached &&
          box.hasSize) {
        final origin = box.localToGlobal(Offset.zero, ancestor: stack);
        setState(() {
          _highlight = (origin & box.size)
              .inflate(8)
              .intersect(Offset.zero & stack.size);
          _showHint = bestRank >= widget.labels.length;
        });
        _highlightTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _highlight = null);
        });
      }
      return;
    }
    if (_attempts == 35 && widget.fallbackLabels.isNotEmpty) {
      _visitedScrollPositions.clear();
      for (final scrollable in scrollables) {
        final position = scrollable.position;
        if (position.hasContentDimensions) {
          position.jumpTo(position.minScrollExtent);
        }
      }
      return _later();
    }
    // Let loading spinners resolve before scanning lazy list contents.
    if (_attempts > 3) {
      for (final scrollable in scrollables) {
        final position = scrollable.position;
        if (!position.hasContentDimensions || position.maxScrollExtent <= 0) {
          continue;
        }
        final last = _visitedScrollPositions[position];
        final next = (position.pixels + position.viewportDimension * 0.65)
            .clamp(position.minScrollExtent, position.maxScrollExtent);
        if (next > position.pixels + 1 && (last == null || next > last + 1)) {
          _visitedScrollPositions[position] = next;
          position.jumpTo(next);
          break;
        }
      }
    }
    if (_attempts < 65) {
      _later();
    } else {
      _stopped = true;
      if (mounted) setState(() => _showHint = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification &&
            notification.dragDetails != null) {
          _stopped = true;
          _retry?.cancel();
          if (_highlight != null) setState(() => _highlight = null);
        }
        return false;
      },
      child: Stack(
        key: _stackKey,
        children: [
          KeyedSubtree(key: _contentKey, child: widget.child),
          if (_highlight case final rect?)
            Positioned.fromRect(
              rect: rect,
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const ValueKey('settings-focus-highlight'),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.12),
                    border: Border.all(color: colors.primary, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          if (_showHint)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: SafeArea(
                child: Material(
                  color: colors.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      widget.unavailableHint,
                      style: TextStyle(color: colors.onSecondaryContainer),
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
