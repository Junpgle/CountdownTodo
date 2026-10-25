import 'package:flutter/material.dart';

import '../../../models/data_export_models.dart';
import '../../../utils/app_dialogs.dart';

class ImportRestoreRulesCard extends StatelessWidget {
  final Set<ImportDataScope> selectedScopes;
  final int selectedTeamCount;

  const ImportRestoreRulesCard({
    super.key,
    required this.selectedScopes,
    required this.selectedTeamCount,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasRecordScopes = selectedScopes.any(
      (scope) =>
          scope == ImportDataScope.productivity ||
          scope == ImportDataScope.courses ||
          scope == ImportDataScope.habits ||
          scope == ImportDataScope.finance,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.rule_folder_outlined, color: colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  '恢复规则',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '各数据域沿用自己的导入规则。备份条目数不是预计新增数、更新数或冲突数。',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            if (hasRecordScopes) ...[
              const SizedBox(height: 8),
              Text(
                '待办、课表、习惯和记账按各自现有规则处理；当前预览不逐条预测本地冲突。',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ],
            if (selectedScopes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '所选范围内的软删除记录仍会进入原有导入流程，不代表会删除同数量的本地数据。',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ],
            if (selectedTeamCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                '当前选择中有 $selectedTeamCount 条团队记录，按下方团队策略处理。',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ],
            if (selectedScopes.contains(ImportDataScope.challenge)) ...[
              const SizedBox(height: 10),
              _ImportRestoreNotice(
                icon: Icons.warning_amber_rounded,
                color: colorScheme.errorContainer,
                foreground: colorScheme.onErrorContainer,
                text: '30天挑战：备份状态会恢复到当前账号，可能覆盖当前挑战进度。',
              ),
            ],
            if (selectedScopes.contains(ImportDataScope.settings)) ...[
              const SizedBox(height: 8),
              _ImportRestoreNotice(
                icon: Icons.settings_outlined,
                color: colorScheme.tertiaryContainer,
                foreground: colorScheme.onTertiaryContainer,
                text: '偏好设置：备份中受支持的设置键会覆盖对应当前设置；缺少的键保持不变。',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ImportRestoreReviewDialog extends StatelessWidget {
  final ImportPreview preview;
  final Set<ImportDataScope> selectedScopes;
  final bool? isSameAccount;
  final TeamDataStrategy teamStrategy;
  final int selectedTeamCount;

  const ImportRestoreReviewDialog({
    super.key,
    required this.preview,
    required this.selectedScopes,
    required this.isSameAccount,
    required this.teamStrategy,
    required this.selectedTeamCount,
  });

  static Future<bool> show({
    required BuildContext context,
    required ImportPreview preview,
    required Set<ImportDataScope> selectedScopes,
    required bool? isSameAccount,
    required TeamDataStrategy teamStrategy,
    required int selectedTeamCount,
  }) async {
    final result = await showAppDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ImportRestoreReviewDialog(
        preview: preview,
        selectedScopes: selectedScopes,
        isSameAccount: isSameAccount,
        teamStrategy: teamStrategy,
        selectedTeamCount: selectedTeamCount,
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedPreviews = preview.scopes
        .where((scope) => selectedScopes.contains(scope.scope))
        .toList(growable: false);

    return AlertDialog(
      title: const Text('确认恢复范围'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('将处理以下备份数据域：'),
              const SizedBox(height: 8),
              for (final scope in selectedPreviews)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Icon(scope.icon, size: 18, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(scope.label)),
                      const SizedBox(width: 8),
                      Text('${scope.count} 项（备份）'),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                '以上数量来自备份文件，不是预计写入数量。',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              if (isSameAccount != null) ...[
                const SizedBox(height: 10),
                Text(
                  isSameAccount! ? '账号处理：保留原 UUID。' : '账号处理：按现有规则重映射 UUID。',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ],
              if (selectedTeamCount > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '团队数据：$selectedTeamCount 条；${teamStrategy == TeamDataStrategy.skip ? '跳过团队记录' : '转为个人数据'}。',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ],
              if (selectedScopes.contains(ImportDataScope.challenge)) ...[
                const SizedBox(height: 12),
                _ImportRestoreNotice(
                  icon: Icons.warning_amber_rounded,
                  color: colorScheme.errorContainer,
                  foreground: colorScheme.onErrorContainer,
                  text: '恢复挑战状态可能覆盖当前账号的挑战进度。',
                ),
              ],
              if (selectedScopes.contains(ImportDataScope.settings)) ...[
                const SizedBox(height: 8),
                _ImportRestoreNotice(
                  icon: Icons.settings_outlined,
                  color: colorScheme.tertiaryContainer,
                  foreground: colorScheme.onTertiaryContainer,
                  text: '备份中受支持的设置键会覆盖对应当前设置。',
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('确认恢复'),
        ),
      ],
    );
  }
}

class ImportScopeRestoreSummaryList extends StatelessWidget {
  final List<ImportScopeRestoreSummary> summaries;

  const ImportScopeRestoreSummaryList({super.key, required this.summaries});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < summaries.length; index++) ...[
          if (index > 0) const Divider(height: 20),
          _buildSummary(context, summaries[index], colorScheme),
        ],
      ],
    );
  }

  Widget _buildSummary(
    BuildContext context,
    ImportScopeRestoreSummary summary,
    ColorScheme colorScheme,
  ) {
    final detail = switch (summary.kind) {
      ImportScopeRestoreKind.recordChanges =>
        summary.importedCount == 0 &&
                summary.updatedCount == 0 &&
                summary.skippedCount == 0
            ? '没有记录变更'
            : '新增 ${summary.importedCount} · 更新 ${summary.updatedCount} · 跳过 ${summary.skippedCount}',
      ImportScopeRestoreKind.settingsApplied =>
        '已应用 ${summary.detailCount} 项设置',
      ImportScopeRestoreKind.challengeRestored =>
        '挑战状态已恢复 · 包含 ${summary.detailCount} 项任务',
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(summary.scope.icon, size: 18, color: colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                summary.scope.label,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ImportRestoreNotice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color foreground;
  final String text;

  const _ImportRestoreNotice({
    required this.icon,
    required this.color,
    required this.foreground,
    required this.text,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: foreground),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(color: foreground)),
        ),
      ],
    ),
  );
}
