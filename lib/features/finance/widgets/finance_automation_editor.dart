import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../widgets/floating_glass_control.dart';
import '../models/finance_models.dart';
import '../services/finance_repository.dart';
import 'finance_management_widgets.dart';

/// The dialog owns its controllers and keeps the draft open if saving fails.
class FinanceAutomationEditor extends StatefulWidget {
  final FinanceRecurringRule? rule;
  final FinanceEntryTemplate? template;
  final List<FinanceCategory> categories;
  final List<FinancePaymentMethod> paymentMethods;
  final Future<void> Function(FinanceRecurringRule)? onSaveRule;
  final Future<void> Function(FinanceEntryTemplate)? onSaveTemplate;

  const FinanceAutomationEditor.rule({
    super.key,
    this.rule,
    required this.categories,
    required this.paymentMethods,
    required Future<void> Function(FinanceRecurringRule) onSave,
  })  : template = null,
        onSaveRule = onSave,
        onSaveTemplate = null;

  const FinanceAutomationEditor.template({
    super.key,
    this.template,
    required this.categories,
    required this.paymentMethods,
    required Future<void> Function(FinanceEntryTemplate) onSave,
  })  : rule = null,
        onSaveTemplate = onSave,
        onSaveRule = null;

  @override
  State<FinanceAutomationEditor> createState() =>
      _FinanceAutomationEditorState();
}

