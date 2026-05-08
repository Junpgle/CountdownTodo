import 'package:flutter/material.dart';

class AiAssistantTutorialScreen extends StatelessWidget {
  const AiAssistantTutorialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('AI助手使用教程')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
        children: [
          _heroFlow(context),
          const SizedBox(height: 12),
          _sectionTitle(context, '这个助手能做什么'),
          _capabilityItem(
            context,
            icon: Icons.checklist_rtl_rounded,
            title: '待办管理',
            detail: '新建、修改、完成、删除、改期、批量改期、分类、拆分、合并。',
          ),
          _capabilityItem(
            context,
            icon: Icons.view_timeline_rounded,
            title: '规划块与专注',
            detail: '新建/调整规划块，跳过规划块，启动或停止番茄钟，维护专注记录。',
          ),
          _capabilityItem(
            context,
            icon: Icons.timer_outlined,
            title: '倒计时与分类标签',
            detail: '管理倒计时、待办分类（文件夹）、番茄标签。',
          ),
          _capabilityItem(
            context,
            icon: Icons.hub_rounded,
            title: '智能上下文回答',
            detail: '可结合课程、专注记录、团队等上下文回答（开启智能上下文时）。',
          ),
          const SizedBox(height: 8),
          _sectionTitle(context, '怎么用（最短路径）'),
          _howToItem(
            context,
            step: '1',
            title: '输入任务目标',
            detail: '一句话说清楚：做什么 + 时间 + 数量。\n例：把今天待办按优先级重排，并给3个可执行调整。',
          ),
          _howToItem(
            context,
            step: '2',
            title: '查看AI回复',
            detail: 'AI可能给普通建议，也可能生成“待执行操作”清单。',
          ),
          _howToItem(
            context,
            step: '3',
            title: '确认并执行',
            detail: '在“待执行操作”里勾选/编辑/忽略，最后点“执行所选操作”才会真正写入数据。',
          ),
          _howToItem(
            context,
            step: '4',
            title: '需要时再调参数',
            detail: '复杂任务可开“深度思考”；需额外背景时开“智能上下文”。',
          ),
          const SizedBox(height: 8),
          _sectionTitle(context, '顶部栏按钮'),
          _buttonItem(
            context,
            icon: Icons.arrow_back_ios_new_rounded,
            name: '返回',
            detail: '退出当前 AI 助手页，回到上一个页面。',
          ),
          _buttonItem(
            context,
            icon: Icons.history_rounded,
            name: '历史对话（窄屏）',
            detail: '打开历史会话侧栏，用于切换/删除会话。',
          ),
          _buttonItem(
            context,
            icon: Icons.keyboard_double_arrow_left_rounded,
            name: '隐藏侧栏（宽屏）',
            detail: '收起左侧历史会话栏，增大聊天区域。',
          ),
          _buttonItem(
            context,
            icon: Icons.keyboard_double_arrow_right_rounded,
            name: '显示侧栏（宽屏）',
            detail: '展开左侧历史会话栏。',
          ),
          _buttonItem(
            context,
            icon: Icons.add_comment_rounded,
            name: '新建对话',
            detail: '创建新会话并切换过去，不删除旧记录。',
          ),
          _buttonItem(
            context,
            icon: Icons.tune_rounded,
            name: '提示词设置',
            detail: '配置自定义提示词，影响 AI 的回答和动作生成。',
          ),
          _buttonItem(
            context,
            icon: Icons.menu_book_rounded,
            name: '使用教程',
            detail: '打开当前教程页。',
          ),
          const SizedBox(height: 8),
          _sectionTitle(context, '历史侧栏按钮'),
          _buttonItem(
            context,
            icon: Icons.delete_sweep_outlined,
            name: '清空所有历史对话',
            detail: '删除全部会话（不可撤销）。',
          ),
          _buttonItem(
            context,
            icon: Icons.close,
            name: '关闭侧栏（窄屏）',
            detail: '仅关闭历史侧栏，不影响会话数据。',
          ),
          _buttonItem(
            context,
            icon: Icons.delete_outline,
            name: '删除单个对话',
            detail: '删除当前行会话；若删的是正在使用会话会自动切换。',
          ),
          const SizedBox(height: 8),
          _sectionTitle(context, '输入区上方按钮'),
          _buttonItem(
            context,
            icon: Icons.model_training_outlined,
            name: '模型配置',
            detail: '选择继承全局模型或使用聊天页独立模型配置。',
          ),
          _buttonItem(
            context,
            icon: Icons.content_copy_rounded,
            name: '复制提示词',
            detail: '把完整提示词复制到剪贴板，便于外部 AI 使用。',
          ),
          _buttonItem(
            context,
            icon: Icons.assignment_rounded,
            name: '粘贴AI回复识别',
            detail: '把外部 AI 回复粘贴回来，解析为可执行操作。',
          ),
          _buttonItem(
            context,
            icon: Icons.delete_sweep_rounded,
            name: '清空当前会话消息',
            detail: '清空当前会话的聊天内容。',
          ),
          const SizedBox(height: 8),
          _sectionTitle(context, '输入框按钮'),
          _buttonItem(
            context,
            icon: Icons.psychology_rounded,
            name: '深度思考',
            detail: '开启后更偏复杂推理，响应可能更慢。',
          ),
          _buttonItem(
            context,
            icon: Icons.auto_awesome_rounded,
            name: '智能上下文',
            detail: '按提问自动注入课程/专注/团队等上下文信息。',
          ),
          _buttonItem(
            context,
            icon: Icons.refresh_rounded,
            name: '重试',
            detail: '对上一条问题重新生成回复（仅在上一条是助手回复时显示）。',
          ),
          _buttonItem(
            context,
            icon: Icons.arrow_upward_rounded,
            name: '发送',
            detail: '发送当前输入内容给 AI。',
          ),
          _buttonItem(
            context,
            icon: Icons.stop_rounded,
            name: '停止',
            detail: '中断当前生成；已生成部分会保留为“已中断”回复。',
          ),
          const SizedBox(height: 8),
          _sectionTitle(context, '待执行操作区按钮'),
          _buttonItem(
            context,
            icon: Icons.check_box_outlined,
            name: '勾选框',
            detail: '控制该条动作是否参与执行。',
          ),
          _buttonItem(
            context,
            icon: Icons.edit_outlined,
            name: '编辑执行内容',
            detail: '执行前修改该动作的标题、时间、备注等内容。',
          ),
          _buttonItem(
            context,
            icon: Icons.close_rounded,
            name: '忽略此操作',
            detail: '标记该动作为忽略，不会执行。',
          ),
          _buttonItem(
            context,
            icon: Icons.arrow_drop_down,
            name: '分类下拉',
            detail: '为待办类动作选择目标分类/默认分类。',
          ),
          _buttonItem(
            context,
            icon: Icons.add_task,
            name: '执行所选操作',
            detail: '真正落库执行。只有勾选且未忽略的动作会生效。',
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.security_rounded, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '只执行你确认过的操作。涉及删除/停止类动作，先检查再执行。',
                  ),
                ),
              ],
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
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: DefaultTextStyle.of(context).style,
                children: [
                  TextSpan(
                    text: '$title：',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: detail),
                ],
              ),
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
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              step,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: colorScheme.primary,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(detail),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  Widget _buttonItem(
    BuildContext context, {
    required IconData icon,
    required String name,
    required String detail,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 17, color: colorScheme.primary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(detail),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroFlow(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primary.withValues(alpha: 0.10),
            colorScheme.tertiary.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '一图看懂',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          const Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _FlowChip(icon: Icons.chat_rounded, text: '提问'),
              Icon(Icons.arrow_forward_rounded, size: 16),
              _FlowChip(icon: Icons.psychology_rounded, text: '生成建议/操作'),
              Icon(Icons.arrow_forward_rounded, size: 16),
              _FlowChip(icon: Icons.rule_rounded, text: '你来确认'),
              Icon(Icons.arrow_forward_rounded, size: 16),
              _FlowChip(icon: Icons.done_all_rounded, text: '执行落库'),
            ],
          ),
        ],
      ),
    );
  }

}

class _FlowChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FlowChip({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.primary),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
