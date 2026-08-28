import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/finance_models.dart';
import '../services/finance_repository.dart';
import '../../../services/reminder_schedule_service.dart';
import 'finance_entry_screen.dart';

/// 周期账单和快捷记账模板管理。
class FinanceAutomationScreen extends StatefulWidget {
  const FinanceAutomationScreen({super.key});

  @override
  State<FinanceAutomationScreen> createState() =>
      _FinanceAutomationScreenState();
}

class _FinanceAutomationScreenState extends State<FinanceAutomationScreen> {
  List<FinanceRecurringRule> _rules = const [];
  List<FinanceEntryTemplate> _templates = const [];
  List<FinanceCategory> _categories = const [];
  List<FinancePaymentMethod> _paymentMethods = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait<dynamic>([
        FinanceRepository.getRecurringRules(),
        FinanceRepository.getTemplates(),
        FinanceRepository.getCategories(includeArchived: true),
        FinanceRepository.getPaymentMethods(includeArchived: true),
      ]);
      if (!mounted) return;
      setState(() {
        _rules = values[0] as List<FinanceRecurringRule>;
        _templates = values[1] as List<FinanceEntryTemplate>;
        _categories = values[2] as List<FinanceCategory>;
        _paymentMethods = values[3] as List<FinancePaymentMethod>;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showMessage('自动化数据加载失败：$error');
    }
  }

  Future<void> _addRule() async {
    final rule = await _showRuleEditor();
    if (rule == null) return;
    await _saveRule(rule);
  }

  Future<void> _editRule(FinanceRecurringRule rule) async {
    final edited = await _showRuleEditor(rule: rule);
    if (edited == null) return;
    await _saveRule(edited);
  }

  Future<void> _saveRule(FinanceRecurringRule rule) async {
    try {
      await FinanceRepository.saveRecurringRule(rule);
      await _rescheduleReminders();
      await _load();
    } catch (error) {
      _showMessage('保存周期账单失败：$error');
    }
  }

  Future<void> _toggleRule(FinanceRecurringRule rule, bool enabled) async {
    try {
      await FinanceRepository.setRecurringRuleEnabled(rule.uuid, enabled);
      await _rescheduleReminders();
      await _load();
    } catch (error) {
      _showMessage('更新周期账单失败：$error');
    }
  }

  Future<void> _deleteRule(FinanceRecurringRule rule) async {
    if (!await _confirm('删除周期账单', '删除后不会再提醒或自动记账，可以在回收站恢复。')) {
      return;
    }
    await FinanceRepository.deleteRecurringRule(rule.uuid);
    await _rescheduleReminders();
    await _load();
  }

  Future<void> _rescheduleReminders() async {
    try {
      await ReminderScheduleService.scheduleCurrentUser();
    } catch (_) {
      // 系统提醒不可用不应影响规则本身的保存。
    }
  }

  Future<void> _addTemplate() async {
    final template = await _showTemplateEditor();
    if (template == null) return;
    await _saveTemplate(template);
  }

  Future<void> _editTemplate(FinanceEntryTemplate template) async {
    final edited = await _showTemplateEditor(template: template);
    if (edited == null) return;
    await _saveTemplate(edited);
  }

  Future<void> _saveTemplate(FinanceEntryTemplate template) async {
    try {
      await FinanceRepository.saveTemplate(template);
      await _load();
    } catch (error) {
      _showMessage('保存快捷模板失败：$error');
    }
  }

  Future<void> _useTemplate(FinanceEntryTemplate template) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FinanceEntryScreen(initialTemplate: template),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _deleteTemplate(FinanceEntryTemplate template) async {
    if (!await _confirm('删除快捷模板', '删除后可以在记账回收站恢复。')) return;
    await FinanceRepository.deleteTemplate(template.uuid);
    await _load();
  }

