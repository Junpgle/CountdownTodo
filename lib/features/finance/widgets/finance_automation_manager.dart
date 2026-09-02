import 'package:flutter/material.dart';

import '../../../widgets/floating_glass_control.dart';
import '../models/finance_models.dart';
import '../services/finance_repository.dart';
import 'finance_management_widgets.dart';

enum _AutomationTab { rules, templates }

enum _RuleFilter { all, enabled, paused }

class FinanceAutomationManager extends StatefulWidget {
  final List<FinanceRecurringRule> rules;
  final List<FinanceEntryTemplate> templates;
  final List<FinanceCategory> categories;
  final List<FinancePaymentMethod> paymentMethods;
  final Future<bool> Function() onAddRule;
  final Future<bool> Function() onAddTemplate;
  final Future<void> Function(FinanceRecurringRule) onEditRule;
  final Future<void> Function(FinanceRecurringRule, bool) onToggleRule;
  final Future<void> Function(FinanceRecurringRule) onDeleteRule;
  final Future<void> Function(FinanceEntryTemplate) onEditTemplate;
  final Future<void> Function(FinanceEntryTemplate) onUseTemplate;
  final Future<void> Function(FinanceEntryTemplate) onDeleteTemplate;

  const FinanceAutomationManager({
    super.key,
    required this.rules,
    required this.templates,
    required this.categories,
    required this.paymentMethods,
    required this.onAddRule,
    required this.onAddTemplate,
    required this.onEditRule,
    required this.onToggleRule,
    required this.onDeleteRule,
    required this.onEditTemplate,
    required this.onUseTemplate,
    required this.onDeleteTemplate,
  });

  @override
  State<FinanceAutomationManager> createState() =>
      _FinanceAutomationManagerState();
}

class _FinanceAutomationManagerState extends State<FinanceAutomationManager> {
  final _search = TextEditingController();
  final _busy = <String>{};
  _AutomationTab _tab = _AutomationTab.rules;
  _RuleFilter _filter = _RuleFilter.all;

