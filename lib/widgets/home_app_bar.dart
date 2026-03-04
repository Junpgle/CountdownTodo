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

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: isLight ? Colors.transparent : null,
      elevation: 0,
      toolbarHeight: 100,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text("$timeSalutation, $username",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isLight ? Colors.white : null)),
          const SizedBox(height: 4),
          Text(DateFormat('MM月dd日 EEEE', 'zh_CN').format(DateTime.now()),
              style: TextStyle(fontSize: 14, color: isLight ? Colors.white.withOpacity(0.9) : Colors.blueGrey)),
          const SizedBox(height: 2),
          Text(currentGreeting,
              style: TextStyle(fontSize: 12, color: isLight ? Colors.white.withOpacity(0.8) : Colors.grey)),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.calendar_month, color: isLight ? Colors.white : null),
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => WeeklyCourseScreen(username: username)));
          },
        ),
        IconButton(
            icon: isSyncing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(Icons.cloud_sync, color: isLight ? Colors.white : null),
            onPressed: onSync
        ),
        IconButton(
            icon: Icon(Icons.settings, color: isLight ? Colors.white : null),
            onPressed: onSettings
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(100);
}