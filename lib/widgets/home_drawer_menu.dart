import 'dart:ui';
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Background solid color
          Container(
            color: isDark ? const Color(0xFF121418) : const Color(0xFFF0F4F8),
          ),
          // Glow Orb 1 (Top Left)
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    colorScheme.primary.withValues(alpha: isDark ? 0.3 : 0.2),
                    Colors.transparent,
                  ],
                  stops: const [0.2, 1.0],
                ),
              ),
            ),
          ),
          // Glow Orb 2 (Bottom Rightish)
          Positioned(
            bottom: -50,
            left: 100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    colorScheme.secondary.withValues(alpha: isDark ? 0.25 : 0.15),
                    Colors.transparent,
                  ],
                  stops: const [0.2, 1.0],
                ),
              ),
            ),
          ),
          // Backdrop Filter for Frosted Glass effect
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                color: Colors.transparent,
              ),
            ),
          ),

          // Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(left: 20.0, right: 16.0, top: 40.0, bottom: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar & Profile
                  Row(
                    children: [
                      // Avatar with border glow
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.primary.withValues(alpha: 0.2),
                              blurRadius: 15,
                              spreadRadius: 2,
                            )
                          ],
                          border: Border.all(
                            color: colorScheme.primary.withValues(alpha: 0.3),
                            width: 2,
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 28,
                          backgroundColor: isDark 
                              ? colorScheme.surfaceContainerHighest
                              : colorScheme.surface,
                          child: Text(
                            username.isNotEmpty ? username.substring(0, 1).toUpperCase() : '?',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Greeting Pill Badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: colorScheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: colorScheme.primary.withValues(alpha: 0.2),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                timeSalutation,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              username,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Features Group
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),
                  
                  // Utilities Group (Frosted Card)
                  Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surface.withValues(alpha: isDark ? 0.3 : 0.5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: colorScheme.onSurface.withValues(alpha: 0.05),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        _buildMenuItem(
                          context,
                          icon: Icons.lightbulb_outline_rounded,
                          title: '查看引导',
                          onTap: () {
                            ZoomDrawer.of(context)?.close();
                            onGuide();
                          },
                          isCompact: true,
                        ),
                        _buildMenuItem(
                          context,
                          icon: Icons.system_update_rounded,
                          title: '检查更新',
                          onTap: () {
                            ZoomDrawer.of(context)?.close();
                            onUpdate();
                          },
                          isCompact: true,
                        ),
                        _buildMenuItem(
                          context,
                          icon: Icons.settings_rounded,
                          title: '设置中心',
                          onTap: () {
                            ZoomDrawer.of(context)?.close();
                            onSettings();
                          },
                          isCompact: true,
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // Version Info Badge
                  FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const SizedBox();
                      return Padding(
                        padding: const EdgeInsets.only(left: 8.0, top: 8.0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: colorScheme.onSurface.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'v${snapshot.data!.version}',
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurface.withValues(alpha: 0.5),
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
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
    bool isCompact = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Padding(
      padding: EdgeInsets.symmetric(vertical: isCompact ? 2.0 : 4.0, horizontal: 8.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          splashColor: colorScheme.primary.withValues(alpha: 0.1),
          highlightColor: colorScheme.primary.withValues(alpha: 0.05),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: isCompact ? 10.0 : 12.0, horizontal: 12.0),
            child: Row(
              children: [
                // Icon inside a rounded squircle
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon, 
                    size: isCompact ? 20 : 24, 
                    color: colorScheme.primary.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(width: 16),
                
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: isCompact ? 15 : 16,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).textTheme.bodyLarge?.color?.withValues(alpha: 0.9),
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
                  )
                else
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: Theme.of(context).iconTheme.color?.withValues(alpha: 0.3),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