  bool get _isRules => _tab == _AutomationTab.rules;
  List<FinanceRecurringRule> get _rules =>
      widget.rules.where((rule) => !rule.isDeleted).toList();
  List<FinanceEntryTemplate> get _templates =>
      widget.templates.where((template) => !template.isDeleted).toList();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _run(String key, Future<void> Function() action) async {
    if (!_busy.add(key)) return;
    setState(() {});
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('操作失败：$error')));
      }
    } finally {
      _busy.remove(key);
      if (mounted) setState(() {});
    }
  }

  Future<void> _add() => _run('add', () async {
        final tab = _tab;
        final saved =
            _isRules ? await widget.onAddRule() : await widget.onAddTemplate();
        if (saved && mounted) {
          setState(() {
            _tab = tab;
            _filter = _RuleFilter.all;
            _search.clear();
          });
        }
      });

  String _categoryName(String? uuid) {
    for (final category in widget.categories) {
      if (category.uuid == uuid) return '${category.icon} ${category.name}';
    }
    return uuid == null ? '未指定分类' : '已归档或未知分类';
  }

  String _paymentName(String? uuid) {
    for (final method in widget.paymentMethods) {
      if (method.uuid == uuid) return method.name;
    }
    return '';
  }

  bool _matches(String name, String? merchant, String? note, String? category) {
    final query = _search.text.trim().toLowerCase();
    return query.isEmpty ||
        [name, merchant, note, _categoryName(category)]
            .whereType<String>()
            .join(' ')
            .toLowerCase()
            .contains(query);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final rules = _rules
        .where((rule) =>
            (_filter == _RuleFilter.all ||
                rule.isEnabled == (_filter == _RuleFilter.enabled)) &&
            _matches(rule.name, rule.merchant, rule.note, rule.categoryUuid))
        .toList();
    final templates = _templates
        .where((template) => _matches(template.name, template.merchant,
            template.note, template.categoryUuid))
        .toList();
    final count = _isRules ? rules.length : templates.length;
    final total = _isRules ? _rules.length : _templates.length;
    final filtered = _search.text.trim().isNotEmpty ||
        (_isRules && _filter != _RuleFilter.all);

    return FinancePageList(children: [
      const FinancePageIntro(
        icon: Icons.auto_awesome_outlined,
        title: '让记账少一步',
        description: '固定账单按期安排，常用账单一键填入。',
      ),
      const SizedBox(height: 24),
      LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final showIcons = constraints.maxWidth > 360 &&
            MediaQuery.textScalerOf(context).scale(14) <= 20;
        final tabs = SegmentedButton<_AutomationTab>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: _AutomationTab.rules,
              icon: showIcons ? const Icon(Icons.event_repeat_outlined) : null,
              label: const Text('周期账单',
                  key: ValueKey('finance-automation-tab-rules')),
            ),
            ButtonSegment(
              value: _AutomationTab.templates,
              icon: showIcons ? const Icon(Icons.bolt_outlined) : null,
              label: const Text('快捷模板',
                  key: ValueKey('finance-automation-tab-templates')),
            ),
          ],
          selected: {_tab},
          onSelectionChanged: (selection) {
            FocusScope.of(context).unfocus();
            setState(() {
              _tab = selection.single;
              _filter = _RuleFilter.all;
              _search.clear();
            });
          },
        );
        if (compact) return tabs;
        return Row(children: [
          Expanded(child: tabs),
          const SizedBox(width: 16),
          _addButton(),
        ]);
      }),
      const SizedBox(height: 16),
      TextField(
        key: const ValueKey('finance-automation-search'),
        controller: _search,
        onChanged: (_) => setState(() {}),
        decoration: financeFieldDecoration(context,
                label: _isRules ? '搜索周期账单' : '搜索快捷模板', icon: Icons.search)
            .copyWith(
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空搜索',
                        onPressed: () => setState(_search.clear),
                        icon: const Icon(Icons.close),
                      )),
      ),
      if (_isRules) ...[
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final filter in _RuleFilter.values)
            ChoiceChip(
              key: ValueKey('finance-automation-filter-${filter.name}'),
              label: Text(switch (filter) {
                _RuleFilter.all => '全部 ${_rules.length}',
                _RuleFilter.enabled =>
                  '已启用 ${_rules.where((rule) => rule.isEnabled).length}',
                _RuleFilter.paused =>
                  '已暂停 ${_rules.where((rule) => !rule.isEnabled).length}',
              }),
              selected: _filter == filter,
              onSelected: (_) => setState(() => _filter = filter),
              showCheckmark: false,
            ),
        ]),
      ],
      const SizedBox(height: 18),
      LayoutBuilder(builder: (context, constraints) {
        final summary = Text(
            filtered
                ? '找到 $count 个结果'
                : '共 $count 个${_isRules ? '周期账单' : '快捷模板'}',
            style: theme.textTheme.labelLarge
                ?.copyWith(color: colors.onSurfaceVariant));
        if (constraints.maxWidth >= 600) return summary;
        return Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [summary, _addButton(compact: true)],
        );
      }),
      const SizedBox(height: 10),
      if (count == 0)
        FinanceEmptyState(
          icon: filtered
              ? Icons.search_off_outlined
              : (_isRules ? Icons.event_repeat_outlined : Icons.bolt_outlined),
          title: filtered ? '没有找到匹配项目' : (_isRules ? '安排第一笔周期账单' : '保存常用的一笔'),
          description: filtered
              ? '试试其他关键词，或清除筛选条件。'
              : (_isRules ? '房租、订阅或工资，不用每次重新填写。' : '早餐、通勤、日常消费，下次记账更快。'),
          actionLabel: filtered ? '清除筛选' : '立即新增',
          onAction: filtered
              ? () => setState(() {
                    _search.clear();
                    _filter = _RuleFilter.all;
                  })
              : (_busy.contains('add') ? null : _add),
        )
      else
        FinanceAdaptiveFields(
          minChildWidth: 330,
          children: _isRules
              ? [for (final rule in rules) _ruleCard(rule)]
              : [for (final template in templates) _templateCard(template)],
        ),
      if (_isRules && total > 0) ...[
        const SizedBox(height: 16),
        Text('暂停的规则不会自动记账或发送提醒，可随时重新启用。',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: colors.onSurfaceVariant)),
      ],
    ]);
  }

  Widget _addButton({bool compact = false}) {
    return FilledButton.icon(
      key: const ValueKey('finance-automation-add'),
      onPressed: _busy.contains('add') ? null : _add,
      icon: const Icon(Icons.add),
      label: Text(compact ? '新增' : (_isRules ? '新增周期账单' : '新增模板')),
    );
  }

  Widget _heading(String name, IconData icon, String busyKey,
      VoidCallback onEdit, VoidCallback onDelete) {
    final colors = Theme.of(context).colorScheme;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
            color: colors.secondaryContainer,
            borderRadius: BorderRadius.circular(13)),
        child: Icon(icon, size: 21, color: colors.onSecondaryContainer),
      ),
      const SizedBox(width: 12),
      Expanded(
          child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(name,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
      )),
      PopupMenuButton<String>(
        tooltip: '$name 的更多操作',
        enabled: !_busy.contains(busyKey),
        onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('编辑')),
          PopupMenuItem(value: 'delete', child: Text('移入回收站')),
        ],
      ),
    ]);
  }

  Widget _amount(int amount, FinanceTransactionType type) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(formatFinanceAmount(amount),
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            FinanceStatusBadge(label: type.label),
          ]),
    );
  }

  Widget _metadata(String? category, String? payment, {String? extra}) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
          [
            _categoryName(category),
            if (_paymentName(payment).isNotEmpty) _paymentName(payment),
            if (extra != null) extra,
          ].join(' · '),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5)),
    );
  }

  Widget _ruleCard(FinanceRecurringRule rule) {
    final key = 'rule-${rule.uuid}';
    final busy = _busy.contains(key);
    void edit() => _run(key, () => widget.onEditRule(rule));
    final schedule = rule.frequency == FinanceRecurringFrequency.yearly
        ? '每年 ${rule.monthOfYear} 月 ${rule.dayOfMonth} 日'
        : '每月 ${rule.dayOfMonth} 日';
    return FinanceSectionCard(
      key: ValueKey('finance-automation-rule-${rule.uuid}'),
      onTap: busy ? null : edit,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _heading(rule.name, Icons.event_repeat_outlined, key, edit,
            () => _run(key, () => widget.onDeleteRule(rule))),
        _amount(rule.amountMinor, rule.type),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FinanceStatusBadge(
              label: schedule, icon: Icons.calendar_today_outlined),
          FinanceStatusBadge(
              label: rule.autoGenerate
                  ? '自动记账'
                  : rule.reminderMinutes > 0
                      ? '仅提醒'
                      : '手动记账',
              icon: rule.autoGenerate
                  ? Icons.autorenew
                  : rule.reminderMinutes > 0
                      ? Icons.notifications_none
                      : Icons.edit_outlined,
              highlighted: rule.isEnabled),
        ]),
        _metadata(rule.categoryUuid, rule.paymentMethodUuid,
            extra: rule.endDate == null ? null : '至 ${rule.endDate}'),
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1)),
        Row(children: [
          Expanded(
              child: Text(rule.isEnabled ? '已启用' : '已暂停',
                  style: Theme.of(context).textTheme.labelLarge)),
          Semantics(
            label: '${rule.isEnabled ? '暂停' : '启用'}${rule.name}',
            child: LiquidGlassSwitch(
              key: ValueKey('finance-automation-toggle-${rule.uuid}'),
              value: rule.isEnabled,
              onChanged: busy
                  ? null
                  : (value) =>
                      _run(key, () => widget.onToggleRule(rule, value)),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            key: ValueKey('finance-automation-edit-${rule.uuid}'),
            onPressed: busy ? null : edit,
            child: const Text('编辑'),
          ),
        ]),
      ]),
    );
  }

  Widget _templateCard(FinanceEntryTemplate template) {
    final key = 'template-${template.uuid}';
    final busy = _busy.contains(key);
    void edit() => _run(key, () => widget.onEditTemplate(template));
    void use() => _run(key, () => widget.onUseTemplate(template));
    return FinanceSectionCard(
      key: ValueKey('finance-automation-template-${template.uuid}'),
      onTap: busy ? null : use,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _heading(template.name, Icons.bolt_outlined, key, edit,
            () => _run(key, () => widget.onDeleteTemplate(template))),
        _amount(template.amountMinor, template.type),
        _metadata(template.categoryUuid, template.paymentMethodUuid),
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1)),
        Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonalIcon(
                key: ValueKey('finance-automation-use-${template.uuid}'),
                onPressed: busy ? null : use,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('记一笔'),
              ),
              TextButton(
                  onPressed: busy ? null : edit, child: const Text('编辑')),
              Text('已使用 ${template.useCount} 次',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),
      ]),
    );
  }
}
