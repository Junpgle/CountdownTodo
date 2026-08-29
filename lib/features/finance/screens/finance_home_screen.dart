import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/finance_models.dart';
import '../services/finance_automation_service.dart';
import '../services/finance_repository.dart';
import '../../../widgets/floating_bottom_bar.dart';
import '../widgets/finance_widgets.dart';
import 'finance_automation_screen.dart';
import 'finance_budget_screen.dart';
import 'finance_entry_screen.dart';
import 'finance_settings_screen.dart';
import 'finance_text_recognition_screen.dart';
import 'finance_trash_screen.dart';

class FinanceHomeScreen extends StatefulWidget {
  final String username;
  final bool openQuickEntry;

  const FinanceHomeScreen({
    super.key,
    required this.username,
    this.openQuickEntry = false,
  });

  @override
  State<FinanceHomeScreen> createState() => _FinanceHomeScreenState();
}

class _FinanceHomeScreenState extends State<FinanceHomeScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<FinanceTransaction> _transactions = const [];
  List<FinanceCategory> _categories = const [];
  List<FinancePaymentMethod> _paymentMethods = const [];
  FinanceSummary _summary = const FinanceSummary();
  String _keyword = '';
  FinanceTransactionType? _filterType;
  int _selectedIndex = 0;
  bool _isLoading = true;
  String? _loadError;
  int _loadGeneration = 0;

  Map<String, FinanceCategory> get _categoryMap => {
        for (final item in _categories) item.uuid: item,
      };

  Map<String, FinancePaymentMethod> get _paymentMethodMap => {
        for (final item in _paymentMethods) item.uuid: item,
      };

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.openQuickEntry) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openEntry();
      });
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      try {
        await FinanceAutomationService.reconcileCurrentPeriod();
      } catch (_) {
        // 自动化异常不应阻断已有账单的查看和手动记账。
      }
      final from = DateTime(_month.year, _month.month);
      final to = DateTime(_month.year, _month.month + 1);
      final values = await Future.wait<dynamic>([
        FinanceRepository.getTransactions(from: from, to: to),
        FinanceRepository.getSummary(from: from, to: to),
        FinanceRepository.getCategories(includeArchived: true),
        FinanceRepository.getPaymentMethods(includeArchived: true),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _transactions = values[0] as List<FinanceTransaction>;
        _summary = values[1] as FinanceSummary;
        _categories = values[2] as List<FinanceCategory>;
        _paymentMethods = values[3] as List<FinancePaymentMethod>;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _isLoading = false;
        _loadError = error.toString();
      });
    }
  }

  Future<void> _openEntry([
    FinanceTransaction? transaction,
    FinanceEntryTemplate? initialTemplate,
  ]) async {
    final result = await Navigator.of(context).push<FinanceTransaction>(
      MaterialPageRoute(
        builder: (_) => FinanceEntryScreen(
          transaction: transaction,
          initialTemplate: initialTemplate,
        ),
      ),
    );
    if (result != null && mounted) await _load();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FinanceSettingsScreen()),
    );
    if (mounted) await _load();
  }

  Future<void> _openTextRecognition() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const FinanceTextRecognitionScreen(),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openBudgets() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FinanceBudgetScreen(initialMonth: _month),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openAutomation() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FinanceAutomationScreen()),
    );
    if (mounted) await _load();
  }

  Future<void> _deleteTransaction(FinanceTransaction transaction) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除账单？'),
        content: const Text('删除后不会计入统计，确认继续吗？'),
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
    );
    if (confirmed != true) return;
    await FinanceRepository.deleteTransaction(transaction.uuid);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('账单已删除')),
      );
      await _load();
    }
  }

  Future<void> _exportCsv() async {
    final path = await FinanceRepository.exportCsv(
      transactions: _transactions,
      categories: _categoryMap,
      paymentMethods: _paymentMethodMap,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            path == null ? '已取消导出' : '已导出本月账单${path.isEmpty ? '' : '：$path'}'),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
    });
    _load();
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      helpText: '选择月份',
    );
    if (picked == null || !mounted) return;
    setState(() => _month = DateTime(picked.year, picked.month));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final useFloatingBottomBar = floatingBottomBarShouldFloat(context);
    final scaffold = Scaffold(
      extendBody: useFloatingBottomBar,
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: const Text('记账'),
        actions: [
          IconButton(
            tooltip: '文本识别',
            onPressed: _openTextRecognition,
            icon: const Icon(Icons.text_snippet_outlined),
          ),
          IconButton(
            tooltip: '预算',
            onPressed: _openBudgets,
            icon: const Icon(Icons.track_changes_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: '更多操作',
            onSelected: (value) {
              if (value == 'settings') _openSettings();
              if (value == 'text') _openTextRecognition();
              if (value == 'automation') _openAutomation();
              if (value == 'export') _exportCsv();
              if (value == 'trash') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const FinanceTrashScreen(),
                  ),
                );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'text',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.text_snippet_outlined),
                  title: Text('文本识别记账'),
                ),
              ),
              PopupMenuItem(
                value: 'export',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.file_download_outlined),
                  title: Text('导出本月 CSV'),
                ),
              ),
              PopupMenuItem(
                value: 'automation',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.autorenew_outlined),
                  title: Text('自动化与快捷模板'),
                ),
              ),
              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.settings_outlined),
                  title: Text('记账设置'),
                ),
              ),
              PopupMenuItem(
                value: 'trash',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline),
                  title: Text('记账回收站'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? _buildError(colorScheme)
              : Column(
                  children: [
                    _buildMonthBar(colorScheme),
                    Expanded(
                      child: IndexedStack(
                        index: _selectedIndex,
                        children: [
                          FinanceOverviewPanel(
                            month: _month,
                            summary: _summary,
                            transactions: _transactions,
                            categories: _categoryMap,
                            onAdd: _openEntry,
                            onRefresh: _load,
                          ),
                          FinanceLedgerPanel(
                            transactions: _transactions,
                            categories: _categoryMap,
                            paymentMethods: _paymentMethodMap,
                            keyword: _keyword,
                            filterType: _filterType,
                            onKeywordChanged: (value) =>
                                setState(() => _keyword = value),
                            onFilterChanged: (value) =>
                                setState(() => _filterType = value),
                            onEdit: _openEntry,
                            onDelete: _deleteTransaction,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
      floatingActionButton: _isLoading || _loadError != null
          ? null
          : FloatingGlassActionButton.extended(
              onPressed: _openEntry,
              icon: const Icon(Icons.add),
              label: const Text('记一笔'),
            ),
      bottomNavigationBar: useFloatingBottomBar
          ? FloatingBottomNavigationBar(
              items: const [
                FloatingBottomNavigationItem(
                  icon: Icons.insights_outlined,
                  label: '概览',
                ),
                FloatingBottomNavigationItem(
                  icon: Icons.receipt_long_outlined,
                  label: '账单',
                ),
              ],
              selectedIndex: _selectedIndex,
              onTabSelected: (index) => setState(() => _selectedIndex = index),
            )
          : NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) =>
                  setState(() => _selectedIndex = index),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.insights_outlined),
                  selectedIcon: Icon(Icons.insights),
                  label: '概览',
                ),
                NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long),
                  label: '账单',
                ),
              ],
            ),
    );

    final isDesktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux);
    if (!isDesktop) return scaffold;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(
          LogicalKeyboardKey.keyN,
          control: true,
          shift: true,
        ): _FinanceQuickEntryIntent(),
        SingleActivator(
          LogicalKeyboardKey.keyN,
          meta: true,
          shift: true,
        ): _FinanceQuickEntryIntent(),
      },
      child: Actions(
        actions: {
          _FinanceQuickEntryIntent: CallbackAction<_FinanceQuickEntryIntent>(
            onInvoke: (_) {
              unawaited(_openEntry());
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: scaffold,
        ),
      ),
    );
  }

  Widget _buildMonthBar(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: '上个月',
            onPressed: () => _changeMonth(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _pickMonth,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${_month.year} 年 ${_month.month} 月',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.expand_more,
                        size: 18, color: colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '下个月',
            onPressed: () => _changeMonth(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  Widget _buildError(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 12),
            const Text('记账数据加载失败'),
            const SizedBox(height: 8),
            Text(
              _loadError ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FinanceQuickEntryIntent extends Intent {
  const _FinanceQuickEntryIntent();
}
