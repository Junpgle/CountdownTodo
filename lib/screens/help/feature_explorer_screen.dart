import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/finance/screens/ai_usage_cost_screen.dart';
import '../../features/finance/screens/finance_automation_screen.dart';
import '../../features/finance/screens/finance_bill_import_screen.dart';
import '../../features/finance/screens/finance_future_commitments_screen.dart';
import '../../features/finance/screens/finance_home_screen.dart';
import '../../features/habits/screens/habit_center_screen.dart';
import '../../features/journal/screens/journal_home_screen.dart';
import '../../features/journal/screens/journal_trash_screen.dart';
import '../../features/thirty_day_challenge/screens/challenge_center_screen.dart';
import '../../models/todo_create_save_result.dart';
import '../../services/feature_tip_service.dart';
import '../../services/onboarding_checklist_service.dart';
import '../../services/storage/app_settings_storage.dart';
import '../../storage_service.dart';
import '../../utils/app_dialogs.dart';
import '../../utils/app_platform.dart';
import '../../utils/countdown_todo_tutorial_links.dart';
import '../../utils/page_transitions.dart';
import '../../widgets/floating_glass_control.dart';
import '../../widgets/global_search_overlay.dart';
import '../../widgets/optional_liquid_glass_surface.dart';
import '../add_todo_screen.dart';
import '../ai_assistant_tutorial_screen.dart';
import '../animation_settings_page.dart';
import '../band_sync_screen.dart';
import '../conflict_inbox_screen.dart';
import '../course_calendar_adjustment_screen.dart';
import '../course_screens.dart';
import '../feature_guide_screen.dart';
import '../fixed_schedule_editor_screen.dart';
import '../folder_manage_screen.dart';
import '../historical_todos_screen.dart';
import '../home_settings_screen.dart';
import '../math_menu_screen.dart';
import '../personal_timeline_screen.dart';
import '../plan_block_stats_screen.dart';
import '../plan_weekly_availability_screen.dart';
import '../pomodoro_screen.dart';
import '../screen_time_detail_screen.dart';
import '../settings/batch_tag_page.dart';
import '../settings/calendar_sync_page.dart';
import '../settings/device_calendar_read_page.dart';
import '../settings/home_text_config_page.dart';
import '../settings/lan_sync_screen.dart';
import '../settings/notification_settings_page.dart';
import '../settings/pages/account_devices_page.dart';
import '../settings/pages/ai_assistant_settings_page.dart';
import '../settings/pages/auto_backup_page.dart';
import '../settings/pages/data_import_page.dart';
import '../settings/pages/mcp_introduction_page.dart';
import '../settings/pages/platform_specific_settings_page.dart';
import '../settings/pages/preference_settings_page.dart';
import '../settings/pages/recurrence_series_merge_page.dart';
import '../settings/pages/sidebar_menu_settings_page.dart';
import '../settings/pages/sync_health_page.dart';
import '../settings/wallpaper_settings_page.dart';
import '../team_management_screen.dart';
import '../time_log_screen.dart';
import '../todo_plan_screen.dart';
import '../unified_waterfall_screen.dart';
import '../../utils/time_utils.dart';

part 'feature_explorer/feature_explorer_catalog_schedule_focus.dart';
part 'feature_explorer/feature_explorer_catalog_growth.dart';
part 'feature_explorer/feature_explorer_catalog_ai_sync_tips.dart';
part 'feature_explorer/feature_explorer_widgets.dart';

enum FeatureExplorerCategory {
  all('全部', Icons.apps_rounded),
  recent('近期新增', Icons.new_releases_rounded),
  schedule('时间与日程', Icons.calendar_month_rounded),
  focus('专注与复盘', Icons.timer_rounded),
  growth('成长与生活', Icons.self_improvement_rounded),
  aiAndSync('AI 与多端', Icons.auto_awesome_rounded),
  hiddenTips('隐藏神技', Icons.lightbulb_rounded);

  final String label;
  final IconData icon;
  const FeatureExplorerCategory(this.label, this.icon);
}

class FeatureExplorerItem {
  final String id;
  final String title;
  final String subtitle;
  final String locationPath;
  final FeatureExplorerCategory category;
  final IconData icon;
  final String? badgeText;
  final bool isNew;
  final List<String> keywords;
  final List<String> steps;
  final String actionLabel;
  final String? tutorialLabel;
  final Uri? tutorialUri;
  final Widget Function(BuildContext context, String username)? pageBuilder;
  final Future<void> Function(BuildContext context, String username)?
  customAction;
  final bool markSeenOnLaunch;

  const FeatureExplorerItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.locationPath,
    required this.category,
    required this.icon,
    this.badgeText,
    this.isNew = false,
    this.keywords = const [],
    required this.steps,
    required this.actionLabel,
    this.tutorialLabel,
    this.tutorialUri,
    this.pageBuilder,
    this.customAction,
    this.markSeenOnLaunch = true,
  });
}

