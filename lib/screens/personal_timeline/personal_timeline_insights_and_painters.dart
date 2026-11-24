part of '../personal_timeline_screen.dart';

extension _PersonalTimelineInsightsExt on _PersonalTimelineScreenState {
  Widget _buildOverviewInsightPanels(ColorScheme cs, bool isWide) {
    final panels = [
      _buildMasonryInsightPanel(
        '质量雷达',
        Icons.shield_outlined,
        cs,
        _buildQualitySnapshot(cs, fillHeight: isWide),
        fillHeight: isWide,
      ),
      _buildMasonryInsightPanel(
        '屏幕投入',
        Icons.devices_other_rounded,
        cs,
        _buildScreenSnapshot(cs, fillHeight: isWide),
        fillHeight: isWide,
      ),
      _buildMasonryInsightPanel(
        '产出节拍',
        Icons.query_stats_rounded,
        cs,
        _buildHourlyRhythm(cs),
        fillHeight: isWide,
      ),
    ];

    if (!isWide) {
      return Padding(
        padding: const EdgeInsets.only(top: 28),
        child: Column(
          children: [
            for (int i = 0; i < panels.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: i == panels.length - 1 ? 0 : 16,
                ),
                child: panels[i],
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: SizedBox(
        height: 286,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < panels.length; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: i == 0 ? 0 : 6,
                    right: i == panels.length - 1 ? 0 : 6,
                  ),
                  child: panels[i],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMasonryInsightPanel(
    String title,
    IconData icon,
    ColorScheme cs,
    Widget child, {
    bool fillHeight = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(title, icon, cs),
        const SizedBox(height: 12),
        if (fillHeight) Expanded(child: child) else child,
      ],
    );
  }

  Widget _buildSideHighlights(ColorScheme cs) {
    if (_summary == null) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('学习图谱', Icons.auto_awesome_mosaic_rounded, cs),
        const SizedBox(height: 20),
        _buildSubjectDonutChart(cs),
      ],
    );
  }

  Widget _buildQualitySnapshot(ColorScheme cs, {bool fillHeight = false}) {
    final summary = _summary!;
    final focusSessionCount = _pomodoroCount + _timeLogCount;
    final deepRatio = focusSessionCount > 0
        ? summary.deepWorkCount / focusSessionCount
        : 0.0;
    return OptionalLiquidGlassCard(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      borderRadius: 28,
      highContrast: true,
      fallbackDecoration: BoxDecoration(
        color: cs.surfaceContainerLow.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisAlignment: fillHeight
            ? MainAxisAlignment.spaceBetween
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRankItem(
            0,
            '平均投入时长',
            '${summary.avgPomodoroMinutes.toStringAsFixed(0)}分钟',
            cs,
          ),
          _buildRankItem(0, '深度专注占比', _formatPercent(deepRatio), cs),
          _buildRankItem(
            0,
            '中断率',
            _formatPercent(summary.interruptionRate),
            cs,
          ),
          _buildRankItem(
            0,
            '最长单段投入',
            '${summary.longestPomodoroMinutes}分钟',
            cs,
          ),
          if (_planBlockCount > 0)
            _buildRankItem(
              0,
              '规划达成率',
              _formatPercent(
                _plannedMinutes > 0
                    ? _planActualSeconds / (_plannedMinutes * 60)
                    : 0,
              ),
              cs,
            ),
          const SizedBox(height: 10),
          Text(
            summary.interruptionRate <= 0.15
                ? '你不是在频繁切换，而是真的沉下来了。'
                : '本阶段中断偏多，适合把高难任务放进黄金时段。',
            style: TextStyle(
              fontSize: 11,
              height: 1.45,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScreenSnapshot(ColorScheme cs, {bool fillHeight = false}) {
    if (_screenTimeSeconds <= 0) {
      return OptionalLiquidGlassCard(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        borderRadius: 28,
        highContrast: true,
        fallbackDecoration: BoxDecoration(
          color: cs.surfaceContainerLow.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Text(
          '暂无屏幕使用数据',
          style: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
        ),
      );
    }

    return OptionalLiquidGlassCard(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      borderRadius: 28,
      highContrast: true,
      fallbackDecoration: BoxDecoration(
        color: cs.surfaceContainerLow.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisAlignment: fillHeight
            ? MainAxisAlignment.spaceBetween
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRankItem(
            0,
            '屏幕总时长',
            _formatSecondsCompact(_screenTimeSeconds),
            cs,
          ),
          _buildRankItem(
            0,
            '专注转化率',
            _formatPercent((_totalFocusMinutes * 60) / _screenTimeSeconds),
            cs,
          ),
          _buildRankItem(
            0,
            '生产力应用占比',
            _formatPercent(_productiveScreenSeconds / _screenTimeSeconds),
            cs,
          ),
          _buildRankItem(
            0,
            '分心应用时长',
            _formatSecondsCompact(_distractionScreenSeconds),
            cs,
          ),
          if (_topScreenApps.isNotEmpty) ...[
            const Divider(height: 18, thickness: 0.5),
            ..._topScreenApps.take(3).toList().asMap().entries.map((e) {
              final app = e.value;
              return _buildRankItem(
                e.key + 1,
                app.key,
                _formatSecondsCompact(app.value),
                cs,
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildSubjectDonutChart(ColorScheme cs) {
    final dist = _summary!.subjectDistribution;
    if (dist.isEmpty) {
      return Container(
        height: 160,
        alignment: Alignment.center,
        child: Text(
          '暂无分类数据',
          style: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
        ),
      );
    }

    final sorted = dist.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final List<Color> palette = [
      cs.primary,
      cs.secondary,
      cs.tertiary,
      cs.errorContainer,
      Colors.orangeAccent,
      Colors.tealAccent,
      Colors.indigoAccent,
      cs.outline,
    ];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 140,
            child: Stack(
              children: [
                Center(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      size: const Size(120, 120),
                      painter: _DonutPainter(sorted, palette),
                    ),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_pomodoroCount + _timeLogCount}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -1,
                        ),
                      ),
                      Text(
                        '投入段',
                        style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: List.generate(sorted.length, (i) {
              final e = sorted[i];
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: palette[i % palette.length],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${e.key} ${(e.value * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildHourlyRhythm(ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.primary.withValues(alpha: 0.1),
            cs.secondary.withValues(alpha: 0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: cs.primary.withValues(alpha: 0.1)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final chartHeight = constraints.hasBoundedHeight
              ? (constraints.maxHeight - 96).clamp(52.0, 76.0)
              : 70.0;
          final chart = _buildHourlyChart(
            _summary!.hourlyDistribution,
            _summary!.peakHour,
            cs,
            height: chartHeight,
          );

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_rounded, color: cs.primary, size: 24),
              const SizedBox(height: 8),
              Text(
                '${_getPeriodName()}黄金活跃期',
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              chart,
              const SizedBox(height: 10),
              Text(
                '${_summary!.peakHour}:00 为巅峰时刻',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: cs.primary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '该时段活动最密集，适合安排高难任务',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                  height: 1.4,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHourlyChart(
    List<int> distribution,
    int peakHour,
    ColorScheme cs, {
    double height = 82,
  }) {
    if (distribution.isEmpty) return SizedBox(height: height);

    final int maxVal = distribution.reduce((a, b) => a > b ? a : b);
    if (maxVal == 0) return SizedBox(height: height);

    return SizedBox(
      height: height,
      child: Column(
        children: [
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(24, (i) {
                final h = distribution[i];
                final bool isPeak = i == peakHour;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: FractionallySizedBox(
                      heightFactor: h == 0 ? 0.06 : (h / maxVal),
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isPeak
                              ? cs.primary
                              : cs.primary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: List.generate(24, (i) {
              final show = i == 0 || i == 6 || i == 12 || i == 18 || i == 23;
              return Expanded(
                child: Text(
                  show ? i.toString().padLeft(2, '0') : '',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 9,
                    color: i == peakHour
                        ? cs.primary
                        : cs.onSurfaceVariant.withValues(alpha: 0.48),
                    fontWeight: i == peakHour
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildMLInsightsSection(ColorScheme cs) {
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        findItemIndexCallback: (Key key) {
          if (key is ValueKey<String>) {
            final title = key.value;
            final idx = _mlInsights.indexWhere((it) => it.title == title);
            return idx != -1 ? idx : null;
          }
          return null;
        },
        itemCount: _mlInsights.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, index) => SizedBox(
          key: ValueKey<String>(_mlInsights[index].title),
          width: 260,
          child: RepaintBoundary(
            child: _buildInsightItem(_mlInsights[index], cs),
          ),
        ),
      ),
    );
  }

  Widget _buildInsightItem(TimelineMLInsight insight, ColorScheme cs) {
    final confidenceColor = insight.confidence >= 0.7
        ? Colors.green
        : insight.confidence >= 0.5
        ? Colors.orange
        : Colors.grey;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.primary.withValues(alpha: 0.06),
            cs.tertiary.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(insight.icon, size: 18, color: cs.primary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      insight.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    Text(
                      insight.category == 'focus'
                          ? '专注分析'
                          : insight.category == 'completion'
                          ? '完成分析'
                          : insight.category == 'efficiency'
                          ? '效率分析'
                          : '模式分析',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: confidenceColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  '${(insight.confidence * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: confidenceColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Text(
              insight.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.3,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, ColorScheme cs) {
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  String _getPeriodName() {
    switch (_dimension) {
      case TimelineDimension.daily:
        return '今日';
      case TimelineDimension.weekly:
        return '本周';
      case TimelineDimension.monthly:
        return '本月';
      case TimelineDimension.yearly:
        return '今年';
    }
  }

  Widget _buildReflection(ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: cs.primary.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.format_quote_rounded,
            color: cs.primary.withValues(alpha: 0.3),
            size: 40,
          ),
          const SizedBox(height: 16),
          Text(
            _getReflectionText(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              height: 1.8,
              fontFamily: 'Serif',
              color: cs.onSurface.withValues(alpha: 0.8),
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '— 时光记录员',
            style: TextStyle(
              fontSize: 12,
              color: cs.primary.withValues(alpha: 0.5),
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  String _formatEventTitle(TimelineEvent event) {
    final int seed = event.id.hashCode;
    final String sub = (event.subtitle ?? '').toLowerCase();

    String pick(List<String> options) => options[seed % options.length];

    // Keyword detection
    final bool isHomework =
        sub.contains('作业') || sub.contains('练习') || sub.contains('刷题');
    final bool isExam =
        sub.contains('考试') ||
        sub.contains('测验') ||
        sub.contains('考证') ||
        sub.contains('竞赛');
    final bool isReview =
        sub.contains('复习') ||
        sub.contains('总结') ||
        sub.contains('整理') ||
        sub.contains('笔记');
    final bool isReading =
        sub.contains('阅读') ||
        sub.contains('看书') ||
        sub.contains('读书') ||
        sub.contains('文献');

    switch (event.type) {
      case TimelineEventType.pomodoroStart:
        if (isHomework) {
          return pick([
            '开启作业攻坚模式',
            '开始在题海中远航',
            '正在消灭今日作业',
            '笔尖下的专注力',
            '让作业也变成享受',
          ]);
        }
        if (isExam) {
          return pick([
            '进入考前冲刺状态',
            '模拟实战，严阵以待',
            '为了那个目标，出发',
            '正在构建知识盔甲',
            '考场如战场，此刻亮剑',
          ]);
        }
        if (isReview) {
          return pick(['温故而知新', '梳理凌乱的思想', '搭建知识的脚手架', '让记忆变得更深邃', '正在进行深度总结']);
        }
        if (isReading) {
          return pick([
            '潜入书香的世界',
            '跨越时空的对话',
            '在文字间寻找答案',
            '静心享受阅读时光',
            '开启心灵的洗礼',
          ]);
        }
        return pick([
          '开启了专注之旅',
          '让世界安静下来',
          '潜入思考的深处',
          '专注于当下的美好',
          '启动高效引擎',
          '此刻，唯有专注',
          '与目标同行',
          '听，是专注的声音',
          '开始雕琢时光',
          '进入心流频道',
        ]);

      case TimelineEventType.pomodoroEnd:
        if (isHomework) {
          return pick([
            '搞定了！离完成又近一步',
            '笔耕不辍，收获满满',
            '又攻克了一道难题',
            '让作业见证你的成长',
            '今日份作业能量注入完毕',
          ]);
        }
        if (isExam) {
          return pick([
            '离梦想的终点更近了',
            '多一分专注，多一分底气',
            '胜算在一点点积攒',
            '你的努力，必有回响',
            '为了那张完美的答卷',
          ]);
        }
        if (isReview) {
          return pick([
            '知识点已经刻入脑海',
            '思想变得更加清晰',
            '又完成了一次查漏补缺',
            '梳理，是为了更好的出发',
            '收获了成长的复利',
          ]);
        }
        if (isReading) {
          return pick([
            '收获了文字的芬芳',
            '拓宽了生命的维度',
            '与作者共鸣的瞬间',
            '知识的种子正在发芽',
            '精神世界又丰盈了一些',
          ]);
        }
        return pick([
          '收获了专注的果实',
          '完成了一次深呼吸',
          '时光不负苦心人',
          '专注画上圆满句号',
          '又一次战胜了分心',
          '内心的充盈感',
          '让努力被看见',
          '合上专注的篇章',
          '达成一次深度连接',
          '汗水凝结成光',
        ]);

      case TimelineEventType.todoCreated:
        return pick([
          '播种了一个新希望',
          '建立了奋斗的目标',
          '写下未来的约定',
          '开启新任务的挑战',
          '清单上的新成员',
          '勾勒成长的蓝图',
          '给未来一个交代',
          '新的旅程由此开始',
          '记录下这一刻的灵感',
          '待办项+1',
        ]);

      case TimelineEventType.todoCompleted:
        if (event.extraData?['is_recurrence'] == true) {
          return pick([
            '完成了一次周期打卡',
            '习惯如约进行',
            '为坚持再添一格',
            '今天的习惯已达成',
            '周期目标顺利完成',
          ]);
        }
        if (isHomework) {
          return pick([
            '彻底消灭了这项作业',
            '作业清单-1，快乐值+1',
            '笔尖圆满收官',
            '让成就感在纸面跳跃',
            '搞定，今晚可以睡个好觉',
          ]);
        }
        if (isExam) {
          return pick([
            '这是一次漂亮的突围',
            '又翻过了一座大山',
            '离证书/高分又近了',
            '为这场博弈画上句号',
            '你是自己的冠军',
          ]);
        }
        return pick([
          '达成了一个小目标',
          '划掉了一个烦恼',
          '离梦想又近了一步',
          '又一个目标被征服',
          '完美的句点',
          '成就感满满',
          '坚持终有回响',
          '实力证明了自己',
          '完成，是最好的奖励',
          '给努力一个回馈',
        ]);

      case TimelineEventType.courseStart:
        return pick([
          '步入知识的殿堂',
          '与智慧有个约会',
          '课堂，是成长的阶梯',
          '吸收新知识的养分',
          '聆听思想的碰撞',
          '在学海中起航',
          '开启学术模式',
          '知识点正在加载',
          '拓宽认知的边界',
          '在课堂遇见更好的自己',
        ]);
      case TimelineEventType.searchQuery:
        return '探索：${event.subtitle}';
      case TimelineEventType.timeLog:
        return pick(['补全了一段真实投入', '为时间留下了记录', '把做过的事写进时间', '记录一段实际行动']);
      case TimelineEventType.planBlock:
        return pick(['按计划进入行动时段', '赴一场与目标的约定', '规划开始落地', '进入预定任务时间']);
      case TimelineEventType.habitCheckIn:
        return pick(['习惯按计划落地', '为坚持再添一格', '今天也和目标见面了', '把小事做成日常']);
      case TimelineEventType.financeTransaction:
        switch (event.extraData?['finance_type']?.toString()) {
          case 'income':
            return pick(['收入到账，记下这份收获', '为今天的进账留下记录']);
          case 'refund':
            return pick(['收到一笔退款', '生活退回了一点余额']);
          default:
            return pick(['为生活记下一笔支出', '把今天的消费留下来', '让每一笔开销都有迹可循']);
        }
      default:
        return event.title;
    }
  }

  String _getReflectionText() {
    final int seed =
        _selectedDate.day +
        _selectedDate.month +
        _selectedDate.year +
        _dimension.index;
    String pick(List<String> options) => options[seed % options.length];

    if (_recurringCompletedCount > 0 && _totalFocusMinutes == 0) {
      return "习惯不靠一时冲刺，\n而是一次次如约完成。\n这 $_recurringCompletedCount 期坚持，正在悄悄塑造新的你。";
    }

    if (_totalFocusMinutes == 0) {
      return pick([
        "有时候，静谧的休息也是一种力量。\n在无声的岁月里，\n愿你正温柔地积蓄着光芒。",
        "暂时的停歇，是为了跳得更高。\n给自己一点温柔，\n明天又是全新的开始。",
        "今天的留白，是为了画出更美的未来。\n好好休息，也是一种自律。",
        "允许自己偶尔的‘无所事事’，\n在忙碌的世界里，\n找回那份宁静的初衷。",
        "晚风微凉，生活很长。\n愿你今晚有个好梦，\n积攒满格的勇气。",
        "不去追赶时间，让时间来拥抱你。\n今天的寂静，是成长的呼吸。",
        "慢下来，听听内心的声音。\n不焦虑，不盲从，\n在节奏中寻找平衡。",
        "生活不只有冲刺，还有漫步。\n愿你在休息中，\n发现平凡日子里的光。",
        "累了就停下，这并不代表放弃。\n在独处的时光里，\n你是自由且完整的。",
        "收起行囊，在港湾里泊靠。\n愿明日的阳光，\n能照进你充满力量的梦。",
      ]);
    }

    if (_dimension == TimelineDimension.daily) {
      return pick([
        "专注的灵魂最动人，\n你与目标同行的身影，\n是今日最美的风景。",
        "哪怕只是微小的进步，\n也值得被温柔以待。\n每一分钟的努力，\n都在折射未来的光。",
        "今日的汗水，\n会化作明日的星辰。\n感谢你如此坚定地走在路上。",
        "世界喧嚣，你自清欢。\n在这一份专注里，\n你找到了自己的宇宙。",
        "每一个番茄钟的滴答声，\n都是梦想在敲门。\n你离未来，又近了一些。",
        "你是时间的雕刻师，\n用专注打磨着平凡的日常。\n今日的收获，沉甸甸且珍贵。",
        "不积跬步，无以至千里。\n你走的每一步，\n都有其不可替代的意义。",
        "愿这一份充实，\n能化作今晚香甜的睡眠。\n你值得所有的赞美。",
        "在这段旅程中，\n你既是行者，也是光。\n照亮了属于自己的坚持。",
        "完成比完美更重要，\n而你今天做得如此出色。\n请继续保持这份热爱。",
      ]);
    }

    return pick([
      "这一阶段的奔波与坚持，\n终将汇成成长的河流。\n感谢那个从不轻言放弃的自己。",
      "月盈月亏，岁月流转，\n你的足迹清晰而坚定。\n愿接下来的日子，能遇见更好的风景。",
      "年岁序展，光阴如梭，\n这一段的努力，\n已写就最动人的篇章。",
      "回头望去，那是你亲手耕耘出的绿洲。\n在这段时间里，\n你证明了自己的韧性。",
      "每一次攀登都值得铭记，\n每一个高度都是新的起点。\n愿你心怀热望，步履不停。",
      "时光不会遗忘每一滴汗水，\n空间会记住每一次专注。\n这一份总结，是你最好的勋章。",
      "在变幻的世界里，\n守住了一份不变的坚持。\n你比想象中更加强大。",
      "愿这段时间的沉淀，\n能化作你厚积薄发的底气。\n未来已来，不惧挑战。",
      "每一次总结，都是为了更好的出发。\n整理好心情，\n去迎接下一场山海。",
      "你的努力，藏在每一个被勾掉的待办里。\n它们聚沙成塔，\n终将铸就你的不凡。",
    ]);
  }

  String _getMotivationText() {
    final int seed =
        _selectedDate.day + _selectedDate.month + _selectedDate.year;
    String pick(List<String> options) => options[seed % options.length];

    if (_recurringEndingStreak >= 3) {
      return '习惯已经连续完成 $_recurringEndingStreak 期，稳定本身就是一种力量。';
    }

    return pick([
      "专注当下，便是对未来最好的期许。",
      "点滴积累，终将汇成璀璨星河。",
      "坚持的每一天，都在定义全新的你。",
      "岁月的厚重，藏在每一个奋斗的瞬间。",
      "不焦虑未来，不沉溺过去，只深耕现在。",
      "每一个伟大的成就，都源于一次小小的专注。",
      "向着光生长，哪怕缓慢，也要坚定。",
      "愿你心如明镜，在专注中见众生，见自己。",
      "时间对每个人都是公平的，专注让它更有价值。",
      "既然选择了远方，便只顾风雨兼程。",
      "在这一秒，做最好的自己。",
      "平凡的日常里，也藏着不凡的英雄梦想。",
    ]);
  }
}

class _DonutPainter extends CustomPainter {
  final List<MapEntry<String, double>> data;
  final List<Color> palette;
  static final Paint _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  const _DonutPainter(this.data, this.palette);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final strokeWidth = radius * 0.35;
    _paint.strokeWidth = strokeWidth;

    double startAngle = -3.14159 / 2;
    for (int i = 0; i < data.length; i++) {
      final sweepAngle = data[i].value * 2 * 3.14159;
      _paint.color = palette[i % palette.length];

      // Draw arc with slight gap
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
        startAngle + 0.05,
        sweepAngle - 0.1,
        false,
        _paint,
      );
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      !identical(oldDelegate.data, data) ||
      !identical(oldDelegate.palette, palette);
}

class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color color;
  static final Paint _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  static final Path _path = Path();

  _SparklinePainter(this.data, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    _paint.color = color;
    _path.reset();
    var maxVal = data.first;
    var minVal = data.first;
    for (var index = 1; index < data.length; index++) {
      final value = data[index];
      maxVal = maxVal > value ? maxVal : value;
      minVal = minVal < value ? minVal : value;
    }
    final double range = (maxVal - minVal).clamp(1.0, double.infinity);

    final double stepX = size.width / (data.length - 1);

    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final y = size.height - ((data[i] - minVal) / range * size.height);
      if (i == 0) {
        _path.moveTo(x, y);
      } else {
        _path.lineTo(x, y);
      }
    }

    canvas.drawPath(_path, _paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      !identical(oldDelegate.data, data) || oldDelegate.color != color;
}
