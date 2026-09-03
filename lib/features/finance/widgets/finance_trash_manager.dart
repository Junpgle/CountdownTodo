import 'package:flutter/material.dart';

import '../services/finance_repository.dart';
import 'finance_management_widgets.dart';

enum FinanceTrashKind {
  transaction('账单', Icons.receipt_long_outlined),
  budget('预算', Icons.track_changes_outlined),
  loan('贷款', Icons.account_balance_outlined),
  rule('周期账单', Icons.event_repeat_outlined),
  template('快捷模板', Icons.bolt_outlined);

  final String label;
  final IconData icon;
  const FinanceTrashKind(this.label, this.icon);
}

class FinanceTrashEntry {
  final String uuid;
  final FinanceTrashKind kind;
  final String title;
  final String details;
  final String amountLabel;
  final int amountMinor;
  final Future<void> Function() onRestore;

  const FinanceTrashEntry({
    required this.uuid,
    required this.kind,
    required this.title,
    required this.details,
    required this.amountLabel,
    required this.amountMinor,
    required this.onRestore,
  });

  String get key => '${kind.name}-$uuid';
}

class FinanceTrashManager extends StatefulWidget {
  final List<FinanceTrashEntry> entries;

  const FinanceTrashManager({super.key, required this.entries});

  @override
  State<FinanceTrashManager> createState() => _FinanceTrashManagerState();
}

class _FinanceTrashManagerState extends State<FinanceTrashManager> {
  final _search = TextEditingController();
  final _restoring = <String>{};
  FinanceTrashKind? _kind;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _restore(FinanceTrashEntry entry) async {
    if (!_restoring.add(entry.key)) return;
    setState(() {});
    try {
      await entry.onRestore();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('恢复${entry.kind.label}失败：$error')));
      }
    } finally {
      _restoring.remove(entry.key);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final query = _search.text.trim().toLowerCase();
    final visible = widget.entries
        .where((entry) =>
            (_kind == null || entry.kind == _kind) &&
            (query.isEmpty ||
                '${entry.title} ${entry.details} ${entry.amountLabel} ${formatFinanceAmount(entry.amountMinor)}'
                    .toLowerCase()
                    .contains(query)))
        .toList();
    return FinancePageList(children: [
      const FinancePageIntro(
        icon: Icons.restore_from_trash_outlined,
        title: '找回需要的记录',
        description: '按类型或关键词查找，随时找回误删记录。',
      ),
      const SizedBox(height: 24),
      if (widget.entries.isEmpty)
        const FinanceEmptyState(
          icon: Icons.inventory_2_outlined,
          title: '回收站是空的',
          description: '删除的账单、预算、贷款和模板会保留在这里。',
        )
      else ...[
        TextField(
          key: const ValueKey('finance-trash-search'),
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: financeFieldDecoration(context,
                  label: '搜索名称、日期或备注', icon: Icons.search)
              .copyWith(
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: '清空搜索',
                    onPressed: () => setState(_search.clear),
                    icon: const Icon(Icons.close),
                  ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 6, children: [
          ChoiceChip(
            key: const ValueKey('finance-trash-filter-all'),
            label: Text('全部 ${widget.entries.length}'),
            selected: _kind == null,
            showCheckmark: false,
            onSelected: (_) => setState(() => _kind = null),
          ),
          for (final kind in FinanceTrashKind.values)
            if (_kind == kind ||
                widget.entries.any((entry) => entry.kind == kind))
              ChoiceChip(
                key: ValueKey('finance-trash-filter-${kind.name}'),
                label: Text(
                    '${kind.label} ${widget.entries.where((entry) => entry.kind == kind).length}'),
                selected: _kind == kind,
                showCheckmark: false,
                onSelected: (_) => setState(() => _kind = kind),
              ),
        ]),
        const SizedBox(height: 20),
        if (visible.isEmpty)
          FinanceEmptyState(
            icon: Icons.search_off_outlined,
            title: '没有找到匹配记录',
            description: '试试其他关键词，或查看全部类型。',
            actionLabel: '清除筛选',
            onAction: () => setState(() {
              _search.clear();
              _kind = null;
            }),
          ),
        for (final kind in FinanceTrashKind.values)
          if (visible.any((entry) => entry.kind == kind)) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                Icon(kind.icon, size: 20, color: colors.primary),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(kind.label,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700))),
                Text('${visible.where((entry) => entry.kind == kind).length} 项',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: colors.onSurfaceVariant)),
              ]),
            ),
            FinanceAdaptiveFields(
              minChildWidth: 330,
              children: [
                for (final entry
                    in visible.where((entry) => entry.kind == kind))
                  _entryCard(entry)
              ],
            ),
            const SizedBox(height: 24),
          ],
      ],
    ]);
  }

  Widget _entryCard(FinanceTrashEntry entry) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final restoring = _restoring.contains(entry.key);
    return FinanceSectionCard(
      key: ValueKey('finance-trash-item-${entry.key}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(entry.title,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(entry.details,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: colors.onSurfaceVariant, height: 1.5)),
        const SizedBox(height: 16),
        FinanceAdaptiveFields(
          minChildWidth: 150,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(entry.amountLabel,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: colors.onSurfaceVariant)),
              const SizedBox(height: 3),
              Text(formatFinanceAmount(entry.amountMinor),
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ]),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                key: ValueKey('finance-trash-restore-${entry.key}'),
                onPressed: restoring ? null : () => _restore(entry),
                icon: restoring
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.restore_rounded, size: 18),
                label: Text(restoring ? '恢复中…' : '恢复'),
              ),
            ),
          ],
        ),
      ]),
    );
  }
}