class FeatureExplorerScreen extends StatefulWidget {
  final String? username;
  final bool isEmbedded;
  final FeatureExplorerCategory initialCategory;

  const FeatureExplorerScreen({
    super.key,
    this.username,
    this.isEmbedded = false,
    this.initialCategory = FeatureExplorerCategory.all,
  });

  @override
  State<FeatureExplorerScreen> createState() => _FeatureExplorerScreenState();
}

class _FeatureExplorerScreenState extends State<FeatureExplorerScreen> {
  final TextEditingController _searchController = TextEditingController();
  late FeatureExplorerCategory _selectedCategory = widget.initialCategory;
  String _searchQuery = '';
  bool _onlyUnexplored = false;
  Set<String> _seenBadges = const {};

  @override
  void initState() {
    super.initState();
    _loadSeenBadges();
    FeatureTipService.revision.addListener(_loadSeenBadges);
    OnboardingChecklistService.markTaskCompleted(
      OnboardingChecklistService.taskExploreFeatureHub,
    );
  }

  @override
  void dispose() {
    FeatureTipService.revision.removeListener(_loadSeenBadges);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSeenBadges() async {
    final seen = await FeatureTipService.getSeenFeatureBadges();
    if (!mounted) return;
    setState(() {
      _seenBadges = seen;
    });
  }

  Future<String> _resolveUsername() async {
    final provided = widget.username?.trim();
    if (provided != null && provided.isNotEmpty) return provided;
    return await StorageService.getLoginSession() ?? 'default';
  }

  void _mutateState(VoidCallback fn) => setState(fn);

  List<FeatureExplorerItem> _buildCatalog() {
    return [
      ..._buildScheduleAndFocusCatalog(),
      ..._buildGrowthCatalog(),
      ..._buildAiSyncAndTipsCatalog(),
    ];
  }

  static final RegExp _whitespacePattern = RegExp(r'\s+');

  int _itemPriority(FeatureExplorerItem item) {
    final isExplored = _seenBadges.contains(item.id);
    if (item.isNew && !isExplored) {
      return 0; // 近期新增且用户未读：最高优先级置顶
    }
    if (!isExplored) {
      return 1; // 尚未体验的功能优先排在已体验功能之前
    }
    if (item.isNew) {
      return 2; // 近期新增（已体验）
    }
    return 3; // 其他已体验功能
  }

  List<FeatureExplorerItem> _filteredItems(List<FeatureExplorerItem> catalog) {
    final query = _searchQuery.trim().toLowerCase();
    final queryTerms = query.isEmpty
        ? const <String>[]
        : query
              .split(_whitespacePattern)
              .where((term) => term.isNotEmpty)
              .toList(growable: false);
    final indexed = <({int index, FeatureExplorerItem item})>[];
    for (var i = 0; i < catalog.length; i++) {
      final item = catalog[i];
      if (_onlyUnexplored && _seenBadges.contains(item.id)) {
        continue;
      }
      final bool matches;
      if (query.isEmpty) {
        if (_selectedCategory == FeatureExplorerCategory.all) {
          matches = true;
        } else if (_selectedCategory == FeatureExplorerCategory.recent) {
          matches = item.isNew;
        } else {
          matches = item.category == _selectedCategory;
        }
      } else {
        final haystack = [
          item.title,
          item.subtitle,
          item.locationPath,
          item.badgeText ?? '',
          ...item.keywords,
          ...item.steps,
        ].join(' ').toLowerCase();
        matches = queryTerms.every((term) => haystack.contains(term));
      }
      if (matches) {
        indexed.add((index: i, item: item));
      }
    }

    indexed.sort((a, b) {
      final priorityCompare = _itemPriority(a.item)
          .compareTo(_itemPriority(b.item));
      if (priorityCompare != 0) return priorityCompare;
      return a.index.compareTo(b.index);
    });

    return indexed.map((entry) => entry.item).toList();
  }

  Future<void> _launchFeature(FeatureExplorerItem item) async {
    if (item.markSeenOnLaunch) {
      await FeatureTipService.markFeatureBadgeSeen(item.id);
    }
    // Also mark corresponding onboarding task if applicable
    switch (item.id) {
      case 'todos_and_countdowns':
        await OnboardingChecklistService.markTaskCompleted(
          OnboardingChecklistService.taskCreateTodoOrCountdown,
        );
      case 'fixed_schedule_related_todo':
      case 'course_schedule_and_import':
        await OnboardingChecklistService.markTaskCompleted(
          OnboardingChecklistService.taskCourseOrSchedule,
        );
      case 'todo_plan_center':
      case 'habit_challenge_planning_linkage':
        await OnboardingChecklistService.markTaskCompleted(
          OnboardingChecklistService.taskPlanBlock,
        );
      case 'pomodoro_focus':
      case 'time_log_and_backfill':
      case 'time_log_schedule_overlay':
        await OnboardingChecklistService.markTaskCompleted(
          OnboardingChecklistService.taskPomodoroFocus,
        );
      case 'ai_assistant_and_tutorial':
      case 'tip_long_press_voice':
        await OnboardingChecklistService.markTaskCompleted(
          OnboardingChecklistService.taskAiOrQuickVoice,
        );
    }

    final username = await _resolveUsername();
    if (!mounted) return;
    if (item.customAction != null) {
      await item.customAction!(context, username);
      return;
    }
    if (item.pageBuilder != null) {
      final page = item.pageBuilder!(context, username);
      await Navigator.of(
        context,
        rootNavigator: true,
      ).push(PageTransitions.slideHorizontal(page));
    }
  }

  Future<void> _launchTutorial(FeatureExplorerItem item) async {
    final tutorialUri = item.tutorialUri;
    if (tutorialUri == null) return;

    try {
      final launched = await launchUrl(
        tutorialUri,
        mode: LaunchMode.externalApplication,
      );
      if (launched || !mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法打开教程链接，请稍后重试。')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('打开教程失败，请检查网络后重试。')));
    }
  }

  Future<void> _showItemDetailSheet(FeatureExplorerItem item) async {
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    await showAppModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      item.icon,
                      color: scheme.onPrimaryContainer,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                item.title,
                                style: Theme.of(sheetContext)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                            if (item.badgeText != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  item.badgeText!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: scheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.subtitle,
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.place_rounded,
                      size: 18,
                      color: scheme.onSecondaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '入口位置：${item.locationPath}',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '如何操作',
                style: Theme.of(sheetContext).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < item.steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item.steps[i],
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.45,
                            color: scheme.onSurface.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    _launchFeature(item);
                  },
                  icon: const Icon(Icons.rocket_launch_rounded, size: 18),
                  label: Text(item.actionLabel),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              if (item.tutorialUri != null) ...[
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _launchTutorial(item);
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(item.tutorialLabel ?? '查看高阶教程'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Color _categoryAccentColor(
    FeatureExplorerCategory category,
    ColorScheme scheme,
  ) {
    return switch (category) {
      FeatureExplorerCategory.all => scheme.primary,
      FeatureExplorerCategory.recent => scheme.primary,
      FeatureExplorerCategory.schedule => scheme.primary,
      FeatureExplorerCategory.focus => scheme.tertiary,
      FeatureExplorerCategory.growth => scheme.secondary,
      FeatureExplorerCategory.aiAndSync => scheme.primary,
      FeatureExplorerCategory.hiddenTips => scheme.tertiary,
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final catalog = _buildCatalog();
    final filtered = _filteredItems(catalog);
    final totalCount = catalog.length;
    final exploredCount = catalog
        .where((item) => _seenBadges.contains(item.id))
        .length;
    final remainingCount = totalCount - exploredCount;
    final unreadNewCount = catalog
        .where((item) => item.isNew && !_seenBadges.contains(item.id))
        .length;

    return Scaffold(
      extendBodyBehindAppBar: !widget.isEmbedded,
      appBar: widget.isEmbedded
          ? null
          : FloatingGlassAppBar(
              flexibleSpace: const FloatingGlassTopBarBackground(),
              title: const Text('功能探索百宝箱'),
              actions: [
                IconButton(
                  tooltip: '版本更新日志',
                  icon: const Icon(Icons.history_edu_rounded, size: 20),
                  onPressed: () {
                    Navigator.of(context, rootNavigator: true).push(
                      PageTransitions.slideHorizontal(
                        FeatureGuideScreen(
                          mode: FeatureGuideMode.changelog,
                          loggedInUser: widget.username,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
      body: floatingGlassSettingsBody(
        context,
        standalone: !widget.isEmbedded,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            widget.isEmbedded
                ? 16
                : floatingGlassSettingsContentTopInset(context, extra: 12),
            16,
            32,
          ),
          children: [
            _buildTopControlCard(
              scheme: scheme,
              catalog: catalog,
              totalCount: totalCount,
              exploredCount: exploredCount,
              remainingCount: remainingCount,
              unreadNewCount: unreadNewCount,
            ),
            const SizedBox(height: 16),
            if (filtered.isEmpty)
              _buildEmptyState(scheme)
            else
              ..._buildFeatureListWidgets(filtered, scheme),
          ],
        ),
      ),
    );
  }

  /// 顶部探索进度与控制面板：清晰展示「已体验多少个、还差多少个」+ 搜索 + 分类筛选
}

abstract final class DeviceCalendarReadServicePlaceholder {
  static bool get isSupportedPlatform =>
      !kIsWeb && (AppPlatform.isAndroid || AppPlatform.isIOS);
}
