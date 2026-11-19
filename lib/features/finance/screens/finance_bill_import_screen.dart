import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../utils/app_dialogs.dart';
import '../../../utils/text_file_reader.dart';
import '../../../widgets/floating_glass_control.dart';
import '../models/finance_models.dart';
import '../services/finance_bill_import_parser.dart';
import '../services/finance_repository.dart';

enum _ImportPreviewFilter { all, selected, duplicates, neutral }

typedef FinanceBillFileLoader =
    Future<({String name, Uint8List bytes})?> Function();

class FinanceBillImportScreen extends StatefulWidget {
  final FinanceBillFileLoader? onPickFile;

  const FinanceBillImportScreen({super.key, this.onPickFile});

  @override
  State<FinanceBillImportScreen> createState() =>
      _FinanceBillImportScreenState();
}

class _FinanceBillImportScreenState extends State<FinanceBillImportScreen> {
  bool _isParsing = false;
  bool _isSaving = false;
  String? _fileName;
  FinanceBillParseResult? _result;
  List<FinanceCategory> _categories = const [];
  List<FinancePaymentMethod> _paymentMethods = const [];
  _ImportPreviewFilter _filter = _ImportPreviewFilter.all;

  Future<void> _pickAndParseFile() async {
    if (_isParsing || _isSaving) return;
    try {
      final picked = widget.onPickFile != null
          ? await widget.onPickFile!()
          : await _defaultPickFile();
      if (picked == null || !mounted) return;

      setState(() => _isParsing = true);

      final meta = await Future.wait<dynamic>([
        FinanceRepository.getCategories(includeArchived: false),
        FinanceRepository.getPaymentMethods(includeArchived: false),
        FinanceRepository.getTransactions(),
      ]);
      final categories = meta[0] as List<FinanceCategory>;
      final paymentMethods = meta[1] as List<FinancePaymentMethod>;
      final existingTransactions = meta[2] as List<FinanceTransaction>;

      final parsed = FinanceBillImportParser.parseBytes(
        picked.bytes,
        fileName: picked.name,
        categories: categories,
        paymentMethods: paymentMethods,
        existingTransactions: existingTransactions,
      );

      if (!mounted) return;
      setState(() {
        _categories = categories;
        _paymentMethods = paymentMethods;
        _fileName = picked.name;
        _result = parsed;
        _filter = _ImportPreviewFilter.all;
        _isParsing = false;
      });
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() => _isParsing = false);
      _showMessage(error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isParsing = false);
      _showMessage('解析账单失败：$error');
    }
  }

  Future<({String name, Uint8List bytes})?> _defaultPickFile() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const [
        'csv',
        'xlsx',
        'tsv',
        'txt',
        'json',
        'qif',
        'ofx',
        'qfx',
      ],
    );
    if (picked == null) return null;

    Uint8List? bytes;
    try {
      bytes = await picked.readAsBytes();
    } catch (_) {
      // 部分平台可能只暴露本地文件路径，下面会按路径兜底读取。
    }
    if ((bytes == null || bytes.isEmpty) &&
        !kIsWeb &&
        picked.path != null &&
        picked.path!.isNotEmpty) {
      bytes = await readFileBytes(picked.path!);
    }
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('无法读取所选文件内容');
    }
    return (name: picked.name, bytes: bytes);
  }

  List<FinanceBillImportItem> get _filteredItems {
    final items = _result?.items ?? const <FinanceBillImportItem>[];
    return switch (_filter) {
      _ImportPreviewFilter.all => items,
      _ImportPreviewFilter.selected => items.where((e) => e.selected).toList(),
      _ImportPreviewFilter.duplicates =>
        items.where((e) => e.isDuplicate).toList(),
      _ImportPreviewFilter.neutral => items.where((e) => e.isNeutral).toList(),
    };
  }

  List<FinanceBillImportItem> get _selectedItems {
    final items = _result?.items ?? const <FinanceBillImportItem>[];
    return items.where((e) => e.selected).toList();
  }

  String _categoryLabel(String? uuid) {
    if (uuid == null) return '未分类';
    for (final c in _categories) {
      if (c.uuid == uuid) {
        return '${c.icon} ${c.name}';
      }
    }
    return '未分类';
  }

  String _paymentLabel(String? uuid) {
    if (uuid == null) return '未指定';
    for (final m in _paymentMethods) {
      if (m.uuid == uuid) {
        return '${m.icon} ${m.name}';
      }
    }
    return '未指定';
  }

  void _toggleSelectAllVisible() {
    final visible = _filteredItems;
    if (visible.isEmpty) return;
    final allSelected = visible.every((item) => item.selected);
    setState(() {
      for (final item in visible) {
        item.selected = !allSelected;
      }
    });
  }

  Future<void> _pickCategoryForItem(FinanceBillImportItem item) async {
    final targetType = item.type == FinanceTransactionType.income
        ? FinanceCategoryType.income
        : FinanceCategoryType.expense;
    final options = _categories.where((c) => c.type == targetType).toList();
    if (options.isEmpty) return;
    final chosen = await _showCategoryPickerDialog(
      title: '选择分类',
      categories: options,
      selectedUuid: item.categoryUuid,
    );
    if (chosen == null || !mounted) return;
    setState(() => item.categoryUuid = chosen.uuid);
  }

  Future<void> _batchUpdateCategory() async {
    final selected = _selectedItems;
    if (selected.isEmpty) {
      _showMessage('请先勾选需要修改的账单');
      return;
    }
    final hasExpense = selected.any(
      (e) => e.type != FinanceTransactionType.income,
    );
    final hasIncome = selected.any(
      (e) => e.type == FinanceTransactionType.income,
    );

    FinanceCategoryType targetType = FinanceCategoryType.expense;
    if (!hasExpense && hasIncome) {
      targetType = FinanceCategoryType.income;
    } else if (hasExpense && hasIncome) {
      final pickedType = await showAppDialog<FinanceCategoryType>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('批量修改分类'),
          content: const Text('当前同时勾选了支出和收入账单，请选择要批量修改的分类类型：'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton.tonal(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(FinanceCategoryType.income),
              child: const Text('仅改收入'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(FinanceCategoryType.expense),
              child: const Text('仅改支出/退款'),
            ),
          ],
        ),
      );
      if (pickedType == null || !mounted) return;
      targetType = pickedType;
    }

    final options = _categories.where((c) => c.type == targetType).toList();
    if (options.isEmpty) return;
    final chosen = await _showCategoryPickerDialog(
      title: '批量设为${targetType == FinanceCategoryType.income ? '收入' : '支出'}分类',
      categories: options,
    );
    if (chosen == null || !mounted) return;

    var count = 0;
    setState(() {
      for (final item in selected) {
        final itemCatType = item.type == FinanceTransactionType.income
            ? FinanceCategoryType.income
            : FinanceCategoryType.expense;
        if (itemCatType == targetType) {
          item.categoryUuid = chosen.uuid;
          count++;
        }
      }
    });
    _showMessage('已将 $count 笔账单分类修改为「${chosen.name}」');
  }

  Future<void> _pickPaymentForItem(FinanceBillImportItem item) async {
    if (_paymentMethods.isEmpty) return;
    final chosen = await _showPaymentPickerDialog(
      title: item.type == FinanceTransactionType.transfer ? '选择转出账户' : '选择付款方式',
      selectedUuid: item.paymentMethodUuid,
    );
    if (chosen == null || !mounted) return;
    setState(() => item.paymentMethodUuid = chosen.uuid);
  }

  Future<void> _pickTargetPaymentForItem(FinanceBillImportItem item) async {
    if (_paymentMethods.isEmpty) return;
    final chosen = await _showPaymentPickerDialog(
      title: '选择转入账户',
      selectedUuid: item.targetPaymentMethodUuid,
    );
    if (chosen == null || !mounted) return;
    setState(() => item.targetPaymentMethodUuid = chosen.uuid);
  }

  Future<void> _batchUpdatePaymentMethod() async {
    final selected = _selectedItems;
    if (selected.isEmpty) {
      _showMessage('请先勾选需要修改的账单');
      return;
    }
    if (_paymentMethods.isEmpty) return;
    final chosen = await _showPaymentPickerDialog(title: '批量修改付款方式');
    if (chosen == null || !mounted) return;
    setState(() {
      for (final item in selected) {
        item.paymentMethodUuid = chosen.uuid;
      }
    });
    _showMessage('已将 ${selected.length} 笔账单付款方式修改为「${chosen.name}」');
  }

  Future<void> _cycleItemType(FinanceBillImportItem item) async {
    final chosen = await showAppDialog<FinanceTransactionType>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('调整账单类型'),
        children: [
          for (final type in FinanceTransactionType.values)
            ListTile(
              title: Text(type.label),
              trailing: item.type == type
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () => Navigator.of(dialogContext).pop(type),
            ),
        ],
      ),
    );
    if (chosen == null || chosen == item.type || !mounted) return;
    setState(() {
      item.type = chosen;
      // 切换收支类型后重置为匹配类型的默认分类
      final targetCatType = chosen == FinanceTransactionType.income
          ? FinanceCategoryType.income
          : FinanceCategoryType.expense;
      final currentMatches = _categories.any(
        (c) => c.uuid == item.categoryUuid && c.type == targetCatType,
      );
      if (!currentMatches) {
        final fallback = _categories
            .where((c) => c.type == targetCatType)
            .toList();
        if (fallback.isNotEmpty) {
          final other = fallback.where((c) => c.name == '其他').toList();
          item.categoryUuid = other.isNotEmpty
              ? other.first.uuid
              : fallback.first.uuid;
        }
      }
    });
  }

  Future<FinanceCategory?> _showCategoryPickerDialog({
    required String title,
    required List<FinanceCategory> categories,
    String? selectedUuid,
  }) {
    return showAppDialog<FinanceCategory>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 360,
          height: 360,
          child: ListView.builder(
            itemCount: categories.length,
            itemBuilder: (_, index) {
              final cat = categories[index];
              final isSelected = cat.uuid == selectedUuid;
              return ListTile(
                dense: true,
                leading: Text(cat.icon, style: const TextStyle(fontSize: 20)),
                title: Text(cat.name),
                trailing: isSelected ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.of(dialogContext).pop(cat),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Future<FinancePaymentMethod?> _showPaymentPickerDialog({
    required String title,
    String? selectedUuid,
  }) {
    return showAppDialog<FinancePaymentMethod>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 340,
          height: 300,
          child: ListView.builder(
            itemCount: _paymentMethods.length,
            itemBuilder: (_, index) {
              final method = _paymentMethods[index];
              final isSelected = method.uuid == selectedUuid;
              return ListTile(
                dense: true,
                leading: Text(
                  method.icon,
                  style: const TextStyle(fontSize: 20),
                ),
                title: Text(method.name),
                trailing: isSelected ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.of(dialogContext).pop(method),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmImport() async {
    final selected = _selectedItems;
    if (selected.isEmpty || _isSaving) return;

    setState(() => _isSaving = true);
    try {
      final transactions = selected
          .map((item) => item.toTransaction())
          .toList();
      await FinanceRepository.saveTransactionsBatch(transactions);
      if (!mounted) return;
      _showMessage('成功导入 ${transactions.length} 笔账单');
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showMessage('导入失败：$error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    AppSnackBars.hideCurrent(messenger);
    AppSnackBars.showSnackBar(context, SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final topBarHeight = floatingGlassTopBarHeight(context);
    final result = _result;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: const Text('账单导入'),
        actions: [
          if (result != null)
            TextButton.icon(
              onPressed: _isParsing || _isSaving ? null : _pickAndParseFile,
              icon: const Icon(Icons.folder_open_outlined, size: 18),
              label: const Text('重选文件'),
            ),
        ],
      ),
      bottomNavigationBar: result == null ? null : _buildBottomBar(context),
      body: FloatingGlassTopBarContentFade(
        topBarHeight: topBarHeight,
        child: _isParsing
            ? const Center(child: CircularProgressIndicator())
            : result == null
            ? _buildEmptyState(context, topBarHeight)
            : _buildPreviewBody(context, topBarHeight, result),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, double topBarHeight) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return ListView(
      padding: EdgeInsets.fromLTRB(16, topBarHeight + 16, 16, 32),
      children: [
        Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: colors.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: colors.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.file_upload_outlined,
                    color: colors.onPrimaryContainer,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '导入多平台账单',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '支持微信（.xlsx / .csv）、支付宝（.csv）、银行流水（.csv / .xlsx / .ofx / .qfx / .qif）、云闪付、主流记账软件导出及通用表格 / JSON（.csv / .tsv / .xlsx / .json）。解析后会进入预览确认页，自动匹配分类与付款方式，并标记疑似重复或不计收支记录。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey('finance-bill-import-pick-file'),
                    onPressed: _pickAndParseFile,
                    icon: const Icon(Icons.upload_file_rounded),
                    label: const Text('选择账单文件（CSV / XLSX / JSON / OFX / QIF）'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: colors.surfaceContainerLowest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: colors.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '支持哪些账单格式与导出方式？',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '• 微信：我 → 服务 → 钱包 → 账单 → 常见问题 → 下载账单 → 用于个人对账（导出后解压获得 .xlsx 或 .csv）',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '• 支付宝：我的 → 账单 → 右上角「…」→ 开具交易流水证明 → 用于个人对账（导出后获得 .csv）',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '• 银行流水 / 云闪付：支持网银或手机银行导出的 CSV / XLSX / OFX / QFX / QIF 流水（自动识别单列正负金额或收入/支出双列）',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '• 记账软件 / 通用表格：支持钱迹、随手记等导出的 CSV / XLSX，或包含「时间、金额」列的自定义表格 / TSV / JSON 文件',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewBody(
    BuildContext context,
    double topBarHeight,
    FinanceBillParseResult result,
  ) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final visible = _filteredItems;
    final selected = _selectedItems;

    var selectedExpenseMinor = 0;
    var selectedIncomeMinor = 0;
    var selectedRefundMinor = 0;
    var selectedTransferMinor = 0;
    for (final item in selected) {
      switch (item.type) {
        case FinanceTransactionType.expense:
          selectedExpenseMinor += item.amountMinor;
        case FinanceTransactionType.income:
          selectedIncomeMinor += item.amountMinor;
        case FinanceTransactionType.refund:
          selectedRefundMinor += item.amountMinor;
        case FinanceTransactionType.transfer:
          selectedTransferMinor += item.amountMinor;
      }
    }

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, topBarHeight + 12, 16, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  color: colors.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: colors.outlineVariant.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: colors.primaryContainer,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                result.platform.label,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: colors.onPrimaryContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _fileName ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 16,
                          runSpacing: 6,
                          children: [
                            Text(
                              '共 ${result.items.length} 笔 · 已选 ${selected.length} 笔',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '支出 ${formatFinanceAmount(selectedExpenseMinor)}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '收入 ${formatFinanceAmount(selectedIncomeMinor)}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (selectedRefundMinor > 0)
                              Text(
                                '退款 ${formatFinanceAmount(selectedRefundMinor)}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colors.tertiary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            if (selectedTransferMinor > 0)
                              Text(
                                '互转 ${formatFinanceAmount(selectedTransferMinor)}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colors.secondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                        if (result.skippedStatusCount > 0 ||
                            result.duplicateCount > 0 ||
                            result.neutralCount > 0) ...[
                          const SizedBox(height: 8),
                          Text(
                            [
                              if (result.skippedStatusCount > 0)
                                '已跳过 ${result.skippedStatusCount} 笔关闭/无效账单',
                              if (result.duplicateCount > 0)
                                '${result.duplicateCount} 笔疑似重复（默认未勾选）',
                              if (result.neutralCount > 0)
                                '${result.neutralCount} 笔不计收支（默认未勾选）',
                            ].join(' · '),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        label: Text('全部 (${result.items.length})'),
                        selected: _filter == _ImportPreviewFilter.all,
                        onSelected: (_) =>
                            setState(() => _filter = _ImportPreviewFilter.all),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: Text('已选 (${selected.length})'),
                        selected: _filter == _ImportPreviewFilter.selected,
                        onSelected: (_) => setState(
                          () => _filter = _ImportPreviewFilter.selected,
                        ),
                      ),
                      if (result.duplicateCount > 0) ...[
                        const SizedBox(width: 8),
                        FilterChip(
                          label: Text('疑似重复 (${result.duplicateCount})'),
                          selected: _filter == _ImportPreviewFilter.duplicates,
                          onSelected: (_) => setState(
                            () => _filter = _ImportPreviewFilter.duplicates,
                          ),
                        ),
                      ],
                      if (result.neutralCount > 0) ...[
                        const SizedBox(width: 8),
                        FilterChip(
                          label: Text('不计收支 (${result.neutralCount})'),
                          selected: _filter == _ImportPreviewFilter.neutral,
                          onSelected: (_) => setState(
                            () => _filter = _ImportPreviewFilter.neutral,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      avatar: Icon(
                        visible.isNotEmpty && visible.every((e) => e.selected)
                            ? Icons.deselect_outlined
                            : Icons.select_all_outlined,
                        size: 18,
                      ),
                      label: Text(
                        visible.isNotEmpty && visible.every((e) => e.selected)
                            ? '取消全选'
                            : '全选当前',
                      ),
                      onPressed: visible.isEmpty
                          ? null
                          : _toggleSelectAllVisible,
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.category_outlined, size: 18),
                      label: const Text('批量改分类'),
                      onPressed: selected.isEmpty ? null : _batchUpdateCategory,
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.credit_card_outlined, size: 18),
                      label: const Text('批量改付款方式'),
                      onPressed: selected.isEmpty
                          ? null
                          : _batchUpdatePaymentMethod,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (visible.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('当前筛选下没有账单记录')),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverList.separated(
              itemCount: visible.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) =>
                  _buildImportItemCard(context, visible[index]),
            ),
          ),
      ],
    );
  }

  Widget _buildImportItemCard(
    BuildContext context,
    FinanceBillImportItem item,
  ) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final occurredText = DateFormat('yyyy-MM-dd HH:mm')
        .format(DateTime.fromMillisecondsSinceEpoch(item.occurredAt));
    final amountColor = switch (item.type) {
      FinanceTransactionType.expense => colors.error,
      FinanceTransactionType.income => colors.primary,
      FinanceTransactionType.refund => colors.tertiary,
      FinanceTransactionType.transfer => colors.secondary,
    };
    final notePreview = item.buildCombinedNote();

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: item.selected
          ? colors.surfaceContainerLow
          : colors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: item.selected
              ? colors.primary.withValues(alpha: 0.35)
              : colors.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 10, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: item.selected,
              onChanged: (value) =>
                  setState(() => item.selected = value ?? false),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.merchant,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatSignedFinanceAmount(item.amountMinor, item.type),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: amountColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  if (notePreview != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      notePreview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    occurredText,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  if (item.isDuplicate || item.isNeutral) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (item.isDuplicate)
                          _StatusBadge(
                            label: item.duplicateReason ?? '疑似重复',
                            backgroundColor: colors.errorContainer,
                            foregroundColor: colors.onErrorContainer,
                          ),
                        if (item.isNeutral)
                          _StatusBadge(
                            label: item.neutralReason ?? '不计收支',
                            backgroundColor: colors.secondaryContainer,
                            foregroundColor: colors.onSecondaryContainer,
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _InlineEditChip(
                        label: item.type.label,
                        onTap: () => _cycleItemType(item),
                      ),
                      _InlineEditChip(
                        label: _categoryLabel(item.categoryUuid),
                        onTap: () => _pickCategoryForItem(item),
                      ),
                      _InlineEditChip(
                        label: item.type == FinanceTransactionType.transfer
                            ? '转出: ${_paymentLabel(item.paymentMethodUuid)}'
                            : _paymentLabel(item.paymentMethodUuid),
                        onTap: () => _pickPaymentForItem(item),
                      ),
                      if (item.type == FinanceTransactionType.transfer)
                        _InlineEditChip(
                          label:
                              '转入: ${_paymentLabel(item.targetPaymentMethodUuid)}',
                          onTap: () => _pickTargetPaymentForItem(item),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selectedCount = _selectedItems.length;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(
            top: BorderSide(
              color: colors.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
        ),
        child: FilledButton(
          key: const ValueKey('finance-bill-import-confirm'),
          onPressed: selectedCount == 0 || _isSaving ? null : _confirmImport,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('确认导入 ($selectedCount 笔)'),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  const _StatusBadge({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: foregroundColor, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _InlineEditChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _InlineEditChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: colors.onSurface),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 16,
              color: colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
