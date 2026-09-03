import 'dart:async';

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/screens/finance_loan_entry_screen.dart';
import 'package:countdown_todo/features/finance/widgets/finance_automation_editor.dart';
import 'package:countdown_todo/features/finance/widgets/finance_automation_manager.dart';
import 'package:countdown_todo/features/finance/widgets/finance_trash_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<FinanceCategory> _categories() => [
      FinanceCategory(uuid: 'food', name: '餐饮', icon: '🍜'),
      FinanceCategory(uuid: 'home', name: '住房', icon: '🏠'),
      FinanceCategory(uuid: 'archived', name: '旧分类', isArchived: true),
      FinanceCategory(
          uuid: 'salary', name: '工资', type: FinanceCategoryType.income),
    ];

FinanceRecurringRule _rule({String uuid = 'rent', bool enabled = true}) =>
    FinanceRecurringRule(
      uuid: uuid,
      name: enabled ? '每月房租' : '暂停的会员',
      amountMinor: 250000,
      categoryUuid: 'home',
      startDate: '2026-01-01',
      dayOfMonth: 15,
      isEnabled: enabled,
    );

FinanceEntryTemplate _template() => FinanceEntryTemplate(
      uuid: 'breakfast',
      name: '工作日早餐',
      amountMinor: 1800,
      categoryUuid: 'food',
      useCount: 5,
    );

Future<void> _pump(
  WidgetTester tester,
  Widget body, {
  Size size = const Size(390, 844),
  double scale = 1,
  Brightness brightness = Brightness.light,
  double keyboard = 0,
  bool isScreen = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal, brightness: brightness)),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          viewInsets: EdgeInsets.only(bottom: keyboard)),
      child: child!,
    ),
    home: isScreen ? body : Scaffold(body: body),
  ));
  await tester.pumpAndSettle();
}

FinanceAutomationManager _manager({
  Future<void> Function(FinanceRecurringRule, bool)? onToggle,
  Future<void> Function(FinanceRecurringRule)? onEdit,
  Future<void> Function(FinanceEntryTemplate)? onUse,
  Future<bool> Function()? onAdd,
}) =>
    FinanceAutomationManager(
      rules: [
        _rule(),
        _rule(uuid: 'paused', enabled: false),
        _rule(uuid: 'deleted')..isDeleted = true
      ],
      templates: [_template()],
      categories: _categories(),
      paymentMethods: const [],
      onAddRule: onAdd ?? () async => false,
      onAddTemplate: () async => false,
      onEditRule: onEdit ?? (_) async {},
      onToggleRule: onToggle ?? (_, __) async {},
      onDeleteRule: (_) async {},
      onEditTemplate: (_) async {},
      onUseTemplate: onUse ?? (_) async {},
      onDeleteTemplate: (_) async {},
    );

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _key(String key) => find.byKey(ValueKey(key));
Finder _textField(String key) =>
    find.descendant(of: _key(key), matching: find.byType(TextField));

Future<void> _openEditor(WidgetTester tester, Widget editor,
    {Size size = const Size(390, 844),
    double scale = 1,
    double keyboard = 0}) async {
  await _pump(
      tester,
      Builder(
          builder: (context) => TextButton(
                onPressed: () =>
                    showDialog<bool>(context: context, builder: (_) => editor),
                child: const Text('打开编辑'),
              )),
      size: size,
      scale: scale,
      keyboard: keyboard);
  await _tap(tester, find.text('打开编辑'));
}

Future<void> _scrollThrough(WidgetTester tester, {int times = 8}) async {
  for (var i = 0; i < times; i++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }
}

