import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_zoom_drawer/flutter_zoom_drawer.dart';
import '../screens/course_screens.dart';
import '../utils/page_transitions.dart';
import 'floating_glass_control.dart';

class ShimmerWidget extends StatefulWidget {
  final bool isLight;
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerWidget({
    super.key,
    required this.isLight,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<ShimmerWidget> createState() => _ShimmerWidgetState();
}

class _ShimmerWidgetState extends State<ShimmerWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _animation = Tween<double>(begin: -2.0, end: 2.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.isLight
        ? Colors.white.withValues(alpha: 0.3)
        : Colors.grey[800]!;
    final highlightColor = widget.isLight
        ? Colors.white.withValues(alpha: 0.6)
        : Colors.grey[700]!;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width == double.infinity ? null : widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(_animation.value, 0),
              end: Alignment(_animation.value + 0.5, 0),
              colors: [
                baseColor,
                highlightColor,
                baseColor,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

class HomeTextConfig {
  final String? customTimeSalutation;
  final String? dateFormat;
  final String? usernameFormat;

  const HomeTextConfig({
    this.customTimeSalutation,
    this.dateFormat,
    this.usernameFormat,
  });
}

class HomeAppBar extends StatefulWidget implements PreferredSizeWidget {
  final String username;
  final String timeSalutation;
  final String currentGreeting;
  final HomeTextConfig? textConfig;
  final bool isLight;
  final bool isSyncing;
  final VoidCallback onSync;
  final VoidCallback onSettings;
  final VoidCallback? onSearch; // 🚀 新增：搜索回调
  final VoidCallback? onAiAssistant;
  final VoidCallback? onTeams; // 🚀 新增：团队回调
  final GlobalKey? settingsKey;
  final GlobalKey? courseKey;
  final GlobalKey? searchKey; // 🚀 新增
  final GlobalKey? syncKey;
  final GlobalKey? teamsKey; // 🚀 新增
  final GlobalKey? aiKey;
  final GlobalKey? menuKey; // 🚀 新增：左侧菜单键
  final bool showCourseButton;
  final int teamPendingCount; // 🚀 Uni-Sync 4.0: 团队待处理消息数
  final bool hasTeamConflictDot;

  const HomeAppBar({
    super.key,
    required this.username,
    required this.timeSalutation,
    required this.currentGreeting,
    this.textConfig,
    required this.isLight,
    required this.isSyncing,
    required this.onSync,
    required this.onSettings,
    this.onSearch,
    this.onAiAssistant,
    this.onTeams,
    this.settingsKey,
    this.courseKey,
    this.searchKey,
    this.syncKey,
    this.teamsKey,
    this.aiKey,
    this.menuKey,
    this.showCourseButton = false,
    this.teamPendingCount = 0,
    this.hasTeamConflictDot = false,
  });

  @override
  State<HomeAppBar> createState() => _HomeAppBarState();

  @override
  Size get preferredSize {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final dpr = view.devicePixelRatio;
    final logical = view.physicalSize / dpr;
    final landscape = logical.width > logical.height;
    return Size.fromHeight(landscape ? 64.0 : 112.0);
  }
}

class _HomeAppBarState extends State<HomeAppBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _syncRotationController;

  @override
  void initState() {
    super.initState();
    _syncRotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void dispose() {
    _syncRotationController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HomeAppBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSyncing && !oldWidget.isSyncing) {
      _syncRotationController.repeat();
    } else if (!widget.isSyncing && oldWidget.isSyncing) {
      _syncRotationController.stop();
      _syncRotationController.reset();
    }
  }

  String _formatUsername(String username, String? format) {
    if (format == null || format.isEmpty) return username;
    return format.replaceAll('{name}', username);
  }

  Widget _buildActionButton(BuildContext context,
      {required IconData icon,
      required VoidCallback onPressed,
      bool isLoading = false,
      int badgeCount = 0,
      bool showAlertDot = false,
      EdgeInsetsGeometry? margin,
      bool isSmall = false,
      Key? buttonKey}) {
    final double iconSize = isSmall ? 22.0 : 28.0;
    final double padding = isSmall ? 4.0 : 8.0;
    final colorScheme = Theme.of(context).colorScheme;

    final content = Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          iconSize: iconSize,
          padding: EdgeInsets.all(padding),
          constraints: isSmall ? const BoxConstraints() : null,
          style: floatingGlassPlainIconButtonStyle(),
          icon: isLoading
              ? RotationTransition(
                  turns: _syncRotationController,
                  child: Icon(icon,
                      size: iconSize,
                      color: widget.isLight
                          ? colorScheme.onInverseSurface
                          : colorScheme.primary),
                )
              : Icon(icon,
                  size: iconSize,
                  color: widget.isLight
                      ? colorScheme.onInverseSurface
                      : colorScheme.onSurface),
          onPressed: onPressed,
        ),
        if (badgeCount > 0)
          Positioned(
            right: isSmall ? 0 : 6,
            top: isSmall ? 0 : 6,
            child: Container(
              padding: EdgeInsets.all(isSmall ? 2 : 4),
              decoration: BoxDecoration(
                color: colorScheme.error,
                shape: BoxShape.circle,
              ),
              constraints: BoxConstraints(
                  minWidth: isSmall ? 12 : 16, minHeight: isSmall ? 12 : 16),
              child: Text(
                badgeCount > 9 ? '9+' : badgeCount.toString(),
                style: TextStyle(
                    color: colorScheme.onError,
                    fontSize: isSmall ? 7 : 8,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        if (showAlertDot && badgeCount <= 0)
          Positioned(
            right: isSmall ? 2 : 7,
            top: isSmall ? 2 : 7,
            child: Container(
              width: isSmall ? 8 : 10,
              height: isSmall ? 8 : 10,
              decoration: BoxDecoration(
                color: colorScheme.error,
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.isLight
                      ? colorScheme.onInverseSurface.withValues(alpha: 0.85)
                      : colorScheme.surface,
                  width: 1.2,
                ),
              ),
            ),
          ),
      ],
    );
    Widget action = content;
    if (margin != null) {
      action = Padding(padding: margin, child: action);
    }
    if (buttonKey != null) {
      action = KeyedSubtree(key: buttonKey, child: action);
    }
    return action;
  }

  Widget _buildAnimatedAction(int index, Widget child) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + index * 45),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, c) {
        final clamped = value.clamp(0.0, 1.0);
        return Opacity(
          opacity: clamped,
          child: Transform.translate(
            offset: Offset(0, (1 - clamped) * 8),
            child: Transform.scale(
              scale: 0.92 + clamped * 0.08,
              child: c,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final bool isTablet = MediaQuery.of(context).size.width >= 768;
    final toolbarH = isLandscape ? 64.0 : 86.0;
    final titleSize = isLandscape ? 18.0 : 22.0;
    final dateSize = isLandscape ? 12.0 : 13.0;
    final greetingSize = isLandscape ? 11.0 : 12.0;

    final bool isMobileGrid = !isTablet && !isLandscape;

    // 应用自定义文字配置
    final config = widget.textConfig;
    final displayTimeSalutation =
        config?.customTimeSalutation ?? widget.timeSalutation;
    final displayGreeting = widget.currentGreeting;
    final displayDateFormat = config?.dateFormat ?? 'MM月dd日 EEEE';
    final displayUsername =
        _formatUsername(widget.username, config?.usernameFormat);

    final searchBtn = _buildActionButton(
      context,
      icon: Icons.search_rounded,
      onPressed: widget.onSearch ?? () {},
      buttonKey: widget.searchKey,
      isSmall: isMobileGrid,
      margin: isMobileGrid ? EdgeInsets.zero : null,
    );
    final syncBtn = _buildActionButton(
      context,
      icon: Icons.cloud_sync_rounded,
      isLoading: widget.isSyncing,
      onPressed: widget.onSync,
      buttonKey: widget.syncKey,
      isSmall: isMobileGrid,
      margin: isMobileGrid ? EdgeInsets.zero : null,
    );
    final aiBtn = _buildActionButton(
      context,
      icon: Icons.smart_toy_outlined,
      onPressed: widget.onAiAssistant ?? () {},
      buttonKey: widget.aiKey,
      isSmall: isMobileGrid,
      margin: isMobileGrid ? EdgeInsets.zero : null,
    );
    final teamsBtn = _buildActionButton(
      context,
      icon: Icons.people_rounded,
      onPressed: widget.onTeams ?? () {},
      buttonKey: widget.teamsKey,
      badgeCount: widget.teamPendingCount,
      showAlertDot: widget.hasTeamConflictDot,
      isSmall: isMobileGrid,
      margin: isMobileGrid ? EdgeInsets.zero : null,
    );
    final settingsBtn = _buildActionButton(
      context,
      icon: Icons.settings_rounded,
      onPressed: widget.onSettings,
      buttonKey: widget.settingsKey,
      isSmall: isMobileGrid,
      margin: isMobileGrid ? EdgeInsets.zero : null,
    );

    return FloatingGlassAppBar(
      backgroundColor: widget.isLight ? Colors.transparent : null,
      floatingControlTint:
          widget.isLight ? colorScheme.scrim.withValues(alpha: 0.32) : null,
      floatingControlIsDark: widget.isLight ? true : null,
      elevation: 0,
      flexibleSpace: FloatingGlassTopBarBackground(
        tint: widget.isLight ? colorScheme.scrim : null,
        isDark: widget.isLight ? true : null,
        unboundedHeight: toolbarH + MediaQuery.paddingOf(context).top,
      ),
      toolbarHeight: toolbarH,
      leading: (isTablet || isLandscape)
          ? null
          : IconButton(
              key: widget.menuKey,
              icon: const Icon(Icons.menu_rounded),
              iconSize: 28,
              color: widget.isLight ? Colors.white : colorScheme.onSurface,
              // The shared app-bar adapter centers this control inside its
              // circular glass shell. Keep the native hit target symmetric
              // so the hamburger glyph does not drift to the right.
              padding: EdgeInsets.zero,
              style: floatingGlassPlainIconButtonStyle(),
              onPressed: () {
                ZoomDrawer.of(context)?.toggle();
              },
            ),
      titleSpacing:
          (isTablet || isLandscape) ? NavigationToolbar.kMiddleSpacing : 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "$displayTimeSalutation, $displayUsername",
            style: TextStyle(
              fontSize: titleSize,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              color: widget.isLight ? Colors.white : null,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat(displayDateFormat, 'zh_CN').format(DateTime.now()),
            style: TextStyle(
              fontSize: dateSize,
              fontWeight: FontWeight.w500,
              color: widget.isLight
                  ? Colors.white.withValues(alpha: 0.9)
                  : Colors.blueGrey,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            displayGreeting,
            style: TextStyle(
              fontSize: greetingSize,
              color: widget.isLight
                  ? Colors.white.withValues(alpha: 0.7)
                  : Colors.grey,
            ),
          ),
        ],
      ),
      actions: [
        if (isTablet || isLandscape) ...[
          if (widget.showCourseButton)
            _buildAnimatedAction(
              0,
              _buildActionButton(
                context,
                icon: Icons.calendar_view_week_rounded,
                onPressed: () async {
                  await PageTransitions.pushFromRect(
                    context: context,
                    page: WeeklyCourseScreen(username: widget.username),
                    sourceKey: widget.courseKey ?? GlobalKey(),
                  );
                },
                buttonKey: widget.courseKey,
              ),
            ),
          _buildAnimatedAction(1, searchBtn),
          _buildAnimatedAction(2, syncBtn),
          _buildAnimatedAction(3, teamsBtn),
          _buildAnimatedAction(4, aiBtn),
          _buildAnimatedAction(5, settingsBtn),
        ] else ...[
          _buildAnimatedAction(0, searchBtn),
          _buildAnimatedAction(1, syncBtn),
        ],
        const SizedBox(width: 8),
      ],
    );
  }
}
