import 'package:flutter/material.dart';
import 'quiz_screen.dart';
import 'other_screens.dart';
import 'settings_screen.dart';
import '../utils/page_transitions.dart';

class MathMenuScreen extends StatefulWidget {
  final String username;
  const MathMenuScreen({super.key, required this.username});

  @override
  State<MathMenuScreen> createState() => _MathMenuScreenState();
}

class _MathMenuScreenState extends State<MathMenuScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  final GlobalKey _quizCardKey = GlobalKey();
  final GlobalKey _settingsCardKey = GlobalKey();
  final GlobalKey _leaderboardCardKey = GlobalKey();
  final GlobalKey _historyCardKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("数学测验中心"),
        centerTitle: true,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // 断点判断：是否为平板/桌面端 (宽屏)
          final bool isTablet = constraints.maxWidth >= 600;
          final bool isWideScreen = constraints.maxWidth >= 800;

          // 宽屏时一行展示4个卡片，普通屏幕展示2个
          final int columns = isWideScreen ? 4 : 2;

          return Center(
            child: ConstrainedBox(
              // 限制全局最大宽度，防止在带鱼屏或 4K 显示器上过度拉伸
              constraints: const BoxConstraints(maxWidth: 1000),
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(isTablet ? 24.0 : 16.0),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          vertical: isTablet ? 32 : 20,
                          horizontal: isTablet ? 40 : 20,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [Colors.blueAccent, Colors.lightBlue]),
                          borderRadius:
                              BorderRadius.circular(isTablet ? 24 : 16),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.calculate,
                                size: isTablet ? 64 : 48, color: Colors.white),
                            SizedBox(height: isTablet ? 16 : 10),
                            Text(
                              "保持大脑活跃！",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: isTablet ? 26 : 20,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "每日坚持练习，提高计算速度",
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: isTablet ? 16 : 14),
                            )
                          ],
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.symmetric(
                        horizontal: isTablet ? 24.0 : 16.0),
                    sliver: SliverGrid.count(
                      crossAxisCount: columns,
                      crossAxisSpacing: isTablet ? 20 : 16,
                      mainAxisSpacing: isTablet ? 20 : 16,
                      childAspectRatio: isWideScreen ? 1.0 : 1.1,
                      children: [
                        _AnimatedMenuCard(
                          index: 0,
                          animationController: _animationController,
                          child: _MenuCard(
                            key: _quizCardKey,
                            title: "开始答题",
                            subtitle: "进入测验",
                            colorStart: const Color(0xFF4facfe),
                            colorEnd: const Color(0xFF00f2fe),
                            icon: Icons.play_arrow_rounded,
                            onTap: () => PageTransitions.pushFromRect(
                              context: context,
                              page: QuizScreen(username: widget.username),
                              sourceKey: _quizCardKey,
                            ),
                          ),
                        ),
                        _AnimatedMenuCard(
                          index: 1,
                          animationController: _animationController,
                          child: _MenuCard(
                            key: _settingsCardKey,
                            title: "题目设置",
                            subtitle: "调整难度",
                            colorStart: const Color(0xFF43e97b),
                            colorEnd: const Color(0xFF38f9d7),
                            icon: Icons.tune_rounded,
                            onTap: () => PageTransitions.pushFromRect(
                              context: context,
                              page: const SettingsScreen(),
                              sourceKey: _settingsCardKey,
                            ),
                          ),
                        ),
                        _AnimatedMenuCard(
                          index: 2,
                          animationController: _animationController,
                          child: _MenuCard(
                            key: _leaderboardCardKey,
                            title: "排行榜",
                            subtitle: "查看排名",
                            colorStart: const Color(0xFFfa709a),
                            colorEnd: const Color(0xFFfee140),
                            icon: Icons.emoji_events_rounded,
                            onTap: () => PageTransitions.pushFromRect(
                              context: context,
                              page: const LeaderboardScreen(),
                              sourceKey: _leaderboardCardKey,
                            ),
                          ),
                        ),
                        _AnimatedMenuCard(
                          index: 3,
                          animationController: _animationController,
                          child: _MenuCard(
                            key: _historyCardKey,
                            title: "历史记录",
                            subtitle: "过往成绩",
                            colorStart: const Color(0xFF667eea),
                            colorEnd: const Color(0xFF764ba2),
                            icon: Icons.history_edu_rounded,
                            onTap: () => PageTransitions.pushFromRect(
                              context: context,
                              page: HistoryScreen(username: widget.username),
                              sourceKey: _historyCardKey,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 底部留白，防止滚动到底部时贴边
                  const SliverToBoxAdapter(child: SizedBox(height: 40)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color colorStart;
  final Color colorEnd;
  final IconData icon;
  final VoidCallback onTap;

  const _MenuCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.colorStart,
    required this.colorEnd,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final bool isLargeCard = constraints.maxWidth > 180;

      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [colorStart, colorEnd]),
            ),
            child: Padding(
              padding: EdgeInsets.all(isLargeCard ? 20.0 : 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                      padding: EdgeInsets.all(isLargeCard ? 10 : 8),
                      decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(10)),
                      child: Icon(icon,
                          color: Colors.white, size: isLargeCard ? 32 : 28)),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontSize: isLargeCard ? 18 : 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                      const SizedBox(height: 4),
                      Text(subtitle,
                          style: TextStyle(
                              fontSize: isLargeCard ? 14 : 12,
                              color: Colors.white70)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _AnimatedMenuCard extends StatelessWidget {
  final int index;
  final AnimationController animationController;
  final Widget child;

  const _AnimatedMenuCard({
    required this.index,
    required this.animationController,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final delay = index * 0.15;
    return FutureBuilder<void>(
      future: Future.delayed(Duration(milliseconds: (delay * 1000).round())),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, 30 * (1 - value)),
              child: Opacity(
                opacity: value,
                child: child,
              ),
            );
          },
          child: child,
        );
      },
    );
  }
}
