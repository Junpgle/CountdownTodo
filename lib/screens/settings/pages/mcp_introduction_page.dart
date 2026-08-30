import 'package:flutter/material.dart';

import '../../../widgets/floating_glass_control.dart';

class McpIntroductionPage extends StatelessWidget {
  final bool isEmbedded;

  const McpIntroductionPage({super.key, this.isEmbedded = false});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: !isEmbedded,
      appBar: isEmbedded
          ? null
          : FloatingGlassAppBar(
              flexibleSpace: const FloatingGlassTopBarBackground(),
              title: const Text('MCP 接入说明'),
            ),
      body: floatingGlassSettingsBody(
        context,
        standalone: !isEmbedded,
        child: SelectionArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              isEmbedded
                  ? 16
                  : floatingGlassSettingsContentTopInset(context, extra: 16),
              16,
              32,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHero(context),
                    const SizedBox(height: 20),
                    _buildSection(
                      context,
                      title: '当前能做什么',
                      icon: Icons.auto_awesome_outlined,
                      children: const [
                        _McpDetailRow(
                          icon: Icons.search_rounded,
                          title: '查询个人待办',
                          detail: '按状态、关键词、分类和截止时间查询，并读取待办详情。',
                        ),
                        _McpDetailRow(
                          icon: Icons.edit_calendar_outlined,
                          title: '管理个人待办',
                          detail: '创建和修改待办、完成或恢复待办，以及软删除到回收站。',
                        ),
                        _McpDetailRow(
                          icon: Icons.sync_outlined,
                          title: '延续应用同步',
                          detail: '写入会保留操作日志和 AI（MCP）审计记录，之后由应用继续同步。',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildSection(
                      context,
                      title: '安全与隐私',
                      icon: Icons.shield_outlined,
                      children: const [
                        _McpDetailRow(
                          icon: Icons.visibility_outlined,
                          title: '首次建议只读',
                          detail:
                              '将 COUNTDOWN_TODO_MCP_READ_ONLY 设为 1 后，服务不会向 AI 客户端提供写入工具。',
                        ),
                        _McpDetailRow(
                          icon: Icons.warning_amber_rounded,
                          title: '写入前确认',
                          detail: '读写模式会直接修改本地数据库。执行写操作时建议关闭应用，完成后再重启或刷新。',
                        ),
                        _McpDetailRow(
                          icon: Icons.policy_outlined,
                          title: '留意模型服务商',
                          detail:
                              'AI 客户端可能把工具返回的数据发送给所选模型，请同时检查客户端与模型服务商的隐私策略。',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildAvailabilityCard(context),
                    const SizedBox(height: 16),
                    _buildGettingStartedCard(context),
                    const SizedBox(height: 12),
                    Text(
                      'MCP 服务不会主动唤醒 CountdownTodo，也不负责立即刷新界面、同步或通知计划；这些动作会在应用下次启动、刷新或同步时完成。',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.hub_outlined,
                  color: colorScheme.primary,
                  size: 28,
                ),
              ),
              const Spacer(),
              Chip(
                label: const Text('开发者预览'),
                side: BorderSide.none,
                backgroundColor: colorScheme.surface.withValues(alpha: 0.72),
                labelStyle: TextStyle(color: colorScheme.onSurface),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'MCP（模型上下文协议）',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'MCP 是 AI 助手连接应用数据和操作能力的一套开放协议。连接 CountdownTodo 后，兼容的 AI 客户端可以在你授予的权限范围内读取或管理个人待办。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onPrimaryContainer,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: colorScheme.primary, size: 22),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildAvailabilityCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return _buildSection(
      context,
      title: '初期支持范围',
      icon: Icons.devices_outlined,
      children: [
        const _McpDetailRow(
          icon: Icons.desktop_windows_outlined,
          title: '桌面端本地连接',
          detail: '本地 stdio 服务面向 macOS、Windows 和 Linux；Android、iOS 与 Web 尚未接入。',
        ),
        const _McpDetailRow(
          icon: Icons.checklist_rounded,
          title: '仅限个人待办',
          detail: '团队待办、倒计时、番茄钟、规划块和课程暂不开放给 MCP。',
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'MCP 使用本地 SQLite 数据库，不会额外监听网络端口。',
            style: TextStyle(
              color: colorScheme.onSecondaryContainer,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGettingStartedCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return _buildSection(
      context,
      title: '如何开始',
      icon: Icons.rocket_launch_outlined,
      children: [
        const _NumberedStep(
          number: '1',
          text: '准备 Node.js 22.13 或更高版本，并安装项目 mcp-server 目录中的依赖。',
        ),
        const _NumberedStep(
          number: '2',
          text: '在 AI 客户端中配置本地 stdio 服务和当前账号的 SQLite 数据库绝对路径。',
        ),
        const _NumberedStep(
          number: '3',
          text: '先启用只读模式，通过 mcp_status 检查连接，再按需开放写入工具。',
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '完整配置示例：mcp-server/README.md',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

class _McpDetailRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;

  const _McpDetailRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 19,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberedStep extends StatelessWidget {
  final String number;
  final String text;

  const _NumberedStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: TextStyle(
                color: colorScheme.onPrimary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                text,
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
