import 'package:flutter/material.dart';
import 'package:flutter_zoom_drawer/flutter_zoom_drawer.dart';
import 'package:package_info_plus/package_info_plus.dart';


class HomeDrawerMenu extends StatelessWidget {
  final String username;
  final String timeSalutation;
  final VoidCallback onSettings;
  final VoidCallback onAiAssistant;
  final VoidCallback onTeams;
  final VoidCallback onGuide;
  final VoidCallback onUpdate;
  final VoidCallback onTimeline;
  final VoidCallback onScreenTime;
  final VoidCallback onPlanCenter;
  final int teamPendingCount;
  final bool hasTeamConflictDot;

  const HomeDrawerMenu({
    super.key,
    required this.username,
    required this.timeSalutation,
    required this.onSettings,
    required this.onAiAssistant,
    required this.onTeams,
    required this.onGuide,
    required this.onUpdate,
    required this.onTimeline,
    required this.onScreenTime,
    required this.onPlanCenter,
    this.teamPendingCount = 0,
    this.hasTeamConflictDot = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: Theme.of(context).brightness == Brightness.dark
                ? [
                    const Color(0xFF1A1C1E),
                    Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                  ]
                : [
                    const Color(0xFFF8FAFC),
                    Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                  ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(left: 16.0, right: 12.0, top: 40.0, bottom: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar & Profile
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                    child: Text(
                      username.isNotEmpty ? username.substring(0, 1).toUpperCase() : '?',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          timeSalutation,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          username,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 48),

              // Menu Items
              _buildMenuItem(
                context,
                icon: Icons.people_rounded,
                title: '群组与团队',
                onTap: () {
                  ZoomDrawer.of(context)?.close();
                  onTeams();
                },
                badgeCount: teamPendingCount,
                showAlertDot: hasTeamConflictDot,
              ),
              _buildMenuItem(
                context,
                icon: Icons.smart_toy_outlined,
                title: 'AI 助手',
                onTap: () {
                  ZoomDrawer.of(context)?.close();
                  onAiAssistant();
                },
              ),
              _buildMenuItem(
                context,
                icon: Icons.timeline_rounded,
                title: '个人报告',
                onTap: () {
                  ZoomDrawer.of(context)?.close();
                  onTimeline();
                },
              ),
              _buildMenuItem(
                context,
                icon: Icons.pie_chart_rounded,
                title: '时间日志',
                onTap: () {
                  ZoomDrawer.of(context)?.close();
                  onScreenTime();
                },
              ),
              _buildMenuItem(
                context,
                icon: Icons.edit_calendar_rounded,
                title: '规划中心',
                onTap: () {
                  ZoomDrawer.of(context)?.close();
                  onPlanCenter();
                },
              ),
              const Spacer(),
              const Divider(height: 32),
              _buildMenuItem(
                context,
                icon: Icons.lightbulb_outline_rounded,
                title: '查看引导',
                onTap: () {
                  ZoomDrawer.of(context)?.close();
                  onGuide();
                },
              ),
              _buildMenuItem(
                context,
                icon: Icons.system_update_rounded,
                title: '检查更新',
                onTap: () {
                  ZoomDrawer.of(context)?.close();
                  onUpdate();
                },
              ),
              _buildMenuItem(
                context,
                icon: Icons.settings_rounded,
                title: '设置中心',
                onTap: () {
                  ZoomDrawer.of(context)?.close();
                  onSettings();
                },
              ),
              const SizedBox(height: 16),
              // Version Info
              FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(left: 16.0, bottom: 8.0),
                    child: Text(
                      'v${snapshot.data!.version}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    int badgeCount = 0,
    bool showAlertDot = false,
    bool isSyncing = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
          child: Row(
            children: [
              isSyncing 
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : Icon(icon, size: 28, color: Theme.of(context).iconTheme.color?.withValues(alpha: 0.8)),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (badgeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    badgeCount > 9 ? '9+' : badgeCount.toString(),
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                )
              else if (showAlertDot)
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
