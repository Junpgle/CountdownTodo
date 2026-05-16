import 'package:flutter/material.dart';
import '../services/medal_recommendation_service.dart';
import '../services/timeline_service.dart';
import 'package:intl/intl.dart';

/// 完整勋章墙页面
class MedalWallPage extends StatefulWidget {
  final MedalRecommendation recommendation;
  final List<MedalProgress> earnedThisSession; // 本阶段新获得
  final TimelineSummary summary;

  const MedalWallPage({
    super.key,
    required this.recommendation,
    required this.earnedThisSession,
    required this.summary,
  });

  @override
  State<MedalWallPage> createState() => _MedalWallPageState();
}

class _MedalWallPageState extends State<MedalWallPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _pageController = PageController();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          // Background Decorative Elements
          Positioned(
            top: -100,
            right: -100,
            child: _buildBackgroundCircle(
              colorScheme.primary.withValues(alpha: 0.15),
              300,
            ),
          ),
          Positioned(
            bottom: 100,
            left: -50,
            child: _buildBackgroundCircle(
              colorScheme.secondary.withValues(alpha: 0.1),
              200,
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                _buildHeader(context),
                _buildTabBar(context),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1200),
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          // Tab 0: 推荐
                          _buildMedalTab(
                            context,
                            widget.recommendation.topRecommendations,
                            isEmpty: widget
                                .recommendation.topRecommendations.isEmpty,
                            emptyMessage: '恭喜！已获得所有推荐勋章',
                            showFeatured: true,
                            isML: widget.recommendation.isML,
                            reasons: widget.recommendation.recommendReasons,
                          ),

                          // Tab 1: 本周新获
                          _buildMedalTab(
                            context,
                            widget.earnedThisSession,
                            isEmpty: widget.earnedThisSession.isEmpty,
                            emptyMessage: '本周还没有获得新勋章',
                          ),

                          // Tab 2: 已获得
                          _buildMedalTab(
                            context,
                            widget.recommendation.earnedMedals,
                            isEmpty: widget.recommendation.earnedMedals.isEmpty,
                            emptyMessage: '还没有获得任何勋章',
                          ),

                          // Tab 3: 未获得（按进度排序）
                          _buildMedalTab(
                            context,
                            widget.recommendation.allMedals
                                .where((m) => !m.earned)
                                .toList()
                              ..sort(
                                  (a, b) => b.progress.compareTo(a.progress)),
                            isEmpty: widget.recommendation.allMedals
                                .where((m) => !m.earned)
                                .isEmpty,
                            emptyMessage: '全部勋章已获得！',
                          ),

                          // Tab 4: 全部
                          _buildMedalTab(
                            context,
                            widget.recommendation.allMedals,
                            isEmpty: widget.recommendation.allMedals.isEmpty,
                            emptyMessage: '暂无勋章数据',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundCircle(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 600;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Padding(
          padding:
              EdgeInsets.fromLTRB(isWide ? 32 : 24, 16, isWide ? 32 : 24, 8),
          child: Row(
            children: [
              IconButton.filledTonal(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '勋章成就',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    Text(
                      '已获得 ${widget.recommendation.earnedMedals.length} / ${widget.recommendation.allMedals.length}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.workspace_premium,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16),
          ),
          child: TabBar(
            controller: _tabController,
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: theme.colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor:
                theme.colorScheme.onSurface.withValues(alpha: 0.6),
            labelStyle:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: [
              const Tab(text: '推荐'),
              Tab(text: '本周(${widget.earnedThisSession.length})'),
              const Tab(text: '已获'),
              const Tab(text: '未获'),
              const Tab(text: '全部'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMedalTab(
    BuildContext context,
    List<MedalProgress> medals, {
    bool isEmpty = false,
    String? emptyMessage,
    bool showFeatured = false,
    bool isML = false,
    Map<String, String> reasons = const {},
  }) {
    if (isEmpty) {
      return _buildEmptyState(context, emptyMessage);
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = _getResponsiveColumnCount(screenWidth);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        if (showFeatured && medals.isNotEmpty)
          SliverToBoxAdapter(
            child: _buildFeaturedMedal(context, medals.first,
                reason: reasons[medals.first.medal.id]),
          ),
        if (isML)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome,
                      size: 14, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(
                    'AI 智能推荐',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: 0.72,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                // If we showed featured, skip the first one in the grid
                final medalIndex = showFeatured ? index + 1 : index;
                if (medalIndex >= medals.length) return null;
                return _buildMedalCard(context, medals[medalIndex],
                    reason: reasons[medals[medalIndex].medal.id]);
              },
              childCount: showFeatured
                  ? (medals.length > 1 ? medals.length - 1 : 0)
                  : medals.length,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  int _getResponsiveColumnCount(double width) {
    if (width < 600) return 2;
    if (width < 900) return 3;
    if (width < 1200) return 4;
    return 5;
  }

  Widget _buildEmptyState(BuildContext context, String? message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.emoji_events_outlined,
              size: 80,
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            message ?? '暂无内容',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturedMedal(BuildContext context, MedalProgress medal,
      {String? reason}) {
    final theme = Theme.of(context);
    final isWide = MediaQuery.of(context).size.width > 600;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            medal.medal.color.withValues(alpha: 0.2),
            medal.medal.color.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: medal.medal.color.withValues(alpha: 0.2),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: isWide ? 100 : 80,
            height: isWide ? 100 : 80,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: medal.medal.color.withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: -5,
                ),
              ],
            ),
            child: Icon(
              medal.medal.icon,
              size: isWide ? 50 : 40,
              color: medal.medal.color,
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: medal.medal.color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '主推目标',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: medal.medal.color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  medal.medal.title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: isWide ? 24 : 20,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  medal.medal.description,
                  maxLines: isWide ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                if (reason != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.auto_awesome,
                          size: 12,
                          color: medal.medal.color.withValues(alpha: 0.7)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          reason,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: medal.medal.color.withValues(alpha: 0.7),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (isWide) const SizedBox(width: 24),
          IconButton.filledTonal(
            onPressed: () => _showMedalDetail(context, medal),
            style: IconButton.styleFrom(
              padding: const EdgeInsets.all(12),
            ),
            icon: const Icon(Icons.arrow_forward_ios, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildMedalCard(BuildContext context, MedalProgress medal,
      {String? reason}) {
    final theme = Theme.of(context);
    final earned = medal.earned;
    final progress = (medal.progress * 100).toInt();

    return GestureDetector(
      onTap: () => _showMedalDetail(context, medal),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              // Background glow for earned medals
              if (earned)
                Positioned(
                  top: -20,
                  right: -20,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: medal.medal.color.withValues(alpha: 0.1),
                    ),
                  ),
                ),

              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Spacer(),
                    // Icon Container
                    Hero(
                      tag: 'medal_${medal.medal.title}',
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: medal.medal.color
                                  .withValues(alpha: earned ? 0.15 : 0.05),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Icon(
                                medal.medal.icon,
                                size: 36,
                                color: earned
                                    ? medal.medal.color
                                    : theme.colorScheme.onSurface
                                        .withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                          if (earned && medal.earnedCount > 1)
                            Positioned(
                              right: -8,
                              bottom: -4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: medal.medal.color,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: Colors.white, width: 1.5),
                                ),
                                child: Text(
                                  'x${medal.earnedCount}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      medal.medal.title,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: earned
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurface
                                .withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 32, // Fixed height for 2 lines of bodySmall
                      child: reason != null
                          ? Column(
                              children: [
                                Text(
                                  medal.medal.description,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 10,
                                    height: 1.2,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: earned ? 0.6 : 0.3),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Expanded(
                                  child: Text(
                                    reason,
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 9,
                                      height: 1.2,
                                      color: medal.medal.color
                                          .withValues(alpha: 0.6),
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              medal.medal.description,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 10,
                                height: 1.2,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: earned ? 0.6 : 0.3),
                              ),
                            ),
                    ),
                    const Spacer(),
                    if (earned)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle,
                                size: 12, color: Colors.green),
                            SizedBox(width: 4),
                            Text(
                              '已获得',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: medal.progress,
                              minHeight: 6,
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHighest,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  medal.medal.color),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$progress%',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: medal.medal.color,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMedalDetail(BuildContext context, MedalProgress medal) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 600;

    Widget buildContent(bool embedded) {
      final padding = isWide ? 32.0 : 24.0;
      return SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(padding, embedded ? 0 : 24, padding, 32),
        child: Column(
          crossAxisAlignment:
              isWide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            // Top section: icon + title side by side on wide
            isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Hero(
                        tag: 'medal_${medal.medal.title}',
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: medal.medal.color.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: medal.medal.color.withValues(alpha: 0.2),
                                blurRadius: 30,
                                spreadRadius: -10,
                              ),
                            ],
                          ),
                          child: Icon(medal.medal.icon,
                              size: 52, color: medal.medal.color),
                        ),
                      ),
                      const SizedBox(width: 28),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              medal.medal.title,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color:
                                    medal.medal.color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                medal.medal.category,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: medal.medal.color,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      Hero(
                        tag: 'medal_${medal.medal.title}',
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: medal.medal.color.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: medal.medal.color.withValues(alpha: 0.2),
                                blurRadius: 30,
                                spreadRadius: -10,
                              ),
                            ],
                          ),
                          child: Icon(medal.medal.icon,
                              size: 64, color: medal.medal.color),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        medal.medal.title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: medal.medal.color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          medal.medal.category,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: medal.medal.color,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
            const SizedBox(height: 32),

            // Stats & Description in 2 columns on wide
            isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          children: [
                            if (medal.earned) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildStatItem(
                                      context,
                                      '首次获得',
                                      medal.firstEarnedAt != null
                                          ? DateFormat('yyyy-MM-dd')
                                              .format(medal.firstEarnedAt!)
                                          : '暂无数据',
                                      Icons.calendar_today_rounded,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildStatItem(
                                      context,
                                      '累计获得',
                                      '${medal.earnedCount} 次',
                                      Icons.history_rounded,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                            ],
                            _buildDetailSection(
                              context,
                              '勋章描述',
                              medal.medal.description,
                              Icons.info_outline,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: Column(
                          children: [
                            if (!medal.earned)
                              _buildProgressSection(context, medal)
                            else
                              _buildDetailSection(
                                context,
                                '成就状态',
                                '恭喜！您已在学习旅程中解锁了这项珍贵的荣誉。',
                                Icons.stars,
                                contentColor: Colors.green,
                              ),
                            const SizedBox(height: 16),
                            _buildDifficultySection(
                                context, medal.medal.priority),
                          ],
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      if (medal.earned) ...[
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatItem(
                                context,
                                '首次获得',
                                medal.firstEarnedAt != null
                                    ? DateFormat('yyyy-MM-dd')
                                        .format(medal.firstEarnedAt!)
                                    : '暂无数据',
                                Icons.calendar_today_rounded,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildStatItem(
                                context,
                                '累计获得',
                                '${medal.earnedCount} 次',
                                Icons.history_rounded,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                      _buildDetailSection(
                        context,
                        '勋章描述',
                        medal.medal.description,
                        Icons.info_outline,
                      ),
                      const SizedBox(height: 16),
                      if (!medal.earned)
                        _buildProgressSection(context, medal)
                      else
                        _buildDetailSection(
                          context,
                          '成就状态',
                          '恭喜！您已在学习旅程中解锁了这项珍贵的荣誉。',
                          Icons.stars,
                          contentColor: Colors.green,
                        ),
                      const SizedBox(height: 16),
                      _buildDifficultySection(context, medal.medal.priority),
                    ],
                  ),

            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('我知道了'),
              ),
            ),
          ],
        ),
      );
    }

    if (isWide) {
      showDialog(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black54,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680, maxHeight: 640),
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(32),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: -50,
                    right: -50,
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: medal.medal.color.withValues(alpha: 0.05),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 28, 0, 0),
                    child: buildContent(true),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Stack(
            children: [
              Positioned(
                top: -50,
                right: -50,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: medal.medal.color.withValues(alpha: 0.05),
                  ),
                ),
              ),
              Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(child: buildContent(false)),
                ],
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildDetailSection(
    BuildContext context,
    String title,
    String content,
    IconData icon, {
    Color? contentColor,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: contentColor ??
                  theme.colorScheme.onSurface.withValues(alpha: 0.7),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressSection(BuildContext context, MedalProgress medal) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: medal.medal.color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: medal.medal.color.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '解锁进度',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                '${(medal.progress * 100).toInt()}%',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: medal.medal.color,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: medal.progress,
              minHeight: 10,
              backgroundColor: medal.medal.color.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation<Color>(medal.medal.color),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            medal.nextMilestone,
            style: theme.textTheme.bodySmall?.copyWith(
              color: medal.medal.color.withValues(alpha: 0.8),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDifficultySection(BuildContext context, int priority) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '获取难度',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          Row(
            children: List.generate(
              5,
              (index) => Icon(
                Icons.star_rounded,
                size: 22,
                color: index < priority
                    ? Colors.amber
                    : theme.colorScheme.outlineVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
      BuildContext context, String label, String value, IconData icon) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
