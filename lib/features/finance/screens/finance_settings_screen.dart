import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/storage/app_settings_storage.dart';
import '../../../storage_service.dart';
import '../../../widgets/floating_glass_control.dart';
import '../models/finance_models.dart';
import '../services/finance_repository.dart';
import '../widgets/finance_catalog_editor.dart';
import '../widgets/finance_catalog_manager.dart';
import 'finance_automation_screen.dart';

class FinanceSettingsScreen extends StatefulWidget {
  final String username;

  const FinanceSettingsScreen({super.key, required this.username});

  @override
  State<FinanceSettingsScreen> createState() => _FinanceSettingsScreenState();
}

class _FinanceSettingsScreenState extends State<FinanceSettingsScreen> {
  List<FinanceCategory> _categories = const [];
  List<FinancePaymentMethod> _paymentMethods = const [];
  bool _budgetAlertsEnabled = true;
  bool _cloudSyncEnabled = false;
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait<dynamic>([
        FinanceRepository.getCategories(includeArchived: true),
        FinanceRepository.getPaymentMethods(includeArchived: true),
        AppSettingsStorage.isFinanceBudgetAlertEnabled(),
        AppSettingsStorage.isFinanceCloudSyncEnabled(widget.username),
      ]);
      if (!mounted) return;
      setState(() {
        _categories = values[0] as List<FinanceCategory>;
        _paymentMethods = values[1] as List<FinancePaymentMethod>;
        _budgetAlertsEnabled = values[2] as bool;
        _cloudSyncEnabled = values[3] as bool;
        _isLoading = false;
        _loadError = null;
      });
    } catch (error) {
      debugPrint('读取记账设置失败：$error');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (_categories.isEmpty && _paymentMethods.isEmpty) {
          _loadError = '暂时无法加载分类与付款方式';
        }
      });
      _showMessage('加载失败，请稍后重试');
    }
  }

  Future<FinanceCategory?> _showCategoryEditor({
    required FinanceCategoryType type,
    FinanceCategory? category,
  }) async {
    if (category?.isSystem == true) return null;
    FinanceCategory? savedCategory;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => FinanceCatalogEditor(
        initialName: category?.name ?? '',
        initialIcon: category?.icon ??
            (type == FinanceCategoryType.expense ? '📦' : '💰'),
        categoryType: category?.type ?? type,
        isEditing: category != null,
        onSave: (draft) async {
          final updated = category == null
              ? FinanceCategory(
                  name: draft.name,
                  type: draft.type!,
                  sortOrder: _categories.length * 10)
              : FinanceCategory.fromMap(category.toMap());
          updated
            ..name = draft.name
            ..icon = draft.icon;
          if (category != null) updated.markAsChanged();
          await FinanceRepository.saveCategory(updated);
          savedCategory = updated;
        },
      ),
    );
    if (saved != true || !mounted) return null;
    await _load();
    _showMessage(category == null ? '分类已添加' : '分类已保存');
    return savedCategory;
  }

  Future<void> _archiveCategory(FinanceCategory category) async {
    if (category.isSystem) return;
    final confirmed = await _confirmArchive(
      title: '归档“${category.name}”？',
      message: '归档后，新建账单中不再显示该分类；历史账单和统计不受影响。',
    );
    if (confirmed != true) return;
    await FinanceRepository.archiveCategory(category.uuid);
    await _load();
    _showMessage('分类已归档，可在“已归档”中恢复');
  }

  Future<void> _unarchiveCategory(FinanceCategory category) async {
    await FinanceRepository.unarchiveCategory(category.uuid);
    await _load();
    _showMessage('分类已恢复');
  }

  Future<bool> _showPaymentEditor({FinancePaymentMethod? method}) async {
    if (method?.isSystem == true) return false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => FinanceCatalogEditor(
        initialName: method?.name ?? '',
        initialIcon: method?.icon ?? '💼',
        isEditing: method != null,
        onSave: (draft) async {
          final updated = method == null
              ? FinancePaymentMethod(
                  name: draft.name, sortOrder: _paymentMethods.length * 10)
              : FinancePaymentMethod.fromMap(method.toMap());
          updated
            ..name = draft.name
            ..icon = draft.icon;
          if (method != null) updated.markAsChanged();
          await FinanceRepository.savePaymentMethod(updated);
        },
      ),
    );
    if (saved != true || !mounted) return false;
    await _load();
    _showMessage(method == null ? '付款方式已添加' : '付款方式已保存');
    return true;
  }

  Future<void> _archivePaymentMethod(FinancePaymentMethod method) async {
    if (method.isSystem) return;
    final confirmed = await _confirmArchive(
      title: '归档“${method.name}”？',
      message: '归档后，新建账单中不再显示该付款方式；历史账单不受影响。',
    );
    if (confirmed != true) return;
    await FinanceRepository.archivePaymentMethod(method.uuid);
    await _load();
    _showMessage('付款方式已归档，可在“已归档”中恢复');
  }

  Future<void> _unarchivePaymentMethod(FinancePaymentMethod method) async {
    await FinanceRepository.unarchivePaymentMethod(method.uuid);
    await _load();
    _showMessage('付款方式已恢复');
  }

  Future<void> _openAutomation() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FinanceAutomationScreen()),
    );
    if (mounted) await _load();
  }

  Future<bool?> _confirmArchive(
      {required String title, required String message}) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.archive_outlined),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('归档')),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const FloatingGlassAppBar(
        flexibleSpace: FloatingGlassTopBarBackground(),
        title: Text('记账设置'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_outlined, size: 36),
                      const SizedBox(height: 12),
                      Text(_loadError!),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('重新加载')),
                    ],
                  ),
                )
              : SafeArea(
                  top: false,
                  child: LayoutBuilder(
                    builder: (context, constraints) => RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(
                          math.max(16, (constraints.maxWidth - 1000) / 2),
                          20,
                          math.max(16, (constraints.maxWidth - 1000) / 2),
                          32,
                        ),
                        physics: const AlwaysScrollableScrollPhysics(),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        children: [
                          FinanceCatalogManager(
                            categories: _categories,
                            paymentMethods: _paymentMethods,
                            onAddCategory: (type) =>
                                _showCategoryEditor(type: type),
                            onEditCategory: (category) async {
                              await _showCategoryEditor(
                                  type: category.type, category: category);
                            },
                            onArchiveCategory: _archiveCategory,
                            onRestoreCategory: _unarchiveCategory,
                            onAddPaymentMethod: () => _showPaymentEditor(),
                            onEditPaymentMethod: (method) async {
                              await _showPaymentEditor(method: method);
                            },
                            onArchivePaymentMethod: _archivePaymentMethod,
                            onRestorePaymentMethod: _unarchivePaymentMethod,
                          ),
                          const SizedBox(height: 28),
                          _buildPreferences(context),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _buildPreferences(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        leading: Icon(Icons.tune_rounded, color: colors.primary),
        title: const Text('更多记账设置'),
        subtitle: const Text('云同步、预算提醒与自动化'),
        children: [
          LiquidGlassSwitchListTile(
            value: _cloudSyncEnabled,
            onChanged: widget.username.trim().isEmpty
                ? null
                : (value) async {
                    setState(() => _cloudSyncEnabled = value);
                    await AppSettingsStorage.setFinanceCloudSyncEnabled(
                        widget.username, value);
                    if (value) StorageService.requestSync(widget.username);
                    if (!mounted) return;
                    _showMessage(value
                        ? '已开启记账云同步，现有本地数据将排队同步'
                        : '已停止后续记账同步；不会中断待办、习惯等其他正在进行的同步');
                  },
            title: const Text('记账云同步'),
            subtitle: const Text('默认仅保存在本机；开启后同步到当前账号'),
            secondary: const Icon(Icons.cloud_sync_outlined),
          ),
          const Divider(height: 1, indent: 20, endIndent: 20),
          LiquidGlassSwitchListTile(
            value: _budgetAlertsEnabled,
            onChanged: (value) async {
              setState(() => _budgetAlertsEnabled = value);
              await AppSettingsStorage.setFinanceBudgetAlertEnabled(value);
            },
            title: const Text('预算提醒'),
            subtitle: const Text('达到 80% 或超支时发送系统通知'),
            secondary: const Icon(Icons.notifications_active_outlined),
          ),
          const Divider(height: 1, indent: 20, endIndent: 20),
          ListTile(
            leading: const Icon(Icons.autorenew_outlined),
            title: const Text('周期账单与快捷模板'),
            subtitle: const Text('管理固定支出、周期收入和常用账单模板'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _openAutomation,
          ),
        ],
      ),
    );
  }
}
