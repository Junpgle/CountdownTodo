import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Height of the frameless macOS title-bar strip reserved for the traffic
/// lights and window dragging.
const double macosWindowChromeHeight = 32.0;

/// Adds the macOS in-app window controls after the native title bar is hidden.
///
/// The native title bar buttons are disabled in [WindowOptions]. Keeping the
/// controls in Flutter makes them follow the app surface and keeps the same
/// layout on the dashboard, login page, splash screens, and settings routes.
class MacosWindowChrome extends StatelessWidget {
  const MacosWindowChrome({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS) return child;

    final mediaQuery = MediaQuery.maybeOf(context);
    final content = mediaQuery == null
        ? child
        : MediaQuery(
            data: mediaQuery.copyWith(
              // The hidden native title bar no longer contributes a top
              // inset. Reintroduce the custom title-bar strip through the
              // same MediaQuery channel that AppBar and SafeArea already use.
              padding: _withTopInset(
                mediaQuery.padding,
                macosWindowChromeHeight,
              ),
              viewPadding: _withTopInset(
                mediaQuery.viewPadding,
                macosWindowChromeHeight,
              ),
            ),
            child: child,
          );

    return Stack(
      fit: StackFit.expand,
      children: [
        content,
        // Leave a small, non-interactive strip for moving the window. The
        // traffic lights and the app-bar actions remain outside this area.
        const Positioned(
          top: 0,
          left: 84,
          right: 240,
          height: macosWindowChromeHeight,
          child: DragToMoveArea(
            child: SizedBox.expand(),
          ),
        ),
        const Positioned(
          top: 0,
          left: 7,
          child: _MacosTrafficLights(),
        ),
      ],
    );
  }

  EdgeInsets _withTopInset(EdgeInsets insets, double minimumTop) {
    return EdgeInsets.fromLTRB(
      insets.left,
      insets.top < minimumTop ? minimumTop : insets.top,
      insets.right,
      insets.bottom,
    );
  }
}

class _MacosTrafficLights extends StatelessWidget {
  const _MacosTrafficLights();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MacosTrafficLight(
          type: _MacosTrafficLightType.close,
          label: '关闭窗口',
        ),
        _MacosTrafficLight(
          type: _MacosTrafficLightType.minimize,
          label: '最小化窗口',
        ),
        _MacosTrafficLight(
          type: _MacosTrafficLightType.zoom,
          label: '最大化或还原窗口',
        ),
      ],
    );
  }
}

enum _MacosTrafficLightType { close, minimize, zoom }

class _MacosTrafficLight extends StatefulWidget {
  const _MacosTrafficLight({
    required this.type,
    required this.label,
  });

  final _MacosTrafficLightType type;
  final String label;

  @override
  State<_MacosTrafficLight> createState() => _MacosTrafficLightState();
}

class _MacosTrafficLightState extends State<_MacosTrafficLight> {
  bool _isHovered = false;

  Color get _trafficColor {
    // These are macOS's conventional semantic traffic-light colors rather
    // than app theme colors, so the controls remain recognizable in either
    // light or dark mode.
    switch (widget.type) {
      case _MacosTrafficLightType.close:
        return const Color(0xFFFF5F57);
      case _MacosTrafficLightType.minimize:
        return const Color(0xFFFFBD2E);
      case _MacosTrafficLightType.zoom:
        return const Color(0xFF28C840);
    }
  }

  IconData get _hoverIcon {
    switch (widget.type) {
      case _MacosTrafficLightType.close:
        return Icons.close_rounded;
      case _MacosTrafficLightType.minimize:
        return Icons.remove_rounded;
      case _MacosTrafficLightType.zoom:
        return Icons.fullscreen_rounded;
    }
  }

  Future<void> _handlePressed() async {
    try {
      switch (widget.type) {
        case _MacosTrafficLightType.close:
          // The existing WindowService close listener remains responsible for
          // the app's close confirmation and tray behavior.
          await windowManager.close();
        case _MacosTrafficLightType.minimize:
          await windowManager.minimize();
        case _MacosTrafficLightType.zoom:
          if (await windowManager.isMaximized()) {
            await windowManager.unmaximize();
          } else {
            await windowManager.maximize();
          }
      }
    } catch (_) {
      // A window can disappear while the async native call is in flight.
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final glyphColor = colorScheme.onSurface.withValues(alpha: 0.62);

    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handlePressed,
          child: SizedBox(
            width: 25,
            height: 25,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: _isHovered ? 14 : 13,
                height: _isHovered ? 14 : 13,
                decoration: BoxDecoration(
                  color: _trafficColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.shadow.withValues(alpha: 0.22),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 80),
                  opacity: _isHovered ? 1 : 0,
                  child: Icon(
                    _hoverIcon,
                    size: 9,
                    color: glyphColor,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