class _FinanceAutomationEditorState extends State<FinanceAutomationEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late final TextEditingController _merchant;
  late final TextEditingController _note;
  late final TextEditingController _day;
  late final TextEditingController _month;
  late final TextEditingController _start;
  late final TextEditingController _end;
  late FinanceTransactionType _type;
  late FinanceRecurringFrequency _frequency;
  String? _categoryUuid;
  String? _paymentUuid;
  late int _reminderMinutes;
  late bool _autoGenerate;
  bool _isSaving = false;
  String? _saveError;

  bool get _isRule => widget.onSaveRule != null;
  bool get _isEditing => widget.rule != null || widget.template != null;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    final template = widget.template;
    _name = TextEditingController(text: rule?.name ?? template?.name ?? '');
    final amount = rule?.amountMinor ?? template?.amountMinor;
    _amount = TextEditingController(
        text: amount == null
            ? ''
            : formatFinanceAmount(amount, withSymbol: false));
    _merchant =
        TextEditingController(text: rule?.merchant ?? template?.merchant ?? '');
    _note = TextEditingController(text: rule?.note ?? template?.note ?? '');
    _day = TextEditingController(text: '${rule?.dayOfMonth ?? 1}');
    _month = TextEditingController(text: '${rule?.monthOfYear ?? 1}');
    _start =
        TextEditingController(text: rule?.startDate ?? dateKey(DateTime.now()));
    _end = TextEditingController(text: rule?.endDate ?? '');
    _type = rule?.type ?? template?.type ?? FinanceTransactionType.expense;
    _frequency = rule?.frequency ?? FinanceRecurringFrequency.monthly;
    _categoryUuid = rule?.categoryUuid ?? template?.categoryUuid;
    _paymentUuid = rule?.paymentMethodUuid ?? template?.paymentMethodUuid;
    _reminderMinutes = rule?.reminderMinutes ?? 1440;
    _autoGenerate = rule?.autoGenerate ?? true;
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _amount,
      _merchant,
      _note,
      _day,
      _month,
      _start,
      _end
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isSaving = true;
      _saveError = null;
    });
    try {
      final amount = parseFinanceAmount(_amount.text)!;
      if (_isRule) {
        final old = widget.rule;
        final result = old == null
            ? FinanceRecurringRule(
                name: _name.text.trim(),
                amountMinor: amount,
                startDate: _start.text.trim())
            : FinanceRecurringRule.fromMap(old.toMap());
        result
          ..name = _name.text.trim()
          ..amountMinor = amount
          ..type = _type
          ..categoryUuid = _categoryUuid
          ..paymentMethodUuid = _paymentUuid
          ..merchant = _emptyToNull(_merchant.text)
          ..note = _emptyToNull(_note.text)
          ..frequency = _frequency
          ..dayOfMonth = int.parse(_day.text.trim())
          ..monthOfYear = int.tryParse(_month.text.trim()) ?? 1
          ..startDate = _start.text.trim()
          ..endDate = _emptyToNull(_end.text)
          ..reminderMinutes = _reminderMinutes
          ..autoGenerate = _autoGenerate;
        if (old != null) result.markAsChanged();
        await widget.onSaveRule!(result);
      } else {
        final old = widget.template;
        final result = old == null
            ? FinanceEntryTemplate(name: _name.text.trim(), amountMinor: amount)
            : FinanceEntryTemplate.fromMap(old.toMap());
        result
          ..name = _name.text.trim()
          ..amountMinor = amount
          ..type = _type
          ..categoryUuid = _categoryUuid
          ..paymentMethodUuid = _paymentUuid
          ..merchant = _emptyToNull(_merchant.text)
          ..note = _emptyToNull(_note.text);
        if (old != null) result.markAsChanged();
        await widget.onSaveTemplate!(result);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      debugPrint('记账自动化保存失败：$error');
      if (mounted) {
        setState(() {
          _isSaving = false;
          _saveError = '保存失败，填写的内容已保留，请重试';
        });
      }
    }
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final current = DateTime.tryParse(controller.text.trim()) ??
        DateTime.tryParse(_start.text.trim()) ??
        DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year < 2000 ? current.year : 2000),
      lastDate: DateTime(current.year > 2100 ? current.year : 2100, 12, 31),
      helpText: controller == _start ? '选择开始日期' : '选择结束日期',
    );
    if (picked != null && mounted) {
      setState(() => controller.text = dateKey(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_isSaving,
      child: FinanceEditorDialog(
        title: Text('${_isEditing ? '编辑' : '新增'}${_isRule ? '周期账单' : '快捷模板'}'),
        content: SizedBox(
          width: 560,
          child: AbsorbPointer(
            absorbing: _isSaving,
            child: Form(
              key: _formKey,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FinanceSectionCard(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(spacing: 8, runSpacing: 4, children: [
                              for (final type in [
                                FinanceTransactionType.expense,
                                FinanceTransactionType.income
                              ])
                                ChoiceChip(
                                  key: ValueKey(
                                      'finance-automation-type-${type.name}'),
                                  selected: _type == type,
                                  label: Text(type.label),
                                  showCheckmark: false,
                                  avatar: Icon(
                                      type == FinanceTransactionType.expense
                                          ? Icons.north_east_rounded
                                          : Icons.south_west_rounded,
                                      size: 17),
                                  onSelected: (_) => setState(() {
                                    if (_type != type) _categoryUuid = null;
                                    _type = type;
                                  }),
                                ),
                            ]),
                            const SizedBox(height: 16),
                            TextFormField(
                              key: const ValueKey('finance-automation-name'),
                              controller: _name,
                              maxLength: 60,
                              textInputAction: TextInputAction.next,
                              decoration: financeFieldDecoration(context,
                                      label: _isRule ? '账单名称' : '模板名称',
                                      hint:
                                          _isRule ? '例如：每月房租、会员订阅' : '例如：工作日早餐')
                                  .copyWith(counterText: ''),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                      ? '请填写名称'
                                      : null,
                            ),
                            const SizedBox(height: 16),
                            FinanceAmountField(
                                key:
                                    const ValueKey('finance-automation-amount'),
                                controller: _amount),
                          ]),
                    ),
                    const SizedBox(height: 14),
                    FinanceSectionCard(
                      title: '归类方式',
                      icon: Icons.category_outlined,
                      child: FinanceAdaptiveFields(
                          children: [_categoryField(), _paymentField()]),
                    ),
                    if (_isRule) ...[
                      const SizedBox(height: 14),
                      _scheduleSection(),
                      const SizedBox(height: 14),
                      _behaviorSection(),
                    ],
                    const SizedBox(height: 14),
                    FinanceSectionCard(
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(top: 12),
                        initiallyExpanded:
                            _merchant.text.isNotEmpty || _note.text.isNotEmpty,
                        shape: const Border(),
                        collapsedShape: const Border(),
                        title: const Text('商家与备注'),
                        subtitle: const Text('可选，记账时一起填入'),
                        children: [
                          TextFormField(
                            controller: _merchant,
                            maxLength: 80,
                            decoration: financeFieldDecoration(context,
                                label: '商家 / 对方',
                                icon: Icons.storefront_outlined),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _note,
                            maxLength: 200,
                            minLines: 2,
                            maxLines: 4,
                            decoration: financeFieldDecoration(context,
                                label: '备注', icon: Icons.notes_outlined),
                          ),
                        ],
                      ),
                    ),
                  ]),
            ),
          ),
        ),
        actions: [
          if (_saveError != null)
            Text(_saveError!, style: TextStyle(color: colors.error)),
          TextButton(
              onPressed:
                  _isSaving ? null : () => Navigator.of(context).pop(false),
              child: const Text('取消')),
          FilledButton(
            key: const ValueKey('finance-automation-save'),
            onPressed: _isSaving ? null : _save,
            child: Text(_isSaving ? '保存中…' : '保存'),
          ),
        ],
      ),
    );
  }

  Widget _categoryField() {
    final type = _type == FinanceTransactionType.income
        ? FinanceCategoryType.income
        : FinanceCategoryType.expense;
    final categories = widget.categories
        .where((item) =>
            !item.isDeleted &&
            item.type == type &&
            (!item.isArchived || item.uuid == _categoryUuid))
        .toList();
    return DropdownButtonFormField<String>(
      key: ValueKey('finance-automation-category-$_type-$_categoryUuid'),
      initialValue: _categoryUuid,
      isExpanded: true,
      decoration: financeFieldDecoration(context, label: '分类'),
      items: [
        const DropdownMenuItem(value: null, child: Text('未指定分类')),
        for (final category in categories)
          DropdownMenuItem(
              value: category.uuid,
              child: Text(
                  '${category.icon} ${category.name}${category.isArchived ? '（已归档）' : ''}',
                  overflow: TextOverflow.ellipsis)),
        if (_categoryUuid != null &&
            categories.every((item) => item.uuid != _categoryUuid))
          DropdownMenuItem(
              value: _categoryUuid,
              child: const Text('已归档或未知分类', overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (value) => setState(() => _categoryUuid = value),
    );
  }

  Widget _paymentField() {
    final methods = widget.paymentMethods
        .where((item) =>
            !item.isDeleted && (!item.isArchived || item.uuid == _paymentUuid))
        .toList();
    return DropdownButtonFormField<String>(
      key: ValueKey('finance-automation-payment-$_paymentUuid'),
      initialValue: _paymentUuid,
      isExpanded: true,
      decoration: financeFieldDecoration(context, label: '付款方式'),
      items: [
        const DropdownMenuItem(value: null, child: Text('未指定付款方式')),
        for (final method in methods)
          DropdownMenuItem(
              value: method.uuid,
              child: Text(
                  '${method.icon} ${method.name}${method.isArchived ? '（已归档）' : ''}',
                  overflow: TextOverflow.ellipsis)),
        if (_paymentUuid != null &&
            methods.every((item) => item.uuid != _paymentUuid))
          DropdownMenuItem(
              value: _paymentUuid,
              child: const Text('已归档或未知付款方式', overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (value) => setState(() => _paymentUuid = value),
    );
  }

  Widget _scheduleSection() {
    return FinanceSectionCard(
      title: '重复安排',
      icon: Icons.event_repeat_outlined,
      description: '遇到当月没有的日期，会安排在月末。',
      child: Column(children: [
        DropdownButtonFormField<FinanceRecurringFrequency>(
          initialValue: _frequency,
          isExpanded: true,
          decoration: financeFieldDecoration(context, label: '重复频率'),
          items: [
            for (final frequency in FinanceRecurringFrequency.values)
              DropdownMenuItem(value: frequency, child: Text(frequency.label))
          ],
          onChanged: (value) {
            if (value != null) setState(() => _frequency = value);
          },
        ),
        const SizedBox(height: 14),
        FinanceAdaptiveFields(children: [
          if (_frequency == FinanceRecurringFrequency.yearly)
            TextFormField(
              key: const ValueKey('finance-automation-month'),
              controller: _month,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration:
                  financeFieldDecoration(context, label: '月份', suffix: '月'),
              validator: (value) {
                final n = int.tryParse(value ?? '');
                return n == null || n < 1 || n > 12 ? '请输入 1–12 月' : null;
              },
            ),
          TextFormField(
            key: const ValueKey('finance-automation-day'),
            controller: _day,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration:
                financeFieldDecoration(context, label: '日期', suffix: '日'),
            validator: (value) {
              final n = int.tryParse(value ?? '');
              return n == null || n < 1 || n > 31 ? '请输入 1–31 日' : null;
            },
          ),
        ]),
        const SizedBox(height: 14),
        FinanceAdaptiveFields(children: [
          _dateField(_start, '开始日期'),
          _dateField(_end, '结束日期（可选）')
        ]),
      ]),
    );
  }

  Widget _dateField(TextEditingController controller, String label) {
    final isStart = controller == _start;
    return TextFormField(
      key: ValueKey(
          isStart ? 'finance-automation-start' : 'finance-automation-end'),
      controller: controller,
      keyboardType: TextInputType.datetime,
      decoration: financeFieldDecoration(context,
              label: label, hint: isStart ? 'YYYY-MM-DD' : '留空表示长期有效')
          .copyWith(
        suffixIcon: IconButton(
            tooltip: '选择${isStart ? '开始' : '结束'}日期',
            onPressed: () => _pickDate(controller),
            icon: const Icon(Icons.calendar_month_outlined)),
      ),
      validator: (value) {
        final text = value?.trim() ?? '';
        if (!isStart && text.isEmpty) return null;
        final date = DateTime.tryParse(text);
        if (date == null || dateKey(date) != text) return '请输入 YYYY-MM-DD';
        final start = DateTime.tryParse(_start.text.trim());
        if (!isStart && start != null && date.isBefore(start)) {
          return '结束日期不能早于开始日期';
        }
        return null;
      },
    );
  }

  Widget _behaviorSection() {
    final values = <int>{0, 60, 1440, 2880, 10080, _reminderMinutes}.toList()
      ..sort();
    return FinanceSectionCard(
      title: '到期如何处理',
      icon: Icons.notifications_none_outlined,
      child: Column(children: [
        LiquidGlassSwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('自动记账'),
          subtitle: const Text('关闭后手动记账，提醒时间可单独设置'),
          value: _autoGenerate,
          onChanged: (value) => setState(() => _autoGenerate = value),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _reminderMinutes,
          isExpanded: true,
          decoration: financeFieldDecoration(context, label: '提醒时间'),
          items: [
            for (final minutes in values)
              DropdownMenuItem(
                  value: minutes,
                  child: Text(minutes == 0
                      ? '不提醒'
                      : minutes % 1440 == 0
                          ? '提前 ${minutes ~/ 1440} 天'
                          : '提前 $minutes 分钟'))
          ],
          onChanged: (value) {
            if (value != null) setState(() => _reminderMinutes = value);
          },
        ),
      ]),
    );
  }

  static String? _emptyToNull(String value) =>
      value.trim().isEmpty ? null : value.trim();
}
