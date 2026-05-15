import 'package:flutter/material.dart';
import '../services/medal_recommendation_service.dart';

/// 勋章推荐卡片 Widget
class MedalRecommendationCard extends StatelessWidget {
  final MedalRecommendation recommendation;
  final VoidCallback? onViewAll;

  const MedalRecommendationCard({
    Key? key,
    required this.recommendation,
    this.onViewAll,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.emoji_events_outlined,
                    color: Colors.amber, size: 24),
                const SizedBox(width: 12),
                Text(
                  '下一个目标',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                if (recommendation.isML) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome, size: 10, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 2),
                        Text(
                          'AI',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const Spacer(),
                if (recommendation.earnedMedals.isNotEmpty)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Text(
                      '已获得 ${recommendation.earnedMedals.length} 个',
                      style: TextStyle(
                        color: Colors.amber[700],
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Top 3 Recommendations
            if (recommendation.topRecommendations.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      Icon(Icons.celebration_outlined,
                          size: 48, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      Text(
                        '恭喜！已获得所有勋章',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Column(
                children: recommendation.topRecommendations
                    .asMap()
                    .entries
                    .map((entry) {
                  final index = entry.key;
                  final medal = entry.value;
                  return Padding(
                    padding: EdgeInsets.only(
                        bottom: index <
                                recommendation.topRecommendations.length - 1
                            ? 16
                            : 0),
                    child: _buildMedalProgressItem(context, medal, reason: recommendation.recommendReasons[medal.medal.id]),
                  );
                }).toList(),
              ),

            if (recommendation.topRecommendations.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // View All Button
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: onViewAll,
                  icon: const Icon(Icons.list_outlined),
                  label: Text(
                    '查看全部勋章 (${recommendation.allMedals.length})',
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.blue,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMedalProgressItem(
    BuildContext context,
    MedalProgress medal, {
    String? reason,
  }) {
    final percentage = (medal.progress * 100).toStringAsFixed(0);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[200]!),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Medal title and icon
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: medal.medal.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  medal.medal.icon,
                  color: medal.medal.color,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      medal.medal.title,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      medal.nextMilestone,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (reason != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        reason,
                        style: TextStyle(
                          color: medal.medal.color.withValues(alpha: 0.7),
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Progress bar
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: medal.progress,
                    minHeight: 6,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      medal.medal.color,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$percentage%',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 完整勋章列表对话框
class MedalListDialog extends StatefulWidget {
  final MedalRecommendation recommendation;

  const MedalListDialog({
    Key? key,
    required this.recommendation,
  }) : super(key: key);

  @override
  State<MedalListDialog> createState() => _MedalListDialogState();
}

class _MedalListDialogState extends State<MedalListDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '勋章系统',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Tab bar
          TabBar(
            controller: _tabController,
            tabs: [
              Tab(
                text:
                    '推荐 (${widget.recommendation.topRecommendations.length})',
              ),
              Tab(text: '已获得 (${widget.recommendation.earnedMedals.length})'),
              Tab(text: '全部 (${widget.recommendation.allMedals.length})'),
            ],
          ),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildMedalList(
                    context, widget.recommendation.topRecommendations),
                _buildMedalList(
                    context, widget.recommendation.earnedMedals),
                _buildMedalList(context, widget.recommendation.allMedals),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedalList(
    BuildContext context,
    List<MedalProgress> medals,
  ) {
    if (medals.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            '暂无勋章',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: medals.length,
      itemBuilder: (context, index) {
        final medal = medals[index];
        final percentage = (medal.progress * 100).toStringAsFixed(0);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title row
                Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: medal.medal.color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        medal.medal.icon,
                        color: medal.medal.color,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            medal.medal.title,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            medal.medal.description,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Progress bar
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
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
                          const SizedBox(height: 8),
                          Text(
                            medal.nextMilestone,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$percentage%',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (medal.earned)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.green[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: Text(
                                '已获得',
                                style: TextStyle(
                                  color: Colors.green[700],
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
