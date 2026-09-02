import 'package:flutter/material.dart';

import '../../../services/reminder_schedule_service.dart';
import '../../../widgets/floating_glass_control.dart';
import '../models/finance_models.dart';
import '../services/finance_repository.dart';
import '../widgets/finance_automation_editor.dart';
import '../widgets/finance_automation_manager.dart';
import '../widgets/finance_management_widgets.dart';
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
  String? _loadError;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    try {
      final values = await Future.wait<dynamic>([
        FinanceRepository.getRecurringRules(),
        FinanceRepository.getTemplates(),
        FinanceRepository.getCategories(includeArchived: true),
        FinanceRepository.getPaymentMethods(includeArchived: true),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _rules = values[0] as List<FinanceRecurringRule>;
        _templates = values[1] as List<FinanceEntryTemplate>;
        _categories = values[2] as List<FinanceCategory>;
        _paymentMethods = values[3] as List<FinancePaymentMethod>;
        _isLoading = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _isLoading = false;
        _loadError = error.toString();
      });
    }
  }

  Future<bool> _openRuleEditor([FinanceRecurringRule? rule]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => FinanceAutomationEditor.rule(
        rule: rule,
        categories: _categories,
        paymentMethods: _paymentMethods,
        onSave: FinanceRepository.saveRecurringRule,
      ),
    );
    if (saved != true || !mounted) return false;
    await _rescheduleReminders();
    await _load();
    return true;
  }

  Future<void> _toggleRule(FinanceRecurringRule rule, bool enabled) async {
    await FinanceRepository.setRecurringRuleEnabled(rule.uuid, enabled);
    await _rescheduleReminders();
    await _load();
  }

  Future<void> _deleteRule(FinanceRecurringRule rule) async {
    if (!await _confirm('删除周期账单', '删除后不会再提醒或自动记账，可以在回收站恢复。') || !mounted) {
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

  Future<bool> _openTemplateEditor([FinanceEntryTemplate? template]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => FinanceAutomationEditor.template(
        template: template,
        categories: _categories,
        paymentMethods: _paymentMethods,
        onSave: FinanceRepository.saveTemplate,
      ),
    );
    if (saved != true || !mounted) return false;
    await _load();
    return true;
  }

  Future<void> _useTemplate(FinanceEntryTemplate template) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => FinanceEntryScreen(initialTemplate: template)),
    );
    if (mounted) await _load();
  }

  Future<void> _deleteTemplate(FinanceEntryTemplate template) async {
    if (!await _confirm('删除快捷模板', '删除后可以在记账回收站恢复。') || !mounted) return;
    await FinanceRepository.deleteTemplate(template.uuid);
    await _load();
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
                  child: const Text('取消')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('删除')),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: const Text('记账自动化'),
        actions: [
          IconButton(
              tooltip: '刷新', onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? FinancePageList(children: [
                  FinanceEmptyState(
                    icon: Icons.error_outline_rounded,
                    title: '自动化数据加载失败',
                    description: '请重试，已有账单和模板不会丢失。',
                    actionLabel: '重新加载',
                    onAction: _load,
                  ),
                ])
              : RefreshIndicator(
                  onRefresh: _load,
                  child: FinanceAutomationManager(
                    rules: _rules,
                    templates: _templates,
                    categories: _categories,
                    paymentMethods: _paymentMethods,
                    onAddRule: _openRuleEditor,
                    onAddTemplate: _openTemplateEditor,
                    onEditRule: (rule) async {
                      await _openRuleEditor(rule);
                    },
                    onToggleRule: _toggleRule,
                    onDeleteRule: _deleteRule,
                    onEditTemplate: (template) async {
                      await _openTemplateEditor(template);
                    },
                    onUseTemplate: _useTemplate,
                    onDeleteTemplate: _deleteTemplate,
                  ),
                ),
    );
  }
}
