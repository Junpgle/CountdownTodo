import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../screens/course_screens.dart';
import '../utils/page_transitions.dart';

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
    final baseColor =
        widget.isLight ? Colors.white.withValues(alpha: 0.3) : Colors.grey[800]!;
    final highlightColor =
        widget.isLight ? Colors.white.withValues(alpha: 0.6) : Colors.grey[700]!;

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

class HomeAppBar extends StatefulWidget implements PreferredSizeWidget {
  final String username;
  final String timeSalutation;
  final String currentGreeting;
  final bool isLight;
  final bool isSyncing;
  final VoidCallback onSync;
  final VoidCallback onSettings;
  final VoidCallback? onSearch; // 🚀 新增：搜索回调
  final VoidCallback? onTeams; // 🚀 新增：团队回调
  final GlobalKey? settingsKey;
  final GlobalKey? courseKey;
  final GlobalKey? searchKey; // 🚀 新增
  final GlobalKey? teamsKey; // 🚀 新增
  final bool showCourseButton;
  final int teamPendingCount; // 🚀 Uni-Sync 4.0: 团队待处理消息数
  final bool hasTeamConflictDot;

  const HomeAppBar({
    super.key,
    required this.username,
    required this.timeSalutation,
    required this.currentGreeting,
    required this.isLight,
    required this.isSyncing,
    required this.onSync,
    required this.onSettings,
    this.onSearch,
    this.onTeams,
    this.settingsKey,
    this.courseKey,
    this.searchKey,
    this.teamsKey,
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
    return Size.fromHeight(landscape ? 64.0 : 100.0);
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

  Widget _buildActionButton(BuildContext context,
      {required IconData icon,
      required VoidCallback onPressed,
      bool isLoading = false,
      int badgeCount = 0,
      bool showAlertDot = false,
      EdgeInsetsGeometry? margin,
      bool isSmall = false,
      Key? buttonKey}) {
    final double iconSize = isSmall ? 18.0 : 24.0;
    final double padding = isSmall ? 4.0 : 8.0;
    final double? containerSize = isSmall ? 34.0 : null;

    return Container(
      key: buttonKey,
      width: containerSize,
      height: containerSize,
      alignment: Alignment.center,
      margin: margin ?? const EdgeInsets.only(right: 8, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: widget.isLight
            ? Colors.white.withValues(alpha: 0.15)
            : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        shape: BoxShape.circle,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          IconButton(
            iconSize: iconSize,
            padding: EdgeInsets.all(padding),
            constraints: isSmall ? const BoxConstraints() : null,
            icon: isLoading
                ? RotationTransition(
                    turns: _syncRotationController,
                    child: Icon(icon,
                        size: iconSize,
                        color: widget.isLight
                            ? Colors.white
                            : Theme.of(context).colorScheme.primary),
                  )
                : Icon(icon,
                    size: iconSize,
                    color: widget.isLight
                        ? Colors.white
                        : Theme.of(context).colorScheme.onSurface),
            onPressed: onPressed,
          ),
          if (badgeCount > 0)
            Positioned(
              right: isSmall ? 0 : 6,
              top: isSmall ? 0 : 6,
              child: Container(
                padding: EdgeInsets.all(isSmall ? 2 : 4),
                decoration: const BoxDecoration(
                    color: Colors.redAccent, shape: BoxShape.circle),
                constraints: BoxConstraints(
                    minWidth: isSmall ? 12 : 16, minHeight: isSmall ? 12 : 16),
                child: Text(
                  badgeCount > 9 ? '9+' : badgeCount.toString(),
                  style: TextStyle(
                      color: Colors.white,
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
                  color: Colors.redAccent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.isLight
                        ? Colors.white.withValues(alpha: 0.85)
                        : Theme.of(context).colorScheme.surface,
                    width: 1.2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final bool isTablet = MediaQuery.of(context).size.width >= 768;
    final toolbarH = isLandscape ? 64.0 : 100.0;
    final titleSize = isLandscape ? 18.0 : 22.0;
    final dateSize = isLandscape ? 12.0 : 13.0;
    final greetingSize = isLandscape ? 11.0 : 12.0;

    final bool isMobileGrid = !isTablet && !isLandscape;

    // 🚀 定义各个操作按钮，以便在不同布局中复用
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
      isSmall: isMobileGrid,
      margin: isMobileGrid ? EdgeInsets.zero : null,
    );
    final teamsBtn = _buildActionButton(
      context,
      icon: Icons.people_rounded,
      onPressed: widget.onTeams ?? () => Navigator.pushNamed(context, '/teams'),
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

    return AppBar(
      backgroundColor: widget.isLight ? Colors.transparent : null,
      elevation: 0,
      toolbarHeight: toolbarH,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "${widget.timeSalutation}, ${widget.username}",
            style: TextStyle(
              fontSize: titleSize,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              color: widget.isLight ? Colors.white : null,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('MM月dd日 EEEE', 'zh_CN').format(DateTime.now()),
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
            widget.currentGreeting,
            style: TextStyle(
              fontSize: greetingSize,
              color:
                  widget.isLight ? Colors.white.withValues(alpha: 0.7) : Colors.grey,
            ),
          ),
        ],
      ),
      actions: [
        if (isTablet || isLandscape) ...[
          if (widget.showCourseButton)
            _buildActionButton(
              context,
              icon: Icons.calendar_month_rounded,
              onPressed: () async {
                await PageTransitions.pushFromRect(
                  context: context,
                  page: WeeklyCourseScreen(username: widget.username),
                  sourceKey: widget.courseKey ?? GlobalKey(),
                );
              },
              buttonKey: widget.courseKey,
            ),
          searchBtn,
          syncBtn,
          teamsBtn,
          settingsBtn,
        ] else ...[
          // 🚀 手机端纵屏：2*2 矩阵排列，位置自定义：团队(TL), 设置(TR), 搜索(BL), 同步(BR)
          Padding(
            padding: const EdgeInsets.only(right: 12), // 移除 top: 4 以节省空间，防止溢出
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    teamsBtn, // 团队放在左上角
                    const SizedBox(width: 8),
                    settingsBtn, // 设置放在右上角
                  ],
                ),
                const SizedBox(height: 4), // 缩小行间距
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    searchBtn, // 搜索放在左下角
                    const SizedBox(width: 8),
                    syncBtn, // 同步放在右下角
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(width: 8),
      ],
    );
  }

}
