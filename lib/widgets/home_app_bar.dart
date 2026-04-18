import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../screens/course_screens.dart';
import '../screens/home_settings_screen.dart';
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
        widget.isLight ? Colors.white.withOpacity(0.3) : Colors.grey[800]!;
    final highlightColor =
        widget.isLight ? Colors.white.withOpacity(0.6) : Colors.grey[700]!;

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

class HomeAppBar extends StatefulWidget {
  final String username;
  final String timeSalutation;
  final String currentGreeting;
  final bool isLight;
  final bool isSyncing;
  final VoidCallback onSync;
  final VoidCallback onSettings;
  final GlobalKey? settingsKey;
  final GlobalKey? courseKey;

  const HomeAppBar({
    super.key,
    required this.username,
    required this.timeSalutation,
    required this.currentGreeting,
    required this.isLight,
    required this.isSyncing,
    required this.onSync,
    required this.onSettings,
    this.settingsKey,
    this.courseKey,
    this.showCourseButton = true,
  });

  final bool showCourseButton;

  @override
  State<HomeAppBar> createState() => _HomeAppBarState();
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
      Key? buttonKey}) {
    return Container(
      key: buttonKey,
      margin: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: widget.isLight
            ? Colors.white.withOpacity(0.15)
            : Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: isLoading
            ? RotationTransition(
                turns: _syncRotationController,
                child: Icon(icon,
                    color: widget.isLight
                        ? Colors.white
                        : Theme.of(context).colorScheme.primary),
              )
            : Icon(icon,
                color: widget.isLight
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface),
        onPressed: onPressed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final toolbarH = isLandscape ? 64.0 : 100.0;
    final titleSize = isLandscape ? 18.0 : 22.0;
    final dateSize = isLandscape ? 12.0 : 13.0;
    final greetingSize = isLandscape ? 11.0 : 12.0;
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
                  ? Colors.white.withOpacity(0.9)
                  : Colors.blueGrey,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            widget.currentGreeting,
            style: TextStyle(
              fontSize: greetingSize,
              color:
                  widget.isLight ? Colors.white.withOpacity(0.7) : Colors.grey,
            ),
          ),
        ],
      ),
      actions: [
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
        _buildActionButton(
          context,
          icon: Icons.cloud_sync_rounded,
          isLoading: widget.isSyncing,
          onPressed: widget.onSync,
        ),
        _buildActionButton(
          context,
          icon: Icons.people_rounded,
          onPressed: () => Navigator.pushNamed(context, '/teams'),
        ),
        _buildActionButton(
          context,
          icon: Icons.settings_rounded,
          onPressed: widget.onSettings,
          buttonKey: widget.settingsKey,
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  @override
  Size get preferredSize {
    final window = WidgetsBinding.instance.window;
    final dpr = window.devicePixelRatio;
    final logical = window.physicalSize / dpr;
    final landscape = logical.width > logical.height;
    return Size.fromHeight(landscape ? 64.0 : 100.0);
  }
}
