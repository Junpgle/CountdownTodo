import 'package:flutter/material.dart';

import 'page_transitions.dart';

/// Settings cards expand into a page in portrait layouts. Embedded panes keep
/// their existing nested navigation, including route names for breadcrumbs.
class SettingsNavigation {
  const SettingsNavigation._();

  static final _pendingPushes = Expando<Future<Object?>>();

  static Future<T?> push<T>({
    required BuildContext context,
    required Widget page,
    required GlobalKey sourceKey,
    bool isEmbedded = false,
    bool rootNavigator = false,
    RouteSettings? settings,
    IconData? placeholderIcon,
    Color? sourceColor,
    BorderRadius sourceBorderRadius = const BorderRadius.all(
      Radius.circular(16),
    ),
  }) {
    if (!context.mounted) return Future<T?>.value();
    final pending = _pendingPushes[sourceKey];
    if (pending != null) return pending.then((result) => result as T?);
    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    final navigationContext = rootNavigator
        ? Navigator.of(context, rootNavigator: true).context
        : context;
    final Future<T?> navigation;
    if (isPortrait && !isEmbedded) {
      navigation = PageTransitions.pushFromRect<T>(
        context: navigationContext,
        page: page,
        sourceKey: sourceKey,
        settings: settings,
        placeholderIcon: placeholderIcon,
        sourceColor: sourceColor,
        sourceBorderRadius: sourceBorderRadius,
      );
    } else {
      navigation = Navigator.of(
        navigationContext,
      ).push<T>(PageTransitions.slideHorizontal<T>(page, settings: settings));
    }
    // The shared transition resolves its source on the next frame. Coalesce
    // repeated taps so that this delay cannot open duplicate settings pages.
    final guarded = navigation.whenComplete(() {
      _pendingPushes[sourceKey] = null;
    });
    _pendingPushes[sourceKey] = guarded;
    return guarded;
  }
}
