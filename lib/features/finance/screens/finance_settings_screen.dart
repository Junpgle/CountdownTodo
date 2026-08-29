import '../../../widgets/floating_glass_control.dart';
import 'package:flutter/material.dart';

import '../models/finance_models.dart';
import '../services/finance_repository.dart';
import '../../../services/storage/app_settings_storage.dart';
import 'finance_automation_screen.dart';

class FinanceSettingsScreen extends StatefulWidget {
  const FinanceSettingsScreen({super.key});

  @override
  State<FinanceSettingsScreen> createState() => _FinanceSettingsScreenState();
}

class _FinanceSettingsScreenState extends State<FinanceSettingsScreen> {
  List<FinanceCategory> _categories = const [];
  List<FinancePaymentMethod> _paymentMethods = const [];
  bool _budgetAlertsEnabled = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait<dynamic>([
      FinanceRepository.getCategories(includeArchived: true),
      FinanceRepository.getPaymentMethods(includeArchived: true),
      AppSettingsStorage.isFinanceBudgetAlertEnabled(),
    ]);
    if (!mounted) return;
    setState(() {
      _categories = values[0] as List<FinanceCategory>;
      _paymentMethods = values[1] as List<FinancePaymentMethod>;
      _budgetAlertsEnabled = values[2] as bool;
      _isLoading = false;
    });
  }

  Future<void> _addCategory() async {
    final result = await _showCategoryEditor();
    if (result == null) return;
    await FinanceRepository.saveCategory(
      FinanceCategory(
        name: result.name,
        icon: result.icon,
        type: result.type,
        sortOrder: _categories.length * 10,
      ),
    );
    await _load();
  }

  Future<void> _editCategory(FinanceCategory category) async {
    if (category.isSystem) {
      _showMessage('系统分类不可修改，但可以直接使用');
      return;
    }
    final result = await _showCategoryEditor(category: category);
    if (result == null) return;
    if (result.type != category.type &&
        await FinanceRepository.hasTransactionsForCategory(category.uuid)) {
      _showMessage('该分类已被账单使用，不能修改收入/支出类型');
      return;
    }
    category.name = result.name;
    category.icon = result.icon;
    category.type = result.type;
    category.markAsChanged();
    await FinanceRepository.saveCategory(category);
    await _load();
  }

  Future<void> _archiveCategory(FinanceCategory category) async {
    if (category.isSystem) {
      _showMessage('系统分类不可归档');
      return;
    }
    final confirmed = await _confirm(
      title: '归档分类',
      message: '归档后不会影响历史账单，但新建账单中不会再显示该分类。',
    );
    if (confirmed != true) return;
    await FinanceRepository.archiveCategory(category.uuid);
    await _load();
  }

  Future<void> _unarchiveCategory(FinanceCategory category) async {
    await FinanceRepository.unarchiveCategory(category.uuid);
    await _load();
  }

  Future<void> _addPaymentMethod() async {
    final result = await _showPaymentEditor();
    if (result == null) return;
    await FinanceRepository.savePaymentMethod(
      FinancePaymentMethod(
        name: result.name,
        icon: result.icon,
        sortOrder: _paymentMethods.length * 10,
      ),
    );
    await _load();
  }

  Future<void> _editPaymentMethod(FinancePaymentMethod method) async {
    if (method.isSystem) {
      _showMessage('系统付款方式不可修改，但可以直接使用');
      return;
    }
    final result = await _showPaymentEditor(method: method);
    if (result == null) return;
    method.name = result.name;
    method.icon = result.icon;
    method.markAsChanged();
    await FinanceRepository.savePaymentMethod(method);
    await _load();
  }

  Future<void> _archivePaymentMethod(FinancePaymentMethod method) async {
    if (method.isSystem) {
      _showMessage('系统付款方式不可归档');
      return;
    }
    final confirmed = await _confirm(
      title: '归档付款方式',
      message: '归档后不会影响历史账单，但新建账单中不会再显示该方式。',
    );
    if (confirmed != true) return;
    await FinanceRepository.archivePaymentMethod(method.uuid);
    await _load();
  }

  Future<void> _unarchivePaymentMethod(FinancePaymentMethod method) async {
    await FinanceRepository.unarchivePaymentMethod(method.uuid);
    await _load();
  }

  Future<void> _openAutomation() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FinanceAutomationScreen()),
    );
    if (mounted) await _load();
  }

  Future<_CategoryEditorResult?> _showCategoryEditor({
    FinanceCategory? category,
  }) async {
    final nameController = TextEditingController(text: category?.name ?? '');
    final iconController = TextEditingController(text: category?.icon ?? '📦');
    var type = category?.type ?? FinanceCategoryType.expense;
    final result = await showDialog<_CategoryEditorResult>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(category == null ? '新增分类' : '编辑分类'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: '名称'),
                maxLength: 30,
              ),
              TextField(
                controller: iconController,
                decoration: const InputDecoration(labelText: '图标（可选）'),
                maxLength: 4,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<FinanceCategoryType>(
                initialValue: type,
                decoration: InputDecoration(
                  labelText: '适用类型',
                  helperText: category == null ? null : '创建后不可修改',
                ),
                items: [
                  for (final value in FinanceCategoryType.values)
                    DropdownMenuItem(
                      value: value,
                      child: Text(value.label),
                    ),
                ],
                onChanged: category == null
                    ? (value) {
                        if (value != null) setState(() => type = value);
                      }
                    : null,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(
                  context,
                  _CategoryEditorResult(
                    name: name,
                    icon: iconController.text.trim().isEmpty
                        ? '📦'
                        : iconController.text.trim(),
                    type: type,
                  ),
                );
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    iconController.dispose();
    return result;
  }

  Future<_PaymentEditorResult?> _showPaymentEditor({
    FinancePaymentMethod? method,
  }) async {
    final nameController = TextEditingController(text: method?.name ?? '');
    final iconController = TextEditingController(text: method?.icon ?? '💼');
    final result = await showDialog<_PaymentEditorResult>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(method == null ? '新增付款方式' : '编辑付款方式'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: '名称'),
              maxLength: 30,
            ),
            TextField(
              controller: iconController,
              decoration: const InputDecoration(labelText: '图标（可选）'),
              maxLength: 4,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(
                context,
                _PaymentEditorResult(
                  name: name,
                  icon: iconController.text.trim().isEmpty
                      ? '💼'
                      : iconController.text.trim(),
                ),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    nameController.dispose();
    iconController.dispose();
    return result;
  }

  Future<bool?> _confirm({required String title, required String message}) {
    return showDialog<bool>(
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
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: FloatingGlassAppBar(
          flexibleSpace: const FloatingGlassTopBarBackground(),
          title: const Text('记账设置')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Column(
                      children: [
                        SwitchListTile.adaptive(
                          value: _budgetAlertsEnabled,
                          onChanged: (value) async {
                            setState(() => _budgetAlertsEnabled = value);
                            await AppSettingsStorage
                                .setFinanceBudgetAlertEnabled(value);
                          },
                          title: const Text('预算提醒'),
                          subtitle: const Text('达到 80% 或超支时发送系统通知'),
                          secondary:
                              const Icon(Icons.notifications_active_outlined),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.autorenew_outlined),
                          title: const Text('周期账单与快捷模板'),
                          subtitle: const Text('管理固定支出、周期收入和常用账单模板'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _openAutomation,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildSectionHeader(
                    title: '分类',
                    subtitle: '系统分类不可删除，自定义分类可以归档',
                    onAdd: _addCategory,
                    colorScheme: colorScheme,
                  ),
                  Card(
                    child: Column(
                      children: _categories
                          .where((item) => !item.isDeleted)
                          .map((item) => _buildCategoryTile(item))
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildSectionHeader(
                    title: '付款方式',
                    subtitle: '第一版只记录付款来源，不计算账户余额',
                    onAdd: _addPaymentMethod,
                    colorScheme: colorScheme,
                  ),
                  Card(
                    child: Column(
                      children: _paymentMethods
                          .where((item) => !item.isDeleted)
                          .map((item) => _buildPaymentTile(item))
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    required VoidCallback onAdd,
    required ColorScheme colorScheme,
  }) {
    return Row(
      children: [
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

  Widget _buildCategoryTile(FinanceCategory category) {
    return ListTile(
      leading: Text(category.icon, style: const TextStyle(fontSize: 22)),
      title: Text(category.name),
      subtitle: Text(
        '${category.type.label}${category.isArchived ? ' · 已归档' : ''}',
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'edit') _editCategory(category);
          if (value == 'archive') _archiveCategory(category);
          if (value == 'unarchive') _unarchiveCategory(category);
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'edit', child: Text('编辑')),
          if (category.isArchived)
            const PopupMenuItem(value: 'unarchive', child: Text('取消归档'))
          else if (!category.isSystem)
            const PopupMenuItem(value: 'archive', child: Text('归档')),
        ],
      ),
    );
  }

  Widget _buildPaymentTile(FinancePaymentMethod method) {
    return ListTile(
      leading: Text(method.icon, style: const TextStyle(fontSize: 22)),
      title: Text(method.name),
      subtitle: method.isArchived ? const Text('已归档') : null,
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'edit') _editPaymentMethod(method);
          if (value == 'archive') _archivePaymentMethod(method);
          if (value == 'unarchive') _unarchivePaymentMethod(method);
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'edit', child: Text('编辑')),
          if (method.isArchived)
            const PopupMenuItem(value: 'unarchive', child: Text('取消归档'))
          else if (!method.isSystem)
            const PopupMenuItem(value: 'archive', child: Text('归档')),
        ],
      ),
    );
  }
}

class _CategoryEditorResult {
  final String name;
  final String icon;
  final FinanceCategoryType type;

  const _CategoryEditorResult({
    required this.name,
    required this.icon,
    required this.type,
  });
}

class _PaymentEditorResult {
  final String name;
  final String icon;

  const _PaymentEditorResult({required this.name, required this.icon});
}
