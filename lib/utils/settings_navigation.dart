import 'dart:async';

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

/// Shared navigation-key registry and route pusher for settings screens.
mixin SettingsNavigationMixin<T extends StatefulWidget> on State<T> {
  final Map<String, GlobalKey> _settingsNavigationKeys = {};

  /// Override when navigation keys share an existing key map such as
  /// target-highlight item keys.
  Map<String, GlobalKey> get settingsNavigationKeyStore =>
      _settingsNavigationKeys;

  bool get isEmbeddedSettingsPage => false;

  String get settingsNavigationKeyPrefix => 'settings';

  GlobalKey settingsNavigationKey(String id) =>
      settingsNavigationKeyStore.putIfAbsent(
        id,
        () => GlobalKey(debugLabel: '$settingsNavigationKeyPrefix-$id'),
      );

  Future<R?> openSettingsPage<R>(
    String id,
    Widget page, {
    RouteSettings? settings,
    bool rootNavigator = false,
    IconData? placeholderIcon,
    Color? sourceColor,
    BorderRadius sourceBorderRadius = const BorderRadius.all(
      Radius.circular(16),
    ),
  }) => SettingsNavigation.push<R>(
    context: context,
    page: page,
    sourceKey: settingsNavigationKey(id),
    isEmbedded: isEmbeddedSettingsPage,
    rootNavigator: rootNavigator,
    settings: settings,
    placeholderIcon: placeholderIcon,
    sourceColor: sourceColor,
    sourceBorderRadius: sourceBorderRadius,
  );
}

/// Shared initial-target scroll and temporary highlight behavior for settings
/// screens and sub-pages.
mixin SettingsTargetHighlightMixin<T extends StatefulWidget> on State<T> {
  String? highlightTarget;
  Timer? _highlightTimer;

  GlobalKey? resolveSettingsTargetKey(String target);

  void scheduleInitialSettingsTarget(
    String? initialTarget, {
    bool highlight = true,
    Duration highlightDuration = const Duration(seconds: 3),
    Duration scrollDuration = const Duration(milliseconds: 500),
    Curve curve = Curves.easeInOut,
    double alignment = 0.15,
  }) {
    if (initialTarget == null || initialTarget.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      scrollToSettingsTarget(
        initialTarget,
        highlight: highlight,
        highlightDuration: highlightDuration,
        scrollDuration: scrollDuration,
        curve: curve,
        alignment: alignment,
      );
    });
  }

  void scrollToSettingsTarget(
    String target, {
    bool highlight = true,
    Duration highlightDuration = const Duration(seconds: 3),
    Duration scrollDuration = const Duration(milliseconds: 500),
    Curve curve = Curves.easeInOut,
    double alignment = 0.15,
  }) {
    final key = resolveSettingsTargetKey(target);
    final targetContext = key?.currentContext;
    if (targetContext == null) return;
    if (highlight) {
      setState(() => highlightTarget = target);
      _highlightTimer?.cancel();
      _highlightTimer = Timer(highlightDuration, () {
        _highlightTimer = null;
        if (mounted) {
          setState(() => highlightTarget = null);
        }
      });
    }
    Scrollable.ensureVisible(
      targetContext,
      duration: scrollDuration,
      curve: curve,
      alignment: alignment,
    );
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _highlightTimer = null;
    super.dispose();
  }
}