void main() {
  testWidgets('周期账单与模板分开，支持状态和分类关键词搜索', (tester) async {
    await _pump(tester, _manager());
    expect(_key('finance-automation-rule-rent'), findsOneWidget);
    expect(_key('finance-automation-template-breakfast'), findsNothing);
    expect(_key('finance-automation-rule-deleted'), findsNothing);
    await _tap(tester, _key('finance-automation-filter-paused'));
    expect(_key('finance-automation-rule-rent'), findsNothing);
    expect(_key('finance-automation-rule-paused'), findsOneWidget);
    await _tap(tester, _key('finance-automation-tab-templates'));
    expect(_key('finance-automation-template-breakfast'), findsOneWidget);
    await tester.enterText(_key('finance-automation-search'), '餐饮');
    await tester.pumpAndSettle();
    expect(_key('finance-automation-template-breakfast'), findsOneWidget);
    await tester.enterText(_key('finance-automation-search'), '不存在');
    await tester.pumpAndSettle();
    expect(find.text('没有找到匹配项目'), findsOneWidget);
    await _tap(tester, find.text('清除筛选'));
    expect(_key('finance-automation-template-breakfast'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('编辑、暂停与记一笔调用对应项目，保存新增后清除旧筛选', (tester) async {
    String? edited;
    String? used;
    bool? enabled;
    await _pump(
        tester,
        _manager(
          onEdit: (rule) async => edited = rule.uuid,
          onToggle: (_, value) async => enabled = value,
          onUse: (template) async => used = template.uuid,
          onAdd: () async => true,
        ));
    await _tap(tester, _key('finance-automation-edit-rent'));
    expect(edited, 'rent');
    await _tap(tester, _key('finance-automation-toggle-rent'));
    expect(enabled, false);
    await _tap(tester, _key('finance-automation-tab-templates'));
    await _tap(tester, _key('finance-automation-use-breakfast'));
    expect(used, 'breakfast');
    await _tap(tester, _key('finance-automation-tab-rules'));
    await tester.enterText(_key('finance-automation-search'), '不存在');
    await tester.pumpAndSettle();
    await _tap(tester, _key('finance-automation-add'));
    expect(_key('finance-automation-rule-rent'), findsOneWidget);
  });

  testWidgets('周期规则编辑保留归档分类、同步版本和生成进度，不修改原对象', (tester) async {
    final rule = _rule()
      ..categoryUuid = 'archived'
      ..lastGeneratedPeriod = '2026-08'
      ..version = 8
      ..deviceId = 'test-device'
      ..isEnabled = false;
    FinanceRecurringRule? saved;
    await _openEditor(
        tester,
        FinanceAutomationEditor.rule(
          rule: rule,
          categories: _categories(),
          paymentMethods: const [],
          onSave: (value) async => saved = value,
        ));
    expect(find.textContaining('旧分类'), findsWidgets);
    await tester.enterText(_textField('finance-automation-name'), '新房租名称');
    await _tap(tester, _key('finance-automation-save'));
    expect(saved?.name, '新房租名称');
    expect(saved?.categoryUuid, 'archived');
    expect(saved?.lastGeneratedPeriod, '2026-08');
    expect(saved?.version, 9);
    expect(saved?.deviceId, 'test-device');
    expect(saved?.isEnabled, false);
    expect(rule.name, '每月房租');
    expect(rule.version, 8);
    expect(tester.takeException(), isNull);
  });

  testWidgets('切换收支类型清除不匹配分类，保留模板使用次数', (tester) async {
    final template = _template()..lastUsedAt = 123456;
    FinanceEntryTemplate? saved;
    await _openEditor(
        tester,
        FinanceAutomationEditor.template(
          template: template,
          categories: _categories(),
          paymentMethods: const [],
          onSave: (value) async => saved = value,
        ));
    await _tap(tester, _key('finance-automation-type-income'));
    await _tap(tester, _key('finance-automation-save'));
    expect(saved?.type, FinanceTransactionType.income);
    expect(saved?.categoryUuid, isNull);
    expect(saved?.useCount, 5);
    expect(saved?.lastUsedAt, 123456);
    expect(template.type, FinanceTransactionType.expense);
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存失败不丢草稿，保存进行中不能重复提交', (tester) async {
    var calls = 0;
    final pending = Completer<void>();
    await _openEditor(
        tester,
        FinanceAutomationEditor.template(
          template: _template(),
          categories: _categories(),
          paymentMethods: const [],
          onSave: (_) async {
            calls++;
            if (calls == 1) throw StateError('test save failure');
            await pending.future;
          },
        ));
    await tester.enterText(_textField('finance-automation-name'), '保留的草稿');
    await _tap(tester, _key('finance-automation-save'));
    expect(find.text('保存失败，填写的内容已保留，请重试'), findsOneWidget);
    expect(
        tester
            .widget<TextField>(_textField('finance-automation-name'))
            .controller
            ?.text,
        '保留的草稿');
    await tester.tap(_key('finance-automation-save'));
    await tester.pump();
    await tester.tap(_key('finance-automation-save'));
    await tester.pump();
    expect(calls, 2);
    expect(
        tester.widget<FilledButton>(_key('finance-automation-save')).onPressed,
        isNull);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(FinanceAutomationEditor), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('周期表单校验日期范围并提供日历选择入口', (tester) async {
    var calls = 0;
    await _openEditor(
        tester,
        FinanceAutomationEditor.rule(
          rule: _rule()..frequency = FinanceRecurringFrequency.yearly,
          categories: _categories(),
          paymentMethods: const [],
          onSave: (_) async {
            calls++;
          },
        ));
    await tester.ensureVisible(_key('finance-automation-end'));
    await tester.enterText(_textField('finance-automation-end'), '2025-12-31');
    await _tap(tester, _key('finance-automation-save'));
    expect(calls, 0);
    expect(find.text('结束日期不能早于开始日期'), findsOneWidget);
    await tester.enterText(_textField('finance-automation-end'), '2026-12-31');
    await tester.ensureVisible(_key('finance-automation-month'));
    await tester.enterText(_textField('finance-automation-month'), '13');
    await _tap(tester, _key('finance-automation-save'));
    expect(calls, 0);
    expect(find.text('请输入 1–12 月'), findsOneWidget);
    await tester.enterText(_textField('finance-automation-month'), '12');
    await _tap(tester, find.byTooltip('选择开始日期'));
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await _tap(tester, find.text('Cancel'));
    await _tap(tester, _key('finance-automation-save'));
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('回收站按类型搜索，恢复请求防重复并显示错误', (tester) async {
    final pending = Completer<void>();
    var restores = 0;
    await _pump(
        tester,
        FinanceTrashManager(entries: [
          FinanceTrashEntry(
              uuid: 'bill',
              kind: FinanceTrashKind.transaction,
              title: '早餐账单',
              details: '2026-09-01 · 备注',
              amountLabel: '支出',
              amountMinor: 1800,
              onRestore: () async {
                restores++;
                await pending.future;
              }),
          FinanceTrashEntry(
              uuid: 'budget',
              kind: FinanceTrashKind.budget,
              title: '餐饮预算',
              details: '2026-09',
              amountLabel: '预算额度',
              amountMinor: 150000,
              onRestore: () async {
                throw StateError('预算冲突');
              }),
        ]));
    await _tap(tester, _key('finance-trash-filter-budget'));
    expect(_key('finance-trash-item-transaction-bill'), findsNothing);
    await _tap(tester, _key('finance-trash-restore-budget-budget'));
    expect(find.textContaining('预算冲突'), findsOneWidget);
    await _tap(tester, _key('finance-trash-filter-all'));
    await tester.enterText(_key('finance-trash-search'), '早餐');
    await tester.pumpAndSettle();
    expect(_key('finance-trash-item-budget-budget'), findsNothing);
    await tester.ensureVisible(_key('finance-trash-restore-transaction-bill'));
    await tester.tap(_key('finance-trash-restore-transaction-bill'));
    await tester.pump();
    await tester.tap(_key('finance-trash-restore-transaction-bill'));
    await tester.pump();
    expect(restores, 1);
    pending.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('管理页在窄屏大字体深色模式与宽屏均无溢出', (tester) async {
    await _pump(tester, _manager(),
        size: const Size(320, 740), scale: 2, brightness: Brightness.dark);
    expect(tester.takeException(), isNull);
    await _scrollThrough(tester);
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await _tap(tester, _key('finance-automation-tab-templates'));
    await _scrollThrough(tester);
    await _pump(tester, _manager(), size: const Size(1280, 900));
    expect(tester.takeException(), isNull);
    await _pump(
        tester,
        FinanceTrashManager(entries: [
          for (final kind in FinanceTrashKind.values)
            FinanceTrashEntry(
                uuid: kind.name,
                kind: kind,
                title: '一条名称较长的已删除记录',
                details: '2026-09-01 · 这是需要保留的备注信息',
                amountLabel: kind.label,
                amountMinor: 123456789,
                onRestore: () async {}),
        ]),
        size: const Size(320, 740),
        scale: 2,
        brightness: Brightness.dark);
    await _scrollThrough(tester, times: 16);
  });

  testWidgets('编辑对话框在小屏键盘弹出时仍能保存、取消', (tester) async {
    await _openEditor(
        tester,
        FinanceAutomationEditor.rule(
          rule: _rule(),
          categories: _categories(),
          paymentMethods: const [],
          onSave: (_) async {},
        ),
        size: const Size(320, 690),
        scale: 1.6,
        keyboard: 260);
    expect(tester.takeException(), isNull);
    expect(_key('finance-automation-save').hitTestable(), findsOneWidget);
    await _scrollThrough(tester, times: 15);
    await _tap(tester, find.text('取消'));
    expect(find.byType(FinanceAutomationEditor), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('贷款表单预览和固定保存栏适配键盘与大字体', (tester) async {
    final loan = FinanceLoan(
        uuid: 'preview',
        name: '电脑分期',
        principalMinor: 1200000,
        annualInterestRateBps: 450,
        termMonths: 12,
        startDate: '2026-09-01',
        repaymentDay: 15);
    await _pump(tester, FinanceLoanEntryScreen(loan: loan),
        isScreen: true,
        size: const Size(320, 740),
        scale: 2,
        brightness: Brightness.dark,
        keyboard: 240);
    expect(find.text('保存贷款').hitTestable(), findsOneWidget);
    await _scrollThrough(tester, times: 16);
    expect(tester.takeException(), isNull);
    await _pump(tester, FinanceLoanEntryScreen(loan: loan),
        isScreen: true, size: const Size(1200, 1000));
    await tester.ensureVisible(_key('finance-loan-preview'));
    expect(find.text('首期应还'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
