import 'dart:async';

import 'package:flutter/material.dart';

/// Route-guarded loading dialog controller that removes only the dialog route
/// it pushed, never dismissing unrelated dialogs or routes pushed on top.
class CourseLoadingDialogController {
  CourseLoadingDialogController({this.logPrefix = '课表进度弹窗'});

  final String logPrefix;

  bool _isOpen = false;
  Route<void>? _route;
  Future<void>? _ready;
  NavigatorState? _navigator;

  bool get isOpen => _isOpen;

  void show(BuildContext context, String message) {
    if (!context.mounted || _isOpen) return;

    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );

    _isOpen = true;
    _route = route;
    _navigator = navigator;
    _ready = Future<void>.microtask(() {});
    final dialogFuture = navigator.push<void>(route);
    unawaited(_observe(route, dialogFuture));
  }

  Future<void> _observe(Route<void> route, Future<void> dialogFuture) async {
    try {
      await dialogFuture;
    } catch (error, stackTrace) {
      debugPrint('⚠️ $logPrefix异常结束: $error\n$stackTrace');
    } finally {
      if (identical(_route, route)) {
        _reset();
      }
    }
  }

  Future<void> close() async {
    if (!_isOpen) return;

    final route = _route;
    final ready = _ready;
    if (route == null) return;
    if (ready != null) await ready;

    final navigator = _navigator;
    if (identical(_route, route)) {
      if (navigator != null && navigator.mounted && route.isActive) {
        navigator.removeRoute(route);
      }
      _reset();
    }
  }

  void dispose() {
    final route = _route;
    final navigator = _navigator;
    if (route != null &&
        navigator != null &&
        navigator.mounted &&
        route.isActive) {
      navigator.removeRoute(route);
    }
    _reset();
  }

  void _reset() {
    _isOpen = false;
    _route = null;
    _ready = null;
    _navigator = null;
  }
}

/// Shared Material 3 option card for choosing between replace and merge
/// schedule import modes.
class CourseImportOptionCard extends StatelessWidget {
  const CourseImportOptionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: highlighted ? accentColor : colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: accentColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: highlighted ? accentColor : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
