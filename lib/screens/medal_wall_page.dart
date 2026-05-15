import 'package:flutter/material.dart';
import '../services/medal_recommendation_service.dart';
import '../services/timeline_service.dart';

/// 完整勋章墙页面
class MedalWallPage extends StatefulWidget {
  final MedalRecommendation recommendation;
  final List<MedalProgress> earnedThisSession; // 本阶段新获得
  final TimelineSummary summary;

  const MedalWallPage({
    Key? key,
    required this.recommendation,
    required this.earnedThisSession,
    required this.summary,
  }) : super(key: key);

  @override
  State<MedalWallPage> createState() => _MedalWallPageState();
}

class _MedalWallPageState extends State<MedalWallPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late PageController _pageController;
  int _currentTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _pageController = PageController();
    _tabController.addListener(() {
      setState(() => _currentTabIndex = _tabController.index);
    });
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('勋章系统'),
        elevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: TabBar(
            controller: _tabController,
            isScrollable: false,
            tabs: [
              Tab(
                text:
                    '推荐 (${widget.recommendation.topRecommendations.length})',
              ),
              Tab(text: '本周新获 (${widget.earnedThisSession.length})'),
              Tab(
                text:
                    '已获得 (${widget.recommendation.earnedMedals.length})',
              ),
              Tab(text: '全部 (${widget.recommendation.allMedals.length})'),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 0: 推荐
          _buildMedalTab(
            context,
            widget.recommendation.topRecommendations,
            isEmpty:
                widget.recommendation.topRecommendations.isEmpty,
            emptyMessage: '恭喜！已获得所有推荐勋章',
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

          // Tab 3: 全部
          _buildMedalTab(
            context,
            widget.recommendation.allMedals,
          ),
        ],
      ),
    );
  }

  Widget _buildMedalTab(
    BuildContext context,
    List<MedalProgress> medals, {
    bool isEmpty = false,
    String? emptyMessage,
  }) {
    if (isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.emoji_events_outlined,
                size: 64,
                color: Colors.grey[300],
              ),
              const SizedBox(height: 16),
              Text(
                emptyMessage ?? '暂无内容',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: medals.length,
      itemBuilder: (context, index) {
        final medal = medals[index];
        return _buildMedalCard(context, medal);
      },
    );
  }

  Widget _buildMedalCard(BuildContext context, MedalProgress medal) {
    final earned = medal.earned;
    final progress = (medal.progress * 100).toStringAsFixed(0);

    return GestureDetector(
      onTap: () => _showMedalDetail(context, medal),
      child: Card(
        elevation: earned ? 4 : 1,
        shadowColor: medal.medal.color.withValues(alpha: 0.3),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: earned
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      medal.medal.color.withValues(alpha: 0.15),
                      medal.medal.color.withValues(alpha: 0.05),
                    ],
                  )
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Medal Icon
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: medal.medal.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        medal.medal.icon,
                        size: 40,
                        color: medal.medal.color,
                      ),
                      if (earned)
                        Positioned(
                          bottom: -5,
                          right: -5,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.check,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Medal Title
                Text(
                  medal.medal.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),

                // Progress or Status
                if (!earned)
                  Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: medal.progress,
                          minHeight: 4,
                          backgroundColor: Colors.grey[200],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            medal.medal.color,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$progress%',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: medal.medal.color,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '已获得',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.green[700],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMedalDetail(BuildContext context, MedalProgress medal) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: medal.medal.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        medal.medal.icon,
                        size: 48,
                        color: medal.medal.color,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            medal.medal.title,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            decoration: BoxDecoration(
                              color: medal.medal.color.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: Text(
                              medal.medal.category,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: medal.medal.color,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Description
                Text(
                  '描述',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  medal.medal.description,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),

                // Progress
                if (!medal.earned) ...[
                  Text(
                    '进度',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: medal.progress,
                            minHeight: 8,
                            backgroundColor: Colors.grey[200],
                            valueColor: AlwaysStoppedAnimation<Color>(
                              medal.medal.color,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '${(medal.progress * 100).toStringAsFixed(0)}%',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              color: medal.medal.color,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: medal.medal.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      medal.nextMilestone,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: medal.medal.color,
                      ),
                    ),
                  ),
                ] else ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: Colors.green[700],
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '已获得此勋章',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: Colors.green[700],
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),

                // Priority Info
                Text(
                  '难度等级',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: List.generate(
                    5,
                    (index) => Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.star,
                        size: 20,
                        color: index < medal.medal.priority
                            ? Colors.amber
                            : Colors.grey[300],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