  Future<FinanceRecurringRule?> _showRuleEditor({
    FinanceRecurringRule? rule,
  }) async {
    final nameController = TextEditingController(text: rule?.name ?? '');
    final amountController = TextEditingController(
      text: rule == null
          ? ''
          : formatFinanceAmount(rule.amountMinor, withSymbol: false),
    );
    final merchantController =
        TextEditingController(text: rule?.merchant ?? '');
    final noteController = TextEditingController(text: rule?.note ?? '');
    final dayController =
        TextEditingController(text: '${rule?.dayOfMonth ?? 1}');
    final monthController =
        TextEditingController(text: '${rule?.monthOfYear ?? 1}');
    final startDateController = TextEditingController(
      text: rule?.startDate ?? dateKey(DateTime.now()),
    );
    final endDateController = TextEditingController(text: rule?.endDate ?? '');
    var type = rule?.type ?? FinanceTransactionType.expense;
    var frequency = rule?.frequency ?? FinanceRecurringFrequency.monthly;
    var categoryUuid = rule?.categoryUuid;
    var paymentMethodUuid = rule?.paymentMethodUuid;
    var reminderMinutes = rule?.reminderMinutes ?? 1440;
    var autoGenerate = rule?.autoGenerate ?? true;
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<FinanceRecurringRule>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final categoryItems = _categories
              .where(
                (item) =>
                    !item.isDeleted &&
                    !item.isArchived &&
                    item.type ==
                        (type == FinanceTransactionType.income
                            ? FinanceCategoryType.income
                            : FinanceCategoryType.expense),
              )
              .toList();
          final categoryValue = categoryItems.any(
            (item) => item.uuid == categoryUuid,
          )
              ? categoryUuid
              : null;
          final paymentItems = _paymentMethods
              .where((item) => !item.isDeleted && !item.isArchived)
              .toList();
          final paymentValue = paymentItems.any(
            (item) => item.uuid == paymentMethodUuid,
          )
              ? paymentMethodUuid
              : null;
          final reminderValues = <int>{0, 60, 1440, 2880, 10080}
            ..add(reminderMinutes);
          return AlertDialog(
            title: Text(rule == null ? '新增周期账单' : '编辑周期账单'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameController,
                        autofocus: rule == null,
                        decoration: const InputDecoration(
                          labelText: '名称',
                          hintText: '例如：房租、会员订阅',
                        ),
                        maxLength: 60,
                        validator: (value) =>
                            value?.trim().isEmpty == true ? '请输入名称' : null,
                      ),
                      TextFormField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        decoration: const InputDecoration(
                          labelText: '金额',
                          prefixText: '¥ ',
                        ),
                        validator: (value) =>
                            parseFinanceAmount(value ?? '') == null
                                ? '请输入金额'
                                : null,
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<FinanceTransactionType>(
                        initialValue: type,
                        decoration: const InputDecoration(labelText: '类型'),
                        items: const [
                          DropdownMenuItem(
                            value: FinanceTransactionType.expense,
                            child: Text('支出'),
                          ),
                          DropdownMenuItem(
                            value: FinanceTransactionType.income,
                            child: Text('收入'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            type = value;
                            categoryUuid = null;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: categoryValue,
                        decoration: const InputDecoration(labelText: '分类'),
                        items: [
                          for (final category in categoryItems)
                            DropdownMenuItem(
                              value: category.uuid,
                              child: Text('${category.icon}  ${category.name}'),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => categoryUuid = value),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: paymentValue,
                        decoration:
                            const InputDecoration(labelText: '付款方式（可选）'),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('未指定'),
                          ),
                          for (final payment in paymentItems)
                            DropdownMenuItem(
                              value: payment.uuid,
                              child: Text('${payment.icon}  ${payment.name}'),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => paymentMethodUuid = value),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<FinanceRecurringFrequency>(
                        initialValue: frequency,
                        decoration: const InputDecoration(labelText: '重复频率'),
                        items: [
                          for (final value in FinanceRecurringFrequency.values)
                            DropdownMenuItem(
                              value: value,
                              child: Text(value.label),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => frequency = value);
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: dayController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                labelText: '日期',
                                suffixText: '日',
                              ),
                              validator: (value) {
                                final day = int.tryParse(value ?? '');
                                return day == null || day < 1 || day > 31
                                    ? '1-31'
                                    : null;
                              },
                            ),
                          ),
                          if (frequency ==
                              FinanceRecurringFrequency.yearly) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: monthController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: const InputDecoration(
                                  labelText: '月份',
                                  suffixText: '月',
                                ),
                                validator: (value) {
                                  final month = int.tryParse(value ?? '');
                                  return month == null ||
                                          month < 1 ||
                                          month > 12
                                      ? '1-12'
                                      : null;
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: startDateController,
                        decoration: const InputDecoration(
                          labelText: '开始日期',
                          hintText: 'YYYY-MM-DD',
                        ),
                        validator: (value) =>
                            _validDateKey(value) ? null : '日期格式无效',
                      ),
                      TextFormField(
                        controller: endDateController,
                        decoration: const InputDecoration(
                          labelText: '结束日期（可选）',
                          hintText: 'YYYY-MM-DD',
                        ),
                        validator: (value) {
                          if (value?.trim().isEmpty == true) return null;
                          return _validDateKey(value) ? null : '日期格式无效';
                        },
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        initialValue: reminderMinutes,
                        decoration: const InputDecoration(labelText: '提前提醒'),
                        items: [
                          for (final minutes
                              in (reminderValues.toList()..sort()))
                            DropdownMenuItem(
                              value: minutes,
                              child: Text(_reminderLabel(minutes)),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => reminderMinutes = value);
                          }
                        },
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('到期自动记账'),
                        subtitle: const Text('关闭后只提醒，不会自动产生账单'),
                        value: autoGenerate,
                        onChanged: (value) =>
                            setState(() => autoGenerate = value),
                      ),
                      TextFormField(
                        controller: merchantController,
                        decoration: const InputDecoration(labelText: '商家（可选）'),
                        maxLength: 80,
                      ),
                      TextFormField(
                        controller: noteController,
                        decoration: const InputDecoration(labelText: '备注（可选）'),
                        maxLines: 2,
                        maxLength: 200,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  if (!formKey.currentState!.validate()) return;
                  final amount = parseFinanceAmount(amountController.text);
                  final day = int.tryParse(dayController.text);
                  final month = int.tryParse(monthController.text);
                  if (amount == null || day == null || month == null) return;
                  final editedRule = FinanceRecurringRule(
                    uuid: rule?.uuid,
                    name: nameController.text.trim(),
                    type: type,
                    amountMinor: amount,
                    categoryUuid: categoryUuid,
                    paymentMethodUuid: paymentMethodUuid,
                    merchant: _emptyToNull(merchantController.text),
                    note: _emptyToNull(noteController.text),
                    frequency: frequency,
                    dayOfMonth: day,
                    monthOfYear: month,
                    startDate: startDateController.text.trim(),
                    endDate: _emptyToNull(endDateController.text),
                    reminderMinutes: reminderMinutes,
                    autoGenerate: autoGenerate,
                    isEnabled: rule?.isEnabled ?? true,
                    isDeleted: false,
                    lastGeneratedPeriod: rule?.lastGeneratedPeriod,
                    version: rule?.version ?? 1,
                    createdAt: rule?.createdAt,
                    updatedAt: rule?.updatedAt,
                    deviceId: rule?.deviceId,
                  );
                  if (rule != null) editedRule.markAsChanged();
                  Navigator.pop(dialogContext, editedRule);
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
    nameController.dispose();
    amountController.dispose();
    merchantController.dispose();
    noteController.dispose();
    dayController.dispose();
    monthController.dispose();
    startDateController.dispose();
    endDateController.dispose();
    return result;
  }

  Future<FinanceEntryTemplate?> _showTemplateEditor({
    FinanceEntryTemplate? template,
  }) async {
    final nameController = TextEditingController(text: template?.name ?? '');
    final amountController = TextEditingController(
      text: template == null
          ? ''
          : formatFinanceAmount(template.amountMinor, withSymbol: false),
    );
    final merchantController =
        TextEditingController(text: template?.merchant ?? '');
    final noteController = TextEditingController(text: template?.note ?? '');
    var type = template?.type ?? FinanceTransactionType.expense;
    var categoryUuid = template?.categoryUuid;
    var paymentMethodUuid = template?.paymentMethodUuid;
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<FinanceEntryTemplate>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final categoryItems = _categories
              .where(
                (item) =>
                    !item.isDeleted &&
                    !item.isArchived &&
                    item.type ==
                        (type == FinanceTransactionType.income
                            ? FinanceCategoryType.income
                            : FinanceCategoryType.expense),
              )
              .toList();
          final categoryValue = categoryItems.any(
            (item) => item.uuid == categoryUuid,
          )
              ? categoryUuid
              : null;
          final paymentItems = _paymentMethods
              .where((item) => !item.isDeleted && !item.isArchived)
              .toList();
          final paymentValue = paymentItems.any(
            (item) => item.uuid == paymentMethodUuid,
          )
              ? paymentMethodUuid
              : null;
          return AlertDialog(
            title: Text(template == null ? '新增快捷模板' : '编辑快捷模板'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameController,
                        autofocus: template == null,
                        decoration: const InputDecoration(
                          labelText: '模板名称',
                          hintText: '例如：早餐、地铁、月薪',
                        ),
                        maxLength: 60,
                        validator: (value) =>
                            value?.trim().isEmpty == true ? '请输入模板名称' : null,
                      ),
                      TextFormField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        decoration: const InputDecoration(
                          labelText: '默认金额',
                          prefixText: '¥ ',
                        ),
                        validator: (value) =>
                            parseFinanceAmount(value ?? '') == null
                                ? '请输入金额'
                                : null,
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<FinanceTransactionType>(
                        initialValue: type,
                        decoration: const InputDecoration(labelText: '类型'),
                        items: const [
                          DropdownMenuItem(
                            value: FinanceTransactionType.expense,
                            child: Text('支出'),
                          ),
                          DropdownMenuItem(
                            value: FinanceTransactionType.income,
                            child: Text('收入'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            type = value;
                            categoryUuid = null;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: categoryValue,
                        decoration: const InputDecoration(labelText: '分类'),
                        items: [
                          for (final category in categoryItems)
                            DropdownMenuItem(
                              value: category.uuid,
                              child: Text('${category.icon}  ${category.name}'),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => categoryUuid = value),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: paymentValue,
                        decoration:
                            const InputDecoration(labelText: '付款方式（可选）'),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('未指定'),
                          ),
                          for (final payment in paymentItems)
                            DropdownMenuItem(
                              value: payment.uuid,
                              child: Text('${payment.icon}  ${payment.name}'),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => paymentMethodUuid = value),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: merchantController,
                        decoration: const InputDecoration(labelText: '商家（可选）'),
                        maxLength: 80,
                      ),
                      TextFormField(
                        controller: noteController,
                        decoration: const InputDecoration(labelText: '备注（可选）'),
                        maxLines: 2,
                        maxLength: 200,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  if (!formKey.currentState!.validate()) return;
                  final amount = parseFinanceAmount(amountController.text);
                  if (amount == null) return;
                  final editedTemplate = FinanceEntryTemplate(
                    uuid: template?.uuid,
                    name: nameController.text.trim(),
                    type: type,
                    amountMinor: amount,
                    categoryUuid: categoryUuid,
                    paymentMethodUuid: paymentMethodUuid,
                    merchant: _emptyToNull(merchantController.text),
                    note: _emptyToNull(noteController.text),
                    useCount: template?.useCount ?? 0,
                    lastUsedAt: template?.lastUsedAt,
                    isDeleted: false,
                    version: template?.version ?? 1,
                    createdAt: template?.createdAt,
                    updatedAt: template?.updatedAt,
                    deviceId: template?.deviceId,
                  );
                  if (template != null) editedTemplate.markAsChanged();
                  Navigator.pop(dialogContext, editedTemplate);
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
    nameController.dispose();
    amountController.dispose();
    merchantController.dispose();
    noteController.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('记账自动化'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSectionHeader(
                    title: '周期账单',
                    subtitle: '房租、订阅、工资等可按月或按年提醒，并可到期自动记账',
                    icon: Icons.autorenew_outlined,
                    onAdd: _addRule,
                    colorScheme: colorScheme,
                  ),
                  if (_rules.isEmpty) _buildEmpty('还没有周期账单，点击右上角新增'),
                  for (final rule in _rules) _buildRuleTile(rule),
                  const SizedBox(height: 28),
                  _buildSectionHeader(
                    title: '快捷模板',
                    subtitle: '把常用账单保存下来，记一笔时一键填充',
                    icon: Icons.flash_on_outlined,
                    onAdd: _addTemplate,
                    colorScheme: colorScheme,
                  ),
                  if (_templates.isEmpty) _buildEmpty('还没有快捷模板，点击右上角新增'),
                  for (final template in _templates)
                    _buildTemplateTile(template),
                  const SizedBox(height: 16),
                  Card(
                    child: ListTile(
                      leading: Icon(Icons.keyboard_outlined,
                          color: colorScheme.primary),
                      title: const Text('桌面端快捷记账'),
                      subtitle:
                          const Text('在记账首页按 Ctrl/Cmd + Shift + N 快速打开录入页'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildRuleTile(FinanceRecurringRule rule) {
    final schedule = rule.frequency == FinanceRecurringFrequency.yearly
        ? '每年 ${rule.monthOfYear} 月 ${rule.dayOfMonth} 日'
        : '每月 ${rule.dayOfMonth} 日';
    final end = rule.endDate == null ? '' : ' · 至 ${rule.endDate}';
    return Card(
      child: ListTile(
        leading: Icon(
          rule.autoGenerate ? Icons.autorenew : Icons.notifications_none,
        ),
        title: Text(rule.name),
        subtitle: Text(
          '$schedule$end · ${formatFinanceAmount(rule.amountMinor)}'
          '${rule.autoGenerate ? ' · 自动记账' : ' · 仅提醒'}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch.adaptive(
              value: rule.isEnabled,
              onChanged: (value) => _toggleRule(rule, value),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') _editRule(rule);
                if (value == 'delete') _deleteRule(rule);
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('编辑')),
                PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplateTile(FinanceEntryTemplate template) {
    return Card(
      child: ListTile(
        leading: Icon(
          template.type == FinanceTransactionType.income
              ? Icons.arrow_downward_rounded
              : Icons.arrow_upward_rounded,
        ),
        title: Text(template.name),
        subtitle: Text(
          '${template.type.label} · ${formatFinanceAmount(template.amountMinor)}'
          '${template.useCount == 0 ? '' : ' · 使用 ${template.useCount} 次'}',
        ),
        onTap: () => _useTemplate(template),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'use') _useTemplate(template);
            if (value == 'edit') _editTemplate(template);
            if (value == 'delete') _deleteTemplate(template);
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'use', child: Text('使用')),
            PopupMenuItem(value: 'edit', child: Text('编辑')),
            PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onAdd,
    required ColorScheme colorScheme,
  }) {
    return Row(
      children: [
        Icon(icon, color: colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '新增',
          onPressed: onAdd,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }

  Widget _buildEmpty(String message) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(child: Text(message)),
      ),
    );
  }

  Future<bool> _confirm(String title, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  static bool _validDateKey(String? value) {
    final text = value?.trim() ?? '';
    final parsed = DateTime.tryParse(text);
    return parsed != null && dateKey(parsed) == text;
  }

  static String? _emptyToNull(String value) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  static String _reminderLabel(int minutes) {
    if (minutes == 0) return '不提醒';
    if (minutes % 1440 == 0) return '提前 ${minutes ~/ 1440} 天';
    return '提前 $minutes 分钟';
  }
}
