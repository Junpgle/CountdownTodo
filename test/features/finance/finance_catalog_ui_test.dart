import 'dart:async';

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/widgets/finance_catalog_editor.dart';
import 'package:countdown_todo/features/finance/widgets/finance_catalog_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<FinanceCategory> _categories() => [
      FinanceCategory(uuid: 'food', name: '餐饮', icon: '🍜', isSystem: true),
      FinanceCategory(uuid: 'coffee', name: '咖啡', icon: '☕'),
      FinanceCategory(uuid: 'archived', name: '旧分类', isArchived: true),
      FinanceCategory(uuid: 'deleted', name: '已删除分类', isDeleted: true),
      FinanceCategory(
          uuid: 'salary',
          name: '工资',
          type: FinanceCategoryType.income,
          isSystem: true),
    ];

const _searchKey = ValueKey('finance-catalog-search');
const _nameKey = ValueKey('finance-catalog-name');
const _saveKey = ValueKey('finance-catalog-save');

Future<void> _pumpCatalog(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
  Brightness brightness = Brightness.light,
  List<FinanceCategory>? categories,
  Future<FinanceCategory?> Function(FinanceCategoryType)? onAdd,
  Future<void> Function(FinanceCategory)? onEdit,
  Future<void> Function(FinanceCategory)? onArchive,
  Future<void> Function(FinanceCategory)? onRestore,
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
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: FinanceCatalogManager(
          categories: categories ?? _categories(),
          paymentMethods: [
            FinancePaymentMethod(
                uuid: 'wechat', name: '微信', icon: '💬', isSystem: true),
            FinancePaymentMethod(uuid: 'card', name: '日常银行卡', icon: '💳'),
          ],
          onAddCategory: onAdd ?? (_) async => null,
          onAddPaymentMethod: () async => false,
          onEditCategory: onEdit ?? (_) async {},
          onArchiveCategory: onArchive ?? (_) async {},
          onRestoreCategory: onRestore ?? (_) async {},
          onEditPaymentMethod: (_) async {},
          onArchivePaymentMethod: (_) async {},
          onRestorePaymentMethod: (_) async {},
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _openEditor(
  WidgetTester tester, {
  required Future<void> Function(FinanceCatalogDraft) onSave,
  FinanceCategoryType? type = FinanceCategoryType.expense,
  bool editing = false,
  String name = '',
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: Builder(
          builder: (context) => TextButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) => FinanceCatalogEditor(
                    initialName: name,
                    initialIcon: '📦',
                    categoryType: type,
                    isEditing: editing,
                    onSave: onSave,
                  ),
                ),
                child: const Text('打开编辑'),
              )),
    ),
  ));
  await tester.tap(find.text('打开编辑'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('分类按收支分开，搜索与归档筛选不会显示已删除项目', (tester) async {
    String? restored;
    await _pumpCatalog(tester,
        onRestore: (category) async => restored = category.uuid);
    expect(find.text('咖啡'), findsOneWidget);
    expect(find.text('餐饮'), findsOneWidget);
    expect(find.text('工资'), findsNothing);
    expect(find.text('旧分类'), findsNothing);
    expect(find.text('已删除分类'), findsNothing);

    await tester.enterText(find.byKey(_searchKey), '咖啡');
    await tester.pumpAndSettle();
    expect(find.text('餐饮'), findsNothing);
    await tester.tap(find.byTooltip('清空搜索'));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('finance-catalog-filter-archived')));
    await tester.pumpAndSettle();
    expect(find.text('旧分类'), findsOneWidget);
    expect(find.text('咖啡'), findsNothing);
    await tester.tap(find.byTooltip('恢复旧分类'));
    await tester.pumpAndSettle();
    expect(restored, 'archived');

    await tester.tap(find.text('收入分类'));
    await tester.pumpAndSettle();
    expect(find.text('工资'), findsOneWidget);
    expect(find.text('旧分类'), findsNothing);
    await tester.ensureVisible(find.text('付款方式'));
    await tester.tap(find.text('付款方式'));
    await tester.pumpAndSettle();
    expect(find.text('日常银行卡'), findsOneWidget);
    expect(find.text('微信'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('自定义卡片直接编辑并支持归档，系统项目不提供无效操作', (tester) async {
    String? edited;
    String? archived;
    await _pumpCatalog(
      tester,
      onEdit: (category) async => edited = category.uuid,
      onArchive: (category) async => archived = category.uuid,
    );
    final system = find.byKey(const ValueKey('finance-catalog-item-food'));
    expect(
        find.descendant(
            of: system, matching: find.byType(PopupMenuButton<String>)),
        findsNothing);
    await tester.tap(find.text('餐饮'));
    await tester.pumpAndSettle();
    expect(edited, isNull);
    await tester.tap(find.text('咖啡'));
    await tester.pumpAndSettle();
    expect(edited, 'coffee');
    await tester.tap(find.byTooltip('管理咖啡'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('归档'));
    await tester.pumpAndSettle();
    expect(archived, 'coffee');
  });

  testWidgets('新增默认使用当前分类类型，保存后自动显示新增项目', (tester) async {
    final categories = _categories();
    FinanceCategoryType? requested;
    await _pumpCatalog(tester, categories: categories, onAdd: (type) async {
      requested = type;
      final category = FinanceCategory(uuid: 'new', name: '新分类');
      categories.add(category);
      return category;
    });
    await tester.tap(find.text('收入分类'));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('finance-catalog-filter-archived')));
    await tester.enterText(find.byKey(_searchKey), '找不到');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('finance-catalog-add')));
    await tester.pumpAndSettle();
    expect(requested, FinanceCategoryType.income);
    expect(find.text('新分类'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(_searchKey)).controller!.text,
        isEmpty);
    expect(
        tester
            .widget<ChoiceChip>(
                find.byKey(const ValueKey('finance-catalog-filter-active')))
            .selected,
        isTrue);
  });

  testWidgets('图标选择和名称校验有效，失败保留输入并阻止重复保存', (tester) async {
    var attempts = 0;
    FinanceCatalogDraft? saved;
    final firstSave = Completer<void>();
    await _openEditor(tester, onSave: (draft) async {
      attempts++;
      saved = draft;
      if (attempts == 1) await firstSave.future;
    });
    await tester.tap(find.byKey(_saveKey));
    await tester.pumpAndSettle();
    expect(find.text('请填写分类名称'), findsOneWidget);
    expect(attempts, 0);

    await tester.enterText(find.byKey(_nameKey), '  宠物用品  ');
    await tester.ensureVisible(find.byKey(const ValueKey('finance-icon-🐾')));
    await tester.tap(find.byKey(const ValueKey('finance-icon-🐾')));
    await tester.tap(find.byKey(_saveKey));
    await tester.pump();
    expect(attempts, 1);
    expect(tester.widget<FilledButton>(find.byKey(_saveKey)).onPressed, isNull);
    expect(find.byType(FinanceCatalogEditor), findsOneWidget);
    expect(saved?.name, '宠物用品');
    expect(saved?.icon, '🐾');
    expect(saved?.type, FinanceCategoryType.expense);

    firstSave.completeError(StateError('storage unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('保存失败，填写的内容已保留，请重试'), findsOneWidget);
    expect(tester.widget<TextFormField>(find.byKey(_nameKey)).controller!.text,
        '  宠物用品  ');
    await tester.tap(find.byKey(_saveKey));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byType(FinanceCatalogEditor), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('编辑已有分类时类型固定，取消后表单安全销毁', (tester) async {
    await _openEditor(tester,
        editing: true,
        name: '兼职',
        type: FinanceCategoryType.income,
        onSave: (_) async {});
    for (final chip in tester.widgetList<ChoiceChip>(find.byType(ChoiceChip))) {
      expect(chip.onSelected, isNull);
    }
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(FinanceCatalogEditor), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('小屏深色大字体和桌面布局不溢出', (tester) async {
    await _pumpCatalog(tester,
        size: const Size(320, 600), textScale: 2, brightness: Brightness.dark);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('付款方式'));
    await tester.tap(find.text('付款方式'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('小屏键盘弹出时仍可滚动编辑并使用底部操作', (tester) async {
    await _openEditor(tester,
        size: const Size(320, 640),
        textScale: 1.6,
        type: null,
        onSave: (_) async {});
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(_nameKey));
    await tester.enterText(find.byKey(_nameKey), '日常银行卡');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(_saveKey));
    await tester.pumpAndSettle();
    expect(find.byType(FinanceCatalogEditor), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
