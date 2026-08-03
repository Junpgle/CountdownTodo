import 'package:flutter/material.dart';

import '../models/cloud_challenge.dart';
import '../services/cloud_challenge_service.dart';

class CloudChallengePickerScreen extends StatefulWidget {
  const CloudChallengePickerScreen({super.key});

  @override
  State<CloudChallengePickerScreen> createState() =>
      _CloudChallengePickerScreenState();
}

class _CloudChallengePickerScreenState
    extends State<CloudChallengePickerScreen> {
  final _service = CloudChallengeService();
  CloudChallengeCatalog? _catalog;
  Object? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final catalog = await _service.fetchCatalog();
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final catalog = _catalog;

    return Scaffold(
      appBar: AppBar(
        title: const Text('云端挑战'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState(scheme)
              : catalog == null
                  ? _buildErrorState(scheme)
                  : _buildCatalog(catalog, scheme),
    );
  }

  Widget _buildCatalog(CloudChallengeCatalog catalog, ColorScheme scheme) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: catalog.challenges.length + 1,
      separatorBuilder: (_, index) => SizedBox(height: index == 0 ? 12 : 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Card(
            elevation: 0,
            color: scheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.cloud_download_rounded, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '来自 GitHub 的挑战清单',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          catalog.updatedAt.isEmpty
                              ? '选择一份挑战后会自动填入编辑页，你仍然可以继续修改。'
                              : '清单更新于 ${catalog.updatedAt}。选择后会自动填入编辑页，你仍然可以继续修改。',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onPrimaryContainer),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final challenge = catalog.challenges[index - 1];
        return _buildChallengeCard(challenge, scheme);
      },
    );
  }

  Widget _buildChallengeCard(
    CloudChallengeTemplate challenge,
    ColorScheme scheme,
  ) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(challenge),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: scheme.onTertiaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      challenge.title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    if (challenge.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        challenge.description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _buildInfoChip(
                          '${challenge.tasks.length} 项任务',
                          Icons.format_list_bulleted_rounded,
                          scheme,
                        ),
                        for (final tag in challenge.tags.take(3))
                          _buildInfoChip(
                              tag, Icons.label_outline_rounded, scheme),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label, IconData icon, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              '暂时无法获取云端挑战',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              '请检查网络连接，或返回使用本地自定义输入。',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重新获取'),
            ),
          ],
        ),
      ),
    );
  }
}
