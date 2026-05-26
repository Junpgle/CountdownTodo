import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../storage_service.dart';

class HistoricalCountdownsScreen extends StatefulWidget {
  final String username;
  const HistoricalCountdownsScreen({super.key, required this.username});

  @override
  State<HistoricalCountdownsScreen> createState() =>
      _HistoricalCountdownsScreenState();
}

class _HistoricalCountdownsScreenState
    extends State<HistoricalCountdownsScreen> {
  List<CountdownItem> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final allCountdowns = await StorageService.getCountdowns(widget.username);
    setState(() {
      // 过滤出已过期的倒计时
      _history = allCountdowns.where((item) {
        return item.targetDate.difference(DateTime.now()).inDays + 1 < 0;
      }).toList();
      
      // 按照过期目标日降序排列（最近过期的排在最前面）
      _history.sort((a, b) => b.targetDate.compareTo(a.targetDate));
      _isLoading = false;
    });
  }

  Future<void> _deleteItem(CountdownItem item) async {
    await StorageService.permanentlyDeleteCountdown(widget.username, item.id);
    _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.check_circle_outline, color: Colors.white),
              SizedBox(width: 8),
              Text('已从记忆博物馆彻底删除该历史记录'),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context, CountdownItem item) async {
    final colorScheme = Theme.of(context).colorScheme;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: colorScheme.error,
              ),
              const SizedBox(width: 10),
              const Text(
                "彻底删除",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "确定要彻底删除该倒计时历史记录吗？删除后将不可恢复。",
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.errorContainer.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  item.title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            TextButton(
              child: Text(
                "取消",
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                "确认删除",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      _deleteItem(item);
    }
  }

  Widget _buildStatsPanel(BuildContext context, bool isTablet) {
    final oldestItem = _history.isNotEmpty ? _history.last : null;
    final oldestDays = oldestItem != null
        ? (oldestItem.targetDate.difference(DateTime.now()).inDays + 1).abs()
        : 0;

    return Padding(
      padding: EdgeInsets.all(isTablet ? 24.0 : 16.0),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primaryContainer,
              Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: EdgeInsets.all(isTablet ? 24 : 20),
        child: isTablet
            ? Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem(
                    context,
                    "已封存时光",
                    "${_history.length}",
                    "个倒计时",
                    Icons.folder_special_rounded,
                  ),
                  Container(
                    width: 1,
                    height: 60,
                    color: Theme.of(context)
                        .colorScheme
                        .onPrimaryContainer
                        .withValues(alpha: 0.2),
                  ),
                  _buildStatItem(
                    context,
                    "最久远记忆",
                    "$oldestDays",
                    "天前 · ${oldestItem?.title ?? '无'}",
                    Icons.history_toggle_off_rounded,
                  ),
                ],
              )
            : Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: _buildStatItem(
                          context,
                          "已封存时光",
                          "${_history.length}",
                          "个倒计时",
                          Icons.folder_special_rounded,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildStatItem(
                          context,
                          "最久远记忆",
                          "$oldestDays",
                          "天前",
                          Icons.history_toggle_off_rounded,
                        ),
                      ),
                    ],
                  ),
                  if (oldestItem != null) ...[
                    const SizedBox(height: 12),
                    Divider(
                      color: Theme.of(context)
                          .colorScheme
                          .onPrimaryContainer
                          .withValues(alpha: 0.1),
                      height: 1,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.auto_stories_outlined,
                          size: 14,
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer
                              .withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            "时光寄语: ${oldestItem.title}",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer
                                  .withValues(alpha: 0.8),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    String label,
    String value,
    String unit,
    IconData icon,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.35),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context)
                    .colorScheme
                    .onPrimaryContainer
                    .withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onPrimaryContainer
                        .withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHistoryCard(BuildContext context, CountdownItem item) {
    final diff = (item.targetDate.difference(DateTime.now()).inDays + 1).abs();
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // 提供点击反馈，展现更立体的交互感
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 左侧：圆形渐变微章，高对比展示过期时间
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colorScheme.errorContainer,
                      colorScheme.tertiaryContainer.withValues(alpha: 0.8),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "$diff",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: colorScheme.onErrorContainer,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      "天前",
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onErrorContainer.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),

              // 中间：倒计时标题与目标日
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today_rounded,
                          size: 12,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "目标日: ${DateFormat('yyyy-MM-dd').format(item.targetDate)}",
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // 右侧：优雅的删除图标按钮
              IconButton(
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: colorScheme.error.withValues(alpha: 0.8),
                  size: 22,
                ),
                onPressed: () => _confirmDelete(context, item),
                style: IconButton.styleFrom(
                  hoverColor: colorScheme.errorContainer.withValues(alpha: 0.1),
                  highlightColor: colorScheme.errorContainer.withValues(alpha: 0.2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.8, end: 1.0),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Opacity(
            opacity: ((value - 0.8) / 0.2).clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 64.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.hourglass_empty_rounded,
                  size: 72,
                  color: colorScheme.primary.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                "记忆博物馆空空如也",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "这里是记忆的博物馆，当倒计时结束时，它们将在此安息。",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('历史倒计时'),
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final bool isTablet = constraints.maxWidth >= 600;
                final bool isDesktop = constraints.maxWidth >= 1000;
                
                // 根据屏幕宽度确定排版列数
                final int crossAxisCount = isDesktop ? 3 : (isTablet ? 2 : 1);

                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: _history.isEmpty
                        ? _buildEmptyState(context)
                        : CustomScrollView(
                            physics: const BouncingScrollPhysics(),
                            slivers: [
                              // 顶部的统计数据分析看板
                              SliverToBoxAdapter(
                                child: _buildStatsPanel(context, isTablet),
                              ),

                              // 卡片列表部分
                              SliverPadding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: isTablet ? 24 : 16,
                                  vertical: 8,
                                ),
                                sliver: crossAxisCount > 1
                                    ? SliverGrid(
                                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: crossAxisCount,
                                          mainAxisSpacing: 16,
                                          crossAxisSpacing: 16,
                                          childAspectRatio: isDesktop ? 2.5 : 2.25,
                                        ),
                                        delegate: SliverChildBuilderDelegate(
                                          (context, index) =>
                                              _buildHistoryCard(context, _history[index]),
                                          childCount: _history.length,
                                        ),
                                      )
                                    : SliverList(
                                        delegate: SliverChildBuilderDelegate(
                                          (context, index) => Padding(
                                            padding: const EdgeInsets.only(bottom: 12),
                                            child: _buildHistoryCard(
                                                context, _history[index]),
                                          ),
                                          childCount: _history.length,
                                        ),
                                      ),
                              ),

                              // 底部留白以优化滑动体验
                              const SliverToBoxAdapter(
                                child: SizedBox(height: 40),
                              ),
                            ],
                          ),
                  ),
                );
              },
            ),
    );
  }
}

