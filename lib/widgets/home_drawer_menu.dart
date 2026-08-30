import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_zoom_drawer/flutter_zoom_drawer.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/sidebar_menu_service.dart';
import '../update_service.dart';
import 'optional_liquid_glass_surface.dart';
import 'platform_backdrop_filter.dart';

const double _homeWideDrawerMaxWidth = 360.0;

/// Returns the horizontal space reserved for the home drawer when it opens.
///
/// Phones keep the existing proportional drawer, while wide layouts use a
/// compact proportional width with a desktop-friendly maximum. Keeping this
/// calculation outside the dashboard makes the width constraint easy to
/// verify without building the whole home screen.
double homeDrawerSlideWidthFor({
  required double screenWidth,
  required bool isWide,
}) {
  if (!isWide) return screenWidth * 0.72;

  final proportionalWidth = screenWidth * 0.4;
  return proportionalWidth < _homeWideDrawerMaxWidth
      ? proportionalWidth
      : _homeWideDrawerMaxWidth;
}

DateTime? _parseRegistrationDate(dynamic raw) {
  if (raw is num) {
    final value = raw.toInt();
    final milliseconds = value.abs() < 100000000000 ? value * 1000 : value;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true)
        .toLocal();
  }
  if (raw is! String || raw.trim().isEmpty) return null;

  final value = raw.trim();
  final numeric = num.tryParse(value);
  if (numeric != null) return _parseRegistrationDate(numeric);

  final hasTimezone =
      value.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(value);
  final normalized = value.replaceFirst(' ', 'T');
  final parseValue = hasTimezone
      ? normalized
      : normalized.padRight(normalized.length + 1, 'Z');
  return DateTime.tryParse(parseValue)?.toLocal();
}

Future<int?> _loadCompanionDays() async {
  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getInt('current_user_id') ?? ApiService.currentUserId;
  if (userId <= 0) return null;

  final status = await ApiService.fetchUserStatus(userId);
  final registeredAt = _parseRegistrationDate(
    status?['created_at'] ?? status?['createdAt'],
  );
  if (registeredAt == null) return null;

  final registeredDay =
      DateTime(registeredAt.year, registeredAt.month, registeredAt.day);
  final today = DateTime.now();
  final todayDay = DateTime(today.year, today.month, today.day);
  final days = todayDay.difference(registeredDay).inDays + 1;
  return days > 0 ? days : 1;
}

class _VersionReleaseInfo {
  final String? date;
  final bool isInternalBuild;
  final bool hasUpdate;

  const _VersionReleaseInfo({
    this.date,
    this.isInternalBuild = false,
    this.hasUpdate = false,
  });
}

int _compareVersionNames(String left, String right) {
  final leftParts =
      left.split('.').map((part) => int.tryParse(part) ?? 0).toList();
  final rightParts =
      right.split('.').map((part) => int.tryParse(part) ?? 0).toList();
  final length = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (var index = 0; index < length; index++) {
    final leftPart = index < leftParts.length ? leftParts[index] : 0;
    final rightPart = index < rightParts.length ? rightParts[index] : 0;
    if (leftPart != rightPart) return leftPart.compareTo(rightPart);
  }
  return 0;
}

class HomeDrawerMenu extends StatefulWidget {
  final String username;
  final String timeSalutation;
  final VoidCallback onSettings;
  final VoidCallback onAiAssistant;
  final VoidCallback onTeams;
  final VoidCallback onFinance;
  final VoidCallback onChangelog;
  final VoidCallback onChallengeCenter;
  final VoidCallback onUpdate;
  final VoidCallback onOpenUpdateSettings;
  final VoidCallback onTimeline;
  final VoidCallback onJournal;
  final VoidCallback onScreenTime;
  final VoidCallback onPlanCenter;
  final VoidCallback onHabits;
  final int teamPendingCount;
  final bool hasTeamConflictDot;

  const HomeDrawerMenu({
    super.key,
    required this.username,
    required this.timeSalutation,
    required this.onSettings,
    required this.onAiAssistant,
    required this.onTeams,
    required this.onFinance,
    required this.onChangelog,
    required this.onChallengeCenter,
    required this.onUpdate,
    required this.onOpenUpdateSettings,
    required this.onTimeline,
    required this.onJournal,
    required this.onScreenTime,
    required this.onPlanCenter,
    required this.onHabits,
    this.teamPendingCount = 0,
    this.hasTeamConflictDot = false,
  });

  @override
  State<HomeDrawerMenu> createState() => _HomeDrawerMenuState();
}

