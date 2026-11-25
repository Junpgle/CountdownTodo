part of '../about_screen.dart';

class _LinkItem {
  final GlobalKey? sourceKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  _LinkItem({
    this.sourceKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}

class _DatabaseChangelogSheet extends StatelessWidget {
  final int? currentVersion;

  const _DatabaseChangelogSheet({required this.currentVersion});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentLabel = currentVersion == null ? '未读取' : 'V$currentVersion';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 8, 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.storage_rounded,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '数据库更新日志',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '当前 $currentLabel · 最新 V${DatabaseSchemaHistory.currentVersion}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
                tooltip: '关闭',
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '以下记录仅包含本地 SQLite 架构变更，不包含应用功能更新。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            findItemIndexCallback: (Key key) {
              if (key is ValueKey<int>) {
                final v = key.value;
                final idx = DatabaseSchemaHistory.changes.indexWhere(
                  (c) => c.version == v,
                );
                return idx != -1 ? idx : null;
              }
              return null;
            },
            itemCount: DatabaseSchemaHistory.changes.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final entry = DatabaseSchemaHistory.changes[index];
              final isCurrent = entry.version == currentVersion;

              return RepaintBoundary(
                key: ValueKey<int>(entry.version),
                child: OptionalLiquidGlassCard(
                  margin: EdgeInsets.zero,
                  borderRadius: 12,
                  clipBehavior: Clip.antiAlias,
                  highContrast: true,
                  tint: isCurrent
                      ? colorScheme.primaryContainer.withValues(alpha: 0.16)
                      : null,
                  fallbackDecoration: BoxDecoration(
                    color: isCurrent
                        ? colorScheme.primaryContainer.withValues(alpha: 0.45)
                        : colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.fromBorderSide(
                      BorderSide(
                        color: isCurrent
                            ? colorScheme.primary.withValues(alpha: 0.35)
                            : colorScheme.outlineVariant.withValues(
                                alpha: 0.45,
                              ),
                      ),
                    ),
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Theme(
                      data: theme.copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        key: PageStorageKey(
                          'database-version-${entry.version}',
                        ),
                        initiallyExpanded: isCurrent,
                        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          14,
                        ),
                        title: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'V${entry.version}',
                                style: TextStyle(
                                  color: colorScheme.onSecondaryContainer,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (isCurrent) ...[
                              const SizedBox(width: 8),
                              Text(
                                '当前',
                                style: TextStyle(
                                  color: colorScheme.primary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(entry.title),
                        ),
                        children: entry.changes
                            .map(
                              (change) => Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 7),
                                      child: Icon(
                                        Icons.circle,
                                        size: 5,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        change,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(height: 1.45),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class PrivacyPolicyPage extends StatelessWidget {
  final String? content;
  final String? date;
  final bool isLoading;
  final bool isEmbedded;

  const PrivacyPolicyPage({
    super.key,
    this.content,
    this.date,
    this.isLoading = true,
    this.isEmbedded = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: !isEmbedded,
      appBar: isEmbedded
          ? null
          : FloatingGlassAppBar(
              flexibleSpace: const FloatingGlassTopBarBackground(),
              title: const Text('隐私政策'),
              centerTitle: true,
            ),
      body: floatingGlassSettingsBody(
        context,
        standalone: !isEmbedded,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : content == null
            ? const Center(child: Text('加载失败，请检查网络连接'))
            : Markdown(
                data: content!,
                padding: EdgeInsets.fromLTRB(
                  16,
                  isEmbedded
                      ? 16
                      : floatingGlassSettingsContentTopInset(
                          context,
                          extra: 16,
                        ),
                  16,
                  16,
                ),
                styleSheet: MarkdownStyleSheet(
                  h1: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  h2: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  h3: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  p: const TextStyle(fontSize: 14, height: 1.6),
                  listBullet: const TextStyle(fontSize: 14),
                  blockquote: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                  code: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                  codeblockDecoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
      ),
    );
  }
}
