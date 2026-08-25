import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'optional_liquid_glass_surface.dart';

/// A compact transient status message anchored to the control that initiated
/// the operation. It uses the root overlay so it never participates in the
/// Scaffold's SnackBar/FAB layout calculations.
class AppStatusToast {
  AppStatusToast._();

  static OverlayEntry? _activeEntry;

  static void show({
    required BuildContext context,
    required GlobalKey anchorKey,
    required String message,
    IconData icon = Icons.check_circle_rounded,
    Duration duration = const Duration(milliseconds: 1800),
  }) {
    dismissCurrent();
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    final anchorBox =
        anchorKey.currentContext?.findRenderObject() as RenderBox?;
    Rect? anchorRect;
    if (overlayBox != null && anchorBox != null && anchorBox.hasSize) {
      final offset = anchorBox.localToGlobal(Offset.zero, ancestor: overlayBox);
      anchorRect = offset & anchorBox.size;
    }

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) {
        final mediaQuery = MediaQuery.of(overlayContext);
        final right = anchorRect == null
            ? 16.0
            : math.max(16.0, mediaQuery.size.width - anchorRect.right);
        final top = anchorRect?.bottom ?? mediaQuery.padding.top + 12;
        return Positioned(
          top: top + 8,
          right: right,
          child: _AppStatusToastView(
            message: message,
            icon: icon,
            duration: duration,
            onDismissed: () => _remove(entry),
          ),
        );
      },
    );
    _activeEntry = entry;
    overlay.insert(entry);
  }

  static void dismissCurrent() {
    final entry = _activeEntry;
    _activeEntry = null;
    if (entry?.mounted ?? false) entry!.remove();
  }

  static void _remove(OverlayEntry entry) {
    if (!identical(_activeEntry, entry)) return;
    _activeEntry = null;
    if (entry.mounted) entry.remove();
  }
}

class _AppStatusToastView extends StatefulWidget {
  const _AppStatusToastView({
    required this.message,
    required this.icon,
    required this.duration,
    required this.onDismissed,
  });

  final String message;
  final IconData icon;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  State<_AppStatusToastView> createState() => _AppStatusToastViewState();
}

class _AppStatusToastViewState extends State<_AppStatusToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 160),
    );
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _opacity = curved;
    _offset = Tween<Offset>(
      begin: const Offset(0, -0.18),
      end: Offset.zero,
    ).animate(curved);
    _controller.forward();
    _dismissTimer = Timer(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _controller.reverse();
    if (mounted) widget.onDismissed();
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Widget _content(Color foregroundColor, Color iconColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(widget.icon, size: 18, color: iconColor),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              widget.message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foregroundColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fallback = Container(
      decoration: BoxDecoration(
        color: colorScheme.inverseSurface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.16),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: _content(
        colorScheme.onInverseSurface,
        colorScheme.primaryContainer,
      ),
    );
    final glassContent = _content(
      colorScheme.onSurface,
      colorScheme.primary,
    );

    return Material(
      type: MaterialType.transparency,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _opacity,
          child: SlideTransition(
            position: _offset,
            child: ConstrainedBox(
              key: const ValueKey<String>('app-status-toast'),
              constraints: const BoxConstraints(maxWidth: 260),
              child: OptionalLiquidGlassPanel(
                borderRadius: 18,
                tint: colorScheme.primary.withValues(alpha: 0.14),
                isDark: colorScheme.brightness == Brightness.dark,
                fallback: fallback,
                child: glassContent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