class _HomeDrawerMenuState extends State<HomeDrawerMenu> {
  late final Future<PackageInfo> _packageInfoFuture;
  late final Future<int?> _companionDaysFuture;
  // 可为空以兼容热重载保留的旧 State；初始化完成前只显示版本号。
  Future<_VersionReleaseInfo>? _versionReleaseInfoFuture;
  List<String> _featureOrder = SidebarMenuService.defaultOrder(
    SidebarMenuTarget.features,
  );
  List<String> _utilityOrder = SidebarMenuService.defaultOrder(
    SidebarMenuTarget.utilities,
  );
  Map<String, bool> _menuVisibility = SidebarMenuService.defaultVisibility();

  Future<_VersionReleaseInfo> get _releaseInfoFuture =>
      _versionReleaseInfoFuture ??= _loadVersionReleaseInfo();

  @override
  void initState() {
    super.initState();
    _packageInfoFuture = PackageInfo.fromPlatform();
    _companionDaysFuture = _loadCompanionDays();
    _versionReleaseInfoFuture = _loadVersionReleaseInfo();
    SidebarMenuService.revision.addListener(_reloadMenuPreferences);
    _reloadMenuPreferences();
  }

  @override
  void dispose() {
    SidebarMenuService.revision.removeListener(_reloadMenuPreferences);
    super.dispose();
  }

  Future<void> _reloadMenuPreferences() async {
    final pair = await SidebarMenuService.loadPair();
    final visibility = await SidebarMenuService.loadVisibility();
    if (!mounted) return;
    setState(() {
      _featureOrder = pair.features;
      _utilityOrder = pair.utilities;
      _menuVisibility = visibility;
    });
  }

  bool _isMenuVisible(String key) => _menuVisibility[key] ?? true;

  Widget? _buildConfiguredMenuItem(BuildContext context, String key) {
    if (!_isMenuVisible(key)) return null;
    final definition = SidebarMenuService.definition(key);
    final VoidCallback? onTap = switch (key) {
      'teams' => widget.onTeams,
      'finance' => widget.onFinance,
      'aiAssistant' => widget.onAiAssistant,
      'timeline' => widget.onTimeline,
      'journal' => widget.onJournal,
      'screenTime' => widget.onScreenTime,
      'planCenter' => widget.onPlanCenter,
      'habits' => widget.onHabits,
      'challengeCenter' => widget.onChallengeCenter,
      'changelog' => widget.onChangelog,
      'update' => widget.onUpdate,
      _ => null,
    };
    if (onTap == null) return null;
    return _buildMenuItem(
      context,
      icon: definition.icon,
      title: definition.title,
      onTap: () {
        ZoomDrawer.of(context)?.close();
        onTap();
      },
      badgeCount: key == 'teams' ? widget.teamPendingCount : 0,
      showAlertDot: key == 'teams' && widget.hasTeamConflictDot,
      isCompact: true,
    );
  }

