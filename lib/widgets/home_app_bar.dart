import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../screens/course_screens.dart';
import '../screens/home_settings_screen.dart';

class HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String username;
  final String timeSalutation;
  final String currentGreeting;
  final bool isLight;
  final bool isSyncing;
  final VoidCallback onSync;
  final VoidCallback onSettings;

  const HomeAppBar({
    super.key,
    required this.username,
    required this.timeSalutation,
    required this.currentGreeting,
    required this.isLight,
    required this.isSyncing,
    required this.onSync,
    required this.onSettings,
  });

  Widget _buildActionButton(BuildContext context, {required IconData icon, required VoidCallback onPressed, bool isLoading = false}) {
    return Container(
      margin: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: isLight ? Colors.white.withOpacity(0.15) : Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: isLoading
            ? SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: isLight ? Colors.white : Theme.of(context).colorScheme.primary,
          ),
        )
            : Icon(icon, color: isLight ? Colors.white : Theme.of(context).colorScheme.onSurface),
        onPressed: onPressed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // determine orientation and pick compact sizes in landscape
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final toolbarH = isLandscape ? 64.0 : 100.0;
    final titleSize = isLandscape ? 18.0 : 22.0;
    final dateSize = isLandscape ? 12.0 : 13.0;
    final greetingSize = isLandscape ? 11.0 : 12.0;
    return AppBar(
      backgroundColor: isLight ? Colors.transparent : null,
      elevation: 0,
      toolbarHeight: toolbarH,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "$timeSalutation, $username",
            style: TextStyle(
              fontSize: titleSize,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              color: isLight ? Colors.white : null,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('MM月dd日 EEEE', 'zh_CN').format(DateTime.now()),
            style: TextStyle(
              fontSize: dateSize,
              fontWeight: FontWeight.w500,
              color: isLight ? Colors.white.withOpacity(0.9) : Colors.blueGrey,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            currentGreeting,
            style: TextStyle(
              fontSize: greetingSize,
              color: isLight ? Colors.white.withOpacity(0.7) : Colors.grey,
            ),
          ),
        ],
      ),
      actions: [
        _buildActionButton(
          context,
          icon: Icons.calendar_month_rounded,
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => WeeklyCourseScreen(username: username)));
          },
        ),
        _buildActionButton(
          context,
          icon: Icons.cloud_sync_rounded,
          isLoading: isSyncing,
          onPressed: onSync,
        ),
        _buildActionButton(
          context,
          icon: Icons.settings_rounded,
          onPressed: onSettings,
        ),
        const SizedBox(width: 8), // 右侧额外留白
      ],
    );
  }

  @override
  Size get preferredSize {
    // preferredSize doesn't get BuildContext, so use window metrics to approximate orientation
    final window = WidgetsBinding.instance.window;
    final dpr = window.devicePixelRatio;
    final logical = window.physicalSize / dpr;
    final landscape = logical.width > logical.height;
    return Size.fromHeight(landscape ? 64.0 : 100.0);
  }
}