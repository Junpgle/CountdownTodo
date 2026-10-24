import 'package:flutter/material.dart';

import '../../../models/data_export_models.dart';

class ImportScopeSelector extends StatelessWidget {
  final ImportPreview preview;
  final Set<ImportDataScope> selectedScopes;
  final ValueChanged<Set<ImportDataScope>> onSelectionChanged;

  const ImportScopeSelector({
    super.key,
    required this.preview,
    required this.selectedScopes,
    required this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedPreviews = preview.scopes
        .where((scope) => selectedScopes.contains(scope.scope))
        .toList(growable: false);
    final selectedCount = selectedPreviews.fold<int>(
      0,
      (total, scope) => total + scope.count,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '选择恢复范围',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: selectedScopes.length == preview.scopes.length
                  ? null
                  : () => onSelectionChanged(
                      preview.scopes.map((scope) => scope.scope).toSet(),
                    ),
              child: const Text('全选'),
            ),
            TextButton(
              onPressed: selectedScopes.isEmpty
                  ? null
                  : () => onSelectionChanged({}),
              child: const Text('清空'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '已选 ${selectedPreviews.length} 个数据域 · $selectedCount 项',
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
        ),
        if (selectedScopes.contains(ImportDataScope.settings)) ...[
          const SizedBox(height: 6),
          Text(
            '包含偏好设置：导入后会应用备份中的设置。取消勾选可保持当前设置不变。',
            style: TextStyle(color: colorScheme.tertiary, fontSize: 12),
          ),
        ],
        const SizedBox(height: 8),
        ...preview.scopes.map((scope) => _buildScopeTile(context, scope)),
        if (preview.unsupportedKeys.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前版本不会导入以下数据段',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  preview.unsupportedKeys.join('、'),
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildScopeTile(BuildContext context, ImportScopePreview scope) {
    final theme = Theme.of(context);
    final scopeSelected = selectedScopes.contains(scope.scope);
    final subtitleParts = <String>['${scope.count} 项'];
    if (scope.deletedCount > 0) {
      subtitleParts.add('含软删除 ${scope.deletedCount} 项');
    }
    if (scope.teamCount > 0) {
      subtitleParts.add('团队数据 ${scope.teamCount} 项');
    }

    return ExpansionTile(
      key: PageStorageKey<ImportDataScope>(scope.scope),
      leading: Checkbox(
        value: scopeSelected,
        onChanged: (value) {
          final next = Set<ImportDataScope>.from(selectedScopes);
          if (value == true) {
            next.add(scope.scope);
          } else {
            next.remove(scope.scope);
          }
          onSelectionChanged(next);
        },
      ),
      title: Row(
        children: [
          Icon(scope.icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(scope.label)),
        ],
      ),
      subtitle: Text(subtitleParts.join(' · ')),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 52, right: 12, bottom: 12),
      children: [
        for (final type in scope.types)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(child: Text(type.label)),
                const SizedBox(width: 8),
                Text(
                  _typeCountSummary(type),
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: _onSurfaceVariant(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        if (scope.scope == ImportDataScope.productivity)
          _scopeHint(context, '任务、规划和专注记录合并选择，以保留它们之间的关联。'),
        if (scope.scope == ImportDataScope.finance)
          _scopeHint(context, '分类、付款方式、账单和计划作为一个完整记账数据域恢复。'),
        if (scope.scope == ImportDataScope.settings)
          _scopeHint(context, '会应用备份中的偏好设置；取消选择后当前设置保持不变。', warning: true),
      ],
    );
  }

  Widget _scopeHint(BuildContext context, String text, {bool warning = false}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: warning
                ? theme.colorScheme.tertiary
                : _onSurfaceVariant(context),
          ),
        ),
      ),
    );
  }

  String _typeCountSummary(ImportTypePreview type) {
    final parts = <String>['${type.count} 项'];
    if (type.deletedCount > 0) parts.add('删除 ${type.deletedCount}');
    if (type.teamCount > 0) parts.add('团队 ${type.teamCount}');
    return parts.join(' · ');
  }

  Color _onSurfaceVariant(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;
}