  Future<_VersionReleaseInfo> _loadVersionReleaseInfo() async {
    try {
      final packageInfo = await _packageInfoFuture;
      final manifest = await UpdateService.checkManifest(
        preferCache: true,
        refreshInBackground: true,
      );
      if (manifest == null) return const _VersionReleaseInfo();

      final currentVersion =
          packageInfo.version.trim().split('+').first.split('-').first;
      final latestVersion =
          manifest.versionName.trim().split('+').first.split('-').first;
      final hasUpdate = _compareVersionNames(latestVersion, currentVersion) > 0;
      for (final entry in manifest.changelogHistory) {
        final entryVersion =
            entry.versionName.trim().split('+').first.split('-').first;
        if (entryVersion == currentVersion) {
          return _VersionReleaseInfo(
            date: entry.date.isNotEmpty ? entry.date : null,
            hasUpdate: hasUpdate,
          );
        }
      }
      return _VersionReleaseInfo(
        isInternalBuild: true,
        hasUpdate: hasUpdate,
      );
    } catch (_) {
      // 清单不可用时无法判断版本是否为内部测试版，保留纯版本号显示。
      return const _VersionReleaseInfo();
    }
  }

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
                    colorScheme.secondary
                        .withValues(alpha: isDark ? 0.25 : 0.15),
                    Colors.transparent,
                  ],
                  stops: const [0.2, 1.0],
                ),
              ),
            ),
          ),
          // Backdrop Filter for Frosted Glass effect
          Positioned.fill(
            child: OptionalLiquidGlassPanel(
              borderRadius: 0,
              isDark: isDark,
              tint: Color.alphaBlend(
                colorScheme.primary.withValues(alpha: 0.06),
                colorScheme.surface,
              ).withValues(alpha: isDark ? 0.3 : 0.38),
              fallback: PlatformBackdropFilter(
                filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: Container(
                  color: Colors.transparent,
                ),
              ),
              child: const SizedBox.expand(),
            ),
          ),

          // Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(
                  left: 20.0, right: 16.0, top: 40.0, bottom: 24.0),
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
                            widget.username.isNotEmpty
                                ? widget.username.substring(0, 1).toUpperCase()
                                : '?',
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
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color:
                                    colorScheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: colorScheme.primary
                                      .withValues(alpha: 0.2),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                widget.timeSalutation,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.username,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            FutureBuilder<int?>(
                              future: _companionDaysFuture,
                              builder: (context, snapshot) {
                                final days = snapshot.data;
                                if (days == null) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    '已陪伴您${days.toString()}天',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colorScheme.onSurface
                                          .withValues(alpha: 0.55),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Menu groups share one scroll area. Users can move all
                  // feature entries into utilities without overflowing the
                  // fixed-height drawer on small screens.
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ..._featureOrder
                              .map((key) =>
                                  _buildConfiguredMenuItem(context, key))
                              .whereType<Widget>(),
                          const SizedBox(height: 12),
                          Container(
                            decoration: BoxDecoration(
                              color: colorScheme.surface
                                  .withValues(alpha: isDark ? 0.3 : 0.5),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: colorScheme.onSurface
                                    .withValues(alpha: 0.05),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              children: [
                                ..._utilityOrder
                                    .map((key) =>
                                        _buildConfiguredMenuItem(context, key))
                                    .whereType<Widget>(),
                                _buildMenuItem(
                                  context,
                                  icon: Icons.settings_rounded,
                                  title: '设置中心',
                                  onTap: () {
                                    ZoomDrawer.of(context)?.close();
                                    widget.onSettings();
                                  },
                                  isCompact: true,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Version Info Badge
                  FutureBuilder<PackageInfo>(
                    future: _packageInfoFuture,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const SizedBox();
                      return Padding(
                        padding: const EdgeInsets.only(left: 8.0, top: 8.0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color:
                                colorScheme.onSurface.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: FutureBuilder<_VersionReleaseInfo>(
                            future: _releaseInfoFuture,
                            builder: (context, dateSnapshot) {
                              final versionColor =
                                  colorScheme.onSurface.withValues(alpha: 0.5);
                              final versionStyle = TextStyle(
                                fontSize: 11,
                                color: versionColor,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                              );
                              final releaseInfo = dateSnapshot.data;
                              final updateLabel = releaseInfo == null
                                  ? null
                                  : releaseInfo.isInternalBuild
                                      ? '内部测试版'
                                      : releaseInfo.date;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('v${snapshot.data!.version}',
                                          style: versionStyle),
                                      if (updateLabel != null) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          width: 1,
                                          height: 12,
                                          color: versionColor,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          updateLabel,
                                          style: versionStyle.copyWith(
                                            fontWeight: FontWeight.normal,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (releaseInfo?.hasUpdate == true)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(6),
                                        onTap: () {
                                          ZoomDrawer.of(context)?.close();
                                          widget.onOpenUpdateSettings();
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 2, vertical: 2),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.new_releases_outlined,
                                                size: 14,
                                                color: colorScheme.primary,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                '发现新版本！',
                                                style: versionStyle.copyWith(
                                                  color: colorScheme.primary,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 0.2,
                                                ),
                                              ),
                                              Icon(
                                                Icons.chevron_right_rounded,
                                                size: 16,
                                                color: colorScheme.primary,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
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
      padding: EdgeInsets.symmetric(
          vertical: isCompact ? 0.0 : 2.0, horizontal: 8.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          splashColor: colorScheme.primary.withValues(alpha: 0.1),
          highlightColor: colorScheme.primary.withValues(alpha: 0.05),
          child: Padding(
            padding: EdgeInsets.symmetric(
                vertical: isCompact ? 8.0 : 10.0, horizontal: 12.0),
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
                      color: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.color
                          ?.withValues(alpha: 0.9),
                    ),
                  ),
                ),

                if (badgeCount > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      badgeCount > 9 ? '9+' : badgeCount.toString(),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
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
                    color: Theme.of(context)
                        .iconTheme
                        .color
                        ?.withValues(alpha: 0.3),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
