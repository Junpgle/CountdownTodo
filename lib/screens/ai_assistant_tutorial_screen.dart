import 'package:flutter/material.dart';

class AiAssistantTutorialScreen extends StatefulWidget {
  const AiAssistantTutorialScreen({super.key});

  @override
  State<AiAssistantTutorialScreen> createState() => _AiAssistantTutorialScreenState();
}

class _AiAssistantTutorialScreenState extends State<AiAssistantTutorialScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final List<Widget> children = [
      _heroFlow(context),
      const SizedBox(height: 24),
      _sectionTitle(context, '✨ 核心能力'),
      _capabilityItem(
        context,
        icon: Icons.auto_fix_high_rounded,
        title: '待办规划',
        detail: '根据目标自动生成待办，或将已有待办精准排入“规划块”中，构建日程。',
        color: colorScheme.primary,
      ),
      _capabilityItem(
        context,
        icon: Icons.view_timeline_rounded,
        title: '任务拆合',
        detail: '将复杂大任务智能拆解为子任务，或将琐碎待办合并。',
        color: colorScheme.secondary,
      ),
      _capabilityItem(
        context,
        icon: Icons.timer_outlined,
        title: '专注协同',
        detail: '通过 AI 启停番茄钟、补录专注记录，并自动同步规划进度。',
        color: colorScheme.tertiary,
      ),
      _capabilityItem(
        context,
        icon: Icons.hub_rounded,
        title: '多维管理',
        detail: '管理倒计时、分类文件夹及番茄标签，全方位梳理工作流。',
        color: colorScheme.error,
      ),
      const SizedBox(height: 16),
      _sectionTitle(context, '📅 深度规划与同步'),
      _planningHighlight(context),
      const SizedBox(height: 16),
      _sectionTitle(context, '🚀 快速上手'),
      _howToItem(
        context,
        step: '01',
        title: '输入任务目标',
        detail: '例：“规划一下今天下午，避开3点的课，把剩下的待办排满。”',
      ),
      _howToItem(
        context,
        step: '02',
        title: '预览操作清单',
        detail: 'AI 会生成 [ACTION] 动作块，在界面下方或侧边栏显示预览。',
      ),
      _howToItem(
        context,
        step: '03',
        title: '确认并一键执行',
        detail: '勾选需要执行的项。只有你点下“执行所选操作”，数据才会被真正修改。',
      ),
      const SizedBox(height: 16),
      _sectionTitle(context, '🧩 外部 AI 协作'),
      _externalAiNote(context),
      const SizedBox(height: 16),
      _sectionTitle(context, '🛠️ 界面指南'),
      _guideGrid(context),
      const SizedBox(height: 24),
      _sectionTitle(context, '🔍 智能上下文详解'),
      _smartContextDetails(context),
      const SizedBox(height: 24),
      _sectionTitle(context, '💡 高级技巧'),
      _proTips(context),
      const SizedBox(height: 24),
      _securityNote(context),
      const SizedBox(height: 32),
    ];

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text(
              'AI 助手教程',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            floating: true,
            pinned: true,
            stretch: true,
            backgroundColor: colorScheme.surface,
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      const stagger = 0.03;
                      final startTime = index * stagger;
                      const animationDuration = 0.6;
                      final value = Curves.easeOutQuart.transform(
                        ((_controller.value - startTime) / animationDuration).clamp(0.0, 1.0),
                      );
                      return IgnorePointer(
                        ignoring: value == 0,
                        child: Opacity(
                          opacity: value,
                          child: Transform.translate(
                            offset: Offset(0, 40 * (1 - value)),
                            child: child,
                          ),
                        ),
                      );
                    },
                    child: children[index],
                  );
                },
                childCount: children.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, left: 4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
          ),
        ],
      ),
    );
  }

  Widget _capabilityItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String detail,
    required Color color,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 22, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _howToItem(
    BuildContext context, {
    required String step,
    required String title,
    required String detail,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.primary.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Text(
                    step,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          colorScheme.primary,
                          colorScheme.primary.withValues(alpha: 0.1),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      detail,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _guideGrid(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _gridItem(context, Icons.history_rounded, '历史会话', '管理往期对话记录')),
            const SizedBox(width: 12),
            Expanded(child: _gridItem(context, Icons.add_comment_rounded, '开启新篇', '随时开启全新话题')),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _gridItem(context, Icons.psychology_rounded, '深度思考', '应对复杂逻辑推理')),
            const SizedBox(width: 12),
            Expanded(child: _gridItem(context, Icons.auto_awesome_rounded, '智能注入', '自动获取应用上下文')),
          ],
        ),
      ],
    );
  }

  Widget _gridItem(BuildContext context, IconData icon, String title, String desc) {
    final colorScheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 1.6,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 2),
            Expanded(
              child: Text(
                desc,
                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroFlow(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primaryContainer,
            colorScheme.secondaryContainer.withValues(alpha: 0.5),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(Icons.auto_awesome_rounded, size: 48, color: colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            '高效协作，一气呵成',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onPrimaryContainer,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '从灵感到执行，AI 助你管理每一分钟',
            style: TextStyle(
              color: colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _heroStep(context, Icons.chat_bubble_outline_rounded, '提问'),
              _heroArrow(context),
              _heroStep(context, Icons.auto_fix_high_rounded, '生成'),
              _heroArrow(context),
              _heroStep(context, Icons.task_alt_rounded, '执行'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroStep(BuildContext context, IconData icon, String label) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surface.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 24, color: colorScheme.primary),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
      ],
    );
  }

  Widget _heroArrow(BuildContext context) {
    return Icon(
      Icons.arrow_forward_ios_rounded,
      size: 14,
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
    );
  }

  Widget _securityNote(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Icon(Icons.shield_rounded, color: colorScheme.error, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '安全与确认',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onErrorContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'AI 仅生成建议，所有数据变更均需你手动点击执行。',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onErrorContainer.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _planningHighlight(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.secondaryContainer.withValues(alpha: 0.2),
            colorScheme.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.secondary.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          _planningRow(context, Icons.event_note_rounded, '自动避让', 'AI 规划时会自动避开课程表中的已有课程。'),
          const SizedBox(height: 12),
          _planningRow(context, Icons.sync_rounded, '多端同步', '规划块支持远端与本地同步，确保日程在所有设备一致。'),
          const SizedBox(height: 12),
          _planningRow(context, Icons.auto_graph_rounded, '进度追踪', 'AI 可根据番茄钟实际专注时长自动更新规划进度。'),
        ],
      ),
    );
  }

  Widget _planningRow(BuildContext context, IconData icon, String title, String desc) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.secondary),
        const SizedBox(width: 12),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface, height: 1.4),
              children: [
                TextSpan(text: '$title：', style: const TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: desc),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _externalAiNote(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.tertiary.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.extension_rounded, size: 20, color: colorScheme.tertiary),
              const SizedBox(width: 8),
              const Text('不依赖内置 API 也能用', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '你可以通过“复制提示词”将当前上下文带入 ChatGPT 或 Claude，再通过“粘贴 AI 回复识别”功能将结果带回应用执行。',
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 8),
          Text(
            '适合：内置 API 不稳定或需要使用更高版本模型时。',
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _proTips(BuildContext context) {
    return Column(
      children: [
        _tipItem(context, '深度思考', '开启“深度思考”模式（如使用 R1/O1 模型），AI 会展示推理过程，适合处理复杂的日程重排任务。'),
        _tipItem(context, '提示词自定义', '在顶部菜单中进入“提示词设置”，你可以定制 AI 的语气或强制其遵循特定的工作流建议。'),
        _tipItem(context, '课程组件入口', '在课程表组件中长按或点击菜单，可直接发起针对该课程时间段的 AI 规划。'),
      ],
    );
  }

  Widget _tipItem(BuildContext context, String title, String desc) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•', style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 2),
                Text(desc, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _smartContextDetails(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '智能上下文通过“关键词按需注入”技术，仅在对话需要时才向 AI 传递特定背景，平衡了功能、性能与隐私。',
            style: TextStyle(fontSize: 14, height: 1.6),
          ),
          const SizedBox(height: 20),
          _contextDetailItem(
            context,
            Icons.school_rounded,
            '课程表',
            '课、上课、教室、排课...',
            '自动注入相关的课程时间、地点与教师信息，用于避开上课时间规划待办。',
          ),
          _divider(context),
          _contextDetailItem(
            context,
            Icons.history_toggle_off_rounded,
            '专注记录',
            '专注、时长、番茄钟、统计...',
            '注入历史专注时长与记录，帮助 AI 总结效率或回答关于“我最近在忙什么”的问题。',
          ),
          _divider(context),
          _contextDetailItem(
            context,
            Icons.sync_problem_rounded,
            '同步冲突',
            '冲突、同步、版本、覆盖...',
            '当出现多设备同步数据不一致时，AI 可获取冲突项细节，助你决策。',
          ),
          _divider(context),
          _contextDetailItem(
            context,
            Icons.groups_rounded,
            '团队协作',
            '团队、成员、协作、邀请...',
            '提供团队基本信息与成员列表，用于执行团队分配任务或查看小组状态。',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline_rounded, size: 16, color: colorScheme.secondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '提示：关闭“智能上下文”可停止所有自动注入，节省流量并保护隐私。',
                    style: TextStyle(fontSize: 12, color: colorScheme.onSecondaryContainer),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _contextDetailItem(
      BuildContext context, IconData icon, String title, String keywords, String desc) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        keywords,
                        style: TextStyle(fontSize: 10, color: colorScheme.primary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3)),
    );
  }
}
